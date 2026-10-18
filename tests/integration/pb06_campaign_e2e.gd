## PB-06：沿用 INT-18A Boot/身份/房间/结算驱动，正式关卡使用 Plan B 棋子 PK。
extends "res://tests/integration/int18a_campaign_e2e.gd"

const TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const CAMPAIGN_PLAYER_UNIT_TARGET: int = 12


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failed = true
	push_error("PB06_FAIL " + message)
	get_tree().quit(1)


func _run() -> void:
	get_tree().current_scene = null
	SceneRouter.game_scene_override = null
	_media = ProjectSettings.globalize_path("res://.godot/pb06/media")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--pb06-media="):
			_media = argument.trim_prefix("--pb06-media=")
	DirAccess.make_dir_recursive_absolute(_media)
	print("PB06_USER_DIR=", OS.get_user_data_dir())
	_check(not SaveManager.has_save(), "PB-06 验收使用隔离存档目录")
	_check(get_tree().change_scene_to_file("res://core/boot/boot.tscn") == OK, "启动正式 Boot")
	await _wait(func(): return get_tree().current_scene is ComicPlayer, "首次开场漫画")
	var comic: ComicPlayer = get_tree().current_scene
	_check(comic.get_playback_control().panel_count == 19, "开场六幕19个播放节点")
	var acts: Dictionary = {}
	while is_instance_valid(comic) and get_tree().current_scene == comic:
		var panel := comic.get_playback_control().current_panel_number
		if panel in [1, 5, 9, 12, 16, 19]:
			await get_tree().create_timer(0.22).timeout
			await _capture("intro_%02d" % panel)
		acts[panel] = true
		var event := InputEventKey.new()
		event.keycode = KEY_SPACE
		event.pressed = true
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames()
	_check(acts.size() == 19 and SettingsManager.opening_comic_seen, "开场逐格播放并保存首次记录")
	get_tree().current_scene.get_node("%StartButton").pressed.emit()
	await _frames()
	var setup = get_tree().current_scene
	setup._streamer_name_input.text = "PB06 TEST_ONLY"
	setup._streamer_continue.pressed.emit()
	setup._player_presentation_page.get_node("Center/Panel/Content/Action").pressed.emit()
	_check(setup._selection._buttons.size() == 12, "正式十二身份可用")
	await _capture("identity_12")
	setup._selection._buttons[0].pressed.emit()
	setup._selection._buttons[0].pressed.emit()
	setup._selection.get_node("%NextButton").pressed.emit()
	setup._room_transition_action.pressed.emit()
	setup._fan_group_name_input.text = "PB06 TEST_ONLY fans"
	setup._confirm_button.pressed.emit()
	await _frames()
	await _room_start(1)

	for order: int in range(1, 5):
		var sandbox = get_tree().current_scene
		var flow: BattleAttemptFlow = sandbox.get_battle_attempt_flow()
		var host: PlanBBattleHost = sandbox.get_plan_b_battle_host()
		var catalog: Object = sandbox.get_plan_b_content_catalog()
		var ui: Control = sandbox.get_plan_b_battle_ui()
		var level: LevelProfile = flow.get_current_level_profile()
		_check(host != null and catalog != null and ui != null, "正式 Sandbox 组合 A/B/C/D")
		_check(level.level_order == order, "正式关卡顺序%d" % order)
		_check(level.streamer_id == ["alien", "kiwi", "frog", "fox"][order - 1], "四关主播稳定 ID")
		var current_context: Dictionary = catalog.call("get_current_level_context")
		var opponent_config: Dictionary = catalog.call("get_opponent_config")
		_check(str(current_context.get("level_id", "")) == level.level_id, "C 当前词池属于本关")
		_check(str(opponent_config.get("streamer_id", "")) == level.streamer_id, "C 对手配置属于本关")
		_check(ui.call("get_board_world_bounds") == Rect2(Vector2(448.0, 72.0), Vector2(1024.0, 828.0)),
			"D棋盘 Rect2 与正式布局一致")
		var initial_counts: Dictionary = host.get_faction_counts()
		_check(int(initial_counts.get("player", 0)) == 0, "开局没有玩家信徒")
		_check(int(initial_counts.get("opponent", 0)) == 2, "A 用两名费米初始棋子播种")
		_check(int(initial_counts.get("neutral", 0)) == 76, "开局保留76名中立观众")
		_check(host.get_used_word_ids().size() == 2, "两条开局费米词进入 A 已用集合")
		_check(host.get_player_hand().size() == 3, "A 按 C 候选初始化三个固定话语槽")
		print("PB06_LEVEL_BEGIN ", level.level_id, " ", level.streamer_id)
		await _capture("level_%d_start" % order)

		host.opponent_auto_publish_enabled = false
		host.opponent_counterattack_enabled = false
		host.player_publish_cooldown_seconds = 0.0
		host.opponent_publish_cooldown_seconds = 0.0
		if order == 1:
			host.update_pk(5000.0)
			await _wait(func(): return not flow.is_normal_combat_active(), "B人口差触发首关PK失败")
			await _wait(func(): return sandbox.get_node("%FailureOverlay").visible, "失败重试界面")
			_check(SaveManager.data.get_committed_normal_hit_history().is_empty(), "失败尝试没有提交普通话语历史")
			await _capture("level_1_failure")
			ui.call("request_restart")
			await _wait(
				func(): return flow.is_normal_combat_active() and host.get_battle_state() == &"running",
				"失败后由正式UI重开当前关"
			)
			var restarted_counts: Dictionary = host.get_faction_counts()
			_check(int(restarted_counts.get("player", 0)) == 0 and int(restarted_counts.get("opponent", 0)) == 2,
				"重开重置 B 人口与费米播种")
			_check(host.get_player_hand().size() == 3, "重开重置 A 的三个话语槽")

		await _publish_first_word_with_pointer(sandbox)
		var player_count := await _fill_player_population(sandbox, CAMPAIGN_PLAYER_UNIT_TARGET)
		_check(player_count >= CAMPAIGN_PLAYER_UNIT_TARGET, "A发表事务通过B真实播种玩家棋子")
		var campaign_counts: Dictionary = host.get_faction_counts()
		_check(int(campaign_counts.get("player", 0)) > int(campaign_counts.get("opponent", 0)),
			"PK优势来自 B 的真实玩家人数")
		_check(flow.get_hit_resolution().get_normal_hit_history().size() >= 3,
			"Plan B 成功发表进入旧普通历史与神谕候选池")
		var player_tendencies: Dictionary = {}
		for record: Dictionary in flow.get_hit_resolution().get_normal_hit_history():
			player_tendencies[str(record.get("tendency", ""))] = true
		_check(player_tendencies.has("orthodox") and player_tendencies.has("heretical") and player_tendencies.has("absurd"),
			"原始话语倾向映射进入旧结算候选")
		ui.call("clear_dialogue_bubbles", -1)

		await _advance_to_tier(sandbox, 2)
		_check(host.get_current_tier() == flow.get_current_tier(), "Plan B PK 与旧 CombatStage 共用Tier来源")
		await _capture("level_%d_tier2" % order)
		await _pause_check(sandbox)
		var paused_counts: Dictionary = host.get_faction_counts()
		await get_tree().create_timer(0.2).timeout
		_check(host.get_faction_counts() == paused_counts, "SceneTree暂停冻结 B 模拟与PK")
		host.update_pk(1000.0)
		await _wait(
			func(): return not flow.is_normal_combat_active() and host.get_battle_state() == &"ended",
			"B人口优势推送A Host到100%",
			30.0
		)
		var phases: ContradictionOracleFlow = sandbox.get_contradiction_oracle_flow()
		await _wait(func(): return phases.is_contradiction_active(), "PA-12后进入原六句矛盾阶段")
		await _capture("level_%d_paradox" % order)
		var broken: bool = order != 2
		var chosen: LevelContradiction = level.true_contradictions[0] if broken else level.false_contradictions[0]
		var target: BarrageView
		for child: Node in flow.get_barrage_area().get_children():
			if child is BarrageView and not child.is_queued_for_deletion():
				child.set_process(false)
				if child.runtime_record.original_sentence_id == chosen.original_sentence_id:
					target = child
				else:
					child.position = Vector2(-3000.0, -3000.0)
		_check(target != null, "本关正式矛盾原句已生成")
		if target != null:
			target.position = Vector2(120.0, 300.0)
			await _shoot(sandbox, target, order == 1)
		var contradiction: ContradictionBreakSystem = phases.get_contradiction_system()
		_check(contradiction.get_outcome() == (ContradictionBreakSystem.Outcome.BREAKTHROUGH if broken else ContradictionBreakSystem.Outcome.NOT_BROKEN),
			"矛盾阶段沿用旧单发真/假判定")
		if order == 1:
			_check(SaveManager.data.completed_tutorial_step_ids.size() == 3, "旧三步蓄力教程转接到真实矛盾射击")
		_check(not sandbox.get_rest_result_view()._overlay.visible and phases.get_oracle_session() == null,
			"PA-17完成前下游界面保持关闭")
		await _capture("level_%d_pa17" % order)
		if broken:
			await _wait(func(): return phases.get_oracle_session() != null, "复读演出后进入原神谕", 90.0)
			await _capture("level_%d_oracle" % order)
			_check(phases.get_selection_timer().get_remaining_seconds() > 9.0, "神谕计时从旧演出后开始")
			var oracle_display: Control = sandbox.get_oracle_candidate_display()
			await _shoot(sandbox, oracle_display.get_child(0))
		await _wait(func(): return sandbox.get_rest_result_view()._overlay.visible, "正式Rest显示", 90.0)
		var result: RestSession = phases.get_result()
		_check(result != null and result.is_open(), "原流程打开同一Rest结果对象")
		_check(result.get_result_snapshot()["result_kind"] == ("breakthrough_oracle_complete" if broken else "pk_win_unbroken"),
			"成功击破与未击破仍沿用旧结算")
		if broken and sandbox.loser_card_catalog.find_profile(StringName(level.streamer_id)) != null:
			_expected_cards += 1
		var before := _facts()
		contradiction.outcome_locked.emit(contradiction.get_outcome())
		if broken:
			_check(not phases.get_confirmation_state().confirm_selection(
				level.level_id, phases.get_confirmation_state().get_confirmed_selection(level.level_id)
			), "重复神谕确认被拒绝")
		_check(_facts() == before, "重复结算事实不重复发奖")
		await _capture("level_%d_rest" % order)
		sandbox.get_rest_result_view()._continue_button.pressed.emit()
		sandbox.get_rest_result_view()._continue_button.pressed.emit()
		await _frames()
		if order < 4:
			await _wait(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("start_live"), "Rest返回房间")
			_check(SaveManager.data.next_normal_level_order == order + 1, "重复继续只推进一关")
			_check(SaveManager.load_game() == OK and _facts() == before, "普通关成果在真实存档恢复")
			SceneRouter.goto_main_menu()
			await _frames()
			get_tree().current_scene._continue_button.pressed.emit()
			await _frames()
			await _room_start(order + 1)
		else:
			await _wait(func(): return sandbox.get_divine_descent_flow() != null, "四关后创建原神降临流程")
			var divine: DivineDescentFlow = sandbox.get_divine_descent_flow()
			divine.completed.connect(func(_ending: EndingSession): _result_events += 1)
			_check(not divine.get_session().should_enter_empty_ending(), "正式普通话语历史进入非空终局")
			await _capture("divine_descent")
			await _wait(func(): return divine.get_spread().is_sentence_locked(), "原神降临衰减后锁句", 30.0)
			await _capture("divine_locked")
			await _wait(func(): return get_tree().current_scene is EndingPage, "正式Ending", 40.0)
	_check(_result_events == 1, "Ending只接收一次")
	_check(SaveManager.data.live_session.fan_count == 480, "四关正式PK胜利粉丝结算为480")
	_check(SaveManager.data.loser_card_data.acquired_streamer_ids.size() == _expected_cards,
		"败者卡仅按正式目录发放")
	_check(not SaveManager.data.loser_card_data.acquired_streamer_ids.has(&"kiwi"), "未击破关卡不发败者卡")
	_check(SaveManager.data.assimilation_data.defeated_streamer_ids.size() == 3, "三场真实击破各提交一次")
	await _capture("ending")
	var ending: Dictionary = get_tree().current_scene._display_data.duplicate(true)
	SceneRouter.goto_main_menu()
	await _frames()
	get_tree().current_scene._continue_button.pressed.emit()
	await _wait(func(): return get_tree().current_scene is EndingPage, "存档终局回看")
	_check(get_tree().current_scene._display_data == ending, "终局快照读回不重复发奖")
	print("PB06_E2E_RESULT checks=", _checks, " failed=", _failed, " ending_events=", _result_events, " facts=", _facts())
	get_tree().quit(1 if _failed else 0)


