extends SceneTree

const SYSTEM_SCRIPT = preload("res://systems/contradiction_break/contradiction_break_system.gd")
const CONFIG_SCRIPT = preload("res://systems/contradiction_break/contradiction_window_config.gd")
const LEVEL = preload("res://data/level_configuration/level_001.tres")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_true_hit_breaks()
	_test_false_only_ends_unbroken()
	_test_empty_hit_ends_unbroken()
	if _failed > 0:
		quit(1)
	else:
		print("CB-05: 3 cases passed")
		quit(0)


# 每场沿用正式一发配置，首次发射后立即拒绝第二次发射。
func _make_system() -> ContradictionBreakSystem:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	system.load_level_content(LEVEL)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	system.start_window(config)
	_expect(system.register_launched_shot(), "first shot accepted")
	_expect(not system.register_launched_shot(), "one chance rejects second launch")
	return system


# 同发命中真假矛盾时按真矛盾形成成功，并固定首次结果。
func _test_true_hit_breaks() -> void:
	var system := _make_system()
	var hits: Array[String] = ["sample_contradiction_false_001", "sample_contradiction_true_001"]
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.BREAKTHROUGH, "true in one shot breaks")
	# 首次结果关闭攻击；重复解析和重开窗口均不能覆盖成功。
	_expect(not system.resolve_shot_hit_ids([]) and not system.start_window(CONFIG_SCRIPT.new()) and not system.can_launch_shot(), "first breakthrough stays fixed")
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.BREAKTHROUGH, "later requests preserve breakthrough")
	system.queue_free()


# 唯一一发只命中假矛盾，形成未击破结果并关闭攻击。
func _test_false_only_ends_unbroken() -> void:
	var system := _make_system()
	var hits: Array[String] = ["sample_contradiction_false_001"]
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN and not system.can_launch_shot(), "false only exhausts the one chance")
	system.queue_free()


# 唯一一发没有命中，仍消耗机会并形成未击破结果。
func _test_empty_hit_ends_unbroken() -> void:
	var system := _make_system()
	var hits: Array[String] = []
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN and not system.can_launch_shot(), "miss exhausts the one chance")
	system.queue_free()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
		return
	_failed += 1
	push_error("FAIL: " + description)
