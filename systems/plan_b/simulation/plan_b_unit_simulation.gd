## 管理本局观众棋子的播种、运动、接触裁决、自然离场和中立人口补充。
class_name PlanBUnitSimulation
extends Node2D

signal unit_changed(unit_id: int, reason: StringName)
signal unit_spawned(unit_id: int)
signal unit_despawned(unit_id: int)
signal contact_resolved(first_unit_id: int, second_unit_id: int, outcome: StringName)
signal word_batch_spawned(batch: Dictionary)
signal word_batch_trait_awarded(word_order: int, unit_id: int, trait_name: StringName)
signal word_groups_changed(groups: Array)
signal unit_physics_positions_updated(
	unit_ids: PackedInt32Array,
	previous_positions: PackedVector2Array,
	current_positions: PackedVector2Array
)
signal simulation_started
signal simulation_paused

const UNIT_SCENE: PackedScene = preload("res://systems/plan_b/simulation/plan_b_unit.tscn")
const PB14_PERFORMANCE_TRACKER_SCRIPT: Script = preload("res://systems/plan_b/performance/pb14_performance_tracker.gd")
const NEUTRAL_TEAM: StringName = &"neutral"
const PLAYER_TEAM: StringName = &"player"
const OPPONENT_TEAM: StringName = &"opponent"
const WORD_BATCH_SIZE_BY_STRENGTH: Dictionary = {1: 2, 2: 4, 3: 8}
const S1_INSTANT_REWRITE_MAX_TARGETS: int = 4
const RANDOM_SPAWN_CANDIDATE_COUNT: int = 64
const RANDOM_SPAWN_GRID_COLUMNS: int = 7
const RANDOM_SPAWN_GRID_ROWS: int = 6
const INFECTION_CHANCES_BY_STRENGTH: Dictionary = {
	1: 0.50,
	2: 0.60,
	3: 0.70,
}
const BATCH_TRAIT_INFECTION_THRESHOLD: int = 5
const SPAWN_BURST_DURATION_SECONDS: float = 0.5

@export_group("Audience Population")
@export_range(1, 512, 1) var maximum_population: int = 96
@export_range(0, 500, 1) var initial_neutral_count: int = 30
@export_range(0, 32, 1) var initial_seed_slot_count: int = 2
@export_range(0, 32, 1) var neutral_spawn_batch_reserve: int = 8
@export_range(0.05, 10.0, 0.05) var neutral_spawn_interval_seconds: float = 0.75
## 以现有补人节奏为中心扰动到达时间；固定随机 seed 时，补人时刻可重复。
@export_range(0.0, 0.95, 0.05) var neutral_spawn_jitter_ratio: float = 0.25
@export_range(1.0, 180.0, 0.5) var lifespan_min_seconds: float = 53.0
@export_range(1.0, 180.0, 0.5) var lifespan_max_seconds: float = 77.0

@export_group("Collision")
@export_range(2.0, 32.0, 1.0) var unit_collision_radius: float = 32.0
@export_range(0.0, 5.0, 0.05) var collision_cooldown_seconds: float = 0.7
@export_range(0.0, 120.0, 1.0) var contact_recoil_speed: float = 22.0

@export_group("S1 Instant Rewrite")
@export_range(0.0, 480.0, 1.0) var s1_instant_rewrite_radius: float = 120.0

@export_group("Movement")
@export_range(1.0, 160.0, 1.0) var base_speed_min: float = 30.0
@export_range(1.0, 160.0, 1.0) var base_speed_max: float = 52.0
@export_range(1.0, 200.0, 1.0) var maximum_speed: float = 78.0
@export_range(1.0, 1000.0, 1.0) var detection_radius: float = 220.0
@export_range(0.0, 3.0, 0.05) var wandering_weight: float = 0.35
@export_range(0.0, 3.0, 0.05) var chase_weight: float = 1.0
@export_range(0.0, 3.0, 0.05) var flee_weight: float = 1.35
@export_range(0.0, 2.0, 0.05) var chase_speed_scale: float = 1.05
@export_range(0.0, 2.0, 0.05) var flee_speed_scale: float = 1.15

@export_group("Group Motion")
@export_range(32.0, 512.0, 1.0) var ally_detection_radius: float = 160.0
## 运行时实际间距不低于当前碰撞直径，避免同盟靠拢时持续挤入碰撞圆。
@export_range(20.0, 128.0, 1.0) var ally_ideal_spacing: float = 36.0
@export_range(0.0, 2.0, 0.05) var ally_attraction_weight: float = 0.45
@export_range(0.0, 2.0, 0.05) var ally_separation_weight: float = 0.65
## 运行时入组距离不低于当前碰撞直径。
@export_range(24.0, 128.0, 1.0) var word_group_join_distance: float = 72.0
## 运行时离组距离至少比有效入组距离多留迟滞余量。
@export_range(24.0, 180.0, 1.0) var word_group_leave_distance: float = 90.0
@export_range(60.0, 400.0, 1.0) var word_group_max_center_radius: float = 180.0
@export_range(0.05, 0.5, 0.01) var target_decision_refresh_seconds: float = 0.1
@export_range(0.05, 0.5, 0.05) var neighbor_grid_refresh_seconds: float = 0.1
@export_range(0.05, 1.0, 0.05) var group_topology_refresh_seconds: float = 0.2
@export_range(0.05, 0.5, 0.01) var contact_recoil_duration_seconds: float = 0.18

@export var play_area: Rect2 = Rect2()

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _neutral_spawn_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _units_by_id: Dictionary = {}
var _type_counter_by_type: Dictionary = {}
var _next_unit_id: int = 1
var _is_running: bool = false
var _spawn_elapsed_seconds: float = 0.0
var _next_neutral_spawn_interval_seconds: float = 0.0
var _pending_contact_pairs: Array[Vector2i] = []
var _pending_contact_lookup: Dictionary = {}
var _spawned_word_batches_by_order: Dictionary = {}
var _player_batch_infection_counts: Dictionary = {}
var _player_batch_trait_triggered: Dictionary = {}
var _neighbor_grid: Dictionary = {}
var _neighbor_grid_cell_size: float = 220.0
var _neighbor_grid_elapsed_seconds: float = 0.0
var _neighbor_grid_dirty: bool = true
var _neighbor_grid_positions_adjusted: bool = false
var _word_groups_by_id: Dictionary = {}
var _next_word_group_id: int = 1
var _group_refresh_remaining_seconds: float = 0.0
var _steering_cache_by_unit_id: Dictionary = {}
var _previous_physics_positions_by_unit_id: Dictionary = {}
var _performance_tracker: Node
var _tracker_steering_decisions_this_tick: int = 0
var _tracker_neighbor_query_count: int = 0
var _tracker_neighbor_total_usec: int = 0
var _tracker_neighbor_max_usec: int = 0
var _tracker_neighbor_candidate_total: int = 0
var _tracker_neighbor_candidate_max: int = 0
var _tracker_neighbor_result_total: int = 0
var _tracker_neighbor_result_max: int = 0


func _ready() -> void:
	_rng.randomize()
	_neutral_spawn_rng.randomize()
	# 默认使用当前 Viewport 的本地尺寸；嵌入战斗场景时由 A 注入实际中央区域。
	if play_area.size.x <= 0.0 or play_area.size.y <= 0.0:
		play_area = Rect2(Vector2.ZERO, get_viewport_rect().size)
	set_physics_process(false)


## 设置可替换的“战斗类型 -> 能克制的类型”测试表；正式属性名和方向由 C 注入。
func set_type_counter_map(counter_map: Dictionary) -> bool:
	var normalized_map: Dictionary = {}
	for source_value: Variant in counter_map.keys():
		var target_value: Variant = counter_map[source_value]
		var source_type := StringName(str(source_value).strip_edges())
		var target_type := StringName(str(target_value).strip_edges())
		if source_type == &"" or target_type == &"" or source_type == target_type:
			return false
		normalized_map[source_type] = target_type
	_type_counter_by_type = normalized_map
	return true


## 固定本局随机流；补人时序使用独立随机流，避免棋子行为改变到达顺序。
func set_random_seed(seed_value: int) -> void:
	_rng.seed = seed_value
	_neutral_spawn_rng.seed = seed_value
	_spawn_elapsed_seconds = 0.0
	_next_neutral_spawn_interval_seconds = 0.0


## 将 C 的开局与补人配置注入模拟器；A 的对手播种数量由 create_population 的显式参数控制。
func configure_population_config(config: Dictionary) -> bool:
	if _is_running or not _units_by_id.is_empty():
		return false
	if not config.has("initial_neutral_count") or not config.has("initial_seed_slot_count") \
		or not config.has("neutral_spawn_interval_seconds") \
		or not config.has("neutral_spawn_jitter_ratio"):
		return false
	var neutral_count: int = int(config["initial_neutral_count"])
	var c_seed_slot_count: int = int(config["initial_seed_slot_count"])
	var spawn_interval: float = float(config["neutral_spawn_interval_seconds"])
	var jitter_ratio: float = float(config["neutral_spawn_jitter_ratio"])
	if neutral_count < 0 or c_seed_slot_count < 0 or c_seed_slot_count > 32 \
		or neutral_count + c_seed_slot_count > maximum_population \
		or spawn_interval < 0.05 or spawn_interval > 10.0 \
		or jitter_ratio < 0.0 or jitter_ratio > 0.95:
		return false
	initial_neutral_count = neutral_count
	initial_seed_slot_count = c_seed_slot_count
	neutral_spawn_interval_seconds = spawn_interval
	neutral_spawn_jitter_ratio = jitter_ratio
	_spawn_elapsed_seconds = 0.0
	_next_neutral_spawn_interval_seconds = 0.0
	return true


## 按基础间隔和扰动比例为下一名中立观众抽取到达时间。
func _roll_neutral_spawn_interval_seconds() -> float:
	var base_interval: float = maxf(neutral_spawn_interval_seconds, 0.05)
	var jitter_ratio: float = clampf(neutral_spawn_jitter_ratio, 0.0, 0.95)
	var minimum_interval: float = maxf(base_interval * (1.0 - jitter_ratio), 0.05)
	var maximum_interval: float = maxf(base_interval * (1.0 + jitter_ratio), minimum_interval)
	return _neutral_spawn_rng.randf_range(minimum_interval, maximum_interval)


## A 注入棋盘的全局场景矩形；模拟器根节点无旋转、单位缩放时转换成本地边界。
func set_play_area(scene_area: Rect2) -> bool:
	if scene_area.size.x <= unit_collision_radius * 2.0 or scene_area.size.y <= unit_collision_radius * 2.0:
		return false
	var local_corner_a: Vector2 = to_local(scene_area.position)
	var local_corner_b: Vector2 = to_local(scene_area.end)
	var local_minimum := Vector2(
		minf(local_corner_a.x, local_corner_b.x),
		minf(local_corner_a.y, local_corner_b.y)
	)
	var local_maximum := Vector2(
		maxf(local_corner_a.x, local_corner_b.x),
		maxf(local_corner_a.y, local_corner_b.y)
	)
	var local_area := Rect2(local_minimum, local_maximum - local_minimum)
	if local_area.size.x <= unit_collision_radius * 2.0 or local_area.size.y <= unit_collision_radius * 2.0:
		return false
	play_area = local_area
	return true


## 创建中立人群及预留播种目标。预留目标先保持中立，由 A 读取 C 词语后调用 seed_unit。
func create_population(neutral_count: int = -1, seed_slot_count: int = -1) -> Array[int]:
	clear_population()
	var neutral_total: int = initial_neutral_count if neutral_count < 0 else maxi(neutral_count, 0)
	var reserved_total: int = initial_seed_slot_count if seed_slot_count < 0 else maxi(seed_slot_count, 0)
	var population_total: int = mini(neutral_total + reserved_total, maximum_population)
	var created_ids: Array[int] = []
	for index: int in population_total:
		var new_unit: PlanBUnit = _spawn_unit(NEUTRAL_TEAM, {}, 0, _random_spawn_position())
		created_ids.append(new_unit.unit_id)
	return created_ids


