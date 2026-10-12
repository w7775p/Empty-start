extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const PRESENTATION_SCENE: PackedScene = preload("res://systems/presentation/opponent_breakthrough_presentation.tscn")
const ASSET_CONFIG: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const PREVIEW_DIR: String = "res://docs/Shared/PresentationAssets/previews"

const ALIEN_TIER_03: Texture2D = preload("res://assets/characters/opponents/alien/alien_tier_03.png")
const ALIEN_TRANSITION: Texture2D = preload("res://assets/characters/opponents/alien/alien_defeat_transition.png")
const ALIEN_DEFEAT: Texture2D = preload("res://assets/characters/opponents/alien/alien_defeat.png")
const ALIEN_BACKGROUND: Texture2D = preload("res://assets/environment/live/alien/background.png")
const FOX_TIER_03: Texture2D = preload("res://assets/characters/opponents/fox/fox_tier_03.png")
const FOX_DEFEAT: Texture2D = preload("res://assets/characters/opponents/fox/fox_defeat.png")
const FOX_PETALS: Array[Texture2D] = [
	preload("res://assets/characters/opponents/fox/effects/fox_rose_01.png"),
	preload("res://assets/characters/opponents/fox/effects/fox_rose_02.png"),
	preload("res://assets/characters/opponents/fox/effects/fox_rose_03.png"),
	preload("res://assets/characters/opponents/fox/effects/fox_rose_04.png"),
]
const KIWI_TIER_03: Texture2D = preload("res://assets/characters/opponents/kiwi/kiwi_tier_03.png")
const KIWI_DEFEAT: Texture2D = preload("res://assets/characters/opponents/kiwi/kiwi_defeat.png")
const KIWI_BACKGROUND: Texture2D = preload("res://assets/environment/live/kiwi/background.png")

var _sandbox: Control
var _hud: Control
var _portrait: TextureRect
var _portrait_motion: StreamerPortraitMotion
var _presentation: OpponentBreakthroughPresentation
var _current_role: StringName = &"alien"
var _capture_mode: bool = false
var _record_mode: bool = false
var _record_start_frame: int = 0


# 通过额外命令行参数启动精确尺寸的 GUI 关键帧采集。
func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture-pa17")
	_record_mode = OS.get_cmdline_user_args().has("--record-pa17")
	if _capture_mode or _record_mode:
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_size(Vector2i(1920, 1080) if _capture_mode else Vector2i(1280, 720))
	call_deferred("_setup_demo")


# 复用正式 Sandbox HUD 作背景，仅关闭本次预览不需要的战斗流程。
func _setup_demo() -> void:
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set_script(null)
	_sandbox.name = "PA17PreviewSandbox"
	var attack_input: Node = _sandbox.get_node_or_null("AttackChargeInput")
	if attack_input != null:
		attack_input.set_script(null)
	add_child(_sandbox)
	move_child(_sandbox, 0)
	_sandbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame

	_hud = _sandbox.get_node("BattleHud") as Control
	_portrait = _hud.get_node("%OpponentPortraitArt") as TextureRect
	_portrait_motion = _hud.get("opponent_portrait_motion") as StreamerPortraitMotion
	var portrait_slot: Control = _sandbox.get_node(
		"BattleHud/OpponentStreamerArea/OpponentPortraitPlaceholder"
	) as Control
	_presentation = PRESENTATION_SCENE.instantiate() as OpponentBreakthroughPresentation
	portrait_slot.add_child(_presentation)
	_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _presentation.bind_targets(_portrait, _portrait_motion):
		push_error("PA17_DEMO_PORTRAIT_BIND_FAILED")
		get_tree().quit(2)
		return
	_presentation.defeat_animation_finished.connect(_on_defeat_animation_finished)
	_presentation.unbroken_offline_finished.connect(_on_unbroken_offline_finished)
	_set_role(&"alien")
	if _capture_mode:
		call_deferred("_capture_sequence")
	elif _record_mode:
		call_deferred("_record_sequence")