func _publish_first_word_with_pointer(sandbox) -> void:
	var host: PlanBBattleHost = sandbox.get_plan_b_battle_host()
	var catalog: Object = sandbox.get_plan_b_content_catalog()
	var ui: Control = sandbox.get_plan_b_battle_ui()
	var hand: Array[Dictionary] = host.get_player_hand()
	if hand.is_empty():
		_check(false, "C提供的手牌不能为空")
		return
	var word_id: String = str(hand[0].get("word_id", ""))
	var card_button := ui.find_child("WordCard1", true, false) as Control
	var spawn_position: Vector2 = ui.call("get_board_world_bounds").get_center()
	_check(card_button != null and not word_id.is_empty(), "真实UI手牌和棋盘落点可点击")
	if card_button == null:
		return
	await _click_canvas_point(card_button.get_global_rect().get_center())
	await _click_canvas_point(spawn_position)
	await _wait(func(): return host.get_used_word_ids().has(word_id), "D点击事件经A Host成功播种")
	_check(int(host.get_faction_counts().get("player", 0)) >= 2, "成功发表按强度创建完整玩家棋子批次")
	_check(host.get_player_hand().size() == 3, "成功发表保留固定三槽")


func _fill_player_population(sandbox, target_count: int) -> int:
	var host: PlanBBattleHost = sandbox.get_plan_b_battle_host()
	var catalog: Object = sandbox.get_plan_b_content_catalog()
	var ui: Control = sandbox.get_plan_b_battle_ui()
	var seen_tendencies: Dictionary = {}
	var maximum_publishes: int = target_count + 16
	var publishes: int = 0
	while publishes < maximum_publishes:
		var counts: Dictionary = host.get_faction_counts()
		var player_count: int = int(counts.get("player", 0))
		if player_count >= target_count and seen_tendencies.size() >= 3:
			break
		var hand: Array[Dictionary] = host.get_player_hand()
		if hand.is_empty():
			break
		var selected_index: int = -1
		var available_slot_states: Array[Dictionary] = host.get_player_slot_states()
		for hand_index: int in range(hand.size()):
			var candidate_id: String = str(hand[hand_index].get("word_id", ""))
			if candidate_id.is_empty() or hand_index >= available_slot_states.size():
				continue
			if not bool(available_slot_states[hand_index].get("available", false)):
				continue
			var tendency: String = str(hand[hand_index].get("tendency", ""))
			if not tendency.is_empty() and not seen_tendencies.has(tendency):
				selected_index = hand_index
				break
		if selected_index < 0:
			for hand_index: int in range(hand.size()):
				if (hand_index < available_slot_states.size()
						and bool(available_slot_states[hand_index].get("available", false))
						and not str(hand[hand_index].get("word_id", "")).is_empty()):
					selected_index = hand_index
					break
		if selected_index < 0:
			var wait_seconds: float = 5.0
			var has_cooling_slot: bool = false
			for state: Dictionary in available_slot_states:
				var remaining: float = float(state.get("remaining", 0.0))
				if remaining > 0.0:
					has_cooling_slot = true
					wait_seconds = minf(wait_seconds, remaining)
			if not has_cooling_slot:
				break
			await get_tree().create_timer(wait_seconds + 0.1).timeout
			continue
		var definition: Dictionary = hand[selected_index]
		var word_id: String = str(definition.get("word_id", ""))
		var spawn_position: Vector2 = ui.call("get_board_world_bounds").get_center()
		var slot_id: int = int(definition.get("slot_id", selected_index))
		if word_id.is_empty():
			break
		var result: Dictionary = host.publish_word(
			"player", word_id, spawn_position, slot_id
		)
		_check(bool(result.get("ok", false)), "A唯一发表入口成功播种: " + word_id)
		if not bool(result.get("ok", false)):
			break
		seen_tendencies[str(definition.get("tendency", ""))] = true
		ui.call("resolve_publish_request", slot_id, word_id, spawn_position, result)
		publishes += 1
	var final_counts: Dictionary = host.get_faction_counts()
	_check(int(final_counts.get("player", 0)) >= target_count, "测试夹具以B真实种子构造玩家人口优势")
	_check(seen_tendencies.has("orthodox") and seen_tendencies.has("heretical") and seen_tendencies.has("absurd"),
		"本场玩家话语覆盖旧三项倾向")
	ui.call("clear_dialogue_bubbles", -1)
	return int(final_counts.get("player", 0))


