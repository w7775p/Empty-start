## INT-18A：正式场景与资源；合成输入及 PK 调试跳转只用于缩短人工刷分。
extends Node

var _checks: int = 0
var _failed: bool = false
var _media: String
var _result_events: int = 0
var _expected_cards: int = 0


## 驱动保留在树根，允许真实 SceneRouter 替换各个生产场景。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_media = ProjectSettings.globalize_path("res://.godot/int18a/media")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--int18a-media="):
			_media = argument.trim_prefix("--int18a-media=")
	DirAccess.make_dir_recursive_absolute(_media)
	get_tree().create_timer(420.0).timeout.connect(func(): _check(false, "E2E 总超时"))
	_run.call_deferred()


## 首次漫画、身份、房间、四关、终局、读档全部经真实顶层场景。
func _run() -> void:
	get_tree().current_scene = null
	print("INT18A_USER_DIR=", OS.get_user_data_dir())
	_check(not SaveManager.has_save(), "验收必须使用新的隔离user目录")
	# 本夹具继续回归旧普通弹幕 Sandbox；正式玩家入口由 PB-06 另行覆盖。
	SceneRouter.game_scene_override = load("res://scenes/sandbox/sandbox.tscn") as PackedScene
	_check(get_tree().change_scene_to_file("res://core/boot/boot.tscn") == OK, "启动Boot")
	await _wait(func(): return get_tree().current_scene is ComicPlayer, "首次漫画")
	var comic: ComicPlayer = get_tree().current_scene
	_check(comic.get_playback_control().panel_count == 19, "六幕19播放节点")
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
	_check(acts.size() == 19 and SettingsManager.opening_comic_seen, "逐格播放并保存首次记录")
	get_tree().current_scene.get_node("%StartButton").pressed.emit()
	await _frames()
	var setup = get_tree().current_scene
	setup._streamer_name_input.text = "INT18A TEST_ONLY"
	setup._streamer_continue.pressed.emit()
	setup._player_presentation_page.get_node("Center/Panel/Content/Action").pressed.emit()
	_check(setup._selection._buttons.size() == 12, "正式十二身份")
	await _capture("identity_12")
	setup._selection._buttons[0].pressed.emit()
	setup._selection._buttons[0].pressed.emit()
	setup._selection.get_node("%NextButton").pressed.emit()
	setup._room_transition_action.pressed.emit()
	setup._fan_group_name_input.text = "TEST_ONLY fans"
	setup._confirm_button.pressed.emit()
	await _frames()
	await _room_start(1)
	for order: int in range(1, 5):
		var sandbox = get_tree().current_scene
		var flow: BattleAttemptFlow = sandbox.get_battle_attempt_flow()
		var level: LevelProfile = flow.get_current_level_profile()
		_check(level.level_order == order, "正式顺序%d" % order)
		_check(level.streamer_id == ["alien", "kiwi", "frog", "fox"][order - 1], "主播稳定ID")
		print("INT18A_LEVEL_BEGIN ", level.level_id)
		await _capture("level_%d" % order)
		await _normal_shot(sandbox, order == 1)
		if OS.get_cmdline_user_args().has("--opening-demo"):
			await get_tree().create_timer(3.0).timeout
			print("INT18A_OPENING_DEMO_PASS checks=", _checks)
			get_tree().quit(0)
			return
		if order == 1:
			_check(SaveManager.data.completed_tutorial_step_ids.size() == 3, "三步由真实准心/满蓄/命中完成")
			sandbox.debug_set_player_pk(0.0)
			await get_tree().create_timer(0.5).timeout
			_check(not flow.is_normal_combat_active(), "真实失败")
			await _capture("failure")
			sandbox.get_node("%RestartButton").pressed.emit()
			await _frames()
			_check(flow.is_normal_combat_active() and SaveManager.data.completed_tutorial_step_ids.size() == 3, "失败重开保留教学")
			_check(SaveManager.data.get_committed_normal_hit_history().is_empty(), "失败命中未提交")
			await _normal_shot(sandbox, false)
		# 仅跳过重复刷PK；真实Tier仍负责演出、抽选与下一批生成。
		sandbox.debug_set_player_pk(0.67)
		await _wait(func(): return _has_special(flow.get_barrage_area()), "真实T2首次技能批次")
		await _capture("level_%d_special" % order)
		await _pause_check(sandbox)
		sandbox.debug_set_player_pk(1.0)
		var phases: ContradictionOracleFlow = sandbox.get_contradiction_oracle_flow()
		await _wait(func(): return phases.is_contradiction_active(), "PA12后Paradox")
		await _capture("level_%d_paradox" % order)
		var broken := order != 2
		var chosen: LevelContradiction = level.true_contradictions[0] if broken else level.false_contradictions[0]
		var target: BarrageView
		for child: Node in flow.get_barrage_area().get_children():
			if child is BarrageView and not child.is_queued_for_deletion():
				child.set_process(false)
				if child.runtime_record.original_sentence_id == chosen.original_sentence_id:
					target = child
				else:
					child.position = Vector2(-3000, -3000)
		_check(target != null, "正式矛盾原句存在")
		target.position = Vector2(120, 300)
		await _shoot(sandbox, target)
		var source: ContradictionBreakSystem = phases.get_contradiction_system()
		_check(source.get_outcome() == (ContradictionBreakSystem.Outcome.BREAKTHROUGH if broken else ContradictionBreakSystem.Outcome.NOT_BROKEN), "矛盾真实一发结果")
		_check(not sandbox.get_rest_result_view()._overlay.visible and phases.get_oracle_session() == null, "PA17完成前下游关闭")
		await _capture("level_%d_pa17" % order)
		if broken:
			# 生产120条复读与正式寿命自然退场，保持正式参数。
			await _wait(func(): return phases.get_oracle_session() != null, "复读自然结束后神谕", 90.0)
			await _capture("level_%d_oracle" % order)
			_check(phases.get_selection_timer().get_remaining_seconds() > 9.0, "Oracle计时从演出后开始")
			await _shoot(sandbox, sandbox.get_node("%OracleCandidateDisplay").get_child(0))
		await _wait(func(): return sandbox.get_rest_result_view()._overlay.visible, "真实Rest显示", 90.0)
		var result: RestSession = phases.get_result()
		_check(result != null and result.is_open(), "同一结果已打开")
		_check(result.get_result_snapshot()["result_kind"] == ("breakthrough_oracle_complete" if broken else "pk_win_unbroken"), "成功/未击破结果")
		if broken and sandbox.loser_card_catalog.find_profile(StringName(level.streamer_id)) != null:
			_expected_cards += 1
		var before := _facts()
		source.outcome_locked.emit(source.get_outcome())
		if broken:
			_check(not phases.get_confirmation_state().confirm_selection(level.level_id, phases.get_confirmation_state().get_confirmed_selection(level.level_id)), "重复神谕拒绝")
		_check(_facts() == before, "重复结果不发奖")
		await _capture("level_%d_rest" % order)
		sandbox.get_rest_result_view()._continue_button.pressed.emit()
		sandbox.get_rest_result_view()._continue_button.pressed.emit()
		await _frames()
		if order < 4:
			await _wait(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("start_live"), "结算回房间")
			_check(SaveManager.data.next_normal_level_order == order + 1, "重复继续仅前进一关")
			_check(SaveManager.load_game() == OK and _facts() == before, "真实保存恢复奖励")
			# 真实菜单继续入口重建房间，确认新场景不从第一关开始。
			SceneRouter.goto_main_menu()
			await _frames()
			get_tree().current_scene._continue_button.pressed.emit()
			await _frames()
			await _room_start(order + 1)
		else:
			await _wait(func(): return sandbox.get_divine_descent_flow() != null, "神降临创建")
			var divine: DivineDescentFlow = sandbox.get_divine_descent_flow()
			divine.completed.connect(func(_ending: EndingSession): _result_events += 1)
			_check(not divine.get_session().should_enter_empty_ending(), "真实普通历史进入非空终局")
			await _capture("divine_descent")
			await _wait(func(): return divine.get_spread().is_sentence_locked(), "12秒衰减后锁句", 30.0)
			await _capture("divine_locked")
			await _wait(func(): return get_tree().current_scene is EndingPage, "正式Ending", 40.0)
	_check(_result_events == 1, "Ending只接收一次")
	_check(SaveManager.data.live_session.fan_count == 480, "四关粉丝精确480")
	_check(SaveManager.data.loser_card_data.acquired_streamer_ids.size() == _expected_cards, "卡片只发放正式目录已有资料")
	_check(not SaveManager.data.loser_card_data.acquired_streamer_ids.has(&"kiwi"), "未击破不发败者卡")
	_check(SaveManager.data.assimilation_data.defeated_streamer_ids.size() == 3, "三场真正击败各提交一次")
	await _capture("ending")
	var ending: Dictionary = get_tree().current_scene._display_data.duplicate(true)
	SceneRouter.goto_main_menu()
	await _frames()
	get_tree().current_scene._continue_button.pressed.emit()
	await _wait(func(): return get_tree().current_scene is EndingPage, "存档结局回看")
	_check(get_tree().current_scene._display_data == ending, "结局快照读回不发奖")
	print("INT18A_E2E_RESULT checks=", _checks, " failed=", _failed, " ending_events=", _result_events, " facts=", _facts())
	get_tree().quit(1 if _failed else 0)