## 将一个现存中立观众改成首次信徒；验证失败不会改变棋子或发出事件。
func seed_unit(neutral_unit_id: int, team_value: StringName, word_definition: Dictionary, new_word_order: int) -> bool:
	var unit := _units_by_id.get(neutral_unit_id) as PlanBUnit
	var clean_team := StringName(str(team_value))
	var clean_definition: Dictionary = _copy_valid_word_definition(word_definition)
	if unit == null or unit.team != NEUTRAL_TEAM:
		return false
	if not _is_faction(clean_team) or clean_definition.is_empty() or new_word_order < 1:
		return false
	unit.apply_word_snapshot(clean_team, clean_definition, new_word_order)
	unit_changed.emit(unit.unit_id, &"seed")
	return true


## PB-25 只在首关教程兜底时，按真实battle_type克制关系完成一次剧情感染并发出原事件。
func apply_tutorial_conversion(infecting_unit_id: int, receiving_unit_id: int) -> Dictionary:
	if not _is_running:
		return {"ok": false, "reason": &"simulation_not_running"}
	var infecting_unit := _units_by_id.get(infecting_unit_id) as PlanBUnit
	var receiving_unit := _units_by_id.get(receiving_unit_id) as PlanBUnit
	if infecting_unit == null or receiving_unit == null:
		return {"ok": false, "reason": &"target_unavailable"}
	if (infecting_unit.team != PLAYER_TEAM or receiving_unit.team != OPPONENT_TEAM
			or not infecting_unit.has_word() or not receiving_unit.has_word()):
		return {"ok": false, "reason": &"invalid_factions"}
	if not _counters(infecting_unit, receiving_unit):
		return {"ok": false, "reason": &"no_type_advantage"}
	var source_word_order := infecting_unit.word_order
	receiving_unit.apply_word_snapshot(
		PLAYER_TEAM, infecting_unit.get_word_snapshot(), source_word_order
	)
	unit_changed.emit(receiving_unit.unit_id, &"convert")
	_record_player_batch_infection(source_word_order)
	contact_resolved.emit(infecting_unit.unit_id, receiving_unit.unit_id, &"converted")
	return {
		"ok": true,
		"source_unit_id": infecting_unit.unit_id,
		"target_unit_id": receiving_unit.unit_id,
		"battle_type": str(infecting_unit.get_battle_type()),
		"word_order": source_word_order,
	}


## 按 strength 一次提交完整2/4/8颗批次；校验或容量失败时不创建节点、不占用 ID。
func spawn_word_batch(
	scene_position: Vector2,
	team_value: StringName,
	word_definition: Dictionary,
	new_word_order: int,
	requested_count: int
) -> Dictionary:
	var clean_team := StringName(str(team_value).strip_edges())
	var clean_definition: Dictionary = _copy_valid_word_definition(word_definition)
	if not _is_faction(clean_team):
		return _batch_spawn_failure(&"invalid_team")
	if clean_definition.is_empty() or new_word_order < 1:
		return _batch_spawn_failure(&"invalid_word")
	var expected_count: int = int(WORD_BATCH_SIZE_BY_STRENGTH.get(int(clean_definition.get("strength", 0)), 0))
	if requested_count != expected_count:
		return _batch_spawn_failure(&"invalid_batch_size")
	if _spawned_word_batches_by_order.has(new_word_order):
		return _batch_spawn_failure(&"duplicate_word_order")
	if not _is_scene_position_in_play_area(scene_position):
		return _batch_spawn_failure(&"invalid_position")
	if _units_by_id.size() + expected_count > maximum_population:
		return _batch_spawn_failure(&"capacity")

	var local_spawn_position: Vector2 = to_local(scene_position)
	var local_spawn_positions: Array[Vector2] = _get_word_batch_spawn_positions(
		local_spawn_position, expected_count, new_word_order
	)
	if local_spawn_positions.size() != expected_count:
		return _batch_spawn_failure(&"no_spawn_space")

	# 先完整实例化整批；预检失败时释放预备节点，ID和随机流均保持原值。
	var pending_units: Array[PlanBUnit] = []
	for child_index: int in expected_count:
		var unit_instance: Node = UNIT_SCENE.instantiate()
		var unit := unit_instance as PlanBUnit
		if unit == null:
			if is_instance_valid(unit_instance):
				unit_instance.free()
			for pending_unit: PlanBUnit in pending_units:
				pending_unit.free()
			return _batch_spawn_failure(&"unit_scene_unavailable")
		pending_units.append(unit)

	var first_unit_id: int = _next_unit_id
	var batch_unit_ids: Array[int] = []
	var target_positions: Array[Vector2] = []
	for child_index: int in expected_count:
		var unit_id: int = first_unit_id + child_index
		var unit: PlanBUnit = pending_units[child_index]
		var local_target: Vector2 = local_spawn_positions[child_index]
		var spawn_direction: Vector2 = (local_target - local_spawn_position).normalized()
		if spawn_direction.length_squared() <= 0.0001:
			spawn_direction = Vector2.from_angle(TAU * float(child_index) / float(expected_count))
		var wander := Vector2.from_angle(_rng.randf_range(0.0, TAU))
		var lifetime: float = _rng.randf_range(minf(lifespan_min_seconds, lifespan_max_seconds), maxf(lifespan_min_seconds, lifespan_max_seconds))
		var base_speed: float = _rng.randf_range(minf(base_speed_min, base_speed_max), maxf(base_speed_min, base_speed_max))
		_configure_spawn_unit(unit, unit_id, clean_team, clean_definition, new_word_order, local_target, wander, base_speed, lifetime)
		unit.spawn_burst_direction = spawn_direction
		unit.spawn_burst_speed = minf(maximum_speed, maxf(48.0, base_speed))
		unit.spawn_burst_remaining_seconds = SPAWN_BURST_DURATION_SECONDS
		unit.velocity = spawn_direction * unit.spawn_burst_speed
		batch_unit_ids.append(unit_id)
		target_positions.append(to_global(local_target))

	# 先登记全体，再开启物理监测并发事实信号；观察者读取时总能看到完整人口。
	for child_index: int in expected_count:
		_register_spawn_unit(pending_units[child_index], first_unit_id + child_index)
	_next_unit_id += expected_count
	for unit: PlanBUnit in pending_units:
		unit.monitoring = true

	_spawned_word_batches_by_order[new_word_order] = clean_team
	if clean_team == PLAYER_TEAM:
		_player_batch_infection_counts[new_word_order] = 0
		_player_batch_trait_triggered[new_word_order] = false
	var batch: Dictionary = {
		"ok": true,
		"reason": "ok",
		"word_order": new_word_order,
		"team": str(clean_team),
		"word_id": str(clean_definition.get("word_id", "")),
		"word_definition": clean_definition.duplicate(true),
		"spawn_position": scene_position,
		"spawn_target_positions": target_positions.duplicate(),
		"unit_ids": batch_unit_ids.duplicate(),
		"count": expected_count,
	}
	for unit: PlanBUnit in pending_units:
		unit_spawned.emit(unit.unit_id)
	word_batch_spawned.emit(batch.duplicate(true))
	return batch


## S1 整批出生成功后，改写落点附近最靠近的旧玩家信徒；排除本批新单位。
func rewrite_player_units_nearby_after_s1(
	center_position: Vector2,
	word_definition: Dictionary,
	new_word_order: int,
	excluded_unit_ids: Array
) -> Array[int]:
	var clean_definition: Dictionary = _copy_valid_word_definition(word_definition)
	if clean_definition.is_empty() or int(clean_definition.get("strength", 0)) != 1 or new_word_order < 1:
		return []
	var excluded_ids: Dictionary = {}
	for value: Variant in excluded_unit_ids:
		var excluded_id: int = _normalize_unit_id(value)
		if excluded_id >= 0:
			excluded_ids[excluded_id] = true
	var radius: float = maxf(s1_instant_rewrite_radius, 0.0)
	var radius_squared: float = radius * radius
	var candidates: Array[Dictionary] = []
	for unit_id: int in _get_sorted_unit_ids():
		if excluded_ids.has(unit_id):
			continue
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		if unit == null or unit.team != PLAYER_TEAM or not unit.has_word() or unit.word_order >= new_word_order:
			continue
		var distance_squared: float = unit.global_position.distance_squared_to(center_position)
		if distance_squared > radius_squared:
			continue
		candidates.append({
			"unit": unit,
			"unit_id": unit.unit_id,
			"distance_squared": distance_squared,
		})
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_distance: float = float(first.get("distance_squared", 0.0))
		var second_distance: float = float(second.get("distance_squared", 0.0))
		if first_distance == second_distance:
			return int(first.get("unit_id", -1)) < int(second.get("unit_id", -1))
		return first_distance < second_distance
	)
	var rewritten_unit_ids: Array[int] = []
	var rewrite_count: int = mini(S1_INSTANT_REWRITE_MAX_TARGETS, candidates.size())
	for candidate_index: int in rewrite_count:
		var candidate: Dictionary = candidates[candidate_index]
		var unit := candidate.get("unit") as PlanBUnit
		if unit == null:
			continue
		# apply_word_snapshot 只替换话语、属性、倾向、强度与顺序号，保留旧友军的运行状态。
		unit.apply_word_snapshot(PLAYER_TEAM, clean_definition, new_word_order)
		rewritten_unit_ids.append(unit.unit_id)
		# 复用现有 S1 relay 事件聚合，让 UI 将同一批改口合并为一次反馈。
		unit_changed.emit(unit.unit_id, &"relay")
	if not rewritten_unit_ids.is_empty():
		# 下一物理步先刷新邻居网格，再重算新的同词团体拓扑。
		_group_refresh_remaining_seconds = 0.0
	return rewritten_unit_ids


## 执行四名主播的专属反击；单位事实留在 B，A/C 只调度并回收结果。
func apply_counterattack_effect(request: Dictionary) -> Dictionary:
	if not _is_running or request.is_empty():
		return _counterattack_failure("simulation_unavailable", "")
	var streamer_id: String = str(request.get("streamer_id", ""))
	if streamer_id.is_empty() and str(request.get("effect_id", "")) == "split":
		# 兼容 PB-02 旧反击夹具；正式请求始终带稳定主播 ID。
		streamer_id = "alien"
	match streamer_id:
		"alien":
			return _apply_alien_split_counterattack(request)
		"kiwi":
			return _apply_kiwi_rewrite_counterattack(request)
		"frog":
			return _apply_frog_absorb_counterattack(request)
		"fox":
			return _apply_fox_reflect_counterattack(request)
		_:
			return _counterattack_failure("unknown_streamer", streamer_id)


