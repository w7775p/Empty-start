extends Node

const SECTION_SIMULATION_TICK: int = 0
const SECTION_STEERING_BATCH: int = 1
const SECTION_NEIGHBOR_QUERY: int = 2
const SECTION_GROUP_REFRESH: int = 3
const SECTION_POSITION_EXPORT: int = 4
const SECTION_UI_UNIT_SNAPSHOT: int = 5
const SECTION_UI_POSITION_SNAPSHOT: int = 6
const SECTION_UI_GROUP_SNAPSHOT: int = 7
const SECTION_UI_REFRESH: int = 8
const SECTION_UI_DRAW: int = 9
const SECTION_GROUP_BUBBLE_DRAW: int = 10
const SECTION_DIALOGUE_BUBBLE_CREATE: int = 11
const SECTION_UNIT_DRAW_BATCH: int = 12
const SECTION_GROUP_BUBBLE_GENERATION: int = 13
const SECTION_GROUP_SNAPSHOT_EMIT: int = 14
const SECTION_POSITION_SIGNAL: int = 15
const SECTION_GROUP_BUBBLE_LAYOUT: int = 16
const SECTION_GROUP_BUBBLE_POSITIONS: int = 17
const SECTION_UI_SOURCE_REFRESH: int = 18
const SECTION_UI_VIEW_REFRESH: int = 19
const SECTION_UI_UNIT_EVENT_SNAPSHOT: int = 20

const EVENT_GROUP_BUBBLE_STARTED: int = 0
const EVENT_DIALOGUE_BUBBLE_STARTED: int = 1
const EVENT_BATCH_BURST_STARTED: int = 2
const EVENT_GROUP_BUBBLE_LAYOUT_MISS: int = 3

const SECTION_NAMES := [
	"simulation_tick",
	"steering_batch",
	"neighbor_query",
	"group_refresh",
	"position_export",
	"ui_unit_snapshot",
	"ui_position_snapshot",
	"ui_group_snapshot",
	"ui_refresh",
	"ui_draw",
	"group_bubble_draw",
	"dialogue_bubble_create",
	"unit_draw_batch",
	"group_bubble_generation",
	"group_snapshot_emit",
	"position_signal",
	"group_bubble_layout",
	"group_bubble_positions",
	"ui_source_refresh",
	"ui_view_refresh",
	"ui_unit_event_snapshot",
]
const EVENT_NAMES := [
	"group_bubble_started",
	"dialogue_bubble_started",
	"batch_burst_started",
	"group_bubble_layout_miss",
]

var _enabled: bool = false
var _output_path: String = ""
var _duration_usec: int = 0
var _started_at_usec: int = 0
var _window_started_at_usec: int = 0
var _last_frame_at_usec: int = 0
var _file: FileAccess

var _battle_host: Object
var _simulation: Object
var _battle_ui: Object
var _attempt_flow: Object

var _section_calls := PackedInt64Array()
var _section_total_usec := PackedInt64Array()
var _section_max_usec := PackedInt64Array()
var _section_work_total := PackedInt64Array()
var _section_work_max := PackedInt64Array()
var _section_aux_total := PackedInt64Array()
var _section_aux_max := PackedInt64Array()
var _event_counts := PackedInt64Array()

var _frame_count: int = 0
var _wall_frame_total_usec: int = 0
var _wall_frame_max_usec: int = 0
var _wall_frame_max_elapsed_usec: int = 0
var _process_total_usec: int = 0
var _process_max_usec: int = 0
var _physics_total_usec: int = 0
var _physics_max_usec: int = 0
var _fps_total: float = 0.0
var _draw_calls_total: int = 0
var _draw_calls_max: int = 0

var _latest_group_count: int = 0
var _latest_group_member_count: int = 0
var _latest_active_group_bubbles: int = 0
var _latest_drawn_units: int = 0
var _latest_drawn_group_bubbles: int = 0
var _latest_group_tail_candidates: int = 0


## 仅由显式 opt-in 的 Sandbox 创建；duration 为0时保持运行，供人工停止。
func configure(output_path: String, duration_seconds: float = 0.0) -> bool:
	if _enabled or not is_finite(duration_seconds) or duration_seconds < 0.0:
		return false
	_enabled = true
	_output_path = output_path.strip_edges()
	_duration_usec = int(round(duration_seconds * 1000000.0))
	process_mode = Node.PROCESS_MODE_ALWAYS
	return true


