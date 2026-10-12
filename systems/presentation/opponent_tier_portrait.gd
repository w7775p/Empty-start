class_name OpponentTierPortrait
extends Control

const TierFx = preload("res://systems/presentation/opponent_tier_fx.gd")

signal flip_finished(tier: int)

@export var flip_seconds: float = 0.32
@export_range(0.02, 0.5) var narrow_scale: float = 0.08
@export var rebound_scale: float = 1.07
@export var kiwi_flip_seconds: float = 0.42
@export var kiwi_burst_scale: float = 1.09
@export var kiwi_shake_pixels: float = 7.0
@export_range(0.7, 1.0, 0.01) var alien_tier_scale: float = 0.90

var current_tier: int = 0
var fx: OpponentTierFx
var _portrait: TextureRect
var _idle: Texture2D
var _tier_01: Texture2D
var _tier_02: Texture2D
var _tier_03: Texture2D
var _flip_tween: Tween
var _shudder_tween: Tween
var _impact_tween: Tween
var _pending_texture: Texture2D
var _character_id: String = ""
var _impact_backdrop: Control
var _display_scale: float = 1.0
var _pending_display_scale: float = 1.0


# 插入 PA-14 的 Idle 层内部，让汗滴、切图与现有呼吸动作共同移动。
func attach_portrait(portrait: TextureRect) -> void:
	var slot: Control = portrait.get_parent() as Control
	var index: int = portrait.get_index()
	name = "OpponentTierPortrait"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(self)
	slot.move_child(self, index)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait = portrait
	portrait.reparent(self, false)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.pivot_offset = portrait.size * 0.5
	_impact_backdrop = Control.new()
	_impact_backdrop.name = "TierImpactBackdrop"
	_impact_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_impact_backdrop)
	move_child(_impact_backdrop, 0)
	_impact_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx = TierFx.new()
	fx.name = "TierFx"
	add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.bind_backdrop(_impact_backdrop)
	resized.connect(_refresh_pivot)
	_refresh_pivot()


# 纹理由关卡/集成方显式提供；缺图时保留 idle 占位，不猜测文件名。
func configure_textures(idle: Texture2D, tier_01: Texture2D, tier_02: Texture2D, tier_03: Texture2D) -> void:
	_idle = idle
	_tier_01 = tier_01
	_tier_02 = tier_02
	_tier_03 = tier_03
	reset_for_tier(current_tier)


# 三名对手共用白色冲击条；Kiwi 的翻图节奏仍单独处理。
func configure_character(character_id: String) -> void:
	_character_id = character_id
	fx.configure_character(character_id)
	_display_scale = _scale_for_texture(_portrait.texture)
	_portrait.scale = Vector2.ONE * _display_scale


func show_tier(tier: int) -> void:
	var target_tier: int = clampi(tier, 0, 6)
	var target: Texture2D = _texture_for_tier(target_tier)
	var target_display_scale: float = _scale_for_texture(target)
	if target_tier == current_tier and _flip_tween == null:
		return
	current_tier = target_tier
	fx.set_sweat(target_tier == 2)
	fx.clear_impact()
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null
	if _shudder_tween != null:
		_shudder_tween.kill()
		_shudder_tween = null
	if _impact_tween != null:
		_impact_tween.kill()
		_impact_tween = null
	position = Vector2.ZERO
	_display_scale = _scale_for_texture(_portrait.texture)
	_portrait.scale = Vector2.ONE * _display_scale
	if _portrait.texture == target or _portrait.texture == null or target == null:
		_portrait.texture = target
		_display_scale = target_display_scale
		_portrait.scale = Vector2.ONE * _display_scale
		if target_tier == 1 or target_tier == 2:
			_play_shudder()
		return
	_pending_texture = target
	_pending_display_scale = target_display_scale
	if _character_id == "kiwi":
		_play_kiwi_flip()
		return
	var half: float = maxf(flip_seconds, 0.08) * 0.5
	_flip_tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	_flip_tween.tween_method(_set_horizontal_scale, 1.0, narrow_scale, half).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(_swap_at_edge)
	_flip_tween.tween_method(_set_horizontal_scale, narrow_scale, rebound_scale, half * 0.72).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_method(_set_horizontal_scale, rebound_scale, 1.0, half * 0.28).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(_finish_flip)