## 费米选中的信徒分裂出最多请求数量的同快照棋子，受全场人口上限约束。
func _apply_alien_split_counterattack(request: Dictionary) -> Dictionary:
	var target_id: int = _normalize_unit_id(request.get("target_unit_id", -1))
	var target_unit := _units_by_id.get(target_id) as PlanBUnit
	if target_unit == null or target_unit.team != OPPONENT_TEAM or not target_unit.has_word():
		return _counterattack_failure("no_usable_target", "split")
	if str(target_unit.get_word_snapshot().get("streamer_id", "")) not in ["", "alien"]:
		return _counterattack_failure("wrong_streamer_target", "split")
	var parameters_value: Variant = request.get("effect_parameters", {})
	if not parameters_value is Dictionary:
		return _counterattack_failure("invalid_parameters", "split")
	var effect_parameters: Dictionary = parameters_value
	var requested_count: int = maxi(int(effect_parameters.get("child_count", 2)), 0)
	var available_slots: int = maxi(maximum_population - _units_by_id.size(), 0)
	var spawn_count: int = mini(requested_count, available_slots)
	if spawn_count <= 0:
		return _counterattack_failure("capacity", "split")
	var source_definition: Dictionary = target_unit.get_word_snapshot()
	var spawned_unit_ids: Array[int] = []
	for child_index: int in spawn_count:
		var spawn_position: Vector2 = _get_split_child_position(target_unit, child_index, spawn_count)
		var child_unit: PlanBUnit = _spawn_unit(
			target_unit.team, source_definition, target_unit.word_order, spawn_position
		)
		if child_unit != null:
			spawned_unit_ids.append(child_unit.unit_id)
	if spawned_unit_ids.is_empty():
		return _counterattack_failure("unit_scene_unavailable", "split")
	return _counterattack_success("split", spawned_unit_ids, {
		"source_unit_id": target_id,
		"spawned_count": spawned_unit_ids.size(),
		"message": "费米分裂生成%d名信徒" % spawned_unit_ids.size(),
	})


## 奥格尔从玩家主流属性的克制方向选一条当前合法敌方词，改写最多三名己方旧信徒。
func _apply_kiwi_rewrite_counterattack(request: Dictionary) -> Dictionary:
	var dominant_type: StringName = _get_dominant_player_battle_type()
	if dominant_type == &"":
		return _counterattack_failure("no_player_word_type", "kiwi_rewrite")
	var rewrite_type: StringName = _get_battle_type_that_counters(dominant_type)
	if rewrite_type == &"":
		return _counterattack_failure("no_counter_type", "kiwi_rewrite")
	var available_words_value: Variant = request.get("available_opponent_words", [])
	if not available_words_value is Array:
		return _counterattack_failure("no_counter_word", "kiwi_rewrite")
	var selected_definition: Dictionary = {}
	for word_value: Variant in available_words_value:
		if not word_value is Dictionary:
			continue
		var definition: Dictionary = _copy_valid_word_definition(word_value)
		if definition.is_empty() or str(definition.get("battle_type", "")) != str(rewrite_type):
			continue
		if str(definition.get("streamer_id", "")) != "kiwi" \
			or str(definition.get("available_to", "")) != "opponent":
			continue
		selected_definition = definition
		break
	if selected_definition.is_empty():
		return _counterattack_failure("no_counter_word", "kiwi_rewrite")
	var new_word_order: int = int(request.get("word_order", 0))
	if new_word_order < 1:
		return _counterattack_failure("invalid_word_order", "kiwi_rewrite")
	var parameters_value: Variant = request.get("effect_parameters", {})
	if not parameters_value is Dictionary:
		return _counterattack_failure("invalid_parameters", "kiwi_rewrite")
	var effect_parameters: Dictionary = parameters_value
	var maximum_targets: int = clampi(int(effect_parameters.get("max_targets", 3)), 0, 3)
	if maximum_targets <= 0:
		return _counterattack_failure("invalid_parameters", "kiwi_rewrite")
	var targets: Array[PlanBUnit] = []
	for unit: PlanBUnit in _get_sorted_units():
		if unit.team != OPPONENT_TEAM or not unit.has_word():
			continue
		if _get_unit_streamer_id(unit) != "kiwi" or unit.word_order >= new_word_order:
			continue
		targets.append(unit)
		if targets.size() >= maximum_targets:
			break
	if targets.is_empty():
		return _counterattack_failure("no_usable_target", "kiwi_rewrite")
	var affected_unit_ids: Array[int] = []
	for unit: PlanBUnit in targets:
		unit.apply_word_snapshot(OPPONENT_TEAM, selected_definition, new_word_order)
		affected_unit_ids.append(unit.unit_id)
		unit_changed.emit(unit.unit_id, &"relay")
	_group_refresh_remaining_seconds = 0.0
	return _counterattack_success("kiwi_rewrite", affected_unit_ids, {
		"word_id": str(selected_definition.get("word_id", "")),
		"word_order": new_word_order,
		"battle_type": str(rewrite_type),
		"dominant_player_battle_type": str(dominant_type),
		"counter_battle_type": str(rewrite_type),
		"message": "奥格尔改口%d名信徒" % affected_unit_ids.size(),
	})


## 咕拉以一名己方信徒为施法者，将120px内最近的最多三名中立观众转成同属性信徒。
func _apply_frog_absorb_counterattack(request: Dictionary) -> Dictionary:
	var caster_id: int = _normalize_unit_id(request.get("target_unit_id", -1))
	var caster := _units_by_id.get(caster_id) as PlanBUnit
	if caster == null or caster.team != OPPONENT_TEAM or not caster.has_word() \
		or _get_unit_streamer_id(caster) != "frog":
		return _counterattack_failure("no_usable_caster", "frog_absorb")
	var parameters_value: Variant = request.get("effect_parameters", {})
	if not parameters_value is Dictionary:
		return _counterattack_failure("invalid_parameters", "frog_absorb")
	var effect_parameters: Dictionary = parameters_value
	var radius: float = maxf(float(effect_parameters.get("radius_pixels", 120.0)), 0.0)
	var maximum_targets: int = clampi(int(effect_parameters.get("max_targets", 3)), 0, 3)
	if maximum_targets <= 0:
		return _counterattack_failure("invalid_parameters", "frog_absorb")
	var candidates: Array[Dictionary] = []
	for unit: PlanBUnit in _get_sorted_units():
		if unit.team != NEUTRAL_TEAM:
			continue
		var distance_squared: float = unit.global_position.distance_squared_to(caster.global_position)
		if distance_squared > radius * radius:
			continue
		candidates.append({"unit": unit, "distance_squared": distance_squared, "unit_id": unit.unit_id})
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_distance: float = float(first.get("distance_squared", 0.0))
		var second_distance: float = float(second.get("distance_squared", 0.0))
		if first_distance == second_distance:
			return int(first.get("unit_id", -1)) < int(second.get("unit_id", -1))
		return first_distance < second_distance
	)
	var affected_unit_ids: Array[int] = []
	var target_count: int = mini(maximum_targets, candidates.size())
	for candidate_index: int in target_count:
		var neutral := candidates[candidate_index].get("unit") as PlanBUnit
		if neutral == null:
			continue
		neutral.apply_word_snapshot(OPPONENT_TEAM, caster.get_word_snapshot(), caster.word_order)
		affected_unit_ids.append(neutral.unit_id)
		unit_changed.emit(neutral.unit_id, &"convert")
		contact_resolved.emit(caster.unit_id, neutral.unit_id, &"converted")
	if affected_unit_ids.is_empty():
		return _counterattack_failure("no_usable_target", "frog_absorb")
	_group_refresh_remaining_seconds = 0.0
	return _counterattack_success("frog_absorb", affected_unit_ids, {
		"source_unit_id": caster_id,
		"radius_pixels": radius,
		"message": "咕拉吞食%d名中立观众" % affected_unit_ids.size(),
	})


## 列巴给最多三名现存信徒添加一次性reflect；合法玩家感染会由原反弹裁决消耗。
func _apply_fox_reflect_counterattack(request: Dictionary) -> Dictionary:
	var parameters_value: Variant = request.get("effect_parameters", {})
	if not parameters_value is Dictionary:
		return _counterattack_failure("invalid_parameters", "fox_reflect")
	var effect_parameters: Dictionary = parameters_value
	var maximum_targets: int = clampi(int(effect_parameters.get("max_targets", 3)), 0, 3)
	if maximum_targets <= 0:
		return _counterattack_failure("invalid_parameters", "fox_reflect")
	var affected_unit_ids: Array[int] = []
	for unit: PlanBUnit in _get_sorted_units():
		if unit.team != OPPONENT_TEAM or not unit.has_word() \
			or _get_unit_streamer_id(unit) != "fox" \
			or (unit.combat_trait_uses > 0 and unit.combat_trait != &"reflect"):
			continue
		# T4可以刷新T2仍未消耗的一次性保护，但不覆盖其他类型的有效特性。
		unit.set_combat_trait(&"reflect", 1)
		affected_unit_ids.append(unit.unit_id)
		unit_changed.emit(unit.unit_id, &"reflect")
		if affected_unit_ids.size() >= maximum_targets:
			break
	if affected_unit_ids.is_empty():
		return _counterattack_failure("no_usable_target", "fox_reflect")
	return _counterattack_success("fox_reflect", affected_unit_ids, {
		"message": "列巴为%d名信徒加上反弹保护" % affected_unit_ids.size(),
	})


func _get_dominant_player_battle_type() -> StringName:
	var counts: Dictionary = {&"type_a": 0, &"type_b": 0, &"type_c": 0}
	for unit: PlanBUnit in _get_sorted_units():
		if unit.team != PLAYER_TEAM or not unit.has_word():
			continue
		var battle_type: StringName = unit.get_battle_type()
		if counts.has(battle_type):
			counts[battle_type] = int(counts[battle_type]) + 1
	var dominant_type: StringName = &""
	var dominant_count: int = 0
	for battle_type: StringName in [&"type_a", &"type_b", &"type_c"]:
		var count: int = int(counts.get(battle_type, 0))
		# 只用严格大于替换，平局稳定保留type_a→type_b→type_c顺序。
		if count > dominant_count:
			dominant_type = battle_type
			dominant_count = count
	return dominant_type


func _get_battle_type_that_counters(target_type: StringName) -> StringName:
	for attacker_type: StringName in [&"type_a", &"type_b", &"type_c"]:
		if StringName(str(_type_counter_by_type.get(attacker_type, ""))) == target_type:
			return attacker_type
	return &""


func _get_unit_streamer_id(unit: PlanBUnit) -> String:
	return str(unit.get_word_snapshot().get("streamer_id", ""))


func _counterattack_failure(reason: String, effect_id: String) -> Dictionary:
	return {
		"ok": false,
		"applied": false,
		"effect_id": effect_id,
		"reason": reason,
		"result_reason": reason,
		"message": _counterattack_failure_message(reason),
		"affected_count": 0,
		"affected_unit_ids": [],
	}


func _counterattack_success(effect_id: String, affected_unit_ids: Array[int], extra_details: Dictionary) -> Dictionary:
	var result: Dictionary = {
		"ok": not affected_unit_ids.is_empty(),
		"applied": not affected_unit_ids.is_empty(),
		"effect_id": effect_id,
		"reason": "applied" if not affected_unit_ids.is_empty() else "no_usable_target",
		"result_reason": "applied" if not affected_unit_ids.is_empty() else "no_usable_target",
		"message": "反击影响%d名单位" % affected_unit_ids.size(),
		"affected_count": affected_unit_ids.size(),
		"affected_unit_ids": affected_unit_ids.duplicate(),
	}
	for key: Variant in extra_details:
		result[str(key)] = extra_details[key]
	return result


func _counterattack_failure_message(reason: String) -> String:
	match reason:
		"no_usable_target":
			return "没有可用反击目标"
		"no_usable_caster":
			return "当前主播没有可用信徒"
		"no_counter_word":
			return "奥格尔词池没有可用的克制词条"
		"no_player_word_type":
			return "没有玩家信徒可用于判断主流属性"
		"no_counter_type":
			return "属性克制配置缺少反制类型"
		"capacity":
			return "反击效果受人口上限限制"
		"invalid_parameters":
			return "反击参数无效"
		"unit_scene_unavailable":
			return "分裂棋子生成失败"
		"invalid_word_order":
			return "无法分配新的话语顺序"
		"wrong_streamer_target":
			return "选中的棋子不属于当前主播"
		"unknown_streamer":
			return "当前主播没有可用技能"
		"simulation_unavailable":
			return "模拟器当前无法执行反击"
		_:
			return "反击未生效：%s" % reason


