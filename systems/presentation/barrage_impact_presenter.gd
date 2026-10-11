class_name BarrageImpactPresenter
extends Control

const EFFECT_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_fx.gd")

@export_group("场上演出")
@export_range(1, 40, 1) var max_active_effects: int = 18
@export var effect_in_front: bool = true
@export_group("漫画符号")
@export var impact_symbol_texture: Texture2D = preload("res://assets/ui/combat/impact_marks/impact_01_razor.png")
@export_range(24, 156, 1) var impact_symbol_size: int = 76
@export var impact_symbol_offset: Vector2 = Vector2(4, -62)

var _attack: AttackChargeInput
var _effect_layer: Control
var _effects: Array[Control] = []


# 在独立战斗协调层把已有攻击信号绑定到表现组件；重绑时取消旧连接。
func bind_attack(attack: AttackChargeInput) -> void:
	if _attack != null and is_instance_valid(_attack):
		if _attack.shot_arrival_resolved.is_connected(_on_shot_arrival_resolved):
			_attack.shot_arrival_resolved.disconnect(_on_shot_arrival_resolved)
	_attack = attack
	if _attack != null:
		_attack.shot_arrival_resolved.connect(_on_shot_arrival_resolved)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_effect_layer = Control.new()
	_effect_layer.name = "ActiveImpactEffects"
	_effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_effect_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_effect_layer)
	if effect_in_front:
		_effect_layer.z_index = 6


# 消费真实目标/特性最终结果；CA-15 整发遮挡时只显示铁板硬碰，其他话语保持。
func _on_shot_arrival_resolved(_snapshot: AttackTargetSnapshot, target_results: Array[Dictionary]) -> void:
	var has_occlusion: bool = false
	var has_reflect: bool = false
	for fact: Dictionary in target_results:
		var hit: BarrageTraitResult = fact.get("trait_result") as BarrageTraitResult
		if hit == null:
			continue
		has_occlusion = has_occlusion or hit.kind == BarrageTraitResult.Kind.OCCLUSION
		has_reflect = has_reflect or hit.kind == BarrageTraitResult.Kind.REFLECT
	for fact: Dictionary in target_results:
		var view: BarrageView = fact.get("target") as BarrageView
		var hit: BarrageTraitResult = fact.get("trait_result") as BarrageTraitResult
		if view == null or hit == null or not is_instance_valid(view):
			continue
		if has_occlusion and not has_reflect and hit.kind != BarrageTraitResult.Kind.OCCLUSION:
			continue
		play_target_result(view, hit)


# 对单个真实命中事实播放材质动画；不控制本体删除、收益和子弹幕内容。
func play_target_result(target: BarrageView, result: BarrageTraitResult) -> BarrageImpactFx:
	if target == null or result == null or not is_instance_valid(target):
		return null
	if not target.is_inside_tree():
		return null
	_ensure_layer()
	_clean_finished()
	while _effects.size() >= max_active_effects:
		var old: Control = _effects.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var fx: BarrageImpactFx = EFFECT_SCRIPT.new() as BarrageImpactFx
	_effect_layer.add_child(fx)
	fx.position = _effect_layer.get_global_transform().affine_inverse() * target.global_position
	fx.accent_texture = impact_symbol_texture
	fx.accent_size = impact_symbol_size
	fx.accent_offset = impact_symbol_offset
	_effects.append(fx)

	var kind: BarrageTraitResult.Kind = result.kind
	if kind == BarrageTraitResult.Kind.OCCLUSION:
		fx.play_hard_hit(target)
	elif kind == BarrageTraitResult.Kind.REFLECT:
		fx.play_rebound(target)
	elif kind == BarrageTraitResult.Kind.RETALIATION_COPY:
		fx.play_fracture(target, &"retaliation_copy")
	elif target.get_special_material() == &"split":
		fx.play_fracture(target, &"split")
	elif kind == BarrageTraitResult.Kind.FAKE_CARD:
		fx.play_fracture(target, &"fake_card")
	else:
		fx.play_fracture(target, &"normal")
	return fx


# BT-06/弹幕生成创建真实两个子弹幕后调用，用已有子弹幕 Text/Tendency/Strength 表现。
func play_spawned_split_children(children: Array[BarrageView]) -> void:
	for child: BarrageView in children:
		if child == null or not is_instance_valid(child) or not child.is_inside_tree():
			continue
		if child.get_special_material() != &"glass":
			continue
		var original: Vector2 = child.scale
		child.scale = original * 0.58
		child.modulate.a = 0.0
		var t: Tween = child.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
		t.set_parallel(true)
		t.tween_property(child, "scale", original, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(child, "modulate:a", 1.0, 0.18)


# 场景重置/切关收起旧视觉副本，保留 BarrageArea 真实实例的销毁责任。
func reset_effects() -> void:
	_ensure_layer()
	for effect: Control in _effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_effects.clear()


func get_active_effect_count() -> int:
	_clean_finished()
	return _effects.size()


func _ensure_layer() -> void:
	if _effect_layer != null and is_instance_valid(_effect_layer):
		return
	_effect_layer = Control.new()
	_effect_layer.name = "ActiveImpactEffects"
	_effect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effect_layer)


func _clean_finished() -> void:
	for index in range(_effects.size() - 1, -1, -1):
		if not is_instance_valid(_effects[index]) or _effects[index].is_queued_for_deletion():
			_effects.remove_at(index)


func _exit_tree() -> void:
	bind_attack(null)