## 房间只读资料，开播按钮防重复且真正实例化正式Sandbox。
func _room_start(order: int) -> void:
	await _wait(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("start_live"), "独立房间")
	var room = get_tree().current_scene
	_check(not room.has_node("%AttackChargeInput"), "房间隔离战斗输入")
	await _capture("room_%d" % order)
	room.get_node("%StartLiveButton").pressed.emit()
	_check(room.start_live() == ERR_ALREADY_IN_USE, "开播连点拒绝")
	await _wait(func(): return get_tree().current_scene != null and get_tree().current_scene.has_method("get_battle_attempt_flow"), "主动开播进入战斗")


## 只移动验收目标以隔离随机重叠，数据与攻击时序均使用生产配置。
func _normal_shot(sandbox, tutorial: bool) -> void:
	var flow: BattleAttemptFlow = sandbox.get_battle_attempt_flow()
	var area: BarrageArea = flow.get_barrage_area()
	area.clear_current_barrages()
	var level := flow.get_current_level_profile()
	var target := area.spawn_normal_barrage(level, level.get_normal_speech_pool()[0])
	_check(target != null, "生产普通原句生成")
	target.set_process(false)
	target.position = Vector2(150, 360)
	if tutorial:
		await _capture("tutorial_aim")
	await _shoot(sandbox, target, tutorial)
	_check(not flow.get_hit_resolution().get_normal_hit_history().is_empty(), "正式命中形成暂存历史")


