extends SceneTree

const SYSTEM_SCRIPT = preload("res://systems/contradiction_break/contradiction_break_system.gd")
const CONFIG_SCRIPT = preload("res://systems/contradiction_break/contradiction_window_config.gd")
const LEVEL = preload("res://data/level_configuration/level_001.tres")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_timeout_does_not_break()
	if _failed > 0:
		quit(1)
	else:
		print("CB-06: 1 timeout case passed")
		quit(0)


# 仅缩短 TEST_ONLY 等待时间，发射次数沿用正式一发配置。
func _test_timeout_does_not_break() -> void:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	system.load_level_content(LEVEL)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	config.duration_seconds = 0.02
	system.start_window(config)
	await create_timer(0.08).timeout
	_expect(system.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN and not system.can_launch_shot(), "timeout gives PK win without break")
	system.queue_free()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
		return
	_failed += 1
	push_error("FAIL: " + description)
