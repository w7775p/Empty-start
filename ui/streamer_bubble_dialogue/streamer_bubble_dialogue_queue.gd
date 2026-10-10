extends Node

signal sequence_completed(sequence_id: StringName, side: int)

const PLAYER_SIDE: int = 0
const OPPONENT_SIDE: int = 1
const PLOT_PRIORITY: int = 2
const HIT_PRIORITY: int = 1
const TIMED_IDLE_PRIORITY: int = 0

var max_visible_bubbles_per_side: int = 3

var _display_bubble: Callable
var _clear_bubbles: Callable
var _pending_by_side: Dictionary = {0: [], 1: []}
var _active_by_side: Dictionary = {0: [], 1: []}
var _active_sequence_by_side: Dictionary = {0: null, 1: null}
var _side_enabled: Dictionary = {0: true, 1: true}
var _arrival_order: int = 0
var _sequence_counter: int = 0


# 队列只依赖展示和清理回调，气泡节点仍由 HUD/Stack 持有其视觉生命周期。
func configure(
	maximum_per_side: int, display_bubble: Callable, clear_bubbles: Callable
) -> void:
	max_visible_bubbles_per_side = maxi(maximum_per_side, 1)
	_display_bubble = display_bubble
	_clear_bubbles = clear_bubbles


# 单条请求按优先级调度；剧情单句也走序列路径以保证完成通知来自真实气泡结束。
func enqueue_entry(entry: BubbleDialogueEntry) -> bool:
	if not _is_entry_valid(entry) or not bool(_side_enabled.get(entry.side, false)):
		return false
	if entry.priority == BubbleDialogueEntry.Priority.PLOT:
		return not String(enqueue_sequence([entry])).is_empty()
	_enqueue_request({
		"entry": entry,
		"priority": int(entry.priority),
		"order": _next_arrival_order(),
	})
	_pump_side(entry.side)
	return true


# 同一侧剧情序列保持原数组顺序并连续播放，低优先级请求在序列完整播完后恢复。
func enqueue_sequence(
	entries: Array[BubbleDialogueEntry], sequence_id: StringName = &""
) -> StringName:
	if entries.is_empty():
		return &""
	var side: int = entries[0].side
	if not _is_side_valid(side) or not bool(_side_enabled.get(side, false)):
		return &""
	var copied_entries: Array[BubbleDialogueEntry] = []
	for entry: BubbleDialogueEntry in entries:
		if not _is_entry_valid(entry) or entry.side != side:
			return &""
		if entry.priority != BubbleDialogueEntry.Priority.PLOT:
			return &""
		copied_entries.append(entry)
	if String(sequence_id).is_empty():
		sequence_id = _new_sequence_id()
	_enqueue_request({
		"entries": copied_entries,
		"index": 0,
		"priority": PLOT_PRIORITY,
		"order": _next_arrival_order(),
		"sequence_id": sequence_id,
		"side": side,
	})
	_pump_side(side)
	return sequence_id


# T0 离线会拒绝该侧新请求并清除在播与待播对白；重新连线后显式启用。
func set_side_enabled(side: int, enabled: bool) -> void:
	if not _is_side_valid(side):
		return
	_side_enabled[side] = enabled
	if not enabled:
		clear_side(side)


# 重开或当前关切换时清除活动、待播和未完成序列，不产生完成信号。
func clear_side(side: int = -1) -> void:
	if side == -1:
		clear_side(PLAYER_SIDE)
		clear_side(OPPONENT_SIDE)
		return
	if not _is_side_valid(side):
		return
	_pending_by_side[side].clear()
	_active_by_side[side].clear()
	_active_sequence_by_side[side] = null
	if _clear_bubbles.is_valid():
		_clear_bubbles.call(side)


# 每侧独立泵送：剧情优先、命中其次、闲聊最低；同优先级按请求到达顺序。
func _pump_side(side: int) -> void:
	if not bool(_side_enabled.get(side, false)) or not _display_bubble.is_valid():
		return
	var active: Array = _active_by_side[side]
	var active_sequence: Variant = _active_sequence_by_side[side]
	if active_sequence != null:
		if active.is_empty():
			_show_next_sequence_line(side)
		return
	var pending: Array = _pending_by_side[side]
	var next_index: int = _find_next_request_index(pending)
	if next_index < 0:
		return
	var next_request: Dictionary = pending[next_index]
	var priority: int = int(next_request["priority"])
	if priority == PLOT_PRIORITY:
		_active_sequence_by_side[side] = pending.pop_at(next_index)
		_retire_active_below(side, PLOT_PRIORITY)
		if active.is_empty():
			_show_next_sequence_line(side)
		return
	if priority == HIT_PRIORITY:
		_retire_active_below(side, HIT_PRIORITY)
		if active.size() >= max_visible_bubbles_per_side:
			_retire_oldest_hit(side)
			return
		pending.remove_at(next_index)
		var entry: BubbleDialogueEntry = next_request["entry"]
		if _show_entry(side, entry, int(next_request["order"]), &""):
			_pump_side(side)
		return
	if _has_active_higher_priority(side, TIMED_IDLE_PRIORITY):
		return
	if active.size() >= max_visible_bubbles_per_side:
		return
	pending.remove_at(next_index)
	var idle_entry: BubbleDialogueEntry = next_request["entry"]
	if _show_entry(side, idle_entry, int(next_request["order"]), &""):
		_pump_side(side)


