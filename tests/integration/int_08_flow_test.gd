extends Node

const TEST_SANDBOX: PackedScene = preload("res://tests/integration/int_04_test_only_sandbox.tscn")
var _sandbox
var _rest_results: Array[RestSession] = []
var _errors: Array[String] = []
var _checks: int = 0
var _failed: bool = false


# TEST_ONLY 实景验证提交中途失败；组件和成果写入均使用正式实现。
func _ready() -> void:
	call_deferred("_execute")


func _execute() -> void:
	SaveManager.new_game()
	_sandbox = TEST_SANDBOX.instantiate()
	add_child(_sandbox)
	await _frames()
	var flow: ContradictionOracleFlow = _sandbox.get_contradiction_oracle_flow()
	flow.rest_ready.connect(func(result): _rest_results.append(result))
	flow.commit_failed.connect(func(reason): _errors.append(reason))
	var level: LevelProfile = _sandbox.level_catalog.profiles[0]
	var run: SaveData = SaveManager.data
	_sandbox._hit_resolution.record_normal_word_hit(level.get_normal_speech_pool()[0].original_sentence_id, "orthodox")
	run.tendency_state.record_normal_speech_tendency("orthodox", 3)
	_sandbox.debug_set_player_pk(1.0)
	await _frames()
	var system: ContradictionBreakSystem = flow.get_contradiction_system()
	_check(flow.is_contradiction_active() and system.get_remaining_shots() == 1, "公开入口启动矛盾一发窗口")
	system.register_launched_shot()
	var ids: Array[String] = [level.true_contradictions[0].original_sentence_id]
	system.resolve_shot_hit_ids(ids)
	await get_tree().create_timer(0.7).timeout
	var session: FinalOracleSession = flow.get_oracle_session()
	_check(session != null and session.is_open(), "真实静音 Timer 后进入神谕")
	# 仅破坏内存 TEST_ONLY 池权重，令圣典、历史、卡片、击败已写入后池登记失败。
	level.normal_pool_inheritance.appearance_weight = -1.0
	print("INT08 EXPECTED FAILURE BEGIN: 普通词库继承提交失败")
	_check(flow.confirm_candidate(session.get_display_candidates()[0]), "正式确认只接受一次")
	await _frames()
	_check(_errors == ["普通词库继承提交失败"] and flow.get_commit_error() == _errors[0], "流程报告实际写入拒绝")
	_check(flow.get_result() == null and _rest_results.is_empty() and _sandbox._rest_session == null, "失败未交付假 Rest 结果")
	_check(run.scripture_data.entries.size() == 1 and run.loser_card_data.acquired_streamer_ids.size() == 1
		and run.assimilation_data.defeated_streamer_ids.size() == 1, "失败保留此前合法提交成果")
	_check(run.get_committed_normal_hit_history()[0]["hit_count"] == 1 and run.tendency_state.orthodox_total == 3, "历史和倾向已经且仅提交一次")
	_check(run.assimilation_data.inherited_word_weights.is_empty() and run.assimilation_data.inherited_trait_ids.is_empty(), "失败停止后续特性写入")
	_check(not flow.confirm_candidate(session.get_display_candidates()[0]), "失败后重复确认仍拒绝")
	print("INT08 EXPECTED FAILURE END")
	level.normal_pool_inheritance.appearance_weight = 1.0
	_check(flow.commit_confirmed_rewards(), "修复配置后显式补齐奖励")
	_check(not flow.commit_confirmed_rewards(), "帧尾交接等待中重复提交拒绝")
	await _frames()
	_check(_rest_results.size() == 1 and flow.get_result() == _rest_results[0] and _sandbox._rest_session == _rest_results[0], "交付一次同一 RestSession")
	var rewards: Dictionary = flow.get_result().read_committed_rewards(run, _sandbox.level_catalog, _sandbox.loser_card_catalog)
	_check(rewards["new_scripture_entry"] != null and rewards["new_loser_card"] != null
		and not rewards["new_assimilation"].is_empty(), "Rest 只读全部已保存奖励")
	_check(run.get_committed_normal_hit_history()[0]["hit_count"] == 1 and run.tendency_state.orthodox_total == 3
		and run.scripture_data.entries.size() == 1 and run.loser_card_data.acquired_streamer_ids.size() == 1, "补齐保留历史、倾向、圣典及卡片数量")
	_check(run.assimilation_data.inherited_word_weights.size() == 1 and run.assimilation_data.inherited_trait_ids == [&"occlusion"], "继承池和白名单特性补齐一次")
	# 重开已确认同关会自动交接首份成果，无需再选择；新尝试普通暂存仍回滚。
	var original_history: Array[Dictionary] = run.get_committed_normal_hit_history()
	var original_candidate: Dictionary = session.get_confirmed_selection()
	var original_verse: int = rewards["new_scripture_entry"].verse_number
	var original_assimilation: Dictionary = run.assimilation_data.get_current_content_snapshot()
	_sandbox.restart_current_attempt()
	# 复现 review：新 HitResolution 再命中一次，旧神谕复用时不得将新暂存入账。
	_sandbox._hit_resolution.record_normal_word_hit(level.get_normal_speech_pool()[0].original_sentence_id, "orthodox")
	run.tendency_state.record_normal_speech_tendency("orthodox", 3)
	_sandbox.debug_set_player_pk(1.0)
	await _frames()
	system = flow.get_contradiction_system()
	system.register_launched_shot()
	system.resolve_shot_hit_ids(ids)
	await get_tree().create_timer(0.7).timeout
	await _frames()
	_check(_rest_results.size() == 2 and flow.get_result() != _rest_results[0], "同关重开复用首次确认并交付本次结果")
	var replay_rewards: Dictionary = flow.get_result().read_committed_rewards(run, _sandbox.level_catalog, _sandbox.loser_card_catalog)
	_check(run.get_committed_normal_hit_history() == original_history and run.tendency_state.orthodox_total == 3
		and run.tendency_state.heretical_total == 0 and run.tendency_state.absurd_total == 0
		and run.tendency_state.attempt_orthodox_total == 0
		and flow.get_oracle_session().get_confirmed_selection() == original_candidate
		and replay_rewards["new_scripture_entry"].verse_number == original_verse and run.scripture_data.entries.size() == 1
		and run.loser_card_data.acquired_streamer_ids.size() == 1
		and run.assimilation_data.get_current_content_snapshot() == original_assimilation, "重开已确认关的新普通命中未入账，Rest 保留首次成果")
	# 第二关真实窗口到期走未击破，不创建候选或奖励。
	_sandbox._rest_result_view._continue_button.pressed.emit()
	await _frames()
	_sandbox.debug_set_player_pk(1.0)
	await _frames()
	system = flow.get_contradiction_system()
	await get_tree().create_timer(10.2).timeout
	_check(system.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN
		and flow.get_result().get_result_snapshot()["result_kind"] == "pk_win_unbroken", "十秒窗口到期交付未击破 Rest")
	_check(run.scripture_data.entries.size() == 1 and run.loser_card_data.acquired_streamer_ids.size() == 1, "超时未击破无新增奖励")
	# 确认完成后同帧重开，旧帧尾 Rest 交接必须失效；已提交成果仍保留。
	_sandbox.restart_current_attempt()
	var second_level: LevelProfile = _sandbox.level_catalog.profiles[1]
	_sandbox._hit_resolution.record_normal_word_hit(second_level.get_normal_speech_pool()[0].original_sentence_id, "orthodox")
	_sandbox.debug_set_player_pk(1.0)
	await _frames()
	system = flow.get_contradiction_system()
	system.register_launched_shot()
	ids = [second_level.true_contradictions[0].original_sentence_id]
	system.resolve_shot_hit_ids(ids)
	await get_tree().create_timer(0.7).timeout
	session = flow.get_oracle_session()
	_check(flow.confirm_candidate(session.get_display_candidates()[0]), "第二关确认准备帧尾交接")
	_sandbox.restart_current_attempt()
	await _frames()
	_check(flow.get_result() == null and _sandbox._rest_session == null and _rest_results.size() == 3, "同帧重开隔离旧 Rest 交接")
	_check(run.scripture_data.entries.size() == 2 and run.loser_card_data.acquired_streamer_ids.size() == 2, "重开保留已合法提交成果")
	_sandbox.queue_free()
	await _frames()
	_check(not is_instance_valid(flow), "场景离树销毁流程")
	print("FAIL" if _failed else "PASS", " INT-08 flow checks=", _checks, " rest_ready=", _rest_results.size(), " expected_failures=", _errors.size())
	get_tree().quit(1 if _failed else 0)


# 留出帧尾结果与真实界面布局的处理时间。
func _frames() -> void:
	for index in range(4):
		await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("FAIL INT-08: " + description)
		get_tree().quit(1)
	else:
		print("INT08 OK: " + description)
