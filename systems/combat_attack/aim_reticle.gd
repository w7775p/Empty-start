class_name AimReticle
extends Control

signal animation_finished

@export_group("判定与位置")
# 正式 PC 命中区域为直径 144px 的圆，包络框是策划表中的 144×144。
@export var reticle_diameter: float = 144.0

@export_group("空心圆与环形蓄力")
# 正式 PC 视觉限定 96×96；视觉大小不改变实际目标相交判定。
@export_range(32.0, 160.0, 1.0) var visual_diameter: float = 96.0
@export_range(2.0, 24.0, 0.5) var center_ring_radius: float = 7.5
@export_range(1.0, 8.0, 0.5) var center_line_width: float = 2.5
@export_range(0.0, 30.0, 0.5) var outer_ring_gap: float = 4.0
@export_range(1.0, 8.0, 0.5) var outer_ring_width: float = 3.0
@export_range(0.0, 9.0, 0.5) var contrast_halo_width: float = 5.5
@export var idle_color: Color = Color(0.92, 0.99, 1.0, 0.96)
@export var track_color: Color = Color(0.75, 0.93, 0.96, 0.77)
@export var charge_color: Color = Color(0.35, 0.98, 0.88, 1.0)
@export var full_color: Color = Color(1.0, 0.88, 0.37, 1.0)
@export var shot_color: Color = Color(1.0, 1.0, 1.0, 1.0)

@export_group("短时动态")
@export_range(2.0, 40.0, 1.0) var charge_smoothing: float = 18.0
@export_range(0.05, 0.5, 0.01) var shot_flash_duration: float = 0.16
@export_range(0.05, 0.5, 0.01) var movement_flash_duration: float = 0.12
@export_range(0.0, 0.4, 0.01) var shot_ring_expansion: float = 0.20
@export_range(0.0, 0.4, 0.01) var full_pulse_strength: float = 0.10

var _mouse_reticle_diameter: float
var _touch_aim_active: bool = false
var _touch_viewport_position: Vector2
var _charge_target: float = 0.0
var _charge_display: float = 0.0
var _charge_held: bool = false
var _charge_full: bool = false
var _visual_paused: bool = false
var _shot_flash_remaining: float = 0.0
var _movement_flash_remaining: float = 0.0
var _pulse_clock: float = 0.0


# 命中节点使用 PC 直径 144，绘制始终居中于独立的 96×96 视觉区域。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mouse_reticle_diameter = reticle_diameter
	size = Vector2.ONE * reticle_diameter
	custom_minimum_size = size
	refresh_mouse_position()
	queue_redraw()


# 只推进表现计时；蓄力真实进度由 CombatAttack 的外部调用提供。
func _process(delta: float) -> void:
	if _visual_paused:
		return
	_pulse_clock += delta
	var blend: float = 1.0 - exp(-charge_smoothing * delta)
	_charge_display = lerpf(_charge_display, _charge_target, blend)
	if absf(_charge_display - _charge_target) < 0.001:
		_charge_display = _charge_target
	_movement_flash_remaining = maxf(0.0, _movement_flash_remaining - delta)
	if _shot_flash_remaining > 0.0:
		_shot_flash_remaining = maxf(0.0, _shot_flash_remaining - delta)
		if _shot_flash_remaining <= 0.0:
			animation_finished.emit()
	queue_redraw()


# 鼠标事件更新原有位置关系；微小运动反馈只改变画面，不改判定范围。
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		_touch_aim_active = false
		_set_reticle_diameter(_mouse_reticle_diameter)
		var canvas_position: Vector2 = get_canvas_transform().affine_inverse() * mouse_event.position
		_set_aim_center_global_position(canvas_position)
		_movement_flash_remaining = movement_flash_duration


# 场景布局变化后重新对齐鼠标或当前触屏中心。
func refresh_mouse_position() -> void:
	if _touch_aim_active:
		_set_aim_center_global_position(get_canvas_transform().affine_inverse() * _touch_viewport_position)
		return
	_set_aim_center_global_position(get_global_mouse_position())


# 移动端尺寸与实际命中圆同步，触屏坐标先转换为画布坐标。
func move_touch_aim(viewport_position: Vector2, diameter: float) -> void:
	_touch_aim_active = true
	_touch_viewport_position = viewport_position
	_set_reticle_diameter(diameter)
	_set_aim_center_global_position(get_canvas_transform().affine_inverse() * viewport_position)
	_movement_flash_remaining = movement_flash_duration


# 使用真实鼠标按下事件位置恢复 PC 准心，规避隐藏窗口中的系统光标异常读数。
func restore_mouse_aim(viewport_position: Vector2) -> void:
	_touch_aim_active = false
	_set_reticle_diameter(_mouse_reticle_diameter)
	_set_aim_center_global_position(get_canvas_transform().affine_inverse() * viewport_position)


# 同步外部已存在的蓄力事实；该接口每帧调用也不会重新启动演出。
func set_charge_visual_state(progress: float, is_held: bool, is_fully_charged: bool) -> void:
	_charge_target = clampf(progress, 0.0, 1.0)
	_charge_held = is_held
	_charge_full = is_fully_charged
	if is_fully_charged:
		_charge_target = 1.0
	queue_redraw()


