extends Node

const DEMO_SCENE: PackedScene = preload("res://scenes/plan_b/fermi_battle_demo.tscn")

var _failures: Array[String] = []
var _battle_end_results: Array[StringName] = []
var _counterattack_windups: Array[Dictionary] = []
var _counterattack_results: Array[Dictionary] = []
var _spawned_unit_count: int = 0


func _ready() -> void:
	_run()


func _run() -> void:
	var demo: Control = DEMO_SCENE.instantiate()
	add_child(demo)
	var host: PlanBBattleHost = demo.get_node("BattleHost")
	var simulation: PlanBUnitSimulation = demo.get_node("BattleHost/Simulation")
	host.battle_ended.connect(_on_battle_ended)
	host.counterattack_windup_started.connect(_on_counterattack_windup_started)
	host.counterattack_resolved.connect(_on_counterattack_resolved)
	simulation.unit_spawned.connect(_on_unit_spawned)
	simulation.set_random_seed(20261017)
	simulation.initial_neutral_count = 8
	simulation.initial_seed_slot_count = 2
	simulation.neutral_spawn_interval_seconds = 999.0
	simulation.lifespan_min_seconds = 120.0
	simulation.lifespan_max_seconds = 120.0
	host.initial_opponent_seed_count = 2
	host.opponent_auto_publish_enabled = false
	host.opponent_counterattack_enabled = false
	host.start_battle(Vector2(900.0, 490.0))

	var initial_counts: Dictionary = host.get_faction_counts()
	_check(int(initial_counts.get("player", 0)) == 0, "开局没有玩家信徒")
	_check(int(initial_counts.get("opponent", 0)) == 2, "A 将两个预留播种位初始化成费米对手")
	_check(int(initial_counts.get("neutral", 0)) == 8, "开局保留指定的8个中立样本")
	_check(host.get_used_word_ids().size() == 2, "开局对手占用两条话并提交两个顺序号")
	_check(is_equal_approx(host.get_pk(), 50.0), "开局 PK 为50%")
	_check(is_equal_approx(host.get_publish_cooldown_remaining("opponent"), 0.0), "开局播种不占用主动发言冷却")

	var neutral_ids: Array[int] = simulation.get_neutral_unit_ids()
	var player_words: Array[String] = host.get_available_word_ids("player")
	var opponent_words: Array[String] = host.get_available_word_ids("opponent")
	_check(player_words.size() >= 4, "C 提供足够的玩家候选话语")
	_check(opponent_words.size() >= 2, "C 在开局词语后仍提供主动发表候选")
	if neutral_ids.size() < 5 or player_words.size() < 4 or opponent_words.size() < 2:
		_finish()
		return

	var invalid_target: Dictionary = host.publish_legacy_seed_word("player", player_words[0], "missing_viewer")
	_check(not bool(invalid_target.get("ok", true)), "无效目标必须拒绝发表")
	_check(host.get_used_word_ids().size() == 2, "失败发表不能占用话语或顺序号")
	var first_publish: Dictionary = host.publish_legacy_seed_word("player", player_words[0], str(neutral_ids[0]))
	_check(bool(first_publish.get("ok", false)), "有效玩家发表应成功")
	_check(int(first_publish.get("word_order", 0)) == 3, "开局两条费米话后首条玩家话取得顺序3")
	var duplicate_word: Dictionary = host.publish_legacy_seed_word("player", player_words[0], str(neutral_ids[1]))
	_check(StringName(duplicate_word.get("reason", &"")) == &"word_already_used", "重复词应被拒绝")
	var player_cooldown: Dictionary = host.publish_legacy_seed_word("player", player_words[1], str(neutral_ids[1]))
	_check(StringName(player_cooldown.get("reason", &"")) == &"cooldown", "发表冷却期间应拒绝新词")
	_check(not host.get_used_word_ids().has(player_words[1]), "冷却失败不能占用话语")
	var player_counts: Dictionary = host.get_faction_counts()
	_check(int(player_counts.get("player", 0)) == 1, "成功发表只播种一名玩家棋子")
	_check(int(player_counts.get("opponent", 0)) == 2, "玩家播种不会改写对手数量")
	var pk_before_player_advantage: float = host.get_pk()
	host.update_pk(0.1)
	_check(host.get_pk() < pk_before_player_advantage, "玩家落后时PK应朝0%变化")

	host.update_battle(5.1)
	var player_retry: Dictionary = host.publish_legacy_seed_word("player", player_words[1], str(neutral_ids[1]))
	_check(bool(player_retry.get("ok", false)), "冷却结束后同一句话可以发表")
	_check(int(player_retry.get("word_order", 0)) == 4, "失败发表不占用全局顺序号")
	var equal_pk: float = host.get_pk()
	host.update_pk(5.0)
	_check(is_equal_approx(host.get_pk(), equal_pk), "玩家和费米人数相等时PK保持不变")

	host.update_battle(5.1)
	var player_third_publish: Dictionary = host.publish_legacy_seed_word("player", player_words[2], str(neutral_ids[2]))
	_check(bool(player_third_publish.get("ok", false)), "玩家冷却结束后可以继续发表")
	var pk_before_lead: float = host.get_pk()
	host.update_pk(0.1)
	_check(host.get_pk() > pk_before_lead, "玩家领先时PK应朝100%变化")

	var opponent_publish: Dictionary = host.publish_legacy_seed_word("opponent", opponent_words[0], str(neutral_ids[3]))
	_check(bool(opponent_publish.get("ok", false)), "费米主动发表复用同一个入口")
	_check(int(opponent_publish.get("word_order", 0)) == 6, "双方共用一个全局递增顺序号")
	var opponent_cooldown: Dictionary = host.publish_legacy_seed_word("opponent", opponent_words[1], str(neutral_ids[4]))
	_check(StringName(opponent_cooldown.get("reason", &"")) == &"cooldown", "费米同样受A层主动发言冷却约束")
	_check(not host.get_used_word_ids().has(opponent_words[1]), "费米冷却失败不能占用词语")
	host.update_battle(11.5)
	var opponent_retry: Dictionary = host.publish_legacy_seed_word("opponent", opponent_words[1], str(neutral_ids[4]))
	_check(bool(opponent_retry.get("ok", false)), "费米冷却结束后可发表新词")
	_check(int(opponent_retry.get("word_order", 0)) == 7, "失败费米请求不占用顺序号")

	host.pause_battle()
	var paused_publish: Dictionary = host.publish_legacy_seed_word("player", player_words[3], str(neutral_ids[5]))
	_check(StringName(paused_publish.get("reason", &"")) == &"battle_not_running", "暂停期间不能发表")
	_check(host.get_used_word_ids().size() == 7, "暂停失败发表不得改变已用词集合")

	_test_counterattack(demo, host, simulation)
	_test_terminal_boundaries(host, simulation)
	_finish()


