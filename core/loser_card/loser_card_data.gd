class_name LoserCardData
extends Resource

# 周目只保存稳定主播 ID，卡面与文案继续从静态 Catalog 读取。
@export var acquired_streamer_ids: Array[StringName] = []
@export var rewarded_level_ids: Array[StringName] = []


# 击破成功且神谕正式确认后获得对应资料库卡片，同场只提交一次。
func grant_on_true_defeat(
		level_id: StringName, streamer_id: StringName,
		contradiction_broken: bool, oracle_confirmed: bool, catalog: LoserCardCatalog
	) -> bool:
	if level_id.is_empty() or streamer_id.is_empty() or catalog == null:
		return false
	if not contradiction_broken or not oracle_confirmed or catalog.find_profile(streamer_id) == null:
		return false
	if rewarded_level_ids.has(level_id):
		return false
	rewarded_level_ids.append(level_id)
	acquired_streamer_ids.append(streamer_id)
	return true
