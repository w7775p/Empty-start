extends Node

const BATTLE_HOST_SCRIPT_PATH := "res://systems/plan_b/battle/plan_b_battle_host.gd"
const CONTENT_SCRIPT_PATH := "res://systems/plan_b/content/plan_b_content_catalog.gd"
const SIMULATION_SCRIPT_PATH := "res://systems/plan_b/simulation/plan_b_unit_simulation.gd"
const OPPONENT_DIRECTOR_SCRIPT_PATH := "res://systems/plan_b/opponent/fermi_opponent_director.gd"
const TYPE_COUNTERS := {"type_a": "type_b", "type_b": "type_c", "type_c": "type_a"}
const FIXED_SEEDS: Array[int] = [20261017, 20261018, 20261019, 20261020, 20261021, 20261022, 20261023, 20261024, 20261025, 20261026]

var _failures: Array[String] = []
var _contact_events: Array[Dictionary] = []
var _unit_changes: Array[Dictionary] = []
var _unit_spawns: Array[int] = []
var _unit_despawns: Array[int] = []
var _battle_end_results: Array[StringName] = []


# 本入口只走 A/B/C 公开方法与信号；目录、场景和字段来自当前 Plan B 接口约定。
func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var content: Object = _load_content_catalog()
	if content == null:
		_check(false, "PB-03 PlanBContentCatalog 与测试配置可加载")
		_finish()
		return
	var player_words: Array = content.call("get_word_definitions", "level_001", "player")
	var opponent_words: Array = content.call("get_word_definitions", "level_001", "opponent")
	_test_content_contract(content, player_words, opponent_words)
	await _test_battle_host(content)
	await _test_unit_simulation(player_words + opponent_words)
	_finish()


func _load_content_catalog() -> Object:
	var catalog_script: Script = load(CONTENT_SCRIPT_PATH) as Script
	if catalog_script == null:
		return null
	var catalog: Object = catalog_script.new()
	if not bool(catalog.call("load_test_configuration")):
		return null
	return catalog


# C 返回完整可读快照，A 的公开查询应消费同一批词条。
func _test_content_contract(content: Object, player_words: Array, opponent_words: Array) -> void:
	_check(player_words.size() >= 12, "C 至少提供 12 条玩家测试话语")
	_check(opponent_words.size() >= 5, "C 至少提供 5 条费米测试话语")
	var battle_types: Dictionary = {}
	var strengths: Dictionary = {}
	for word_value: Variant in player_words + opponent_words:
		var word: Dictionary = word_value as Dictionary
		for required_field: String in ["word_id", "text", "battle_type", "strength", "traits", "tendency", "available_level"]:
			_check(word.has(required_field), "C 话语快照含字段 %s" % required_field)
		battle_types[str(word.get("battle_type", ""))] = true
		strengths[int(word.get("strength", 0))] = true
	_check(battle_types.size() == 3, "C 测试词池覆盖三种临时战斗属性")
	_check(strengths.has(1) and strengths.has(2) and strengths.has(3), "C 测试词池覆盖 strength 1/2/3")
	_check(_near(float(content.call("get_strength_success_probability", 1)), 0.20), "C strength 1 概率为 20%")
	_check(_near(float(content.call("get_strength_success_probability", 2)), 0.35), "C strength 2 概率为 35%")
	_check(_near(float(content.call("get_strength_success_probability", 3)), 0.50), "C strength 3 概率为 50%")
	_check(StringName(content.call("get_type_matchup", "type_a", "type_b")) == &"advantage", "C 暴露可替换克制关系")
	if not player_words.is_empty():
		var original: Dictionary = content.call("get_word_definition", str(player_words[0].get("word_id", "")))
		var original_text: String = str(original.get("text", ""))
		original["text"] = "test mutation"
		var changed_traits: Array = original.get("traits", [])
		changed_traits.append(&"test_mutation")
		original["traits"] = changed_traits
		var reread: Dictionary = content.call("get_word_definition", str(player_words[0].get("word_id", "")))
		_check(
			str(reread.get("text", "")) == original_text
			and not (reread.get("traits", []) as Array).has(&"test_mutation"),
			"C 返回的词语快照及 traits 不会反写静态词库"
		)


