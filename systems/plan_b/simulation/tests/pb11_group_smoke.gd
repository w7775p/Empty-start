extends Node2D

const BOARD_RECT: Rect2 = Rect2(Vector2(448.0, 72.0), Vector2(1024.0, 828.0))

var _simulation: PlanBUnitSimulation
var _failed_checks: Array[String] = []
var _group_change_events: Array[Array] = []
var _contact_events_by_pair: Dictionary = {}


func _ready() -> void:
	_simulation = get_node("Simulation") as PlanBUnitSimulation
	_simulation.word_groups_changed.connect(_on_word_groups_changed)
	_simulation.contact_resolved.connect(_on_contact_resolved)
	call_deferred("_run_smoke")


## 验证同词结群、迟滞拆合、友军靠拢和敌我反冲仍由真实物理接触驱动。
func _run_smoke() -> void:
	await get_tree().process_frame
	await _test_group_topology_and_hysteresis()
	if not _failed_checks.is_empty():
		_finish_smoke()
		return
	await _test_flocking_and_word_isolation()
	if not _failed_checks.is_empty():
		_finish_smoke()
		return
	await _test_soft_ally_contact_and_enemy_recoil()
	_finish_smoke()


## 同阵营同话语近邻连成组；超过加入阈值要稳定脱离到拆分阈值才断开。
func _test_group_topology_and_hysteresis() -> void:
	await _reset_simulation(20261021, 16)
	var ids: Array[int] = _simulation.create_population(4, 0)
	for index: int in ids.size():
		_simulation.seed_unit(ids[index], &"player", _word("same", "同话团", "type_a", 2), index + 1)
		var local_position := Vector2(100.0 + float(index % 2) * 50.0 + float(index / 2) * 200.0, 140.0)
		_set_global_position(ids[index], BOARD_RECT.position + local_position)
	_set_motion_speed(ids, 0.0)
	_simulation.start_simulation()
	var groups: Array[Dictionary] = _simulation.get_word_groups()
	_check(groups.size() == 2, "two separated pairs form two same-word groups")
	var first_group_id: int = _group_id_containing(groups, ids[0])
	var second_group_id: int = _group_id_containing(groups, ids[2])
	_check(first_group_id > 0 and second_group_id > 0 and first_group_id != second_group_id, "separated groups own distinct stable IDs")
	for group: Dictionary in groups:
		var member_ids: Array = group.get("member_ids", [])
		_check(member_ids.size() == 2, "initial group contains its two adjacent members")
		_check(str(group.get("word_id", "")) == "same" and str(group.get("team", "")) == "player", "group key is team plus word ID")
		_check(group.get("member_positions", {}) is Dictionary, "group exposes global member positions")
		_check(group.get("center_position", Vector2.ZERO) is Vector2, "group exposes a global center")
		_check(str(group.get("word_snapshot", {}).get("text", "")) == "同话团", "group exposes the current full word snapshot")

	_set_global_position(ids[2], BOARD_RECT.position + Vector2(165.0, 140.0))
	_set_global_position(ids[3], BOARD_RECT.position + Vector2(215.0, 140.0))
	await _wait_physics_frames(18)
	groups = _simulation.get_word_groups()
	_check(groups.size() == 1, "close groups merge into one connected component")
	var merged_group_id: int = _group_id_containing(groups, ids[0])
	_check(merged_group_id == first_group_id or merged_group_id == second_group_id, "merged component reuses one prior group ID")
	var merged_group: Dictionary = _find_group_containing(groups, ids[0])
	var merged_ids: Array = merged_group.get("member_ids", [])
	_check(merged_ids.size() == 4, "merged group contains all four units without fusion")
	var counts: Dictionary = _simulation.get_faction_counts()
	_check(int(counts.get("player", 0)) == 4, "group formation leaves the real player population unchanged")

	_set_global_position(ids[2], BOARD_RECT.position + Vector2(225.0, 140.0))
	_set_global_position(ids[3], BOARD_RECT.position + Vector2(275.0, 140.0))
	await _wait_physics_frames(18)
	groups = _simulation.get_word_groups()
	_check(groups.size() == 1, "same-group links remain joined through the 90px hysteresis band")

	_set_global_position(ids[2], BOARD_RECT.position + Vector2(330.0, 140.0))
	_set_global_position(ids[3], BOARD_RECT.position + Vector2(380.0, 140.0))
	await _wait_physics_frames(18)
	groups = _simulation.get_word_groups()
	_check(groups.size() == 2, "groups split after every link exceeds the leave distance")
	_check(_group_id_containing(groups, ids[0]) == merged_group_id, "largest overlapping component keeps the old group ID")
	_check(_group_id_containing(groups, ids[2]) != merged_group_id, "split component receives a new group ID")
	_check(_group_change_events.size() >= 3, "topology changes publish group update facts")
	_simulation.pause_simulation()