## 启动或恢复本地物理帧推进；棋子移动和碰撞由模块自身驱动。
func start_simulation() -> void:
	if _is_running:
		return
	_is_running = true
	var units: Array[PlanBUnit] = _get_sorted_units()
	_rebuild_neighbor_grid(units)
	_neighbor_grid_elapsed_seconds = 0.0
	if _next_neutral_spawn_interval_seconds <= 0.0:
		_next_neutral_spawn_interval_seconds = _roll_neutral_spawn_interval_seconds()
	_refresh_word_groups()
	# 开局或测试夹具调整棋子位置时，将首个插值区间设为零长度。
	for unit: PlanBUnit in units:
		_previous_physics_positions_by_unit_id[unit.unit_id] = unit.global_position
	set_physics_process(true)
	simulation_started.emit()


## 暂停棋子运动、生命周期、碰撞裁决和路人补充，保留所有运行状态。
func pause_simulation() -> void:
	if not _is_running:
		return
	_is_running = false
	set_physics_process(false)
	simulation_paused.emit()


## 清场并立即释放所属棋子，不依赖离树回调完成业务清理。
func clear_population() -> void:
	pause_simulation()
	var had_word_groups: bool = not _word_groups_by_id.is_empty()
	_pending_contact_pairs.clear()
	_pending_contact_lookup.clear()
	_spawn_elapsed_seconds = 0.0
	_next_neutral_spawn_interval_seconds = 0.0
	_spawned_word_batches_by_order.clear()
	_player_batch_infection_counts.clear()
	_player_batch_trait_triggered.clear()
	_neighbor_grid.clear()
	_neighbor_grid_elapsed_seconds = 0.0
	_neighbor_grid_dirty = true
	_neighbor_grid_positions_adjusted = false
	_steering_cache_by_unit_id.clear()
	_previous_physics_positions_by_unit_id.clear()
	_word_groups_by_id.clear()
	_next_word_group_id = 1
	_group_refresh_remaining_seconds = 0.0
	if _performance_tracker != null:
		_performance_tracker.call("set_group_snapshot", 0, 0)
	var existing_ids: Array[int] = _get_sorted_unit_ids()
	for unit_id: int in existing_ids:
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		_units_by_id.erase(unit_id)
		if is_instance_valid(unit):
			remove_child(unit)
			unit.queue_free()
		unit_despawned.emit(unit_id)
	if had_word_groups:
		word_groups_changed.emit([])


## PB-01 的清场入口；业务清理仍统一由本模拟模块拥有。
func clear_battle() -> void:
	clear_population()


## 供 A 以一个布尔值控制开始、暂停或恢复。
func set_active(active: bool) -> void:
	if active:
		start_simulation()
	else:
		pause_simulation()


## 按阵营重新统计实际棋子；PK 由 A 每帧读取本查询结果。
func get_faction_counts() -> Dictionary:
	var counts: Dictionary = {"player": 0, "opponent": 0, "neutral": 0}
	for unit_value: Variant in _units_by_id.values():
		var unit := unit_value as PlanBUnit
		if unit == null:
			continue
		var key := str(unit.team)
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


## 提供按 unit_id 排序的深拷贝，供 UI 绘制、交接和日志读取。
func get_unit_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for unit_id: int in _get_sorted_unit_ids():
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		if unit != null:
			snapshots.append(unit.get_public_snapshot())
	return snapshots


## 返回单个棋子的只读深拷贝；找不到时返回空字典。
func get_unit_snapshot(unit_id: int) -> Dictionary:
	var unit := _units_by_id.get(unit_id) as PlanBUnit
	return unit.get_public_snapshot() if unit != null else {}


## 返回 B 唯一计算的同阵营、同word_id空间连通组；成员位置用全局像素坐标。
func get_word_groups() -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	var group_ids: Array[int] = []
	for key: Variant in _word_groups_by_id.keys():
		group_ids.append(int(key))
	group_ids.sort()
	for group_id: int in group_ids:
		var stored_group: Dictionary = _word_groups_by_id.get(group_id, {})
		var member_positions: Dictionary = {}
		var member_ids: Array[int] = []
		var center_sum := Vector2.ZERO
		for member_value: Variant in stored_group.get("member_ids", []):
			var member_id: int = int(member_value)
			var unit := _units_by_id.get(member_id) as PlanBUnit
			if unit == null or unit.team != StringName(str(stored_group.get("team", ""))):
				continue
			var world_position: Vector2 = unit.global_position
			member_ids.append(member_id)
			member_positions[member_id] = world_position
			center_sum += world_position
		if member_ids.is_empty():
			continue
		var group_snapshot: Dictionary = stored_group.duplicate(true)
		group_snapshot["member_ids"] = member_ids
		group_snapshot["member_positions"] = member_positions
		group_snapshot["center_position"] = center_sum / float(member_ids.size())
		groups.append(group_snapshot)
	return groups

## 将当前稳定ID顺序的棋子放进空间网格；目标和团体查询共用这份局部索引。
func _rebuild_neighbor_grid(units: Array[PlanBUnit]) -> void:
	_neighbor_grid.clear()
	_neighbor_grid_cell_size = maxf(
		maxf(detection_radius, ally_detection_radius),
		maxf(_effective_word_group_leave_distance(), unit_collision_radius * 4.0)
	)
	for unit: PlanBUnit in units:
		var cell: Vector2i = _neighbor_grid_cell_for_position(unit.position)
		var bucket: Array = _neighbor_grid.get(cell, [])
		bucket.append(unit)
		_neighbor_grid[cell] = bucket
	_neighbor_grid_dirty = false
	_neighbor_grid_positions_adjusted = false


## 只从附近网格桶取候选，再用当前物理位置做精确半径过滤。
func _get_neighbor_units(scene_local_position: Vector2, search_radius: float) -> Array[PlanBUnit]:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	var scanned_candidate_count: int = 0
	var nearby_units: Array[PlanBUnit] = []
	if _neighbor_grid.is_empty() or search_radius <= 0.0:
		if _performance_tracker != null:
			_record_tracker_neighbor_query(Time.get_ticks_usec() - tracker_start_usec, 0, 0)
		return nearby_units
	# 网格刷新之间的自然位移与一次接触分离都计入候选半径，避免碰撞后立即全量重建。
	var movement_padding: float = maximum_speed * _neighbor_grid_elapsed_seconds
	if _neighbor_grid_positions_adjusted:
		movement_padding += unit_collision_radius + 0.5
	var padded_radius: float = search_radius + movement_padding
	var cell_minimum: Vector2i = _neighbor_grid_cell_for_position(
		scene_local_position - Vector2.ONE * padded_radius
	)
	var cell_maximum: Vector2i = _neighbor_grid_cell_for_position(
		scene_local_position + Vector2.ONE * padded_radius
	)
	var radius_squared: float = padded_radius * padded_radius
	for cell_y: int in range(cell_minimum.y, cell_maximum.y + 1):
		for cell_x: int in range(cell_minimum.x, cell_maximum.x + 1):
			var bucket_value: Variant = _neighbor_grid.get(Vector2i(cell_x, cell_y), [])
			if not (bucket_value is Array):
				continue
			if _performance_tracker != null:
				scanned_candidate_count += bucket_value.size()
			for unit_value: Variant in bucket_value:
				var unit := unit_value as PlanBUnit
				if (
					unit == null
					or _units_by_id.get(unit.unit_id) != unit
					or unit.position.distance_squared_to(scene_local_position) > radius_squared
				):
					continue
				nearby_units.append(unit)
	nearby_units.sort_custom(_unit_id_is_before)
	if _performance_tracker != null:
		_record_tracker_neighbor_query(
			Time.get_ticks_usec() - tracker_start_usec, scanned_candidate_count, nearby_units.size()
		)
	return nearby_units


## Neighborhood 查询在物理步内先累计，避免每次查询都跨 Node 调用 Tracker。
func _record_tracker_neighbor_query(elapsed_usec: int, candidate_count: int, result_count: int) -> void:
	_tracker_neighbor_query_count += 1
	_tracker_neighbor_total_usec += maxi(elapsed_usec, 0)
	_tracker_neighbor_max_usec = maxi(_tracker_neighbor_max_usec, elapsed_usec)
	_tracker_neighbor_candidate_total += maxi(candidate_count, 0)
	_tracker_neighbor_candidate_max = maxi(_tracker_neighbor_candidate_max, candidate_count)
	_tracker_neighbor_result_total += maxi(result_count, 0)
	_tracker_neighbor_result_max = maxi(_tracker_neighbor_result_max, result_count)


## 目标方向按棋子ID分相错峰；每个棋子独立遵守约10Hz更新上限。
func _target_decision_phase(unit_id: int) -> float:
	var interval: float = maxf(target_decision_refresh_seconds, 0.01)
	return interval * float(posmod(unit_id - 1, 6)) / 6.0


## 物理帧沿用缓存方向；每个单位到达错峰时隙后才重新查询共享邻域网格。
func _update_cached_steering(unit: PlanBUnit, delta: float) -> void:
	var cached_value: Variant = _steering_cache_by_unit_id.get(unit.unit_id, {})
	var cached: Dictionary = cached_value if cached_value is Dictionary else {}
	if cached.is_empty():
		cached = {
			"direction": unit.wander_direction,
			"intent": &"wander",
			"refresh_remaining_seconds": _target_decision_phase(unit.unit_id),
		}
	var interval: float = maxf(target_decision_refresh_seconds, 0.01)
	var refresh_remaining: float = float(cached.get("refresh_remaining_seconds", 0.0)) - delta
	if refresh_remaining <= 0.0:
		var nearby_units: Array[PlanBUnit] = []
		# 中立棋子只会游荡；略过永远不会被它们使用的邻域扫描。
		if unit.team != NEUTRAL_TEAM:
			var search_radius: float = maxf(detection_radius, ally_detection_radius)
			nearby_units = _get_neighbor_units(unit.position, search_radius)
		var decision: Dictionary = _get_steering(unit, nearby_units)
		cached["direction"] = decision.get("direction", unit.wander_direction)
		cached["intent"] = decision.get("intent", &"wander")
		if _performance_tracker != null:
			_tracker_steering_decisions_this_tick += 1
		refresh_remaining += interval
		if refresh_remaining <= 0.0:
			refresh_remaining = interval
	cached["refresh_remaining_seconds"] = refresh_remaining
	_steering_cache_by_unit_id[unit.unit_id] = cached


## 每个物理步发布按ID排序的上一/当前位置；新生棋子首帧以相同位置起步。
func _emit_physics_positions() -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	var unit_ids := PackedInt32Array()
	var previous_positions := PackedVector2Array()
	var current_positions := PackedVector2Array()
	for unit: PlanBUnit in _get_sorted_units():
		var current_position: Vector2 = unit.global_position
		var previous_value: Variant = _previous_physics_positions_by_unit_id.get(unit.unit_id, current_position)
		var previous_position: Vector2 = previous_value if previous_value is Vector2 else current_position
		unit_ids.append(unit.unit_id)
		previous_positions.append(previous_position)
		current_positions.append(current_position)
		_previous_physics_positions_by_unit_id[unit.unit_id] = current_position
	if _performance_tracker != null:
		_performance_tracker.call(
			"record_section",
			PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_POSITION_EXPORT,
			Time.get_ticks_usec() - tracker_start_usec,
			unit_ids.size()
		)
		tracker_start_usec = Time.get_ticks_usec()
	unit_physics_positions_updated.emit(unit_ids, previous_positions, current_positions)
	if _performance_tracker != null:
		_performance_tracker.call(
			"record_section",
			PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_POSITION_SIGNAL,
			Time.get_ticks_usec() - tracker_start_usec,
			unit_ids.size()
		)