func _test_counterattack(demo: Control, host: PlanBBattleHost, simulation: PlanBUnitSimulation) -> void:
	# 固定样本形成2人优势，C 的蓄力请求交给 B 后生成两个完整子体。
	simulation.initial_neutral_count = 10
	simulation.initial_seed_slot_count = 2
	simulation.neutral_spawn_interval_seconds = 999.0
	host.initial_opponent_seed_count = 2
	host.opponent_auto_publish_enabled = false
	host.opponent_counterattack_enabled = true
	host.restart_battle(Vector2(900.0, 490.0))
	var neutral_ids: Array[int] = simulation.get_neutral_unit_ids()
	var player_words: Array[String] = host.get_available_word_ids("player")
	if neutral_ids.size() < 4 or player_words.size() < 4:
		_check(false, "反击样本需要4名中立目标和4条玩家话语")
		return
	for index: int in range(4):
		if index > 0:
			host.update_battle(5.1)
		var result: Dictionary = host.publish_legacy_seed_word(
			"player", player_words[index], str(neutral_ids[index])
		)
		_check(bool(result.get("ok", false)), "反击样本中的玩家发表成功")
	host.update_battle(0.1)
	_check(not _counterattack_windups.is_empty(), "C 在玩家领先达到阈值时发出蓄力事实")
	var population_before_effect: int = host.get_unit_snapshots().size()
	var spawned_before_effect: int = _spawned_unit_count
	host.update_battle(1.3)
	_check(not _counterattack_results.is_empty(), "C 在前摇结束后发出反击结算事实")
	_check(bool(_counterattack_results.back().get("applied", false)), "A 将 split 请求交给 B 成功执行")
	_check(host.get_unit_snapshots().size() == population_before_effect + 2, "B 按 child_count 生成两个反击子体")
	_check(_spawned_unit_count == spawned_before_effect + 2, "反击子体通过 unit_spawned 发出事实")
	var phrase_counts_before: Dictionary = _word_counts_for_team(host.get_unit_snapshots(), "opponent")
	var split_phrase_inherited: bool = false
	for phrase_id: String in phrase_counts_before:
		if int(phrase_counts_before[phrase_id]) >= 3:
			split_phrase_inherited = true
	_check(split_phrase_inherited, "反击子体继承目标对手的完整当前话语快照")
	_check(demo.get_node_or_null("BattleHost") == host, "反击 smoke 使用正式 PB-01 组装场景")


