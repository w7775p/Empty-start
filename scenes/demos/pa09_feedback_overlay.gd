extends Control

## PA-09 仅显示必要的异常结果词与准星旁整发净值。
## 此场景只消费演示值，游戏内 PK 的真实数据归战斗结算系统。
enum Style { CLEAN, INK, IMPACT }
enum Case { SMALL, LARGE, BLOCK, REFLECT, MULTI, MISS }

@export_group("准星旁数值")
@export_range(18, 60, 1) var minimum_font_size: int = 28
@export_range(40, 110, 1) var maximum_font_size: int = 78
@export_range(0.05, 2.0, 0.05) var effect_seconds: float = 1.05
@export_range(10, 70, 1) var float_distance: float = 34.0
@export var positive_color: Color = Color("#aff7db")
@export var negative_color: Color = Color("#ff8a82")

const INK := Color("#211a20")
const PALE := Color("#fff5e8")
const CASE_DELTA := [2, 8, -12, -17, -24, 0]

var style: Style = Style.CLEAN
var case_id: Case = Case.BLOCK
var aim_center: Vector2 = Vector2(945, 655)
var target_positions: Array[Vector2] = [Vector2(1084, 457), Vector2(810, 602), Vector2(1304, 700)]
var _elapsed: float = 0.0
var _playing: bool = true
var _labels: Array[Label] = []
var _number: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number = _new_label()
	preview(0, 2)


# 选型与样例类型只驱动临时表现，不修改现有战斗状态。
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


func _new_label() -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_outline_color", INK)
	add_child(label)
	return label


# 本发结算绝对值越大，字号及阴影越重。
func _font_size_for(delta: int) -> int:
	return clampi(roundi(float(minimum_font_size) + sqrt(float(absi(delta))) * 9.3), minimum_font_size, maximum_font_size)


func _build_labels() -> void:
	for label in _labels:
		label.queue_free()
	_labels.clear()
	var net: int = CASE_DELTA[case_id]
	_number.visible = net != 0
	_number.text = "%+d" % net
	_number.add_theme_font_size_override("font_size", _font_size_for(net))
	_number.add_theme_color_override("font_color", positive_color if net >= 0 else negative_color)
	_number.add_theme_constant_override("outline_size", 3 if style == Style.CLEAN else 5)
	_number.add_theme_color_override("font_outline_color", INK)
	_number.add_theme_color_override("font_shadow_color", Color(0.06, 0.02, 0.08, clampf(0.24 + absf(float(net)) / 31.0, 0.24, 0.95)))
	_number.add_theme_constant_override("shadow_outline_size", clampi(roundi(2.0 + sqrt(float(absi(net))) * 3.9), 2, 24))
	_number.add_theme_constant_override("shadow_offset_x", clampi(roundi(float(absi(net)) * 0.22), 2, 8))
	_number.add_theme_constant_override("shadow_offset_y", clampi(roundi(float(absi(net)) * 0.28), 3, 10))
	if style == Style.INK:
		_number.add_theme_color_override("font_color", PALE if net >= 0 else Color("#fff1de"))
		_number.add_theme_color_override("font_outline_color", Color("#a3414b") if net < 0 else Color("#1d3b34"))
	elif style == Style.IMPACT:
		_number.add_theme_color_override("font_color", Color("#c6fff3") if net >= 0 else Color("#ffde88"))
		_number.add_theme_color_override("font_outline_color", Color("#1b1428"))

	# 普通命中只看准星数值，特殊异常才需要额外局部结果词。
	var captions: Array[String] = []
	var positions: Array[Vector2] = []
	match case_id:
		Case.BLOCK:
			captions = ["BLOCK"]
			positions = [target_positions[0]]
		Case.REFLECT:
			captions = ["REFLECT"]
			positions = [target_positions[0]]
		Case.MULTI:
			captions = ["BLOCK", "REFLECT"]
			positions = [target_positions[1], target_positions[2]]
		Case.MISS:
			captions = ["MISS"]
			positions = [aim_center + Vector2(32, 22)]
	for i in range(captions.size()):
		var label := _new_label()
		label.text = captions[i]
		label.set_meta("base_position", positions[i])
		label.add_theme_font_size_override("font_size", 24 if style == Style.CLEAN else 31)
		label.add_theme_color_override("font_color", Color("#e9eced") if style == Style.CLEAN else (Color("#f8f6df") if style == Style.INK else Color("#fff5ad")))
		label.add_theme_constant_override("outline_size", 3 if style == Style.CLEAN else 5)
		label.add_theme_color_override("font_outline_color", Color("#1e232b"))
		_labels.append(label)
	_apply_time(_elapsed)


func _apply_time(seconds: float) -> void:
	var p := clampf(seconds / effect_seconds, 0.0, 1.0)
	var rise := 1.0 - pow(1.0 - p, 3)
	var appear := clampf(p * 13.0, 0.0, 1.0)
	var fade := clampf((1.0 - p) * 4.0, 0.0, 1.0)
	var alpha := minf(appear, fade)
	var impact := 1.0 + 0.24 * exp(-p * 12.0) * sin(p * 36.0)
	_number.position = aim_center + Vector2(65, -76 - float_distance * rise)
	_number.pivot_offset = Vector2(23, 20)
	_number.rotation = -0.10 if style == Style.INK else (-0.07 if style == Style.IMPACT else 0.0)
	_number.scale = Vector2.ONE * (impact if style == Style.IMPACT else (1.0 + 0.08 * exp(-p * 12.0)))
	_number.modulate.a = alpha
	for label in _labels:
		var anchor: Vector2 = label.get_meta("base_position")
		label.position = anchor + Vector2(0, -19 * rise)
		label.rotation = -0.09 if style == Style.INK else 0.0
		label.modulate.a = alpha
