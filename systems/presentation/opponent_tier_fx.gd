class_name OpponentTierFx
extends Control

@export var sweat_anchor: Vector2 = Vector2(0.72, 0.22)
@export var sweat_size: float = 26.0
@export var sweat_period: float = 1.75
@export var impact_strength: float = 1.0
@export var kiwi_impact_seconds: float = 0.34
@export var impact_flash_alpha: float = 0.24
@export var impact_line_scale: float = 1.0
@export_range(8, 20, 1) var impact_lanes_per_side: int = 13
@export var impact_focus_anchor: Vector2 = Vector2(0.52, 0.39)
@export var impact_face_clearance: Vector2 = Vector2(0.27, 0.25)

var sweat_alpha: float = 0.0:
	set(value):
		sweat_alpha = clampf(value, 0.0, 1.0)
		queue_redraw()

var _time: float = 0.0
var _impact_left: float = 0.0
var _impact_duration: float = 0.23
var _character_id: String = ""
var _sweat_tween: Tween
var _impact_backdrop: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


# T2 时淡入两滴循环滑落的程序水滴，离开 T2 时淡出。
func set_sweat(enabled: bool) -> void:
	if _sweat_tween != null:
		_sweat_tween.kill()
	set_process(enabled or sweat_alpha > 0.0 or _impact_left > 0.0)
	_sweat_tween = create_tween()
	_sweat_tween.tween_property(self, "sweat_alpha", 1.0 if enabled else 0.0, 0.16 if enabled else 0.12)
	if not enabled:
		_sweat_tween.tween_callback(_stop_if_idle)


# 换图瞬间的漫画冲击只属于立绘局部，不改变战斗受击判定。
func play_impact() -> void:
	_impact_duration = kiwi_impact_seconds if _character_id == "kiwi" else 0.23
	_impact_left = _impact_duration
	set_process(true)
	queue_redraw()
	_queue_backdrop_redraw()


# 三名对手共用白色速度条；角色 ID 仍决定现有冲击时长。
func configure_character(character_id: String) -> void:
	_character_id = character_id
	_queue_backdrop_redraw()


# 临时白条画布位于 PNG 下方；TierFx 统一管理计时、汗滴和清理。
func bind_backdrop(backdrop: Control) -> void:
	if _impact_backdrop != null and _impact_backdrop.draw.is_connected(_draw_impact_backdrop):
		_impact_backdrop.draw.disconnect(_draw_impact_backdrop)
	_impact_backdrop = backdrop
	_impact_backdrop.draw.connect(_draw_impact_backdrop)
	_queue_backdrop_redraw()


func clear_impact() -> void:
	_impact_left = 0.0
	queue_redraw()
	_queue_backdrop_redraw()
	_stop_if_idle()


func reset_fx() -> void:
	if _sweat_tween != null:
		_sweat_tween.kill()
	sweat_alpha = 0.0
	_impact_left = 0.0
	_time = 0.0
	set_process(false)
	_queue_backdrop_redraw()


func _process(delta: float) -> void:
	_time += delta
	_impact_left = maxf(0.0, _impact_left - delta)
	queue_redraw()
	_queue_backdrop_redraw()
	_stop_if_idle()


func _queue_backdrop_redraw() -> void:
	if _impact_backdrop != null:
		_impact_backdrop.queue_redraw()


func _stop_if_idle() -> void:
	if sweat_alpha <= 0.0 and _impact_left <= 0.0:
		set_process(false)


func _draw() -> void:
	if sweat_alpha > 0.0:
		var unit: float = minf(size.x / 448.0, size.y / 432.0)
		for index: int in 2:
			var phase: float = fposmod(_time / maxf(sweat_period, 0.1) + float(index) * 0.52, 1.0)
			var life: float = sin(phase * PI) * sweat_alpha
			var center: Vector2 = size * sweat_anchor + Vector2(float(index) * 30.0 - 12.0, phase * 24.0) * unit
			_draw_drop(center, sweat_size * unit * (1.0 - phase * 0.12), life)


