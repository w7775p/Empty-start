class_name SaveData
extends Resource

const CURRENT_VERSION: int = 1

@export var save_version: int = CURRENT_VERSION
@export var play_time: float = 0.0
@export var current_scene: String = ""
@export var checkpoint_id: String = ""

# 离开战斗回到独立房间时保留普通关卡进度。
@export var next_normal_level_order: int = 1
@export var completed_normal_level_ids: Array[String] = []
# 末关选择下播后仍需从房间恢复到既有终局流程。
@export var normal_campaign_completed: bool = false
# 教学只保存稳定步骤 ID，观察与提示仍由现有运行器持有。
@export var completed_tutorial_step_ids: Array[String] = []
# 结局保存显示快照，读档回看不重新发奖或重跑终局。
@export var ending_display_data: Dictionary = {}
# 正常终局已保存、片尾未完成；读档续播原结尾，不能凭快照直接解锁。
@export var ending_roll_pending: bool = false

# 新周目尚未完成身份确认时留空；确认后由 SaveManager 一次写入玩家侧身份数据。
@export var streamer_name: String = ""
@export var fan_group_name: String = ""
@export var identity_id: StringName = &""

# 直播数据系统持有本场表现状态；随当前周目存档跨场景保留粉丝数。
@export var live_session: LiveSessionData = LiveSessionData.new()
## 对手各自拥有数据实例；缺少正式初始粉丝时保留0，不从观众模板推算人口。
@export var opponent_live_sessions: Dictionary = {}


# 吞并系统保存当前周目累计的主播、词库权重和特性成果。
@export var assimilation_data: AssimilationData = AssimilationData.new()

# 败者卡系统保存本周目已获得的稳定主播 ID 与发卡提交身份。
@export var loser_card_data: LoserCardData = LoserCardData.new()

# 圣典系统持有当前周目已保存及待写入的经文记录。
@export var scripture_data: ScriptureData = ScriptureData.new()

# 三项倾向系统持有精确累计值与开局身份对应倾向参照。
@export var tendency_state: TendencyState = TendencyState.new()

# 只保存各次 PK 胜利正式提交的普通话语历史；首次提交顺序跨关递增。
@export var committed_normal_hit_history: Array[Dictionary] = []
@export var next_normal_hit_commit_order: int = 1

# Repeat 按关卡保存 PK 胜利时的普通实际生成统计；键为关卡 ID，值为原句 ID 到数量。
@export var committed_normal_repeat_history_by_level: Dictionary = {}


func get_committed_normal_hit_history() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in committed_normal_hit_history:
		result.append(entry.duplicate(true))
	return result


## 按真实主播ID读取独立直播数据；切关与重开不会串到玩家或其他主播。
func get_opponent_live_session(streamer_id: String) -> LiveSessionData:
	if streamer_id.is_empty():
		return null
	if not opponent_live_sessions.has(streamer_id):
		opponent_live_sessions[streamer_id] = LiveSessionData.new()
	return opponent_live_sessions[streamer_id] as LiveSessionData