# 选择角色只替换本次预览的 T5、败北图和现有背景 / 花瓣素材。
func _set_role(character_id: StringName) -> void:
	_presentation.reset_to_tier_three()
	_current_role = character_id
	var role_name: String = ""
	var tier_texture: Texture2D
	var transition_texture: Texture2D
	var defeat_texture: Texture2D
	var live_background: Texture2D
	var petals: Array[Texture2D] = []
	match character_id:
		&"alien":
			role_name = "外星主播"
			tier_texture = ALIEN_TIER_03
			transition_texture = ALIEN_TRANSITION
			defeat_texture = ALIEN_DEFEAT
			live_background = ALIEN_BACKGROUND
			_hud.call("configure_portrait_character", "alien")
		&"fox":
			role_name = "狐狸主播"
			tier_texture = FOX_TIER_03
			transition_texture = null
			defeat_texture = FOX_DEFEAT
			live_background = null
			petals = FOX_PETALS
			_hud.call("configure_portrait_character", "fox")
		&"kiwi":
			role_name = "Kiwi"
			tier_texture = KIWI_TIER_03
			transition_texture = null
			defeat_texture = KIWI_DEFEAT
			live_background = KIWI_BACKGROUND
			_hud.call("configure_portrait_character", "kiwi")
		_:
			return

	_hud.call("configure_streamers", "仓鼠主播", role_name)
	_hud.call("configure_streamer_assets",
		ASSET_CONFIG.player_streamer_portrait,
		ASSET_CONFIG.player_live_background,
		ASSET_CONFIG.player_fan_badge,
		tier_texture,
		live_background,
		null
	)
	_hud.call("refresh_pk", 0.98, 5)
	_hud.call("set_opponent_portrait_connected", true)
	_hud.call("set_paradox_stage_active", true, 5)
	_hud.call("show_battle_state", "PA-17 · Paradox 成败演出预览")
	_presentation.configure_visuals(tier_texture, transition_texture, defeat_texture, petals)


# 键盘操作展示三种真击破演出及单独的未击破离线演出。
func _unhandled_key_input(event: InputEvent) -> void:
	if _capture_mode or _record_mode or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_set_role(&"alien")
			_presentation.play_defeat(&"alien")
		KEY_2:
			_set_role(&"fox")
			_presentation.play_defeat(&"fox")
		KEY_3:
			_set_role(&"kiwi")
			_presentation.play_defeat(&"kiwi")
		KEY_U:
			_presentation.play_unbroken_offline()
		KEY_R:
			_set_role(_current_role)
		_:
			return
	get_viewport().set_input_as_handled()


# 按固定顺序播放四段原有演出，供 Godot MovieWriter 连续录制。
func _record_sequence() -> void:
	_record_start_frame = Engine.get_process_frames()
	await get_tree().create_timer(0.4).timeout
	_record_mark("外星人融化开始")
	if not _presentation.play_defeat(&"alien"):
		push_error("PA17_RECORD_ALIEN_START_FAILED")
		get_tree().quit(5)
		return
	await _presentation.defeat_animation_finished
	_record_mark("外星人击败图停留")
	await get_tree().create_timer(3.75).timeout
	_record_mark("外星人片段结束")

	_set_role(&"fox")
	await get_tree().create_timer(0.35).timeout
	_record_mark("狐狸花瓣雨开始")
	if not _presentation.play_defeat(&"fox"):
		push_error("PA17_RECORD_FOX_START_FAILED")
		get_tree().quit(6)
		return
	await _presentation.defeat_animation_finished
	_record_mark("狐狸击败图停留")
	await get_tree().create_timer(3.75).timeout
	_record_mark("狐狸片段结束")

	_set_role(&"kiwi")
	await get_tree().create_timer(0.35).timeout
	_record_mark("Kiwi 整图乱舞开始")
	if not _presentation.play_defeat(&"kiwi"):
		push_error("PA17_RECORD_KIWI_START_FAILED")
		get_tree().quit(7)
		return
	await _presentation.defeat_animation_finished
	_record_mark("Kiwi 击败图停留")
	await get_tree().create_timer(3.75).timeout
	_record_mark("Kiwi 片段结束")

	_set_role(&"fox")
	await get_tree().create_timer(0.35).timeout
	_record_mark("未击破 T5 展示")
	await get_tree().create_timer(0.45).timeout
	_record_mark("未击破 T5 离线开始")
	if not _presentation.play_unbroken_offline():
		push_error("PA17_RECORD_OFFLINE_START_FAILED")
		get_tree().quit(8)
		return
	await _presentation.unbroken_offline_finished
	_record_mark("未击破离线画面停留")
	await get_tree().create_timer(3.75).timeout
	_record_mark("未击破片段结束")
	_record_mark("连续演出录制完成")
	get_tree().quit(0)


