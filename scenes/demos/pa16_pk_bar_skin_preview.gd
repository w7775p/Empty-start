extends Control

@onready var _sandbox: Control = $Sandbox
@onready var _help_panel: Control = $PreviewHelp
@onready var _help_text: Label = $PreviewHelp/Instructions

var _preview_failed: bool = false
var _capture_output_directory: String = ""


# 预览控制器保留键盘和采集流程；正式 Sandbox 仍按原暂停规则运行。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	if SaveManager.data == null:
		SaveManager.new_game()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for argument: String in arguments:
		if argument.begins_with("--pa16-output-dir="):
			_capture_output_directory = argument.trim_prefix("--pa16-output-dir=")
	var capture_requested: bool = arguments.has("--pa16-capture") or arguments.has("--pa16-capture-1280")
	if capture_requested:
		if _capture_output_directory.is_empty():
			push_error("截图模式需使用 --pa16-output-dir=<绝对本机目录> 指定输出位置。")
			get_tree().quit(1)
			return
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(_capture_output_directory)
		if directory_error != OK:
			push_error("无法创建截图输出目录：%s" % _capture_output_directory)
			get_tree().quit(1)
			return
	if arguments.has("--pa16-capture"):
		_set_capture_window(Vector2i(1920, 1080))
		_prepare_capture_view()
		_help_panel.hide()
		call_deferred("_capture_1920")
	elif arguments.has("--pa16-capture-1280"):
		_set_capture_window(Vector2i(1280, 720))
		_prepare_capture_view()
		_help_panel.hide()
		call_deferred("_capture_1280")


# 调试按键经当前 Sandbox HitResolution 更新 PK，阶段继续由 CombatStage 计算。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event: InputEventKey = event as InputEventKey
	match key_event.keycode:
		KEY_1:
			_set_player_pk(0.05, "PK 5% · 负向 0–10%")
		KEY_2:
			_set_player_pk(0.15, "PK 15% · 负向 10–20%")
		KEY_3:
			_set_player_pk(0.25, "PK 25% · 负向 20–30%")
		KEY_4:
			_set_player_pk(0.35, "PK 35% · 负向 30–40%")
		KEY_5:
			_set_player_pk(0.45, "PK 45% · T0 原底板")
		KEY_6:
			_set_player_pk(0.56, "PK 56% · 使用当前 CombatStage")
		KEY_7:
			_set_player_pk(0.65, "PK 65% · 使用当前 CombatStage")
		KEY_8:
			_set_player_pk(0.72, "PK 72% · 使用当前 CombatStage")
		KEY_9:
			_set_player_pk(0.80, "PK 80% · 使用当前 CombatStage")
		KEY_Q:
			_set_player_pk(0.91, "PK 91% · 使用当前 CombatStage")
		KEY_E:
			_set_player_pk(1.0, "PK 100% · 请求当前矛盾流程")
		KEY_R:
			_sandbox.call("restart_current_attempt")
			_set_help_status("已重开")
		KEY_P:
			get_tree().paused = not get_tree().paused
			_set_help_status("预览已暂停" if get_tree().paused else "预览已继续")
		_:
			return
	get_viewport().set_input_as_handled()


# 调试操作经现有 Sandbox 接口提交 PK，状态文字只提示当前预览输入。
func _set_player_pk(player_pk: float, status: String) -> void:
	_sandbox.call("debug_set_player_pk", player_pk)
	_set_help_status(status)


# 用真实 CombatStage 档位状态验证 0–5 图；满 PK 由真实 ContradictionOracleFlow 切换 Paradox。
func _capture_1920() -> void:
	await _wait_for_frames(8)
	await _restart_for_preview()
	await _capture_state(0.45, "T0 原底板", "base", "pa16_tier_0_base_1920.png")
	await _capture_state(0.56, "Tier 1", "pk_bar_pos_01.png", "pa16_tier_1_1920.png")
	await _capture_tier2_transition()
	await _capture_state(0.72, "Tier 3", "pk_bar_pos_03.png", "pa16_tier_3_1920.png")
	await _capture_state(0.80, "Tier 4", "pk_bar_pos_04.png", "pa16_tier_4_1920.png")
	await _capture_state(0.91, "Tier 5", "pk_bar_pos_05.png", "pa16_tier_5_1920.png")
	_sandbox.call("debug_set_player_pk", 1.0)
	var contradiction_flow: ContradictionOracleFlow = _sandbox.call("get_contradiction_oracle_flow") as ContradictionOracleFlow
	await _wait_for_contradiction(contradiction_flow, 2.0)
	await _wait_seconds(0.36)
	_check(contradiction_flow != null and contradiction_flow.is_contradiction_active(), "Paradox 截图由真实矛盾流程进入")
	await _capture_current_state("PK 100% · Paradox", "pk_bar_pos_06.png", "pa16_paradox_1920.png")

	await _restart_for_preview()
	await _capture_state(0.05, "负向 0–10%", "pk_bar_neg_04.png", "pa16_negative_00_10_1920.png")
	await _verify_boundary(0.10, "pk_bar_neg_03.png", "10% 边界进入 neg_03")
	await _capture_state(0.15, "负向 10–20%", "pk_bar_neg_03.png", "pa16_negative_10_20_1920.png")
	await _verify_boundary(0.20, "pk_bar_neg_02.png", "20% 边界进入 neg_02")
	await _capture_state(0.25, "负向 20–30%", "pk_bar_neg_02.png", "pa16_negative_20_30_1920.png")
	await _verify_boundary(0.30, "pk_bar_neg_01.png", "30% 边界进入 neg_01")
	await _capture_state(0.35, "负向 30–40%", "pk_bar_neg_01.png", "pa16_negative_30_40_1920.png")
	await _capture_state(0.40, "PK 40% · 负向覆盖退出", "base", "pa16_recovered_40_1920.png")
	await _capture_state(0.56, "恢复至当前 Tier 1", "pk_bar_pos_01.png", "pa16_recovered_tier_1_1920.png")
	await _verify_pause_restart_and_failure()
	get_tree().quit(1 if _preview_failed else 0)