func is_enabled() -> bool:
	return _enabled


## A 在 tracker 入树前注入各状态拥有者；运行快照每个输出窗口只读取一次。
func set_runtime_sources(
	battle_host: Object, simulation: Object, battle_ui: Object, attempt_flow: Object
) -> void:
	_battle_host = battle_host
	_simulation = simulation
	_battle_ui = battle_ui
	_attempt_flow = attempt_flow


## B/D 通过固定 section ID 回报累计时间与工作量；默认关闭时不会创建本节点。
func record_section(
	section_id: int, elapsed_usec: int, work_count: int = 0, auxiliary_count: int = 0
) -> void:
	record_aggregate(section_id, 1, elapsed_usec, elapsed_usec, work_count, auxiliary_count, work_count, auxiliary_count)


## 高频回调先在所属系统本地聚合，再按物理帧/渲染帧批量写入 Tracker。
func record_aggregate(
	section_id: int,
	call_count: int,
	total_usec: int,
	max_usec: int,
	work_total: int = 0,
	auxiliary_total: int = 0,
	work_maximum: int = -1,
	auxiliary_maximum: int = -1
) -> void:
	if not _enabled or section_id < 0 or section_id >= SECTION_NAMES.size():
		return
	var calls: int = maxi(call_count, 0)
	var total: int = maxi(total_usec, 0)
	var maximum: int = maxi(max_usec, 0)
	var work: int = maxi(work_total, 0)
	var auxiliary: int = maxi(auxiliary_total, 0)
	var max_work: int = maxi(work_maximum, 0) if work_maximum >= 0 else work
	var max_auxiliary: int = maxi(auxiliary_maximum, 0) if auxiliary_maximum >= 0 else auxiliary
	_section_calls[section_id] += calls
	_section_total_usec[section_id] += total
	_section_max_usec[section_id] = maxi(_section_max_usec[section_id], maximum)
	_section_work_total[section_id] += work
	_section_work_max[section_id] = maxi(_section_work_max[section_id], max_work)
	_section_aux_total[section_id] += auxiliary
	_section_aux_max[section_id] = maxi(_section_aux_max[section_id], max_auxiliary)


## 记录气泡生成等离散事件，不在事件发生时打印或写文件。
func record_event(event_id: int, count: int = 1) -> void:
	if not _enabled or event_id < 0 or event_id >= EVENT_NAMES.size():
		return
	_event_counts[event_id] += maxi(count, 0)


## B 团体刷新与 D 气泡状态变化时更新计数，避免 telemetry 每帧遍历组快照。
func set_group_snapshot(group_count: int, member_count: int) -> void:
	if not _enabled:
		return
	_latest_group_count = maxi(group_count, 0)
	_latest_group_member_count = maxi(member_count, 0)


func set_active_group_bubble_count(bubble_count: int) -> void:
	if _enabled:
		_latest_active_group_bubbles = maxi(bubble_count, 0)


func set_ui_draw_work(unit_count: int, bubble_count: int, tail_candidate_count: int) -> void:
	if not _enabled:
		return
	_latest_drawn_units = maxi(unit_count, 0)
	_latest_drawn_group_bubbles = maxi(bubble_count, 0)
	_latest_group_tail_candidates = maxi(tail_candidate_count, 0)


func _ready() -> void:
	if not _enabled:
		set_process(false)
		return
	_resize_counters()
	if _output_path.is_empty():
		_output_path = "user://pb14_performance_tracker.jsonl"
	_file = FileAccess.open(_output_path, FileAccess.WRITE)
	if _file == null:
		push_error("PB14 tracker: cannot open output path %s" % _output_path)
		_enabled = false
		set_process(false)
		return
	_started_at_usec = Time.get_ticks_usec()
	_window_started_at_usec = _started_at_usec
	_last_frame_at_usec = _started_at_usec
	_write_record({
		"record": "start",
		"godot_version": str(Engine.get_version_info().get("string", "")),
		"physics_tps": Engine.physics_ticks_per_second,
		"output_path": _output_path,
	})