# 使用同一套相对坐标排布三名对手；粗主线和细辅线交错，保留原底板与面部留白。
func _draw_impact_backdrop() -> void:
	if _impact_backdrop == null or _impact_left <= 0.0:
		return
	var area: Vector2 = _impact_backdrop.size
	if area.x <= 1.0 or area.y <= 1.0:
		return
	var elapsed: float = _impact_duration - _impact_left
	var burst: float = clampf(elapsed / 0.045, 0.0, 1.0)
	var alpha: float = pow(_impact_left / _impact_duration, 0.55) * impact_strength * burst
	var focus: Vector2 = area * impact_focus_anchor
	var clearance: Vector2 = area * impact_face_clearance
	var flash: float = impact_flash_alpha * (1.0 - elapsed / 0.095) if elapsed < 0.095 else 0.0
	var strong := Color(1.0, 1.0, 1.0, minf(1.0, alpha * (1.15 + flash)))
	var soft := Color(1.0, 1.0, 1.0, minf(1.0, alpha * (0.86 + flash)))
	var unit: float = minf(area.x, area.y) * impact_line_scale
	for edge_side: int in 4:
		var count: int = impact_lanes_per_side if edge_side % 2 == 0 else impact_lanes_per_side - 1
		# 顶部单独加密；起点延至卡片标题所在的上缘，其他三边维持原排布。
		if edge_side == 0:
			count += 12
		for index: int in count:
			var offset: float = sin(float(index * 17 + edge_side * 11) * 1.31) * 0.18
			var u: float = (float(index) + 0.48 + offset) / float(count)
			var main: bool = (index + edge_side * 2) % 5 == 0
			var edge: Vector2
			match edge_side:
				0:
					edge = area * Vector2(u, -0.088)
				1:
					edge = area * Vector2(1.025 if main else 1.0, u)
				2:
					edge = area * Vector2(u, 1.015 if main else 1.0)
				_:
					edge = area * Vector2(-0.025 if main else 0.0, u)
			var inner: Vector2 = _impact_inner_point(edge, focus, clearance)
			var reach: float = 1.10 + float((index * 3 + edge_side) % 5) * 0.045
			var target: Vector2 = focus + (inner - focus) * reach
			if edge_side == 0 and not main:
				# 辅线在上半圈分段收束，避免新增线条全都伸向面部。
				if index % 3 == 1:
					target = edge.lerp(target, 0.44)
				elif index % 3 == 2:
					target = edge.lerp(target, 0.67)
			var direction: Vector2 = (target - edge).normalized()
			var side: Vector2 = direction.orthogonal()
			var width: float = unit * (0.018 + float(index % 3) * 0.003 if main else 0.004 + float(index % 4) * 0.0015)
			if edge_side == 0 and not main:
				width *= 0.72
			var inner_width: float = width * (0.62 if main else 0.76)
			var mid: Vector2 = edge.lerp(target, 0.54) + side * unit * sin(float(index * 7 + edge_side)) * 0.003
			var color: Color = strong if main else soft
			_draw_impact_quad(edge - side * width, edge + side * width * 0.9, mid + side * width * 0.8, mid - side * width * 0.86, color)
			_draw_impact_quad(mid - side * width * 0.86, mid + side * width * 0.8, target + side * inner_width, target - side * inner_width, color)


func _impact_inner_point(edge: Vector2, focus: Vector2, clearance: Vector2) -> Vector2:
	var offset: Vector2 = edge - focus
	var scaled: Vector2 = Vector2(offset.x / maxf(clearance.x, 1.0), offset.y / maxf(clearance.y, 1.0))
	return focus + offset / maxf(scaled.length(), 0.001)


# 三角形拼接避免不规则四边形三角化失败。
func _draw_impact_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, color: Color) -> void:
	_impact_backdrop.draw_colored_polygon(PackedVector2Array([a, b, c]), color)
	_impact_backdrop.draw_colored_polygon(PackedVector2Array([a, c, d]), color)


func _draw_drop(center: Vector2, radius: float, alpha: float) -> void:
	var outline := PackedVector2Array([
		center + Vector2(0.0, -radius * 1.45),
		center + Vector2(radius * 0.72, -radius * 0.15),
		center + Vector2(radius * 0.78, radius * 0.48),
		center + Vector2(0.0, radius),
		center + Vector2(-radius * 0.78, radius * 0.48),
		center + Vector2(-radius * 0.72, -radius * 0.15)
	])
	draw_colored_polygon(outline, Color(0.12, 0.18, 0.29, alpha))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius * 1.15),
		center + Vector2(radius * 0.52, -radius * 0.07),
		center + Vector2(radius * 0.55, radius * 0.43),
		center + Vector2(0.0, radius * 0.72),
		center + Vector2(-radius * 0.55, radius * 0.43),
		center + Vector2(-radius * 0.52, -radius * 0.07)
	]), Color(0.36, 0.86, 1.0, alpha))
	draw_line(center + Vector2(-radius * 0.26, -radius * 0.20), center + Vector2(-radius * 0.10, -radius * 0.55), Color(1.0, 1.0, 1.0, alpha), maxf(2.0, radius * 0.12))
