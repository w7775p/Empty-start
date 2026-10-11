class_name StreamerBubbleView
extends Control

signal expired(view: StreamerBubbleView)

enum TailDirection { LEFT, RIGHT }

@export_enum("Left", "Right") var tail_direction: int = TailDirection.LEFT
@export_range(0.0, 1.0, 0.01) var tail_position: float = 0.68
@export_range(120.0, 448.0, 1.0) var max_bubble_width: float = 310.0
@export_range(120.0, 320.0, 1.0) var min_bubble_width: float = 134.0
@export_range(12.0, 64.0, 1.0) var tail_length: float = 22.0
@export_range(12.0, 64.0, 1.0) var tail_base_width: float = 26.0
@export var text_margin: Vector2 = Vector2(25.0, 16.0)
@export var fill_color: Color = Color("#FFF8EA")
@export var text_color: Color = Color("#292734")
@export var outline_color: Color = Color("#252331")
@export_range(1.0, 8.0, 0.5) var outline_width: float = 3.0
@export_range(0.01, 0.8, 0.01) var popup_duration_seconds: float = 0.14
@export_range(0.0, 120.0, 1.0) var float_distance_px: float = 18.0
@export_range(0.01, 1.0, 0.01) var fade_duration_seconds: float = 0.24

@onready var _text_label: RichTextLabel = $Text
@onready var _base_font_size: int = _text_label.get_theme_font_size("normal_font_size")

var stack_position: Vector2 = Vector2.ZERO:
	set(value):
		stack_position = value
		_update_position()

var float_progress: float = 0.0:
	set(value):
		float_progress = value
		_update_position()

var _message: String = ""
var _history_depth: int = 0
var _display_duration_seconds: float = 3.0
var _lifetime_tween: Tween
var _layout_tween: Tween
var _finished: bool = false


# 文字保留在原 RichTextLabel 中，历史状态只调整排版层级，不截断原文。
func configure(message: String, display_duration_seconds: float) -> void:
	_message = message
	_display_duration_seconds = maxf(display_duration_seconds, 0.1)
	_reflow()


# 最新对白为主气泡，前两条采用较小的无尾历史气泡。
func set_history_depth(depth: int) -> void:
	var updated: int = clampi(depth, 0, 2)
	if _history_depth == updated:
		return
	_history_depth = updated
	_reflow()


func _reflow() -> void:
	if _text_label == null:
		return
	var is_current: bool = _history_depth == 0
	var font: Font = _text_label.get_theme_font("normal_font")
	var base_size: int = _base_font_size
	var font_size: int = mini(22, base_size + 1) if is_current else (19 if _history_depth == 1 else 18)
	var horizontal_padding: float = text_margin.x if is_current else text_margin.x - 5.0
	var vertical_padding: float = text_margin.y if is_current else 14.0
	var tail_reserved: float = tail_length if is_current else 0.0
	var maximum_text: float = maxf(30.0, max_bubble_width - 2.0 * horizontal_padding - tail_reserved - 5.0)
	var widest: float = 0.0
	for line: String in _message.split("\n", true):
		widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var minimum_text: float = maxf(32.0, min_bubble_width - horizontal_padding * 2.0 - tail_reserved)
	var available: float = clampf(widest + 4.0, minf(minimum_text, maximum_text), maximum_text)
	var measured: Vector2 = font.get_multiline_string_size(
		_message, HORIZONTAL_ALIGNMENT_LEFT, available, font_size
	)
	# RichTextLabel 与 Font 的行距测量略有差异，留少量额外高度。
	var text_height: float = maxf(measured.y + 6.0, font.get_height(font_size) + 4.0)
	var body_width: float = available + horizontal_padding * 2.0 + 5.0
	var body_height: float = text_height + vertical_padding * 2.0 + 3.0
	var body_left: float = tail_length if is_current and tail_direction == TailDirection.LEFT else 0.0
	_text_label.text = _message
	_text_label.add_theme_font_size_override("normal_font_size", font_size)
	_text_label.add_theme_color_override("default_color", text_color if is_current else Color("#49414A"))
	_text_label.position = Vector2(body_left + horizontal_padding, vertical_padding)
	_text_label.size = Vector2(available, text_height)
	# 缩为历史气泡时先释放旧的 Control 最小尺寸，确保画面真的收缩。
	var new_size := Vector2(body_width + tail_reserved, body_height)
	custom_minimum_size = Vector2.ZERO
	size = new_size
	custom_minimum_size = new_size
	pivot_offset = size * 0.5
	self_modulate.a = 1.0
	queue_redraw()