## 同话友军能主动靠近；不同word_id即便贴邻也不会共用共享气泡组。
func _test_flocking_and_word_isolation() -> void:
	await _reset_simulation(20261022, 8)
	var ids: Array[int] = _simulation.create_population(3, 0)
	_simulation.seed_unit(ids[0], &"player", _word("flock", "结群测试", "type_a", 2), 1)
	_simulation.seed_unit(ids[1], &"player", _word("flock", "结群测试", "type_a", 2), 2)
	_simulation.seed_unit(ids[2], &"player", _word("other", "另一句话", "type_b", 1), 3)
	_set_global_position(ids[0], BOARD_RECT.position + Vector2(100.0, 300.0))
	_set_global_position(ids[1], BOARD_RECT.position + Vector2(220.0, 300.0))
	_set_global_position(ids[2], BOARD_RECT.position + Vector2(550.0, 600.0))
	_simulation.detection_radius = 24.0
	_simulation.ally_detection_radius = 160.0
	_simulation.ally_attraction_weight = 0.45
	_simulation.ally_separation_weight = 0.65
	_simulation.wandering_weight = 0.0
	_set_motion_speed(ids, 30.0)
	_simulation.start_simulation()
	var initial_groups: Array[Dictionary] = _simulation.get_word_groups()
	_check(initial_groups.size() == 3, "singletons and different current word IDs remain separate bubble groups")
	await _wait_physics_frames(8)
	var first_motion_snapshot: Dictionary = _simulation.get_unit_snapshot(ids[0])
	_check(first_motion_snapshot.get("motion_intent", "") == "group", "unthreatened word follower chooses group movement")
	var initial_distance: float = (BOARD_RECT.position + Vector2(100.0, 300.0)).distance_to(BOARD_RECT.position + Vector2(220.0, 300.0))
	await _wait_physics_frames(72)
	var first_after: Vector2 = _simulation.get_unit_snapshot(ids[0]).get("position", Vector2.ZERO)
	var second_after: Vector2 = _simulation.get_unit_snapshot(ids[1]).get("position", Vector2.ZERO)
	_check(first_after.distance_to(second_after) < initial_distance, "same-word followers move toward one another")
	var groups: Array[Dictionary] = _simulation.get_word_groups()
	_check(groups.size() == 2, "a nearby different-word ally keeps a separate bubble group")
	var same_word_group: Dictionary = _find_group_containing(groups, ids[0])
	var same_word_members: Array = same_word_group.get("member_ids", [])
	_check(same_word_members.size() == 2, "same-word followers form a shared group")
	_check(_simulation.get_faction_counts() == {"player": 3, "opponent": 0, "neutral": 0}, "flocking never merges or changes PK population")
	_simulation.pause_simulation()


## 同阵营接触只软分离；敌我合法接触保留0.18秒真实反冲。
func _test_soft_ally_contact_and_enemy_recoil() -> void:
	await _reset_simulation(20261023, 8)
	var ally_ids: Array[int] = _simulation.create_population(2, 0)
	_simulation.seed_unit(ally_ids[0], &"player", _word("ally-new", "新同盟", "type_a", 2), 2)
	_simulation.seed_unit(ally_ids[1], &"player", _word("ally-old", "旧同盟", "type_c", 1), 1)
	_set_motion_speed(ally_ids, 0.0)
	_set_global_position(ally_ids[0], BOARD_RECT.position + Vector2(400.0, 420.0))
	_set_global_position(ally_ids[1], BOARD_RECT.position + Vector2(418.0, 420.0))
	_simulation.start_simulation()
	var ally_outcome: String = await _wait_for_pair_outcome(ally_ids[0], ally_ids[1])
	_check(ally_outcome == "same_team_bounce", "allies still make real contact and relay the newer word")
	var ally_first := _find_unit_node(ally_ids[0])
	var ally_second := _find_unit_node(ally_ids[1])
	_check(ally_first.contact_recoil_remaining_seconds == 0.0 and ally_second.contact_recoil_remaining_seconds == 0.0, "same-team contact avoids the strong recoil state")
	_check(ally_first.global_position.distance_to(ally_second.global_position) >= _simulation.unit_collision_radius * 2.0, "same-team collision resolves physical overlap")
	_check(_simulation.get_faction_counts() == {"player": 2, "opponent": 0, "neutral": 0}, "same-team relay preserves headcount")

	await _reset_simulation(20261024, 8)
	var enemy_ids: Array[int] = _simulation.create_population(2, 0)
	_simulation.seed_unit(enemy_ids[0], &"player", _word("attacker", "可克制话", "type_a", 2), 1)
	_simulation.seed_unit(enemy_ids[1], &"opponent", _word("defender", "被克制话", "type_b", 1), 2)
	_set_motion_speed(enemy_ids, 0.0)
	_set_global_position(enemy_ids[0], BOARD_RECT.position + Vector2(500.0, 420.0))
	_set_global_position(enemy_ids[1], BOARD_RECT.position + Vector2(518.0, 420.0))
	_simulation.start_simulation()
	var enemy_outcome: String = await _wait_for_pair_outcome(enemy_ids[0], enemy_ids[1])
	_check(enemy_outcome == "converted" or enemy_outcome == "infection_failed", "enemy contact still performs a legal infection attempt")
	var player_unit := _find_unit_node(enemy_ids[0])
	var opponent_unit := _find_unit_node(enemy_ids[1])
	_check(player_unit.contact_recoil_remaining_seconds > 0.1, "enemy contact keeps a short visible recoil after the first physics tick")
	_check(opponent_unit.contact_recoil_remaining_seconds > 0.1, "both enemy contact bodies retain recoil movement")
	_check(player_unit.global_position.distance_to(opponent_unit.global_position) >= _simulation.unit_collision_radius * 2.0, "enemy contact resolves physical overlap")
	_simulation.pause_simulation()


