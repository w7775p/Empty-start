extends SceneTree

const HitResolutionScript = preload("res://core/combat/hit_resolution.gd")


func _initialize() -> void:
	var hit_resolution = HitResolutionScript.new(0.001, 0.0, 1.0)
	hit_resolution.apply_player_pk_delta(-0.001)
	var target_results: Array[Dictionary] = [
		{"pk_delta": 0.005, "tendency_delta": 10},
	]
	var shot_result: Dictionary = hit_resolution.resolve_shot_results(target_results)
	var remaining_targets: Array = shot_result.get("target_results", [])
	var test_passed: bool = (
		shot_result.get("cancelled_by_zero_pk", false)
		and is_equal_approx(shot_result.get("total_pk_delta", -1.0), 0.0)
		and is_equal_approx(shot_result.get("final_player_pk", -1.0), 0.0)
		and is_equal_approx(hit_resolution.get_player_pk(), 0.0)
		and remaining_targets.is_empty()
	)
	# 矛盾/终局关闭普通结算时，晚到正常收益与陷阱扣分都应丢弃且不广播 PK。
	var frozen_resolution := HitResolution.new(1.0, 0.0, 1.0)
	var updates: Array[float] = []
	frozen_resolution.final_player_pk_updated.connect(func(pk: float) -> void: updates.append(pk))
	frozen_resolution.set_normal_pk_resolution_enabled(false)
	var late_result: Dictionary = frozen_resolution.resolve_shot_results(target_results, HitResolution.ShotAnomaly.BOUNCE)
	frozen_resolution.apply_player_pk_delta(-0.1)
	test_passed = test_passed and late_result.get("terminal_mode", false) and late_result.get("target_results", [1]).is_empty()
	test_passed = test_passed and is_zero_approx(late_result.get("total_pk_delta", -1.0)) and is_equal_approx(frozen_resolution.get_player_pk(), 1.0) and updates.is_empty()
	if test_passed:
		print("PASS HR-08 zero PK cancels pending hit; closed normal resolution drops late rewards/penalties")
		quit(0)
	else:
		push_error("HR-08 pullback-to-zero priority test failed.")
		quit(1)
