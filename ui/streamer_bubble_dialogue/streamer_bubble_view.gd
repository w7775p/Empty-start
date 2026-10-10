class_name StreamerBubbleView
extends Control

signal expired(view: StreamerBubbleView)

enum TailDirection { LEFT, RIGHT }

@export_enum("Left", "Right") var tail_direction: int = TailDirection.LEFT
@export_range(0.0, 1.0, 0.01) var tail_position: float = 0.68
@export_range(120.0, 448.0, 1.0) var max_bubble_width: float = 352.0
@export_range(120.0, 320.0, 1.0) var min_bubble_width: float = 142.0
@export_range(12.0, 64.0, 1.0) var tail_length: float = 24.0
@export_range(12.0, 64.0, 1.0) var tail_base_width: float = 30.0
@export var text_margin: Vector2 = Vector2(18.0, 12.0)
@export var fill_color: Color = Color("#fff6dd")
@export var text_color: Color = Color("#26242b")
@export var outline_color: Color = Color("#27242c")
@export_range(1.0, 8.0, 0.5) var outline_width: float = 3.0
@export_range(0.01, 0.8, 0.01) var popup_duration_seconds: float = 0.16
@export_range(0.0, 120.0, 1.0) var float_distance_px: float = 38.0
@export_range(0.01, 1.0, 0.01) var fade_duration_seconds: float = 0.28

@onready var _text_label: RichTextLabel = $Text

var stack_position: Vector2 = Vector2.ZERO:
	set(value):
		stack_position = value
		_update_position()

var float_progress: float = 0.0:
	set(value):
		float_progress = value
		_update_position()

var _display_duration_seconds: float = 3.0
var _lifetime_tween: Tween
var _finished: bool = false


# RichTextLabel 按 Theme 字体测量后换行；外层宽度保持在当前三列立绘区内。
func configure(message: String, display_duration_seconds: float) -> void:
	_text_label.text = message
	_text_label.add_theme_color_override("default_color", text_color)
	var theme_font: Font = _text_label.get_theme_font("normal_font")
	var font_size: int = _text_label.get_theme_font_size("normal_font_size")
	var maximum_text_width: float = maxf(
		1.0, max_bubble_width - tail_length - text_margin.x * 2.0
	)
	var widest_line: float = 0.0
	for line: String in message.split("\n", true):
		widest_line = maxf(
			widest_line,
			theme_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		)
	var minimum_text_width: float = minf(
		maximum_text_width,
		maxf(1.0, min_bubble_width - tail_length - text_margin.x * 2.0)
	)
	var text_width: float = clampf(widest_line, minimum_text_width, maximum_text_width)
	var measured_text: Vector2 = theme_font.get_multiline_string_size(
		message, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size
	)
	var text_height: float = maxf(measured_text.y, theme_font.get_height(font_size))
	var body_width: float = text_width + text_margin.x * 2.0
	var body_left: float = tail_length if tail_direction == TailDirection.LEFT else 0.0
	_text_label.position = Vector2(body_left + text_margin.x, text_margin.y)
	_text_label.size = Vector2(text_width, text_height)
	size = Vector2(body_width + tail_length, text_height + text_margin.y * 2.0)
	custom_minimum_size = size
	pivot_offset = size * 0.5
	_display_duration_seconds = maxf(display_duration_seconds, 0.1)
	queue_redraw()


# 每条对白单独运行短弹、上浮和渐隐 Tween，结束后通知所属侧浮层回收。
func start_lifecycle() -> void:
	_finished = false
	float_progress = 0.0
	scale = Vector2(0.78, 0.78)
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


# 堆叠增减时平顺挪动旧气泡，浮动量仍由各自生命周期单独叠加。
func set_stack_position(target: Vector2, animate: bool) -> void:
	if animate and is_inside_tree():
		var position_tween: Tween = create_tween()
		position_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		position_tween.tween_property(self, "stack_position", target, 0.16)
	else:
		stack_position = target


# 清理战斗尝试时取消绑定于气泡节点的 Tween，避免旧对白延迟回调。
func cancel_lifecycle() -> void:
	if is_instance_valid(_lifetime_tween) and _lifetime_tween.is_running():
		_lifetime_tween.kill()


# 普通命中满额或剧情抢占时沿用既有淡出时长提前结束，不改绘制和动画参数。
func finish_early() -> void:
	if _finished:
		return
	if is_instance_valid(_lifetime_tween) and _lifetime_tween.is_running():
		_lifetime_tween.kill()
	_lifetime_tween = create_tween()
	_lifetime_tween.tween_property(self, "modulate:a", 0.0, maxf(fade_duration_seconds, 0.01))
	_lifetime_tween.tween_callback(_emit_expired)


# 椭圆描边在尾巴根部留出开口，再补两条边线形成朝主播指向的漫画尾巴。
func _draw() -> void:
	var body_left: float = tail_length if tail_direction == TailDirection.LEFT else 0.0
	var body_width: float = size.x - tail_length
	var center := Vector2(body_left + body_width * 0.5, size.y * 0.5)
	var radius_x: float = maxf(1.0, body_width * 0.5 - outline_width * 0.5)
	var radius_y: float = maxf(1.0, size.y * 0.5 - outline_width * 0.5)
	var normalized_tail_y: float = (tail_position - 0.5) * 1.6
	var base_angle: float = asin(normalized_tail_y)
	if tail_direction == TailDirection.LEFT:
		base_angle = PI - base_angle
	var half_opening: float = clampf(tail_base_width / maxf(radius_y * 2.0, 1.0), 0.08, 0.42)
	var base_a := _ellipse_point(center, radius_x, radius_y, base_angle - half_opening)
	var base_b := _ellipse_point(center, radius_x, radius_y, base_angle + half_opening)
	var tail_tip := Vector2(
		0.0 if tail_direction == TailDirection.LEFT else size.x,
		center.y + radius_y * normalized_tail_y
	)
	var tail_points := PackedVector2Array([base_a, tail_tip, base_b])
	var shadow_offset := Vector2(0.0, 3.0)
	draw_ellipse(center + shadow_offset, radius_x, radius_y, Color(0.03, 0.03, 0.04, 0.2))
	draw_colored_polygon(_offset_points(tail_points, shadow_offset), Color(0.03, 0.03, 0.04, 0.2))
	draw_ellipse(center, radius_x, radius_y, fill_color)
	draw_colored_polygon(tail_points, fill_color)
	var arc_start: float = fposmod(base_angle + half_opening, TAU)
	var arc_end: float = arc_start + TAU - half_opening * 2.0
	draw_ellipse_arc(
		center, radius_x, radius_y, arc_start, arc_end, 64, outline_color, outline_width, true
	)
	draw_line(base_a, tail_tip, outline_color, outline_width, true)
	draw_line(tail_tip, base_b, outline_color, outline_width, true)


# 以椭圆参数角计算尾巴两端，并保持绘制点处在控件本地坐标。
func _ellipse_point(center: Vector2, radius_x: float, radius_y: float, angle: float) -> Vector2:
	return center + Vector2(cos(angle) * radius_x, sin(angle) * radius_y)


# 阴影复用同一组尾巴顶点平移绘制，保持轮廓和底色一致。
func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point: Vector2 in points:
		shifted.append(point + offset)
	return shifted


# 将浮动进度叠加到堆叠槽位，不覆盖侧浮层给出的排版位置。
func _update_position() -> void:
	position = stack_position + Vector2.UP * float_distance_px * float_progress


# 生命周期 Tween 到期时仅发送一次完成通知。
func _emit_expired() -> void:
	if _finished:
		return
	_finished = true
	expired.emit(self)
