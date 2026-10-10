extends BarrageGlassSurface

# 强度样式仅用于视觉预览：关注程度来自清晰的板身、外发光和缓慢呼吸。
var _tier: int = 1
var _pulse_clock: float = 0.0
var _redraw_elapsed: float = 0.0


# 战斗运行记录决定倾向与强度；背景光晕不参与命中、容量及生命周期。
func configure(tendency: String, strength: int, is_repeat: bool) -> void:
	super.configure(tendency, strength, is_repeat)
	_tier = clampi(strength, 1, 3)
	var tint: Color = get_base_tint()
	var level: int = _tier - 1
	# S1 透出场景；S2 形成清晰玻璃；S3 亮面显色并成为场上高价值目标。
	var fill: Color = Color("#101622").lerp(tint, [0.16, 0.38, 0.62][level])
	fill.a = [0.66, 0.84, 0.95][level]
	_glass_style.bg_color = fill
	var edge: Color = tint.lightened([0.18, 0.39, 0.60][level])
	edge.a = [0.36, 0.77, 1.0][level]
	_glass_style.border_color = edge
	_glass_style.set_border_width_all([1, 2, 3][level])
	# 彩色外扩光晕提供强度认知，整圈柔光代替刻痕与层叠硬框。
	var bloom: Color = tint.lightened(0.38)
	bloom.a = [0.0, 0.34, 0.63][level]
	_glass_style.shadow_color = bloom
	_glass_style.shadow_size = [0, 8, 17][level]
	_glass_style.shadow_offset = Vector2.ZERO
	queue_redraw()


# S3 缓慢呼吸，约每秒 24 次更新绘制，减少同屏多条弹幕的无效刷新。
func _process(delta: float) -> void:
	if _tier != 3:
		return
	_pulse_clock += delta
	_redraw_elapsed += delta
	if _redraw_elapsed >= 1.0 / 24.0:
		_redraw_elapsed = 0.0
		queue_redraw()


# 保持平整完整的亮面玻璃：强度越高，边缘越亮、柔光越强，无刻痕装饰。
func _draw() -> void:
	if size.x < 30.0 or size.y < 20.0:
		return
	var highlight_level: float = float(_tier - 1) * 0.5
	if _tier == 3:
		# 呼吸振幅温和，形成持续可被余光感知的注意力引导。
		var pulse: float = 0.5 + 0.5 * sin(_pulse_clock * 3.4)
		var glow: Color = _glass_style.shadow_color
		glow.a = lerpf(0.40, 0.72, pulse)
		_glass_style.shadow_color = glow
		_glass_style.shadow_size = roundi(lerpf(13.0, 20.0, pulse))
	draw_style_box(_glass_style, Rect2(Vector2.ZERO, size))

	# 上缘局部漫反射与平缓亮度层次：连续光面，避免尖角划痕与按钮式硬高光。
	var light: Color = Color(1.0, 1.0, 1.0, 0.07 + 0.16 * highlight_level)
	var inset: float = maxf(12.0, corner_radius + 5.0)
	draw_rect(Rect2(inset, 6.0, maxf(1.0, size.x - inset * 2.0), 2.5), light)
