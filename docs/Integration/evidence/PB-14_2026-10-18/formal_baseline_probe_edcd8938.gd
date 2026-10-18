extends Node

const BASELINE_COMMIT: String = "edcd89383ded3ea4d938f67c7328456c199b340c"
const EXPECTED_POPULATION: int = 96
const POPULATION_STABLE_WARMUP_MSEC: int = 5000
const PROFILE_DURATION_MSEC: int = 20000
const READY_TIMEOUT_MSEC: int = 90000

var _simulation: Node
var _started_at_msec: int = 0
var _last_census_at_msec: int = 0
var _full_population_since_msec: int = 0
var _profile_started_at_msec: int = 0
var _last_frame_at_usec: int = 0
var _frame_interval_msec: Array[float] = []
var _process_time_msec: Array[float] = []
var _physics_time_msec: Array[float] = []
var _fps_values: Array[float] = []
var _draw_call_values: Array[float] = []
var _population_minimum: int = 2147483647
var _population_maximum: int = 0
var _physics_frames_at_start: int = 0


func _ready() -> void:
	_started_at_msec = Time.get_ticks_msec()
	call_deferred("_find_battle_simulation")


## 只读取正式 Sandbox 中 B 模块的公开查询；达到96后预热5秒并采样20秒。
func _process(_delta: float) -> void:
	if _simulation == null:
		return
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_census_at_msec >= 1000:
		_last_census_at_msec = now_msec
		var counts: Dictionary = _simulation.call("get_faction_counts")
		var total: int = int(counts.get("player", 0)) + int(counts.get("opponent", 0)) + int(counts.get("neutral", 0))
		print("PB14_CENSUS t_ms=%d player=%d opponent=%d neutral=%d total=%d running=%s" % [
			now_msec - _started_at_msec,
			int(counts.get("player", 0)),
			int(counts.get("opponent", 0)),
			int(counts.get("neutral", 0)),
			total,
			str(bool(_simulation.call("is_running"))),
		])
		if total == EXPECTED_POPULATION and bool(_simulation.call("is_running")):
			if _full_population_since_msec == 0:
				_full_population_since_msec = now_msec
				print("PB14_FULL_POPULATION t_ms=%d" % (now_msec - _started_at_msec))
		else:
			_full_population_since_msec = 0
		if _profile_started_at_msec == 0 and _full_population_since_msec > 0:
			if now_msec - _full_population_since_msec >= POPULATION_STABLE_WARMUP_MSEC:
				_begin_profile_sample(now_msec, counts)
	if _profile_started_at_msec > 0:
		_record_frame_sample()
		if now_msec - _profile_started_at_msec >= PROFILE_DURATION_MSEC:
			_finish_profile_sample(now_msec)
	elif now_msec - _started_at_msec >= READY_TIMEOUT_MSEC:
		print("PB14_PROFILE_UNVERIFIED reason=simulation_not_running_or_population_not_96")
		get_tree().quit(1)


func _begin_profile_sample(now_msec: int, counts: Dictionary) -> void:
	_profile_started_at_msec = now_msec
	_last_frame_at_usec = Time.get_ticks_usec()
	_population_minimum = int(counts.get("player", 0)) + int(counts.get("opponent", 0)) + int(counts.get("neutral", 0))
	_population_maximum = _population_minimum
	var profile_context: Dictionary = {
		"commit": BASELINE_COMMIT,
		"scene": "res://scenes/sandbox/sandbox_plan_b.tscn",
		"logic_viewport": Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
			int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
		),
		"client_window": DisplayServer.window_get_size(),
		"window_mode": str(DisplayServer.window_get_mode()),
		"physics_tps": Engine.physics_ticks_per_second,
		"population": counts,
		"warmup_ms": POPULATION_STABLE_WARMUP_MSEC,
		"sample_ms": PROFILE_DURATION_MSEC,
	}
	print("PB14_PROFILE_BEGIN " + JSON.stringify(profile_context))


## 每个渲染帧只采引擎公开性能监视器；不复制棋子词条快照。
func _record_frame_sample() -> void:
	var now_usec: int = Time.get_ticks_usec()
	if _last_frame_at_usec > 0:
		_frame_interval_msec.append(float(now_usec - _last_frame_at_usec) / 1000.0)
	_last_frame_at_usec = now_usec
	_process_time_msec.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_time_msec.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_fps_values.append(Performance.get_monitor(Performance.TIME_FPS))
	_draw_call_values.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var counts: Dictionary = _simulation.call("get_faction_counts")
	var total: int = int(counts.get("player", 0)) + int(counts.get("opponent", 0)) + int(counts.get("neutral", 0))
	_population_minimum = mini(_population_minimum, total)
	_population_maximum = maxi(_population_maximum, total)


func _finish_profile_sample(now_msec: int) -> void:
	var counts: Dictionary = _simulation.call("get_faction_counts")
	var summary: Dictionary = {
		"commit": BASELINE_COMMIT,
		"scene": "res://scenes/sandbox/sandbox_plan_b.tscn",
		"duration_ms": now_msec - _profile_started_at_msec,
		"render_frames": _frame_interval_msec.size(),
		"fps": _summarize_values(_fps_values),
		"wall_frame_ms": _summarize_values(_frame_interval_msec),
		"process_ms": _summarize_values(_process_time_msec),
		"physics_ms": _summarize_values(_physics_time_msec),
		"draw_calls": _summarize_values(_draw_call_values),
		"population_minimum": _population_minimum,
		"population_maximum": _population_maximum,
		"final_counts": counts,
		"note": "TIME_PROCESS/TIME_PHYSICS_PROCESS are engine monitors; Script/Idle profiler breakdown remains separate.",
	}
	print("PB14_PROFILE_END " + JSON.stringify(summary))
	get_tree().quit(0)


func _summarize_values(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "mean": 0.0, "p95": 0.0, "max": 0.0}
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var total: float = 0.0
	for value: float in sorted_values:
		total += value
	var percentile_index: int = clampi(int(ceil(float(sorted_values.size()) * 0.95)) - 1, 0, sorted_values.size() - 1)
	return {
		"n": sorted_values.size(),
		"mean": total / float(sorted_values.size()),
		"p95": sorted_values[percentile_index],
		"max": sorted_values.back(),
	}


func _find_battle_simulation() -> void:
	var scene_root: Node = get_tree().current_scene
	_simulation = _find_simulation_recursive(scene_root)
	if _simulation == null:
		return
	print("PB14_SIMULATION_READY path=%s" % _simulation.get_path())


func _find_simulation_recursive(node: Node) -> Node:
	if node.has_method("get_faction_counts") and node.has_method("get_unit_snapshots") and node.has_method("is_running"):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_simulation_recursive(child)
		if found != null:
			return found
	return null
