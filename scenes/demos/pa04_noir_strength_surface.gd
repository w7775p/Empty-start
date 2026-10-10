extends BarrageGlassSurface

# 仅供方案预览；通过同一个 BarrageGlassSurface 对外接口展示三档玻璃结构。
# 选定后由 PA-04 组件负责人把样式迁入正式材质。
var _tier: int = 1


# 外部运行记录仍决定强度和倾向，禁止另造战斗数值。
func configure(tendency: String, strength: int, is_repeat: bool) -> void:
	super.configure(tendency, strength, is_repeat)
	_tier = clampi(strength, 1, 3)
	queue_redraw()


# 不使用整条水平按钮高光，改用切角反射、内沿折光和分层边缘。
func _draw() -> void:
	if size.x < 30.0 or size.y < 20.0:
		return
	# Glass base and strength-aware border are provided by the original surface.
	draw_style_box(_glass_style, Rect2(Vector2.ZERO, size))
	var tint: Color = get_base_tint()
	var rim: Color = tint.lightened(0.48)
	var w: float = size.x
	var h: float = size.y
	var tier_ratio: float = float(_tier - 1) * 0.5

	# All tiers: an upper-right light reflection; no left-side stripe.
	var edge_reflect: Color = Color.WHITE
	edge_reflect.a = 0.14 + tier_ratio * 0.34
	draw_line(Vector2(w * 0.73, 3.7), Vector2(w - 16.0, 3.7), edge_reflect, 1.1 + tier_ratio * 0.75, true)
	var bottom: Color = tint.darkened(0.35)
	bottom.a = 0.20 + tier_ratio * 0.35
	draw_line(Vector2(15.0, h - 4.0), Vector2(w - 15.0, h - 4.0), bottom, 1.0 + tier_ratio, true)

	if _tier >= 2:
		# S2: two subtle, slanted facets in the upper-right, kept outside text baseline.
		var sheen: Color = rim
		sheen.a = 0.22 if _tier == 2 else 0.39
		draw_colored_polygon(PackedVector2Array([
			Vector2(w - 59.0, 6.0), Vector2(w - 39.0, 6.0),
			Vector2(w - 57.0, 15.0), Vector2(w - 72.0, 15.0)
		]), sheen)
		var corner: Color = Color.WHITE
		corner.a = 0.17 if _tier == 2 else 0.35
		draw_line(Vector2(w - 17.0, 8.0), Vector2(w - 9.0, 16.0), corner, 1.2, true)

	if _tier >= 3:
		# S3: continuous inset rim for a deep cut-glass look; symmetrical around the panel.
		var inner: StyleBoxFlat = StyleBoxFlat.new()
		inner.bg_color = Color.TRANSPARENT
		inner.border_color = rim
		inner.border_color.a = 0.55
		inner.set_border_width_all(1)
		inner.set_corner_radius_all(maxi(3, roundi(corner_radius - 4.0)))
		draw_style_box(inner, Rect2(5.0, 5.0, w - 10.0, h - 10.0))
		# The polished underside provides glass thickness without covering glyphs.
		var depth: Color = Color.WHITE
		depth.a = 0.31
		draw_line(Vector2(16.0, h - 7.5), Vector2(w - 16.0, h - 7.5), depth, 1.0, true)
		# Short diagonal-cut reflections keep the entire left edge quiet.
		var diamond: Color = rim
		diamond.a = 0.65
		draw_line(Vector2(w - 34.0, 7.0), Vector2(w - 43.0, 17.0), diamond, 1.9, true)
		draw_line(Vector2(w - 23.0, 7.0), Vector2(w - 32.0, 17.0), diamond, 1.5, true)
