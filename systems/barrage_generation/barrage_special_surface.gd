class_name BarrageSpecialSurface
extends "res://systems/barrage_generation/barrage_glass_surface.gd"

@export_group("遮挡 / 铁质")
@export var metal_base: Color = Color("#394450")
@export var metal_edge: Color = Color("#B7CBD4")
@export_range(1.0, 9.0, 0.5) var metal_border_width: float = 3.0

@export_group("分裂 / 预裂玻璃")
@export var crack_color: Color = Color(0.92, 0.96, 1.0, 0.77)
@export_range(0.5, 4.0, 0.5) var crack_line_width: float = 1.5

@export_group("水军反击 / 单块刷屏")
@export var retaliation_base: Color = Color("#2B3143")
@export var retaliation_edge: Color = Color("#E8A6A1")
@export_range(12, 24, 1) var retaliation_font_size: int = 16
@export_range(0.0, 14.0, 0.5) var retaliation_notch: float = 8.0

@export_group("反弹 / 果冻")
@export_range(0.0, 8.0, 0.5) var jelly_wobble: float = 3.5
@export_range(0.0, 9.0, 0.1) var jelly_frequency: float = 2.8
@export_range(0.0, 1.0, 0.05) var jelly_opacity: float = 0.76
@export var jelly_shine: Color = Color(1.0, 1.0, 1.0, 0.68)

var _main_material: StringName = &"glass"
var _phase: float = 0.0
var _source_line: String = ""
var _text_font: Font
var _metal_style: StyleBoxFlat = StyleBoxFlat.new()


# 只消费已有稳定特性 ID；材质优先级与战斗结果顺序保持一致。
func configure_traits(traits: Array[StringName], source_line: String = "", drawing_font: Font = null) -> void:
	_main_material = &"glass"
	for id: StringName in [&"reflect", &"occlusion", &"fake_card", &"retaliation_copy", &"split"]:
		if traits.has(id):
			_main_material = id
			break
	_phase = 0.0
	_source_line = source_line
	_text_font = drawing_font
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
		# 与 PA-04 共用已有 24Hz 节流重绘；连续形变本身不需要独立逐帧刷新。
		_phase += delta * jelly_frequency


# 所有材质共享真实 BarrageView 的绘制矩形，不产生额外命中节点。
func _draw() -> void:
	if size.x < 30.0 or size.y < 25.0:
		return
	match _main_material:
		&"occlusion":
			_draw_metal()
		&"reflect":
			_draw_jelly()
		&"fake_card":
			_draw_fake_repeat()
		&"retaliation_copy":
			_draw_retaliation_panel()
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


# 参考凝胶软糖：圆角方形外轮廓、内部透光胶体、顶部弧形湿润反光。
# 高分辨率轮廓以连续轮廓点绘制，小幅缓慢变形由已有 PA-04 24Hz 刷新驱动。
func _draw_jelly() -> void:
	var center: Vector2 = size * 0.5
	var radius: Vector2 = size * 0.5 - Vector2(3.0, 3.0)
	var hull: PackedVector2Array = PackedVector2Array()
	var core: PackedVector2Array = PackedVector2Array()
	for i in range(65):
		var angle: float = TAU * float(i) / 64.0
		var cx: float = cos(angle)
		var cy: float = sin(angle)
		# 超椭圆把扁长椭圆改为饱满的圆角凝胶块；表面产生轻微不规则弹性起伏。
		var contour: Vector2 = Vector2(
			signf(cx) * pow(absf(cx), 0.63) * radius.x,
			signf(cy) * pow(absf(cy), 0.63) * radius.y
		)
		var jiggle: float = sin(angle * 3.0 + _phase) * jelly_wobble
		contour += Vector2(cx * jiggle * 0.55, cy * jiggle * 0.45)
		hull.append(center + contour)
		core.append(center + contour * Vector2(0.94, 0.76) + Vector2(0, -1.0))
	var tint: Color = get_base_tint()
	var gel: Color = tint.lightened(0.18)
	gel.a = jelly_opacity
	var dark_edge: Color = tint.darkened(0.39)
	dark_edge.a = 0.56
	var light_edge: Color = tint.lightened(0.62)
	light_edge.a = 0.47
	var lit_core: Color = tint.lightened(0.52)
	lit_core.a = 0.27
	# 暗边包裹透明胶体，较亮的内层保持底下画面透出。
	draw_colored_polygon(hull, gel)
	draw_colored_polygon(core, lit_core)
	# 底部流动的胶体折光层增加体积与重量感，保留中心正文区域。
	var lower_gel: Color = tint.lightened(0.34)
	lower_gel.a = 0.32
	draw_colored_polygon(PackedVector2Array([
		Vector2(19, size.y - 22), Vector2(size.x * 0.34, size.y - 28),
		Vector2(size.x * 0.64, size.y - 20), Vector2(size.x - 19, size.y - 23),
		Vector2(size.x - 20, size.y - 11), Vector2(19, size.y - 11)
	]), lower_gel)
	draw_polyline(hull, dark_edge, 2.8, true)
	draw_polyline(hull, light_edge, 1.1, true)
	# 凝胶顶面使用整体柔软反射，避开中心正文。
	var reflection: PackedVector2Array = PackedVector2Array()
	for i in range(20):
		var angle: float = PI * 1.10 + PI * 0.43 * float(i) / 19.0
		var cx: float = cos(angle)
		var cy: float = sin(angle)
		reflection.append(center + Vector2(
			signf(cx) * pow(absf(cx), 0.63) * (radius.x - 8.0),
			signf(cy) * pow(absf(cy), 0.63) * (radius.y - 7.0)
		))
	var shine: Color = jelly_shine
	shine.a *= 0.88
	draw_polyline(reflection, shine, 2.8, true)
	# 微小的胶体气泡只放在边缘，避开正文。其亮暗相依来传递湿润和透光感。
	var bubble_dark: Color = tint.darkened(0.24)
	bubble_dark.a = 0.42
	var bubble_light: Color = Color(1.0, 1.0, 1.0, 0.42)
	for center_point: Vector2 in [Vector2(26, 19), Vector2(size.x - 30, 18), Vector2(size.x - 22, size.y - 20)]:
		draw_circle(center_point, 4.5, bubble_dark)
		draw_arc(center_point, 3.2, PI * 1.05, PI * 1.84, 12, bubble_light, 1.2, true)
	var lowlight: Color = tint.lightened(0.60)
	lowlight.a = 0.30
	draw_line(Vector2(size.x * 0.34, size.y - 9), Vector2(size.x * 0.78, size.y - 9), lowlight, 1.6, true)