# 通过 A 的唯一入口检查词占用、统一顺序号、真实人数 PK 和终止边界。
func _test_battle_host(content: Object) -> void:
	var first_context: Dictionary = await _start_host(content)
	var demo: Node = first_context.get("demo") as Node
	var host: Node = first_context.get("host") as Node
	if host == null:
		_check(false, "A 场景提供 publish_word 公开入口")
		if is_instance_valid(demo):
			demo.queue_free()
			await get_tree().process_frame
		return
	var simulation_module: Node = _find_method_node(demo, &"start_simulation")
	_check(
		simulation_module != null
		and simulation_module.has_method("seed_unit")
		and simulation_module.has_method("get_faction_counts")
		and simulation_module.has_method("get_unit_snapshots"),
		"A 场景组合 PB-02 的公开模拟模块"
	)
	var c_word_ids: Array = content.call("get_word_ids", "level_001", "player")
	var host_word_ids: Array = host.call("get_available_word_ids", "player")
	_check(not host_word_ids.is_empty(), "A 向玩家提供可发表话语")
	for word_id_value: Variant in host_word_ids:
		_check(not (content.call("get_word_definition", str(word_id_value)) as Dictionary).is_empty(), "A 使用 C 的正式原型词库 ID %s" % str(word_id_value))
	var initial_counts: Dictionary = host.call("get_faction_counts")
	_check(
		int(initial_counts.get("player", 0)) == 0
		and int(initial_counts.get("opponent", 0)) == 2
		and int(initial_counts.get("neutral", 0)) == 76,
		"开局应由A使用B两个中立播种位建立76中立/2费米人口；实际=%s" % [initial_counts]
	)
	var opening_word_ids: Array = host.call("get_used_word_ids")
	_check(
		opening_word_ids.size() == 2 and opening_word_ids[0] != opening_word_ids[1],
		"两条费米开局话语应记录为不同的已用word_id；实际=%s" % [opening_word_ids]
	)
	var neutral_ids: Array[String] = _get_neutral_ids(host)
	var player_publish_count := 3
	var opponent_publish_count := int(initial_counts.get("player", 0)) + player_publish_count - int(initial_counts.get("opponent", 0))
	_check(neutral_ids.size() >= player_publish_count + maxi(opponent_publish_count, 0), "A/B 提供足够的中立目标快照")
	if c_word_ids.is_empty() or host_word_ids.size() < player_publish_count or opponent_publish_count <= 0 \
		or (host.call("get_available_word_ids", "opponent") as Array).size() < opponent_publish_count \
		or neutral_ids.size() < player_publish_count + opponent_publish_count:
		if is_instance_valid(demo):
			demo.queue_free()
			await get_tree().process_frame
		return

	var expected_next_order: int = (host.call("get_used_word_ids") as Array).size() + 1
	var first_word_id: String = str(host_word_ids[0])
	var failed_target: Dictionary = host.call("publish_legacy_seed_word", "player", first_word_id, "2147483647")
	_check(not bool(failed_target.get("ok", false)), "无效目标发表失败")
	_check((host.call("get_available_word_ids", "player") as Array).has(first_word_id), "失败发表不占用话语")
	var first_success: Dictionary = host.call("publish_legacy_seed_word", "player", first_word_id, neutral_ids[0])
	_check(bool(first_success.get("ok", false)) and int(first_success.get("word_order", 0)) == expected_next_order, "首个成功发表取得下一个全局顺序号")
	var duplicate: Dictionary = host.call("publish_legacy_seed_word", "player", first_word_id, neutral_ids[1])
	_check(not bool(duplicate.get("ok", false)), "同一阵营重复发表相同 word_id 失败")
	var second_success: Dictionary = host.call("publish_legacy_seed_word", "player", str(host_word_ids[1]), neutral_ids[1])
	var third_success: Dictionary = host.call("publish_legacy_seed_word", "player", str(host_word_ids[2]), neutral_ids[2])
	_check(
		int(second_success.get("word_order", 0)) == expected_next_order + 1
		and int(third_success.get("word_order", 0)) == expected_next_order + 2,
		"连续成功发表共享递增顺序号"
	)
	var opponent_ids: Array = host.call("get_available_word_ids", "opponent")
	_check(not opponent_ids.is_empty(), "A 向费米提供可发表话语")
	for index: int in range(opponent_publish_count):
		var opponent_success: Dictionary = host.call("publish_legacy_seed_word", "opponent", str(opponent_ids[index]), neutral_ids[3 + index])
		_check(
			bool(opponent_success.get("ok", false))
			and int(opponent_success.get("word_order", 0)) == expected_next_order + 3 + index,
			"玩家和费米共用同一全局顺序号"
		)
	var counts: Dictionary = host.call("get_faction_counts")
	_check(
		int(counts.get("player", 0)) == int(initial_counts.get("player", 0)) + player_publish_count
		and int(counts.get("opponent", 0)) == int(initial_counts.get("opponent", 0)) + opponent_publish_count,
		"A/B 人数只在中立播种成功时变化"
	)
	var pk_before: float = float(host.call("get_pk"))
	host.call("update_pk", 1.0)
	_check(_near(float(host.call("get_pk")), pk_before), "双方人数相等时 PK 不变化")
	var seeded_snapshot: Dictionary = _find_snapshot(host, neutral_ids[0])
	_check(
		_matches_word_snapshot(seeded_snapshot, host.call("get_word_definition", first_word_id), expected_next_order),
		"播种棋子快照继承完整话语属性和顺序号"
	)
	if is_instance_valid(demo):
		demo.queue_free()
		await get_tree().process_frame

	var zero_context: Dictionary = await _start_host(content)
	var zero_demo: Node = zero_context.get("demo") as Node
	var zero_host: Node = zero_context.get("host") as Node
	_battle_end_results.clear()
	zero_host.connect(&"battle_ended", Callable(self, "_on_battle_ended"))
	var zero_counts: Dictionary = zero_host.call("get_faction_counts")
	if int(zero_counts.get("opponent", 0)) <= int(zero_counts.get("player", 0)):
		var zero_word_ids: Array = zero_host.call("get_available_word_ids", "opponent")
		var zero_neutral_ids: Array[String] = _get_neutral_ids(zero_host)
		if not zero_word_ids.is_empty() and not zero_neutral_ids.is_empty():
			zero_host.call("publish_legacy_seed_word", "opponent", str(zero_word_ids[0]), zero_neutral_ids[0])
	zero_host.call("update_pk", 1000000.0)
	_check(_near(float(zero_host.call("get_pk")), 0.0), "真实人口差把 PK 限制在 0 边界")
	_check(not _battle_end_results.is_empty() and _battle_end_results.back() == &"failed", "PK 达到 0 发出失败事件")
	if is_instance_valid(zero_demo):
		zero_demo.queue_free()
		await get_tree().process_frame

	var hundred_context: Dictionary = await _start_host(content)
	var hundred_demo: Node = hundred_context.get("demo") as Node
	var hundred_host: Node = hundred_context.get("host") as Node
	var hundred_words: Array = hundred_host.call("get_available_word_ids", "player")
	var hundred_neutrals: Array[String] = _get_neutral_ids(hundred_host)
	var hundred_counts: Dictionary = hundred_host.call("get_faction_counts")
	var hundred_player_publish_count: int = maxi(1, int(hundred_counts.get("opponent", 0)) - int(hundred_counts.get("player", 0)) + 1)
	for index: int in range(mini(hundred_player_publish_count, mini(hundred_words.size(), hundred_neutrals.size()))):
		hundred_host.call("publish_legacy_seed_word", "player", str(hundred_words[index]), hundred_neutrals[index])
	_battle_end_results.clear()
	hundred_host.connect(&"battle_ended", Callable(self, "_on_battle_ended"))
	hundred_host.call("update_pk", 1000000.0)
	_check(_near(float(hundred_host.call("get_pk")), 100.0), "真实人口差把 PK 限制在 100 边界")
	_check(StringName(hundred_host.call("get_battle_state")) == &"ended", "PK 达到 100 发出结束状态")
	_check(not _battle_end_results.is_empty() and _battle_end_results.back() == &"enter_contradiction", "PK 达到 100 发出矛盾阶段事件")
	if is_instance_valid(hundred_demo):
		hundred_demo.queue_free()
		await get_tree().process_frame


