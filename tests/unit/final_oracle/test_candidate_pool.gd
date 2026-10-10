extends SceneTree

const HIT_RESOLUTION = preload("res://core/combat/hit_resolution.gd")
const CANDIDATE_POOL = preload("res://core/final_oracle/final_oracle_candidate_pool.gd")
const REPEAT_PLAN = preload("res://core/repeat/repeat_plan.gd")
const REPEAT_STATS = preload("res://core/repeat/repeat_generation_stats.gd")
const SAVE_DATA = preload("res://core/save/save_data.gd")
const CONFIRMATION_STATE = preload("res://core/final_oracle/final_oracle_confirmation_state.gd")

var _confirmation_events: Array[Dictionary] = []


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await process_frame
	if not _test_duplicate_history_rows_are_one_candidate():
		quit(1)
		return
	if not _test_only_normal_hit_history_enters_pool():
		quit(1)
		return
	if not _test_highest_normal_repeat_per_tendency():
		quit(1)
		return
	if not _test_latest_hit_breaks_repeat_tie():
		quit(1)
		return
	if not _test_stable_sentence_id_breaks_final_tie():
		quit(1)
		return
	if not _test_fill_candidates_to_three():
		quit(1)
		return
	if not _test_auto_pick_uses_formal_order():
		quit(1)
		return
	if not _test_same_run_level_confirms_once():
		quit(1)
		return
	print("通过：FO-02 至 FO-09 候选生成、排序、超时选择与单次确认")
	quit()


# 同一原句的 String / StringName ID 只形成一个候选。
func _test_duplicate_history_rows_are_one_candidate() -> bool:
	var pool = CANDIDATE_POOL.new()
	var history: Array[Dictionary] = [
		{
			"original_sentence_id": "line-a",
			"tendency": "orthodox",
			"hit_count": 1,
			"first_hit_order": 1,
			"last_hit_order": 1,
		},
		{
			"original_sentence_id": &"line-a",
			"tendency": "orthodox",
			"hit_count": 2,
			"first_hit_order": 1,
			"last_hit_order": 3,
		},
	]
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history(history)
	if candidates.size() != 1 or str(candidates[0].get("original_sentence_id", "")) != "line-a":
		push_error("FO-02 同一原句的 String / StringName ID 必须只形成一句候选")
		return false
	return true


# 候选只从 HR-14 普通历史建立；复读与矛盾文本由其他入口处理，不作为候选来源。
func _test_only_normal_hit_history_enters_pool() -> bool:
	var hit_resolution = HIT_RESOLUTION.new(0.5, 0.0, 1.0)
	hit_resolution.record_normal_word_hit("line-a", "orthodox")
	hit_resolution.record_normal_word_hit("line-a", "orthodox")
	hit_resolution.record_normal_word_hit("neutral-line", "neutral")
	var pool = CANDIDATE_POOL.new()
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history(
		hit_resolution.get_normal_hit_history()
	)
	if candidates.size() != 1 or str(candidates[0].get("original_sentence_id", "")) != "line-a":
		push_error("FO-02 候选池只能包含 HR-14 提供的普通话语原句")
		return false
	if int(candidates[0].get("hit_count", 0)) != 2:
		push_error("FO-02 候选应保留 HR-14 聚合后的原句命中次数")
		return false
	return true


# 同倾向选择普通复读数最高者，矛盾复读数不参与比较。
func _test_highest_normal_repeat_per_tendency() -> bool:
	var pool = CANDIDATE_POOL.new()
	var history: Array[Dictionary] = [
		_make_history_entry("line-a", "orthodox"),
		_make_history_entry("line-b", "orthodox"),
		_make_history_entry("line-c", "heretical"),
		_make_history_entry("line-d", "absurd"),
	]
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history(history)
	var repeat_stats: RepeatGenerationStats = REPEAT_STATS.new()
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-a"), 2)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-b"), 5)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-c"), 3)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.CONTRADICTION, &"line-a"), 10)
	var selected: Array[Dictionary] = pool.select_most_repeated_per_tendency(candidates, repeat_stats)
	if selected.size() != 3:
		push_error("FO-03 应为每种存在候选的倾向最多选出一句")
		return false
	var selected_by_tendency: Dictionary = {}
	for candidate: Dictionary in selected:
		selected_by_tendency[str(candidate.get("tendency", ""))] = str(
			candidate.get("original_sentence_id", "")
		)
	if (
		selected_by_tendency.get("orthodox", "") != "line-b"
		or selected_by_tendency.get("heretical", "") != "line-c"
		or selected_by_tendency.get("absurd", "") != "line-d"
	):
		push_error("FO-03 没有按每种倾向的实际普通复读数选择最高候选")
		return false
	return true


