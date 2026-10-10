extends SceneTree

# TEST_ONLY 一秒蓄力状态路径；取消后重新蓄力，满蓄只能消费一次。
# 此纯逻辑测试不宣称验证鼠标、候选变化或“没有发射”。
func _init() -> void:
	var charge := AttackChargeProgress.new(1.0)
	charge.advance(0.4, true)
	var canceled: bool = charge.cancel_if_undercharged() and is_zero_approx(charge.get_progress())
	charge.advance(0.5, false)
	var idle: bool = is_zero_approx(charge.get_progress())
	charge.advance(0.5, true)
	var partial: bool = not charge.is_fully_charged() and not charge.consume_fully_charged()
	charge.advance(0.5, true)
	var full: bool = charge.is_fully_charged() and not charge.cancel_if_undercharged()
	var consumed: bool = charge.consume_fully_charged() and not charge.consume_fully_charged()
	var passed: bool = canceled and idle and partial and full and consumed and is_zero_approx(charge.get_progress())
	if passed:
		print("PASS CA charge: undercharge cancels, released input stays idle, full charge consumes once")
	else:
		push_error("FAIL CA charge: canceled=%s idle=%s partial=%s full=%s consumed=%s" % [canceled, idle, partial, full, consumed])
	quit(0 if passed else 1)
