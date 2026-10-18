extends Node2D

const BOARD_RECT: Rect2 = Rect2(Vector2(448.0, 72.0), Vector2(1024.0, 828.0))

var _simulation: PlanBUnitSimulation
var _failed_checks: Array[String] = []
var _physics_signal_count: int = 0
var _history_is_contiguous: bool = true
var _all_ids_stable_and_sorted: bool = true
var _last_current_by_id: Dictionary = {}
var _last_published_ids: PackedInt32Array = PackedInt32Array()
var _last_published_positions: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_simulation = get_node("Simulation") as PlanBUnitSimulation
	_simulation.unit_physics_positions_updated.connect(_on_physics_positions_updated)
	call_deferred("_run_smoke")


## 固定一秒物理样本，验证决策约10Hz、位置发布保持60Hz且插值坐标连续。
func _run_smoke() -> void:
	_simulation.position = BOARD_RECT.position
	_simulation.maximum_population = 6
	_simulation.neutral_spawn_interval_seconds = 100.0
	_simulation.lifespan_min_seconds = 120.0
	_simulation.lifespan_max_seconds = 120.0
	_simulation.base_speed_min = 30.0
	_simulation.base_speed_max = 30.0
	_simulation.maximum_speed = 78.0
	_simulation.detection_radius = 24.0
	_simulation.ally_detection_radius = 160.0
	_simulation.target_decision_refresh_seconds = 0.1
	_simulation.neighbor_grid_refresh_seconds = 0.1
	_simulation.group_topology_refresh_seconds = 0.2
	_simulation.wandering_weight = 0.0
	_simulation.set_random_seed(20261401)
	_simulation.set_type_counter_map({"type_a": "type_b", "type_b": "type_c", "type_c": "type_a"})
	_simulation.set_play_area(BOARD_RECT)
	var ids: Array[int] = _simulation.create_population(6, 0)
	for index: int in 4:
		var phrase_id: String = "pair-a" if index < 2 else "pair-b"
		var phrase_text: String = "邻域A" if index < 2 else "邻域B"
		_simulation.seed_unit(ids[index], &"player", _word(phrase_id, phrase_text), index + 1)
		var local_x: float = 180.0 + float(index % 2) * 150.0 + float(index / 2) * 400.0
		_set_global_position(ids[index], BOARD_RECT.position + Vector2(local_x, 300.0))
	_set_global_position(ids[4], BOARD_RECT.position + Vector2(240.0, 330.0))
	_set_global_position(ids[5], BOARD_RECT.position + Vector2(900.0, 600.0))
	_set_motion_speed(ids, 30.0)
	_set_motion_speed_for_unit(ids[4], 0.0)
	_simulation.start_simulation()
	var initial_grid_rebuilds: int = int(_simulation.get("neighbor_grid_rebuild_count"))
	var initial_group_refreshes: int = int(_simulation.get("word_group_refresh_count"))
	_check(
		_simulation.seed_unit(ids[5], &"player", _word("pair-a", "邻域A"), 5),
		"an in-round phrase change succeeds"
	)
	await _wait_physics_frames(2)
	_check(
		int(_simulation.get("neighbor_grid_rebuild_count")) == initial_grid_rebuilds,
		"a phrase-only change waits for the scheduled spatial-grid refresh"
	)
	_check(
		int(_simulation.get("word_group_refresh_count")) == initial_group_refreshes,
		"a phrase change waits for the scheduled topology refresh"
	)
	await _wait_physics_frames(58)
	_simulation.pause_simulation()

	var decision_count: int = int(_simulation.get("steering_call_count"))
	var decisions_by_id: Dictionary = _simulation.get("steering_calls_by_id")
	var grid_rebuild_count: int = int(_simulation.get("neighbor_grid_rebuild_count"))
	var group_refresh_count: int = int(_simulation.get("word_group_refresh_count"))
	var neutral_decisions_with_neighbors: int = int(_simulation.get("neutral_decisions_with_neighbors"))
	var faction_decisions_with_neighbors: int = int(_simulation.get("faction_decisions_with_neighbors"))
	var expected_full_rate: int = _physics_signal_count * ids.size()
	_check(_physics_signal_count >= 56 and _physics_signal_count <= 62, "position facts publish on every 60Hz physics step")
	_check(decision_count > 0 and decision_count < int(float(expected_full_rate) * 0.4), "target decisions are staggered and throttled below every-physics-step work")
	_check(grid_rebuild_count >= 8 and grid_rebuild_count <= 13, "the shared spatial grid stays near its 10Hz refresh cadence")
	_check(group_refresh_count >= 4 and group_refresh_count <= 7, "word-group topology stays near its 5Hz refresh cadence")
	_check(neutral_decisions_with_neighbors == 0, "neutral wandering decisions skip unused local-neighbor scans")
	_check(faction_decisions_with_neighbors > 0, "faction steering keeps real nearby ally queries")
	_check(_history_is_contiguous, "each physics signal previous position matches the preceding current position")
	_check(_all_ids_stable_and_sorted, "packed position arrays use stable ascending unit IDs")
	_check(_last_published_ids.size() == ids.size(), "physics position publication includes every surviving unit")
	_check(_last_published_positions.size() == ids.size(), "previous/current position arrays remain aligned")
	for unit_id: int in ids:
		var updates_for_unit: int = int(decisions_by_id.get(unit_id, 0))
		_check(updates_for_unit >= 6 and updates_for_unit <= 13, "each unit receives about ten target decisions per second")
		var latest_snapshot: Dictionary = _simulation.get_unit_snapshot(unit_id)
		var latest_position: Vector2 = latest_snapshot.get("position", Vector2.ZERO)
		_check(latest_position.distance_to(_last_current_position_for(unit_id)) <= 0.01, "position fact matches the actual current unit position")
	_check(_simulation.get_faction_counts() == {"player": 5, "opponent": 0, "neutral": 1}, "decision throttling preserves real battle population")
	_check(_simulation.get_word_groups().size() == 5, "phrase changes join the topology at its next scheduled refresh")
	var neutral_snapshot: Dictionary = _simulation.get_unit_snapshot(ids[4])
	_check(neutral_snapshot.get("motion_intent", "") == "wander", "neutral unit preserves its wander behavior")
	print("PB14 NEIGHBOR_QUERY_COUNTS neutral_with_neighbors=%d faction_with_neighbors=%d" % [
		neutral_decisions_with_neighbors, faction_decisions_with_neighbors
	])
	_finish_smoke(decision_count, grid_rebuild_count, group_refresh_count)


