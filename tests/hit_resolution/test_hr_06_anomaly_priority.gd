extends SceneTree

const HitResolutionScript = preload("res://core/combat/hit_resolution.gd")


func _initialize() -> void:
	var hit_resolution = HitResolutionScript.new(0.5, 0.0, 1.0)
	var failed_count: int = 0

	if hit_resolution.select_shot_anomaly(true, true, true) != HitResolutionScript.ShotAnomaly.BOUNCE:
		push_error("HR-06 bounce must take priority over obstruction and miss.")
		failed_count += 1
	else:
		print("PASS HR-06 bounce priority")

	if hit_resolution.select_shot_anomaly(false, true, true) != HitResolutionScript.ShotAnomaly.OBSTRUCTION:
		push_error("HR-06 obstruction must take priority over miss.")
		failed_count += 1
	else:
		print("PASS HR-06 obstruction priority")

	if hit_resolution.select_shot_anomaly(false, false, true) != HitResolutionScript.ShotAnomaly.MISS:
		push_error("HR-06 miss must be selected when no bounce or obstruction exists.")
		failed_count += 1
	else:
		print("PASS HR-06 miss fallback")

	if hit_resolution.select_shot_anomaly(true, false, false, true) != HitResolutionScript.ShotAnomaly.MISS:
		push_error("A release snapshot with occlusion must force the whole shot to MISS, including reflect overlap.")
		failed_count += 1
	else:
		print("PASS CA-15 release-snapshot occlusion overrides shot anomaly hierarchy")

	quit(1 if failed_count > 0 else 0)
