class_name PkHamsterBallIndicator
extends TextureRect

const HAPPY_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_indicator_01.png")
const PANIC_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_indicator_02.png")
const CIRCLE_MASK_SHADER: Shader = preload("res://systems/presentation/pk_hamster_ball_circle_mask.gdshader")

@export_range(24.0, 112.0, 1.0) var indicator_diameter_px: float = 32.0
@export_range(0.90, 1.0, 0.005) var circle_mask_radius: float = 0.96
@export_range(0.005, 0.08, 0.005) var circle_mask_softness: float = 0.015
@export_range(0.0, 64.0, 0.5) var track_y_offset_px: float = 0.0
@export_range(0.02, 0.5, 0.01) var move_smoothing_seconds: float = 0.11
@export_range(0.0, 2.0, 0.05) var roll_multiplier: float = 1.0
@export_range(0.0, 64.0, 0.5) var tier_jump_height_px: float = 19.0
@export_range(0.03, 0.3, 0.01) var tier_jump_up_seconds: float = 0.11
@export_range(0.05, 0.5, 0.01) var tier_jump_land_seconds: float = 0.22
@export_range(0.0, 30.0, 0.5) var tier_spin_degrees: float = 8.0
@export_range(0.0, 24.0, 0.5) var downgrade_shake_amplitude_px: float = 5.0
@export_range(1, 8, 1) var downgrade_shake_cycles: int = 4
@export_range(0.02, 0.12, 0.01) var downgrade_shake_step_seconds: float = 0.045
@export_range(0.0, 36.0, 0.5) var downgrade_jump_height_px: float = 13.0
@export_range(0.0, 0.8, 0.01) var panic_face_hold_seconds: float = 0.32

var _track: ProgressBar
var _player_pk: float = 0.5
var _target_center_x: float = 0.0
var _display_center_x: float = 0.0
var _track_center_y: float = 0.0
var _roll_rotation: float = 0.0
var _event_rotation: float = 0.0
var _bounce_offset_y: float = 0.0
var _shake_offset_x: float = 0.0
var _is_position_initialized: bool = false
var _event_tween: Tween


# 指示器挂在真实 PK 进度条内，直接使用同一轨道坐标和宽度。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	z_index = 10
	texture = HAPPY_TEXTURE
	var circular_material := ShaderMaterial.new()
	circular_material.shader = CIRCLE_MASK_SHADER
	circular_material.set_shader_parameter("circle_radius", circle_mask_radius)
	circular_material.set_shader_parameter("edge_softness", circle_mask_softness)
	material = circular_material
	_track = get_parent() as ProgressBar
	if _track == null:
		push_error("PkHamsterBallIndicator 必须作为 ProgressBar 子节点使用。")
		return
	_track.resized.connect(_on_track_resized)
	_on_track_resized()
	set_player_pk(_track.value / maxf(_track.max_value, 1.0), true)


# 使用实际画面位移量计算滚动角度；窗口静止时不继续自转。
func _process(delta: float) -> void:
	if _track == null or delta <= 0.0:
		return
	var previous_center: float = _display_center_x
	var smoothing: float = maxf(move_smoothing_seconds, 0.001)
	var blend: float = 1.0 - exp(-delta / smoothing)
	_display_center_x = lerpf(_display_center_x, _target_center_x, blend)
	if absf(_target_center_x - _display_center_x) < 0.04:
		_display_center_x = _target_center_x
	var displayed_delta: float = _display_center_x - previous_center
	if absf(displayed_delta) > 0.0001:
		_roll_rotation += displayed_delta / maxf(indicator_diameter_px * 0.5, 1.0) * roll_multiplier
	_sync_transform()


# 读取和进度条相同的唯一 player_pk，并映射到当前实际轨道宽度。
func set_player_pk(player_pk: float, snap: bool = false) -> void:
	_player_pk = clampf(player_pk, 0.0, 1.0)
	_update_target_position()
	if snap or not _is_position_initialized:
		_display_center_x = _target_center_x
		_roll_rotation = 0.0
		_is_position_initialized = true
		_sync_transform()


# 重开时取消局部动画、恢复笑脸，并按新尝试的 PK 快照对齐轨道。
func reset_for_attempt(player_pk: float) -> void:
	_cancel_event_tween()
	texture = HAPPY_TEXTURE
	_roll_rotation = 0.0
	_event_rotation = 0.0
	_bounce_offset_y = 0.0
	_shake_offset_x = 0.0
	set_player_pk(player_pk, true)


