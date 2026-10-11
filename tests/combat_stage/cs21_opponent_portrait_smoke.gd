extends Control

const OPPONENT_IDLE: Texture2D = preload("res://assets/characters/opponents/alien/alien_idle.png")
const PRESENTATION_ASSETS: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const SCREENSHOT_DIRECTORY: String = "res://docs/8. CombatStage/evidence/cs21_2026-10-11"

var _checks: int = 0
var _failures: int = 0


# 使用正式 Sandbox 与 CombatStage Tier 通知验收 T0/T1 立绘显隐及回切。
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().borderless = true
		get_window().min_size = Vector2i(1920, 1080)
		get_window().size = Vector2i(1920, 1080)
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var sandbox: Control = $Sandbox
	var hud: Control = sandbox.get_node("BattleHud")
	var attempt_flow: BattleAttemptFlow = sandbox.call("get_battle_attempt_flow")
	var opponent_slot: Node = hud.get_node("OpponentStreamerArea/OpponentPortraitPlaceholder")
	var portrait: TextureRect = opponent_slot.find_child("OpponentPortraitArt", true, false) as TextureRect
	var portrait_placeholder: Label = opponent_slot.get_node("PlaceholderLabel") as Label
	var state_label: Label = hud.get_node("BattleArea/TopBattleStatus/BattleStateFeedback") as Label
	if attempt_flow == null or portrait == null or portrait_placeholder == null or state_label == null:
		_check(false, "正式 Sandbox、BattleAttemptFlow 和对手立绘节点已装配")
		_finish()
		return

	await get_tree().process_frame
	# 当前 LevelProfile 示例没有指定角色映射；验收视图时使用仓库已有 idle PNG，不改正式关卡数据。
	var current_level: LevelProfile = attempt_flow.get_current_level_profile()
	if current_level == null:
		_check(false, "正式 Sandbox 提供当前 LevelProfile")
		_finish()
		return
	if current_level.streamer_portrait == null:
		print("CS-21 NOTE: level_001 has no formal streamer_portrait mapping; smoke supplies existing alien_idle.png through HUD asset API.")
	hud.call(
		"configure_streamer_assets",
		PRESENTATION_ASSETS.player_streamer_portrait,
		PRESENTATION_ASSETS.player_live_background,
		PRESENTATION_ASSETS.player_fan_badge,
		OPPONENT_IDLE,
		current_level.streamer_live_background,
		current_level.fan_badge_texture
	)

	_check(attempt_flow.get_combat_stage().get_current_tier() == 0, "新战斗从 T0 开始")
	_check(state_label.text == "等待对手连线……", "T0 沿用 CS-20 等待连线文案")
	_check(portrait.texture == OPPONENT_IDLE and not portrait.is_visible_in_tree(), "T0 等待连线时隐藏已配置的对手待机图")
	_check(not portrait_placeholder.is_visible_in_tree(), "T0 不显示对手立绘占位文案")
	await _capture("cs21_t0_waiting")

	sandbox.call("debug_set_player_pk", 0.60)
	await get_tree().process_frame
	_check(attempt_flow.get_combat_stage().get_current_tier() == 1, "正式 CombatStage 进入 T1")
	_check(state_label.text == "对手已连线", "T1 沿用 CS-20 对手已连线文案")
	_check(portrait.is_visible_in_tree(), "进入 T1 后显示现有对手待机图")
	_check(not portrait_placeholder.is_visible_in_tree(), "T1 有待机图时隐藏占位文案")
	await _wait(0.25)
	await _capture("cs21_t1_connected")

	sandbox.call("debug_set_player_pk", 0.50)
	await get_tree().process_frame
	_check(attempt_flow.get_combat_stage().get_current_tier() == 0, "正式 CombatStage 降回 T0")
	_check(state_label.text == "等待对手连线……", "降至 T0 后恢复 CS-20 等待连线文案")
	_check(not portrait.is_visible_in_tree(), "降至 T0 后重新隐藏对手待机图")
	_check(not portrait_placeholder.is_visible_in_tree(), "降至 T0 后继续隐藏对手占位文案")
	await _capture("cs21_t0_returned")

	sandbox.call("debug_set_player_pk", 0.60)
	await get_tree().process_frame
	_check(attempt_flow.get_combat_stage().get_current_tier() == 1, "再次进入 T1")
	_check(portrait.is_visible_in_tree(), "T0 后再次进入 T1 会重新显示对手待机图")
	await _wait(0.25)
	await _capture("cs21_t1_reconnected")
	_finish()


# 等待指定时间让 TextureRect 与现有待机 Tween 完成本帧绘制。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# 只保存正式 Sandbox HUD 的 GUI 视口；headless 只验证状态断言。
func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var evidence_directory: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(evidence_directory) != OK:
		_check(false, "创建 CS-21 GUI 证据目录")
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = evidence_directory.path_join(filename + ".png")
	_check(image.save_png(output_path) == OK, "保存 Godot GUI 截图 %s (%s)" % [filename, image.get_size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS CS-21: " + message)
	else:
		_failures += 1
		push_error("FAIL CS-21: " + message)


func _finish() -> void:
	print("CS-21 RESULT checks=%d failures=%d display=%s viewport=%s" % [
		_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size
	])
	get_tree().quit(0 if _failures == 0 else 1)
