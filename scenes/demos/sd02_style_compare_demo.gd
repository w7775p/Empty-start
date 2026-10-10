extends Control

# SD-02 三种独立美术样式预览，不接管正式对白组件。
const HAMSTER: Texture2D = preload("res://assets/characters/player/hamster_idle.png")
const DESIGNS: Array[String] = ["A  /  LIGHT CHAT", "B  /  POP COMIC", "C  /  MANGA SPEECH"]
const CHINESE: Array[String] = ["轻量短句 · DELTARUNE", "侧边对白卡 · Hi-Fi RUSH", "漫画主气泡 · TWEWY"]
const BG: Color = Color("#0B1221")
const PANEL: Color = Color("#182233")
const CX: Array[float] = [38.0, 658.0, 1278.0]
const CW: float = 604.0
const CARD_X: float = 27.0
const CARD_W: float = 294.0
const BOTTOM: float = 929.0

const SAYINGS: Array[Array] = [
	["你们都在看我吗？", "神说我今天能赢。", "这把别眨眼！"],
	["今天的神谕很清楚：我会把你们全都说服。", "我已经感觉到，弹幕正在向我聚集。", "这把别眨眼！"],
	["大家说，信仰到底是什么？", "我把刚刚的神迹解释给你们听。", "不要怀疑，这并非巧合，也并非运气；神明正在通过我的直播间，向所有正在观看的人显现祂的意志。"]
]

var scenario: int = 0
var cards: Array[Dictionary] = []
var _text_nodes: Array[Label] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rebuild()


# 1/2/3 切换短、中、长三种句子，R 回放切换；始终复用正式仓鼠立绘。
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	if key.keycode in [KEY_1, KEY_2, KEY_3]:
		set_scenario(key.keycode - KEY_1)
	elif key.keycode == KEY_R or key.keycode == KEY_SPACE:
		set_scenario((scenario + 1) % SAYINGS.size())


func set_scenario(next_scenario: int) -> void:
	scenario = clampi(next_scenario, 0, SAYINGS.size() - 1)
	_rebuild()


# A/B/C 使用相同台词，最新发言在最下方，统一使用侧边安全区域。
func _rebuild() -> void:
	for node: Label in _text_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_text_nodes.clear()
	cards.clear()
	var phrases: Array = SAYINGS[scenario]
	for variant in range(3):
		var footer: float = BOTTOM
		for order in range(2, -1, -1):
			var main: bool = order == 2
			var font_size: int = 19 if main else 16
			if variant == 0:
				font_size = 20 if main else 16
			elif variant == 1:
				font_size = 20 if main else 17
			var width: float = CARD_W
			if variant == 2 and main:
				width = 312.0
			var pad_x: float = 23.0 if variant == 2 else 19.0
			var pad_y: float = 18.0 if variant == 2 else 13.0
			var text_width: float = width - pad_x * 2.0 - (12.0 if variant == 2 else 0.0)
			var font: Font = ThemeDB.fallback_font
			var calculated: Vector2 = font.get_multiline_string_size(
				str(phrases[order]), HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size
			)
			var height: float = maxf(48.0 if main else 43.0, calculated.y + 2.0 * pad_y + 7.0)
			var x: float = CX[variant] + CARD_X
			if variant == 1:
				x += 15.0
			var y: float = footer - height
			var card: Dictionary = {
				"variant": variant, "order": order, "text": str(phrases[order]),
				"main": main, "rect": Rect2(x, y, width, height),
				"pad_x": pad_x, "pad_y": pad_y, "font_size": font_size
			}
			cards.append(card)
			var label: Label = Label.new()
			label.text = str(phrases[order])
			label.add_theme_font_size_override("font_size", font_size)
			label.add_theme_color_override("font_color", _label_color(variant, main))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.position = Vector2(x + pad_x, y + pad_y)
			label.size = Vector2(text_width, height - pad_y * 2.0)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(label)
			_text_nodes.append(label)
			footer = y - (11.0 if variant == 2 else 9.0)
	queue_redraw()


func _label_color(variant: int, main: bool) -> Color:
	if variant == 0:
		return Color("#102332") if main else Color("#D4E0F4")
	if variant == 1:
		return Color("#131728")
	return Color("#2B2933") if main else Color("#59525B")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), BG)
	_draw_environment()
	for index in range(3):
		_draw_column(index)
	for card: Dictionary in cards:
		_draw_card(card)


func _draw_environment() -> void:
	# 在三种对比方案后方绘制低对比直播间网格。
	for i in range(0, 1920, 42):
		draw_line(Vector2(i, 0), Vector2(i, 1080), Color(1, 1, 1, 0.022), 1.0)
	for j in range(0, 1080, 42):
		draw_line(Vector2(0, j), Vector2(1920, j), Color(1, 1, 1, 0.019), 1.0)
	_draw_text("SD-02 / BUBBLE ART DIRECTION STUDY", Vector2(44, 47), 42, Color("#F9F4E8"))
	_draw_text("SAME HAMSTER · SAME THREE LINES · SAME VIEWPORT  /  GODOT 4.7.2", Vector2(47, 107), 19, Color("#9EAFBD"))
	_draw_text("1 SHORT    2 MEDIUM    3 LONG    R / SPACE NEXT SCENE", Vector2(45, 1032), 20, Color("#B8C8D4"))


