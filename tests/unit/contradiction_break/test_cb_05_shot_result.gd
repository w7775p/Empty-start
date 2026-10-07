extends SceneTree

const SYSTEM_SCRIPT = preload("res://systems/contradiction_break/contradiction_break_system.gd")
const CONFIG_SCRIPT = preload("res://systems/contradiction_break/contradiction_window_config.gd")
const LEVEL = preload("res://data/level_configuration/level_001.tres")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_true_hit_breaks()
	_test_false_only_continues()
	_test_empty_hit_continues()
	if _failed > 0:
		quit(1)
	else:
		print("CB-05: 3 cases passed")
		quit(0)


func _make_system() -> ContradictionBreakSystem:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	system.load_level_content(LEVEL)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	config.max_shots = 2
	system.start_window(config)
	system.register_launched_shot()
	return system


func _test_true_hit_breaks() -> void:
	var system := _make_system()
	var hits: Array[String] = ["sample_contradiction_false_001", "sample_contradiction_true_001"]
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.BREAKTHROUGH, "true in one shot breaks")
	system.queue_free()


func _test_false_only_continues() -> void:
	var system := _make_system()
	var hits: Array[String] = ["sample_contradiction_false_001"]
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.PENDING and system.get_remaining_shots() == 1 and system.can_launch_shot(), "false only consumes and continues")
	system.queue_free()


func _test_empty_hit_continues() -> void:
	var system := _make_system()
	var hits: Array[String] = []
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.PENDING and system.get_remaining_shots() == 1 and system.can_launch_shot(), "empty hit consumes and continues")
	system.queue_free()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
		return
	_failed += 1
	push_error("FAIL: " + description)
