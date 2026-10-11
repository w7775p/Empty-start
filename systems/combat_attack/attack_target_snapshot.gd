class_name AttackTargetSnapshot
extends RefCounted

var _target_instance_ids: Array[int] = []
var _contradiction_facts: Array[Dictionary] = []
var _occlusion_target_instance_ids: Array[int] = []
var _aim_center_global_position: Vector2 = Vector2.ZERO


# 在释放时复制候选实例 ID 和准心中心；之后候选列表变化不会加入本发。
static func capture_at_release(
		current_candidates: Array[Node], aim_center_global_position: Vector2 = Vector2.ZERO
) -> AttackTargetSnapshot:
	var snapshot := AttackTargetSnapshot.new()
	snapshot._aim_center_global_position = aim_center_global_position
	var seen_instance_ids: Dictionary = {}

	for target in current_candidates:
		if not is_instance_valid(target):
			continue

		var instance_id: int = target.get_instance_id()
		if seen_instance_ids.has(instance_id):
			continue

		seen_instance_ids[instance_id] = true
		snapshot._target_instance_ids.append(instance_id)
		# Paradox 在释放同一帧使用这份文本事实，之后实例移动或离树都不能改变判定。
		if target is BarrageView:
			var view := target as BarrageView
			if (view.runtime_record != null and view.runtime_record.trait_set != null
					and view.runtime_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION)):
				# 整发规则读取释放瞬间的原始特性 ID，不受 reflect 等单目标结果优先级影响。
				snapshot._occlusion_target_instance_ids.append(instance_id)
			if view.runtime_record != null and view.runtime_record.is_contradiction:
				snapshot._contradiction_facts.append({
					"target_instance_id": instance_id,
					"original_sentence_id": view.runtime_record.original_sentence_id,
					"original_sentence_text": view.runtime_record.original_sentence_text,
				})

	return snapshot


# 返回 ID 副本，调用方不能修改已经冻结的本发目标集合。
func get_target_instance_ids() -> Array[int]:
	return _target_instance_ids.duplicate()


# 返回释放瞬间带遮挡特性的原始目标 ID，飞行期间的结果优先级不会改写快照事实。
func get_occlusion_target_instance_ids() -> Array[int]:
	return _occlusion_target_instance_ids.duplicate()


# 返回释放瞬间的矛盾原句副本；命中判定不依赖飞行后实例是否仍在场。
func get_contradiction_facts() -> Array[Dictionary]:
	var facts: Array[Dictionary] = []
	for fact: Dictionary in _contradiction_facts:
		facts.append(fact.duplicate(true))
	return facts


# 返回释放瞬间的准心中心；多神谕同发命中时用它稳定裁决最近目标。
func get_aim_center_global_position() -> Vector2:
	return _aim_center_global_position


# 复核释放快照中的选择目标仍属于当前可见候选集合。
func resolve_present_selection_targets(
		active_selection_targets: Array[Control]
) -> Array[Control]:
	var present_targets: Array[Control] = []
	var selectable_instance_ids: Dictionary = {}
	for target: Control in active_selection_targets:
		if target == null or not is_instance_valid(target):
			continue
		if not target.is_inside_tree() or target.is_queued_for_deletion() or not target.is_visible_in_tree():
			continue
		selectable_instance_ids[target.get_instance_id()] = true

	for instance_id in _target_instance_ids:
		if not selectable_instance_ids.has(instance_id):
			continue
		var target: Object = instance_from_id(instance_id)
		if not is_instance_valid(target) or not target is Control:
			continue
		var control: Control = target as Control
		if not control.is_inside_tree() or control.is_queued_for_deletion() or not control.is_visible_in_tree():
			continue
		present_targets.append(control)
	return present_targets


# 到达时按 BarrageGeneration 的真实实例状态复核；目标移动不重新检查原准心。
func resolve_present_targets(active_barrage_area: BarrageArea) -> Array[Node]:
	var present_targets: Array[Node] = []
	if not is_instance_valid(active_barrage_area) or not active_barrage_area.is_inside_tree() or active_barrage_area.is_queued_for_deletion():
		return present_targets

	var current_time_msec: int = Time.get_ticks_msec()
	var active_area_rect: Rect2 = active_barrage_area.get_global_rect()
	for instance_id in _target_instance_ids:
		var target: Object = instance_from_id(instance_id)
		if not is_instance_valid(target) or not target is BarrageView:
			continue

		var barrage_view := target as BarrageView
		if not barrage_view.is_inside_tree() or barrage_view.is_queued_for_deletion():
			continue
		if barrage_view.get_parent() != active_barrage_area or barrage_view.runtime_record == null:
			continue
		if current_time_msec >= barrage_view.runtime_record.expires_at_msec:
			continue
		if not active_area_rect.intersects(barrage_view.get_global_rect()):
			continue

		present_targets.append(barrage_view)
	return present_targets