func _neighbor_grid_cell_for_position(scene_local_position: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(scene_local_position.x / _neighbor_grid_cell_size)),
		int(floor(scene_local_position.y / _neighbor_grid_cell_size))
	)


func _unit_id_is_before(first_unit: PlanBUnit, second_unit: PlanBUnit) -> bool:
	return first_unit.unit_id < second_unit.unit_id


## 按成员集合重叠延续 group_id，团体拆分或合并时不依赖数组临时索引。
func _refresh_word_groups() -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	var previous_groups: Dictionary = _word_groups_by_id
	var previous_group_by_unit: Dictionary = {}
	for group_id_value: Variant in previous_groups.keys():
		var previous_group: Dictionary = previous_groups[group_id_value]
		for member_value: Variant in previous_group.get("member_ids", []):
			previous_group_by_unit[int(member_value)] = int(group_id_value)

	var components: Array[Dictionary] = _build_word_group_components(previous_group_by_unit)
	var assigned_ids: Dictionary = _assign_word_group_ids(components)
	var next_groups: Dictionary = {}
	var member_count: int = 0
	for component_index: int in components.size():
		var component: Dictionary = components[component_index]
		var group_id: int = int(assigned_ids[component_index])
		var member_ids: Array = component.get("member_ids", [])
		if _performance_tracker != null:
			member_count += member_ids.size()
		next_groups[group_id] = {
			"group_id": group_id,
			"team": str(component.get("team", "")),
			"word_id": str(component.get("word_id", "")),
			"word_order": int(component.get("word_order", 0)),
			"member_ids": member_ids.duplicate(),
			"word_snapshot": (component.get("word_snapshot", {}) as Dictionary).duplicate(true),
		}
	var topology_changed: bool = not _word_groups_have_same_topology(previous_groups, next_groups)
	_word_groups_by_id = next_groups
	_group_refresh_remaining_seconds = group_topology_refresh_seconds
	if _performance_tracker != null:
		_performance_tracker.call("set_group_snapshot", next_groups.size(), member_count)
		_performance_tracker.call(
			"record_section",
			PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_GROUP_REFRESH,
			Time.get_ticks_usec() - tracker_start_usec,
			next_groups.size(),
			member_count
		)
	if topology_changed:
		var snapshot_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
		word_groups_changed.emit(get_word_groups())
		if _performance_tracker != null:
			_performance_tracker.call(
				"record_section",
				PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_GROUP_SNAPSHOT_EMIT,
				Time.get_ticks_usec() - snapshot_start_usec,
				next_groups.size(),
				member_count
			)


## 碰撞半径变大时，提高结群查询阈值，保证接触边缘的棋子可进入同一组。
func _effective_word_group_join_distance() -> float:
	# 相邻碰撞圆至少以直径距离接触；群组入组范围不能比接触阈值更小。
	return maxf(word_group_join_distance, unit_collision_radius * 2.0)


func _effective_word_group_leave_distance() -> float:
	# 保留迟滞；大碰撞半径下比入组距离多留16px，避免贴边抖动。
	var join_distance: float = _effective_word_group_join_distance()
	var hysteresis_margin: float = maxf(unit_collision_radius * 0.25, 8.0)
	return maxf(word_group_leave_distance, join_distance + hysteresis_margin)


## 同队同词的邻近单位形成连通组件，并保留入组/离组迟滞。
func _build_word_group_components(previous_group_by_unit: Dictionary) -> Array[Dictionary]:
	var components: Array[Dictionary] = []
	var visited: Dictionary = {}
	var join_distance: float = _effective_word_group_join_distance()
	var leave_distance: float = _effective_word_group_leave_distance()
	for seed_unit: PlanBUnit in _get_sorted_units():
		if seed_unit.team == NEUTRAL_TEAM or not seed_unit.has_word() or visited.has(seed_unit.unit_id):
			continue
		var seed_word_id: StringName = seed_unit.get_word_id()
		var member_ids: Array[int] = [seed_unit.unit_id]
		var member_positions: Array[Vector2] = [seed_unit.position]
		var queue: Array[PlanBUnit] = [seed_unit]
		var queue_index: int = 0
		visited[seed_unit.unit_id] = true
		while queue_index < queue.size():
			var current_unit: PlanBUnit = queue[queue_index]
			queue_index += 1
			var current_old_group_id: int = int(previous_group_by_unit.get(current_unit.unit_id, -1))
			for neighbor_unit: PlanBUnit in _get_neighbor_units(current_unit.position, leave_distance):
				if visited.has(neighbor_unit.unit_id):
					continue
				if neighbor_unit.team != seed_unit.team or neighbor_unit.get_word_id() != seed_word_id:
					continue
				var neighbor_old_group_id: int = int(previous_group_by_unit.get(neighbor_unit.unit_id, -1))
				var link_distance: float = join_distance
				if current_old_group_id >= 0 and current_old_group_id == neighbor_old_group_id:
					link_distance = leave_distance
				if current_unit.position.distance_squared_to(neighbor_unit.position) > link_distance * link_distance:
					continue
				if not _can_add_word_group_member(member_positions, neighbor_unit.position):
					continue
				visited[neighbor_unit.unit_id] = true
				member_ids.append(neighbor_unit.unit_id)
				member_positions.append(neighbor_unit.position)
				queue.append(neighbor_unit)

		member_ids.sort()
		var old_group_overlaps: Dictionary = {}
		for member_id: int in member_ids:
			var old_group_id: int = int(previous_group_by_unit.get(member_id, -1))
			if old_group_id >= 0:
				old_group_overlaps[old_group_id] = int(old_group_overlaps.get(old_group_id, 0)) + 1
		components.append({
			"team": str(seed_unit.team),
			"word_id": str(seed_word_id),
			"word_order": seed_unit.word_order,
			"member_ids": member_ids,
			"word_snapshot": seed_unit.get_word_snapshot(),
			"old_group_overlaps": old_group_overlaps,
		})
	return components


## 拒绝会让任一成员距新几何中心超过180px的新增连通边，避免长链串场。
func _can_add_word_group_member(member_positions: Array[Vector2], candidate_position: Vector2) -> bool:
	var proposed_center: Vector2 = candidate_position
	for member_position: Vector2 in member_positions:
		proposed_center += member_position
	proposed_center /= float(member_positions.size() + 1)
	if candidate_position.distance_to(proposed_center) > word_group_max_center_radius:
		return false
	for member_position: Vector2 in member_positions:
		if member_position.distance_to(proposed_center) > word_group_max_center_radius:
			return false
	return true


## 最大成员重叠的后继组优先复用旧ID；其余组取得新的战斗内ID。
func _assign_word_group_ids(components: Array[Dictionary]) -> Dictionary:
	var assigned_ids: Dictionary = {}
	var claimed_old_group_ids: Dictionary = {}
	for assignment_index: int in components.size():
		var best_component_index: int = -1
		var best_old_group_id: int = -1
		var best_overlap_count: int = 0
		var best_first_member_id: int = 2147483647
		for component_index: int in components.size():
			if assigned_ids.has(component_index):
				continue
			var component: Dictionary = components[component_index]
			var member_ids: Array = component.get("member_ids", [])
			var first_member_id: int = int(member_ids[0]) if not member_ids.is_empty() else 2147483647
			var overlaps: Dictionary = component.get("old_group_overlaps", {})
			for old_group_value: Variant in overlaps.keys():
				var old_group_id: int = int(old_group_value)
				if claimed_old_group_ids.has(old_group_id):
					continue
				var overlap_count: int = int(overlaps[old_group_value])
				if (
					overlap_count > best_overlap_count
					or (overlap_count == best_overlap_count and overlap_count > 0 and first_member_id < best_first_member_id)
					or (overlap_count == best_overlap_count and overlap_count > 0 and first_member_id == best_first_member_id and old_group_id < best_old_group_id)
				):
					best_component_index = component_index
					best_old_group_id = old_group_id
					best_overlap_count = overlap_count
					best_first_member_id = first_member_id
		if best_component_index < 0 or best_overlap_count <= 0:
			break
		assigned_ids[best_component_index] = best_old_group_id
		claimed_old_group_ids[best_old_group_id] = true

	for component_index: int in components.size():
		if assigned_ids.has(component_index):
			continue
		assigned_ids[component_index] = _next_word_group_id
		_next_word_group_id += 1
	return assigned_ids


func _word_groups_have_same_topology(previous_groups: Dictionary, next_groups: Dictionary) -> bool:
	if previous_groups.size() != next_groups.size():
		return false
	for group_id_value: Variant in previous_groups.keys():
		var group_id: int = int(group_id_value)
		if not next_groups.has(group_id):
			return false
		var previous_group: Dictionary = previous_groups[group_id]
		var next_group: Dictionary = next_groups[group_id]
		if (
			str(previous_group.get("team", "")) != str(next_group.get("team", ""))
			or str(previous_group.get("word_id", "")) != str(next_group.get("word_id", ""))
			or previous_group.get("member_ids", []) != next_group.get("member_ids", [])
		):
			return false
	return true


## 让 A / D 直接取得仍属中立的稳定 ID 列表，结果按 unit_id 排序。
func get_neutral_unit_ids() -> Array[int]:
	var neutral_ids: Array[int] = []
	for unit_id: int in _get_sorted_unit_ids():
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		if unit != null and unit.team == NEUTRAL_TEAM:
			neutral_ids.append(unit_id)
	return neutral_ids


## 用实际全局场景坐标命中最近的中立棋子，未命中返回 -1。
func get_neutral_unit_at(scene_position: Vector2) -> int:
	var selected_id: int = -1
	var nearest_distance: float = unit_collision_radius
	for unit_id: int in get_neutral_unit_ids():
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		if unit == null:
			continue
		var distance: float = unit.global_position.distance_to(scene_position)
		if distance <= nearest_distance:
			selected_id = unit_id
			nearest_distance = distance
	return selected_id


func is_running() -> bool:
	return _is_running


## A 仅在显式 opt-in 时注入观察器；默认模拟逻辑不创建 Tracker 节点。
func set_performance_tracker(tracker: Node) -> void:
	_performance_tracker = tracker if is_instance_valid(tracker) else null


## 每个物理帧先裁决上一轮实际碰撞，再推进移动、寿命和补人。
func _physics_process(delta: float) -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	if _performance_tracker != null:
		_tracker_neighbor_query_count = 0
		_tracker_neighbor_total_usec = 0
		_tracker_neighbor_max_usec = 0
		_tracker_neighbor_candidate_total = 0
		_tracker_neighbor_candidate_max = 0
		_tracker_neighbor_result_total = 0
		_tracker_neighbor_result_max = 0
	_resolve_pending_contacts()
	_advance_units(delta)
	_despawn_expired_units()
	_update_neutral_replenishment(delta)
	_emit_physics_positions()
	if _performance_tracker != null:
		_performance_tracker.call(
			"record_section",
			PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_SIMULATION_TICK,
			Time.get_ticks_usec() - tracker_start_usec,
			_units_by_id.size()
		)
		if _tracker_neighbor_query_count > 0:
			_performance_tracker.call(
				"record_aggregate",
				PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_NEIGHBOR_QUERY,
				_tracker_neighbor_query_count,
				_tracker_neighbor_total_usec,
				_tracker_neighbor_max_usec,
				_tracker_neighbor_candidate_total,
				_tracker_neighbor_result_total,
				_tracker_neighbor_candidate_max,
				_tracker_neighbor_result_max
			)


