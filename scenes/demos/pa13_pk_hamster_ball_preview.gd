extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const PREVIEW_THRESHOLD_STEP: float = 0.001

@onready var _sandbox: Control = $Sandbox
@onready var _help_panel: Control = $PreviewHelp
@onready var _help_text: Label = $PreviewHelp/Instructions


# 预览控制器保持响应暂停键；正式 Sandbox 子树仍按常规可暂停模式运行。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	if SaveManager.data == null:
		SaveManager.new_game()
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--pa13-capture"):
		_set_capture_window(Vector2i(1920, 1080))
		_help_panel.hide()
		call_deferred("_capture_desktop_preview")
	elif arguments.has("--pa13-capture-1280"):
		_set_capture_window(Vector2i(1280, 720))
		_help_panel.hide()
		call_deferred("_capture_1280_preview")


# 键盘操作经 Sandbox 的真实 HitResolution 更新 PK，并沿现有 Tier 通知刷新 HUD。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key_event: InputEventKey = event as InputEventKey
	match key_event.keycode:
		KEY_1:
			_sandbox.call("debug_set_player_pk", 0.0)
			_set_help_status("当前真实 PK：0%")
		KEY_2:
			_sandbox.call("debug_set_player_pk", 0.5)
			_set_help_status("当前真实 PK：50%")
		KEY_3:
			_sandbox.call("debug_set_player_pk", 1.0)
			_set_help_status("当前真实 PK：100%")
		KEY_U:
			_set_pk_across_tier(true)
		KEY_D:
			_set_pk_across_tier(false)
		KEY_R:
			_sandbox.call("restart_current_attempt")
			_set_help_status("已重开：笑脸与当前 PK 重新对齐")
		KEY_P:
			get_tree().paused = not get_tree().paused
			_set_help_status("预览已暂停" if get_tree().paused else "预览已继续")
		_:
			return
	get_viewport().set_input_as_handled()


# 使用当前 Tier 配置阈值触发真实升档或降档事实，不复制阶段规则。
func _set_pk_across_tier(up: bool) -> void:
	var flow: BattleAttemptFlow = _get_battle_flow()
	var current_tier: int = flow.get_current_tier()
	var tier_config: CombatStageTierConfig = TIER_CATALOG.get_tier_config(current_tier)
	if tier_config == null:
		return
	if up:
		if current_tier >= 5:
			return
		_sandbox.call("debug_set_player_pk", tier_config.upgrade_threshold)
		_set_help_status("触发真实升档：Tier %d → %d" % [current_tier, flow.get_current_tier()])
	else:
		if current_tier <= 0:
			return
		_sandbox.call(
			"debug_set_player_pk", maxf(0.0, tier_config.downgrade_threshold - PREVIEW_THRESHOLD_STEP)
		)
		_set_help_status("触发真实降档：Tier %d → %d" % [current_tier, flow.get_current_tier()])


func _capture_desktop_preview() -> void:
	await _wait_for_frames(5)
	await _restart_for_preview()
	_sandbox.call("debug_set_player_pk", 0.0)
	await _wait_seconds(0.32)
	# 只在这张 0% 组件取景帧隐藏失败卡片，Sandbox 失败结果和流程仍真实执行。
	(_sandbox.get_node("FailureOverlay") as Control).hide()
	await _save_preview_frame("pa13_pk_0_1920.png")

	await _restart_for_preview()
	_sandbox.call("debug_set_player_pk", 0.5)
	await _wait_seconds(0.28)
	await _save_preview_frame("pa13_pk_50_1920.png")

	await _restart_for_preview()
	_sandbox.call("debug_set_player_pk", 1.0)
	await _wait_seconds(0.32)
	await _save_preview_frame("pa13_pk_100_1920.png")

	await _restart_for_preview()
	var flow: BattleAttemptFlow = _get_battle_flow()
	var tier_zero: CombatStageTierConfig = TIER_CATALOG.get_tier_config(flow.get_current_tier())
	_sandbox.call("debug_set_player_pk", tier_zero.upgrade_threshold)
	await _wait_seconds(0.12)
	await _save_preview_frame("pa13_tier_up_mid_1920.png")
	await _wait_seconds(0.5)
	var tier_one: CombatStageTierConfig = TIER_CATALOG.get_tier_config(flow.get_current_tier())
	_sandbox.call(
		"debug_set_player_pk", maxf(0.0, tier_one.downgrade_threshold - PREVIEW_THRESHOLD_STEP)
	)
	await _wait_seconds(0.1)
	await _save_preview_frame("pa13_tier_down_mid_1920.png")
	await _verify_pause_and_reset()
	get_tree().quit(1 if _preview_failed else 0)


func _capture_1280_preview() -> void:
	await _wait_for_frames(5)
	await _restart_for_preview()
	_sandbox.call("debug_set_player_pk", 0.5)
	await _wait_seconds(0.28)
	await _save_preview_frame("pa13_pk_50_1280.png")
	get_tree().quit(1 if _preview_failed else 0)


# 检查 Tween 与位置跟随随 SceneTree 暂停冻结，重开后再检查表情和轨道复位。
func _verify_pause_and_reset() -> void:
	var indicator: PkHamsterBallIndicator = _get_indicator()
	var frozen_position: Vector2 = indicator.position
	get_tree().paused = true
	await _wait_always_seconds(0.18)
	var paused_in_place: bool = indicator.position.distance_to(frozen_position) < 0.1
	get_tree().paused = false
	_check(paused_in_place, "暂停期间仓鼠球位置与演出冻结")
	await _wait_seconds(1.2)
	_check(indicator.texture == PkHamsterBallIndicator.HAPPY_TEXTURE, "降档惊慌表情演出后恢复笑脸")
	await _restart_for_preview()
	var happy_after_restart: bool = indicator.texture == PkHamsterBallIndicator.HAPPY_TEXTURE
	_check(happy_after_restart, "重开恢复笑脸")


func _restart_for_preview() -> void:
	_sandbox.call("restart_current_attempt")
	await _wait_for_frames(5)


func _get_battle_flow() -> BattleAttemptFlow:
	return _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow


func _get_indicator() -> PkHamsterBallIndicator:
	return _sandbox.get_node(
		"BattleHud/BattleArea/TopBattleStatus/PKBar/PlayerShare/PkHamsterBallIndicator"
	) as PkHamsterBallIndicator


# 捕获时隐藏系统标题栏并设定客户区尺寸，确保截图是任务目标分辨率。
func _set_capture_window(window_size: Vector2i) -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_size(window_size)


func _save_preview_frame(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var window_size: Vector2i = DisplayServer.window_get_size()
	var path: String = "res://docs/Shared/PresentationAssets/previews/" + file_name
	var error: Error = image.save_png(path)
	_check(error == OK, "Godot 真实 Viewport 截图：" + file_name)
	print("PA13_CAPTURE file=%s viewport=%s window=%s player_pk=%.3f tier=%d" % [
		file_name, image.get_size(), window_size,
		_get_battle_flow().get_hit_resolution().get_player_pk(),
		_get_battle_flow().get_current_tier(),
	])


func _wait_for_frames(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await get_tree().process_frame


func _wait_seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _wait_always_seconds(seconds: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	timer.start(seconds)
	await timer.timeout
	timer.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		print("PA13_OK " + message)
	else:
		_preview_failed = true
		push_error("PA13_FAIL " + message)


func _set_help_status(message: String) -> void:
	_help_text.text = "PA-13 仓鼠球预览\n1/2/3：PK 0% / 50% / 100%   U/D：真实升档 / 降档\nR：重开   P：暂停/继续\n" + message


var _preview_failed: bool = false