## 每个渲染帧仅累积标量监视器；JSON 构建和文件写入每秒最多一次。
func _process(_delta: float) -> void:
	if not _enabled:
		return
	var now_usec: int = Time.get_ticks_usec()
	var wall_frame_usec: int = maxi(now_usec - _last_frame_at_usec, 0)
	_last_frame_at_usec = now_usec
	var process_usec: int = maxi(int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0), 0)
	var physics_usec: int = maxi(int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0), 0)
	var fps_value: float = Performance.get_monitor(Performance.TIME_FPS)
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_frame_count += 1
	_wall_frame_total_usec += wall_frame_usec
	_process_total_usec += process_usec
	_physics_total_usec += physics_usec
	_fps_total += fps_value
	_draw_calls_total += draw_calls
	if wall_frame_usec > _wall_frame_max_usec:
		_wall_frame_max_usec = wall_frame_usec
		_wall_frame_max_elapsed_usec = now_usec - _started_at_usec
	_process_max_usec = maxi(_process_max_usec, process_usec)
	_physics_max_usec = maxi(_physics_max_usec, physics_usec)
	_draw_calls_max = maxi(_draw_calls_max, draw_calls)
	if now_usec - _window_started_at_usec >= 1000000:
		_flush_window(now_usec)
	if _duration_usec > 0 and now_usec - _started_at_usec >= _duration_usec:
		_flush_window(now_usec)
		_write_record({"record": "end", "elapsed_ms": float(now_usec - _started_at_usec) / 1000.0})
		_close_output()
		_enabled = false
		set_process(false)
		get_tree().quit(0)


## 预先分配固定长度的计数数组，采样帧里只更新标量。
func _resize_counters() -> void:
	_section_calls.resize(SECTION_NAMES.size())
	_section_total_usec.resize(SECTION_NAMES.size())
	_section_max_usec.resize(SECTION_NAMES.size())
	_section_work_total.resize(SECTION_NAMES.size())
	_section_work_max.resize(SECTION_NAMES.size())
	_section_aux_total.resize(SECTION_NAMES.size())
	_section_aux_max.resize(SECTION_NAMES.size())
	_event_counts.resize(EVENT_NAMES.size())
	_reset_window_counters()


## 在固定计数数组中清零；避免采样期间创建临时数组或大字典。
func _reset_window_counters() -> void:
	_frame_count = 0
	_wall_frame_total_usec = 0
	_wall_frame_max_usec = 0
	_wall_frame_max_elapsed_usec = 0
	_process_total_usec = 0
	_process_max_usec = 0
	_physics_total_usec = 0
	_physics_max_usec = 0
	_fps_total = 0.0
	_draw_calls_total = 0
	_draw_calls_max = 0
	for index: int in SECTION_NAMES.size():
		_section_calls[index] = 0
		_section_total_usec[index] = 0
		_section_max_usec[index] = 0
		_section_work_total[index] = 0
		_section_work_max[index] = 0
		_section_aux_total[index] = 0
		_section_aux_max[index] = 0
	for event_index: int in EVENT_NAMES.size():
		_event_counts[event_index] = 0


## 每秒汇总一次窗口数据并写入 JSONL；窗口内不创建逐帧记录。
func _flush_window(now_usec: int) -> void:
	if _frame_count <= 0 or _file == null:
		_window_started_at_usec = now_usec
		return
	var sections: Dictionary = {}
	for section_id: int in SECTION_NAMES.size():
		var calls: int = int(_section_calls[section_id])
		if calls <= 0 and _section_work_total[section_id] <= 0 and _section_aux_total[section_id] <= 0:
			continue
		sections[SECTION_NAMES[section_id]] = {
			"calls": calls,
			"mean_us": float(_section_total_usec[section_id]) / float(maxi(calls, 1)),
			"max_us": int(_section_max_usec[section_id]),
			"work_total": int(_section_work_total[section_id]),
			"work_max": int(_section_work_max[section_id]),
			"aux_total": int(_section_aux_total[section_id]),
			"aux_max": int(_section_aux_max[section_id]),
		}
	var events: Dictionary = {}
	for event_id: int in EVENT_NAMES.size():
		var event_count: int = int(_event_counts[event_id])
		if event_count > 0:
			events[EVENT_NAMES[event_id]] = event_count
	var frame_divisor: float = float(maxi(_frame_count, 1))
	_write_record({
		"record": "window",
		"elapsed_s": float(now_usec - _started_at_usec) / 1000000.0,
		"window_ms": float(now_usec - _window_started_at_usec) / 1000.0,
		"frames": _frame_count,
		"frame": {
			"wall_ms_mean": float(_wall_frame_total_usec) / frame_divisor / 1000.0,
			"wall_ms_max": float(_wall_frame_max_usec) / 1000.0,
			"wall_max_elapsed_s": float(_wall_frame_max_elapsed_usec) / 1000000.0,
			"fps_mean": _fps_total / frame_divisor,
			"process_ms_mean": float(_process_total_usec) / frame_divisor / 1000.0,
			"process_ms_max": float(_process_max_usec) / 1000.0,
			"physics_ms_mean": float(_physics_total_usec) / frame_divisor / 1000.0,
			"physics_ms_max": float(_physics_max_usec) / 1000.0,
			"draw_calls_mean": float(_draw_calls_total) / frame_divisor,
			"draw_calls_max": _draw_calls_max,
		},
		"runtime": _capture_runtime_snapshot(),
		"render_work": {
			"last_drawn_units": _latest_drawn_units,
			"last_drawn_group_bubbles": _latest_drawn_group_bubbles,
			"last_group_tail_candidates": _latest_group_tail_candidates,
		},
		"events": events,
		"sections": sections,
	})
	_file.flush()
	_window_started_at_usec = now_usec
	_reset_window_counters()


