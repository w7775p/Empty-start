extends SceneTree

const HitResolutionScript = preload("res://core/combat/hit_resolution.gd")
var _pk_updates: Array[float] = []


func _initialize() -> void:
	var mixed_result: bool = _test_mixed_contributions_use_independent_caps()
	var anomaly_result: bool = _test_anomaly_penalty_is_applied_once()
	var legacy_result: bool = _test_default_preserves_legacy_result()
	if mixed_result and anomaly_result and legacy_result:
		print("PASS HR-17 negative shot contribution cap and legacy default")
		quit(0)
	else:
		push_error("HR-17 negative contribution cap test failed.")
		quit(1)


func _test_mixed_contributions_use_independent_caps() -> bool:
	# 测试值仅用于验证正负独立封顶、异常并入负值后再计算净变化。
	_pk_updates.clear()
	var hit_resolution = HitResolutionScript.new(0.5, 0.0, 1.0, 0.4, 0.15)
	hit_resolution.final_player_pk_updated.connect(
		func(pk: float) -> void: _pk_updates.append(pk)
	)
	var shot_result: Dictionary = hit_resolution.resolve_shot_results(
		[
			{"pk_delta": 0.35, "tendency_delta": 3},
			{"pk_delta": 0.25, "tendency_delta": 7},
			{"pk_delta": -0.1, "tendency_delta": 0},
			{"pk_delta": -0.08, "tendency_delta": 0},
		],
		HitResolutionScript.ShotAnomaly.OBSTRUCTION
	)
	return (
		_pk_updates.size() == 1
		and is_equal_approx(_pk_updates[0], 0.75)
		and is_equal_approx(float(shot_result.get("total_pk_delta", -1.0)), 0.25)
		and is_equal_approx(float(shot_result.get("final_player_pk", -1.0)), 0.75)
		and (shot_result.get("target_results", []) as Array).size() == 4
	)


func _test_anomaly_penalty_is_applied_once() -> bool:
	# 负向上限未触发时仍能区分异常扣一次与重复扣分。
	_pk_updates.clear()
	var hit_resolution = HitResolutionScript.new(0.5, 0.0, 1.0, INF, 0.2)
	var shot_result: Dictionary = hit_resolution.resolve_shot_results(
		[{"pk_delta": -0.02}], HitResolutionScript.ShotAnomaly.BOUNCE
	)
	return (
		is_equal_approx(float(shot_result.get("total_pk_delta", -1.0)), -0.03)
		and is_equal_approx(float(shot_result.get("final_player_pk", -1.0)), 0.47)
	)


func _test_default_preserves_legacy_result() -> bool:
	# 保持旧三参数构造调用时，目标负值与单次落空扣分继续按原值合算。
	_pk_updates.clear()
	var hit_resolution = HitResolutionScript.new(0.5, 0.0, 1.0)
	var shot_result: Dictionary = hit_resolution.resolve_shot_results(
		[{"pk_delta": 0.3}, {"pk_delta": -0.04}], HitResolutionScript.ShotAnomaly.MISS
	)
	return (
		is_equal_approx(float(shot_result.get("total_pk_delta", -1.0)), 0.25)
		and is_equal_approx(float(shot_result.get("final_player_pk", -1.0)), 0.75)
	)
