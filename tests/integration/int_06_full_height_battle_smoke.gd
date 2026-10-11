extends Node

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")
const STAGE_LAYOUT: StageLayoutProfile = preload("res://data/stage_layout/stage_layout_profile.tres")
const EVIDENCE_DIRECTORY: String = "res://docs/Integration/evidence/INT-06_2026-10-11"

var _failures: Array[String] = []
var _sandbox: Control
var _battle_area: Control
var _barrage_area: BarrageArea
var _oracle_display: FinalOracleCandidateDisplay
var _aim: AimReticle
var _attack: AttackChargeInput
var _hud: Control
var _pause_menu: Node
var _last_snapshot: AttackTargetSnapshot
var _last_submission: Dictionary = {}
var _last_selection_target: Control


func _ready() -> void:
	call_deferred("_run")


# 用真实 Sandbox 场景检查设计矩形、底边攻击、操作浮层穿透及暂停输入。
func _run() -> void:
	await get_tree().process_frame
	if SaveManager.data == null:
		SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	add_child(_sandbox)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_bind_sandbox_nodes()
	_verify_layout_and_icon_overlay()
	if _attack != null and _barrage_area != null:
		_attack.configure_attack_timing(SHORT_ATTACK_TIMING)
		_attack.shot_snapshot_created.connect(_on_shot_snapshot_created)
		_attack.shot_hit_resolution_submitted.connect(_on_shot_submitted)
		_attack.selection_target_hit.connect(_on_selection_target_hit)
		await _verify_bottom_edge_normal_hit()
		await _verify_mouse_passes_through_icon()
		await _verify_escape_pause_and_resume()
		await _verify_bottom_oracle_candidate_hit()
		await _verify_fullscreen_window_switch()
	await _capture_screenshot("final")
	var window_size: Vector2i = DisplayServer.window_get_size()
	print("INT06 WINDOW size=%s mode=%d viewport=%s final_transform=%s" % [
		window_size, DisplayServer.window_get_mode(), get_viewport().get_visible_rect().size,
		get_viewport().get_final_transform(),
	])
	if _failures.is_empty():
		print("PASS INT-06 full-height battle layout, transformed bottom hits, icon passthrough, ESC pause/resume")
	else:
		for failure: String in _failures:
			push_error("FAIL INT-06: " + failure)
	_sandbox.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures.is_empty() else 1)


# 读取根场景稳定节点，避免测试依赖新增的私有字段路径。
func _bind_sandbox_nodes() -> void:
	_battle_area = _sandbox.get_node("%BattleHud/BattleArea") as Control
	_barrage_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_oracle_display = _sandbox.get_node("%OracleCandidateDisplay") as FinalOracleCandidateDisplay
	_aim = _sandbox.get_node("%AimReticle") as AimReticle
	_attack = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_hud = _sandbox.get_node("%BattleHud") as Control
	_pause_menu = _sandbox.get_node("%PauseMenu")


