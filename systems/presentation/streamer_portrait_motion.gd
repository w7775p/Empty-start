class_name StreamerPortraitMotion
extends Control

signal shot_motion_started
signal shot_motion_finished

@export var idle_period: float = 3.4
@export var idle_phase: float = 0.0
@export var float_distance: float = 3.0
@export var breath_amount: float = 0.02
@export var sway_degrees: float = 0.6
@export var body_pivot: Vector2 = Vector2(0.5, 0.65)
@export var shot_direction: Vector2 = Vector2.RIGHT
@export var shot_distance: float = 9.0
@export var shot_compression: float = 0.06
@export var recoil_count: int = 2
@export var recovery_seconds: float = 0.18

var idle_strength: float = 1.0
var _idle_layer: Control
var _idle_tween: Tween
var _shot_tween: Tween
var _strength_tween: Tween


# 在原立绘槽中插入事件层与待机层；外部事件继续作用于原槽或立绘本体。
func attach_portrait(portrait: TextureRect) -> void:
	var slot: Node = portrait.get_parent()
	var original_index: int = portrait.get_index()
	name = portrait.name + "Motion"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(self)
	slot.move_child(self, original_index)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_idle_layer = Control.new()
	_idle_layer.name = "Idle"
	_idle_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_idle_layer)
	_idle_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.reparent(_idle_layer, false)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_update_pivots)
	_update_pivots()
	restart_idle()


# 每个角色使用不同周期和相位；可继续通过导出参数微调。
func configure_character(character_id: String) -> void:
	match character_id:
		"kiwi":
			idle_period = 2.9
			idle_phase = 1.7
			float_distance = 2.0
			breath_amount = 0.025
			sway_degrees = 0.8
		"fox":
			idle_period = 4.1
			idle_phase = 3.2
			float_distance = 2.5
			breath_amount = 0.015
			sway_degrees = 0.5
		"alien":
			idle_period = 3.8
			idle_phase = 2.2
			float_distance = 4.0
			breath_amount = 0.02
			sway_degrees = 0.7
		_:
			idle_period = 3.4
			idle_phase = 0.0
			float_distance = 3.0
			breath_amount = 0.02
			sway_degrees = 0.6
	if _idle_layer != null:
		restart_idle()


# 原生 Tween 循环推进相位，正弦端点连续，暂停随所属场景处理。
func restart_idle() -> void:
	if _idle_tween != null:
		_idle_tween.kill()
	_apply_idle(0.0)
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_method(_apply_idle, 0.0, TAU, maxf(idle_period, 0.1))


# 漂浮、呼吸和微摆只写待机层，射击与受击变换可在其他层叠加。
func _apply_idle(phase: float) -> void:
	var wave: float = sin(phase + idle_phase) * idle_strength
	_idle_layer.position = Vector2(0.0, wave * float_distance)
	_idle_layer.scale = Vector2(1.0 - wave * breath_amount * 0.35, 1.0 + wave * breath_amount)
	_idle_layer.rotation = deg_to_rad(sway_degrees) * sin(phase + idle_phase + 0.7) * idle_strength


# 枢轴随槽尺寸更新，运动围绕角色躯干。
func _update_pivots() -> void:
	pivot_offset = size * body_pivot
	_idle_layer.pivot_offset = size * body_pivot


# 满蓄快照到达后播放一次；连续发射取消旧 Tween 并复位事件层。
func play_shot() -> void:
	reset_shot()
	shot_motion_started.emit()
	var forward: Vector2 = shot_direction.normalized() * shot_distance
	_shot_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shot_tween.tween_property(self, "position", forward, 0.055)
	_shot_tween.parallel().tween_property(self, "scale", Vector2(1.0 + shot_compression * 0.5, 1.0 - shot_compression), 0.055)
	for index: int in range(maxi(recoil_count, 1)):
		var recoil: Vector2 = -forward * (0.45 / float(index + 1))
		_shot_tween.tween_property(self, "position", recoil, 0.045)
		_shot_tween.parallel().tween_property(self, "scale", Vector2(0.98, 1.02), 0.045)
		_shot_tween.tween_property(self, "position", forward * (0.15 / float(index + 1)), 0.035)
	_shot_tween.tween_property(self, "position", Vector2.ZERO, maxf(recovery_seconds, 0.01))
	_shot_tween.parallel().tween_property(self, "scale", Vector2.ONE, maxf(recovery_seconds, 0.01))
	_shot_tween.tween_callback(shot_motion_finished.emit)


# 重开或中断只复位事件层，待机保持连续。
func reset_shot() -> void:
	if _shot_tween != null:
		_shot_tween.kill()
	position = Vector2.ZERO
	scale = Vector2.ONE
	rotation = 0.0


# CRT 或受击演出可暂时降低待机幅度，再调用同入口平顺恢复。
func set_idle_strength(value: float, seconds: float = 0.15) -> void:
	if _strength_tween != null:
		_strength_tween.kill()
	_strength_tween = create_tween()
	_strength_tween.tween_property(self, "idle_strength", clampf(value, 0.0, 1.0), maxf(seconds, 0.01))