## 每个输出窗口从 Host、Flow 和 UI 只读采集一次游戏状态。
func _capture_runtime_snapshot() -> Dictionary:
	var population: Dictionary = {"player": 0, "opponent": 0, "neutral": 0}
	if is_instance_valid(_battle_host) and _battle_host.has_method("get_faction_counts"):
		var counts: Variant = _battle_host.call("get_faction_counts")
		if counts is Dictionary:
			population = counts
	var slots: Array = []
	if is_instance_valid(_battle_host) and _battle_host.has_method("get_player_slot_states"):
		var states: Variant = _battle_host.call("get_player_slot_states")
		if states is Array:
			slots = states
	var ready_slots: int = 0
	var cooling_slots: int = 0
	for state_value: Variant in slots:
		if not state_value is Dictionary:
			continue
		var state: Dictionary = state_value
		if bool(state.get("available", false)):
			ready_slots += 1
		elif float(state.get("remaining", 0.0)) > 0.0:
			cooling_slots += 1
	var level_id: String = ""
	var tier: int = -1
	var normal_active: bool = false
	var ui_snapshot: Dictionary = {}
	if is_instance_valid(_battle_ui) and _battle_ui.has_method("get_pb14_performance_snapshot"):
		var ui_value: Variant = _battle_ui.call("get_pb14_performance_snapshot")
		if ui_value is Dictionary:
			ui_snapshot = ui_value
	if is_instance_valid(_attempt_flow):
		if _attempt_flow.has_method("get_current_level_profile"):
			var level_value: Variant = _attempt_flow.call("get_current_level_profile")
			if level_value is LevelProfile:
				level_id = level_value.level_id
		if _attempt_flow.has_method("get_current_tier"):
			tier = int(_attempt_flow.call("get_current_tier"))
		if _attempt_flow.has_method("is_normal_combat_active"):
			normal_active = bool(_attempt_flow.call("is_normal_combat_active"))
	return {
		"population": population,
		"group_count": _latest_group_count,
		"group_member_count": _latest_group_member_count,
		"active_group_bubbles": _latest_active_group_bubbles,
		"player_slot_count": slots.size(),
		"ready_player_slots": ready_slots,
		"cooling_player_slots": cooling_slots,
		"level_id": level_id,
		"tier": tier,
		"normal_combat_active": normal_active,
		"battle_state": str(_battle_host.call("get_battle_state")) if is_instance_valid(_battle_host) and _battle_host.has_method("get_battle_state") else "unknown",
		"ui": ui_snapshot,
	}


## 统一写入单行 JSON；调用频率仅为启动、每秒窗口和结束。
func _write_record(record: Dictionary) -> void:
	if _file != null:
		_file.store_line(JSON.stringify(record))


## 结束记录前刷新并关闭文件句柄。
func _close_output() -> void:
	if _file != null:
		_file.flush()
		_file.close()
		_file = null


## 用户手动关闭场景时补写结束记录，保留已经采集的窗口。
func _exit_tree() -> void:
	if _enabled and _file != null:
		_write_record({"record": "end", "elapsed_ms": float(Time.get_ticks_usec() - _started_at_usec) / 1000.0, "reason": "tree_exit"})
	_close_output()
