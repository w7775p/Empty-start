extends Control

## PA-09 局部表现三套试样：同一个准星、同一批弹幕和正式漫画受击素材。
## 本组件只展示注入的结算样例；数值只以绝对值控制字号、阴影强度。
enum Style { CLEAN, INK, IMPACT }
enum Case { SMALL, LARGE, BLOCK, REFLECT, MULTI, MISS }

@export_group("准星数值")
@export_range(18, 60, 1) var minimum_font_size: int = 28
@export_range(40, 110, 1) var maximum_font_size: int = 78
@export_range(0.05, 2.0, 0.05) var effect_seconds: float = 1.05
@export_range(10, 70, 1) var float_distance: float = 34.0
@export var positive_color: Color = Color("#aff7db")
@export var negative_color: Color = Color("#ff8a82")
@export_group("主角受击")
@export var comic_texture: Texture2D = preload("res://assets/ui/combat/feedback/player_hit_comic_01.png")
@export var comic_offset: Vector2 = Vector2(326, 344)
@export_range(70, 250, 1) var comic_size: float = 174.0

const INK := Color("#211a20")
const PALE := Color("#fff5e8")
const CASE_DELTA := [2, 8, -12, -17, -24, 0]
const CASE_TEXT := ["HIT", "HIT", "BLOCK", "REFLECT", "BLOCK", "MISS"]

var style: Style = Style.CLEAN
var case_id: Case = Case.BLOCK
var aim_center: Vector2 = Vector2(945, 655)
var target_positions: Array[Vector2] = [Vector2(1084, 457), Vector2(810, 602), Vector2(1304, 700)]
var _elapsed: float = 0.0
var _playing: bool = true
var _labels: Array[Label] = []
var _number: Label
var _comic: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_children()
	preview(0, 2)


# 入参是显示样例，不触碰 CombatAttack / HitResolution / Sandbox 里的 PK。
func preview(next_style: int, next_case: int) -> void:
	style = next_style as Style
	case_id = next_case as Case
	_elapsed = 0.0
	_playing = true
	_build_labels()
	_apply_time(0.0)


func seek_at(progress: float) -> void:
	_elapsed = clampf(progress, 0.0, 1.0) * effect_seconds
	_playing = false
	_apply_time(_elapsed)


func toggle_pause() -> void:
	_playing = not _playing


func replay() -> void:
	_elapsed = 0.0
	_playing = true


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	if _elapsed > effect_seconds + 0.55:
		_elapsed = 0.0
	_apply_time(_elapsed)


func _make_children() -> void:
	_number = _new_label()
	_comic = TextureRect.new()
	_comic.texture = comic_texture
	_comic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_comic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_comic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_comic)


func _new_label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", INK)
	add_child(label)
	return label


func _font_size_for(delta: int) -> int:
	return clampi(roundi(float(minimum_font_size) + sqrt(float(absi(delta))) * 9.3), minimum_font_size, maximum_font_size)


func _build_labels() -> void:
	for label in _labels:
		label.queue_free()
	_labels.clear()
	var net: int = CASE_DELTA[case_id]
	_number.text = ("%+d" % net) if net != 0 else "0"
	var size_px := _font_size_for(net)
	_number.add_theme_font_size_override("font_size", size_px)
	_number.add_theme_color_override("font_color", positive_color if net >= 0 else negative_color)
	_number.add_theme_constant_override("outline_size", 3 if style == Style.CLEAN else 5)
	_number.add_theme_color_override("font_shadow_color", Color(0.06, 0.02, 0.08, clampf(0.24 + absf(float(net)) / 31.0, 0.24, 0.95)))
	_number.add_theme_constant_override("shadow_outline_size", clampi(roundi(2.0 + sqrt(float(absi(net))) * 3.9), 2, 24))
	_number.add_theme_constant_override("shadow_offset_x", 2 if net == 0 else clampi(roundi(float(absi(net)) * 0.22), 2, 8))
	_number.add_theme_constant_override("shadow_offset_y", 3 if net == 0 else clampi(roundi(float(absi(net)) * 0.28), 3, 10))
	if style == Style.INK:
		_number.add_theme_color_override("font_color", PALE if net >= 0 else Color("#fff1de"))
		_number.add_theme_color_override("font_outline_color", Color("#a3414b") if net < 0 else Color("#1d3b34"))
	elif style == Style.IMPACT:
		_number.add_theme_color_override("font_color", Color("#c6fff3") if net >= 0 else Color("#ffde88"))
		_number.add_theme_color_override("font_outline_color", Color("#1b1428"))
	var captions: Array[String] = []
	var positions: Array[Vector2] = []
	if case_id == Case.MULTI:
		captions = ["HIT", "BLOCK", "REFLECT"]
		positions = target_positions.duplicate()
	elif case_id == Case.MISS:
		captions = ["MISS"]
		positions = [aim_center + Vector2(32, 22)]
	else:
		captions = [CASE_TEXT[case_id]]
		positions = [target_positions[0]]
	for i in range(captions.size()):
		var label := _new_label()
		label.text = captions[i]
		label.set_meta("base_position", positions[i])
		label.add_theme_font_size_override("font_size", 24 if style == Style.CLEAN else 31)
		label.add_theme_color_override("font_color", Color("#e9eced") if style == Style.CLEAN else (Color("#f8f6df") if style == Style.INK else Color("#fff5ad")))
		label.add_theme_constant_override("outline_size", 3 if style == Style.CLEAN else 5)
		label.add_theme_color_override("font_outline_color", Color("#1e232b"))
		_labels.append(label)
	_comic.visible = net < 0
	_comic.size = Vector2(comic_size, comic_size * 1.14)
	_comic.pivot_offset = _comic.size * 0.5
	_apply_time(_elapsed)


