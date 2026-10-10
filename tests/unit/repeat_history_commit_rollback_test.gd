extends SceneTree

const REPEAT_PLAN = preload("res://core/repeat/repeat_plan.gd")
const REPEAT_STATS = preload("res://core/repeat/repeat_generation_stats.gd")
const SAVE_DATA = preload("res://core/save/save_data.gd")


# 只运行 RP-10 指定的提交与回滚两项单元测试。
func _init() -> void:
	call_deferred("_run_tests")


# 同时检查返回值与真实保存字段，失败时返回非零退出码。
func _run_tests() -> void:
	var commit_passed: bool = _test_commit()
	var rollback_passed: bool = _test_rollback()
	quit(0 if commit_passed and rollback_passed else 1)


# 通过 RP-09 记录实际生成，再提交普通快照；同关重报和矛盾生成不会污染历史。
func _test_commit() -> bool:
	var run_data := SAVE_DATA.new()
	var previous := REPEAT_STATS.new()
	previous.record_generated(_make_plan(REPEAT_PLAN.RepeatType.NORMAL, &"same_line"), 2)
	var passed: bool = previous.commit_normal_repeat_history(run_data, &"previous_level")
	var stats := REPEAT_STATS.new()
	stats.record_generated(_make_plan(REPEAT_PLAN.RepeatType.NORMAL, &"same_line"), 3)
	stats.record_generated(_make_plan(REPEAT_PLAN.RepeatType.CONTRADICTION, &"contradiction_line"), 7)
	passed = passed and stats.get_normal_count(&"same_line") == 3 and stats.get_contradiction_count(&"contradiction_line") == 7
	passed = passed and stats.get_normal_count(&"contradiction_line") == 0 and stats.get_contradiction_count(&"same_line") == 0
	passed = passed and stats.commit_normal_repeat_history(run_data, &"current_level")
	passed = passed and not stats.commit_normal_repeat_history(run_data, &"current_level")
	var replay := REPEAT_STATS.new()
	passed = passed and not replay.commit_normal_repeat_history(run_data, &"current_level")
	var current: Dictionary = run_data.committed_normal_repeat_history_by_level[&"current_level"]
	passed = passed and current == {&"same_line": 3}
	passed = passed and run_data.committed_normal_repeat_history_by_level[&"previous_level"] == {&"same_line": 2}
	# 提交后本场统计仍可供神谕读取，修改运行统计也不会回写已保存快照。
	stats.discard_uncommitted_normal_repeat_history()
	passed = passed and stats.get_normal_count(&"same_line") == 3
	stats.record_generated(_make_plan(REPEAT_PLAN.RepeatType.NORMAL, &"same_line"), 1)
	passed = passed and current[&"same_line"] == 3
	# 原生存读必须保留两关快照；使用独占临时路径，绕开用户正式存档。
	var save_path: String = "user://test_repeat_history_%d.tres" % OS.get_process_id()
	var save_error: Error = ResourceSaver.save(run_data, save_path)
	var restored: SaveData = null
	if save_error == OK:
		restored = ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	passed = passed and restored != null
	if restored != null:
		passed = passed and restored.committed_normal_repeat_history_by_level == run_data.committed_normal_repeat_history_by_level
	if not passed:
		push_error("RP-10 commit failed")
		return false
	print("PASS RP-10 commit: normal snapshot once, previous history preserved, contradiction excluded")
	return true


# 回滚只清本次普通暂存；以前关卡快照保留，重开的新统计可独立提交。
func _test_rollback() -> bool:
	var run_data := SAVE_DATA.new()
	var previous := REPEAT_STATS.new()
	previous.record_generated(_make_plan(REPEAT_PLAN.RepeatType.NORMAL, &"previous_line"), 4)
	var passed: bool = previous.commit_normal_repeat_history(run_data, &"previous_level")
	var saved_before: Dictionary = run_data.committed_normal_repeat_history_by_level.duplicate(true)
	var failed := REPEAT_STATS.new()
	failed.record_generated(_make_plan(REPEAT_PLAN.RepeatType.NORMAL, &"failed_line"), 5)
	failed.record_generated(_make_plan(REPEAT_PLAN.RepeatType.CONTRADICTION, &"contradiction_line"), 2)
	failed.discard_uncommitted_normal_repeat_history()
	passed = passed and failed.get_normal_count(&"failed_line") == 0
	passed = passed and failed.get_contradiction_count(&"contradiction_line") == 2
	passed = passed and run_data.committed_normal_repeat_history_by_level == saved_before
	var retry := REPEAT_STATS.new()
	retry.record_generated(_make_plan(REPEAT_PLAN.RepeatType.NORMAL, &"retry_line"), 1)
	passed = passed and retry.commit_normal_repeat_history(run_data, &"current_level")
	passed = passed and run_data.committed_normal_repeat_history_by_level[&"current_level"] == {&"retry_line": 1}
	passed = passed and run_data.committed_normal_repeat_history_by_level[&"previous_level"] == saved_before[&"previous_level"]
	if not passed:
		push_error("RP-10 rollback failed")
		return false
	print("PASS RP-10 rollback: failed attempt discarded, previous committed history preserved")
	return true


# 计划数量故意大于实际数量，确保历史只来自 record_generated 的实际结果。
func _make_plan(repeat_type: int, line_id: StringName) -> Resource:
	var plan := REPEAT_PLAN.new()
	plan.repeat_type = repeat_type
	plan.original_line_id = line_id
	plan.planned_repeat_count = 100
	return plan