func _advance_to_tier(sandbox, target_tier: int) -> void:
	var host: PlanBBattleHost = sandbox.get_plan_b_battle_host()
	var flow: BattleAttemptFlow = sandbox.get_battle_attempt_flow()
	var tier_catalog: CombatStageTierCatalog = TIER_CATALOG
	while flow.get_current_tier() < target_tier:
		var previous_tier: int = flow.get_current_tier()
		var config: CombatStageTierConfig = tier_catalog.get_tier_config(previous_tier)
		var counts: Dictionary = host.get_faction_counts()
		var total: int = int(counts.get("player", 0)) + int(counts.get("opponent", 0)) + int(counts.get("neutral", 0))
		var lead: int = int(counts.get("player", 0)) - int(counts.get("opponent", 0))
		var rate: float = host.pk_rate_pp_per_second * float(lead) / float(total)
		_check(config != null and rate > 0.0, "真实人数差可推进Tier")
		if config == null or rate <= 0.0:
			return
		var target_pk: float = float(config.upgrade_threshold) * 100.0 + 0.1
		var delta: float = maxf(0.1, (target_pk - host.get_pk()) / rate)
		host.update_pk(delta)
		await _wait(
			func(): return flow.get_current_tier() > previous_tier and host.get_battle_state() == &"running",
			"旧CombatStage升档与D突破演出完成", 30.0
		)
		_check(host.get_current_tier() == flow.get_current_tier(), "Host Tier 显示复用旧 CombatStage 来源")


func _click_canvas_point(canvas_position: Vector2) -> void:
	var screen_position: Vector2 = get_viewport().get_final_transform() * canvas_position
	var motion := InputEventMouseMotion.new()
	motion.position = screen_position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frames()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = screen_position
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames()
