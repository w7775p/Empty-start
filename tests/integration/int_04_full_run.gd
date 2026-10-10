## INT-04：真实场景与 Timer，按钮由信号驱动，输入为合成事件；物理操作另验。
extends Node

var checks := 0
var route_count := 0
var dd_completed := 0
var emphasis_count := 0
var failed := false

func _ready() -> void:
	get_tree().create_timer(100.0).timeout.connect(func(): _check(false, "整局超时"))
	call_deferred("_execute")

# 驱动留在根节点；所有页面继续由真实 SceneRouter 替换和销毁。
func _execute() -> void:
	get_tree().current_scene = null
	SceneRouter.game_scene_override = preload("res://tests/integration/int_04_test_only_sandbox.tscn")
	get_tree().scene_changed.connect(func(): route_count += 1)
	for empty_history in [false, true]:
		print("INT04 ROUTE BEGIN empty_history=", empty_history)
		await _opening()
		var sandbox = get_tree().current_scene
		var run: SaveData = SaveManager.data
		# INT-07 只从公开流程接口观察完成事实，覆盖两路的接收与离树清理。
		var flows: Array[DivineDescentFlow] = []
		var sessions: Array[DivineDescentSession] = []
		var results: Array[EndingSession] = []
		sandbox.divine_descent_entered.connect(func(session):
			var flow: DivineDescentFlow = sandbox.get_divine_descent_flow()
			flows.append(flow)
			sessions.append(session)
			flow.completed.connect(func(result): results.append(result)))
		# 首轮真实失败再重开，本场暂存不得成为终局历史。
		if not empty_history:
			await _normal_hit(sandbox)
			sandbox.debug_set_player_pk(0.0)
			await _frames()
			_check(not sandbox._normal_combat_active, "PK 零未失败")
			sandbox.get_node("%RestartButton").pressed.emit()
			await _frames()
			_check(sandbox._normal_combat_active and run.get_committed_normal_hit_history().is_empty(), "失败重开历史污染")
		for level in range(2):
			print("INT04 LEVEL BEGIN empty_history=", empty_history, " level=", level)
			if not empty_history:
				await _normal_hit(sandbox)
			sandbox.debug_set_player_pk(1.0)
			await _frames()
			var success: bool = not empty_history and level == 0
			var profile: LevelProfile = sandbox._run_state.get_current_level_profile()
			var line: LevelContradiction = profile.true_contradictions[0] if success else profile.false_contradictions[0]
			# 弹幕由实际区域生成，真假结果必须经过真正满蓄释放。
			sandbox._barrage_area.clear_current_barrages()
			var view: BarrageView = sandbox._barrage_area.spawn_contradiction_barrage(profile, line)
			_check(view != null, "矛盾弹幕未生成")
			# 本发只测指定真假句：清场会保留生成 Timer，蓄力期间新真句会混入假句快照。
			# 停止后续批次保留已生成目标和正式十秒窗口，复读仍由流程实际推进。
			sandbox._barrage_area.stop_contradiction_generation()
			await _shoot(sandbox, view)
			var system: ContradictionBreakSystem = sandbox.get_contradiction_oracle_flow().get_contradiction_system()
			_check(system.get_outcome() == (ContradictionBreakSystem.Outcome.BREAKTHROUGH if success else ContradictionBreakSystem.Outcome.NOT_BROKEN),
				"真假结果错误 empty=%s level=%d outcome=%d remaining_shots=%d seconds=%.3f" % [empty_history, level, system.get_outcome(), system.get_remaining_shots(), system.get_remaining_seconds()])
			if success:
				await _wait(func(): return sandbox.get_contradiction_oracle_flow().get_oracle_session() != null, "神谕未打开")
				var candidate: Control = sandbox._attack_charge_input._selection_targets[0]
				await _shoot(sandbox, candidate)
			await _wait(func(): return sandbox._rest_session != null and sandbox._rest_session.is_open(), "Rest 未打开")
			_check(sandbox._rest_result_view._overlay.visible, "真实 Rest 未显示")
			var cards: int = run.loser_card_data.get_acquired_cards(sandbox.loser_card_catalog).size()
			_check(cards == (1 if not empty_history else 0), "真击败奖励数量错误")
			var saved_result := _facts(run)
			var phase_flow: ContradictionOracleFlow = sandbox.get_contradiction_oracle_flow()
			_check(phase_flow.get_result() == sandbox._rest_session, "流程交付的 Rest 对象改变")
			_check(phase_flow.get_result().get_result_snapshot()["result_kind"] == ("breakthrough_oracle_complete" if success else "pk_win_unbroken"), "流程 Rest 分支错误")
			# 沿用真实历史按钮和返回信号，确认查看不改变成果或恢复战斗输入。
			await _frames()
			var rest_view: RestResultView = sandbox._rest_result_view
			rest_view._scripture_history_button.pressed.emit()
			await _frames()
			_check(rest_view._scripture_history.visible and not sandbox._attack_charge_input.can_start_charging(), "Rest 圣典历史或输入隔离失效")
			rest_view._scripture_history.back_requested.emit()
			rest_view._loser_card_history_button.pressed.emit()
			await _frames()
			_check(rest_view._loser_card_history.visible, "Rest 败者卡历史不可用")
			rest_view._loser_card_history.back_requested.emit()
			_check(rest_view._overlay.visible and not rest_view._continue_button.disabled and _facts(run) == saved_result, "历史返回或成果保留错误")
			sandbox.get_contradiction_oracle_flow().get_contradiction_system().outcome_locked.emit(sandbox.get_contradiction_oracle_flow().get_contradiction_system().get_outcome())
			if success:
				_check(not sandbox.get_contradiction_oracle_flow().get_confirmation_state().confirm_selection(profile.level_id,
					sandbox.get_contradiction_oracle_flow().get_confirmation_state().get_confirmed_selection(profile.level_id)), "重复确认被接受")
			_check(_facts(run) == saved_result, "重复结果修改成果")
			await _capture("%s_rest_%d" % ["empty" if empty_history else "main", level])
			var continue_button: Button = sandbox._rest_result_view._continue_button
			continue_button.pressed.emit()
			continue_button.pressed.emit()
			await _frames()
			if level == 0:
				_check(sandbox._run_state.get_current_level_profile().level_id == "test_level_02", "继续未进入第二关或重复推进")
		if not empty_history:
			await _wait(func(): return sandbox.get_divine_descent_flow().get_spread() != null and sandbox.get_divine_descent_flow().get_spread().is_sentence_locked(), "DD 未锁句")
			var spread: DivineDescentSpread = sandbox.get_divine_descent_flow().get_spread()
			spread.locked_sentence_emphasized.connect(func(_id, _count): emphasis_count += 1)
			spread.completed.connect(func(session):
				dd_completed += 1
				_check(session == sandbox.get_divine_descent_flow().get_session(), "DD 完成换了 Session"))
			var snapshot: Dictionary = sandbox.get_divine_descent_flow().get_session().get_entry_snapshot()
			var facts := _facts(run)
			var key := InputEventKey.new()
			key.keycode = KEY_SPACE
			key.pressed = true
			Input.parse_input_event(key)
			Input.flush_buffered_events()
			key = InputEventKey.new()
			key.keycode = KEY_SPACE
			key.pressed = false
			Input.parse_input_event(key)
			Input.flush_buffered_events()
			await _frames()
			_check(emphasis_count == 1, "锁句真实输入未路由 DD-14")
			_check(_facts(run) == facts and sandbox.get_divine_descent_flow().get_session().get_entry_snapshot() == snapshot, "终局输入改变冻结成果")
			_check(not sandbox._barrage_area.allows_trap_generation(), "终局陷阱边界未关闭")
			_check(not sandbox.get_divine_descent_flow().get_combat_mode().allows_normal_pk_resolution() and not sandbox.get_divine_descent_flow().get_combat_mode().allows_tier_changes(), "终局普通规则未关闭")
			var terminal_view: BarrageView
			for child in sandbox._barrage_area.get_children():
				if child is BarrageView and not child.is_queued_for_deletion():
					terminal_view = child
					break
			_check(terminal_view != null and terminal_view.get_presentation_trait_ids() == [&"occlusion"], "DD-16 未读取冻结继承表现")
			await _capture("main_divine_locked")
			await _wait(func(): return spread.is_converging(), "DD-13 未达到真实收束")
			_check(not spread.is_completed(), "DD-17 演出提前完成")
			_check(not spread.begin_full_screen_emphasis(0.15, 0.6), "重复全屏演出被接受")
			await get_tree().create_timer(0.18).timeout
			await _capture("main_full_screen_emphasis")
		await _wait(func(): return get_tree().current_scene is EndingPage, "Ending 顶层路由未完成")
		await _frames()
		_check(not is_instance_valid(sandbox), "Sandbox/终局未销毁")
		_check(flows.size() == 1 and not is_instance_valid(flows[0]), "终局流程未一次进入并销毁")
		_check(results.size() == 1 and results[0] == SceneRouter._ending_session,
			"完成通知或 Ending 路由对象改变")
		_check(results[0].get_final_snapshot()["tendency_result"] == sessions[0].get_entry_snapshot()["tendency_result"],
			"Ending 未沿用首次冻结倾向")
		var page: EndingPage = get_tree().current_scene
		await get_tree().create_timer(0.15).timeout
		_check(page._display_data.get("scripture", {}).get("is_empty") == empty_history, "结局经文空态错误")
		_check(page._scripture_rows.get_child_count() == 2, "Ending 缺章行错误")
		_check(run.live_session.fan_count == 14, "PK 胜利粉丝重复或缺失")
		_check(SceneRouter.goto_ending(SceneRouter._ending_session) == ERR_ALREADY_IN_USE, "重复结局路由被接受")
		var expected := _facts(run)
		_check(SaveManager.load_game() == OK and _facts(SaveManager.data) == expected, "真实磁盘成果读回不一致")
		await _capture("empty_ending" if empty_history else "main_ending")
		print("INT04 ROUTE PASS empty_history=", empty_history, " facts=", expected)
	_check(dd_completed == 1, "DD 演出完成次数错误")
	print("FAIL" if failed else "PASS", " INT-04 full run checks=", checks, " top_level_routes=", route_count, " DD_completed=", dd_completed)
	get_tree().quit(1 if failed else 0)