## 真实鼠标移动、蓄满和释放；测试不直接写入命中或教学结果。
func _shoot(sandbox, target: Control, tutorial: bool = false) -> void:
	var attack: AttackChargeInput = sandbox.get_battle_attempt_flow().get_attack_input()
	await _wait(func(): return attack.can_start_charging(), "攻击就绪")
	var point := get_viewport().get_final_transform() * target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frames()
	if tutorial:
		await _capture("tutorial_charge")
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed:
			await get_tree().create_timer(0.86).timeout
			_check(attack.is_fully_charged(), "真实满蓄")
			if tutorial:
				await _capture("tutorial_fire")
	await get_tree().create_timer(0.42).timeout


## 暂停冻结真实场景和PK回拉，按钮恢复后继续。
func _pause_check(sandbox) -> void:
	var flow: BattleAttemptFlow = sandbox.get_battle_attempt_flow()
	var before := flow.get_hit_resolution().get_player_pk()
	sandbox.get_node("%PauseMenu").pause_game()
	await get_tree().create_timer(0.25).timeout
	_check(is_equal_approx(before, flow.get_hit_resolution().get_player_pk()), "暂停PK冻结")
	await _capture("pause")
	sandbox.get_node("%PauseMenu").resume_game()


## 只读取实际生成的特殊实例，避免用目录抽样替代生产批次。
func _has_special(area: BarrageArea) -> bool:
	for child: Node in area.get_children():
		if child is BarrageView and not child.is_queued_for_deletion() and not child.runtime_record.trait_set.get_trait_ids().is_empty():
			return true
	return false


## 提取数据拥有者的稳定成果用于真实存读与去重核对。
func _facts() -> Dictionary:
	return {"fans": SaveManager.data.live_session.fan_count,
		"cards": SaveManager.data.loser_card_data.acquired_streamer_ids.duplicate(),
		"scripture": SaveManager.data.scripture_data.get_ordered_entries().size(),
		"history": SaveManager.data.get_committed_normal_hit_history(),
		"tutorial": SaveManager.data.completed_tutorial_step_ids.duplicate()}


## 使用墙钟限制单项等待，失败立即停止，避免空退出冒充通过。
func _wait(predicate: Callable, message: String, seconds: float = 15.0) -> void:
	var start := Time.get_ticks_msec()
	while not predicate.call():
		if Time.get_ticks_msec() - start > seconds * 1000:
			_check(false, "等待超时：" + message)
			return
		await get_tree().process_frame


## 等待场景切换与布局完成。
func _frames() -> void:
	for index: int in range(4):
		await get_tree().process_frame


## GPU真实截图只输出到本机D盘，不提交媒体。
func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_media.path_join(label + ".png"))


## 输出明确失败与退出码；检查成功时持续真实路线。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed = true
		push_error("INT18A_FAIL " + message)
		get_tree().quit(1)
