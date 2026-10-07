class_name FinalOracleSession
extends RefCounted

signal opened(level_id: String, candidates: Array[Dictionary])

var _level_id: String = ""
var _display_candidates: Array[Dictionary] = []
var _open: bool = false
var _confirmation_state: FinalOracleConfirmationState
var _repeat_stats: RepeatGenerationStats


# 只接收已完成矛盾过渡的本场事实，使用现有候选池冻结一次展示列表。
func open_after_breakthrough(
	level_id: String,
	normal_hit_history: Array[Dictionary],
	repeat_stats: RepeatGenerationStats,
	confirmation_state: FinalOracleConfirmationState
) -> bool:
	if _open or level_id.is_empty() or repeat_stats == null or confirmation_state == null:
		return false
	var pool := FinalOracleCandidatePool.new()
	var eligible: Array[Dictionary] = pool.build_from_normal_hit_history(normal_hit_history)
	var candidates: Array[Dictionary] = pool.fill_missing_tendency_candidates(eligible, repeat_stats)
	_display_candidates = pool.snapshot_for_display(candidates)
	_level_id = level_id
	_confirmation_state = confirmation_state
	_repeat_stats = repeat_stats
	_open = true
	opened.emit(_level_id, get_display_candidates())
	return true


func is_open() -> bool:
	return _open


func get_level_id() -> String:
	return _level_id


func get_display_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate: Dictionary in _display_candidates:
		result.append(candidate.duplicate(true))
	return result


# 读取同一周目、同一关卡已有的首次确认，避免重开后重新开放选择。
func get_confirmed_selection() -> Dictionary:
	if not _open or _confirmation_state == null:
		return {}
	return _confirmation_state.get_confirmed_selection(_level_id)


# 超时只从本次冻结的候选中按普通复读统计选择，不重新构造或排序展示列表。
func select_timeout_candidate() -> Dictionary:
	if not _open or _repeat_stats == null:
		return {}
	var pool := FinalOracleCandidatePool.new()
	return pool.select_auto_pick_from_display(_display_candidates, _repeat_stats)


# 手动或超时选择只允许提交冻结展示列表中的一句，并复用 FO-09 的单次确认入口。
func confirm_display_candidate(candidate: Dictionary) -> bool:
	if not _open or _confirmation_state == null:
		return false
	var sentence_id: String = str(candidate.get("original_sentence_id", ""))
	if sentence_id.is_empty():
		return false
	for displayed: Dictionary in _display_candidates:
		if str(displayed.get("original_sentence_id", "")) == sentence_id:
			return _confirmation_state.confirm_selection(_level_id, displayed)
	return false