## 为每个夹具重建固定坐标、克制表和随机流，保留真实 Node 生命周期。
func _reset_simulation(seed_value: int, population_cap: int) -> void:
	_simulation.pause_simulation()
	_simulation.clear_battle()
	await get_tree().process_frame
	_simulation.position = BOARD_RECT.position
	_simulation.maximum_population = population_cap
	_simulation.neutral_spawn_interval_seconds = 100.0
	_simulation.lifespan_min_seconds = 120.0
	_simulation.lifespan_max_seconds = 120.0
	_simulation.unit_collision_radius = 13.0
	_simulation.collision_cooldown_seconds = 0.7
	_simulation.contact_recoil_speed = 22.0
	_simulation.base_speed_min = 30.0
	_simulation.base_speed_max = 52.0
	_simulation.maximum_speed = 78.0
	_simulation.detection_radius = 220.0
	_simulation.set_type_counter_map({"type_a": "type_b", "type_b": "type_c", "type_c": "type_a"})
	_simulation.set_random_seed(seed_value)
	_check(_simulation.set_play_area(BOARD_RECT), "B accepts the global test board Rect2")
	_contact_events_by_pair.clear()
	_group_change_events.clear()


## 在逻辑画布中放置夹具棋子；外部输入位置按scene-global坐标传递。
func _set_global_position(unit_id: int, scene_position: Vector2) -> void:
	var unit := _find_unit_node(unit_id)
	if unit != null:
		unit.global_position = scene_position


func _set_motion_speed(unit_ids: Array[int], speed: float) -> void:
	for unit_id: int in unit_ids:
		var unit := _find_unit_node(unit_id)
		if unit == null:
			continue
		unit.base_speed = speed
		unit.velocity = Vector2.ZERO
		unit.wander_direction = Vector2.ZERO
		unit.wander_change_remaining = 100.0


func _wait_physics_frames(frame_count: int) -> void:
	for frame_index: int in frame_count:
		await get_tree().physics_frame


func _wait_for_pair_outcome(first_id: int, second_id: int) -> String:
	var pair := Vector2i(mini(first_id, second_id), maxi(first_id, second_id))
	for frame_index: int in 20:
		var outcomes: Array = _contact_events_by_pair.get(pair, [])
		if not outcomes.is_empty():
			return str(outcomes.back())
		await get_tree().physics_frame
	return "no-contact"


func _find_group_containing(groups: Array[Dictionary], unit_id: int) -> Dictionary:
	for group: Dictionary in groups:
		var member_ids: Array = group.get("member_ids", [])
		if member_ids.has(unit_id):
			return group
	return {}


func _group_id_containing(groups: Array[Dictionary], unit_id: int) -> int:
	return int(_find_group_containing(groups, unit_id).get("group_id", -1))


func _find_unit_node(unit_id: int) -> PlanBUnit:
	for child: Node in _simulation.get_children():
		var unit := child as PlanBUnit
		if unit != null and unit.unit_id == unit_id:
			return unit
	return null


func _word(word_id: String, text: String, battle_type: String, strength: int) -> Dictionary:
	return {
		"word_id": word_id,
		"text": text,
		"battle_type": battle_type,
		"strength": strength,
		"traits": [],
		"tendency": "neutral",
	}


func _on_word_groups_changed(groups: Array) -> void:
	_group_change_events.append(groups.duplicate(true))


func _on_contact_resolved(first_id: int, second_id: int, outcome: StringName) -> void:
	var pair := Vector2i(mini(first_id, second_id), maxi(first_id, second_id))
	var outcomes: Array = _contact_events_by_pair.get(pair, [])
	outcomes.append(str(outcome))
	_contact_events_by_pair[pair] = outcomes


func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failed_checks.append(description)
	push_error("PB-11 CHECK FAILED: " + description)


func _finish_smoke() -> void:
	_simulation.pause_simulation()
	if _failed_checks.is_empty():
		print("PB-11 PASS: group topology/hysteresis, flocking, word isolation, soft ally separation, enemy recoil")
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)
		return
	print("PB-11 FAIL: %d check(s)" % _failed_checks.size())
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1)