func start_lifecycle() -> void:
	_finished = false
	float_progress = 0.0
	scale = Vector2(0.85, 0.85)
	modulate.a = 0.0
	var lifespan: float = _display_duration_seconds
	var popup_time: float = minf(popup_duration_seconds, lifespan * 0.35)
	var fade_time: float = minf(fade_duration_seconds, lifespan * 0.35)
	_lifetime_tween = create_tween().set_parallel(true)
	_lifetime_tween.tween_property(self, "scale", Vector2.ONE, popup_time) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_lifetime_tween.tween_property(self, "modulate:a", 1.0, popup_time)
	_lifetime_tween.tween_property(self, "float_progress", 1.0, lifespan) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_lifetime_tween.tween_property(self, "modulate:a", 0.0, fade_time) \
		.set_delay(lifespan - fade_time)
	_lifetime_tween.chain().tween_callback(_emit_expired)


func set_stack_position(target: Vector2, animate: bool) -> void:
	if is_instance_valid(_layout_tween):
		_layout_tween.kill()
	if animate and is_inside_tree():
		_layout_tween = create_tween()
		_layout_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_layout_tween.tween_property(self, "stack_position", target, 0.15)
	else:
		stack_position = target


func cancel_lifecycle() -> void:
	if is_instance_valid(_lifetime_tween) and _lifetime_tween.is_running():
		_lifetime_tween.kill()
	if is_instance_valid(_layout_tween):
		_layout_tween.kill()


func finish_early() -> void:
	if _finished:
		return
	if is_instance_valid(_lifetime_tween) and _lifetime_tween.is_running():
		_lifetime_tween.kill()
	_lifetime_tween = create_tween()
	_lifetime_tween.tween_property(self, "modulate:a", 0.0, maxf(fade_duration_seconds, 0.01))
	_lifetime_tween.tween_callback(_emit_expired)


# 当前对白绘制饱满的漫画椭圆和上扬尖尾；较早的气泡保留全部文字，但改为无尾的紧凑形态。
func _draw() -> void:
	if size.x < 5.0 or size.y < 5.0:
		return
	var current: bool = _history_depth == 0
	var body_left: float = tail_length if current and tail_direction == TailDirection.LEFT else 0.0
	var width: float = size.x - (tail_length if current else 0.0)
	var center := Vector2(body_left + width * 0.5, size.y * 0.5)
	var radius: Vector2 = Vector2(width * 0.5 - outline_width, size.y * 0.5 - outline_width)
	var border: PackedVector2Array = PackedVector2Array()
	var shade: PackedVector2Array = PackedVector2Array()
	for i in range(65):
		var a: float = TAU * float(i) / 64.0
		var c: float = cos(a)
		var s: float = sin(a)
		var direction: Vector2 = Vector2(signf(c) * pow(absf(c), 0.54), signf(s) * pow(absf(s), 0.54))
		border.append(center + direction * radius)
		shade.append(center + direction * radius + Vector2(0.0, 3.5))
	var shadow_color := Color("#101423", 0.31 if current else 0.14)
	draw_colored_polygon(shade, shadow_color)
	if current:
		var side: float = 1.0 if tail_direction == TailDirection.RIGHT else -1.0
		var rim: float = radius.x
		var tail_shift: float = (tail_position - 0.68) * radius.y * 0.72
		var tail_spread: float = clampf(tail_base_width / 26.0, 0.6, 1.8)
		var a: Vector2 = center + Vector2(side * rim * 0.67, -radius.y * 0.61 - 4.0 * tail_spread + tail_shift)
		var b: Vector2 = center + Vector2(side * rim * 0.90, -radius.y * 0.18 + 4.0 * tail_spread + tail_shift)
		var tip: Vector2 = center + Vector2(side * (rim + tail_length * 0.85), -radius.y - 21.0 + tail_shift)
		var elbow: Vector2 = a.lerp(tip, 0.73) + Vector2(-side * 6.0, 1.0)
		var tail: PackedVector2Array = PackedVector2Array([a, elbow, tip, b])
		draw_colored_polygon(_offset_points(tail, Vector2(0, 3.5)), shadow_color)
		draw_colored_polygon(tail, fill_color)
		draw_polyline(PackedVector2Array([a, elbow, tip, b]), outline_color, outline_width, true)
	draw_colored_polygon(border, fill_color if current else Color("#F7F0E6"))
	var edge_color: Color = outline_color if current else Color("#58505C")
	draw_polyline(border, edge_color, outline_width if current else 2.0, true)
	# Soft white glint across the upper arc, kept out of the reading area.
	if current:
		var arc_points: PackedVector2Array = PackedVector2Array()
		for i in range(16):
			var angle: float = PI * 1.16 + PI * 0.54 * float(i) / 15.0
			arc_points.append(center + Vector2(cos(angle) * radius.x * 0.87, sin(angle) * radius.y * 0.84))
		draw_polyline(arc_points, Color(1.0, 1.0, 1.0, 0.60), 2.2, true)


func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted: PackedVector2Array = PackedVector2Array()
	for item: Vector2 in points:
		shifted.append(item + offset)
	return shifted


func _update_position() -> void:
	position = stack_position + Vector2.UP * float_distance_px * float_progress


func _emit_expired() -> void:
	if _finished:
		return
	_finished = true
	expired.emit(self)
