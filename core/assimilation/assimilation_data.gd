class_name AssimilationData
extends Resource

@export var completed_streamer_ids: Array[StringName] = []
@export var defeated_streamer_ids: Array[StringName] = []

# 当前周目已经记录普通通关结果的关卡 ID，与击败提交分开保存。
@export var completed_level_ids: Array[StringName] = []

# 当前周目中已经正式提交真正击败结果的关卡 ID。
@export var defeated_level_ids: Array[StringName] = []

# 键为稳定词库 ID，值为该词库继承后的出现权重。
@export var inherited_word_weights: Dictionary = {}

@export var inherited_trait_ids: Array[StringName] = []


# 击破成功且神谕正式确认后登记；周目由本 Resource 所属 SaveData 确定。
func register_defeated_streamer(
		level_id: StringName, streamer_id: StringName,
		contradiction_broken: bool, oracle_confirmed: bool
	) -> bool:
	if level_id.is_empty() or streamer_id.is_empty():
		return false
	if not contradiction_broken or not oracle_confirmed:
		return false
	if defeated_level_ids.has(level_id) or defeated_streamer_ids.has(streamer_id):
		return false
	_register_completed_streamer(level_id, streamer_id)
	defeated_level_ids.append(level_id)
	defeated_streamer_ids.append(streamer_id)
	return true


# 仅登记已真正击败关卡允许继承的普通词库；稳定 pool_id 保留首次权重。
func register_inherited_word_pool(
		level_id: StringName, pool_id: StringName, appearance_weight: float,
		can_inherit: bool, is_contradiction_pool: bool
	) -> bool:
	if not defeated_level_ids.has(level_id) or pool_id.is_empty() or appearance_weight < 0.0:
		return false
	if not can_inherit or is_contradiction_pool or inherited_word_weights.has(pool_id):
		return false
	inherited_word_weights[pool_id] = appearance_weight
	return true


# 只登记当前击败关卡允许继承的稳定特性 ID；不同来源共享同一去重集合。
func register_inherited_trait(level_id: StringName, trait_id: StringName, can_inherit: bool) -> bool:
	if not defeated_level_ids.has(level_id) or trait_id.is_empty() or not can_inherit:
		return false
	if inherited_trait_ids.has(trait_id):
		return false
	inherited_trait_ids.append(trait_id)
	return true


# PK 胜利登记通关；击破且正式确认后再登记真正击败，返回本次新增的两类事实。
func register_level_result(
		level_id: StringName, streamer_id: StringName, pk_won: bool,
		contradiction_broken: bool, oracle_confirmed: bool
	) -> Dictionary:
	var changes: Dictionary = {"completed_added": false, "defeated_added": false}
	if level_id.is_empty() or streamer_id.is_empty() or not pk_won:
		return changes
	changes["completed_added"] = _register_completed_streamer(level_id, streamer_id)
	changes["defeated_added"] = register_defeated_streamer(
		level_id, streamer_id, contradiction_broken, oracle_confirmed
	)
	return changes


# 通关按周目内关卡去重，主播集合仍按稳定 ID 去重。
func _register_completed_streamer(level_id: StringName, streamer_id: StringName) -> bool:
	if completed_level_ids.has(level_id):
		return false
	completed_level_ids.append(level_id)
	if not completed_streamer_ids.has(streamer_id):
		completed_streamer_ids.append(streamer_id)
	return true