func _start_host(content: Object) -> Dictionary:
	var host_script: Script = load(BATTLE_HOST_SCRIPT_PATH) as Script
	var simulation_script: Script = load(SIMULATION_SCRIPT_PATH) as Script
	var opponent_script: Script = load(OPPONENT_DIRECTOR_SCRIPT_PATH) as Script
	if host_script == null or simulation_script == null or opponent_script == null:
		_check(false, "A/B/C 正式模块脚本可加载")
		return {}
	var wrapper := Node.new()
	wrapper.name = "PB05RuntimeFixture"
	var host: Node = host_script.new() as Node
	var simulation: Node = simulation_script.new() as Node
	simulation.name = "Simulation"
	host.add_child(simulation)
	wrapper.add_child(host)
	get_tree().root.add_child(wrapper)
	await get_tree().process_frame
	var opponent_director: Object = opponent_script.new()
	_check(bool(host.call("configure_modules", simulation, content, opponent_director)), "A 接入 B/C 正式公开模块")
	host.set("opponent_auto_publish_enabled", false)
	host.set("player_publish_cooldown_seconds", 0.0)
	host.set("opponent_publish_cooldown_seconds", 0.0)
	simulation.call("set_random_seed", 20261017)
	host.call("start_battle", Vector2(900.0, 490.0))
	return {"demo": wrapper, "host": host, "simulation": simulation}


