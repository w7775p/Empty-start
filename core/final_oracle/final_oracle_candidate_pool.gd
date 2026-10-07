class_name FinalOracleCandidatePool
extends RefCounted

const _TENDENCY_ORDER: Array[String] = ["orthodox", "heretical", "absurd"]
const _MAX_CANDIDATE_COUNT: int = 3


# 从 HR-14 的普通命中快照按原句 ID 去重，保留首次出现的历史记录顺序。
func build_from_normal_hit_history(normal_hit_history: Array[Dictionary]) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var seen_sentence_ids: Dictionary = {}
	for history_entry: Dictionary in normal_hit_history:
		if not history_entry.has("original_sentence_id"):
			continue
		var original_sentence_id: Variant = history_entry["original_sentence_id"]
		if original_sentence_id == null:
			continue
		var stable_sentence_id: String = str(original_sentence_id)
		if stable_sentence_id.is_empty() or seen_sentence_ids.has(stable_sentence_id):
			continue
		seen_sentence_ids[stable_sentence_id] = true
		candidates.append(history_entry.duplicate(true))
	return candidates


# 每种有候选的倾向保留普通复读数最高的一句，并按最近命中和稳定原句 ID 裁决并列。
func select_most_repeated_per_tendency(
		candidates: Array[Dictionary], repeat_stats: RepeatGenerationStats
	) -> Array[Dictionary]:
	var best_candidates_by_tendency: Dictionary = {}
	var best_repeat_counts_by_tendency: Dictionary = {}
	for candidate: Dictionary in candidates:
		var tendency_id: String = str(candidate.get("tendency", ""))
		if not _TENDENCY_ORDER.has(tendency_id):
			continue
		var original_sentence_id: Variant = candidate.get("original_sentence_id")
		if original_sentence_id == null:
			continue
		var repeat_count: int = repeat_stats.get_normal_count(StringName(str(original_sentence_id)))
		var should_replace: bool = not best_candidates_by_tendency.has(tendency_id)
		if not should_replace:
			should_replace = _is_better_repeat_ranked_candidate(
				candidate,
				repeat_count,
				best_candidates_by_tendency[tendency_id],
				int(best_repeat_counts_by_tendency[tendency_id])
			)
		if should_replace:
			best_candidates_by_tendency[tendency_id] = candidate
			best_repeat_counts_by_tendency[tendency_id] = repeat_count

	var selected_candidates: Array[Dictionary] = []
	for tendency_id: String in _TENDENCY_ORDER:
		if best_candidates_by_tendency.has(tendency_id):
			selected_candidates.append(best_candidates_by_tendency[tendency_id].duplicate(true))
	return selected_candidates


# 超时只从展示快照中选择普通复读数最高的一句，并沿用正式并列规则。
func select_auto_pick_from_display(
		display_candidates: Array[Dictionary], repeat_stats: RepeatGenerationStats
	) -> Dictionary:
	var best_candidate: Dictionary = {}
	var best_repeat_count: int = -1
	for candidate: Dictionary in display_candidates:
		var original_sentence_id: Variant = candidate.get("original_sentence_id")
		if original_sentence_id == null or str(original_sentence_id).is_empty():
			continue
		var repeat_count: int = repeat_stats.get_normal_count(StringName(str(original_sentence_id)))
		if (
			best_candidate.is_empty()
			or _is_better_repeat_ranked_candidate(
				candidate, repeat_count, best_candidate, best_repeat_count
			)
		):
			best_candidate = candidate
			best_repeat_count = repeat_count
	return best_candidate.duplicate(true)


# 正式排序统一按普通复读数降序、最近命中顺序降序、原句 ID 升序比较。
func _is_better_repeat_ranked_candidate(
		candidate: Dictionary,
		candidate_repeat_count: int,
		current_best: Dictionary,
		current_repeat_count: int
	) -> bool:
	if candidate_repeat_count != current_repeat_count:
		return candidate_repeat_count > current_repeat_count
	var candidate_last_hit_order: int = int(candidate.get("last_hit_order", 0))
	var current_last_hit_order: int = int(current_best.get("last_hit_order", 0))
	if candidate_last_hit_order != current_last_hit_order:
		return candidate_last_hit_order > current_last_hit_order
	return str(candidate.get("original_sentence_id", "")) < str(
		current_best.get("original_sentence_id", "")
	)


# 倾向领头候选不足三句时，按普通复读次数、最近命中顺序和原句 ID 补位。
func fill_missing_tendency_candidates(
		candidates: Array[Dictionary], repeat_stats: RepeatGenerationStats
	) -> Array[Dictionary]:
	var final_candidates: Array[Dictionary] = select_most_repeated_per_tendency(
		candidates, repeat_stats
	)
	var selected_sentence_ids: Dictionary = {}
	for candidate: Dictionary in final_candidates:
		selected_sentence_ids[str(candidate.get("original_sentence_id", ""))] = true

	while final_candidates.size() < _MAX_CANDIDATE_COUNT:
		var best_fallback_candidate: Dictionary = {}
		var best_repeat_count: int = -1
		for candidate: Dictionary in candidates:
			var original_sentence_id: Variant = candidate.get("original_sentence_id")
			var tendency_id: String = str(candidate.get("tendency", ""))
			if original_sentence_id == null or not _TENDENCY_ORDER.has(tendency_id):
				continue
			var stable_sentence_id: String = str(original_sentence_id)
			if stable_sentence_id.is_empty() or selected_sentence_ids.has(stable_sentence_id):
				continue
			var repeat_count: int = repeat_stats.get_normal_count(StringName(stable_sentence_id))
			if (
				best_fallback_candidate.is_empty()
				or _is_better_repeat_ranked_candidate(candidate, repeat_count, best_fallback_candidate, best_repeat_count)
			):
				best_fallback_candidate = candidate
				best_repeat_count = repeat_count
		if best_fallback_candidate.is_empty():
			break

		var selected_sentence_id: String = str(
			best_fallback_candidate.get("original_sentence_id", "")
		)
		selected_sentence_ids[selected_sentence_id] = true
		final_candidates.append(best_fallback_candidate.duplicate(true))
	return final_candidates


# 选择开放时复制当前候选及其顺序；调用方保留快照用于整个选择阶段的显示。
func snapshot_for_display(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var display_snapshot: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		display_snapshot.append(candidate.duplicate(true))
	return display_snapshot
