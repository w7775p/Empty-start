extends SceneTree

const SYSTEM_SCRIPT = preload("res://systems/contradiction_break/contradiction_break_system.gd")
const CONFIG_SCRIPT = preload("res://systems/contradiction_break/contradiction_window_config.gd")
const CHARGE_SCRIPT = preload("res://systems/combat_attack/attack_charge_progress.gd")

var _failed: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_full_charge_consumes_one_shot()
	_test_undercharge_cancel_does_not_consume()
	if _failed > 0:
		quit(1)
	else:
		print("CB-04: 2 cases passed")
		quit(0)


# 攻击组件只有真正蓄满且消费蓄力时才会发出发射事实。
func _test_full_charge_consumes_one_shot() -> void:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	config.max_shots = 2
	system.start_window(config)
	var charge: AttackChargeProgress = CHARGE_SCRIPT.new(1.0)
	charge.advance(1.0, true)
	if charge.consume_fully_charged():
		system.register_launched_shot()
	_expect(system.get_remaining_shots() == 1, "full charge launch consumes one")
	system.queue_free()


# 未满蓄力取消没有快照事实，因此矛盾系统不会扣次数。
func _test_undercharge_cancel_does_not_consume() -> void:
	var system: ContradictionBreakSystem = SYSTEM_SCRIPT.new()
	root.add_child(system)
	var config: ContradictionWindowConfig = CONFIG_SCRIPT.new()
	config.max_shots = 2
	system.start_window(config)
	var charge: AttackChargeProgress = CHARGE_SCRIPT.new(1.0)
	charge.advance(0.3, true)
	charge.cancel_if_undercharged()
	if charge.consume_fully_charged():
		system.register_launched_shot()
	_expect(system.get_remaining_shots() == 2, "undercharge cancel keeps chance")
	system.queue_free()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
		return
	_failed += 1
	push_error("FAIL: " + description)