# 直接用 B 的稳定公开 API 建立固定 seed 样例，碰撞由真实 Area2D 物理事件触发。
func _test_unit_simulation(all_words: Array) -> void:
	var simulation_script: Script = load(SIMULATION_SCRIPT_PATH) as Script
	_check(simulation_script != null, "PB-02 PlanBUnitSimulation 脚本可加载")
	if simulation_script == null:
		return
	var word_a: Dictionary = _find_word(all_words, "type_a", 3)
	var word_b: Dictionary = _find_word_of_type(all_words, "type_b")
	var word_c: Dictionary = _find_word_of_type(all_words, "type_c")
	_check(not word_a.is_empty() and not word_b.is_empty() and not word_c.is_empty(), "C 提供接触测试所需的属性与强度组合")
	if word_a.is_empty() or word_b.is_empty() or word_c.is_empty():
		return

	var seed_context: Dictionary = _create_simulation(simulation_script, 2, 44.0, 100.0, 100.0, 20261017)
	var simulation: Node = seed_context.get("simulation") as Node
	var unit_ids: Array = seed_context.get("unit_ids", [])
	var seeded_before: Dictionary = simulation.call("get_faction_counts")
	var invalid_seed: bool = bool(simulation.call("seed_unit", 999999, &"player", word_a, 1))
	_check(not invalid_seed and simulation.call("get_faction_counts") == seeded_before, "B 播种失败不改阵营人数")
	_check(bool(simulation.call("seed_unit", int(unit_ids[0]), &"player", word_c, 1)), "B 公开 seed_unit 可播种中立棋子")
	_check(bool(simulation.call("seed_unit", int(unit_ids[1]), &"player", word_a, 2)), "B 可用更新 word_order 播种同阵营测试棋子")
	var seeded_counts: Dictionary = simulation.call("get_faction_counts")
	_check(int(seeded_counts.get("player", 0)) == 2 and int(seeded_counts.get("neutral", 0)) == 0, "播种只改变目标真实阵营人数")
	var relay_snapshot: Dictionary = _find_snapshot(simulation, int(unit_ids[0]))
	_check(_matches_word_snapshot(relay_snapshot, word_c, 1), "B 公开快照含完整话语属性")
	_check(_unit_changes.has({"unit_id": int(unit_ids[0]), "reason": &"seed"}), "B 播种时发出 seed 事实事件")
	_unit_changes.clear()
	simulation.call("start_simulation")
	await get_tree().create_timer(0.25, true, true).timeout
	simulation.call("pause_simulation")
	var relay_happened: bool = false
	for event: Dictionary in _unit_changes:
		if int(event.get("unit_id", -1)) == int(unit_ids[0]) and StringName(event.get("reason", &"")) == &"relay":
			relay_happened = true
	_check(relay_happened, "同阵营真实碰撞把新话完整传给旧棋子")
	var relayed_snapshot: Dictionary = _find_snapshot(simulation, int(unit_ids[0]))
	_check(_matches_word_snapshot(relayed_snapshot, word_a, 2), "传话继承完整快照与全局顺序号")
	await _dispose_simulation(simulation)

	await _test_enemy_contact(simulation_script, word_a, word_b)
	await _test_neutral_infection(simulation_script, word_a)
	await _test_strength_rates(simulation_script, all_words)
	await _test_birth_and_despawn(simulation_script)