func _make_history_entry(original_sentence_id: String, tendency: String) -> Dictionary:
	return {
		"original_sentence_id": original_sentence_id,
		"tendency": tendency,
		"hit_count": 1,
		"first_hit_order": 1,
		"last_hit_order": 1,
	}


func _make_candidate_history_entry(
		original_sentence_id: String, tendency: String, hit_count: int, last_hit_order: int
	) -> Dictionary:
	var history_entry: Dictionary = _make_history_entry(original_sentence_id, tendency)
	history_entry["hit_count"] = hit_count
	history_entry["last_hit_order"] = last_hit_order
	return history_entry


# 普通复读数相同时，最近命中优先级高于原句 ID 顺序。
func _test_latest_hit_breaks_repeat_tie() -> bool:
	var earlier_hit: Dictionary = _make_history_entry("line-a", "orthodox")
	earlier_hit["last_hit_order"] = 7
	var later_hit: Dictionary = _make_history_entry("line-z", "orthodox")
	later_hit["last_hit_order"] = 8
	var pool = CANDIDATE_POOL.new()
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history([earlier_hit, later_hit])
	var repeat_stats: RepeatGenerationStats = REPEAT_STATS.new()
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-a"), 2)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-z"), 2)
	var selected: Array[Dictionary] = pool.select_most_repeated_per_tendency(candidates, repeat_stats)
	if selected.size() != 1 or str(selected[0].get("original_sentence_id", "")) != "line-z":
		push_error("FO-04 普通复读并列时应优先选择最近命中的原句")
		return false
	return true


# 普通复读数和最近命中顺序均相同时，按原句 ID 升序稳定裁决。
func _test_stable_sentence_id_breaks_final_tie() -> bool:
	var later_id: Dictionary = _make_history_entry("line-z", "orthodox")
	later_id["last_hit_order"] = 8
	var earlier_id: Dictionary = _make_history_entry("line-a", "orthodox")
	earlier_id["last_hit_order"] = 8
	var pool = CANDIDATE_POOL.new()
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history([later_id, earlier_id])
	var repeat_stats: RepeatGenerationStats = REPEAT_STATS.new()
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-a"), 2)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-z"), 2)
	var selected: Array[Dictionary] = pool.select_most_repeated_per_tendency(candidates, repeat_stats)
	if selected.size() != 1 or str(selected[0].get("original_sentence_id", "")) != "line-a":
		push_error("FO-04 双层并列时应按稳定原句 ID 升序裁决")
		return false
	return true


# 缺少倾向时按普通命中历史补位，遵守三句上限并保留不足三句时的实际数量。
func _test_fill_candidates_to_three() -> bool:
	var pool = CANDIDATE_POOL.new()
	var history: Array[Dictionary] = [
		_make_candidate_history_entry("line-main", "orthodox", 1, 1),
		_make_candidate_history_entry("line-z", "orthodox", 10, 20),
		_make_candidate_history_entry("line-b", "orthodox", 10, 20),
		_make_candidate_history_entry("line-a", "orthodox", 10, 21),
		_make_candidate_history_entry("line-low-hit-new", "orthodox", 9, 100),
	]
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history(history)
	var repeat_stats: RepeatGenerationStats = REPEAT_STATS.new()
	repeat_stats.record_generated(
		_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-main"), 200
	)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-z"), 50)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-a"), 99)
	repeat_stats.record_generated(
		_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-low-hit-new"), 199
	)
	var final_candidates: Array[Dictionary] = pool.fill_missing_tendency_candidates(
		candidates, repeat_stats
	)
	if final_candidates.size() != 3:
		push_error("FO-05 候选不足三种倾向时应补位至三句上限")
		return false
	var selected_ids: Array[String] = []
	for candidate: Dictionary in final_candidates:
		selected_ids.append(str(candidate.get("original_sentence_id", "")))
	if selected_ids != ["line-main", "line-low-hit-new", "line-a"]:
		push_error("FO-05 补位应按普通复读次数、最近命中时间、原句 ID 排序")
		return false

	var short_history: Array[Dictionary] = [
		_make_candidate_history_entry("short-a", "orthodox", 1, 1),
		_make_candidate_history_entry("short-b", "heretical", 1, 2),
	]
	var short_candidates: Array[Dictionary] = pool.build_from_normal_hit_history(short_history)
	var short_final_candidates: Array[Dictionary] = pool.fill_missing_tendency_candidates(
		short_candidates, repeat_stats
	)
	if short_final_candidates.size() != 2:
		push_error("FO-05 合格普通话语少于三句时应返回实际数量")
		return false
	return true