func _draw_column(index: int) -> void:
	var x: float = CX[index]
	var frame: Rect2 = Rect2(x, 171, CW, 817)
	_round_box(frame, PANEL, Color("#46536A"), 2, 19)
	# Distinct top accent under the title.
	var accent: Color = [Color("#B9E5CC"), Color("#FFCF66"), Color("#EF9C96")][index]
	draw_rect(Rect2(x + 24, 182, CW - 48, 6), accent)
	_draw_text(DESIGNS[index], Vector2(x + 26, 225), 31, Color("#F8F2E8"))
	_draw_text(CHINESE[index], Vector2(x + 27, 268), 19, Color("#AFC3D2"))
	_draw_text("主播  ·  煲煲", Vector2(x + 335, 318), 22, Color("#FFEDD2"))
	# 保留真实角色透明立绘，验证气泡与面部遮挡关系。
	var portrait: Rect2 = Rect2(x + 228, 352, 356, 476)
	draw_texture_rect(HAMSTER, portrait, false)
	# Character foot / frame marker and viewing baseline.
	draw_line(Vector2(x + 20, 958), Vector2(x + CW - 20, 958), Color("#5F6A7B"), 1.0)
	_draw_text("LIVE   ·   233   ♡", Vector2(x + 32, 983), 16, accent)


func _draw_card(item: Dictionary) -> void:
	var variant: int = item.variant
	var main: bool = item.main
	var rect: Rect2 = item.rect
	match variant:
		0: _draw_light_chat(rect, main)
		1: _draw_pop_comic(rect, main)
		2: _draw_manga_card(rect, main)


# A 方案采用克制的游戏文字框，最新台词以薄荷绿强调。
func _draw_light_chat(rect: Rect2, main: bool) -> void:
	var body: Color = Color("#B9E5CC") if main else Color("#162439")
	var border: Color = Color("#F1F8F2") if main else Color("#75869C")
	_round_box(rect, body, border, 3.0 if main else 1.5, 5.0)
	if main:
		# 主台词尖尾控制在文字轨道内，避开仓鼠面部。
		draw_colored_polygon(PackedVector2Array([
			Vector2(rect.position.x + 13, rect.position.y - 7),
			Vector2(rect.position.x + 24, rect.position.y),
			Vector2(rect.position.x + 35, rect.position.y - 7)
		]), Color("#F1F8F2"))
		draw_rect(Rect2(rect.position.x - 4, rect.position.y + 14, 5, rect.size.y - 27), Color("#64CFAA"))


# B 方案使用错位剪纸造型、厚重阴影与高对比配色。
func _draw_pop_comic(rect: Rect2, main: bool) -> void:
	var palette: Color = Color("#FFCF66") if main else (Color("#FFB5C0") if rect.position.y < 750 else Color("#6FD7D8"))
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(rect.position.x + 14, rect.position.y),
		Vector2(rect.end.x, rect.position.y + 1),
		Vector2(rect.end.x - 8, rect.end.y - 7),
		Vector2(rect.end.x - 23, rect.end.y),
		Vector2(rect.position.x, rect.end.y - 5),
		Vector2(rect.position.x + 3, rect.position.y + 13)
	])
	var shadow: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in pts:
		shadow.append(p + Vector2(7, 8))
	draw_colored_polygon(shadow, Color("#080D18", 0.80))
	draw_colored_polygon(pts, palette)
	draw_polyline(pts, Color("#181527"), 4.0 if main else 2.5, true)
	if main:
		draw_rect(Rect2(rect.position.x + 14, rect.position.y - 11, 75, 17), Color("#232033"))
		_draw_text("LIVE!", Vector2(rect.position.x + 21, rect.position.y + 3), 14, Color("#FFF6E8"))


# C 方案只让最新发言使用完整漫画气泡，旧句转换为无尾旁注。
func _draw_manga_card(rect: Rect2, main: bool) -> void:
	if not main:
		_round_box(rect, Color("#F4EDE3"), Color("#6D5E66"), 2.0, 17.0)
		return
	var center: Vector2 = rect.position + rect.size * 0.5
	var rx: float = rect.size.x * 0.5
	var ry: float = rect.size.y * 0.5
	var ellipse: PackedVector2Array = PackedVector2Array()
	var shadow: PackedVector2Array = PackedVector2Array()
	for i in range(65):
		var a: float = float(i) / 64.0 * TAU
		var ca: float = cos(a)
		var sa: float = sin(a)
		var pt: Vector2 = center + Vector2(
			signf(ca) * pow(absf(ca), 0.55) * (rx - 2.0),
			signf(sa) * pow(absf(sa), 0.60) * (ry - 2.0)
		)
		ellipse.append(pt)
		shadow.append(pt + Vector2(5, 6))
	draw_colored_polygon(shadow, Color("#090E1B", 0.55))
	# 气泡尖尾朝向角色嘴部，但不覆盖眼睛。
	var a: Vector2 = Vector2(rect.end.x - 33, rect.position.y + rect.size.y * 0.36)
	var b: Vector2 = Vector2(rect.end.x - 14, rect.position.y + rect.size.y * 0.59)
	var tip: Vector2 = Vector2(rect.end.x + 38, rect.position.y - 47)
	var triangle: PackedVector2Array = PackedVector2Array([a, tip, b])
	draw_colored_polygon(triangle, Color("#FFF8EC"))
	draw_polyline(triangle, Color("#211B2A"), 3.4, true)
	draw_colored_polygon(ellipse, Color("#FFF8EC"))
	draw_polyline(ellipse, Color("#211B2A"), 3.4, true)
	draw_arc(center - Vector2(5, 2), minf(rx, ry) * 0.78, PI * 1.15, PI * 1.59, 24, Color(1, 1, 1, 0.65), 2.0, true)


func _round_box(r: Rect2, fill: Color, edge: Color, thick: float, radius: float) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(roundi(thick))
	style.set_corner_radius_all(roundi(radius))
	draw_style_box(style, r)


func _draw_text(content: String, at: Vector2, pixels: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, at, content, HORIZONTAL_ALIGNMENT_LEFT, -1, pixels, color)