func _test_enemy_contact(simulation_script: Script, word_a: Dictionary, word_b: Dictionary) -> void:
	var context: Dictionary = _create_simulation(simulation_script, 2, 44.0, 100.0, 100.0, 20261017)
	var simulation: Node = context["simulation"]
	var unit_ids: Array = context["unit_ids"]
	_check(bool(simulation.call("seed_unit", int(unit_ids[0]), &"player", word_a, 1)), "B 播种玩家敌我接触样例")
	_check(bool(simulation.call("seed_unit", int(unit_ids[1]), &"opponent", word_a, 2)), "B 播种同属性对手样例")
	_contact_events.clear()
	simulation.call("start_simulation")
	await get_tree().create_timer(0.25, true, true).timeout
	simulation.call("pause_simulation")
	_check(_has_contact_outcome(&"same_type_bounce"), "敌我同属性真实接触只弹开")
	_check(not _has_contact_outcome(&"converted"), "敌我同属性接触不会感染")
	var same_counts: Dictionary = simulation.call("get_faction_counts")
	_check(int(same_counts.get("player", 0)) == 1 and int(same_counts.get("opponent", 0)) == 1, "同属性弹开不改人数")
	await _dispose_simulation(simulation)

	var counter_context: Dictionary = _create_simulation(simulation_script, 2, 44.0, 100.0, 100.0, 20261018)
	simulation = counter_context["simulation"]
	unit_ids = counter_context["unit_ids"]
	simulation.call("seed_unit", int(unit_ids[0]), &"player", word_a, 1)
	simulation.call("seed_unit", int(unit_ids[1]), &"opponent", word_b, 2)
	_contact_events.clear()
	simulation.call("start_simulation")
	await get_tree().create_timer(0.25, true, true).timeout
	simulation.call("pause_simulation")
	var valid_counter_seen: bool = false
	for event: Dictionary in _contact_events:
		var outcome := StringName(event.get("outcome", &""))
		if outcome in [&"converted", &"infection_failed"]:
			valid_counter_seen = true
	_check(valid_counter_seen, "敵我克制组合进入真实感染概率裁决")
	_check(not _has_contact_outcome(&"no_counter_bounce"), "克制合法组合不会被误判为无克制")
	await _dispose_simulation(simulation)


func _test_neutral_infection(simulation_script: Script, word: Dictionary) -> void:
	var context: Dictionary = _create_simulation(simulation_script, 2, 44.0, 100.0, 100.0, 20261019)
	var simulation: Node = context["simulation"]
	var unit_ids: Array = context["unit_ids"]
	simulation.call("seed_unit", int(unit_ids[0]), &"player", word, 1)
	_contact_events.clear()
	simulation.call("start_simulation")
	await get_tree().create_timer(0.25, true, true).timeout
	simulation.call("pause_simulation")
	var legal_attempt_seen: bool = _has_contact_outcome(&"converted") or _has_contact_outcome(&"infection_failed")
	_check(legal_attempt_seen, "带感染能力的阵营棋子碰中立棋子进入成功率裁决")
	await _dispose_simulation(simulation)