## 收集 Area2D 实际碰撞，双方的 entered 信号折叠为同一个无向棋子对。
func _on_unit_area_entered(other_area: Area2D, source_unit_id: int) -> void:
	var other_unit := other_area as PlanBUnit
	if other_unit == null or other_unit.unit_id == source_unit_id:
		return
	var pair := Vector2i(mini(source_unit_id, other_unit.unit_id), maxi(source_unit_id, other_unit.unit_id))
	if _pending_contact_lookup.has(pair):
		return
	_pending_contact_lookup[pair] = true
	_pending_contact_pairs.append(pair)


## 先按 ID 排序接触，再裁决，保证固定 seed 回放的抽样顺序稳定。
func _resolve_pending_contacts() -> void:
	if _pending_contact_pairs.is_empty():
		return
	var pairs: Array[Vector2i] = _pending_contact_pairs.duplicate()
	_pending_contact_pairs.clear()
	_pending_contact_lookup.clear()
	pairs.sort_custom(_pair_is_before)
	for pair: Vector2i in pairs:
		var first_unit := _units_by_id.get(pair.x) as PlanBUnit
		var second_unit := _units_by_id.get(pair.y) as PlanBUnit
		if first_unit == null or second_unit == null:
			continue
		_resolve_contact(first_unit, second_unit)


## 用棋子 ID 对接触对排序，避免物理 signal 的顺序影响随机判定结果。
func _pair_is_before(first_pair: Vector2i, second_pair: Vector2i) -> bool:
	if first_pair.x == second_pair.x:
		return first_pair.y < second_pair.y
	return first_pair.x < second_pair.x


## 冷却通过后先弹开，再按阵营、属性和注入克制表裁决一次。
func _resolve_contact(first_unit: PlanBUnit, second_unit: PlanBUnit) -> void:
	if first_unit.contact_cooldown_remaining > 0.0 or second_unit.contact_cooldown_remaining > 0.0:
		return
	first_unit.contact_cooldown_remaining = collision_cooldown_seconds
	second_unit.contact_cooldown_remaining = collision_cooldown_seconds
	var strong_contact: bool = (
		first_unit.team != second_unit.team
		or first_unit.team == NEUTRAL_TEAM
	)
	_separate_and_recoil(first_unit, second_unit, strong_contact)

	if first_unit.team == second_unit.team:
		if first_unit.team == NEUTRAL_TEAM:
			contact_resolved.emit(first_unit.unit_id, second_unit.unit_id, &"neutral_bounce")
			return
		_relay_newer_word(first_unit, second_unit)
		contact_resolved.emit(first_unit.unit_id, second_unit.unit_id, &"same_team_bounce")
		return

	if first_unit.team == NEUTRAL_TEAM:
		_attempt_neutral_conversion(second_unit, first_unit)
		return
	if second_unit.team == NEUTRAL_TEAM:
		_attempt_neutral_conversion(first_unit, second_unit)
		return

	var first_counters_second: bool = _counters(first_unit, second_unit)
	var second_counters_first: bool = _counters(second_unit, first_unit)
	if first_unit.get_battle_type() == second_unit.get_battle_type():
		contact_resolved.emit(first_unit.unit_id, second_unit.unit_id, &"same_type_bounce")
		return
	if first_counters_second == second_counters_first:
		contact_resolved.emit(first_unit.unit_id, second_unit.unit_id, &"no_counter_bounce")
		return
	var infecting_unit: PlanBUnit = first_unit if first_counters_second else second_unit
	var receiving_unit: PlanBUnit = second_unit if first_counters_second else first_unit
	_attempt_conversion(infecting_unit, receiving_unit)


## 中立人群之间只发生物理弹开；阵营棋子可用当前话语强度尝试感染路人。
func _attempt_neutral_conversion(infecting_unit: PlanBUnit, neutral_unit: PlanBUnit) -> void:
	if infecting_unit.team == NEUTRAL_TEAM or not infecting_unit.has_word():
		contact_resolved.emit(infecting_unit.unit_id, neutral_unit.unit_id, &"neutral_bounce")
		return
	_attempt_conversion(infecting_unit, neutral_unit)


## strength 只作为合法感染的成功率，不参与移动、寿命、PK 或改口裁决。
func _attempt_conversion(infecting_unit: PlanBUnit, receiving_unit: PlanBUnit) -> void:
	if _try_reflect_legal_attack(infecting_unit, receiving_unit):
		return
	var chance: float = float(INFECTION_CHANCES_BY_STRENGTH.get(infecting_unit.get_strength(), 0.0))
	if chance > 0.0 and _rng.randf() < chance:
		var infecting_team: StringName = infecting_unit.team
		var infecting_word_order: int = infecting_unit.word_order
		receiving_unit.apply_word_snapshot(
			infecting_team,
			infecting_unit.get_word_snapshot(),
			infecting_word_order
		)
		unit_changed.emit(receiving_unit.unit_id, &"convert")
		if infecting_team == PLAYER_TEAM:
			_record_player_batch_infection(infecting_word_order)
		contact_resolved.emit(infecting_unit.unit_id, receiving_unit.unit_id, &"converted")
		return
	contact_resolved.emit(infecting_unit.unit_id, receiving_unit.unit_id, &"infection_failed")


## 只记录玩家发言批次产生的成功转换；同一批达到阈值后最多奖励一次。
func _record_player_batch_infection(word_order_value: int) -> void:
	if not _player_batch_infection_counts.has(word_order_value):
		return
	var success_count: int = int(_player_batch_infection_counts[word_order_value]) + 1
	_player_batch_infection_counts[word_order_value] = success_count
	if success_count < BATCH_TRAIT_INFECTION_THRESHOLD or bool(_player_batch_trait_triggered.get(word_order_value, false)):
		return
	_player_batch_trait_triggered[word_order_value] = true
	_award_player_batch_trait(word_order_value)


## 第五次成功感染时，在仍存活的同批玩家棋子上应用一次分裂或反弹。
func _award_player_batch_trait(word_order_value: int) -> void:
	var candidates: Array[PlanBUnit] = []
	for unit: PlanBUnit in _get_sorted_units():
		if unit.team == PLAYER_TEAM and unit.word_order == word_order_value and unit.combat_trait_uses <= 0:
			candidates.append(unit)
	if candidates.is_empty():
		return
	var recipient: PlanBUnit = candidates[_rng.randi_range(0, candidates.size() - 1)]
	var trait_name: StringName = &"split" if _rng.randf() < 0.5 else &"reflect"
	if trait_name == &"split":
		if _units_by_id.size() >= maximum_population:
			trait_name = &"reflect"
		else:
			recipient.set_combat_trait(&"split", 1)
			var child := _spawn_unit(
				recipient.team,
				recipient.get_word_snapshot(),
				recipient.word_order,
				_get_split_child_position(recipient, 0, 1)
			)
			if child != null:
				recipient.consume_combat_trait()
				unit_changed.emit(recipient.unit_id, &"split")
				word_batch_trait_awarded.emit(word_order_value, recipient.unit_id, &"split")
				return
			recipient.set_combat_trait(&"", 0)
			trait_name = &"reflect"
	if trait_name == &"reflect":
		recipient.set_combat_trait(&"reflect", 1)
		unit_changed.emit(recipient.unit_id, &"reflect")
		word_batch_trait_awarded.emit(word_order_value, recipient.unit_id, &"reflect")


## 玩家与对手阵营的reflect都只抵挡已通过克制合法性检查的感染。
func _try_reflect_legal_attack(infecting_unit: PlanBUnit, receiving_unit: PlanBUnit) -> bool:
	var is_opponent_attacking_player: bool = infecting_unit.team == OPPONENT_TEAM and receiving_unit.team == PLAYER_TEAM
	var is_player_attacking_opponent: bool = infecting_unit.team == PLAYER_TEAM and receiving_unit.team == OPPONENT_TEAM
	if not is_opponent_attacking_player and not is_player_attacking_opponent:
		return false
	if receiving_unit.combat_trait != &"reflect" or receiving_unit.combat_trait_uses <= 0:
		return false
	if receiving_unit.consume_combat_trait() != &"reflect":
		return false
	var recoil_direction: Vector2 = (infecting_unit.position - receiving_unit.position).normalized()
	if recoil_direction.length_squared() <= 0.0001:
		recoil_direction = Vector2.RIGHT
	_begin_contact_recoil(infecting_unit, recoil_direction)
	unit_changed.emit(receiving_unit.unit_id, &"reflect")
	contact_resolved.emit(infecting_unit.unit_id, receiving_unit.unit_id, &"reflected")
	return true


## 同阵营接触必定由新 word_order 向旧棋子传播完整快照，人数和阵营保持原值。
func _relay_newer_word(first_unit: PlanBUnit, second_unit: PlanBUnit) -> void:
	var source_unit: PlanBUnit = first_unit if first_unit.word_order > second_unit.word_order else second_unit
	var receiving_unit: PlanBUnit = second_unit if source_unit == first_unit else first_unit
	if source_unit.word_order <= receiving_unit.word_order or not source_unit.has_word():
		return
	receiving_unit.apply_word_snapshot(source_unit.team, source_unit.get_word_snapshot(), source_unit.word_order)
	unit_changed.emit(receiving_unit.unit_id, &"relay")


## 分开真实重叠；敌我和中立接触保留短暂击退，同盟只做轻量软分离。
func _separate_and_recoil(first_unit: PlanBUnit, second_unit: PlanBUnit, strong_contact: bool) -> void:
	var offset: Vector2 = first_unit.position - second_unit.position
	var minimum_distance: float = unit_collision_radius * 2.0
	var current_distance: float = offset.length()
	var normal: Vector2 = offset.normalized() if current_distance > 0.001 else Vector2.from_angle(_rng.randf_range(0.0, TAU))
	if current_distance < minimum_distance:
		var separation: float = minimum_distance - current_distance + 0.5
		first_unit.position += normal * separation * 0.5
		second_unit.position -= normal * separation * 0.5
		_neighbor_grid_positions_adjusted = true
	if strong_contact:
		_begin_contact_recoil(first_unit, normal)
		_begin_contact_recoil(second_unit, -normal)
	else:
		# 同阵营贴碰只推开少量，避免团体每次接触都被强烈弹散。
		first_unit.velocity += normal * contact_recoil_speed * 0.1
		second_unit.velocity -= normal * contact_recoil_speed * 0.1


## 接触反冲有明确短时生命周期；期间保留退开速度，目标更新不能覆盖它。
func _begin_contact_recoil(unit: PlanBUnit, direction: Vector2) -> void:
	var recoil_direction: Vector2 = direction.normalized()
	if recoil_direction.length_squared() <= 0.0001:
		recoil_direction = Vector2.RIGHT
	var recoil_speed: float = minf(maximum_speed, maxf(contact_recoil_speed * 2.0, unit.base_speed))
	unit.contact_recoil_velocity = recoil_direction * recoil_speed
	unit.contact_recoil_remaining_seconds = contact_recoil_duration_seconds


