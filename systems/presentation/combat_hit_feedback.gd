extends Control

## PA-09 仅显示必要的异常结果词与准星旁整发净值。
## 既可消费真实攻击结算，也能在独立演示中注入固定数值；PK 所有权不在本组件。
enum Style { CLEAN, INK, IMPACT }
enum Case { SMALL, LARGE, BLOCK, REFLECT, MULTI, MISS }

@export_group("准星旁数值")
@export_range(18, 60, 1) var minimum_font_size: int = 28
@export_range(40, 110, 1) var maximum_font_size: int = 90
@export_range(0.05, 2.0, 0.05) var effect_seconds: float = 1.05
@export_range(10, 70, 1) var float_distance: float = 34.0
@export var positive_color: Color = Color("#aff7db")
@export var negative_color: Color = Color("#ff8a82")
@export var runtime_style: Style = Style.CLEAN

const INK := Color("#211a20")
const PALE := Color("#fff5e8")
const CASE_DELTA := [2, 8, -12, -17, -24, 0]

var style: Style = Style.CLEAN
var case_id: Case = Case.BLOCK
var aim_center: Vector2 = Vector2(945, 655)
var target_positions: Array[Vector2] = [Vector2(1084, 457), Vector2(810, 602), Vector2(1304, 700)]
var target_rects: Array[Rect2] = []
var _elapsed: float = 0.0
var _playing: bool = true
var _labels: Array[Label] = []
var _number: Label
var _runtime_mode: bool = false
var _runtime_delta_pct: float = 0.0
var _runtime_missed: bool = false
var _runtime_outcomes: Array[Dictionary] = []
var _attack: AttackChargeInput
var _arrival_snapshot: AttackTargetSnapshot


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_number = _new_label()
	_number.visible = false
	_playing = false


# 选型与样例类型只驱动临时表现，不修改现有战斗状态。
func preview(next_style: int, next_case: int) -> void:
	_runtime_mode = false
	style = next_style as Style
	case_id = next_case as Case
	_elapsed = 0.0
	_playing = true
	_build_labels()
	_apply_time(0.0)


# 沙盒唯一接线：先缓存到达时的实际目标位置，再消费整发最终结算。
func bind_attack(attack: AttackChargeInput) -> void:
	if _attack != null and is_instance_valid(_attack):
		if _attack.shot_arrival_resolved.is_connected(_on_shot_arrival_resolved):
			_attack.shot_arrival_resolved.disconnect(_on_shot_arrival_resolved)
		if _attack.shot_hit_resolution_submitted.is_connected(_on_shot_hit_resolution_submitted):
			_attack.shot_hit_resolution_submitted.disconnect(_on_shot_hit_resolution_submitted)
	_attack = attack
	if _attack != null:
		_attack.shot_arrival_resolved.connect(_on_shot_arrival_resolved)
		_attack.shot_hit_resolution_submitted.connect(_on_shot_hit_resolution_submitted)


func clear_feedback() -> void:
	_arrival_snapshot = null
	_runtime_outcomes.clear()
	_number.visible = false
	_playing = false
	for label in _labels:
		label.queue_free()
	_labels.clear()
	queue_redraw()


func _on_shot_arrival_resolved(snapshot: AttackTargetSnapshot, target_results: Array[Dictionary]) -> void:
	_arrival_snapshot = snapshot
	_runtime_outcomes.clear()
	var local_from_canvas: Transform2D = get_global_transform_with_canvas().affine_inverse()
	for fact: Dictionary in target_results:
		var hit: BarrageTraitResult = fact.get("trait_result") as BarrageTraitResult
		var target: BarrageView = fact.get("target") as BarrageView
		if hit == null or target == null or not is_instance_valid(target):
			continue
		var caption: String = ""
		match hit.kind:
			BarrageTraitResult.Kind.OCCLUSION:
				caption = "BLOCK"
			BarrageTraitResult.Kind.REFLECT:
				caption = "REFLECT"
			BarrageTraitResult.Kind.FAKE_CARD:
				caption = "FAKE"
			BarrageTraitResult.Kind.RETALIATION_COPY:
				caption = "COUNTER"
		if caption.is_empty():
			continue
		var canvas_point: Vector2 = target.get_global_transform_with_canvas() * Vector2(target.size.x * 0.5, 0.0)
		_runtime_outcomes.append({"caption": caption, "anchor": local_from_canvas * canvas_point})


func _on_shot_hit_resolution_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	if snapshot == null or snapshot != _arrival_snapshot:
		return
	_arrival_snapshot = null
	var result: Dictionary = submission.get("hit_resolution_result", {})
	if bool(result.get("cancelled_by_zero_pk", false)) or bool(result.get("terminal_mode", false)):
		return
	var aim_canvas: Vector2 = snapshot.get_aim_center_global_position()
	aim_center = get_global_transform_with_canvas().affine_inverse() * aim_canvas
	_runtime_delta_pct = float(result.get("total_pk_delta", 0.0)) * 100.0
	_runtime_missed = int(submission.get("shot_anomaly", HitResolution.ShotAnomaly.NONE)) == HitResolution.ShotAnomaly.MISS and _runtime_outcomes.is_empty()
	_runtime_mode = true
	style = runtime_style
	_elapsed = 0.0
	_playing = true
	_build_labels()
	_apply_time(0.0)


