extends SceneTree

# 同一对手经过重开、关卡完成和新周目，检查连败记录的真实公开生命周期。
func _initialize() -> void:
	var opponent := OpponentPKBar.new()
	opponent.record_current_level_failure()
	opponent.reset_current_attempt()
	var retry_preserved: bool = opponent.get_loss_streak_count() == 1
	opponent.record_current_level_failure()
	var incremented: bool = opponent.get_loss_streak_count() == 2
	opponent.complete_current_level()
	var completed_reset: bool = opponent.get_loss_streak_count() == 0
	opponent.record_current_level_failure()
	opponent.start_new_run()
	var new_run_reset: bool = opponent.get_loss_streak_count() == 0
	var passed: bool = retry_preserved and incremented and completed_reset and new_run_reset
	opponent.free()
	if passed:
		print("PASS OP-09: retry preserves streak; failures accumulate; completion/new run reset")
	else:
		push_error("FAIL OP-09: retry=%s increment=%s completion=%s new_run=%s" % [retry_preserved, incremented, completed_reset, new_run_reset])
	quit(0 if passed else 1)