## 每个物理步核对ID、数组对齐及上一帧到当前帧的位置连续性。
func _on_physics_positions_updated(
	unit_ids: PackedInt32Array,
	previous_positions: PackedVector2Array,
	current_positions: PackedVector2Array
) -> void:
	_physics_signal_count += 1
	if unit_ids.size() != previous_positions.size() or unit_ids.size() != current_positions.size():
		_history_is_contiguous = false
		return
	if not _last_published_ids.is_empty() and unit_ids != _last_published_ids:
		_all_ids_stable_and_sorted = false
	for index: int in unit_ids.size():
		if index > 0 and unit_ids[index - 1] >= unit_ids[index]:
			_all_ids_stable_and_sorted = false
		var unit_id: int = unit_ids[index]
		if _last_current_by_id.has(unit_id):
			var prior_position: Vector2 = _last_current_by_id[unit_id]
			if prior_position.distance_to(previous_positions[index]) > 0.01:
				_history_is_contiguous = false
		_last_current_by_id[unit_id] = current_positions[index]
	_last_published_ids = unit_ids.duplicate()
	_last_published_positions = current_positions.duplicate()


func _last_current_position_for(unit_id: int) -> Vector2:
	return _last_current_by_id.get(unit_id, Vector2.ZERO)


func _set_global_position(unit_id: int, scene_position: Vector2) -> void:
	for child: Node in _simulation.get_children():
		var unit := child as PlanBUnit
		if unit != null and unit.unit_id == unit_id:
			unit.global_position = scene_position
			return


func _set_motion_speed(unit_ids: Array[int], speed: float) -> void:
	for unit_id: int in unit_ids:
		_set_motion_speed_for_unit(unit_id, speed)


func _set_motion_speed_for_unit(unit_id: int, speed: float) -> void:
	for child: Node in _simulation.get_children():
		var unit := child as PlanBUnit
		if unit == null or unit.unit_id != unit_id:
			continue
		unit.base_speed = speed
		unit.velocity = Vector2.ZERO
		unit.wander_direction = Vector2.RIGHT
		unit.wander_change_remaining = 100.0
		break


func _wait_physics_frames(frame_count: int) -> void:
	for frame_index: int in frame_count:
		await get_tree().physics_frame


func _word(word_id: String, text: String) -> Dictionary:
	return {
		"word_id": word_id,
		"text": text,
		"battle_type": "type_a",
		"strength": 1,
		"traits": [],
		"tendency": "neutral",
	}


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failed_checks.append(description)
	push_error("PB-14 CHECK FAILED: " + description)


func _finish_smoke(decision_count: int, grid_rebuild_count: int, group_refresh_count: int) -> void:
	if _failed_checks.is_empty():
		print("PB-14 PASS: physics_ticks=%d decision_updates=%d grid_rebuilds=%d group_refreshes=%d units=%d" % [
			_physics_signal_count, decision_count, grid_rebuild_count, group_refresh_count, _last_published_ids.size()
		])
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)
		return
	print("PB-14 FAIL: %d check(s)" % _failed_checks.size())
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1)
