extends Control

## PA-09 三种动态反馈视觉提案：展示命中点、PK、主播受击。只消费演示事实，不改变 PK。
enum Style { HADES, PERSONA, HIFI }
enum Event { NORMAL, BLOCK, REFLECT, MULTI_NEGATIVE, MISS }

@export var style: Style = Style.HADES
@export_range(0.25, 2.5, 0.05) var effect_scale: float = 1.0
@export_range(0.2, 2.0, 0.05) var lifetime: float = 1.3
@export_range(5.0, 95.0, 1.0) var float_distance: float = 35.0
@export var positive_color: Color = Color("#aaf4c8")
@export var negative_color: Color = Color("#ff8d72")

const COMIC_PATH := "res://assets/ui/combat/feedback/player_hit_comic_01.png"
const WHITE := Color("#fff7eb")
const INK := Color("#121527")
const CANVAS_DIM := Vector2(1920, 1080)

var event_kind: Event = Event.NORMAL
var _elapsed: float = 0.0
var _running: bool = true
var _local: Label
var _secondary: Label
var _pk: Label
var _impact: Label
var _comic: TextureRect
var _multi_labels: Array[Label] = []


# 三版均使用同一组演示事实：普通 +8、遮挡 -6、反弹 -12、多目标净 -9、MISS 0。
func select_visual(next_style: int, next_event: int) -> void:
	style = next_style as Style
	event_kind = next_event as Event
	_elapsed = 0.0
	_running = true
	_build_labels()
	queue_redraw()


func seek_at(progress: float) -> void:
	_elapsed = clampf(progress, 0.0, 1.0) * lifetime
	_running = false
	_update_visuals()


func set_playing(active: bool) -> void:
	_running = active


func restart() -> void:
	_elapsed = 0.0
	_running = true


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed += delta
	if _elapsed >= lifetime + 0.48:
		_elapsed = 0.0
	_update_visuals()


# 主播漫符只在本发净 PK 为负时出现。多目标同发也仅一个节点。
func _build_labels() -> void:
	for child in get_children():
		child.queue_free()
	_local = _label("", 34, WHITE)
	_secondary = _label("", 25, WHITE)
	_pk = _label("", 34, WHITE)
	_impact = _label("", 38, WHITE)
	_multi_labels.clear()
	if event_kind == Event.MULTI_NEGATIVE:
		for text in ["HIT +3", "BLOCK -5"]:
			_multi_labels.append(_label(text, 25, WHITE))
	_comic = TextureRect.new()
	_comic.texture = load(COMIC_PATH) as Texture2D
	_comic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_comic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_comic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comic.size = Vector2(218, 244)
	_comic.position = Vector2(225, 508)
	_comic.pivot_offset = _comic.size * 0.5
	add_child(_comic)
	var main_text: String = ["HIT", "BLOCK", "REFLECT", "COMBO x3", "MISS"][event_kind]
	var caption: String = ["命中 +8", "遮挡 -6", "反弹 -12", "同发 3 目标", "未命中"][event_kind]
	var net_text: String = ["+8 PK", "-6 PK", "-12 PK", "-9 PK", "+0 PK"][event_kind]
	_local.text = main_text
	_secondary.text = caption
	_pk.text = net_text
	_impact.text = ["", "OUCH!", "OUCH!", "OUCH!", ""][event_kind]
	if style == Style.HADES:
		_tune(_local, 32, Color("#f4e1a8"), 4, Color("#172024"))
		_tune(_secondary, 23, Color("#e8dcc0"), 2, Color("#16202a"))
		_tune(_pk, 31, positive_color if event_kind == Event.NORMAL else negative_color, 4, Color("#13221b"))
		_tune(_impact, 29, Color("#f9c18d"), 4, INK)
	elif style == Style.PERSONA:
		_tune(_local, 43, WHITE, 8, INK)
		_tune(_secondary, 26, WHITE, 5, INK)
		_tune(_pk, 46, WHITE, 7, INK)
		_tune(_impact, 46, WHITE, 8, INK)
	else:
		_tune(_local, 40, Color("#fff4a9"), 7, INK)
		_tune(_secondary, 28, Color("#ffffff"), 5, INK)
		_tune(_pk, 44, Color("#ffeb83") if event_kind == Event.NORMAL else Color("#ff8fc2"), 7, INK)
		_tune(_impact, 50, Color("#ffcf4c"), 8, INK)
	for extra in _multi_labels:
		if style == Style.HADES:
			_tune(extra, 23, Color("#ffe6a8"), 3, INK)
		elif style == Style.PERSONA:
			_tune(extra, 30, WHITE, 6, INK)
		else:
			_tune(extra, 30, Color("#76f8ed"), 6, INK)
	_update_visuals()