# 序列中的下一句只会在上一只气泡发出 expired 后创建。
func _show_next_sequence_line(side: int) -> void:
	var request: Dictionary = _active_sequence_by_side[side]
	var entries: Array[BubbleDialogueEntry] = request["entries"]
	var index: int = int(request["index"])
	if index >= entries.size():
		_complete_sequence(side, request)
		return
	var entry: BubbleDialogueEntry = entries[index]
	if not _show_entry(side, entry, int(request["order"]), StringName(request["sequence_id"])):
		push_error("StreamerBubbleDialogueQueue: 剧情气泡显示失败，序列已中止。")
		_active_sequence_by_side[side] = null
		_pump_side(side)


# 展示栈负责实例化及到期回收；队列用同一 expired 信号释放名额和推进序列。
func _show_entry(
	side: int, entry: BubbleDialogueEntry, order: int, sequence_id: StringName
) -> bool:
	var candidate: Variant = _display_bubble.call(entry)
	if candidate == null or not candidate is StreamerBubbleView:
		push_error("StreamerBubbleDialogueQueue: 展示接口没有返回有效气泡。")
		return false
	var bubble: StreamerBubbleView = candidate
	var record: Dictionary = {
		"view": bubble,
		"priority": int(entry.priority),
		"order": order,
		"sequence_id": sequence_id,
		"retiring": false,
	}
	_active_by_side[side].append(record)
	bubble.expired.connect(_on_bubble_expired.bind(side, record))
	return true


# Tween 真正结束后释放队列名额；序列完成信号晚于最后一句的完整显示和渐隐。
func _on_bubble_expired(_bubble: StreamerBubbleView, side: int, record: Dictionary) -> void:
	_active_by_side[side].erase(record)
	var sequence_id: StringName = record["sequence_id"]
	if not String(sequence_id).is_empty():
		var sequence: Variant = _active_sequence_by_side[side]
		if sequence != null and sequence["sequence_id"] == sequence_id:
			sequence["index"] = int(sequence["index"]) + 1
			if int(sequence["index"]) >= sequence["entries"].size():
				_complete_sequence(side, sequence)
	_pump_side(side)


# 完成通知只在所有配置句子的实际气泡寿命结束后发出。
func _complete_sequence(side: int, sequence: Dictionary) -> void:
	var sequence_id: StringName = sequence["sequence_id"]
	_active_sequence_by_side[side] = null
	sequence_completed.emit(sequence_id, side)


# 新剧情或命中请求提前淡出较低优先级气泡，渐隐期间仍计入同侧显示名额。
func _retire_active_below(side: int, minimum_priority: int) -> void:
	for record: Dictionary in _active_by_side[side]:
		if int(record["priority"]) >= minimum_priority or bool(record["retiring"]):
			continue
		record["retiring"] = true
		var bubble: StreamerBubbleView = record["view"]
		if is_instance_valid(bubble):
			bubble.finish_early()


# 满额时只提前结束最早到达、仍在正常显示的即时命中气泡。
func _retire_oldest_hit(side: int) -> void:
	var oldest: Dictionary = {}
	for record: Dictionary in _active_by_side[side]:
		if int(record["priority"]) != HIT_PRIORITY or bool(record["retiring"]):
			continue
		if oldest.is_empty() or int(record["order"]) < int(oldest["order"]):
			oldest = record
	if oldest.is_empty():
		return
	oldest["retiring"] = true
	var bubble: StreamerBubbleView = oldest["view"]
	if is_instance_valid(bubble):
		bubble.finish_early()


func _has_active_higher_priority(side: int, priority: int) -> bool:
	for record: Dictionary in _active_by_side[side]:
		if int(record["priority"]) > priority:
			return true
	return false


# 待播队列按优先级降序、同优先级到达序升序选择。
func _find_next_request_index(pending: Array) -> int:
	var best_index: int = -1
	for index in range(pending.size()):
		var request: Dictionary = pending[index]
		if best_index < 0:
			best_index = index
			continue
		var best: Dictionary = pending[best_index]
		if int(request["priority"]) > int(best["priority"]):
			best_index = index
		elif int(request["priority"]) == int(best["priority"]):
			if int(request["order"]) < int(best["order"]):
				best_index = index
	return best_index


func _enqueue_request(request: Dictionary) -> void:
	var side: int = int(request.get("side", -1))
	if side < 0:
		var entry: BubbleDialogueEntry = request.get("entry")
		side = entry.side if entry != null else -1
	_pending_by_side[side].append(request)


func _next_arrival_order() -> int:
	_arrival_order += 1
	return _arrival_order


func _new_sequence_id() -> StringName:
	_sequence_counter += 1
	return StringName("bubble_sequence_%d" % _sequence_counter)


func _is_entry_valid(entry: BubbleDialogueEntry) -> bool:
	return entry != null and _is_side_valid(entry.side) and not entry.text.strip_edges().is_empty()


func _is_side_valid(side: int) -> bool:
	return side == PLAYER_SIDE or side == OPPONENT_SIDE
