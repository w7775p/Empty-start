extends Control

## 单侧直播区复用正式立绘、气泡与 LiveDataHud，只展示调用方注入的事实。

signal connection_finished
signal shutdown_finished
signal result_presentation_finished(broken: bool)

const LIVE_DATA_SCENE: PackedScene = preload("res://ui/live_data/live_data_hud.tscn")
const BUBBLE_STACK_SCRIPT: Script = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_stack.gd")
const PORTRAIT_MOTION_SCRIPT: Script = preload("res://systems/presentation/streamer_portrait_motion.gd")
const TIER_PORTRAIT_SCRIPT: Script = preload("res://systems/presentation/opponent_tier_portrait.gd")
const CRT_SCRIPT: Script = preload("res://systems/presentation/crt_connection_fx.gd")
const BREAKTHROUGH_SCENE: PackedScene = preload("res://systems/presentation/opponent_breakthrough_presentation.tscn")
const HAMSTER_PORTRAIT: Texture2D = preload("res://assets/characters/player/hamster_idle.png")
const HAMSTER_BACKGROUND: Texture2D = preload("res://assets/environment/live/hamster/background.png")
const HAMSTER_FOREGROUND: Texture2D = preload("res://assets/environment/live/hamster/foreground_desk.png")
const ALIEN_PORTRAIT: Texture2D = preload("res://assets/characters/opponents/alien/alien_idle.png")
const ALIEN_BACKGROUND: Texture2D = preload("res://assets/environment/live/alien/background.png")
const FOX_PETALS: Array[Texture2D] = [
	preload("res://assets/characters/opponents/fox/effects/fox_rose_01.png"),
	preload("res://assets/characters/opponents/fox/effects/fox_rose_02.png"),
	preload("res://assets/characters/opponents/fox/effects/fox_rose_03.png"),
	preload("res://assets/characters/opponents/fox/effects/fox_rose_04.png"),
]

var streamer_side := "player"
var _name_label: Label
var _fan_group_label: Label
var _echo_summary_label: Label
var _portrait_slot: Control
var _portrait_background: TextureRect
var _portrait_art: TextureRect
var _portrait_foreground: TextureRect
var _portrait_placeholder: Label
var _fan_badge: TextureRect
var _bubble_stack
var _crt_connection: Control
var _live_data_hud: Control
var _portrait_motion
var _tier_presenter
var _breakthrough: Control
var _result_configured := false
var _result_active := false
var _result_character_id: StringName = &""
var _result_defeat_texture: Texture2D

func configure_side(side: String) -> void:
	## 场景组合前声明左右侧，以匹配指标对齐、气泡尾部和主播待机动效。
	streamer_side = "opponent" if side == "opponent" else "player"

func _ready() -> void:
	_build_panel()
	_attach_portrait_motion()
	_apply_default_assets()
	_build_presentation_layers()

func configure_identity(display_name: String, fan_group_name: String) -> void:
	_name_label.text = display_name if not display_name.strip_edges().is_empty() else ("玩家主播" if streamer_side == "player" else "当前主播")
	_fan_group_label.text = _format_fan_group_name(fan_group_name)

func configure_assets(portrait: Texture2D, background: Texture2D, fan_badge: Texture2D = null, foreground: Texture2D = null) -> void:
	if foreground == null and streamer_side == "player" and background == HAMSTER_BACKGROUND:
		foreground = HAMSTER_FOREGROUND
	_set_texture(_portrait_background, background)
	_set_texture(_portrait_art, portrait)
	_set_texture(_portrait_foreground, foreground)
	_set_texture(_fan_badge, fan_badge)
	_portrait_placeholder.visible = portrait == null
	if _tier_presenter != null and streamer_side == "opponent":
		_tier_presenter.call("configure_textures", portrait, null, null, null)

func configure_opponent_tier_textures(idle: Texture2D, tier_01: Texture2D, tier_02: Texture2D, tier_03: Texture2D) -> void:
	if _tier_presenter != null and streamer_side == "opponent":
		_tier_presenter.call("configure_textures", idle, tier_01, tier_02, tier_03)

func configure_portrait_character(character_id: String) -> void:
	# 保存当前对手 ID，供结算演出选择对应的角色表现资源。
	_result_character_id = StringName(character_id.strip_edges())

func configure_opponent_foreground(texture: Texture2D) -> void:
	_set_texture(_portrait_foreground, texture)


func set_tier(tier: int) -> void:
	if _tier_presenter != null and streamer_side == "opponent":
		_tier_presenter.call("show_tier", tier)

func set_opponent_portrait_connected(connected: bool) -> void:
	if _tier_presenter != null and streamer_side == "opponent" and not connected:
		_tier_presenter.call("reset_for_tier", 0)
	if _crt_connection != null:
		_crt_connection.call("reset_connected" if connected else "reset_disconnected")

