extends SceneTree

const HitResolutionScript = preload("res://core/combat/hit_resolution.gd")
var _pk_updates: Array[float] = []


func _initialize() -> void:
	var cap_result: bool = _test_positive_contribution_cap_keeps_target_results()
	var default_result: bool = _test_default_preserves_uncapped_aggregate()
	if cap_result and default_result:
		print("PASS HR-16 positive shot contribution cap and legacy default")
		quit(0)
	else:
		push_error("HR-16 positive contribution cap test failed.")
		quit(1)


func _test_positive_contribution_cap_keeps_target_results() -> bool:
	# 有限上限只在测试中注入；多目标正收益合并封顶后再与负收益相抵。
	_pk_updates.clear()
	var hit_resolution = HitResolutionScript.new(0.95, 0.0, 1.0, 0.5)
	hit_resolution.final_player_pk_updated.connect(
		func(pk: float) -> void: _pk_updates.append(pk)
	)
	var target_results: Array[Dictionary] = [
		{"pk_delta": 0.4, "tendency_delta": 3, "is_valid_hit": true},
		{"pk_delta": 0.35, "tendency_delta": 7, "is_valid_hit": true},
		{"pk_delta": -0.1, "tendency_delta": 0, "is_valid_hit": true},
	]
	# 使用现有复读结果接口，验证零收益有效命中仍随逐目标结果返回。
	target_results.append(hit_resolution.calculate_repeat_hit_result())
	var shot_result: Dictionary = hit_resolution.resolve_shot_results(target_results)
	var resolved_targets: Array = shot_result.get("target_results", [])
	return (
		_pk_updates.size() == 1
		and is_equal_approx(_pk_updates[0], 1.0)
		and is_equal_approx(float(shot_result.get("total_pk_delta", -1.0)), 0.4)
		and is_equal_approx(float(shot_result.get("final_player_pk", -1.0)), 1.0)
		and resolved_targets.size() == 4
		and is_equal_approx(float(resolved_targets[0].get("pk_delta", -1.0)), 0.4)
		and resolved_targets[0].get("tendency_delta", -1) == 3
		and resolved_targets[0].get("is_valid_hit", false)
		and is_equal_approx(float(resolved_targets[1].get("pk_delta", -1.0)), 0.35)
		and resolved_targets[1].get("tendency_delta", -1) == 7
		and resolved_targets[1].get("is_valid_hit", false)
		and resolved_targets[3].get("is_valid_hit", false)
		and is_zero_approx(float(resolved_targets[3].get("pk_delta", -1.0)))
		and resolved_targets[3].get("tendency_delta", -1) == 0
	)


func _test_default_preserves_uncapped_aggregate() -> bool:
	# 策划尚未确认正式值时，旧调用形式继续按原始正负贡献求和。
	_pk_updates.clear()
	var hit_resolution = HitResolutionScript.new(0.2, 0.0, 1.0)
	hit_resolution.final_player_pk_updated.connect(
		func(pk: float) -> void: _pk_updates.append(pk)
	)
	var shot_result: Dictionary = hit_resolution.resolve_shot_results([
		{"pk_delta": 0.4, "tendency_delta": 3},
		{"pk_delta": 0.35, "tendency_delta": 7},
		{"pk_delta": -0.1, "tendency_delta": 0},
	])
	return (
		_pk_updates.size() == 1
		and is_equal_approx(_pk_updates[0], 0.85)
		and is_equal_approx(float(shot_result.get("total_pk_delta", -1.0)), 0.65)
		and is_equal_approx(float(shot_result.get("final_player_pk", -1.0)), 0.85)
	)