# 超时自动选择只从展示快照取句，并使用复读数、最近命中、原句 ID 的正式排序。
func _test_auto_pick_uses_formal_order() -> bool:
	var pool = CANDIDATE_POOL.new()
	var history: Array[Dictionary] = [
		_make_candidate_history_entry("line-b", "orthodox", 1, 9),
		_make_candidate_history_entry("line-a", "orthodox", 1, 8),
		_make_candidate_history_entry("line-z", "orthodox", 1, 9),
	]
	var candidates: Array[Dictionary] = pool.build_from_normal_hit_history(history)
	var repeat_stats: RepeatGenerationStats = REPEAT_STATS.new()
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-b"), 5)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-a"), 5)
	repeat_stats.record_generated(_make_repeat_plan(REPEAT_PLAN.RepeatType.NORMAL, &"line-z"), 5)
	var final_candidates: Array[Dictionary] = pool.fill_missing_tendency_candidates(
		candidates, repeat_stats
	)
	var display_candidates: Array[Dictionary] = pool.snapshot_for_display(final_candidates)
	var selected: Dictionary = pool.select_auto_pick_from_display(display_candidates, repeat_stats)
	if str(selected.get("original_sentence_id", "")) != "line-b":
		push_error("FO-08 自动选择没有遵循普通复读、最近命中、原句 ID 顺序")
		return false
	return true


# 手动和自动结果共用同一入口；同一 SaveData 与关卡只广播首次候选。
func _test_same_run_level_confirms_once() -> bool:
	_confirmation_events.clear()
	var run_data: SaveData = SAVE_DATA.new()
	var confirmation_state = CONFIRMATION_STATE.new(run_data)
	confirmation_state.confirmation_committed.connect(_record_confirmation_event)
	var manual_candidate: Dictionary = {"original_sentence_id": "manual-line", "tendency": "orthodox"}
	var automatic_candidate: Dictionary = {"original_sentence_id": "automatic-line", "tendency": "absurd"}
	if not confirmation_state.confirm_selection("level_001", manual_candidate):
		push_error("FO-09 首次手动确认应成功")
		return false
	if confirmation_state.confirm_selection("level_001", automatic_candidate):
		push_error("FO-09 自动确认不得覆盖同一关卡的手动结果")
		return false
	if (
		str(confirmation_state.get_confirmed_selection("level_001").get("original_sentence_id", ""))
		!= "manual-line"
		or _confirmation_events.size() != 1
	):
		push_error("FO-09 重复确认应保留首条结果且只广播一次")
		return false
	if not confirmation_state.confirm_selection("level_002", automatic_candidate):
		push_error("FO-09 不同关卡应使用独立提交身份")
		return false
	var next_run_state = CONFIRMATION_STATE.new(SAVE_DATA.new())
	if not next_run_state.confirm_selection("level_001", automatic_candidate):
		push_error("FO-09 新周目应拥有独立提交身份")
		return false
	return true


func _record_confirmation_event(
		run_data: SaveData, level_id: String, candidate: Dictionary
	) -> void:
	_confirmation_events.append(
		{"run_data": run_data, "level_id": level_id, "candidate": candidate.duplicate(true)}
	)


func _make_repeat_plan(repeat_type: int, original_line_id: StringName) -> RepeatPlan:
	var plan: RepeatPlan = REPEAT_PLAN.new()
	plan.repeat_type = repeat_type
	plan.original_line_id = original_line_id
	return plan
