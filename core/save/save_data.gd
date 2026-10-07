class_name SaveData
extends Resource

const CURRENT_VERSION: int = 1

@export var save_version: int = CURRENT_VERSION
@export var play_time: float = 0.0
@export var current_scene: String = ""
@export var checkpoint_id: String = ""

# 新周目尚未完成身份确认时留空；确认后由 SaveManager 一次写入玩家侧身份数据。
@export var streamer_name: String = ""
@export var fan_group_name: String = ""
@export var identity_id: StringName = &""

# 直播数据系统持有本场表现状态；随当前周目存档跨场景保留粉丝数。
@export var live_session: LiveSessionData = LiveSessionData.new()

# 吞并系统保存当前周目累计的主播、词库权重和特性成果。
@export var assimilation_data: AssimilationData = AssimilationData.new()

# 圣典系统持有当前周目已保存及待写入的经文记录。
@export var scripture_data: ScriptureData = ScriptureData.new()

# 三项倾向系统持有精确累计值与开局身份对应倾向参照。
@export var tendency_state: TendencyState = TendencyState.new()

# 只保存各次 PK 胜利正式提交的普通话语历史；首次提交顺序跨关递增。
@export var committed_normal_hit_history: Array[Dictionary] = []
@export var next_normal_hit_commit_order: int = 1


func get_committed_normal_hit_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in committed_normal_hit_history:
		result.append(entry.duplicate(true))
	return result