func configure_opponent_result(level: LevelProfile, presentation: Dictionary = {}) -> bool:
	if streamer_side != "opponent" or level == null or _breakthrough == null or _tier_presenter == null:
		return false
	_result_character_id = StringName(str(presentation.get("streamer_id", level.streamer_id)))
	_result_defeat_texture = presentation.get("portrait_defeat", level.opponent_defeat_portrait) as Texture2D
	var tier_three: Texture2D = level.opponent_tier_03_portrait
	var tiers: Array = presentation.get("portrait_tiers", [])
	if tiers.size() == 4:
		tier_three = tiers[3] as Texture2D
	var transition: Texture2D = presentation.get("portrait_defeat_transition", level.opponent_defeat_transition_portrait) as Texture2D
	_tier_presenter.call("configure_result_bounds", transition, _result_defeat_texture)
	var petals: Array[Texture2D] = []
	if _result_character_id == &"fox":
		petals = FOX_PETALS.duplicate()
	_result_configured = bool(_breakthrough.call("configure_visuals", tier_three, transition, _result_defeat_texture, petals))
	_tier_presenter.call("reset_for_tier", int(_tier_presenter.get("current_tier")))
	return _result_configured

func play_opponent_result(broken: bool) -> bool:
	if streamer_side != "opponent" or _result_active or not _result_configured or _breakthrough == null:
		return false
	_result_active = true
	set_tier(5)
	set_opponent_portrait_connected(true)
	if broken:
		if _result_character_id == &"frog":
			_tier_presenter.call("reset_for_tier", 5)
			_portrait_art.texture = _result_defeat_texture
			_portrait_motion.call("set_idle_strength", 0.0)
			_finish_result.call_deferred(true)
		elif not bool(_breakthrough.call("play_defeat", _result_character_id)):
			_result_active = false
			return false
	else:
		if not bool(_breakthrough.call("play_unbroken_offline")):
			_result_active = false
			return false
	return true

func reset_for_attempt() -> void:
	_result_active = false
	_result_configured = false
	if _breakthrough != null:
		_breakthrough.call("reset_to_tier_three")
	if _portrait_motion != null:
		_portrait_motion.call("reset_shot")
	if _crt_connection != null:
		_crt_connection.call("reset_connected" if streamer_side == "player" else "reset_disconnected")
	if _tier_presenter != null:
		_tier_presenter.call("reset_for_tier", 0)
	if _portrait_motion != null:
		_portrait_motion.call("set_idle_strength", 1.0)


func is_connecting() -> bool:
	return _crt_connection != null and bool(_crt_connection.call("is_connecting"))


func play_connection() -> void:
	if streamer_side != "opponent" or _crt_connection == null:
		connection_finished.emit()
		return
	_crt_connection.call("play_connection")


func reset_connection() -> void:
	if _crt_connection != null:
		_crt_connection.call("reset_disconnected")


func play_shutdown() -> void:
	if streamer_side != "player" or _crt_connection == null:
		shutdown_finished.emit()
		return
	_crt_connection.call("play_shutdown")


func clear_bubbles() -> void:
	if _bubble_stack != null:
		_bubble_stack.call("clear_bubbles")


func get_live_data_hud() -> Control:
	return _live_data_hud

func set_echo_summary(text_value: String) -> void:
	_echo_summary_label.text = text_value
	_echo_summary_label.tooltip_text = text_value

func bind_live_session(session: LiveSessionData, unknown_metrics: Array = []) -> void:
	_live_data_hud.call("bind_live_session", session)
	_live_data_hud.call("set_unknown_metrics", unknown_metrics)

func configure_formal_comments(rows: Array[Dictionary], parameters: Dictionary) -> void:
	_live_data_hud.call("configure_formal_comments", rows, parameters)

func show_bubble(entry: BubbleDialogueEntry) -> StreamerBubbleView:
	return _bubble_stack.call("show_bubble", entry) as StreamerBubbleView

func play_shot() -> void:
	_portrait_motion.call("play_shot")

func set_idle_strength(value: float, seconds: float = 0.15) -> void:
	_portrait_motion.call("set_idle_strength", value, seconds)

