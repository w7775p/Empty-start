extends SceneTree

func _init() -> void:
	var passed_count: int = 0
	if _test_new_run_starts_at_first_level():
		passed_count += 1
		print("PASS: 新一局默认读取序号最小的关卡。")
	else:
		push_error("FAIL: 新一局未读取序号最小的关卡。")
	if _test_changing_order_reads_selected_level():
		passed_count += 1
		print("PASS: 切换关卡序号后读取对应配置。")
	else:
		push_error("FAIL: 切换关卡序号后未读取对应配置。")
	if _test_restore_completed_campaign_for_terminal_resume():
		passed_count += 1
		print("PASS: 末关下播后可恢复终局上下文。")
	else:
		push_error("FAIL: 末关下播后的终局恢复校验失败。")
	print("LC-05: %d/3 tests passed." % passed_count)
	quit(0 if passed_count == 3 else 1)

## 构造乱序目录，确认流程状态按关卡序号定位，不依赖数组位置。
func _make_run_state() -> LevelRunState:
	var second_level: LevelProfile = LevelProfile.new()
	second_level.level_id = "level_002"
	second_level.level_order = 2
	var first_level: LevelProfile = LevelProfile.new()
	first_level.level_id = "level_001"
	first_level.level_order = 1
	var catalog: LevelCatalog = LevelCatalog.new()
	var profiles: Array[LevelProfile] = [second_level, first_level]
	catalog.profiles = profiles
	return LevelRunState.new(catalog)

## 新一局从关卡序号最小的配置开始。
func _test_new_run_starts_at_first_level() -> bool:
	var run_state: LevelRunState = _make_run_state()
	var current_level: LevelProfile = run_state.get_current_level_profile()
	return current_level != null and current_level.level_id == "level_001"

## 当前关卡切换到指定序号后，读取对应稳定关卡 ID。
func _test_changing_order_reads_selected_level() -> bool:
	var run_state: LevelRunState = _make_run_state()
	if not run_state.set_current_level_order(2):
		return false
	var current_level: LevelProfile = run_state.get_current_level_profile()
	return current_level != null and current_level.level_id == "level_002"

## 末关下播后应恢复终局上下文，且拒绝不完整或序号错误的终局存档。
func _test_restore_completed_campaign_for_terminal_resume() -> bool:
	var completed_run: LevelRunState = _make_run_state()
	if completed_run.complete_level("level_001") != LevelRunState.CompletionResult.ADVANCED:
		return false
	if completed_run.complete_level("level_002") != LevelRunState.CompletionResult.ALL_NORMAL_LEVELS_COMPLETED:
		return false

	var completed_ids: Array[String] = ["level_001", "level_002"]
	var restored: LevelRunState = _make_run_state()
	if not restored.restore_progress(2, completed_ids, true):
		return false
	var current: LevelProfile = restored.get_current_level_profile()
	if not restored.is_all_normal_levels_completed() or current == null or current.level_id != "level_002":
		return false

	var incomplete_ids: Array[String] = ["level_001"]
	var incomplete_restore: LevelRunState = _make_run_state()
	if incomplete_restore.restore_progress(2, incomplete_ids, true):
		return false

	var wrong_order_restore: LevelRunState = _make_run_state()
	return not wrong_order_restore.restore_progress(1, completed_ids, true)