# 三步页面分别操作正式控件，保留十二张批准身份资源。
func _opening() -> void:
	_check(SceneRouter.goto_main_menu() == OK, "主菜单路由失败")
	await _frames()
	get_tree().current_scene.get_node("%StartButton").pressed.emit()
	await _frames()
	var setup = get_tree().current_scene
	setup._streamer_name_input.text = "Jackie INT04 TEST_ONLY"
	setup._streamer_continue.pressed.emit()
	_check(setup._selection._buttons.size() == 12, "批准身份数量变化")
	setup._selection._buttons[0].pressed.emit()
	# ID-10 首次点击翻开，再次点击才沿用正式单选与下一页入口。
	setup._selection._buttons[0].pressed.emit()
	setup._selection.get_node("%NextButton").pressed.emit()
	setup._fan_group_name_input.text = "INT04 TEST_ONLY fans"
	setup._confirm_button.pressed.emit()
	await _frames()
	var room = get_tree().current_scene
	_check(room.has_node("%StartLiveButton") and not room.has_node("%AttackChargeInput"), "开局房间未隔离战斗")
	await _capture("opening_room")
	room.get_node("%StartLiveButton").pressed.emit()
	_check(room.start_live() == ERR_ALREADY_IN_USE, "重复开播未隔离")
	await _frames()
	_check(get_tree().current_scene._normal_combat_active, "开播未进入真实战斗")

