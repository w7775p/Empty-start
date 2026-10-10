class_name PA07VariantProjectile
extends Node2D

## PA-07 三选一的独立 Godot 程序美术草案，确认选型后再提炼进正式战斗组件。
enum Style { ARMOR, ENERGY, WORD }

@export var art_style: Style = Style.ARMOR:
	set(value):
		art_style = value
		queue_redraw()
@export_range(0.5, 2.5, 0.05) var art_scale: float = 1.0:
	set(value):
		art_scale = value
		queue_redraw()
@export_range(15.0, 180.0, 1.0) var speed_line_length: float = 73.0:
	set(value):
		speed_line_length = value
		queue_redraw()
@export_range(1.0, 8.0, 0.25) var speed_line_width: float = 3.0:
	set(value):
		speed_line_width = value
		queue_redraw()
@export var armor_color: Color = Color("#f9b343")
@export var energy_color: Color = Color("#39c8eb")
@export var word_color: Color = Color("#f15f82")

var flight_progress: float = 0.0
var flight_start: Vector2
var flight_end: Vector2
var is_visible_in_flight: bool = true

const INK := Color("#111528")
const WHITE := Color("#f9f9e9")


# 此组件只消费演示进度；实际 PA-07 将由发射快照和既有飞行计时驱动。
func set_flight(start_point: Vector2, end_point: Vector2, progress: float) -> void:
	flight_start = start_point
	flight_end = end_point
	flight_progress = clampf(progress, 0.0, 1.0)
	position = flight_start.lerp(flight_end, flight_progress)
	rotation = (flight_end - flight_start).angle()
	is_visible_in_flight = flight_progress < 0.965
	queue_redraw()


func _draw() -> void:
	if not is_visible_in_flight:
		return
	var visual_scale := Vector2.ONE * art_scale
	var visual_rotation := 0.0
	# 能量弹在飞行过程中略微拉伸压缩；拼贴言弹轻微摆动，三套运动规律可单独比较。
	if art_style == Style.ENERGY:
		visual_scale.x *= 1.0 + 0.20 * sin(flight_progress * PI)
		visual_scale.y *= 1.0 - 0.12 * sin(flight_progress * PI)
	elif art_style == Style.WORD:
		visual_rotation = 0.11 * sin(flight_progress * TAU * 1.5)
	draw_set_transform(Vector2.ZERO, visual_rotation, visual_scale)
	match art_style:
		Style.ARMOR:
			_draw_armor()
		Style.ENERGY:
			_draw_energy()
		Style.WORD:
			_draw_word()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# 包含粗黑轮廓、黄铜弹头、冷色弹身和三道短促漫画速度线。
func _draw_armor() -> void:
	_speed_streak(-62.0, -16.0, 0.95)
	_speed_streak(-90.0, 6.0, 0.7)
	_speed_streak(-51.0, 26.0, 0.9)
	_poly([
		Vector2(-40, -18), Vector2(9, -18), Vector2(39, -4),
		Vector2(44, 0), Vector2(39, 5), Vector2(9, 19), Vector2(-40, 19)
	], INK, 5.0)
	_poly([Vector2(1, -15), Vector2(18, -14), Vector2(40, 0), Vector2(18, 14), Vector2(1, 15)], armor_color, 3.0)
	_poly([Vector2(-34, -15), Vector2(-4, -15), Vector2(-4, 16), Vector2(-34, 16)], Color("#6a97e0"), 3.0)
	draw_line(Vector2(-23, -13), Vector2(-23, 15), INK, 4.0)
	draw_line(Vector2(-18, -9), Vector2(-18, 9), WHITE, 3.0)
	draw_line(Vector2(7, -10), Vector2(19, -9), WHITE, 3.5)
	draw_line(Vector2(-33, 22), Vector2(5, 22), WHITE, 2.0)
	draw_line(Vector2(13, 17), Vector2(31, 7), Color("#d78627"), 3.0)
	draw_circle(Vector2(-38, -6), 3.0, WHITE)


