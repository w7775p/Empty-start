extends Node2D

const BOARD_RECT: Rect2 = Rect2(Vector2(448.0, 72.0), Vector2(1024.0, 828.0))
const LEGAL_CHANCES: Dictionary = {1: 0.50, 2: 0.60, 3: 0.70}
const LEGAL_BATCH_SIZES: Dictionary = {1: 2, 2: 4, 3: 8}

var _simulation: PlanBUnitSimulation
var _failed_checks: Array[String] = []
var _unit_spawned_ids: Array[int] = []
var _spawn_population_sizes: Array[int] = []
var _batch_events: Array[Dictionary] = []
var _trait_events: Array[Dictionary] = []
var _contact_events_by_pair: Dictionary = {}
var _probability_strength_by_attacker_id: Dictionary = {}
var _probability_attempts: Dictionary = {1: 0, 2: 0, 3: 0}
var _probability_conversions: Dictionary = {1: 0, 2: 0, 3: 0}


func _ready() -> void:
	_simulation = get_node("Simulation") as PlanBUnitSimulation
	_simulation.unit_spawned.connect(_on_unit_spawned)
	_simulation.word_batch_spawned.connect(_on_word_batch_spawned)
	_simulation.word_batch_trait_awarded.connect(_on_word_batch_trait_awarded)
	_simulation.contact_resolved.connect(_on_contact_resolved)
	call_deferred("_run_smoke")


## 依序验证批次完整提交、容量原子失败、真实感染概率和同批一次性特性。
func _run_smoke() -> void:
	await get_tree().process_frame
	await _test_batch_sizes_and_atomic_capacity()
	if not _failed_checks.is_empty():
		_finish_smoke()
		return
	await _test_legal_infection_rates()
	if not _failed_checks.is_empty():
		_finish_smoke()
		return
	await _test_batch_trait_and_reflect()
	_finish_smoke()


