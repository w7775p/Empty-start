extends SceneTree


func _initialize() -> void:
	var run_data := SaveData.new()
	var first_attempt := HitResolution.new(0.5, 0.0, 1.0)
	first_attempt.record_normal_word_hit("line-a", "orthodox")
	first_attempt.record_normal_word_hit("line-b", "absurd")
	first_attempt.record_normal_word_hit("line-a", "orthodox")
	# 合并原 HR-14 的原句归并与顺序边界，再沿真实提交 API 检查跨关累计。
	var pending: Array[Dictionary] = first_attempt.get_normal_hit_history()
	var merged: bool = pending.size() == 2
	merged = merged and pending[0].get("original_sentence_id") == "line-a" and pending[0].get("tendency") == "orthodox"
	merged = merged and pending[0].get("hit_count") == 2 and pending[0].get("first_hit_order") == 1 and pending[0].get("last_hit_order") == 3
	var first_ok: bool = first_attempt.commit_normal_hit_history(run_data)
	var second_attempt := HitResolution.new(0.5, 0.0, 1.0)
	second_attempt.record_normal_word_hit("line-b", "absurd")
	second_attempt.record_normal_word_hit("line-c", "heretical")
	var second_ok: bool = second_attempt.commit_normal_hit_history(run_data)
	var history: Array[Dictionary] = run_data.get_committed_normal_hit_history()
	var passed: bool = merged and first_ok and second_ok and not second_attempt.commit_normal_hit_history(run_data)
	passed = passed and history.size() == 3
	passed = passed and history[0]["hit_count"] == 2 and history[0]["first_committed_hit_order"] == 1
	passed = passed and history[1]["hit_count"] == 2 and history[1]["first_committed_hit_order"] == 2
	passed = passed and history[2]["hit_count"] == 1 and history[2]["first_committed_hit_order"] == 3
	# 去重提交要复查存档结果；只检查返回 false 无法发现“报拒绝但仍累计”。
	passed = passed and run_data.get_committed_normal_hit_history() == history
	if passed:
		print("PASS HR-15 PK win commits cumulative normal history with stable first order")
		quit(0)
	else:
		push_error("HR-15 win commit failed")
		quit(1)