# 以固定录制帧率打印片段时间点，供 PR 中标注视频章节。
func _record_mark(label: String) -> void:
	var seconds: float = float(Engine.get_process_frames() - _record_start_frame) / 30.0
	print("PA17_VIDEO_MARK t=%.2f %s" % [seconds, label])


# HUD 状态区仅显示本次演示收到的完成通知。
func _on_defeat_animation_finished(character_id: StringName) -> void:
	_hud.call("show_battle_state", "%s 真击破演出完成" % str(character_id))


# 未击破完成只关闭对手连接表现；本演示不推进 Rest / Oracle 流程。
func _on_unbroken_offline_finished() -> void:
	_hud.call("set_opponent_portrait_connected", false)
	_hud.call("show_battle_state", "未击破 · 对手直播已离线")


# 依次捕获三种角色动作中帧与败北图，以及 T5 未击破离线两态。
func _capture_sequence() -> void:
	var output_directory: String = ProjectSettings.globalize_path(PREVIEW_DIR)
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		push_error("PA17_CAPTURE_DIRECTORY_ERROR")
		get_tree().quit(3)
		return
	await get_tree().process_frame

	_set_role(&"alien")
	_presentation.play_defeat(&"alien")
	await get_tree().create_timer(0.58).timeout
	await _capture_frame("pa17_alien_melt_mid")
	await _presentation.defeat_animation_finished
	await get_tree().create_timer(0.12).timeout
	await _capture_frame("pa17_alien_defeat")

	_set_role(&"fox")
	_presentation.play_defeat(&"fox")
	await get_tree().create_timer(0.92).timeout
	await _capture_frame("pa17_fox_petals_rain")
	await _presentation.defeat_animation_finished
	await get_tree().create_timer(0.12).timeout
	await _capture_frame("pa17_fox_defeat")

	_set_role(&"kiwi")
	_presentation.play_defeat(&"kiwi")
	await get_tree().create_timer(0.52).timeout
	await _capture_frame("pa17_kiwi_wobble_mid")
	await _presentation.defeat_animation_finished
	await get_tree().create_timer(0.12).timeout
	await _capture_frame("pa17_kiwi_defeat")

	_set_role(&"fox")
	await get_tree().create_timer(0.12).timeout
	await _capture_frame("pa17_unbroken_t5")
	_presentation.play_unbroken_offline()
	await get_tree().create_timer(0.95).timeout
	await _capture_frame("pa17_unbroken_signal_loss")
	await _presentation.unbroken_offline_finished
	await get_tree().create_timer(0.08).timeout
	await _capture_frame("pa17_unbroken_offline")
	print("PA17_CAPTURE_DONE frames=9; alien,fox,kiwi,unbroken_offline=verified")
	get_tree().quit(0)


# 保存当前 Godot GUI 视口帧，截图未经后处理。
func _capture_frame(file_stem: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var file_name: String = file_stem + "_1920.png"
	var absolute_path: String = ProjectSettings.globalize_path(PREVIEW_DIR.path_join(file_name))
	var error: Error = image.save_png(absolute_path)
	print("PA17_SCREEN %s saved=%d size=%s" % [file_name, error, image.get_size()])
	if error != OK or image.get_size() != Vector2i(1920, 1080):
		push_error("PA17_CAPTURE_FAILED %s size=%s error=%d" % [file_name, image.get_size(), error])
		get_tree().quit(4)