# 假复读使用 PA-04 真复读的同一块灰玻璃调色、透明度和边缘样式，只改圆角形状。
func _draw_fake_repeat() -> void:
	var center: Vector2 = size * 0.5
	var radius: Vector2 = size * 0.5 - Vector2.ONE * 1.5
	var ellipse: PackedVector2Array = PackedVector2Array()
	for index in range(65):
		var theta: float = TAU * float(index) / 64.0
		ellipse.append(center + Vector2(cos(theta), sin(theta)) * radius)
	draw_colored_polygon(ellipse, _glass_style.bg_color)
	draw_polyline(ellipse, _glass_style.border_color, 1.0, true)


# 同一个命中矩形对应一块不规则板；多处小字都由本 CanvasItem 绘制。
func _draw_retaliation_panel() -> void:
	var w: float = size.x
	var h: float = size.y
	var notch: float = retaliation_notch
	var polygon: PackedVector2Array = PackedVector2Array([
		Vector2(notch + 5, 0), Vector2(w * 0.55, 0), Vector2(w * 0.59, 5),
		Vector2(w - notch - 3, 3), Vector2(w, notch + 5), Vector2(w - 4, h * 0.43),
		Vector2(w, h - notch), Vector2(w - notch - 8, h),
		Vector2(w * 0.51, h - 3), Vector2(w * 0.43, h),
		Vector2(notch + 6, h - 2), Vector2(0, h - notch - 4),
		Vector2(4, h * 0.41), Vector2(0, notch + 6), Vector2(notch + 5, 0)
	])
	var shade: Color = retaliation_base.lerp(get_base_tint(), 0.24)
	shade.a = 0.95
	draw_colored_polygon(polygon, shade)
	draw_polyline(polygon, retaliation_edge, 3.0, true)
	draw_line(Vector2(18, 10), Vector2(w - 18, 11), Color(1.0, 0.95, 0.93, 0.35), 1.6, true)
	if _text_font == null or _source_line.is_empty():
		return
	var offsets: Array[Vector2] = [
		Vector2(18, 36), Vector2(w * 0.48, 30),
		Vector2(38, 78), Vector2(w * 0.47, 69),
		Vector2(17, 116), Vector2(w * 0.51, 108)
	]
	var colors: Array[Color] = [
		Color("#FFE7EA"), Color("#F6BFC5"), Color("#D9E1F4"),
		Color("#FFE2DD"), Color("#EDB5BD"), Color("#F5E9F0")
	]
	for index in range(offsets.size()):
		var pos: Vector2 = offsets[index]
		var max_width: float = w * 0.47 - 20.0
		draw_string(_text_font, pos, _source_line, HORIZONTAL_ALIGNMENT_LEFT,
			max_width, retaliation_font_size, colors[index])
