extends SceneTree

const SYSTEM_SCRIPT = preload("res://systems/contradiction_break/contradiction_break_system.gd")
const CONFIG_SCRIPT = preload("res://systems/contradiction_break/contradiction_window_config.gd")
const LEVEL = preload("res://data/level_configuration/level_001.tres")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_remaining_chance_continues()
	_test_exhausted_chances_do_not_break()
	await _test_timeout_does_not_break()
	if _failed > 0:
		quit(1)
	else:
		print("CB-06: 3 cases passed")
		quit(0)


func _make_system(shots: int, seconds: float = 10.0) -> ContradictionBreakSystem:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	system.load_level_content(LEVEL)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	config.max_shots = shots
	config.duration_seconds = seconds
	system.start_window(config)
	return system


func _test_remaining_chance_continues() -> void:
	var system := _make_system(2)
	system.register_launched_shot()
	var hits: Array[String] = ["sample_contradiction_false_001"]
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.PENDING and system.can_launch_shot(), "remaining chance continues")
	system.queue_free()


func _test_exhausted_chances_do_not_break() -> void:
	var system := _make_system(1)
	system.register_launched_shot()
	var hits: Array[String] = []
	system.resolve_shot_hit_ids(hits)
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN and not system.can_launch_shot(), "exhausted chances give PK win without break")
	system.queue_free()


func _test_timeout_does_not_break() -> void:
	var system := _make_system(1, 0.02)
	await create_timer(0.08).timeout
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN and not system.can_launch_shot(), "timeout gives PK win without break")
	system.queue_free()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
		return
	_failed += 1
	push_error("FAIL: " + description)
