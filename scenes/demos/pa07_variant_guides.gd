extends Control

## 演示专用标尺：三栏使用同样的空间、距离、时间，只对比弹体美术。
var phase: float = 0.0
const TITLES := ["A", "B", "C"]
const LEFTS := [72.0, 672.0, 1272.0]
const INK := Color("#101522")

func _draw() -> void:
	for i in range(3):
		var left: float = LEFTS[i]
		var card := Rect2(left, 237, 575, 668)
		draw_rect(card, Color("#0b1323", 0.74))
		draw_rect(card, Color("#90b2d6", 0.32), false, 2.0)
		draw_rect(Rect2(left, 237, 575, 9), [Color("#f5b546"), Color("#4bcffb"), Color("#fa6a8b")][i], true)
		# 对照用的真实飞行方向辅助线与正式准星所在的发射起点。
		var source := Vector2(left+116, 592)
		var target := Vector2(left+380, 592)
		draw_line(source, target, Color("#81b5d4", 0.14), 2.0)
		draw_arc(source, 33, 0.0, TAU, 64, Color("#f4d682", 0.78), 2.5, true)
		draw_arc(source, 48, 0.0, TAU, 64, Color("#f4d682", 0.20), 1.5, true)
		draw_line(source+Vector2(-12,0),source+Vector2(12,0),Color("#efdf9f",0.9),2)
		draw_line(source+Vector2(0,-12),source+Vector2(0,12),Color("#efdf9f",0.9),2)
		draw_circle(source, 3, Color("#fff3c7"))
		if phase >= 0.96:
			_draw_impact(target, i, minf(1.0, (1.06 - phase)*14.0))


# 到达瞬间的简短比较冲击；正式命中碎裂仍由 PA-06 拥有。
func _draw_impact(center: Vector2, style: int, alpha: float) -> void:
	var tint: Color = [Color("#fbbd52"), Color("#73e7ff"), Color("#ff80a0")][style]
	tint.a *= clampf(alpha, 0.0, 1.0)
	var r := 63.0 if style == 1 else 55.0
	if style == 1:
		draw_arc(center, r*0.72, 0, TAU, 48, tint, 8, true)
	else:
		var blades := 11 if style == 2 else 8
		for j in range(blades):
			var angle := TAU * float(j)/float(blades)
			var direction := Vector2.from_angle(angle)
			draw_line(center+direction*22, center+direction*r, tint, 5 if style == 0 else 7, true)
	draw_circle(center, 20, Color(1.0, 1.0, 0.90, 0.15 * alpha))


func set_phase(new_phase: float) -> void:
	phase = new_phase
	queue_redraw()
