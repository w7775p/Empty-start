extends SceneTree

const SYSTEM_SCRIPT = preload("res://systems/contradiction_break/contradiction_break_system.gd")
const CONFIG_SCRIPT = preload("res://systems/contradiction_break/contradiction_window_config.gd")
const LEVEL = preload("res://data/level_configuration/level_001.tres")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	system.load_level_content(LEVEL)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	config.max_shots = 2
	system.start_window(config)
	system.register_launched_shot()
	var hits: Array[String] = ["sample_contradiction_true_001"]
	system.resolve_shot_hit_ids(hits)
	var first_outcome: ContradictionBreakSystem.Outcome = system.get_outcome()
	var later_hits: Array[String] = []
	var accepted_later: bool = system.resolve_shot_hit_ids(later_hits)
	var restarted: bool = system.start_window(config)
	var passed: bool = system.is_result_locked() and first_outcome == ContradictionBreakSystem.Outcome.BREAKTHROUGH and system.get_outcome() == first_outcome and not accepted_later and not restarted and not system.can_launch_shot()
	if passed:
		print("PASS: first outcome remains fixed and attacks close")
		print("CB-07: 1 case passed")
		quit(0)
	else:
		push_error("FAIL: first outcome was changed or attack stayed open")
		quit(1)