# 用实际普通话语产生 PK、倾向与历史，禁止直接写奖励或终局数据。
func _normal_hit(sandbox) -> void:
	var profile: LevelProfile = sandbox._run_state.get_current_level_profile()
	sandbox._barrage_area.clear_current_barrages()
	var speech: LevelSpeech = profile.get_normal_speech_pool()[0]
	var view: BarrageView = sandbox._barrage_area.spawn_normal_barrage(profile, speech)
	var previous: float = sandbox._hit_resolution.get_player_pk()
	await _shoot(sandbox, view)
	_check(sandbox._hit_resolution.get_player_pk() > previous, "普通真实攻击未增 PK")
	_check(not sandbox._hit_resolution.get_normal_hit_history().is_empty(), "普通真实命中无历史")

# 坐标通过 Viewport 变换，蓄力、飞行与硬直全由实际游戏帧推进。
func _shoot(sandbox, target: Control) -> void:
	await _frames()
	var attack: AttackChargeInput = sandbox._attack_charge_input
	var ready_before: bool = attack.can_start_charging()
	var charged_before_release := false
	var snapshots: Array[AttackTargetSnapshot] = []
	var on_shot := func(snapshot: AttackTargetSnapshot): snapshots.append(snapshot)
	attack.shot_snapshot_created.connect(on_shot)
	var target_id: int = target.get_instance_id()
	var point: Vector2 = get_viewport().get_final_transform() * target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed:
			print("INT04 aim target=", target.get_global_rect().get_center(),
				" raw_input=", point, " viewport_mouse=", sandbox._aim_reticle.get_global_mouse_position(),
				" actual_aim=", sandbox._aim_reticle.get_aim_center_global_position())
			await get_tree().create_timer(sandbox.battle_config.attack_timing.charge_time_s + 0.08).timeout
			print("INT04 before release held=", attack.is_charge_held(), " full=", attack.is_fully_charged(), " phase=", attack.get_attack_phase())
			charged_before_release = attack.is_charge_held() and attack.is_fully_charged()
	attack.shot_snapshot_created.disconnect(on_shot)
	if snapshots.size() == 1:
		print("INT04 shot targets=", snapshots[0].get_target_instance_ids(), " expected=", target_id, " facts=", snapshots[0].get_contradiction_facts())
	# 一条链路断言足以定位夹具失败；每发保持一次发射，禁止重试。
	_check(ready_before and charged_before_release and snapshots.size() == 1
		and snapshots[0].get_target_instance_ids() == [target_id], "射击链路未满足 READY→满蓄→单目标唯一快照")
	await get_tree().create_timer(sandbox.battle_config.attack_timing.projectile_flight_s + sandbox.battle_config.attack_timing.recovery_time_s + 0.1).timeout

func _facts(run: SaveData) -> Dictionary:
	return {"identity": run.identity_id, "fans": run.live_session.fan_count,
		"tendency": [run.tendency_state.orthodox_total, run.tendency_state.heretical_total, run.tendency_state.absurd_total],
		"history": run.get_committed_normal_hit_history(),
		"scripture": run.scripture_data.get_ordered_entries().size(),
		"cards": run.loser_card_data.acquired_streamer_ids.size(),
		"assimilation": run.assimilation_data.get_current_content_snapshot()}

func _wait(predicate: Callable, message: String) -> void:
	var start := Time.get_ticks_msec()
	while not predicate.call():
		if Time.get_ticks_msec() - start > 15000:
			_check(false, message)
			return
		await get_tree().process_frame

func _frames() -> void:
	for index in range(4):
		await get_tree().process_frame

func _capture(label: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.godot/int04_" + label + ".png")

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed = true
		push_error("FAIL INT-04: " + message)
		get_tree().quit(1)
