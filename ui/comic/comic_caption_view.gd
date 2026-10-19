class_name ComicCaptionView
extends Control

var caption: ComicCaption
var label: RichTextLabel

const FALLBACK_DARK := Color("31271f")
const FALLBACK_LIGHT := Color("fff9e9")


# The same view is used in playback and in the visual copy editor.
func setup(value: ComicCaption) -> void:
	caption = value
	position = value.rect.position
	size = value.rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var is_bare_label := value.kind == "label"

	if not is_bare_label:
		var panel := Panel.new()
		panel.size = size
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Color("fff9e9") if value.kind == "speech" else Color("201c26e8")
		if value.kind == "danmaku":
			style.bg_color = Color.TRANSPARENT
		style.border_color = Color("473424")
		style.set_border_width_all(3)
		style.set_corner_radius_all(25 if value.kind == "speech" else 10)
		if value.kind == "danmaku":
			style.set_border_width_all(0)
		panel.add_theme_stylebox_override("panel", style)
		add_child(panel)

	label = RichTextLabel.new()
	var padding := Vector2.ZERO if is_bare_label else Vector2(22, 12)
	label.position = padding
	label.size = size - padding * 2.0
	label.bbcode_enabled = true
	label.text = value.text
	label.visible_characters = 0
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", value.font_size)
	var fallback := FALLBACK_LIGHT if value.kind == "narration" or is_bare_label else FALLBACK_DARK
	var color := value.text_color if value.text_color.a > 0.0 else fallback
	label.add_theme_color_override("default_color", color)
	if value.font_path.begins_with("res://") and ResourceLoader.exists(value.font_path, "Font"):
		var font := load(value.font_path) as Font
		if font != null:
			label.add_theme_font_override("normal_font", font)
	add_child(label)
	queue_redraw()


# Draw the speech balloon tail behind the bubble panel.
func _draw() -> void:
	if caption == null or caption.kind != "speech" or caption.tail.x < 0:
		return
	var tip := caption.tail - position
	var anchor := Vector2(clampf(tip.x, 24, size.x - 24), size.y - 5)
	draw_colored_polygon(PackedVector2Array([anchor + Vector2(-17, 0), tip, anchor + Vector2(17, 0)]), Color("fff9e9"))
	draw_line(anchor + Vector2(-17, 0), tip, Color("473424"), 3)
	draw_line(tip, anchor + Vector2(17, 0), Color("473424"), 3)
