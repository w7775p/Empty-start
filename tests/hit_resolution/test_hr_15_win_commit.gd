extends SceneTree


func _initialize() -> void:
	var run_data := SaveData.new()
	var first_attempt := HitResolution.new(0.5, 0.0, 1.0)
	first_attempt.record_normal_word_hit("line-a", "orthodox")
	first_attempt.record_normal_word_hit("line-b", "absurd")
	first_attempt.record_normal_word_hit("line-a", "orthodox")
	var first_ok: bool = first_attempt.commit_normal_hit_history(run_data)
	var second_attempt := HitResolution.new(0.5, 0.0, 1.0)
	second_attempt.record_normal_word_hit("line-b", "absurd")
	second_attempt.record_normal_word_hit("line-c", "heretical")
	var second_ok: bool = second_attempt.commit_normal_hit_history(run_data)
	var history: Array[Dictionary] = run_data.get_committed_normal_hit_history()
	var passed: bool = first_ok and second_ok and not second_attempt.commit_normal_hit_history(run_data)
	passed = passed and history.size() == 3 and run_data.next_normal_hit_commit_order == 4
	passed = passed and history[0]["hit_count"] == 2 and history[0]["first_committed_hit_order"] == 1
	passed = passed and history[1]["hit_count"] == 2 and history[1]["first_committed_hit_order"] == 2
	passed = passed and history[2]["hit_count"] == 1 and history[2]["first_committed_hit_order"] == 3
	if passed:
		print("PASS HR-15 PK win commits cumulative normal history with stable first order")
		quit(0)
	else:
		push_error("HR-15 win commit failed")
		quit(1)