# Paradox 沿用 T5，重开/断线取消残留动画。
func reset_for_tier(tier: int = 0) -> void:
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null
	if _shudder_tween != null:
		_shudder_tween.kill()
		_shudder_tween = null
	if _impact_tween != null:
		_impact_tween.kill()
		_impact_tween = null
	position = Vector2.ZERO
	current_tier = clampi(tier, 0, 6)
	_pending_texture = null
	_portrait.texture = _texture_for_tier(current_tier)
	_display_scale = _scale_for_texture(_portrait.texture)
	_pending_display_scale = _display_scale
	_portrait.scale = Vector2.ONE * _display_scale
	fx.reset_fx()
	fx.set_sweat(current_tier == 2)


func _texture_for_tier(tier: int) -> Texture2D:
	match tier:
		3:
			return _tier_01 if _tier_01 != null else _idle
		4:
			return _tier_02 if _tier_02 != null else _idle
		5, 6:
			return _tier_03 if _tier_03 != null else _idle
		_:
			return _idle


func _set_horizontal_scale(value: float) -> void:
	_portrait.scale = Vector2(value, 1.0) * _display_scale


# Kiwi 在翻面后快速放大、定格、回弹；时长与幅度单独调参。
func _play_kiwi_flip() -> void:
	var compress: float = maxf(kiwi_flip_seconds, 0.32) * 0.29
	_flip_tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	_flip_tween.tween_method(_set_horizontal_scale, 1.0, narrow_scale, compress).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(_swap_at_edge)
	_flip_tween.tween_method(_set_kiwi_scale, narrow_scale, kiwi_burst_scale, 0.105).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_interval(0.06)
	_flip_tween.tween_method(_set_kiwi_scale, kiwi_burst_scale, 0.98, 0.085).set_ease(Tween.EASE_IN_OUT)
	_flip_tween.tween_method(_set_kiwi_scale, 0.98, 1.0, 0.05).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(_finish_flip)


func _set_kiwi_scale(value: float) -> void:
	_portrait.scale = Vector2(value, lerpf(1.0, value, 0.78))


# 位移用独立 Tween，反复改档时统一取消并归零。
func _play_kiwi_shake() -> void:
	var amount: float = kiwi_shake_pixels
	_impact_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_impact_tween.tween_property(self, "position", Vector2(amount, -amount * 0.35), 0.025)
	_impact_tween.tween_property(self, "position", Vector2(-amount * 0.6, amount * 0.3), 0.028)
	_impact_tween.tween_property(self, "position", Vector2(amount * 0.28, -amount * 0.1), 0.032)
	_impact_tween.tween_property(self, "position", Vector2.ZERO, 0.055)


func _play_shudder() -> void:
	if _shudder_tween != null:
		_shudder_tween.kill()
	position = Vector2.ZERO
	_shudder_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_shudder_tween.tween_property(self, "position", Vector2(5.0, -2.0), 0.045)
	_shudder_tween.tween_property(self, "position", Vector2(-3.0, 1.0), 0.055)
	_shudder_tween.tween_property(self, "position", Vector2.ZERO, 0.07)


func _swap_at_edge() -> void:
	_portrait.texture = _pending_texture
	_display_scale = _pending_display_scale
	fx.play_impact()
	if _character_id == "kiwi":
		_play_kiwi_shake()


func _finish_flip() -> void:
	_flip_tween = null
	_pending_texture = null
	_portrait.scale = Vector2.ONE * _display_scale
	flip_finished.emit(current_tier)


func _refresh_pivot() -> void:
	if _portrait != null:
		_portrait.pivot_offset = size * 0.5


# ALIEN 的阶段图比 idle 横向扩张更明显，只缩小阶段图显示，不改原始 PNG 或卡片尺寸。
func _scale_for_texture(texture: Texture2D) -> float:
	if _character_id == "alien" and texture != null and texture != _idle:
		if texture == _tier_01 or texture == _tier_02 or texture == _tier_03:
			return alien_tier_scale
	return 1.0
