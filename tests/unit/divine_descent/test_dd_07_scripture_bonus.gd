extends SceneTree

const CANDIDATE_FILTER = preload("res://core/divine_descent/divine_descent_candidate_filter.gd")


# 一份权重池同时验证最大基础加成、跨章去重和池外经文排除。
func _init() -> void:
	var normal_passed: bool = _test_normal_bonus()
	quit(0 if normal_passed else 1)


# 使用真实 DD-06 输出验证统一最大基础加成，池外经文不会追加候选。
func _test_normal_bonus() -> bool:
	var candidates: Array[Dictionary] = [
		{"original_sentence_id": "line-a", "hit_count": 3, "normal_repeat_count": 5},
		{"original_sentence_id": "line-b", "hit_count": 1, "normal_repeat_count": 2},
		{"original_sentence_id": "line-c", "hit_count": 1, "normal_repeat_count": 0},
	]
	var base_candidates: Array[Dictionary] = CANDIDATE_FILTER.calculate_base_weights(candidates)
	var entries: Array[Dictionary] = [
		{"original_sentence_id": "line-a", "chapter_number": 1},
		{"original_sentence_id": "line-b", "chapter_number": 2},
		{"original_sentence_id": &"line-b", "chapter_number": 4},
		{"original_sentence_id": "outside-pool", "chapter_number": 3},
	]
	var result: Array[Dictionary] = CANDIDATE_FILTER.apply_scripture_bonus(base_candidates, entries)
	var passed: bool = result.size() == 3
	passed = passed and result[0]["weight"] == 16 and result[1]["weight"] == 11 and result[2]["weight"] == 1
	passed = passed and result[0]["original_sentence_id"] == "line-a" and result[1]["original_sentence_id"] == "line-b"
	if not passed:
		push_error("DD-07 normal scripture bonus failed")
		return false
	print("PASS DD-07: max base 8 -> weights 16/11/1; duplicate chapters add once; outside pool excluded")
	return true