# 准星浮字与命中点结果词彼此独立；左侧漫画只看整发净 PK 的正负。
func _apply_time(seconds: float) -> void:
	var p := clampf(seconds / effect_seconds, 0.0, 1.0)
	var rise := 1.0 - pow(1.0 - p, 3)
	var appear := clampf(p * 13.0, 0.0, 1.0)
	var fade := clampf((1.0 - p) * 4.0, 0.0, 1.0)
	var alpha := minf(appear, fade)
	var impact := 1.0 + 0.24 * exp(-p * 12.0) * sin(p * 36.0)
	var delta: int = CASE_DELTA[case_id]
	_number.position = aim_center + Vector2(65, -76 - float_distance * rise)
	_number.pivot_offset = Vector2(23, 20)
	_number.rotation = -0.10 if style == Style.INK else (-0.07 if style == Style.IMPACT else 0.0)
	_number.scale = Vector2.ONE * (impact if style == Style.IMPACT else (1.0 + 0.08 * exp(-p*12.0)))
	_number.modulate.a = alpha
	for i in range(_labels.size()):
		var label := _labels[i]
		var anchor: Vector2 = label.get_meta("base_position")
		label.position = anchor + Vector2(0, -19 * rise)
		label.rotation = -0.09 if style == Style.INK else 0.0
		label.scale = Vector2.ONE * (impact if style == Style.IMPACT else 1.0)
		label.modulate.a = alpha
	_comic.visible = delta < 0
	_comic.position = comic_offset + Vector2(0, -10 * rise)
	_comic.rotation = (0.085 * sin(p*57.0) * (1.0-p)) if style != Style.CLEAN else 0.0
	_comic.scale = Vector2.ONE * (0.66 + 0.34 * minf(1.0, p * 11.0)) * (impact if style == Style.IMPACT else 1.0)
	_comic.modulate.a = alpha
	queue_redraw()


func _draw() -> void:
	var p := clampf(_elapsed / effect_seconds, 0.0, 1.0)
	var opacity := minf(clampf(p * 13.0, 0.0, 1.0), clampf((1.0-p)*4.0, 0.0, 1.0))
	if opacity <= 0.0 or style == Style.CLEAN:
		return
	var at := aim_center + Vector2(102, -53 - float_distance*(1.0-pow(1.0-p,3)))
	if style == Style.INK:
		# 局部的短斜切线只陪衬数值；不会生成任何新的 HUD 板块。
		var red := Color(0.97,0.36,0.37,opacity*0.7)
		draw_line(at+Vector2(-45,-29), at+Vector2(25,-40), red, 4.0, true)
		draw_line(at+Vector2(10,25), at+Vector2(47,18), red, 2.0, true)
	else:
		var shine := Color(0.98,0.76,0.35,opacity*0.8)
		for i in range(6):
			var direction := Vector2.from_angle(-0.9+float(i)*TAU/6.0)
			draw_line(at+direction*39, at+direction*56, shine, 2.5, true)
