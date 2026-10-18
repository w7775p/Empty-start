extends Node

const SAMPLE_DURATION_MSEC: int = 8000
const SNAPSHOT_INTERVAL_MSEC: int = 1000

var _host: Object
var _simulation: Node
var _ui: Object
var _attempt_flow: Object
var _started_at_msec: int = 0
var _last_snapshot_at_msec: int = 0
var _last_frame_at_usec: int = 0
var _wall_frame_ms: Array[float] = []
var _process_ms: Array[float] = []
var _physics_ms: Array[float] = []
var _fps_values: Array[float] = []
var _draw_calls: Array[int] = []


func _ready() -> void:
	call_deferred("_bind_sources")


## 只读连接真实 Sandbox 运行态，短采样结束后自动退出，不输入游戏或改战斗状态。
func _bind_sources() -> void:
	var sandbox: Node = get_parent()
	if sandbox == null or not sandbox.has_method("get_plan_b_battle_host"):
		push_error("PB14_BASELINE_ERROR reason=sandbox_source_unavailable")
		get_tree().quit(2)
		return
	_host = sandbox.call("get_plan_b_battle_host")
	_ui = sandbox.call("get_plan_b_battle_ui")
	_attempt_flow = sandbox.call("get_battle_attempt_flow")
	_simulation = _find_simulation(sandbox)
	if _host == null or _simulation == null or _ui == null or _attempt_flow == null:
		push_error("PB14_BASELINE_ERROR reason=runtime_source_unavailable")
		get_tree().quit(2)
		return
	_started_at_msec = Time.get_ticks_msec()
	_last_snapshot_at_msec = _started_at_msec
	_last_frame_at_usec = Time.get_ticks_usec()
	print("PB14_BASELINE_BEGIN scene=res://scenes/sandbox/sandbox_plan_b.tscn sample_ms=%d" % SAMPLE_DURATION_MSEC)


## 每个渲染帧只积累标量；运行状态与组快照每秒采一次。
func _process(_delta: float) -> void:
	if _host == null:
		return
	var now_usec: int = Time.get_ticks_usec()
	if _last_frame_at_usec > 0:
		_wall_frame_ms.append(float(now_usec - _last_frame_at_usec) / 1000.0)
	_last_frame_at_usec = now_usec
	_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_fps_values.append(Performance.get_monitor(Performance.TIME_FPS))
	_draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_snapshot_at_msec >= SNAPSHOT_INTERVAL_MSEC:
		_last_snapshot_at_msec = now_msec
		_emit_runtime_snapshot(now_msec)
	if now_msec - _started_at_msec >= SAMPLE_DURATION_MSEC:
		_emit_summary(now_msec)
		get_tree().quit(0)


func _emit_runtime_snapshot(now_msec: int) -> void:
	var counts: Dictionary = _host.call("get_faction_counts")
	var groups: Array = _simulation.call("get_word_groups")
	var slots: Array = _host.call("get_player_slot_states")
	var available_slots: int = 0
	for slot: Dictionary in slots:
		if bool(slot.get("available", false)):
			available_slots += 1
	var bubble_value: Variant = _ui.get("_active_group_bubble_ids")
	var active_group_bubbles: int = bubble_value.size() if bubble_value is Dictionary else -1
	var level_value: LevelProfile = _attempt_flow.call("get_current_level_profile") as LevelProfile
	var stage: Dictionary = {
		"level_id": level_value.level_id if level_value != null else "",
		"tier": int(_attempt_flow.call("get_current_tier")),
		"normal_active": bool(_attempt_flow.call("is_normal_combat_active")),
	}
	print("PB14_BASELINE_STATE " + JSON.stringify({
		"elapsed_ms": now_msec - _started_at_msec,
		"population": counts,
		"group_count": groups.size(),
		"active_group_bubbles": active_group_bubbles,
		"player_slots": slots.size(),
		"available_slots": available_slots,
		"stage": stage,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
	}))


func _emit_summary(now_msec: int) -> void:
	print("PB14_BASELINE_END " + JSON.stringify({
		"elapsed_ms": now_msec - _started_at_msec,
		"frames": _wall_frame_ms.size(),
		"wall_frame_ms": _summarize(_wall_frame_ms),
		"process_ms": _summarize(_process_ms),
		"physics_ms": _summarize(_physics_ms),
		"fps": _summarize(_fps_values),
		"draw_calls": _summarize(_draw_calls),
	}))


func _summarize(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0, "mean": 0.0, "max": 0.0}
	var total: float = 0.0
	var maximum: float = 0.0
	for value: Variant in values:
		var number: float = float(value)
		total += number
		maximum = maxf(maximum, number)
	return {"n": values.size(), "mean": total / float(values.size()), "max": maximum}


func _find_simulation(node: Node) -> Node:
	if node.has_method("get_word_groups") and node.has_method("is_running"):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_simulation(child)
		if found != null:
			return found
	return null
