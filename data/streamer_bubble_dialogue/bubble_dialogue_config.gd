## 每场对白的静态配置和读取入口；队列及战斗状态由后续消费者持有。
class_name BubbleDialogueConfig
extends Resource

const Entry = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_entry.gd")
const ACTUAL_HIT_EVENT: StringName = &"actual_hit"
const ANY_SIDE: int = -1

@export var entries: Array[Entry] = []
@export_range(0.1, 60.0, 0.1, "or_greater") var hit_display_duration_seconds: float = 3.0


# 按稳定原句 ID 读取双方配置，保持策划填写顺序；空 ID 表示无关联原句。
func find_by_sentence(original_sentence_id: String, side: int = ANY_SIDE) -> Array[Entry]:
	var matches: Array[Entry] = []
	if original_sentence_id.is_empty():
		return matches
	for entry in entries:
		if entry != null and entry.original_sentence_id == original_sentence_id:
			if side == ANY_SIDE or entry.side == side:
				matches.append(entry)
	return matches


# 事件请求只返回匹配条目；可同时限定发言方和原句，显示顺序交给 SD-03。
func find_by_event(
	event_id: StringName, side: int = ANY_SIDE, original_sentence_id: String = ""
) -> Array[Entry]:
	var matches: Array[Entry] = []
	if event_id == &"":
		return matches
	for entry in entries:
		if entry == null or entry.event_id != event_id:
			continue
		if side != ANY_SIDE and entry.side != side:
			continue
		if not original_sentence_id.is_empty() and entry.original_sentence_id != original_sentence_id:
			continue
		matches.append(entry)
	return matches


# 消费最终命中事实生成玩家复述数据；收益正负均可，复读及落空返回空。
func create_hit_echo(
	original_sentence_id: String, original_sentence_text: String,
	is_valid_hit: bool, is_repeat: bool
) -> Entry:
	if not is_valid_hit or is_repeat or original_sentence_text.strip_edges().is_empty():
		return null
	var entry := Entry.new()
	entry.side = Entry.SpeakerSide.PLAYER
	entry.text = original_sentence_text
	entry.original_sentence_id = original_sentence_id
	entry.event_id = ACTUAL_HIT_EVENT
	entry.display_duration_seconds = hit_display_duration_seconds
	entry.priority = Entry.Priority.HIT
	return entry
