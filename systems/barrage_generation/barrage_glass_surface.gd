class_name BarrageGlassSurface
extends Control

@export_group("四种倾向")
@export var orthodox_color: Color = Color("#46bed6")
@export var heretical_color: Color = Color("#e75988")
@export var absurd_color: Color = Color("#f3bc5e")
@export var neutral_color: Color = Color("#96a4c8")
@export var repeat_color: Color = Color("#8894a6")

@export_group("玻璃底板")
@export_range(4.0, 26.0, 1.0) var corner_radius: float = 13.0
@export_range(0.1, 1.0, 0.05) var glass_alpha: float = 0.75
@export_range(0.0, 1.0, 0.05) var highlight_alpha: float = 0.30
@export_range(0.0, 1.0, 0.05) var repeat_alpha: float = 0.24
@export_range(1.0, 6.0, 0.5) var max_border_width: float = 3.0

var _tendency: String = "neutral"
var _strength: int = 1
var _is_repeat: bool = false
var _glass_style: StyleBoxFlat = StyleBoxFlat.new()


# 从运行记录读取倾向、强度和复读标识，重算当前玻璃材质，不复制战斗事实。
func configure(tendency: String, strength: int, is_repeat: bool) -> void:
	_tendency = tendency
	_strength = clampi(strength, 1, 3)
	_is_repeat = is_repeat
	_rebuild_style()
	queue_redraw()


# 导出只读的展示色，供外侧 Label 与富文本使用一致的材质家族。
func get_base_tint() -> Color:
	if _is_repeat:
		return repeat_color
	match _tendency:
		"orthodox":
			return orthodox_color
		"heretical":
			return heretical_color
		"absurd":
			return absurd_color
		_:
			return neutral_color


# 玻璃颜色与边框随强度变化，普通复读保持灰色低对比。
func _rebuild_style() -> void:
	var tint: Color = get_base_tint()
	var intensity: float = float(_strength - 1) / 2.0
	var fill: Color = Color("#0a1325").lerp(tint, 0.32 + intensity * 0.20)
	fill.a = repeat_alpha if _is_repeat else glass_alpha + intensity * (1.0 - glass_alpha) * 0.62
	var edge: Color = tint.lightened(0.19 + intensity * 0.17)
	edge.a = 0.33 if _is_repeat else 0.55 + intensity * 0.35
	_glass_style.bg_color = fill
	_glass_style.border_color = edge
	var width: int = 1 if _is_repeat else roundi(1.0 + intensity * (max_border_width - 1.0))
	_glass_style.set_border_width_all(width)
	_glass_style.set_corner_radius_all(roundi(corner_radius))
	_glass_style.shadow_color = Color(tint.r * 0.25, tint.g * 0.25, tint.b * 0.25, 0.12 + intensity * 0.18)
	_glass_style.shadow_size = 1 + int(intensity * 3.0)


# 圆角玻璃、内高光、厚度与纵向层次使用轻量 CanvasItem 绘制。
func _draw() -> void:
	if _glass_style.bg_color.a <= 0.001 or size.x < 26.0 or size.y < 22.0:
		return
	draw_style_box(_glass_style, Rect2(Vector2.ZERO, size))
	var tint: Color = get_base_tint()
	var strength_factor: float = float(_strength - 1) * 0.5
	var light: Color = Color.WHITE
	light.a = (highlight_alpha + strength_factor * 0.16) * (0.50 if _is_repeat else 1.0)
	# 高光位于圆角内侧，给透明彩色塑料形成一条清楚的顶部亮带。
	draw_line(Vector2(corner_radius + 3.0, 5.5), Vector2(size.x - corner_radius - 3.0, 5.5), light, 2.0, true)
	var gloss: Color = tint.lightened(0.60)
	gloss.a = light.a * 0.27
	draw_rect(Rect2(9.0, 9.0, maxf(2.0, size.x - 18.0), maxf(2.0, size.y * 0.24)), gloss)
	# 内底缘沿用色系，玻璃厚度只占一条细线，避免文字受干扰。
	var bottom: Color = tint.darkened(0.30)
	bottom.a = 0.20 if _is_repeat else 0.32 + strength_factor * 0.15
	draw_line(Vector2(corner_radius + 2.0, size.y - 5.0), Vector2(size.x - corner_radius - 2.0, size.y - 5.0), bottom, 1.5, true)