# 对照场景节点和布局 Resource 的固定矩形，并确认旧栏清除且浮层不接收鼠标。
func _verify_layout_and_icon_overlay() -> void:
	if _battle_area == null or _barrage_area == null or _oracle_display == null:
		_check(false, "Sandbox 稳定节点引用已保留并可读取")
		return
	var top_status: Control = _battle_area.get_node("TopBattleStatus") as Control
	var hint_overlay: VBoxContainer = _battle_area.get_node("OperationHintOverlay") as VBoxContainer
	var mouse_icon: TextureRect = hint_overlay.get_node("MouseLeftIcon") as TextureRect
	var escape_icon: TextureRect = hint_overlay.get_node("EscapeIcon") as TextureRect
	var escape_label: Label = escape_icon.get_node("EscLabel") as Label
	_check(top_status.size == Vector2(1024.0, 72.0), "TopBattleStatus 保持 1024×72")
	_check(_barrage_area.position == Vector2(0.0, 72.0) and _barrage_area.size == Vector2(1024.0, 1008.0), "BarrageArea 覆盖中央局部 (0,72,1024,1008)")
	_check(_oracle_display.position == Vector2(0.0, 72.0) and _oracle_display.size == Vector2(1024.0, 1008.0), "OracleCandidateDisplay 与全高弹幕区对齐")
	_check(STAGE_LAYOUT.central_barrage_area_rect == Rect2i(448, 72, 1024, 1008), "StageLayoutProfile 保存全画面弹幕矩形")
	_check(STAGE_LAYOUT.top_battle_status_area_size == Vector2i(1024, 72), "StageLayoutProfile 保存顶部状态区尺寸")
	_check(not _battle_area.has_node("ChargeFeedback"), "旧 ChargeFeedback、ChargeState、ChargeProgress 与 ControlsHint 已移除")
	_check(hint_overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE and mouse_icon.mouse_filter == Control.MOUSE_FILTER_IGNORE and escape_icon.mouse_filter == Control.MOUSE_FILTER_IGNORE, "操作 ICON 浮层允许鼠标输入穿过")
	_check(escape_label.text == "ESC" and escape_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "ESC 按键图标保留可见按键字样且不接收鼠标")
	_check(mouse_icon.size == Vector2(48.0, 48.0) and escape_icon.size == Vector2(48.0, 48.0), "鼠标与 ESC 图标均为 48×48 并纵向排列")
	_check(_hud.get("attack_progress") != null and _hud.get("attack_phase") != null, "HUD 保留 refresh_attack 进度与阶段数据")
	var window_size: Vector2i = DisplayServer.window_get_size()
	var final_transform: Transform2D = get_viewport().get_final_transform()
	var battle_rect: Rect2 = final_transform * _battle_area.get_global_rect()
	var overlay_rect: Rect2 = final_transform * hint_overlay.get_global_rect()
	var expected_scale: Vector2 = (final_transform * _battle_area.get_global_transform()).get_scale()
	var bottom_margin: float = battle_rect.end.y - overlay_rect.end.y
	print("INT06 LAYOUT window=%s barrage=%s oracle=%s overlay_screen=%s final_transform=%s" % [window_size, _barrage_area.get_global_rect(), _oracle_display.get_global_rect(), overlay_rect, final_transform])
	_check(absf(overlay_rect.position.x - (battle_rect.position.x + 24.0 * expected_scale.x)) <= 4.0, "操作 ICON 跟随窗口比例锚定中央区左边缘")
	_check(absf(bottom_margin - 24.0 * expected_scale.y) <= 4.0, "操作 ICON 跟随窗口比例锚定中央区底边")


# 在弹幕区最底部使用真实 MouseButton 事件完成普通目标攻击。
func _verify_bottom_edge_normal_hit() -> void:
	var flow: BattleAttemptFlow = _sandbox.get_battle_attempt_flow()
	var level: LevelProfile = flow.get_current_level_profile()
	if level == null or level.normal_speech_pool.is_empty():
		_check(false, "当前关提供普通弹幕测试内容")
		return
	_barrage_area.clear_barrages()
	var target: BarrageView = _barrage_area.spawn_normal_barrage(level, level.normal_speech_pool[0])
	if target == null:
		_check(false, "底边普通目标通过 BarrageArea 正式生成入口出现")
		return
	target.set_process(false)
	target.position = Vector2((_barrage_area.size.x - target.size.x) * 0.5, _barrage_area.size.y - target.size.y - 4.0)
	await get_tree().process_frame
	var expected_target_id: int = target.get_instance_id()
	var target_rect: Rect2 = target.get_global_rect()
	await _capture_screenshot("normal_bottom")
	await _fire_at(target)
	var hit_results: Array = _last_submission.get("hit_resolution_result", {}).get("target_results", [])
	_check(_last_snapshot != null and _last_snapshot.get_target_instance_ids().has(expected_target_id), "底边普通目标进入真实释放快照")
	_check(not hit_results.is_empty(), "正确窗口变换后的准心在底边命中普通弹幕")
	print("INT06 NORMAL_BOTTOM target_id=%d global_rect=%s snapshot=%s results=%s" % [expected_target_id, target_rect, _last_snapshot.get_target_instance_ids() if _last_snapshot != null else [], hit_results])
	await _wait(0.4)