# 用多组固定 seed 对真实 B 物理接触统计成功率，允许有限样本误差。
func _test_strength_rates(simulation_script: Script, all_words: Array) -> void:
	var definitions_by_strength: Dictionary = {
		1: _find_strength_word(all_words, 1),
		2: _find_strength_word(all_words, 2),
		3: _find_strength_word(all_words, 3),
	}
	for strength: int in [1, 2, 3]:
		_check(not definitions_by_strength[strength].is_empty(), "C 为 strength %d 提供可用于接触试验的话语" % strength)
	if definitions_by_strength[1].is_empty() or definitions_by_strength[2].is_empty() or definitions_by_strength[3].is_empty():
		return
	var measured: Dictionary = {}
	for strength: int in [1, 2, 3]:
		var successes: int = 0
		var attempts: int = 0
		var conversion_signals: int = 0
		for seed_value: int in FIXED_SEEDS:
			var context: Dictionary = _create_simulation(simulation_script, 96, 13.0, 100.0, 100.0, seed_value)
			var simulation: Node = context["simulation"]
			var unit_ids: Array = context["unit_ids"]
			var definition: Dictionary = definitions_by_strength[strength]
			for index: int in range(48):
				simulation.call("seed_unit", int(unit_ids[index]), &"player", definition, 1)
			_contact_events.clear()
			_unit_changes.clear()
			simulation.call("start_simulation")
			await get_tree().create_timer(1.0, true, true).timeout
			simulation.call("pause_simulation")
			for event: Dictionary in _contact_events:
				var outcome := StringName(event.get("outcome", &""))
				if outcome == &"converted":
					successes += 1
					attempts += 1
				elif outcome == &"infection_failed":
					attempts += 1
			var counts: Dictionary = simulation.call("get_faction_counts")
			var converted_this_run: int = 0
			for event: Dictionary in _contact_events:
				if StringName(event.get("outcome", &"")) == &"converted":
					converted_this_run += 1
			var convert_events_this_run: int = 0
			for change: Dictionary in _unit_changes:
				if StringName(change.get("reason", &"")) == &"convert":
					convert_events_this_run += 1
			conversion_signals += convert_events_this_run
			_check(convert_events_this_run == converted_this_run, "转换人数变更发出对应 convert 事实事件")
			_check(
				int(counts.get("player", 0)) == 48 + converted_this_run
				and int(counts.get("neutral", 0)) == 48 - converted_this_run,
				"中立感染按成功转换真实改变阵营人数"
			)
			await _dispose_simulation(simulation)
		measured[strength] = float(successes) / float(maxi(attempts, 1))
		_check(attempts >= 20, "strength %d 有至少 20 次真实接触样本" % strength)
		_check(absf(float(measured[strength]) - _expected_rate(strength)) <= 0.14, "strength %d 观测感染率接近配置值" % strength)
		_check(conversion_signals == successes, "转换事件计数与感染成功结果一致")
	_check(float(measured.get(1, 1.0)) < float(measured.get(2, 0.0)), "strength 2 观测成功率高于 strength 1")
	_check(float(measured.get(2, 1.0)) < float(measured.get(3, 0.0)), "strength 3 观测成功率高于 strength 2")
	print("PB-05 strength contact rates=%s" % [measured])


func _test_birth_and_despawn(simulation_script: Script) -> void:
	var context: Dictionary = _create_simulation(simulation_script, 1, 13.0, 240.0, 160.0, 20261020, 1.0, 1.0, 0.05)
	var simulation: Node = context["simulation"]
	simulation.set("maximum_population", 2)
	simulation.set("initial_neutral_count", 1)
	var before_spawn_events: int = _unit_spawns.size()
	simulation.call("start_simulation")
	await get_tree().create_timer(1.3, true, true).timeout
	simulation.call("pause_simulation")
	_check(_unit_spawns.size() > before_spawn_events, "人口补充时发出出生事件")
	_check(not _unit_despawns.is_empty(), "自然寿命到期时发出离场事件")
	await _dispose_simulation(simulation)


func _create_simulation(
	simulation_script: Script,
	unit_count: int,
	radius: float,
	width: float,
	height: float,
	seed_value: int,
	lifespan_min: float = 120.0,
	lifespan_max: float = 120.0,
	spawn_interval: float = 0.75
) -> Dictionary:
	# 参数只配置本测试节点；棋子、播种和碰撞仍由 B 的公开入口处理。
	var simulation: Node = simulation_script.new() as Node
	get_tree().root.add_child(simulation)
	simulation.set("maximum_population", maxi(unit_count, 2))
	simulation.set("initial_neutral_count", unit_count)
	simulation.set("initial_seed_slot_count", 0)
	simulation.set("unit_collision_radius", radius)
	simulation.set("collision_cooldown_seconds", 0.7)
	simulation.set("base_speed_min", 52.0)
	simulation.set("base_speed_max", 52.0)
	simulation.set("maximum_speed", 78.0)
	simulation.set("lifespan_min_seconds", lifespan_min)
	simulation.set("lifespan_max_seconds", lifespan_max)
	simulation.set("neutral_spawn_interval_seconds", spawn_interval)
	_check(bool(simulation.call("set_type_counter_map", TYPE_COUNTERS)), "B 接受测试克制表")
	simulation.call("set_random_seed", seed_value)
	_check(bool(simulation.call("set_play_area", Rect2(Vector2.ZERO, Vector2(width, height)))), "B 接受固定测试场地")
	simulation.connect(&"contact_resolved", Callable(self, "_on_contact_resolved"))
	simulation.connect(&"unit_changed", Callable(self, "_on_unit_changed"))
	simulation.connect(&"unit_spawned", Callable(self, "_on_unit_spawned"))
	simulation.connect(&"unit_despawned", Callable(self, "_on_unit_despawned"))
	_contact_events.clear()
	_unit_changes.clear()
	_unit_spawns.clear()
	_unit_despawns.clear()
	var unit_ids: Array = simulation.call("create_population", unit_count, 0)
	return {"simulation": simulation, "unit_ids": unit_ids}