# 保存真实 Tween 的闪光、偏色、换图和稳定帧。
func _capture_tier2_transition() -> void:
	_sandbox.call("debug_set_player_pk", 0.65)
	await _wait_seconds(0.001)
	await _save_transition_frame("pa16_transition_01_flash.png", "Tier 2 目标底板闪光")
	await _wait_seconds(0.025)
	await _save_transition_frame("pa16_transition_02_tint.png", "Tier 2 目标底板偏色")
	await _wait_seconds(0.08)
	await _save_transition_frame("pa16_transition_03_swap.png", "Tier 2 新贴图恢复")
	_check_skin("pk_bar_pos_02.png", "达到换图点显示 Tier 2 底板")
	await _wait_seconds(0.25)
	_check_skin("pk_bar_pos_02.png", "Tier 2 过渡完成")
	await _capture_current_state("Tier 2 稳定", "pk_bar_pos_02.png", "pa16_tier_2_1920.png")


# 从 Godot 实际 Viewport 保存切换帧，不合成或绘制画面。
func _save_transition_frame(file_name: String, state: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	_check(_save_capture_png(image, file_name) == OK, "Godot Tween 帧 " + file_name)
	var skin: PkBarSkin = _get_skin()
	print("PA16_FRAME file=%s state=%s skin=%s tint=%s" % [
	file_name, state, skin.texture.resource_path.get_file() if skin.texture != null else "base", skin.modulate
	])

# 第二分辨率截图检查背景贴图和实际 ProgressBar 填充关系。
func _capture_1280() -> void:
	await _wait_for_frames(8)
	await _restart_for_preview()
	await _capture_state(0.65, "Tier 2 · 1280×720", "pk_bar_pos_02.png", "pa16_tier_2_1280.png")
	await _capture_state(0.25, "负向 20–30% · 1280×720", "pk_bar_neg_02.png", "pa16_negative_20_30_1280.png")
	get_tree().quit(1 if _preview_failed else 0)


# 精确检查 10% / 20% / 30% 边界仍由真实 PK 值选择右侧区间。
func _verify_boundary(player_pk: float, expected_texture: String, label: String) -> void:
	_sandbox.call("debug_set_player_pk", player_pk)
	await _wait_seconds(0.34)
	_check_skin(expected_texture, label)

# 每次目标变化经真实 Sandbox PK 接线更新，等待动画完成后核对贴图并采集帧。
func _capture_state(player_pk: float, label: String, expected_texture: String, file_name: String) -> void:
	_sandbox.call("debug_set_player_pk", player_pk)
	await _wait_seconds(0.38)
	_check_skin(expected_texture, label)
	await _capture_current_state(label, expected_texture, file_name)


# 只保存本次运行的 Godot Viewport 图像，不经过图像绘制或合成。
func _capture_current_state(label: String, expected_texture: String, file_name: String) -> void:
	var skin: PkBarSkin = _get_skin()
	_check_skin(expected_texture, label)
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var error: Error = _save_capture_png(image, file_name)
	_check(error == OK, "Godot Viewport PNG " + file_name)
	var flow: BattleAttemptFlow = _get_battle_flow()
	print("PA16_CAPTURE file=%s state=%s viewport=%s window=%s pk=%.3f tier=%d skin=%s" % [
		file_name, label, image.get_size(), window_size,
		flow.get_hit_resolution().get_player_pk(), flow.get_current_tier(),
		skin.texture.resource_path.get_file() if skin.texture != null else "base",
	])


# 采集图只写入调用方给定的本机目录，避免落进 Git 工作树。
func _save_capture_png(image: Image, file_name: String) -> Error:
	return image.save_png(_capture_output_directory.path_join(file_name))


# 固定帧采集隐藏弹幕和对白绘制层，只聚焦实际 Sandbox PK / Tier HUD。
func _prepare_capture_view() -> void:
	var battle_hud: Node = _sandbox.get_node("BattleHud")
	battle_hud.get_node("PlayerStreamerArea/PlayerPortraitPlaceholder/PlayerBubbleStack").hide()
	battle_hud.get_node("OpponentStreamerArea/OpponentPortraitPlaceholder/OpponentBubbleStack").hide()
	battle_hud.get_node("BattleArea/BarrageArea").hide()


# 对比实际 TextureRect 当前贴图，避免仅凭 PK 数字推断显示结果。
func _check_skin(expected_texture: String, label: String) -> void:
	var skin: PkBarSkin = _get_skin()
	var actual: String = skin.texture.resource_path.get_file() if skin.texture != null else "base"
	_check(actual == expected_texture, "%s 贴图：期望 %s，实际 %s" % [label, expected_texture, actual])


# 暂停检查只观察底板自己的调色 Tween；PK 状态仍由 Sandbox 正式流程拥有。
func _verify_pause_restart_and_failure() -> void:
	_sandbox.call("debug_set_player_pk", 0.65)
	await _wait_seconds(0.38)
	_sandbox.call("debug_set_player_pk", 0.72)
	await _wait_seconds(0.04)
	var skin: PkBarSkin = _get_skin()
	var frozen_modulate: Color = skin.modulate
	get_tree().paused = true
	await _wait_always_seconds(0.12)
	_check(skin.modulate.is_equal_approx(frozen_modulate), "暂停期间底板 Tween 冻结")
	get_tree().paused = false
	await _wait_seconds(0.36)
	_check(skin.modulate.is_equal_approx(Color.WHITE), "阶段底板动画结束恢复标准调色")

	_sandbox.call("debug_set_player_pk", 0.35)
	await _wait_seconds(0.04)
	_sandbox.call("restart_current_attempt")
	await _wait_for_frames(8)
	_check(_get_skin().modulate.is_equal_approx(Color.WHITE), "重开取消上一场底板闪烁")
	_sandbox.call("debug_set_player_pk", 0.0)
	await _wait_frames_in_failure()
	_check((_sandbox.get_node("FailureOverlay") as Control).visible, "PK 归零仍进入正式失败界面")
	_sandbox.call("restart_current_attempt")
	await _wait_for_frames(8)
	_check(not (_sandbox.get_node("FailureOverlay") as Control).visible, "重开收起正式失败界面")


# 等待真实失败事件抵达 HUD 后再核对失败面板。
func _wait_frames_in_failure() -> void:
	await _wait_for_frames(6)


# 重开当前真实尝试并等待新阶段与 HUD 状态稳定。
func _restart_for_preview() -> void:
	get_tree().paused = false
	_sandbox.call("restart_current_attempt")
	await _wait_for_frames(8)


# 读取 Sandbox 当前持有的正式战斗流程对象。
func _get_battle_flow() -> BattleAttemptFlow:
	return _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow


# 读取 HUD 组合的 PA-16 底板组件。
func _get_skin() -> PkBarSkin:
	return _sandbox.get_node("BattleHud/BattleArea/TopBattleStatus/PKBar/PlayerShare/PkBarSkin") as PkBarSkin


# 等待正式 ContradictionOracleFlow 进入矛盾阶段，不直接伪造 Paradox 状态。
func _wait_for_contradiction(flow: ContradictionOracleFlow, timeout_seconds: float) -> void:
	var deadline: float = Time.get_ticks_msec() + timeout_seconds * 1000.0
	while flow != null and not flow.is_contradiction_active() and Time.get_ticks_msec() < deadline:
		await _wait_seconds(0.05)


# 等待指定数量的场景帧，让节点树和 Viewport 完成更新。
func _wait_for_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await get_tree().process_frame


# 按游戏帧时间等待普通动画阶段结束。
func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


# SceneTree 暂停时仍推进检查用计时器。
func _wait_always_seconds(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()


# 设置本次 Godot Viewport 采集所需的客户区尺寸。
func _set_capture_window(window_size: Vector2i) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(window_size)


# 统一记录真实预览断言并把失败写入 Godot Output。
func _check(condition: bool, message: String) -> void:
	if condition:
		print("PA16_OK " + message)
	else:
		_preview_failed = true
		push_error("PA16_FAIL " + message)


# 更新独立演示中的按键与当前 PK 提示。
func _set_help_status(status: String) -> void:
	_help_text.text = "PA-16 PK 底板预览\n1–4：负向四档   5：T0\n6–Q：Tier 1–5   E：请求真实矛盾阶段\nR：重开   P：暂停/继续\n" + status
