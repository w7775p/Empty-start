extends SceneTree


func _initialize() -> void:
	var run_data := SaveData.new()
	var completed_attempt := HitResolution.new(0.5, 0.0, 1.0)
	completed_attempt.record_normal_word_hit("old-line", "orthodox")
	completed_attempt.commit_normal_hit_history(run_data)
	var previous: Array[Dictionary] = run_data.get_committed_normal_hit_history()
	var failed_attempt := HitResolution.new(0.5, 0.0, 1.0)
	failed_attempt.record_normal_word_hit("new-line", "absurd")
	failed_attempt.discard_uncommitted_normal_hit_history()
	var passed: bool = failed_attempt.get_normal_hit_history().is_empty()
	passed = passed and run_data.get_committed_normal_hit_history() == previous
	if passed:
		print("PASS HR-15 failed attempt discards pending hits and preserves committed history")
		quit(0)
	else:
		push_error("HR-15 failure rollback failed")
		quit(1)
