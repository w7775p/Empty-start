extends Control

## PA-09 真实游戏质感的演出环境；这里只绘制预览 HUD，战斗和 PK 的唯一事实来自其他系统。
@export var visual_style: int = 0
var preview_event: int = 0
const PALE := Color("#f8f3e4")
const INK := Color("#101421")
const TINTS := [Color("#dab777"), Color("#ed394e"), Color("#41d6d9")]


func select_style(next_style: int, next_event: int) -> void:
	visual_style = next_style
	preview_event = next_event
	queue_redraw()


func _draw() -> void:
	var primary: Color = TINTS[visual_style]
	var second: Color = [Color("#f1dba2"),Color("#ffffff"),Color("#f99cce")][visual_style]
	# 中央战斗区宽度及角色侧区与正式 1920 设计口径一致。
	_panel(Rect2(17, 170, 359, 740), Color(0.04,0.071,0.115,0.78), primary * Color(1,1,1,0.6))
	_panel(Rect2(384, 170, 1150, 740), Color(0.038,0.060,0.105,0.52), primary * Color(1,1,1,0.28))
	_panel(Rect2(1542, 170, 359, 740), Color(0.04,0.071,0.115,0.78), primary * Color(1,1,1,0.6))
	# 顶部 PK 蓝色玩家与粉色对手，各档额外留空间给本发数值浮字。
	_panel(Rect2(355, 53, 1210, 97), Color(0.035,0.059,0.085,0.88), primary*Color(1,1,1,0.70))
	draw_rect(Rect2(457, 91, 506, 24),Color("#13364e"),true)
	draw_rect(Rect2(966, 91, 492, 24),Color("#44203b"),true)
	draw_rect(Rect2(457, 91, 415, 24), Color("#54c5db"),true)
	draw_rect(Rect2(966, 91, 280, 24), Color("#fa6c89"),true)
	draw_rect(Rect2(457, 90, 1002, 26),primary*Color(1,1,1,0.65),false,2)
	draw_rect(Rect2(956, 68, 18, 67),INK,true)
	draw_rect(Rect2(966, 68, 6, 67),second,true)
	# 左右双方顶部直播区的轻描边和信息分区。
	_panel(Rect2(39, 774, 316, 116), Color(0.024,0.048,0.077,0.84), primary*Color(1,1,1,0.38))
	_panel(Rect2(1566, 774, 313, 116), Color(0.024,0.048,0.077,0.84), primary*Color(1,1,1,0.38))
	draw_rect(Rect2(384, 915, 1150, 7), primary*Color(1,1,1,0.68))
	if visual_style == 0:
		# Hades 的轻量古铜线条：视觉冲击主要来自字的纵向运动。
		for x in [35.0, 365.0, 1549.0, 1891.0]:
			draw_line(Vector2(x,202),Vector2(x,896),Color("#c4a467",0.27),1.5,true)
		draw_arc(Vector2(959, 103),43,0,TAU,64,Color("#d8b878",0.60),2,true)
	elif visual_style == 1:
		# Persona 风格的局部黑白斜角、红色卡边，只占画面四角。
		_poly([Vector2(382,171),Vector2(605,171),Vector2(559,190),Vector2(383,190)],Color("#e8374d"))
		_poly([Vector2(1530,910),Vector2(1364,910),Vector2(1408,889),Vector2(1533,889)],Color("#ffffff"))
		_poly([Vector2(20,188),Vector2(104,171),Vector2(60,220),Vector2(20,229)],Color("#e8374d"))
	else:
		# Hi-Fi RUSH 风格：局部乐拍标记、霓虹小点与带错位描边的色条。
		draw_rect(Rect2(384, 187, 1147, 12), Color("#fcb04e"))
		for j in range(12):
			draw_circle(Vector2(434 + j*92, 211), 2.8, Color("#bff9e5", 0.45))
		draw_rect(Rect2(18, 170, 16, 742), Color("#f6ae53",0.82))
		draw_rect(Rect2(1875, 170, 23, 742), Color("#e963a3",0.82))


func _panel(rect: Rect2, fill_color: Color, outline: Color) -> void:
	draw_rect(rect,fill_color,true)
	draw_rect(rect,outline,false,2.0)


func _poly(points: Array[Vector2], tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points),tint)
