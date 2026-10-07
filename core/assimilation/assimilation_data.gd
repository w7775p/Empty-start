class_name AssimilationData
extends Resource

@export var completed_streamer_ids: Array[StringName] = []
@export var defeated_streamer_ids: Array[StringName] = []

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
	defeated_level_ids.append(level_id)
	defeated_streamer_ids.append(streamer_id)
	return true