## 游荡是默认意图；可感染目标进入追逐，可感染当前棋子的敌人优先触发逃跑。
func _advance_units(delta: float) -> void:
	var units: Array[PlanBUnit] = _get_sorted_units()
	_neighbor_grid_elapsed_seconds += delta
	if _neighbor_grid_dirty or _neighbor_grid_elapsed_seconds >= maxf(neighbor_grid_refresh_seconds, 0.01):
		_rebuild_neighbor_grid(units)
		_neighbor_grid_elapsed_seconds = 0.0
	_group_refresh_remaining_seconds = maxf(_group_refresh_remaining_seconds - delta, 0.0)
	if _group_refresh_remaining_seconds <= 0.0:
		_refresh_word_groups()
	for unit: PlanBUnit in units:
		unit.age_seconds += delta
		unit.contact_cooldown_remaining = maxf(unit.contact_cooldown_remaining - delta, 0.0)
		unit.wander_change_remaining -= delta
		if unit.wander_change_remaining <= 0.0:
			unit.wander_direction = Vector2.from_angle(_rng.randf_range(0.0, TAU))
			unit.wander_change_remaining = _rng.randf_range(1.2, 3.1)

	var steering_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	if _performance_tracker != null:
		_tracker_steering_decisions_this_tick = 0
	var steering_by_index: Array[Dictionary] = []
	for unit: PlanBUnit in units:
		_update_cached_steering(unit, delta)
		var cached_value: Variant = _steering_cache_by_unit_id.get(unit.unit_id, {})
		var cached: Dictionary = cached_value if cached_value is Dictionary else {}
		steering_by_index.append(cached)
	if _performance_tracker != null:
		_performance_tracker.call(
			"record_section",
			PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_STEERING_BATCH,
			Time.get_ticks_usec() - steering_start_usec,
			units.size(),
			_tracker_steering_decisions_this_tick
		)
	for unit_index: int in units.size():
		var unit: PlanBUnit = units[unit_index]
		if unit.contact_recoil_remaining_seconds > 0.0:
			unit.spawn_burst_remaining_seconds = maxf(unit.spawn_burst_remaining_seconds - delta, 0.0)
			unit.velocity = unit.contact_recoil_velocity
			unit.position += unit.velocity * delta
			_bounce_from_play_area(unit)
			unit.contact_recoil_velocity = unit.velocity
			unit.contact_recoil_remaining_seconds = maxf(unit.contact_recoil_remaining_seconds - delta, 0.0)
			if unit.contact_recoil_remaining_seconds == 0.0:
				unit.contact_recoil_velocity = Vector2.ZERO
				var cached_value: Variant = _steering_cache_by_unit_id.get(unit.unit_id, {})
				if cached_value is Dictionary:
					var cached: Dictionary = cached_value
					cached["refresh_remaining_seconds"] = 0.0
					_steering_cache_by_unit_id[unit.unit_id] = cached
			continue
		if unit.spawn_burst_remaining_seconds > 0.0:
			unit.velocity = unit.spawn_burst_direction * unit.spawn_burst_speed
			unit.position += unit.velocity * delta
			unit.spawn_burst_remaining_seconds = maxf(unit.spawn_burst_remaining_seconds - delta, 0.0)
			_bounce_from_play_area(unit)
			continue
		var steering: Dictionary = steering_by_index[unit_index]
		var direction: Vector2 = steering.get("direction", unit.wander_direction)
		var intent: StringName = steering.get("intent", &"wander")
		unit.motion_intent = intent
		var speed_scale: float = 1.0
		if intent == &"chase":
			speed_scale = chase_speed_scale
		elif intent == &"flee":
			speed_scale = flee_speed_scale
		var applied_speed: float = minf(unit.base_speed * speed_scale, maximum_speed)
		unit.velocity = direction.normalized() * applied_speed if direction.length_squared() > 0.0001 else Vector2.ZERO
		unit.position += unit.velocity * delta
		_bounce_from_play_area(unit)


func _get_steering(unit: PlanBUnit, nearby_units: Array[PlanBUnit]) -> Dictionary:
	if unit.team == NEUTRAL_TEAM:
		return {"direction": unit.wander_direction, "intent": &"wander"}
	var effective_ally_ideal_spacing: float = maxf(ally_ideal_spacing, unit_collision_radius * 2.0)
	var nearest_chase_direction := Vector2.ZERO
	var nearest_threat_direction := Vector2.ZERO
	var same_word_cohesion := Vector2.ZERO
	var other_word_cohesion := Vector2.ZERO
	var separation_direction := Vector2.ZERO
	var same_word_count: int = 0
	var other_word_count: int = 0
	var detection_radius_squared: float = detection_radius * detection_radius
	var nearest_chase_distance_squared: float = detection_radius_squared
	var nearest_threat_distance_squared: float = detection_radius_squared
	for other_unit: PlanBUnit in nearby_units:
		if other_unit == unit:
			continue
		var offset: Vector2 = other_unit.position - unit.position
		var distance_squared: float = offset.length_squared()
		if distance_squared <= 0.000001:
			continue
		if other_unit.team == unit.team:
			if distance_squared <= ally_detection_radius * ally_detection_radius:
				var toward_ally: Vector2 = offset.normalized()
				if other_unit.get_word_id() == unit.get_word_id():
					same_word_cohesion += toward_ally
					same_word_count += 1
				else:
					other_word_cohesion += toward_ally
					other_word_count += 1
				var distance: float = sqrt(distance_squared)
				if distance < effective_ally_ideal_spacing:
					separation_direction -= toward_ally * (
						(effective_ally_ideal_spacing - distance) / effective_ally_ideal_spacing
					)
			continue
		if distance_squared > detection_radius_squared:
			continue
		if other_unit.team == NEUTRAL_TEAM:
			if distance_squared < nearest_chase_distance_squared:
				nearest_chase_distance_squared = distance_squared
				nearest_chase_direction = offset.normalized()
		elif other_unit.team != unit.team:
			if _counters(other_unit, unit) and distance_squared < nearest_threat_distance_squared:
				nearest_threat_distance_squared = distance_squared
				nearest_threat_direction = -offset.normalized()
			elif _counters(unit, other_unit) and distance_squared < nearest_chase_distance_squared:
				nearest_chase_distance_squared = distance_squared
				nearest_chase_direction = offset.normalized()

	if nearest_threat_direction != Vector2.ZERO:
		var flee_direction: Vector2 = (
			nearest_threat_direction * flee_weight
			+ unit.wander_direction * wandering_weight
			+ separation_direction.normalized() * ally_separation_weight * 0.35
		)
		return {"direction": flee_direction.normalized(), "intent": &"flee"}
	if nearest_chase_direction != Vector2.ZERO:
		var cohesion_direction: Vector2 = _get_cohesion_direction(
			same_word_cohesion, same_word_count, other_word_cohesion, other_word_count
		)
		var chase_direction: Vector2 = (
			nearest_chase_direction * chase_weight
			+ unit.wander_direction * wandering_weight
			+ cohesion_direction * ally_attraction_weight * 0.25
			+ separation_direction.normalized() * ally_separation_weight * 0.35
		)
		return {"direction": chase_direction.normalized(), "intent": &"chase"}
	if same_word_count > 0 or other_word_count > 0:
		var attraction_weight: float = ally_attraction_weight if same_word_count > 0 else ally_attraction_weight * 0.5
		var cohesion_direction: Vector2 = _get_cohesion_direction(
			same_word_cohesion, same_word_count, other_word_cohesion, other_word_count
		)
		var group_direction: Vector2 = (
			cohesion_direction * attraction_weight
			+ separation_direction.normalized() * ally_separation_weight
			+ unit.wander_direction * wandering_weight
		)
		return {"direction": group_direction.normalized(), "intent": &"group"}
	return {"direction": unit.wander_direction, "intent": &"wander"}


## 同话小队凝聚优先，异话友军保持较弱吸引以保留真实接触传话。
func _get_cohesion_direction(
	same_word_cohesion: Vector2,
	same_word_count: int,
	other_word_cohesion: Vector2,
	other_word_count: int
) -> Vector2:
	if same_word_count > 0:
		return same_word_cohesion.normalized()
	if other_word_count > 0:
		return other_word_cohesion.normalized()
	return Vector2.ZERO


## 以棋子碰撞半径约束场景边缘，速度法线分量反射回战场。
func _bounce_from_play_area(unit: PlanBUnit) -> void:
	var minimum_x: float = play_area.position.x + unit_collision_radius
	var maximum_x: float = play_area.end.x - unit_collision_radius
	var minimum_y: float = play_area.position.y + unit_collision_radius
	var maximum_y: float = play_area.end.y - unit_collision_radius
	var steering_reflected: bool = false
	var cached_value: Variant = _steering_cache_by_unit_id.get(unit.unit_id, {})
	var cached: Dictionary = cached_value if cached_value is Dictionary else {}
	var cached_direction: Vector2 = cached.get("direction", unit.wander_direction)
	if unit.position.x < minimum_x:
		unit.position.x = minimum_x
		unit.velocity.x = absf(unit.velocity.x)
		unit.wander_direction.x = absf(unit.wander_direction.x)
		cached_direction.x = absf(cached_direction.x)
		if absf(cached_direction.x) <= 0.0001:
			cached_direction.x = absf(unit.velocity.x)
		steering_reflected = true
	elif unit.position.x > maximum_x:
		unit.position.x = maximum_x
		unit.velocity.x = -absf(unit.velocity.x)
		unit.wander_direction.x = -absf(unit.wander_direction.x)
		cached_direction.x = -absf(cached_direction.x)
		if absf(cached_direction.x) <= 0.0001:
			cached_direction.x = -absf(unit.velocity.x)
		steering_reflected = true
	if unit.position.y < minimum_y:
		unit.position.y = minimum_y
		unit.velocity.y = absf(unit.velocity.y)
		unit.wander_direction.y = absf(unit.wander_direction.y)
		cached_direction.y = absf(cached_direction.y)
		if absf(cached_direction.y) <= 0.0001:
			cached_direction.y = absf(unit.velocity.y)
		steering_reflected = true
	elif unit.position.y > maximum_y:
		unit.position.y = maximum_y
		unit.velocity.y = -absf(unit.velocity.y)
		unit.wander_direction.y = -absf(unit.wander_direction.y)
		cached_direction.y = -absf(cached_direction.y)
		if absf(cached_direction.y) <= 0.0001:
			cached_direction.y = -absf(unit.velocity.y)
		steering_reflected = true
	if steering_reflected and not cached.is_empty():
		cached["direction"] = cached_direction.normalized()
		_steering_cache_by_unit_id[unit.unit_id] = cached


## 棋子只会因真实寿命到期离场；替补总以新中立 ID 入场，不重置既有阵营。
func _despawn_expired_units() -> void:
	var expired_ids: Array[int] = []
	for unit_id: int in _get_sorted_unit_ids():
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		if unit != null and unit.age_seconds >= unit.lifespan_seconds:
			expired_ids.append(unit_id)
	for unit_id: int in expired_ids:
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		_units_by_id.erase(unit_id)
		_steering_cache_by_unit_id.erase(unit_id)
		_previous_physics_positions_by_unit_id.erase(unit_id)
		if is_instance_valid(unit):
			remove_child(unit)
			unit.queue_free()
		unit_despawned.emit(unit_id)
	if not expired_ids.is_empty():
		_neighbor_grid_dirty = true


## 以随机间隔补充中立观众；到达批次保留线后暂停计时，留出完整8颗发表空间。
func _update_neutral_replenishment(delta: float) -> void:
	var neutral_spawn_population_limit: int = maxi(
		maximum_population - neutral_spawn_batch_reserve,
		0
	)
	if _units_by_id.size() >= neutral_spawn_population_limit:
		# 容量被批次占用时冻结剩余计时；空出空间后接着完成当前周期。
		return
	if _next_neutral_spawn_interval_seconds <= 0.0:
		_next_neutral_spawn_interval_seconds = _roll_neutral_spawn_interval_seconds()
	_spawn_elapsed_seconds += delta
	if _spawn_elapsed_seconds < _next_neutral_spawn_interval_seconds:
		return
	_spawn_elapsed_seconds = 0.0
	_spawn_unit(NEUTRAL_TEAM, {}, 0, _random_spawn_position())
	_next_neutral_spawn_interval_seconds = _roll_neutral_spawn_interval_seconds()