# 卡通能量弹：多层半透明光晕、清楚的蓝色液态核心、可见流线与少量反射。
func _draw_energy() -> void:
	_poly([Vector2(-speed_line_length - 32, -13), Vector2(-8, -25), Vector2(21, 0), Vector2(-8, 24), Vector2(-speed_line_length - 32, 10)], Color(0.14, 0.72, 1.0, 0.18), 0.0)
	_poly([Vector2(-98, 0), Vector2(-44, -13), Vector2(-28, 0), Vector2(-44, 13)], Color("#58d7ff"), 0.0)
	_speed_streak(-81.0, -20.0, 0.63, Color("#79e8ff"))
	_speed_streak(-118.0, 19.0, 0.55, Color("#b78bff"))
	draw_circle(Vector2(-9, 0), 34, Color(0.20, 0.68, 1, 0.12))
	draw_circle(Vector2(-4, 0), 27, Color(0.30, 0.75, 1, 0.22))
	_ellipse(Vector2(0, 0), Vector2(44, 25), INK, 5.0)
	_ellipse(Vector2(0, 0), Vector2(39, 20), Color("#377ddf"), 0.0)
	_ellipse(Vector2(13, 0), Vector2(24, 15), energy_color, 0.0)
	_ellipse(Vector2(21, 0), Vector2(16, 11), WHITE, 0.0)
	_poly([Vector2(-29,-11), Vector2(-12,-18), Vector2(7,-15), Vector2(-4,-10)], Color("#b8f6ff"), 0.0)
	draw_arc(Vector2(-23, 0), 17, -PI/2, PI/2, 17, Color("#9f66f0"), 3.0)
	draw_circle(Vector2(-47, -29), 4, WHITE)
	draw_circle(Vector2(-53, 28), 3, Color("#b6a0ff"))


# 言语冲击弹：真正用多边形造出压缩的漫画字块和碎片，不使用字体或数学符号 Label。
func _draw_word() -> void:
	_speed_streak(-70.0, -24.0, 1.0, Color("#fce2a5"))
	_speed_streak(-106.0, 5.0, 0.8, Color("#ffffff"))
	_speed_streak(-75.0, 28.0, 0.85, Color("#f77a91"))
	_poly([Vector2(-46, -16), Vector2(-16, -32), Vector2(16, -16), Vector2(44, -21),
		Vector2(30, 1), Vector2(44, 18), Vector2(10, 12), Vector2(-18, 30), Vector2(-46, 10)], INK, 5.0)
	_poly([Vector2(-37, -11), Vector2(-12, -24), Vector2(8,-10), Vector2(25,-15),
		Vector2(17, 2), Vector2(28, 12), Vector2(5, 7), Vector2(-17,22), Vector2(-37,5)], word_color, 0.0)
	_poly([Vector2(-28,-13), Vector2(-5,-20), Vector2(-9, -5), Vector2(7,-8),
		Vector2(-10,15), Vector2(-14,2), Vector2(-32,8)], WHITE, 2.5)
	_poly([Vector2(12,-12), Vector2(35,-11), Vector2(18,1), Vector2(34,10),
		Vector2(7,11), Vector2(17,-1)], Color("#ffe070"), 2.5)
	_poly([Vector2(-47,-30), Vector2(-32,-43), Vector2(-23,-28)], Color("#ffe070"), 2.0)
	_poly([Vector2(37,-28), Vector2(46,-15), Vector2(31,-12)], Color("#ff7798"), 2.0)
	_poly([Vector2(-18, 37), Vector2(-8, 27), Vector2(0, 37)], WHITE, 2.0)
	draw_circle(Vector2(-18, -15), 2.0, INK)


func _speed_streak(from_x: float, offset_y: float, strength: float, color: Color = WHITE) -> void:
	var length := speed_line_length * strength
	var start := Vector2(from_x-length, offset_y)
	var finish := Vector2(from_x+11, offset_y)
	draw_line(start + Vector2(2, 2), finish + Vector2(2, 2), INK, speed_line_width+3.0, true)
	draw_line(start, finish, color, speed_line_width, true)


func _poly(points: Array[Vector2], fill: Color, border_width: float) -> void:
	var array := PackedVector2Array(points)
	draw_colored_polygon(array, fill)
	if border_width > 0.0:
		var closed := array.duplicate()
		closed.append(array[0])
		draw_polyline(closed, INK, border_width, true)


func _ellipse(center: Vector2, radii: Vector2, color: Color, border_width: float) -> void:
	var points := PackedVector2Array()
	for i in range(34):
		var angle := TAU * float(i) / 34.0
		points.append(center + Vector2(cos(angle)*radii.x, sin(angle)*radii.y))
	draw_colored_polygon(points, color)
	if border_width > 0.0:
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, INK, border_width, true)