func _test_terminal_boundaries(host: PlanBBattleHost, simulation: PlanBUnitSimulation) -> void:
	host.opponent_auto_publish_enabled = false
	host.opponent_counterattack_enabled = false
	host.initial_opponent_seed_count = 0
	simulation.initial_neutral_count = 1
	simulation.initial_seed_slot_count = 0
	host.restart_battle(Vector2(900.0, 490.0))
	var neutral_ids: Array[int] = simulation.get_neutral_unit_ids()
	var player_words: Array[String] = host.get_available_word_ids("player")
	var winning_publish: Dictionary = host.publish_legacy_seed_word("player", player_words[0], str(neutral_ids[0]))
	_check(int(winning_publish.get("word_order", 0)) == 1, "重开后全局顺序从1重新开始")
	host.update_pk(60.0)
	_check(is_equal_approx(host.get_pk(), 100.0), "PK应钳制在100%")
	_check(
		not _battle_end_results.is_empty() and _battle_end_results.back() == &"enter_contradiction",
		"PK到100%应发送进入矛盾阶段事实"
	)

	host.initial_opponent_seed_count = 1
	simulation.initial_neutral_count = 0
	simulation.initial_seed_slot_count = 1
	host.restart_battle(Vector2(900.0, 490.0))
	host.update_pk(60.0)
	_check(is_equal_approx(host.get_pk(), 0.0), "PK应钳制在0%")
	_check(_battle_end_results.back() == &"failed", "PK到0%应发送失败事实")


func _word_counts_for_team(snapshots: Array[Dictionary], team: String) -> Dictionary:
	var counts: Dictionary = {}
	for snapshot: Dictionary in snapshots:
		if String(snapshot.get("team", "")) != team:
			continue
		var word_id: String = String(snapshot.get("word_id", ""))
		counts[word_id] = int(counts.get(word_id, 0)) + 1
	return counts


func _finish() -> void:
	if _failures.is_empty():
		print("PASS PB-01: formal B/C/D assembly, initial seeds, publish, PK, counterattack, end boundaries")
	else:
		for failure: String in _failures:
			push_error("FAIL PB-01: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _on_battle_ended(result: StringName) -> void:
	_battle_end_results.append(result)


func _on_counterattack_windup_started(request: Dictionary) -> void:
	_counterattack_windups.append(request.duplicate(true))


func _on_counterattack_resolved(result: Dictionary) -> void:
	_counterattack_results.append(result.duplicate(true))


func _on_unit_spawned(_unit_id: int) -> void:
	_spawned_unit_count += 1

