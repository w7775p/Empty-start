extends SceneTree

func _init() -> void:
	var passed_count: int = 0
	if _test_duplicate_completion_does_not_advance():
		passed_count += 1
		print("PASS: 重复提交同一关不会再次推进。")
	else:
		push_error("FAIL: 重复提交改变了关卡位置。")
	if _test_last_completion_marks_all_finished():
		passed_count += 1
		print("PASS: 最后一关完成后标记普通关卡结束。")
	else:
		push_error("FAIL: 最后一关完成后未标记普通关卡结束。")
	print("LC-06: %d/2 tests passed (advance/deduplicate, final completion)." % passed_count)
	quit(0 if passed_count == 2 else 1)

## 构造一个两关周目状态，测试关卡顺序与原句数据无关。
func _make_run_state() -> LevelRunState:
	var first_level: LevelProfile = LevelProfile.new()
	first_level.level_id = "level_001"
	first_level.level_order = 1
	var second_level: LevelProfile = LevelProfile.new()
	second_level.level_id = "level_002"
	second_level.level_order = 2
	var catalog: LevelCatalog = LevelCatalog.new()
	var profiles: Array[LevelProfile] = [first_level, second_level]
	catalog.profiles = profiles
	return LevelRunState.new(catalog)

## 同一 LevelRunState 中相同 level_id 再次提交时不重复推进。
func _test_duplicate_completion_does_not_advance() -> bool:
	var run_state: LevelRunState = _make_run_state()
	var first_result: int = run_state.complete_level("level_001")
	var repeated_result: int = run_state.complete_level("level_001")
	var current_level: LevelProfile = run_state.get_current_level_profile()
	return first_result == LevelRunState.CompletionResult.ADVANCED and repeated_result == LevelRunState.CompletionResult.ALREADY_COMPLETED and current_level != null and current_level.level_id == "level_002"

## 最后一关首次完成后报告普通关卡全部结束。
func _test_last_completion_marks_all_finished() -> bool:
	var run_state: LevelRunState = _make_run_state()
	run_state.complete_level("level_001")
	var result: int = run_state.complete_level("level_002")
	var current_level: LevelProfile = run_state.get_current_level_profile()
	return result == LevelRunState.CompletionResult.ALL_NORMAL_LEVELS_COMPLETED and run_state.is_all_normal_levels_completed() and current_level != null and current_level.level_id == "level_002"