## 玩家和对手共用完整2/4/8批次入口，并验证失败不占人口、ID或批次信号。
func _test_batch_sizes_and_atomic_capacity() -> void:
	await _reset_simulation(20261018, 90)
	var neutral_ids: Array[int] = _simulation.create_population(10, 0)
	_check(neutral_ids.size() == 10, "batch fixture starts with ten neutrals")
	_simulation.start_simulation()
	_unit_spawned_ids.clear()
	_batch_events.clear()
	_spawn_population_sizes.clear()
	var next_word_order: int = 10
	var expected_spawned: int = 0
	for team: StringName in [&"player", &"opponent"]:
		for strength: int in [1, 2, 3]:
			var batch_size: int = int(LEGAL_BATCH_SIZES[strength])
			var definition: Dictionary = _word("%s-%d" % [str(team), strength], "批次强度%d" % strength, "type_a", strength)
			var origin := BOARD_RECT.position + Vector2(300.0 + 80.0 * strength, 300.0)
			var result: Dictionary = _simulation.spawn_word_batch(origin, team, definition, next_word_order, batch_size)
			_check(bool(result.get("ok", false)), "%s strength %d batch succeeds" % [str(team), strength])
			if not bool(result.get("ok", false)):
				return
			var unit_ids: Array = result.get("unit_ids", [])
			var batch_event: Dictionary = _batch_events.back()
			_check(unit_ids.size() == batch_size and int(result.get("count", 0)) == batch_size, "strength %d creates a complete batch" % strength)
			_check(str(batch_event.get("team", "")) == str(team), "batch fact preserves its team")
			_check(int(batch_event.get("word_order", -1)) == next_word_order, "batch fact preserves global word order")
			_check(batch_event.get("spawn_position", Vector2.ZERO) == origin, "batch fact uses the global click position")
			var event_unit_ids: Array = batch_event.get("unit_ids", [])
			_check(event_unit_ids.size() == batch_size, "batch fact lists every member once")
			var target_positions: Array = batch_event.get("spawn_target_positions", [])
			_check(target_positions.size() == batch_size, "batch fact includes each actual spawn position")
			for index: int in unit_ids.size():
				var unit_id: int = int(unit_ids[index])
				var snapshot: Dictionary = _simulation.get_unit_snapshot(unit_id)
				_check(str(snapshot.get("team", "")) == str(team), "spawned unit has the requested team")
				_check(str(snapshot.get("word_id", "")) == str(definition.get("word_id", "")), "spawned unit has the complete word snapshot")
				_check(int(snapshot.get("word_order", -1)) == next_word_order, "spawned unit has the batch word order")
				_check(int(snapshot.get("strength", 0)) == strength, "spawned unit keeps its strength")
				_check(float(snapshot.get("spawn_burst_remaining", 0.0)) == 0.5, "spawned unit enters the half-second burst")
				_check(snapshot.get("position", Vector2.ZERO) == target_positions[index], "unit snapshot agrees with its published target position")
			var minimum_spacing: float = _simulation.unit_collision_radius * 2.0
			for first_index: int in target_positions.size():
				for second_index: int in range(first_index + 1, target_positions.size()):
					var first_position: Vector2 = target_positions[first_index]
					var second_position: Vector2 = target_positions[second_index]
					var distance: float = first_position.distance_to(second_position)
					_check(distance >= minimum_spacing, "batch spawn positions do not overlap")
			expected_spawned += batch_size
			_check(_unit_spawned_ids.size() == expected_spawned, "unit_spawned reports the real batch member count")
			_check(_batch_events.size() == next_word_order - 9, "one batch fact is emitted per successful batch")
			for observed_population: int in _spawn_population_sizes:
				_check(observed_population == _simulation.get_unit_snapshots().size(), "spawn listeners see the completed batch population")
			_spawn_population_sizes.clear()
			next_word_order += 1

	var population_before_failure: int = _simulation.get_unit_snapshots().size()
	var spawned_before_failure: int = _unit_spawned_ids.size()
	var batch_events_before_failure: int = _batch_events.size()
	var last_unit_id_before_failure: int = int(_simulation.get_unit_snapshots().back().get("unit_id", -1))
	_simulation.maximum_population = population_before_failure + 1
	var capacity_failure: Dictionary = _simulation.spawn_word_batch(
		BOARD_RECT.position + Vector2(500.0, 400.0), &"player", _word("capacity-fail", "容量失败", "type_a", 3), 100, 8
	)
	_check(not bool(capacity_failure.get("ok", false)) and str(capacity_failure.get("reason", "")) == "capacity", "insufficient capacity reports a clear failure")
	_check(_simulation.get_unit_snapshots().size() == population_before_failure, "capacity failure leaves population unchanged")
	_check(_unit_spawned_ids.size() == spawned_before_failure and _batch_events.size() == batch_events_before_failure, "capacity failure emits no spawn or batch facts")
	var invalid_count: Dictionary = _simulation.spawn_word_batch(
		BOARD_RECT.position + Vector2(500.0, 400.0), &"player", _word("count-fail", "数量不匹配", "type_a", 3), 101, 4
	)
	_check(not bool(invalid_count.get("ok", false)) and str(invalid_count.get("reason", "")) == "invalid_batch_size", "wrong strength/count pairing fails")
	var duplicate_order: Dictionary = _simulation.spawn_word_batch(
		BOARD_RECT.position + Vector2(500.0, 400.0), &"opponent", _word("order-fail", "顺序重复", "type_a", 1), 10, 2
	)
	_check(not bool(duplicate_order.get("ok", false)) and str(duplicate_order.get("reason", "")) == "duplicate_word_order", "duplicate batch order fails")
	var invalid_position: Dictionary = _simulation.spawn_word_batch(
		BOARD_RECT.position - Vector2.ONE, &"player", _word("position-fail", "落点无效", "type_a", 1), 102, 2
	)
	_check(not bool(invalid_position.get("ok", false)) and str(invalid_position.get("reason", "")) == "invalid_position", "outside-board position fails")
	_check(_simulation.get_unit_snapshots().size() == population_before_failure, "all rejected batch requests leave population unchanged")

	_simulation.maximum_population = population_before_failure + 2
	var next_batch: Dictionary = _simulation.spawn_word_batch(
		BOARD_RECT.position, &"player", _word("next-batch", "边角发言", "type_a", 1), 200, 2
	)
	_check(bool(next_batch.get("ok", false)), "a complete batch can spawn at the board edge")
	if bool(next_batch.get("ok", false)):
		var next_ids: Array = next_batch.get("unit_ids", [])
		_check(int(next_ids[0]) == last_unit_id_before_failure + 1, "failed requests do not consume unit IDs")