func _label(caption: String, px: int, tint: Color) -> Label:
	var l := Label.new()
	l.text = caption
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _tune(l: Label, px: int, tint: Color, outline_px: int, outline_tint: Color) -> void:
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", tint)
	l.add_theme_constant_override("outline_size", outline_px)
	l.add_theme_color_override("font_outline_color", outline_tint)
	l.pivot_offset = Vector2(60, 22)


func _update_visuals() -> void:
	if _local == null:
		return
	var progress := clampf(_elapsed / lifetime, 0.0, 1.0)
	var appear := clampf(progress * 9.0, 0.0, 1.0)
	var vanish := clampf((1.0 - progress) * 3.0, 0.0, 1.0)
	var visibility := minf(appear, vanish)
	var beat := 1.0 + 0.19 * exp(-progress * 14.0) * sin(progress * 43.0)
	var negative := event_kind == Event.BLOCK or event_kind == Event.REFLECT or event_kind == Event.MULTI_NEGATIVE
	var local_x := 1040.0 if event_kind != Event.MISS else 888.0
	var local_y := 508.0 if event_kind != Event.MISS else 572.0
	var lift := progress * float_distance
	_local.position = Vector2(local_x, local_y - lift)
	_secondary.position = Vector2(local_x + 8, local_y + 56 - lift)
	_pk.position = Vector2(1066.0, 152.0 - progress * 30.0)
	_impact.position = Vector2(231, 637 - lift)
	_local.modulate.a = visibility
	_secondary.modulate.a = visibility * 0.96
	_pk.modulate.a = visibility
	_impact.modulate.a = visibility if negative else 0.0
	for i in range(_multi_labels.size()):
		var extra: Label = _multi_labels[i]
		extra.position = [Vector2(616, 445), Vector2(735, 705)][i] - Vector2(0, lift)
		extra.modulate.a = visibility
		extra.scale = Vector2.ONE * effect_scale
	_comic.visible = negative
	_comic.modulate.a = visibility * (0.72 if style == Style.HADES else 0.94)
	_comic.rotation = 0.0
	_local.rotation = 0.0
	_secondary.rotation = 0.0
	_pk.rotation = 0.0
	_local.scale = Vector2.ONE * effect_scale
	_secondary.scale = Vector2.ONE * effect_scale
	_pk.scale = Vector2.ONE * effect_scale
	_comic.scale = Vector2.ONE * effect_scale
	_comic.position = Vector2(225, 508)
	if style == Style.HADES:
		_local.position += Vector2(0, 8)
		_pk.position += Vector2(0, 5)
		_impact.position += Vector2(13, 10)
		_comic.scale *= 0.72 * beat
		_comic.position += Vector2(0, 12)
	elif style == Style.PERSONA:
		_local.rotation = -0.09
		_pk.rotation = -0.085
		_local.position += Vector2(-8, -10)
		_secondary.position += Vector2(0, 8)
		_comic.scale *= 0.94 * beat
		_comic.rotation = -0.10
		_impact.position += Vector2(6, -36)
		_impact.rotation = -0.12
	else:
		_local.rotation = -0.13
		_pk.rotation = 0.065
		_local.position += Vector2(-9, -8)
		_pk.position += Vector2(0, -16)
		_local.scale *= beat * 1.17
		_comic.scale *= beat * 1.18
		_comic.rotation = 0.055 * sin(progress * 50.0)
		_impact.position += Vector2(-6, -55)
		_impact.rotation = -0.13
	queue_redraw()