# 预览从真实弹幕节点的变换得到目标矩形，坐标已经转换为本层局部坐标。
func set_target_rects(rects: Array[Rect2]) -> void:
	target_rects = rects


func _target_top_center(index: int) -> Vector2:
	if index >= 0 and index < target_rects.size():
		var r: Rect2 = target_rects[index]
		return r.position + Vector2(r.size.x * 0.5, 0)
	return target_positions[index]


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
		if _runtime_mode:
			_playing = false
			_number.visible = false
			for label in _labels:
				label.visible = false
			queue_redraw()
			return
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
func _font_size_for(delta: float) -> int:
	return clampi(roundi(float(minimum_font_size) + sqrt(absf(delta)) * 12.8), minimum_font_size, maximum_font_size)


func _format_net_percent(net: float) -> String:
	# 正常话语实际收益可细到 0.12%，数值浮字需保留结算精度。
	var rounded: float = snappedf(net, 0.01)
	if is_equal_approx(rounded, roundf(rounded)):
		return "%+d%%" % roundi(rounded)
	if is_equal_approx(rounded * 10.0, roundf(rounded * 10.0)):
		return "%+.1f%%" % rounded
	return "%+.2f%%" % rounded


func _build_labels() -> void:
	for label in _labels:
		label.queue_free()
	_labels.clear()
	var net: float = _runtime_delta_pct if _runtime_mode else float(CASE_DELTA[case_id])
	_number.visible = not is_zero_approx(net)
	_number.text = _format_net_percent(net) if _runtime_mode else "%+d" % int(net)
	_number.add_theme_font_size_override("font_size", _font_size_for(net))
	_number.add_theme_color_override("font_color", positive_color if net >= 0 else negative_color)
	_number.add_theme_constant_override("outline_size", 3 if style == Style.CLEAN else 5)
	_number.add_theme_color_override("font_outline_color", INK)
	_number.add_theme_color_override("font_shadow_color", Color(0.06, 0.02, 0.08, clampf(0.24 + absf(net) / 31.0, 0.24, 0.95)))
	_number.add_theme_constant_override("shadow_outline_size", clampi(roundi(2.0 + sqrt(absf(net)) * 3.9), 2, 24))
	_number.add_theme_constant_override("shadow_offset_x", clampi(roundi(absf(net) * 0.22), 2, 8))
	_number.add_theme_constant_override("shadow_offset_y", clampi(roundi(absf(net) * 0.28), 3, 10))
	if style == Style.INK:
		_number.add_theme_color_override("font_color", PALE if net >= 0 else Color("#fff1de"))
		_number.add_theme_color_override("font_outline_color", Color("#a3414b") if net < 0 else Color("#1d3b34"))
	elif style == Style.IMPACT:
		_number.add_theme_color_override("font_color", Color("#c6fff3") if net >= 0 else Color("#ffde88"))
		_number.add_theme_color_override("font_outline_color", Color("#1b1428"))

	# 普通命中只看准星数值，特殊异常才需要额外局部结果词。
	var captions: Array[String] = []
	var positions: Array[Vector2] = []
	var target_anchors: Array[Vector2] = []
	if _runtime_mode:
		for outcome: Dictionary in _runtime_outcomes:
			var caption: String = str(outcome.get("caption", ""))
			if caption.is_empty():
				continue
			captions.append(caption)
			target_anchors.append(outcome.get("anchor", Vector2.ZERO))
		if _runtime_missed:
			captions.append("MISS")
			positions.append(aim_center + Vector2(64, 28))
	else:
		match case_id:
			Case.BLOCK:
				captions = ["BLOCK"]
				target_anchors = [_target_top_center(1)]
			Case.REFLECT:
				captions = ["REFLECT"]
				target_anchors = [_target_top_center(2)]
			Case.MULTI:
				captions = ["BLOCK", "REFLECT"]
				target_anchors = [_target_top_center(1), _target_top_center(2)]
			Case.MISS:
				captions = ["MISS"]
				positions = [aim_center + Vector2(64, 28)]
	for i in range(target_anchors.size()):
		var anchor: Vector2 = target_anchors[i]
		# 标签在对应玻璃弹幕上方，以短连接线指向目标，避开弹幕正文。
		positions.append(anchor + Vector2(-float(captions[i].length()) * 8.5, -49.0))
	for i in range(captions.size()):
		var label := _new_label()
		label.text = captions[i]
		label.set_meta("base_position", positions[i])
		if i < target_anchors.size():
			label.set_meta("target_anchor", target_anchors[i])
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
	queue_redraw()


# 用一段低对比短线把异常词连回实际命中的弹幕，不额外增加 HUD 容器。
func _draw() -> void:
	for label in _labels:
		if not label.has_meta("target_anchor") or label.modulate.a <= 0.0:
			continue
		var hit: Vector2 = label.get_meta("target_anchor")
		var origin: Vector2 = label.position + Vector2(float(label.text.length()) * 8.5, 29.0)
		var tint := Color(0.84, 0.89, 0.96, 0.54 * label.modulate.a)
		draw_line(origin, hit, tint, 1.5, true)
		draw_circle(hit, 2.5, tint)