## 固定seed在真实Area2D接触上抽样，核对三档合法感染率均值。
func _test_legal_infection_rates() -> void:
	await _reset_simulation(20261018, 400)
	_check(is_equal_approx(float(PlanBUnitSimulation.INFECTION_CHANCES_BY_STRENGTH[1]), 0.50), "strength 1 legal infection chance is 50 percent")
	_check(is_equal_approx(float(PlanBUnitSimulation.INFECTION_CHANCES_BY_STRENGTH[2]), 0.60), "strength 2 legal infection chance is 60 percent")
	_check(is_equal_approx(float(PlanBUnitSimulation.INFECTION_CHANCES_BY_STRENGTH[3]), 0.70), "strength 3 legal infection chance is 70 percent")
	var neutral_ids: Array[int] = _simulation.create_population(360, 0)
	_simulation.neutral_spawn_interval_seconds = 100.0
	_simulation.lifespan_min_seconds = 120.0
	_simulation.lifespan_max_seconds = 120.0
	_simulation.maximum_speed = 1.0
	_simulation.detection_radius = 1.0
	_simulation.wandering_weight = 0.0
	_simulation.chase_weight = 0.0
	_simulation.flee_weight = 0.0
	_probability_strength_by_attacker_id.clear()
	_probability_attempts = {1: 0, 2: 0, 3: 0}
	_probability_conversions = {1: 0, 2: 0, 3: 0}
	for pair_index: int in 180:
		var strength: int = int(pair_index / 60) + 1
		var attacker_id: int = neutral_ids[pair_index * 2]
		var target_id: int = neutral_ids[pair_index * 2 + 1]
		var order: int = 1000 + pair_index * 2
		var attacker_definition: Dictionary = _word("rate-p-%d-%d" % [strength, pair_index], "强度%d测试" % strength, "type_a", strength)
		var target_definition: Dictionary = _word("rate-o-%d-%d" % [strength, pair_index], "对手测试", "type_b", 1)
		_simulation.seed_unit(attacker_id, &"player", attacker_definition, order)
		_simulation.seed_unit(target_id, &"opponent", target_definition, order + 1)
		_probability_strength_by_attacker_id[attacker_id] = strength
		var column: int = pair_index % 12
		var row: int = pair_index / 12
		var local_pair_position := Vector2(40.0 + float(column) * 80.0, 40.0 + float(row) * 50.0)
		var attacker := _find_unit_node(attacker_id)
		var target := _find_unit_node(target_id)
		attacker.global_position = BOARD_RECT.position + local_pair_position
		target.global_position = BOARD_RECT.position + local_pair_position + Vector2(18.0, 0.0)
		attacker.base_speed = 0.0
		target.base_speed = 0.0
		attacker.wander_direction = Vector2.ZERO
		target.wander_direction = Vector2.ZERO
		attacker.wander_change_remaining = 100.0
		target.wander_change_remaining = 100.0
	_simulation.start_simulation()
	for frame_index: int in 120:
		if _sum_dictionary_values(_probability_attempts) >= 180:
			break
		await get_tree().physics_frame
	var total_attempts: int = _sum_dictionary_values(_probability_attempts)
	_check(total_attempts == 180, "all 180 legal contact attempts are observed")
	for strength: int in [1, 2, 3]:
		var attempts: int = int(_probability_attempts[strength])
		var conversions: int = int(_probability_conversions[strength])
		var measured_rate: float = float(conversions) / maxf(float(attempts), 1.0)
		var expected_rate: float = float(LEGAL_CHANCES[strength])
		_check(attempts == 60, "strength %d receives sixty legal contact samples" % strength)
		_check(absf(measured_rate - expected_rate) <= 0.18, "strength %d measured %.2f is near %.2f" % [strength, measured_rate, expected_rate])
		print("PB13 LEGAL_INFECTION: strength=%d attempts=%d converted=%d rate=%.3f expected=%.2f" % [
			strength, attempts, conversions, measured_rate, expected_rate,
		])
	_simulation.pause_simulation()