# 真实发射快照产生时调用一次，短时高亮完成后发出动画完成通知。
func play_shot_feedback() -> void:
	_charge_target = 0.0
	_charge_held = false
	_charge_full = false
	_shot_flash_remaining = maxf(0.01, shot_flash_duration)
	queue_redraw()


# 停止短时演出并恢复待机；重复播放前可以安全调用。
func reset_visual_state() -> void:
	_charge_target = 0.0
	_charge_display = 0.0
	_charge_held = false
	_charge_full = false
	_shot_flash_remaining = 0.0
	_movement_flash_remaining = 0.0
	_pulse_clock = 0.0
	queue_redraw()


# 演示与宿主可以独立暂停表现动画；暂停期间保留画面进度。
func set_visual_paused(paused: bool) -> void:
	_visual_paused = paused
	set_process(not paused)


# 测试和演示读取已经绘出的平滑进度，不改变真实攻击状态。
func get_display_charge_progress() -> float:
	return _charge_display


# 测试与宿主判断当前短时发射表现是否还在播放。
func is_shot_feedback_playing() -> bool:
	return _shot_flash_remaining > 0.0


# 现有直径始终代表命中区域；鼠标恢复 144px，触屏继续采用外部独立配置。
func _set_reticle_diameter(diameter: float) -> void:
	if reticle_diameter == diameter:
		return
	reticle_diameter = diameter
	size = Vector2.ONE * diameter
	custom_minimum_size = size
	queue_redraw()


# 中心偏移使用完整缩放基底，支持嵌套缩放的准心场景。
func _set_aim_center_global_position(center_position: Vector2) -> void:
	global_position = center_position - get_global_transform().basis_xform(size * 0.5)


# 判定与显示共享的唯一中心来源。
func get_aim_center_global_position() -> Vector2:
	return get_global_transform() * (size * 0.5)


# 保持现有圆-矩形相交算法；144×144 为 PC 命中圆的包络范围。
func intersects_target_area(target_area: Rect2) -> bool:
	var local_target_area: Rect2 = get_global_transform().affine_inverse() * target_area
	return BarrageAimIntersection.circle_overlaps_rect(
		size * 0.5,
		reticle_diameter,
		local_target_area
	)


# 在独立的 96×96 视觉范围内绘制准星，视觉变化始终不影响 144px 命中圆。
func _draw() -> void:
	var center: Vector2 = size * 0.5
	var shot_strength: float = _shot_flash_remaining / maxf(shot_flash_duration, 0.01)
	var move_strength: float = _movement_flash_remaining / maxf(movement_flash_duration, 0.01)
	var full_strength: float = 0.0
	if _charge_full:
		full_strength = (0.5 + 0.5 * sin(_pulse_clock * 9.0)) * full_pulse_strength
	# 预留描边的最外缘，满蓄/发射动画也控制在视觉边界内。
	var outside_half_width: float = (outer_ring_width + contrast_halo_width) * 0.5
	var max_radius: float = visual_diameter * 0.5 - outside_half_width
	var base_radius: float = maxf(center_ring_radius + 5.0, max_radius - outer_ring_gap)
	var radius: float = minf(base_radius * (1.0 + shot_strength * shot_ring_expansion + full_strength), max_radius)
	var accent: Color = full_color if _charge_full else charge_color
	if shot_strength > 0.0:
		accent = accent.lerp(shot_color, shot_strength)
	var core_color: Color = idle_color.lerp(accent, minf(1.0, shot_strength + move_strength * 0.45))
	var shadow: Color = Color(0.025, 0.043, 0.068, 0.92)

	# 浅色细环叠深色外描边：穿过亮字或深背景都保留轮廓。
	draw_circle(center, center_ring_radius * (1.0 + shot_strength * 0.18), shadow, false, center_line_width + contrast_halo_width, true)
	draw_circle(center, center_ring_radius * (1.0 + shot_strength * 0.18), core_color, false, center_line_width, true)
	draw_arc(center, radius, -PI * 0.5, PI * 1.5, 96, shadow, outer_ring_width + contrast_halo_width, true)
	draw_arc(center, radius, -PI * 0.5, PI * 1.5, 96, track_color, outer_ring_width, true)

	var visible_progress: float = 1.0 if _charge_full else _charge_display
	if visible_progress > 0.001:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * visible_progress, 96, accent, outer_ring_width + shot_strength * 1.2, true)
	if move_strength > 0.01:
		var locate: Color = idle_color
		locate.a = 0.58 * move_strength
		var move_radius: float = minf(radius + 6.0 * (1.0 - move_strength), visual_diameter * 0.5 - 1.5)
		draw_arc(center, move_radius, -PI * 0.5, PI * 1.5, 96, locate, 2.0, true)
	if shot_strength > 0.0:
		var flash_radius: float = minf(radius + 4.0 * shot_strength, visual_diameter * 0.5 - 1.5)
		draw_arc(center, flash_radius, -PI * 0.5, PI * 1.5, 96, Color(1.0, 1.0, 1.0, shot_strength * 0.65), 1.5, true)
