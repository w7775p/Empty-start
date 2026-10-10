class_name BarrageGlassSurface
extends Control

@export_group("倾向色 / GLASS NOIR")
@export var orthodox_color: Color = Color("#1658A2")
@export var heretical_color: Color = Color("#B9502D")
@export var absurd_color: Color = Color("#B7865B")
@export var neutral_color: Color = Color("#ADA4A3")
@export var repeat_color: Color = Color("#8894A6")
@export var glass_base_color: Color = Color("#101622")

@export_group("玻璃尺寸与反光")
@export_range(4.0, 26.0, 1.0) var corner_radius: float = 13.0
@export_range(0.0, 1.0, 0.05) var highlight_alpha: float = 0.23
@export_range(0.0, 1.0, 0.05) var repeat_alpha: float = 0.24
@export_range(1.0, 6.0, 0.5) var max_border_width: float = 3.0

@export_group("强度 S1 / S2 / S3")
# Vector3 的 X / Y / Z 分别对应 S1 / S2 / S3，整组参数可在 Inspector 修改。
@export var stage_fill_alpha: Vector3 = Vector3(0.66, 0.84, 0.95)
@export var stage_tint_amount: Vector3 = Vector3(0.16, 0.38, 0.62)
@export var stage_border_alpha: Vector3 = Vector3(0.36, 0.77, 1.0)
@export var stage_glow_radius: Vector3 = Vector3(0.0, 8.0, 17.0)
@export var stage_glow_alpha: Vector3 = Vector3(0.0, 0.34, 0.63)
@export_range(0.0, 1.0, 0.05) var glow_lighten: float = 0.38

@export_group("S3 呼吸")
@export_range(0.0, 8.0, 0.1) var breathing_speed: float = 3.4
@export_range(1.0, 30.0, 1.0) var breathing_refresh_rate: float = 24.0
@export var s3_glow_radius_range: Vector2 = Vector2(13.0, 20.0)
@export var s3_glow_alpha_range: Vector2 = Vector2(0.40, 0.72)

var _tendency: String = "neutral"
var _strength: int = 1
var _is_repeat: bool = false
var _pulse_clock: float = 0.0
var _redraw_elapsed: float = 0.0
var _glass_style: StyleBoxFlat = StyleBoxFlat.new()


# 根据同一份弹幕运行记录确定倾向、强度和普通复读的玻璃表现。
func configure(tendency: String, strength: int, is_repeat: bool) -> void:
	_tendency = tendency
	_strength = clampi(strength, 1, 3)
	_is_repeat = is_repeat
	_pulse_clock = 0.0
	_redraw_elapsed = 0.0
	_rebuild_style()
	set_process(_strength == 3 and not _is_repeat)
	queue_redraw()


# 颜色入口直接暴露给 Inspector，换色后所有档位跟随对应倾向。
func get_base_tint() -> Color:
	if _is_repeat:
		return repeat_color
	match _tendency:
		"orthodox":
			return orthodox_color
		"heretical":
			return heretical_color
		"absurd":
			return absurd_color
		_:
			return neutral_color


# 只给 S3 更新慢速呼吸；暂停时保留当前亮度。
func _process(delta: float) -> void:
	if get_tree().paused:
		return
	_pulse_clock += delta
	_redraw_elapsed += delta
	if _redraw_elapsed >= 1.0 / maxf(1.0, breathing_refresh_rate):
		_redraw_elapsed = 0.0
		queue_redraw()


# 一套底板颜色对应三档材质权重；复读始终使用低对比灰色玻璃。
func _rebuild_style() -> void:
	var tint: Color = get_base_tint()
	var tier: int = _strength - 1
	var fill: Color = glass_base_color.lerp(tint, _tier_value(stage_tint_amount, tier))
	fill.a = repeat_alpha if _is_repeat else _tier_value(stage_fill_alpha, tier)
	var edge: Color = tint.lightened(0.12 if _is_repeat else [0.18, 0.39, 0.60][tier])
	edge.a = 0.30 if _is_repeat else _tier_value(stage_border_alpha, tier)
	_glass_style.bg_color = fill
	_glass_style.border_color = edge
	_glass_style.set_border_width_all(1 if _is_repeat else roundi(1.0 + float(tier) * (max_border_width - 1.0) / 2.0))
	_glass_style.set_corner_radius_all(roundi(corner_radius))
	var bloom: Color = tint.lightened(glow_lighten)
	bloom.a = 0.0 if _is_repeat else _tier_value(stage_glow_alpha, tier)
	_glass_style.shadow_color = bloom
	_glass_style.shadow_size = 0 if _is_repeat else roundi(_tier_value(stage_glow_radius, tier))
	_glass_style.shadow_offset = Vector2.ZERO


# Vector3 颜色/强度字段只在一个地方读取，避免 S1-S3 产生不同数据来源。
func _tier_value(values: Vector3, tier: int) -> float:
	return [values.x, values.y, values.z][tier]


# 程序绘制完整的玻璃亮面和柔光；取消斜刻痕、双层硬框与左侧竖条。
func _draw() -> void:
	if _glass_style.bg_color.a <= 0.001 or size.x < 26.0 or size.y < 22.0:
		return
	if _strength == 3 and not _is_repeat:
		var pulse: float = 0.5 + 0.5 * sin(_pulse_clock * breathing_speed)
		var glow: Color = _glass_style.shadow_color
		glow.a = lerpf(s3_glow_alpha_range.x, s3_glow_alpha_range.y, pulse)
		_glass_style.shadow_color = glow
		_glass_style.shadow_size = roundi(lerpf(s3_glow_radius_range.x, s3_glow_radius_range.y, pulse))
	draw_style_box(_glass_style, Rect2(Vector2.ZERO, size))
	var top_light: Color = Color.WHITE
	top_light.a = highlight_alpha * ([0.30, 0.65, 1.0][_strength - 1]) * (0.5 if _is_repeat else 1.0)
	var inset: float = maxf(12.0, corner_radius + 5.0)
	draw_rect(Rect2(inset, 6.0, maxf(1.0, size.x - inset * 2.0), 2.5), top_light)