## 同一word_order的五次成功感染只奖励一个特性，并实际验证批次分裂或反弹。
func _test_batch_trait_and_reflect() -> void:
	var split_trait: StringName = await _exercise_batch_trait(20261020, &"split")
	var reflect_trait: StringName = await _exercise_batch_trait(20261019, &"reflect")
	_check(split_trait == &"split", "fixed seed exercises the batch split reward")
	_check(reflect_trait == &"reflect", "fixed seed exercises the batch reflect reward")
	await _test_reflect_contact()


## 固定seed完成一次玩家批次传播，并检查奖励在同一word_order下只出现一次。
func _exercise_batch_trait(seed_value: int, expected_trait: StringName) -> StringName:
	await _reset_simulation(seed_value, 96)
	var created_ids: Array[int] = _simulation.create_population(18, 0)
	var opponent_id: int = created_ids[0]
	_simulation.seed_unit(opponent_id, &"opponent", _word("trait-opponent", "费米反击", "type_c", 3), 1)
	var batch_order: int = 2
	var result: Dictionary = _simulation.spawn_word_batch(
		BOARD_RECT.position + Vector2(500.0, 400.0),
		&"player",
		_word("trait-batch", "第五次感染", "type_a", 3),
		batch_order,
		8
	)
	_check(bool(result.get("ok", false)), "trait test starts with a real strength-3 batch")
	if not bool(result.get("ok", false)):
		return &""
	var player_ids: Array = result.get("unit_ids", [])
	var neutral_ids: Array[int] = []
	for created_index: int in range(1, created_ids.size()):
		neutral_ids.append(created_ids[created_index])
	_simulation.detection_radius = 1.0
	_simulation.maximum_speed = 0.0
	_simulation.wandering_weight = 0.0
	_simulation.chase_weight = 0.0
	_simulation.flee_weight = 0.0
	for player_index: int in player_ids.size():
		var player_unit := _find_unit_node(int(player_ids[player_index]))
		player_unit.spawn_burst_remaining_seconds = 0.0
		player_unit.base_speed = 0.0
		player_unit.wander_direction = Vector2.ZERO
		player_unit.wander_change_remaining = 100.0
		player_unit.global_position = BOARD_RECT.position + Vector2(80.0 + float(player_index) * 100.0, 160.0)
	var opponent_unit := _find_unit_node(opponent_id)
	opponent_unit.base_speed = 0.0
	opponent_unit.wander_direction = Vector2.ZERO
	opponent_unit.wander_change_remaining = 100.0
	opponent_unit.global_position = BOARD_RECT.position + Vector2(950.0, 750.0)
	for neutral_index: int in neutral_ids.size():
		var neutral_unit := _find_unit_node(neutral_ids[neutral_index])
		neutral_unit.base_speed = 0.0
		neutral_unit.wander_direction = Vector2.ZERO
		neutral_unit.wander_change_remaining = 100.0
		neutral_unit.global_position = BOARD_RECT.position + Vector2(
			60.0 + float(neutral_index % 6) * 80.0,
			600.0 + float(neutral_index / 6) * 70.0
		)
	_simulation.start_simulation()
	var successes: int = 0
	var neutral_index: int = 0
	var attempts: int = 0
	while neutral_index < neutral_ids.size() and successes < 10 and attempts < 30:
		var player_id: int = int(player_ids[attempts % player_ids.size()])
		var neutral_id: int = neutral_ids[neutral_index]
		var pair_position := BOARD_RECT.position + Vector2(80.0 + float(attempts % player_ids.size()) * 100.0, 160.0)
		var outcome: String = await _attempt_contact_pair(player_id, neutral_id, pair_position)
		attempts += 1
		if outcome == "converted":
			successes += 1
			neutral_index += 1
		elif outcome == "infection_failed":
			neutral_index += 1
		_check(outcome == "converted" or outcome == "infection_failed", "batch member resolves a legal infection contact")
	_check(successes >= PlanBUnitSimulation.BATCH_TRAIT_INFECTION_THRESHOLD, "one player batch reaches five successful infections")
	_check(_trait_events.size() == 1, "one word_order can award at most one trait")
	var awarded_trait_name := "none"
	if _trait_events.size() == 1:
		var trait_event: Dictionary = _trait_events[0]
		_check(int(trait_event.get("word_order", -1)) == batch_order, "trait belongs to the triggering word batch")
		var awarded_trait: StringName = StringName(str(trait_event.get("trait", "")))
		awarded_trait_name = str(awarded_trait)
		_check(awarded_trait == &"split" or awarded_trait == &"reflect", "batch grants split or reflect")
		_check(awarded_trait == expected_trait, "fixed seed selects the expected one-time trait")
		if awarded_trait == &"split":
			_check(_simulation.get_unit_snapshots().size() == created_ids.size() + player_ids.size() + 1, "split adds one real child and no repeated children")
			_check(_find_unit_node(int(trait_event.get("unit_id", -1))) != null, "split effect names a surviving batch member")
		else:
			var recipient := _find_unit_node(int(trait_event.get("unit_id", -1)))
			_check(recipient != null and recipient.combat_trait == &"reflect" and recipient.combat_trait_uses == 1, "reflect is stored as one available use")
	print("PB13 TRAIT: successes=%d contacts=%d awards=%d trait=%s" % [successes, attempts, _trait_events.size(), awarded_trait_name])
	_simulation.pause_simulation()
	return StringName(awarded_trait_name)