## 初始化独立 Area2D 和运行快照后入场；同一场地的碰撞形状资源互不共享。
## 校验棋盘全局点击位置；边线可点，具体出生点会向内留出碰撞半径。
func _is_scene_position_in_play_area(scene_position: Vector2) -> bool:
	var local_position: Vector2 = to_local(scene_position)
	return (
		local_position.x >= play_area.position.x
		and local_position.x <= play_area.end.x
		and local_position.y >= play_area.position.y
		and local_position.y <= play_area.end.y
	)


## 在落点周围按strength数量铺开初始位置，避免同一批出生时彼此重叠。
func _get_word_batch_spawn_positions(center: Vector2, count: int, word_order_value: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var safe_minimum: Vector2 = play_area.position + Vector2.ONE * unit_collision_radius
	var safe_maximum: Vector2 = play_area.end - Vector2.ONE * unit_collision_radius
	if safe_maximum.x < safe_minimum.x or safe_maximum.y < safe_minimum.y:
		return positions
	var minimum_spacing: float = unit_collision_radius * 2.0 + 1.0
	var ring_radius: float = unit_collision_radius * 2.2
	if count > 2:
		ring_radius = maxf(ring_radius, minimum_spacing / (2.0 * sin(PI / float(count))))
	var base_angle: float = float(word_order_value) * 2.399963229728653
	const ANGLE_STEPS: int = 24
	for unit_index: int in count:
		var initial_angle: float = base_angle + TAU * float(unit_index) / float(count)
		var found_position := false
		for ring_index: int in 12:
			var candidate_radius: float = ring_radius * float(ring_index + 1)
			for angle_index: int in ANGLE_STEPS:
				var candidate_angle: float = initial_angle + TAU * float(angle_index) / float(ANGLE_STEPS)
				var candidate: Vector2 = (center + Vector2.from_angle(candidate_angle) * candidate_radius).clamp(
					safe_minimum,
					safe_maximum
				)
				if not _is_batch_spawn_position_clear(candidate, positions, minimum_spacing):
					continue
				positions.append(candidate)
				found_position = true
				break
			if found_position:
				break
		if not found_position:
			positions.clear()
			return positions
	return positions


## 只检查新批次内部，点击到已有棋子附近仍属合法投放。
func _is_batch_spawn_position_clear(candidate: Vector2, positions: Array[Vector2], minimum_spacing: float) -> bool:
	var minimum_distance_squared: float = minimum_spacing * minimum_spacing
	for position: Vector2 in positions:
		if candidate.distance_squared_to(position) < minimum_distance_squared:
			return false
	return true


func _batch_spawn_failure(reason: StringName) -> Dictionary:
	return {"ok": false, "reason": str(reason), "unit_ids": []}


## 组装棋子数据但暂不启用碰撞，供单体出生和整批事务共用。
func _configure_spawn_unit(
	unit: PlanBUnit,
	unit_id: int,
	team_value: StringName,
	word_definition: Dictionary,
	new_word_order: int,
	spawn_position: Vector2,
	wander_direction: Vector2,
	base_speed: float,
	lifetime: float
) -> void:
	unit.configure_unit(
		unit_id,
		team_value,
		word_definition,
		new_word_order,
		spawn_position,
		wander_direction * base_speed,
		base_speed,
		lifetime,
		wander_direction,
		_rng.randf_range(1.2, 3.1),
		unit_collision_radius
	)
	unit.collision_layer = 1
	unit.collision_mask = 1
	unit.monitoring = false
	unit.monitorable = true


## 入树和注册完成后再允许 Area2D 产生接触事件。
func _register_spawn_unit(unit: PlanBUnit, unit_id: int) -> void:
	add_child(unit)
	unit.area_entered.connect(_on_unit_area_entered.bind(unit_id))
	_units_by_id[unit_id] = unit
	_steering_cache_by_unit_id[unit_id] = {
		"direction": unit.wander_direction,
		"intent": &"wander",
		"refresh_remaining_seconds": _target_decision_phase(unit_id),
	}
	_previous_physics_positions_by_unit_id[unit_id] = unit.global_position
	_neighbor_grid_dirty = true


## 中立补充、split和其它单体出生仍沿用同一初始化和ID登记路径。
func _spawn_unit(team_value: StringName, word_definition: Dictionary, new_word_order: int, spawn_position: Vector2) -> PlanBUnit:
	var unit_instance: Node = UNIT_SCENE.instantiate()
	var unit := unit_instance as PlanBUnit
	if unit == null:
		if is_instance_valid(unit_instance):
			unit_instance.free()
		return null
	var wander := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	var lifetime: float = _rng.randf_range(minf(lifespan_min_seconds, lifespan_max_seconds), maxf(lifespan_min_seconds, lifespan_max_seconds))
	var base_speed: float = _rng.randf_range(minf(base_speed_min, base_speed_max), maxf(base_speed_min, base_speed_max))
	var unit_id: int = _next_unit_id
	_configure_spawn_unit(unit, unit_id, team_value, word_definition, new_word_order, spawn_position, wander, base_speed, lifetime)
	_register_spawn_unit(unit, unit_id)
	_next_unit_id += 1
	unit.monitoring = true
	unit_spawned.emit(unit.unit_id)
	return unit


## 按模拟区域的当前本地坐标取样；优先选择与现有棋子相隔一个直径的位置。
func _random_spawn_position() -> Vector2:
	var left: float = play_area.position.x + unit_collision_radius
	var right: float = play_area.end.x - unit_collision_radius
	var top: float = play_area.position.y + unit_collision_radius
	var bottom: float = play_area.end.y - unit_collision_radius
	if right < left or bottom < top:
		return play_area.get_center()
	var existing_units: Array[PlanBUnit] = _get_sorted_units()
	if existing_units.is_empty():
		return Vector2(_rng.randf_range(left, right), _rng.randf_range(top, bottom))

	var minimum_spacing: float = unit_collision_radius * 2.0 + 1.0
	var minimum_spacing_squared: float = minimum_spacing * minimum_spacing
	# 棋盘安全区内生成7×6个分散格位，30中立加2个播种位有机会全部落在不重叠位置。
	var grid_candidate_positions: Array[Vector2] = []
	var grid_x_step: float = (right - left) / float(RANDOM_SPAWN_GRID_COLUMNS - 1)
	var grid_y_step: float = (bottom - top) / float(RANDOM_SPAWN_GRID_ROWS - 1)
	var grid_jitter_x: float = minf(4.0, maxf((grid_x_step - minimum_spacing) * 0.4, 0.0))
	var grid_jitter_y: float = minf(4.0, maxf((grid_y_step - minimum_spacing) * 0.4, 0.0))
	for row: int in RANDOM_SPAWN_GRID_ROWS:
		for column: int in RANDOM_SPAWN_GRID_COLUMNS:
			var grid_position := Vector2(
				left + grid_x_step * float(column) + _rng.randf_range(-grid_jitter_x, grid_jitter_x),
				top + grid_y_step * float(row) + _rng.randf_range(-grid_jitter_y, grid_jitter_y)
			).clamp(Vector2(left, top), Vector2(right, bottom))
			if _nearest_spawn_unit_distance_squared(grid_position, existing_units) >= minimum_spacing_squared:
				grid_candidate_positions.append(grid_position)
	if not grid_candidate_positions.is_empty():
		return grid_candidate_positions[_rng.randi_range(0, grid_candidate_positions.size() - 1)]

	var best_position: Vector2 = play_area.get_center()
	var best_nearest_distance_squared: float = -1.0
	for _candidate_index: int in RANDOM_SPAWN_CANDIDATE_COUNT:
		var candidate := Vector2(_rng.randf_range(left, right), _rng.randf_range(top, bottom))
		var nearest_distance_squared: float = _nearest_spawn_unit_distance_squared(candidate, existing_units)
		if nearest_distance_squared >= minimum_spacing_squared:
			return candidate
		if nearest_distance_squared > best_nearest_distance_squared:
			best_nearest_distance_squared = nearest_distance_squared
			best_position = candidate
	# 场地没有完整直径的空位时仍让棋子入场，并选择当前相对最空的候选点。
	return best_position


## 返回出生候选点到现存人群的最近距离平方。
func _nearest_spawn_unit_distance_squared(candidate: Vector2, existing_units: Array[PlanBUnit]) -> float:
	var nearest_distance_squared: float = INF
	for unit: PlanBUnit in existing_units:
		nearest_distance_squared = minf(nearest_distance_squared, candidate.distance_squared_to(unit.position))
	return nearest_distance_squared


## 让分裂子体从目标周围展开；每个方向按请求次序稳定计算，且限制在实际战场内。
func _get_split_child_position(target_unit: PlanBUnit, child_index: int, child_count: int) -> Vector2:
	var angle: float = TAU * float(child_index) / float(maxi(child_count, 1))
	var spawn_offset: Vector2 = Vector2.from_angle(angle) * unit_collision_radius * 2.6
	var minimum: Vector2 = play_area.position + Vector2.ONE * unit_collision_radius
	var maximum: Vector2 = play_area.end - Vector2.ONE * unit_collision_radius
	return (target_unit.position + spawn_offset).clamp(minimum, maximum)


## 校验 C 提供的最小静态字段并深拷贝，运行时不持有词库可变引用。
func _copy_valid_word_definition(definition: Dictionary) -> Dictionary:
	var word_id: String = str(definition.get("word_id", "")).strip_edges()
	var text: String = str(definition.get("text", "")).strip_edges()
	var battle_type: String = str(definition.get("battle_type", "")).strip_edges()
	var tendency: String = str(definition.get("tendency", "")).strip_edges()
	var traits_value: Variant = definition.get("traits", [])
	var strength: int = int(definition.get("strength", 0))
	if word_id.is_empty() or text.is_empty() or battle_type.is_empty() or tendency.is_empty():
		return {}
	if strength < 1 or strength > 3 or not (traits_value is Array):
		return {}
	var copy: Dictionary = definition.duplicate(true)
	copy["word_id"] = word_id
	copy["text"] = text
	copy["battle_type"] = battle_type
	copy["strength"] = strength
	copy["traits"] = traits_value.duplicate(true)
	copy["tendency"] = tendency
	return copy


## 只根据外部注入的属性表检查克制方向，不用 strength 改写合法性。
func _counters(source_unit: PlanBUnit, target_unit: PlanBUnit) -> bool:
	if not source_unit.has_word() or not target_unit.has_word():
		return false
	var source_type: StringName = source_unit.get_battle_type()
	var target_type: StringName = target_unit.get_battle_type()
	return _type_counter_by_type.get(source_type, &"") == target_type


## 当前只允许玩家和对手作为可播种阵营。
func _is_faction(team_value: StringName) -> bool:
	return team_value == PLAYER_TEAM or team_value == OPPONENT_TEAM


## C 当前发送字符串 ID，A/B 内部使用 int；拒绝空值和非数字字符串。
func _normalize_unit_id(unit_id_value: Variant) -> int:
	if unit_id_value is int:
		return int(unit_id_value)
	var unit_id_text: String = str(unit_id_value).strip_edges()
	return unit_id_text.to_int() if unit_id_text.is_valid_int() else -1


## 所有对外快照和接触裁决复用稳定 ID 顺序。
func _get_sorted_unit_ids() -> Array[int]:
	var unit_ids: Array[int] = []
	for key: Variant in _units_by_id.keys():
		unit_ids.append(int(key))
	unit_ids.sort()
	return unit_ids


## 将当前有效棋子按 unit_id 排序，供移动和帧更新稳定遍历。
func _get_sorted_units() -> Array[PlanBUnit]:
	var units: Array[PlanBUnit] = []
	for unit_id: int in _get_sorted_unit_ids():
		var unit := _units_by_id.get(unit_id) as PlanBUnit
		if unit != null:
			units.append(unit)
	return units
