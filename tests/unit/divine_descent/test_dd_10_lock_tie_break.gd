extends SceneTree

const CANDIDATE_FILTER = preload("res://core/divine_descent/divine_descent_candidate_filter.gd")


# 验证当前权重及两层并列裁决；所有候选均为 TEST_ONLY 内存数据。
func _init() -> void:
	call_deferred("_run_tests")


# 汇总三项裁决规则，失败通过进程退出码交给调用方。
func _run_tests() -> void:
	var order_passed: bool = _test_earliest_committed_hit_wins()
	var id_passed: bool = _test_stable_original_sentence_id_wins()
	var weight_passed: bool = _test_current_weight_wins()
	quit(0 if order_passed and id_passed and weight_passed else 1)


# 基础权重与当前权重排名相反，锁句仍采用演出期间的当前权重。
func _test_current_weight_wins() -> bool:
	var candidates: Array[Dictionary] = [
		{"original_sentence_id": "test-line-a", "base_weight": 9, "weight": 6},
		{"original_sentence_id": "test-line-b", "base_weight": 1, "weight": 13},
	]
	if CANDIDATE_FILTER.select_highest_weight_candidate(candidates).get("original_sentence_id") != "test-line-b":
		push_error("FAIL DD-09 highest current weight wins")
		return false
	print("PASS DD-09 highest current weight wins")
	return true


# 最高权重并列时，较早命中优先；刻意让该句 ID 更大并重排输入。
func _test_earliest_committed_hit_wins() -> bool:
	var candidates: Array[Dictionary] = [
		{"original_sentence_id": "test-line-a", "weight": 10, "first_committed_hit_order": 8},
		{"original_sentence_id": "test-line-z", "weight": 10, "first_committed_hit_order": 2},
		{"original_sentence_id": "test-line-0", "weight": 9, "first_committed_hit_order": 1},
	]
	var selected: Dictionary = CANDIDATE_FILTER.select_highest_weight_candidate(candidates)
	var passed: bool = selected.get("original_sentence_id") == "test-line-z"
	candidates.reverse()
	selected = CANDIDATE_FILTER.select_highest_weight_candidate(candidates)
	passed = passed and selected.get("original_sentence_id") == "test-line-z"
	if not passed:
		push_error("FAIL DD-10 earliest committed normal hit wins")
		return false
	print("PASS DD-10 earliest committed normal hit wins")
	return true


# 权重与首次命中顺序都相同时，按原句 ID 的大小写敏感字符串升序锁句。
func _test_stable_original_sentence_id_wins() -> bool:
	var candidates: Array[Dictionary] = [
		{"original_sentence_id": "test-line-z", "weight": 10, "first_committed_hit_order": 4},
		{"original_sentence_id": "test-line-b", "weight": 10, "first_committed_hit_order": 4},
		{"original_sentence_id": "test-line-a", "weight": 10, "first_committed_hit_order": 4},
	]
	var selected: Dictionary = CANDIDATE_FILTER.select_highest_weight_candidate(candidates)
	var passed: bool = selected.get("original_sentence_id") == "test-line-a"
	candidates.reverse()
	selected = CANDIDATE_FILTER.select_highest_weight_candidate(candidates)
	passed = passed and selected.get("original_sentence_id") == "test-line-a"
	if not passed:
		push_error("FAIL DD-10 stable original sentence ID wins")
		return false
	print("PASS DD-10 stable original sentence ID wins")
	return true