## 单独验证reflect只挡一次已合法的敌方克制感染，并让攻击者持续后退。
func _test_reflect_contact() -> void:
	await _reset_simulation(20261020, 12)
	var ids: Array[int] = _simulation.create_population(2, 0)
	var player_id: int = ids[0]
	var opponent_id: int = ids[1]
	_simulation.seed_unit(player_id, &"player", _word("reflect-player", "玩家防御", "type_a", 2), 1)
	_simulation.seed_unit(opponent_id, &"opponent", _word("reflect-opponent", "费米克制", "type_c", 3), 2)
	var player_unit := _find_unit_node(player_id)
	var opponent_unit := _find_unit_node(opponent_id)
	player_unit.set_combat_trait(&"reflect", 1)
	player_unit.base_speed = 0.0
	opponent_unit.base_speed = 0.0
	player_unit.wander_direction = Vector2.ZERO
	opponent_unit.wander_direction = Vector2.ZERO
	player_unit.wander_change_remaining = 100.0
	opponent_unit.wander_change_remaining = 100.0
	_simulation.start_simulation()
	var first_outcome: String = await _attempt_contact_pair(player_id, opponent_id, BOARD_RECT.position + Vector2(450.0, 400.0))
	_check(first_outcome == "reflected", "reflect prevents a legal counter infection")
	_check(player_unit.team == &"player" and player_unit.combat_trait_uses == 0, "reflect is consumed without changing the defender team")
	_check(opponent_unit.contact_recoil_remaining_seconds > 0.0, "reflect applies a visible recoil interval to the attacker")
	var second_outcome: String = await _attempt_contact_pair(player_id, opponent_id, BOARD_RECT.position + Vector2(450.0, 400.0))
	_check(second_outcome == "converted" or second_outcome == "infection_failed", "a consumed reflect does not block the next legal infection")
	_simulation.pause_simulation()


## 重置公开模拟参数与事件观察器，保持断言只访问公开快照和实际棋子状态。
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
	_simulation.set_random_seed(seed_value)
	_check(_simulation.set_play_area(BOARD_RECT), "B accepts the scene-global board Rect2")
	_check(_simulation.play_area == Rect2(Vector2.ZERO, BOARD_RECT.size), "global board rect converts to the offset simulator local area")
	_check(_simulation.set_type_counter_map({"type_a": "type_b", "type_b": "type_c", "type_c": "type_a"}), "test matchup map installs")
	_unit_spawned_ids.clear()
	_spawn_population_sizes.clear()
	_batch_events.clear()
	_trait_events.clear()
	_contact_events_by_pair.clear()
	_probability_strength_by_attacker_id.clear()


## 让已创建棋子在场景全局坐标移动，构造可重复的合法碰撞样本。
func _set_unit_global_position(unit_id: int, new_position: Vector2) -> void:
	var unit := _find_unit_node(unit_id)
	if unit != null:
		unit.global_position = new_position


## 通过稳定 unit_id 找到真实棋子节点，仅供场景夹具摆放碰撞位置。
func _find_unit_node(unit_id: int) -> PlanBUnit:
	for child: Node in _simulation.get_children():
		var unit := child as PlanBUnit
		if unit != null and unit.unit_id == unit_id:
			return unit
	return null


