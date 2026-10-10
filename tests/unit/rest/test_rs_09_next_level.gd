extends SceneTree


# 同一双关流程覆盖普通下一关与末关终局路线。
func _init() -> void:
	if _test_continue_selects_next_normal_level():
		print("PASS RS-09/10：乱序目录进入下一关，末关进入终局，重复继续不推进")
		quit()
	else:
		push_error("FAIL RS-09：有下一关时未选择正确的普通关路线")
		quit(1)


# 临时乱序目录使用不连续序号，证明路由复用 LevelRunState 的顺序判断。
func _test_continue_selects_next_normal_level() -> bool:
	var first: LevelProfile = LevelProfile.new()
	first.level_id = "test_rs09_first"
	first.level_order = 1
	var next: LevelProfile = LevelProfile.new()
	next.level_id = "test_rs09_next"
	next.level_order = 3
	var catalog: LevelCatalog = LevelCatalog.new()
	catalog.profiles = [next, first]
	var run_state: LevelRunState = LevelRunState.new(catalog)
	var session: RestSession = RestSession.new()
	if not session.open_result({"level_id": first.level_id, "result_kind": "pk_win_unbroken"}):
		return false
	if session.continue_to_next_level(run_state) != LevelRunState.CompletionResult.ADVANCED or run_state.get_current_level_profile() != next:
		return false
	var last_rest := RestSession.new()
	if not last_rest.open_result({"level_id": next.level_id, "result_kind": "pk_win_unbroken"}):
		return false
	return (
		last_rest.continue_to_next_level(run_state) == LevelRunState.CompletionResult.ALL_NORMAL_LEVELS_COMPLETED
		and run_state.is_all_normal_levels_completed()
		and last_rest.continue_to_next_level(run_state) == LevelRunState.CompletionResult.ALREADY_COMPLETED
	)
