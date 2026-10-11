extends SceneTree

const THEME_PATH := "res://ui/theme/base_theme.tres"
const NORMAL_PATH := "res://assets/fonts/NotoSansSC-VF.ttf"
const STREAMER_PATH := "res://assets/fonts/ZCOOLKuaiLe-Regular.ttf"


func _initialize() -> void:
	call_deferred("_check_font_roles")


func _check_font_roles() -> void:
	var failures: Array[String] = []
	var theme: Theme = load(THEME_PATH)
	var normal: Font = load(NORMAL_PATH)
	var streamer: Font = load(STREAMER_PATH)
	if theme == null or normal == null or streamer == null:
		push_error("Font resources or base Theme failed to load")
		quit(1)
		return
	if theme.default_font != normal:
		failures.append("Global theme default is not Noto Sans SC")
	for glyph: int in [0x795E, 0x55B5, 0x7C89]:
		if not normal.has_char(glyph):
			failures.append("Noto Sans SC lacks Chinese glyph U+%04X" % glyph)
		if not streamer.has_char(glyph):
			failures.append("ZCOOL KuaiLe lacks Chinese glyph U+%04X" % glyph)
	_check_label_font(theme, &"", normal, "font", failures)
	_check_label_font(theme, &"StreamerNameLabel", streamer, "font", failures)
	_check_label_font(theme, &"StreamerHeadingLabel", streamer, "font", failures)
	_check_label_font(theme, &"StreamerMutedLabel", streamer, "font", failures)
	_check_label_font(theme, &"FanGroupNameLabel", streamer, "font", failures)
	var name_input := LineEdit.new()
	name_input.theme = theme
	name_input.theme_type_variation = &"StreamerNameInput"
	root.add_child(name_input)
	if name_input.get_theme_font("font") != streamer:
		failures.append("StreamerNameInput is not using ZCOOL KuaiLe")
	name_input.queue_free()
	var rich := RichTextLabel.new()
	rich.theme = theme
	root.add_child(rich)
	if rich.get_theme_font("normal_font") != normal:
		failures.append("RichTextLabel did not inherit Noto Sans SC")
	rich.queue_free()
	var sandbox_scene: PackedScene = load("res://scenes/sandbox/sandbox.tscn")
	if sandbox_scene == null:
		failures.append("Sandbox scene failed to load")
	else:
		var sandbox := sandbox_scene.instantiate()
		var player: Label = sandbox.get_node("BattleHud/PlayerStreamerArea/PlayerInfoArea/PlayerName")
		var opponent: Label = sandbox.get_node("BattleHud/OpponentStreamerArea/OpponentInfoArea/OpponentName")
		if player.theme_type_variation != &"StreamerHeadingLabel" or opponent.theme_type_variation != &"StreamerHeadingLabel":
			failures.append("Sandbox streamer name labels do not use the ZCOOL variant")
		sandbox.free()
	if failures.is_empty():
		print("FONT_THEME_SMOKE_OK: global, name roles, Chinese glyphs, rich text")
		quit(0)
	else:
		for failure: String in failures:
			push_error(failure)
		quit(1)


func _check_label_font(theme: Theme, variation: StringName, expected: Font, font_item: String, failures: Array[String]) -> void:
	var label := Label.new()
	label.theme = theme
	if not variation.is_empty():
		label.theme_type_variation = variation
	root.add_child(label)
	if label.get_theme_font(font_item) != expected:
		failures.append("Label role %s uses an unexpected font" % variation)
	label.queue_free()