## 通过真实 Area2D 重叠触发一次感染裁决；移动分离后再复用同一对进行复测。
func _attempt_contact_pair(first_id: int, second_id: int, scene_position: Vector2) -> String:
	var first_unit := _find_unit_node(first_id)
	var second_unit := _find_unit_node(second_id)
	if first_unit == null or second_unit == null:
		return "missing-unit"
	first_unit.global_position = BOARD_RECT.position + Vector2(35.0, 780.0)
	second_unit.global_position = BOARD_RECT.position + Vector2(95.0, 780.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	first_unit.contact_cooldown_remaining = 0.0
	second_unit.contact_cooldown_remaining = 0.0
	first_unit.contact_recoil_remaining_seconds = 0.0
	second_unit.contact_recoil_remaining_seconds = 0.0
	first_unit.spawn_burst_remaining_seconds = 0.0
	second_unit.spawn_burst_remaining_seconds = 0.0
	first_unit.global_position = scene_position
	second_unit.global_position = scene_position + Vector2(18.0, 0.0)
	var pair := Vector2i(mini(first_id, second_id), maxi(first_id, second_id))
	var old_events: Array = _contact_events_by_pair.get(pair, [])
	var old_event_count: int = old_events.size()
	for frame_index: int in 12:
		await get_tree().physics_frame
		var events: Array = _contact_events_by_pair.get(pair, [])
		if events.size() > old_event_count:
			return str(events.back())
	return "no-contact"


## 记录真实 unit_spawned 事实，并确认回调读取时整批人口已经登记完成。
func _on_unit_spawned(unit_id: int) -> void:
	_unit_spawned_ids.append(unit_id)
	_spawn_population_sizes.append(_simulation.get_unit_snapshots().size())


## 保存完整批次事实快照，验证一个发表只发一次批次事件。
func _on_word_batch_spawned(batch: Dictionary) -> void:
	_batch_events.append(batch.duplicate(true))


## 记录玩家同批五次传播后的候选特性奖励事实。
func _on_word_batch_trait_awarded(word_order: int, unit_id: int, trait_name: StringName) -> void:
	_trait_events.append({"word_order": word_order, "unit_id": unit_id, "trait": trait_name})


## 统计真实 Area2D 接触结果，并按合法感染方的 strength 汇总抽样率。
func _on_contact_resolved(first_id: int, second_id: int, outcome: StringName) -> void:
	var pair := Vector2i(mini(first_id, second_id), maxi(first_id, second_id))
	var events: Array = _contact_events_by_pair.get(pair, [])
	events.append(str(outcome))
	_contact_events_by_pair[pair] = events
	var attacker_id: int = first_id if _probability_strength_by_attacker_id.has(first_id) else second_id
	if not _probability_strength_by_attacker_id.has(attacker_id):
		return
	if outcome != &"converted" and outcome != &"infection_failed":
		return
	var strength: int = int(_probability_strength_by_attacker_id[attacker_id])
	_probability_attempts[strength] = int(_probability_attempts.get(strength, 0)) + 1
	if outcome == &"converted":
		_probability_conversions[strength] = int(_probability_conversions.get(strength, 0)) + 1


## 汇总固定抽样中的事件次数。
func _sum_dictionary_values(values: Dictionary) -> int:
	var total: int = 0
	for value: Variant in values.values():
		total += int(value)
	return total


## 构造与真实静态词定义一致的独立值快照。
func _word(word_id: String, text: String, battle_type: String, strength: int) -> Dictionary:
	return {
		"word_id": word_id,
		"text": text,
		"battle_type": battle_type,
		"strength": strength,
		"traits": [],
		"tendency": "neutral",
		"available_level": "level_001",
	}


## 聚合确定性 smoke 断言；失败会让场景以非零状态退出。
func _check(condition: bool, description: String) -> void:
	if condition:
		return
	_failed_checks.append(description)
	push_error("PB-13 CHECK FAILED: " + description)


## 输出 PB-13 smoke 汇总并按断言结果退出。
func _finish_smoke() -> void:
	_simulation.pause_simulation()
	if _failed_checks.is_empty():
		print("PB-13 PASS: complete batches, atomic capacity, 50/60/70 legal infection, one-shot split/reflect")
		await get_tree().create_timer(0.5).timeout
		get_tree().quit(0)
		return
	print("PB-13 FAIL: %d check(s)" % _failed_checks.size())
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1)