# 只有真实 Tier 上升事件会调用；升档始终保留笑脸。
func play_tier_up() -> void:
	_cancel_event_tween()
	texture = HAPPY_TEXTURE
	var jump_height: float = absf(tier_jump_height_px)
	var spin: float = deg_to_rad(tier_spin_degrees)
	var land_seconds: float = maxf(tier_jump_land_seconds, 0.05)
	_event_tween = create_tween()
	_event_tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_event_tween.tween_method(_set_bounce_offset_y, 0.0, -jump_height, tier_jump_up_seconds)
	_event_tween.parallel().tween_method(_set_event_rotation, 0.0, spin, tier_jump_up_seconds)
	_event_tween.tween_interval(0.035)
	_event_tween.tween_method(_set_event_rotation, spin, -spin * 0.3, 0.07)
	_event_tween.tween_method(
		_set_bounce_offset_y, -jump_height, jump_height * 0.08, land_seconds * 0.58
	).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_event_tween.parallel().tween_method(_set_event_rotation, -spin * 0.3, 0.0, land_seconds * 0.58)
	_event_tween.tween_method(_set_bounce_offset_y, jump_height * 0.08, 0.0, land_seconds * 0.42)
	_event_tween.tween_callback(_finish_event_tween.bind(_event_tween, false))


# 只有真实 Tier 下降事件会调用；惊慌表情随局部惊跳结束恢复笑脸。
func play_tier_down() -> void:
	_cancel_event_tween()
	texture = PANIC_TEXTURE
	var cycles: int = maxi(downgrade_shake_cycles, 1)
	var step_seconds: float = maxf(downgrade_shake_step_seconds, 0.02)
	var shake_angle: float = deg_to_rad(tier_spin_degrees * 0.65)
	_event_tween = create_tween()
	_event_tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	for index: int in range(cycles * 2):
		var direction: float = 1.0 if index % 2 == 0 else -1.0
		_event_tween.tween_method(
			_set_shake_offset_x, _shake_offset_x, direction * downgrade_shake_amplitude_px, step_seconds
		)
		_event_tween.parallel().tween_method(
			_set_event_rotation, _event_rotation, direction * shake_angle, step_seconds
		)
	_event_tween.tween_method(_set_shake_offset_x, _shake_offset_x, 0.0, step_seconds)
	_event_tween.parallel().tween_method(_set_event_rotation, _event_rotation, 0.0, step_seconds)
	var jump_height: float = absf(downgrade_jump_height_px)
	_event_tween.tween_method(_set_bounce_offset_y, 0.0, -jump_height, tier_jump_up_seconds * 0.75)
	_event_tween.parallel().tween_method(
		_set_event_rotation, 0.0, -deg_to_rad(tier_spin_degrees), tier_jump_up_seconds * 0.75
	)
	_event_tween.tween_method(
		_set_bounce_offset_y, -jump_height, jump_height * 0.06, tier_jump_land_seconds
	).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_event_tween.parallel().tween_method(
		_set_event_rotation, -deg_to_rad(tier_spin_degrees), 0.0, tier_jump_land_seconds
	)
	_event_tween.tween_method(_set_bounce_offset_y, jump_height * 0.06, 0.0, 0.08)
	_event_tween.tween_interval(panic_face_hold_seconds)
	_event_tween.tween_callback(_finish_event_tween.bind(_event_tween, true))


# 父进度条变化尺寸后，重算 0% / 100% 两端和中心高度。
func _on_track_resized() -> void:
	if _track == null:
		return
	size = Vector2.ONE * indicator_diameter_px
	pivot_offset = size * 0.5
	_track_center_y = _track.size.y * 0.5 + track_y_offset_px
	_update_target_position()
	if not _is_position_initialized:
		_display_center_x = _target_center_x
		_is_position_initialized = true
	_sync_transform()


# 位置按进度条完整可见宽度线性映射，进度数据始终由 HUD 提供。
func _update_target_position() -> void:
	if _track == null:
		return
	_target_center_x = clampf(_player_pk, 0.0, 1.0) * _track.size.x


func _set_bounce_offset_y(value: float) -> void:
	_bounce_offset_y = value
	_sync_transform()


func _set_shake_offset_x(value: float) -> void:
	_shake_offset_x = value
	_sync_transform()


func _set_event_rotation(value: float) -> void:
	_event_rotation = value
	_sync_transform()


func _sync_transform() -> void:
	position = Vector2(
		_display_center_x - indicator_diameter_px * 0.5 + _shake_offset_x,
		_track_center_y - indicator_diameter_px * 0.5 + _bounce_offset_y
	)
	rotation = _roll_rotation + _event_rotation


# 新阶段事件中断旧局部演出，保留当前 PK 位置和已经显示的滚动角度。
func _cancel_event_tween() -> void:
	if _event_tween != null and _event_tween.is_running():
		_event_tween.kill()
	_event_tween = null
	_bounce_offset_y = 0.0
	_shake_offset_x = 0.0
	_event_rotation = 0.0
	_sync_transform()


# 演出结束回到轨道中心；降档额外恢复默认笑脸。
func _finish_event_tween(tween: Tween, restore_happy_face: bool) -> void:
	if tween != _event_tween:
		return
	_event_tween = null
	_bounce_offset_y = 0.0
	_shake_offset_x = 0.0
	_event_rotation = 0.0
	if restore_happy_face:
		texture = HAPPY_TEXTURE
	_sync_transform()