func _build_panel() -> void:
	## 侧栏比例沿用 Sandbox：128px 主播资料、432px 直播画面、520px 指标与评论。
	custom_minimum_size = Vector2(448.0, 1080.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("#101a20") if streamer_side == "player" else Color("#211b22")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_build_header(column)
	_build_camera(column)
	_build_live_data(column)


func _build_presentation_layers() -> void:
	_crt_connection = CRT_SCRIPT.new()
	_crt_connection.name = "CrtConnectionFx"
	_crt_connection.z_index = 20
	_portrait_slot.add_child(_crt_connection)
	_crt_connection.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var video_layers: Array[CanvasItem] = [_portrait_background, _portrait_art, _portrait_foreground]
	_crt_connection.call("bind_video_layers", video_layers)
	if streamer_side == "player":
		_crt_connection.connect("shutdown_finished", Callable(self, "_on_crt_shutdown_finished"))
		return
	_crt_connection.connect("connection_finished", Callable(self, "_on_crt_connection_finished"))
	_breakthrough = BREAKTHROUGH_SCENE.instantiate()
	_breakthrough.name = "OpponentBreakthroughPresentation"
	_breakthrough.z_index = 21
	_portrait_slot.add_child(_breakthrough)
	_breakthrough.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_breakthrough.call("bind_targets", _portrait_art, _portrait_motion, _tier_presenter.fit_current_texture)
	_breakthrough.connect("defeat_animation_finished", Callable(self, "_on_defeat_finished"))
	_breakthrough.connect("unbroken_offline_finished", Callable(self, "_on_unbroken_finished"))


func _on_crt_shutdown_finished() -> void:
	shutdown_finished.emit()


func _on_crt_connection_finished() -> void:
	connection_finished.emit()

func _build_header(parent: VBoxContainer) -> void:
	var header := Control.new()
	header.custom_minimum_size.y = 128.0
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(header)
	var role := _label("你的直播间" if streamer_side == "player" else "对手直播间", 16, Color("#aeb8ca"))
	role.position = Vector2(28.0, 14.0)
	role.size = Vector2(390.0, 28.0)
	header.add_child(role)
	_name_label = _label("玩家主播" if streamer_side == "player" else "当前主播", 29, Color("#f1f4fa"))
	_name_label.position = Vector2(28.0, 45.0)
	_name_label.size = Vector2(190.0, 56.0)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE
	header.add_child(_name_label)
	_fan_group_label = _label("❤粉丝团❤", 19, Color("#f7d6a3"))
	_fan_group_label.position = Vector2(224.0, 53.0)
	_fan_group_label.size = Vector2(172.0, 44.0)
	_fan_group_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fan_group_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS_FORCE
	header.add_child(_fan_group_label)
	_fan_badge = TextureRect.new()
	_fan_badge.position = Vector2(398.0, 52.0)
	_fan_badge.size = Vector2(34.0, 34.0)
	_fan_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fan_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fan_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fan_badge.visible = false
	header.add_child(_fan_badge)
	_echo_summary_label = _label("暂无当前复读", 13, Color("#d3dde1"))
	_echo_summary_label.position = Vector2(28.0, 99.0)
	_echo_summary_label.size = Vector2(390.0, 24.0)
	_echo_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_echo_summary_label)

func _build_camera(parent: VBoxContainer) -> void:
	_portrait_slot = Control.new()
	_portrait_slot.custom_minimum_size.y = 432.0
	_portrait_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_slot.clip_contents = true
	parent.add_child(_portrait_slot)
	var camera_backdrop := ColorRect.new()
	camera_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	camera_backdrop.color = Color("#253138") if streamer_side == "player" else Color("#392c36")
	camera_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_slot.add_child(camera_backdrop)
	_portrait_background = _texture_rect(TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_portrait_slot.add_child(_portrait_background)
	_portrait_art = _texture_rect(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_portrait_slot.add_child(_portrait_art)
	_portrait_foreground = _texture_rect(TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_portrait_slot.add_child(_portrait_foreground)
	_portrait_placeholder = _label("主播画面", 21, Color("#d1d7df"))
	_portrait_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_slot.add_child(_portrait_placeholder)
	_bubble_stack = BUBBLE_STACK_SCRIPT.new()
	_bubble_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bubble_stack.set("tail_direction", 1 if streamer_side == "player" else 0)
	_bubble_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_slot.add_child(_bubble_stack)

func _build_live_data(parent: VBoxContainer) -> void:
	_live_data_hud = LIVE_DATA_SCENE.instantiate()
	_live_data_hud.custom_minimum_size = Vector2(0.0, 520.0)
	_live_data_hud.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_live_data_hud.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_live_data_hud.set("display_side", 0 if streamer_side == "player" else 1)
	_live_data_hud.set("auto_bind_player_session", false)
	parent.add_child(_live_data_hud)

func _attach_portrait_motion() -> void:
	_portrait_motion = PORTRAIT_MOTION_SCRIPT.new()
	if streamer_side == "opponent":
		_portrait_motion.call("configure_character", "alien")
	_portrait_motion.call("attach_portrait", _portrait_art)
	if streamer_side == "opponent":
		_tier_presenter = TIER_PORTRAIT_SCRIPT.new()
		_tier_presenter.call("attach_portrait", _portrait_art)


func _on_defeat_finished(character_id: StringName) -> void:
	_finish_result(true)


func _on_unbroken_finished() -> void:
	_finish_result(false)


func _finish_result(broken: bool) -> void:
	if not _result_active:
		return
	_result_active = false
	result_presentation_finished.emit(broken)

func _apply_default_assets() -> void:
	if streamer_side == "player":
		configure_assets(HAMSTER_PORTRAIT, HAMSTER_BACKGROUND, null, HAMSTER_FOREGROUND)
	else:
		configure_assets(ALIEN_PORTRAIT, ALIEN_BACKGROUND)

func _set_texture(texture_rect: TextureRect, texture: Texture2D) -> void:
	texture_rect.texture = texture
	texture_rect.visible = texture != null
	if texture_rect.visible:
		_portrait_placeholder.visible = false

func _texture_rect(stretch_mode_value: int) -> TextureRect:
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = stretch_mode_value
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_rect.visible = false
	return texture_rect

func _label(text_value: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _format_fan_group_name(value: String) -> String:
	var trimmed := value.strip_edges()
	return "❤%s❤" % (trimmed if not trimmed.is_empty() else "粉丝团")
