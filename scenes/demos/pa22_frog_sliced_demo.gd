extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const ASSET_CONFIG: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const FROG_LEVEL: LevelProfile = preload("res://data/level_configuration/level_003.tres")

var _sandbox: Control
var _hud: Control
var _tier_portrait: OpponentTierPortrait
var _capture_mode: bool = false
var _record_mode: bool = false
var _dance_running: bool = false
var _current_tier: int = 1
var _capture_failures: int = 0
var _output_dir: String = ""


# 独立预览复用正式Sandbox HUD和关卡Resource；不启动根战斗流程或写入存档。
func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--pa22-capture")
	_record_mode = OS.get_cmdline_user_args().has("--record-pa22")
	if _capture_mode or _record_mode:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(Vector2i(1920, 1080))
	_output_dir = OS.get_environment("PA22_OUTPUT_DIR")
	if _output_dir.is_empty():
		_output_dir = ProjectSettings.globalize_path("res://docs/Shared/PresentationAssets/previews/pa22-frog-sliced")
	call_deferred("_setup_preview")


func _setup_preview() -> void:
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set_script(null)
	var attack_input: Node = _sandbox.get_node_or_null("AttackChargeInput")
	if attack_input != null:
		attack_input.set_script(null)
	_sandbox.name = "PA22FrogSlicedSandbox"
	add_child(_sandbox)
	move_child(_sandbox, 0)
	_sandbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame

	_hud = _sandbox.get_node("BattleHud") as Control
	_tier_portrait = _hud.get("opponent_tier_portrait") as OpponentTierPortrait
	_hud.call("configure_portrait_character", "frog")
	_hud.call("configure_streamers", "仓鼠主播", FROG_LEVEL.streamer_name)
	_hud.call("configure_fan_group_names", "玩家团", FROG_LEVEL.fan_group_name)
	_hud.call(
		"configure_streamer_assets",
		ASSET_CONFIG.player_streamer_portrait,
		ASSET_CONFIG.player_live_background,
		ASSET_CONFIG.player_fan_badge,
		FROG_LEVEL.streamer_portrait,
		FROG_LEVEL.streamer_live_background,
		FROG_LEVEL.fan_badge_texture
	)
	_hud.call(
		"configure_opponent_tier_textures",
		FROG_LEVEL.streamer_portrait,
		FROG_LEVEL.opponent_tier_01_portrait,
		FROG_LEVEL.opponent_tier_02_portrait,
		FROG_LEVEL.opponent_tier_03_portrait
	)
	_hud.call("configure_opponent_foreground", FROG_LEVEL.streamer_live_foreground)
	if not bool(_hud.call("configure_opponent_result", FROG_LEVEL, {})):
		push_error("PA22_FROG_RESULT_CONFIGURATION_FAILED")
		get_tree().quit(2)
		return
	_hud.call("set_opponent_portrait_connected", true)
	_tier_portrait.frog_cockroach_dance_finished.connect(_on_dance_finished)
	_set_tier(1)
	_hud.call("show_battle_state", "PA-22 青蛙分件 · 1/2/3 Tier · D 蟑螂舞 · R 重置")
	await get_tree().process_frame
	if _capture_mode:
		call_deferred("_capture_sequence")
	elif _record_mode:
		call_deferred("_record_sequence")


# 通过既有PK/Tier入口演示真实阶段映射。
func _set_tier(tier: int) -> void:
	_current_tier = clampi(tier, 1, 6)
	_hud.call("refresh_pk", 0.5, _current_tier)
	_hud.call("show_battle_state", "PA-22 · Tier %d" % _current_tier)


func _play_dance() -> void:
	if _dance_running:
		return
	_dance_running = _tier_portrait.play_frog_cockroach_dance()
	if _dance_running:
		_hud.call("show_battle_state", "PA-22 · 蟑螂舞进行中")
	else:
		_hud.call("show_battle_state", "PA-22 · 当前分件未启动舞蹈")


# F6后可手动切换压力阶段和重复播放蟑螂舞。
func _unhandled_key_input(event: InputEvent) -> void:
	if _capture_mode or _record_mode or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_set_tier(1)
		KEY_2:
			_set_tier(3)
		KEY_3:
			_set_tier(4)
		KEY_4:
			_set_tier(5)
		KEY_D:
			_play_dance()
		KEY_R:
			_tier_portrait.reset_for_tier(_current_tier)
			_set_tier(_current_tier)
		_:
			return
	get_viewport().set_input_as_handled()


# 自动关键帧覆盖idle、三级挣扎、舞蹈中帧和舞蹈复位。
func _capture_sequence() -> void:
	var absolute_dir: String = ProjectSettings.globalize_path(_output_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		push_error("PA22_CAPTURE_DIRECTORY_FAILED " + absolute_dir)
		get_tree().quit(3)
		return
	await get_tree().create_timer(0.45).timeout
	_set_tier(1)
	await get_tree().create_timer(0.45).timeout
	await _capture("frog_t1_idle.png")
	for frame: Dictionary in [
		{"tier": 3, "name": "frog_t3_struggle.png"},
		{"tier": 4, "name": "frog_t4_struggle.png"},
		{"tier": 5, "name": "frog_t5_struggle.png"},
	]:
		_set_tier(int(frame["tier"]))
		await get_tree().create_timer(0.72).timeout
		await _capture(str(frame["name"]))
	_play_dance()
	if not _dance_running:
		push_error("PA22_DANCE_START_FAILED")
		_capture_failures += 1
		_finish_capture()
		return
	await get_tree().create_timer(0.40).timeout
	await _capture("frog_dance_mid.png")
	await _tier_portrait.frog_cockroach_dance_finished
	await get_tree().create_timer(0.12).timeout
	await _capture("frog_dance_restored.png")
	_finish_capture()


# 连续录制只保留一轮Tier压力变化和完整蟑螂舞。
func _record_sequence() -> void:
	await get_tree().create_timer(0.4).timeout
	for tier: int in [3, 4, 5]:
		_set_tier(tier)
		await get_tree().create_timer(0.60).timeout
	_play_dance()
	if not _dance_running:
		push_error("PA22_RECORD_DANCE_START_FAILED")
		get_tree().quit(4)
		return
	await _tier_portrait.frog_cockroach_dance_finished
	await get_tree().create_timer(0.4).timeout
	print("PA22_RECORD_DONE tiers=3 dance=complete")
	get_tree().quit(0)


# 画面在Godot渲染完成后由项目RuntimeProbe直接保存到D盘。
func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var output_path: String = _output_dir.path_join(file_name)
	var result: Dictionary = MCPRuntimeProbe.capture_runtime_screenshot(output_path, "png")
	if result.has("error"):
		push_error("PA22_CAPTURE_FAILED %s %s" % [file_name, result["error"]])
		_capture_failures += 1
	else:
		print("PA22_CAPTURE %s size=%s scene=%s" % [
			file_name, result.get("size", "?"), result.get("current_scene", "?")
		])


func _on_dance_finished() -> void:
	_dance_running = false
	if not _capture_mode and not _record_mode and _hud != null:
		_hud.call("show_battle_state", "PA-22 · 蟑螂舞结束，已恢复当前Tier")


func _finish_capture() -> void:
	print("PA22_CAPTURE_DONE failures=%d output=%s" % [_capture_failures, _output_dir])
	get_tree().quit(1 if _capture_failures > 0 else 0)
