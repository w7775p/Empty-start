class_name BarrageSpecialSurface
extends "res://systems/barrage_generation/barrage_glass_surface.gd"

@export_group("遮挡 / 铁质")
@export var metal_base: Color = Color("#394450")
@export var metal_edge: Color = Color("#B7CBD4")
@export_range(1.0, 9.0, 0.5) var metal_border_width: float = 3.0

@export_group("分裂 / 预裂玻璃")
@export var crack_color: Color = Color(0.92, 0.96, 1.0, 0.77)
@export_range(0.5, 4.0, 0.5) var crack_line_width: float = 1.5

@export_group("反弹 / 果冻")
@export_range(0.0, 8.0, 0.5) var jelly_wobble: float = 3.0
@export_range(0.0, 9.0, 0.1) var jelly_frequency: float = 3.5
@export_range(0.0, 1.0, 0.05) var jelly_opacity: float = 0.84
@export var jelly_shine: Color = Color(1.0, 1.0, 1.0, 0.45)

var _main_material: StringName = &"glass"
var _phase: float = 0.0
var _metal_style: StyleBoxFlat = StyleBoxFlat.new()


# 只消费已有稳定特性 ID；材质优先级与战斗结果顺序保持一致。
func configure_traits(traits: Array[StringName]) -> void:
	_main_material = &"glass"
	for id: StringName in [&"reflect", &"occlusion", &"fake_card", &"retaliation_copy", &"split"]:
		if traits.has(id):
			_main_material = id
			break
	_phase = 0.0
	set_process((_main_material == &"reflect") or (_strength == 3 and not _is_repeat))
	queue_redraw()


# 便于独立演示与场景集成方确认采用的唯一主底板。
func get_main_material() -> StringName:
	return _main_material


# 果冻常态轻微颤动；其他强度沿用 PA-04 的 S3 呼吸。
func _process(delta: float) -> void:
	if get_tree().paused:
		return
	super._process(delta)
	if _main_material == &"reflect":
		_phase += delta * jelly_frequency
		queue_redraw()


# 所有材质共享真实 BarrageView 的绘制矩形，不产生额外命中节点。
func _draw() -> void:
	if size.x < 30.0 or size.y < 25.0:
		return
	match _main_material:
		&"occlusion":
			_draw_metal()
		&"reflect":
			_draw_jelly()
		&"split":
			super._draw()
			_draw_cracked_glass()
		_:
			super._draw()


# 铁板使用低反射主体、双段硬质边和四枚浅色铆钉。
func _draw_metal() -> void:
	var tint: Color = get_base_tint()
	_metal_style.bg_color = metal_base.lerp(tint, 0.12 + float(_strength) * 0.04)
	_metal_style.bg_color.a = 0.98
	_metal_style.border_color = metal_edge.lerp(tint, 0.18)
	_metal_style.set_border_width_all(roundi(metal_border_width))
	_metal_style.set_corner_radius_all(8)
	_metal_style.shadow_color = Color(0, 0, 0, 0.56)
	_metal_style.shadow_size = 7
	draw_style_box(_metal_style, Rect2(Vector2.ZERO, size))
	var w: float = size.x
	var h: float = size.y
	# 金属拉丝为不遮字的上下短反光，避免原有长高光像按钮。
	draw_line(Vector2(12, 7), Vector2(w - 12, 7), Color(0.92, 0.97, 1.0, 0.40), 1.5, true)
	draw_line(Vector2(13, h - 8), Vector2(w - 13, h - 8), Color(0.08, 0.10, 0.16, 0.9), 2.0, true)
	for x: float in [10.0, w - 10.0]:
		for y: float in [h * 0.25, h * 0.75]:
			draw_circle(Vector2(x, y), 2.2, Color("#B2C1CA"))
			draw_circle(Vector2(x - 0.5, y - 0.5), 0.8, Color("#3D4851"))


# 玻璃继承 PA-04 的完整彩色外观；曲线裂纹只布置在四周。
func _draw_cracked_glass() -> void:
	var w: float = size.x
	var h: float = size.y
	var left: PackedVector2Array = PackedVector2Array([
		Vector2(6, 8), Vector2(20, 16), Vector2(30, 13), Vector2(39, 23),
		Vector2(49, 20), Vector2(56, 27)
	])
	var right: PackedVector2Array = PackedVector2Array([
		Vector2(w - 8, h - 7), Vector2(w - 22, h - 16), Vector2(w - 32, h - 12),
		Vector2(w - 43, h - 22), Vector2(w - 54, h - 18)
	])
	draw_polyline(left, Color(0.0, 0.06, 0.13, 0.88), crack_line_width + 1.5, true)
	draw_polyline(right, Color(0.0, 0.06, 0.13, 0.88), crack_line_width + 1.5, true)
	draw_polyline(left, crack_color, crack_line_width, true)
	draw_polyline(right, crack_color, crack_line_width, true)
	draw_line(Vector2(29, 13), Vector2(35, 5), crack_color, 1.0, true)
	draw_line(Vector2(w - 32, h - 12), Vector2(w - 24, h - 3), crack_color, 1.0, true)


# 果冻边缘随时间起伏，湿润反射沿边缘移动；正文文字保持稳定可读。
func _draw_jelly() -> void:
	var middle: Vector2 = size * 0.5
	var rx: float = size.x * 0.5
	var ry: float = size.y * 0.5
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(49):
		var a: float = TAU * float(i) / 48.0
		var wave: float = sin(a * 3.0 + _phase) * jelly_wobble
		var px: float = middle.x + cos(a) * (rx - 2.0 + wave)
		var py: float = middle.y + sin(a) * (ry - 1.0 + wave * 0.35)
		points.append(Vector2(px, py))
	var tint: Color = get_base_tint()
	var fill: Color = tint.lerp(Color("#E9FCFF"), 0.27)
	fill.a = jelly_opacity
	draw_colored_polygon(points, fill)
	var outline: Color = tint.lightened(0.67)
	outline.a = 0.90
	draw_polyline(points, outline, 3.2, true)
	var inside: Color = jelly_shine
	inside.a *= 0.65 + 0.25 * sin(_phase)
	draw_arc(Vector2(middle.x, middle.y + 1.0), minf(rx, ry) * 0.72, PI * 1.06, PI * 1.87, 32, inside, 3.0, true)
	draw_line(Vector2(24, size.y - 8), Vector2(size.x - 24, size.y - 8), Color(0.1, 0.15, 0.27, 0.25), 2.2, true)