# 将普通目标放在 ESC 图标下方，确认 HUD 图形没有阻断瞄准和发射。
func _verify_mouse_passes_through_icon() -> void:
	var level: LevelProfile = _sandbox.get_battle_attempt_flow().get_current_level_profile()
	_barrage_area.clear_barrages()
	var target: BarrageView = _barrage_area.spawn_normal_barrage(level, level.normal_speech_pool[0])
	if target == null:
		_check(false, "图标下方目标通过 BarrageArea 正式生成入口出现")
		return
	target.set_process(false)
	target.position = Vector2(48.0 - target.size.x * 0.5, 960.0 - target.size.y * 0.5)
	await get_tree().process_frame
	var target_id: int = target.get_instance_id()
	await _capture_screenshot("icon_passthrough")
	await _fire_at(target)
	var hit_results: Array = _last_submission.get("hit_resolution_result", {}).get("target_results", [])
	_check(_last_snapshot != null and _last_snapshot.get_target_instance_ids().has(target_id) and not hit_results.is_empty(), "准心与左键输入能穿过 ESC ICON 命中其后方弹幕")
	await _wait(0.4)


# 以真实 Escape 按键事件检查暂停菜单和第二次 Escape 恢复。
func _verify_escape_pause_and_resume() -> void:
	_send_escape(true)
	await get_tree().process_frame
	_check(get_tree().paused, "Escape 输入打开暂停并冻结 SceneTree")
	_send_escape(false)
	await get_tree().process_frame
	_send_escape(true)
	await get_tree().process_frame
	_check(not get_tree().paused, "暂停状态下再次按 Escape 恢复游戏")
	_send_escape(false)
	await get_tree().process_frame
	print("INT06 ESC pause_resume paused=%s" % get_tree().paused)


# 进入真实 Paradox / 神谕流程，把候选移到全高区域底边并用原攻击选择入口命中。
func _verify_bottom_oracle_candidate_hit() -> void:
	var flow: BattleAttemptFlow = _sandbox.get_battle_attempt_flow()
	var level: LevelProfile = flow.get_current_level_profile()
	var hit_resolution: HitResolution = flow.get_hit_resolution()
	var candidate_count: int = mini(3, level.normal_speech_pool.size())
	for index: int in range(candidate_count):
		var speech: LevelSpeech = level.normal_speech_pool[index]
		hit_resolution.record_normal_word_hit(speech.original_sentence_id, speech.tendency_id)
	_sandbox.call("debug_set_player_pk", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var oracle_flow: ContradictionOracleFlow = _sandbox.get_contradiction_oracle_flow()
	var contradiction: ContradictionBreakSystem = oracle_flow.get_contradiction_system()
	if contradiction == null or contradiction.get_true_contradictions().is_empty():
		_check(false, "真实普通 PK 满值后进入 Paradox")
		return
	contradiction.register_launched_shot()
	var breakthrough_ids: Array[String] = [contradiction.get_true_contradictions()[0].original_sentence_id]
	contradiction.resolve_shot_hit_ids(breakthrough_ids)
	await _wait(0.7)
	var session: FinalOracleSession = oracle_flow.get_oracle_session()
	var targets: Array[Control] = []
	for child: Node in _oracle_display.get_children():
		if child is Control:
			targets.append(child as Control)
	if session == null or not session.is_open() or targets.is_empty():
		_check(false, "Paradox 击破后真实神谕候选显示在中央战斗区")
		return
	var bottom_target: Control = targets.back()
	bottom_target.position = Vector2((_oracle_display.size.x - bottom_target.size.x) * 0.5, _oracle_display.size.y - bottom_target.size.y - 8.0)
	await get_tree().process_frame
	var candidate_id: String = _oracle_display.get_candidate_id_for_target(bottom_target)
	var candidate_rect: Rect2 = bottom_target.get_global_rect()
	await _capture_screenshot("oracle_bottom")
	_last_selection_target = null
	await _fire_at(bottom_target)
	_check(_last_selection_target == bottom_target, "全高中央区域底边神谕目标接收真实攻击选择")
	_check(not candidate_id.is_empty(), "底边神谕目标保持稳定候选 ID")
	print("INT06 ORACLE_BOTTOM candidate_id=%s target_rect=%s" % [candidate_id, candidate_rect])


# 短暂切入全屏再恢复窗口，检查 BattleHud 的设计坐标和图标锚点持续适配。
func _verify_fullscreen_window_switch() -> void:
	if not OS.get_cmdline_user_args().has("--test-fullscreen"):
		return
	var starting_size: Vector2i = DisplayServer.window_get_size()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "Godot 窗口切换到全屏模式")
	await _capture_screenshot("fullscreen")
	var icon: Control = _battle_area.get_node("OperationHintOverlay/MouseLeftIcon") as Control
	var fullscreen_battle_rect: Rect2 = get_viewport().get_final_transform() * _battle_area.get_global_rect()
	var fullscreen_rect: Rect2 = get_viewport().get_final_transform() * icon.get_global_rect()
	var fullscreen_size: Vector2i = DisplayServer.window_get_size()
	_check(fullscreen_rect.position.x > fullscreen_battle_rect.position.x and fullscreen_rect.end.y < fullscreen_battle_rect.end.y, "全屏下 ICON 仍贴近左下边缘且处于可视区")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(starting_size)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "Godot 从全屏恢复原窗口尺寸")
	await _capture_screenshot("windowed_after_fullscreen")
	print("INT06 MODE_SWITCH fullscreen_size=%s restored_size=%s" % [fullscreen_size, DisplayServer.window_get_size()])