func _get_neutral_ids(host: Node) -> Array[String]:
	var result: Array[String] = []
	for snapshot_value: Variant in host.call("get_unit_snapshots"):
		var snapshot: Dictionary = snapshot_value as Dictionary
		if str(snapshot.get("team", "")) == "neutral":
			result.append(str(snapshot.get("unit_id", "")))
	return result


func _find_snapshot(source: Node, unit_id: Variant) -> Dictionary:
	for snapshot_value: Variant in source.call("get_unit_snapshots"):
		var snapshot: Dictionary = snapshot_value as Dictionary
		if str(snapshot.get("unit_id", "")) == str(unit_id):
			return snapshot
	return {}


func _matches_word_snapshot(snapshot: Dictionary, definition: Dictionary, expected_order: int) -> bool:
	return str(snapshot.get("word_id", "")) == str(definition.get("word_id", "")) \
		and str(snapshot.get("text", "")) == str(definition.get("text", "")) \
		and str(snapshot.get("battle_type", "")) == str(definition.get("battle_type", "")) \
		and int(snapshot.get("strength", 0)) == int(definition.get("strength", 0)) \
		and snapshot.get("traits", []) == definition.get("traits", []) \
		and str(snapshot.get("tendency", "")) == str(definition.get("tendency", "")) \
		and int(snapshot.get("word_order", 0)) == expected_order


func _find_word(words: Array, battle_type: String, strength: int) -> Dictionary:
	for word_value: Variant in words:
		var word: Dictionary = word_value as Dictionary
		if str(word.get("battle_type", "")) == battle_type and int(word.get("strength", 0)) == strength:
			return word
	return {}


func _find_word_of_type(words: Array, battle_type: String) -> Dictionary:
	for word_value: Variant in words:
		var word: Dictionary = word_value as Dictionary
		if str(word.get("battle_type", "")) == battle_type:
			return word
	return {}


func _find_strength_word(words: Array, strength: int) -> Dictionary:
	for word_value: Variant in words:
		var word: Dictionary = word_value as Dictionary
		if int(word.get("strength", 0)) == strength:
			return word
	return {}


func _find_method_node(node: Node, method_name: StringName) -> Node:
	if node.has_method(method_name):
		return node
	for child: Node in node.get_children():
		var found: Node = _find_method_node(child, method_name)
		if found != null:
			return found
	return null


func _has_contact_outcome(expected: StringName) -> bool:
	for event: Dictionary in _contact_events:
		if StringName(event.get("outcome", &"")) == expected:
			return true
	return false


func _on_contact_resolved(first_unit_id: int, second_unit_id: int, outcome: StringName) -> void:
	_contact_events.append({"first": first_unit_id, "second": second_unit_id, "outcome": outcome})


func _on_unit_changed(unit_id: int, reason: StringName) -> void:
	_unit_changes.append({"unit_id": unit_id, "reason": reason})


func _on_unit_spawned(unit_id: int) -> void:
	_unit_spawns.append(unit_id)


func _on_unit_despawned(unit_id: int) -> void:
	_unit_despawns.append(unit_id)


func _on_battle_ended(result: StringName) -> void:
	_battle_end_results.append(result)


func _dispose_simulation(simulation: Node) -> void:
	simulation.call("clear_population")
	simulation.queue_free()
	await get_tree().process_frame


func _expected_rate(strength: int) -> float:
	return [0.0, 0.20, 0.35, 0.50][strength]


func _near(actual: float, expected: float, tolerance: float = 0.0001) -> bool:
	return absf(actual - expected) <= tolerance


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS PB-05 public A/B/C interfaces, fixed-seed contact rules, infection rates, lifecycle events, and PK boundaries")
	else:
		for failure: String in _failures:
			push_error("FAIL PB-05: " + failure)
		get_tree().quit(1)
		return
	get_tree().quit(0)