func _draw() -> void:
	var progress := clampf(_elapsed / lifetime, 0.0, 1.0)
	var opacity := minf(clampf(progress * 9.0, 0.0, 1.0), clampf((1.0-progress)*3.0, 0.0, 1.0))
	if opacity <= 0.0:
		return
	var negative := event_kind == Event.BLOCK or event_kind == Event.REFLECT or event_kind == Event.MULTI_NEGATIVE
	var at := Vector2(1032, 530) if event_kind != Event.MISS else Vector2(920, 600)
	if style == Style.HADES:
		# 细线花括号式命中强调与小范围 PK 发光，不覆盖可阅读弹幕。
		_line(at+Vector2(-9, -19), at+Vector2(-20, -41), Color(0.96,0.84,0.54,opacity*0.68), 2)
		_line(at+Vector2(24, -19), at+Vector2(35, -42), Color(0.96,0.84,0.54,opacity*0.55), 2)
		draw_arc(Vector2(1049, 172), 42, 0.2, 2.9, 22, Color(0.95,0.80,0.49,opacity*0.42), 2.5, true)
	elif style == Style.PERSONA:
		# 黑白斜切签配红色边角，让状态字像切进画面的实体纸片。
		var red := Color(0.95, 0.16, 0.25, opacity)
		var dark := Color(0.04, 0.045, 0.08, opacity)
		_poly([Vector2(1002,479),Vector2(1232,469),Vector2(1193,537),Vector2(990,548)],dark)
		_poly([Vector2(991,483),Vector2(1005,466),Vector2(1000,536),Vector2(981,549)],red)
		_poly([Vector2(1050,113),Vector2(1240,123),Vector2(1208,191),Vector2(1034,183)],red)
		_poly([Vector2(1055,116),Vector2(1215,125),Vector2(1195,178),Vector2(1046,179)],dark)
		if negative:
			_poly([Vector2(208,559),Vector2(422,534),Vector2(439,671),Vector2(207,672)],red*Color(1,1,1,0.43))
	else:
		# 节奏漫画：短促锯齿星爆与稀疏半色调点，主漫符局限在仓鼠立绘周围。
		var cyan := Color(0.37, 0.88, 0.91, opacity * 0.90)
		var hot := Color(1.0, 0.41, 0.61, opacity * 0.88)
		_star(at + Vector2(58, -14), 17, 38, 9, cyan)
		for i in range(13):
			var angle := TAU * float(i) / 13.0
			var direction := Vector2.from_angle(angle)
			_line(at + direction * 48, at + direction * (76 + (i%3)*8), cyan if i%2==0 else hot, 5.5)
		if negative:
			_star(Vector2(313, 633), 94, 144, 12, hot * Color(1,1,1,0.24))
			for row in range(5):
				for col in range(5):
					var p := Vector2(91 + col*31, 618 + row*26)
					draw_circle(p, 2.6 + 0.8*((col+row)%2), Color(1,0.92,0.65,opacity*0.45))


func _poly(points: Array[Vector2], tint: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), tint)


func _line(a: Vector2, b: Vector2, tint: Color, thickness: float) -> void:
	draw_line(a,b,tint,thickness,true)


func _star(center: Vector2, inner_radius: float, outer_radius: float, spikes: int, tint: Color) -> void:
	var poly := PackedVector2Array()
	for i in range(spikes * 2):
		var radius := outer_radius if i%2==0 else inner_radius
		poly.append(center + Vector2.from_angle(-PI/2 + PI*i/float(spikes))*radius)
	draw_colored_polygon(poly,tint)