# 按满蓄输入链发送窗口坐标事件；坐标经过 Canvas 与 Viewport 最终变换。
func _fire_at(target: Control) -> void:
	await _wait_until_attack_ready()
	if not _attack.can_start_charging():
		return
	_last_snapshot = null
	_last_submission.clear()
	var event_position: Vector2 = _window_position_for(target)
	_send_mouse_button(event_position, true)
	await _wait(SHORT_ATTACK_TIMING.charge_time_s + 0.04)
	event_position = _window_position_for(target)
	_send_mouse_button(event_position, false)
	await _wait(SHORT_ATTACK_TIMING.projectile_flight_s + SHORT_ATTACK_TIMING.recovery_time_s + 0.08)


# 等上一发硬直计时确实结束后再注入下一次输入，避免依赖墙钟和帧调度余量。
func _wait_until_attack_ready() -> void:
	for _frame in range(180):
		if _attack.can_start_charging():
			return
		await get_tree().process_frame
	_check(_attack.can_start_charging(), "上一发攻击硬直结束并允许下一次真实输入")


# 使用窗口真实输入坐标，避免逻辑画布尺寸被 Viewport 重复缩放。
func _window_position_for(target: Control) -> Vector2:
	return get_viewport().get_final_transform() * (_aim.get_canvas_transform() * target.get_global_rect().get_center())


# 输入事件由 AttackChargeInput 的原有 _input 路径处理，HUD 控件只负责显示。
func _send_mouse_button(event_position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = event_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# Escape 通过项目原有 pause Input Map 进入 PauseMenu。
func _send_escape(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 保留真实视口帧作为截图证据，文件名标记窗口尺寸与窗口模式。
func _capture_screenshot(tag: String) -> void:
	await get_tree().process_frame
	var window_size: Vector2i = DisplayServer.window_get_size()
	var mode_name: String = "fullscreen" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "windowed"
	var directory: String = ProjectSettings.globalize_path(EVIDENCE_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var path: String = "%s/int06_%s_%s_%dx%d.png" % [directory, tag, mode_name, window_size.x, window_size.y]
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_png(path)
	_check(error == OK, "截图保存成功：" + path)
	print("INT06 SCREENSHOT path=%s size=%s error=%d" % [path, image.get_size(), error])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _on_shot_snapshot_created(snapshot: AttackTargetSnapshot) -> void:
	_last_snapshot = snapshot


func _on_shot_submitted(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_last_submission = submission


func _on_selection_target_hit(target: Control) -> void:
	_last_selection_target = target


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
