class_name PlanBBattleHost
extends Node

## Plan B 普通战斗的编排与 PK 唯一所有者；不接入正式 Sandbox 的命中或回拉系统。

signal pk_changed(value: float)
signal tier_changed(current_tier: int)
signal battle_ended(result: StringName)
signal battle_state_changed(state: StringName)
signal publish_result(team: String, word_id: String, result: Dictionary)
signal player_hand_changed(hand: Array)
signal unit_changed(unit_id: String, reason: String)
signal unit_spawned(unit_id: String)
signal unit_despawned(unit_id: String)
signal counterattack_windup_started(request: Dictionary)
signal counterattack_resolved(result: Dictionary)

const TIER_CATALOG: Resource = preload("res://data/combat_stage/tier_catalog.tres")
const PLAYER_WORD_SLOT_COUNT: int = 3
const PLAYER_WORD_SLOT_REFILL_SECONDS: float = 5.0

@export_range(0.0, 5.0, 0.01) var pk_rate_pp_per_second: float = 0.85
@export_range(0.0, 60.0, 0.1) var player_publish_cooldown_seconds: float = 5.0
@export_range(0.0, 60.0, 0.1) var opponent_publish_cooldown_seconds: float = 11.5
@export_range(0, 8, 1) var initial_opponent_seed_count: int = 2
@export var available_level: String = "level_001"
@export var opponent_auto_publish_enabled: bool = true
@export var opponent_counterattack_enabled: bool = true

enum BattleState { IDLE, RUNNING, PAUSED, ENDED }

var _simulation: Node
var _word_catalog: Object
var _opponent_director: Object
var _tier_source: Callable
var _battle_state: int = BattleState.IDLE
var _battle_elapsed: float = 0.0
var _pk: float = 0.5
var _current_tier: int = 0
var _next_word_order: int = 1
var _used_word_ids: Array[String] = []
var _last_published_at: Dictionary = {"player": -1000000.0, "opponent": -1000000.0}
var _player_slot_refresh_remaining: Array[float] = [0.0, 0.0, 0.0]
var _player_slot_refresh_word_ids: Array[String] = ["", "", ""]
var _player_slot_definitions: Array[Dictionary] = [{}, {}, {}]
var _simulation_uses_integer_unit_ids: bool = false


func _ready() -> void:
	# Simulation 是场景中的 B 节点；C 的 RefCounted 模块由 A 的组装根注入。
	_simulation = get_node_or_null("Simulation")
	_bind_simulation_signals()


func configure_modules(simulation: Node, word_catalog: Object, opponent_director: Object) -> bool:
	# A 的组装根可注入 B/C 模块；运行中的战斗不允许改换状态拥有者。
	if _battle_state == BattleState.RUNNING or _battle_state == BattleState.PAUSED:
		return false
	if simulation != null and simulation != _simulation:
		_disconnect_simulation_signals()
		_simulation = simulation
		_bind_simulation_signals()
	if word_catalog != null:
		_word_catalog = word_catalog
		if not _load_word_catalog():
			return false
	if opponent_director != null:
		_disconnect_opponent_signal()
		_opponent_director = opponent_director
		_bind_opponent_signal()
	_configure_simulation_type_matchups()
	if not _configure_opponent_director():
		return false
	_configure_counterattack_effect_handler()
	return true


func start_battle(arena_size: Vector2, arena_origin: Vector2 = Vector2.ZERO) -> void:
	# 新开和重开统一重置顺序、冷却、PK、Tier 与棋子人口。
	if _simulation == null:
		push_error("PlanBBattleHost 缺少 Simulation 模块。")
		return
	_battle_state = BattleState.IDLE
	_battle_elapsed = 0.0
	_pk = 0.5
	_current_tier = 0
	_next_word_order = 1
	_used_word_ids.clear()
	_last_published_at = {"player": -1000000.0, "opponent": -1000000.0}
	for slot_id: int in PLAYER_WORD_SLOT_COUNT:
		_player_slot_refresh_remaining[slot_id] = 0.0
		_player_slot_refresh_word_ids[slot_id] = ""
		_player_slot_definitions[slot_id] = {}
	_configure_simulation_type_matchups()
	if not _configure_opponent_director():
		push_error("PlanBBattleHost 无法配置费米发言模块。")
		return
	_configure_counterattack_effect_handler()
	var created_ids: Array = _create_population(arena_size, arena_origin)
	_update_simulation_unit_id_kind()
	if not _seed_initial_opponents(created_ids):
		_simulation.call("clear_battle")
		_used_word_ids.clear()
		_next_word_order = 1
		_simulation_uses_integer_unit_ids = false
		push_error("PlanBBattleHost 无法完整播种开局费米棋子；本局未启动。")
		return
	if _simulation.has_method("start_simulation"):
		_simulation.call("start_simulation")
	else:
		_simulation.call("set_active", true)
	_battle_state = BattleState.RUNNING
	_reset_player_hand_slots()
	if _opponent_director != null and _opponent_director.has_method("set_spawn_area"):
		_opponent_director.call("set_spawn_area", Rect2(arena_origin, arena_size))
	battle_state_changed.emit(&"running")
	pk_changed.emit(get_pk())
	if not _tier_source.is_valid():
		tier_changed.emit(_current_tier)


func pause_battle() -> void:
	if _battle_state != BattleState.RUNNING:
		return
	_battle_state = BattleState.PAUSED
	_simulation.call("set_active", false)
	battle_state_changed.emit(&"paused")


func resume_battle() -> void:
	if _battle_state != BattleState.PAUSED:
		return
	_battle_state = BattleState.RUNNING
	_simulation.call("set_active", true)
	battle_state_changed.emit(&"running")


func restart_battle(arena_size: Vector2, arena_origin: Vector2 = Vector2.ZERO) -> void:
	start_battle(arena_size, arena_origin)


func end_battle(result: StringName) -> void:
	# 结束状态只提交一次，0% 与100%分别由 PK 采样交出事实。
	if _battle_state == BattleState.ENDED:
		return
	_battle_state = BattleState.ENDED
	_simulation.call("set_active", false)
	battle_state_changed.emit(&"ended")
	battle_ended.emit(result)


func get_pk() -> float:
	# 公共值使用0到100的百分点，和PB-04 HUD一致；阈值计算继续使用内部比例。
	return _pk * 100.0


## 给旧关卡 Flow / HitResolution 提供0～1只读视图，普通 PK 仍由本 Host 唯一持有。
func get_pk_fraction() -> float:
	return _pk


func get_faction_counts() -> Dictionary:
	# 转发模拟模块的只读事实，PK 和 HUD 都从同一棋子计数采样。
	return {} if _simulation == null else _simulation.call("get_faction_counts")


func get_unit_snapshots() -> Array[Dictionary]:
	return [] if _simulation == null else _simulation.call("get_unit_snapshots")


func get_neutral_unit_at(scene_position: Vector2) -> Variant:
	# B 以实际场景坐标命中；无目标时统一转换为空 ID 供输入层提示。
	if _simulation == null:
		return ""
	var unit_id: Variant = _simulation.call("get_neutral_unit_at", scene_position)
	if unit_id is int and int(unit_id) < 0:
		return ""
	return unit_id


func get_current_tier() -> int:
	# 正式 Sandbox 由旧 CombatStage 持有 Tier；独立 PB-01 场景使用本地表驱动值。
	if _tier_source.is_valid():
		return int(_tier_source.call())
	return _current_tier


func set_tier_source(source: Callable) -> bool:
	# Tier 阈值与升降档演出归正式 CombatStage；Host 只转发其显示事实。
	if not source.is_valid():
		return false
	_tier_source = source
	return true


func notify_external_tier_changed(current_tier: int) -> void:
	if _tier_source.is_valid():
		tier_changed.emit(current_tier)


func get_battle_state() -> StringName:
	match _battle_state:
		BattleState.RUNNING:
			return &"running"
		BattleState.PAUSED:
			return &"paused"
		BattleState.ENDED:
			return &"ended"
		_:
			return &"idle"


func get_used_word_ids() -> Array[String]:
	return _used_word_ids.duplicate()


func get_available_word_ids(team: String) -> Array[String]:
	if _word_catalog == null or not _word_catalog.has_method("get_available_word_ids"):
		return []
	return _word_catalog.call("get_available_word_ids", team, _used_word_ids, available_level)


func get_word_definitions(team: String) -> Array[Dictionary]:
	# 给 PB-04 一次性读取当前关卡词条；去重状态仍只由 A 保存。
	var word_ids: Array[String] = []
	if _word_catalog == null:
		return []
	if _word_catalog.has_method("get_word_ids"):
		word_ids = _word_catalog.call("get_word_ids", available_level, team)
	else:
		word_ids = _word_catalog.call("get_available_word_ids", team, [], available_level)
	var definitions: Array[Dictionary] = []
	for word_id: String in word_ids:
		var definition: Dictionary = get_word_definition(word_id)
		if not definition.is_empty():
			definitions.append(definition)
	return definitions


func get_word_definition(word_id: String) -> Dictionary:
	if _word_catalog == null or not _word_catalog.has_method("get_word_definition"):
		return {}
	return _word_catalog.call("get_word_definition", word_id)


func get_publish_cooldown_remaining(team: String) -> float:
	if team != "player" and team != "opponent":
		return 0.0
	if team == "player":
		return 0.0
	var cooldown: float = opponent_publish_cooldown_seconds
	var elapsed_since_publish: float = _battle_elapsed - float(_last_published_at.get(team, -1000000.0))
	return maxf(cooldown - elapsed_since_publish, 0.0)


## A 持有三个当前卡槽事实；C 只提供无状态随机候选。
func get_player_hand() -> Array[Dictionary]:
	var hand: Array[Dictionary] = []
	for slot_id: int in PLAYER_WORD_SLOT_COUNT:
		var source_definition: Dictionary = _player_slot_definitions[slot_id]
		var definition: Dictionary = source_definition.duplicate(true)
		if definition.is_empty():
			definition = {"word_id": "", "text": "", "strength": 0, "battle_type": ""}
		definition["slot_id"] = slot_id
		hand.append(definition)
	return hand


func get_player_slot_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = []
	for slot_id: int in PLAYER_WORD_SLOT_COUNT:
		var word_id: String = str(_player_slot_definitions[slot_id].get("word_id", ""))
		var remaining: float = _player_slot_refresh_remaining[slot_id]
		states.append({
			"slot_id": slot_id,
			"word_id": word_id,
			"remaining": remaining,
			"progress": clampf(1.0 - remaining / PLAYER_WORD_SLOT_REFILL_SECONDS, 0.0, 1.0),
			"available": not word_id.is_empty() and remaining <= 0.0 and not _used_word_ids.has(word_id),
			"cooling_word_id": _player_slot_refresh_word_ids[slot_id],
		})
	return states


## 每次尝试从 C 的无状态抽牌入口固定填充三个独立槽位。
func _reset_player_hand_slots() -> void:
	var occupied_word_ids: Array[String] = []
	for slot_id: int in PLAYER_WORD_SLOT_COUNT:
		var definition: Dictionary = _draw_player_word_candidate(occupied_word_ids)
		_player_slot_definitions[slot_id] = definition
		var word_id: String = str(definition.get("word_id", ""))
		if not word_id.is_empty():
			occupied_word_ids.append(word_id)
	player_hand_changed.emit(get_player_hand())


## C 每次只返回一个候选；当前槽和其他槽的状态由 A 持有。
func _draw_player_word_candidate(occupied_word_ids: Array[String]) -> Dictionary:
	if _word_catalog == null:
		return {}
	if _word_catalog.has_method("draw_player_speech_word"):
		var candidate: Variant = _word_catalog.call(
			"draw_player_speech_word", _used_word_ids, occupied_word_ids, available_level
		)
		return candidate.duplicate(true) if candidate is Dictionary else {}
	if _word_catalog.has_method("get_available_word_ids"):
		var candidates: Variant = _word_catalog.call(
			"get_available_word_ids", "player", _used_word_ids, available_level
		)
		if not candidates is Array:
			return {}
		for value: Variant in candidates:
			var word_id: String = str(value)
			if occupied_word_ids.has(word_id):
				continue
			return get_word_definition(word_id)
	return {}


func _get_player_slot_state(slot_id: int) -> Dictionary:
	for state: Dictionary in get_player_slot_states():
		if int(state.get("slot_id", -1)) == slot_id:
			return state
	return {}


func publish_word(team: String, word_id: String, spawn_position: Vector2, slot_id: int = -1) -> Dictionary:
	# 正式发表只接受棋盘全局坐标；B 要么创建完整批次，要么返回失败且不消费发表事实。
	return _publish_word_batch(team, word_id, spawn_position, slot_id)


## 仅供 PB-01 / PB-05 旧主机夹具继续覆盖单颗播种，不用于正式 Sandbox 流程。
func publish_legacy_seed_word(team: String, word_id: String, neutral_unit_id: Variant) -> Dictionary:
	return _publish_word_to_legacy_target(team, word_id, neutral_unit_id)


func _publish_word_batch(team: String, word_id: String, spawn_position: Vector2, slot_id: int) -> Dictionary:
	# B 确认完整批次创建后，A 才提交去重、冷却与顺序号。
	var failure: Dictionary = {"ok": false, "reason": &"invalid_request"}
	if _battle_state != BattleState.RUNNING:
		failure["reason"] = &"battle_not_running"
		return _report_publish_result(team, word_id, failure)
	if team != "player" and team != "opponent":
		failure["reason"] = &"invalid_team"
		return _report_publish_result(team, word_id, failure)
	var definition: Dictionary = get_word_definition(word_id)
	if definition.is_empty():
		failure["reason"] = &"unknown_word"
		return _report_publish_result(team, word_id, failure)
	if _used_word_ids.has(word_id):
		failure["reason"] = &"word_already_used"
		return _report_publish_result(team, word_id, failure)
	if team == "player":
		var slot_state: Dictionary = _get_player_slot_state(slot_id)
		if slot_state.is_empty():
			failure["reason"] = &"invalid_slot"
			return _report_publish_result(team, word_id, failure)
		if str(slot_state.get("word_id", "")) != word_id:
			failure["reason"] = &"slot_word_mismatch"
			return _report_publish_result(team, word_id, failure)
		if not bool(slot_state.get("available", false)):
			failure["reason"] = &"slot_cooldown"
			failure["cooldown_remaining"] = float(slot_state.get("remaining", 0.0))
			return _report_publish_result(team, word_id, failure)
	else:
		var cooldown_remaining: float = get_publish_cooldown_remaining(team)
		if cooldown_remaining > 0.0:
			failure["reason"] = &"cooldown"
			failure["cooldown_remaining"] = cooldown_remaining
			return _report_publish_result(team, word_id, failure)
	if _simulation == null or not _simulation.has_method("spawn_word_batch"):
		failure["reason"] = &"batch_unavailable"
		return _report_publish_result(team, word_id, failure)
	var spawn_count: int = 0
	if _word_catalog != null and _word_catalog.has_method("get_strength_batch_spawn_count"):
		spawn_count = int(_word_catalog.call("get_strength_batch_spawn_count", int(definition.get("strength", 0))))
	else:
		spawn_count = {1: 2, 2: 4, 3: 8}.get(int(definition.get("strength", 0)), 0)
	if spawn_count <= 0:
		failure["reason"] = &"invalid_strength"
		return _report_publish_result(team, word_id, failure)
	var candidate_order: int = _next_word_order
	var batch_result: Dictionary = _simulation.call(
		"spawn_word_batch", spawn_position, StringName(team), definition, candidate_order, spawn_count
	)
	var batch_unit_ids_value: Variant = batch_result.get("unit_ids", [])
	var batch_unit_ids: Array = batch_unit_ids_value if batch_unit_ids_value is Array else []
	var batch_count: int = int(batch_result.get("count", batch_unit_ids.size()))
	if not bool(batch_result.get("ok", false)):
		failure["reason"] = StringName(str(batch_result.get("reason", "batch_failed")))
		failure["spawn_count"] = spawn_count
		return _report_publish_result(team, word_id, failure)
	if batch_count != spawn_count or batch_unit_ids.size() != spawn_count:
		failure["reason"] = &"incomplete_batch"
		failure["spawn_count"] = spawn_count
		return _report_publish_result(team, word_id, failure)
	_used_word_ids.append(word_id)
	if team == "player":
		_player_slot_refresh_remaining[slot_id] = PLAYER_WORD_SLOT_REFILL_SECONDS
		_player_slot_refresh_word_ids[slot_id] = word_id
	else:
		_last_published_at[team] = _battle_elapsed
	_next_word_order += 1
	var success: Dictionary = {
		"ok": true,
		"reason": &"published",
		"word_order": candidate_order,
		"spawn_count": spawn_count,
		"spawn_position": spawn_position,
		"slot_id": slot_id,
		"unit_ids": batch_unit_ids.duplicate(),
		"spawn_target_positions": batch_result.get("spawn_target_positions", []).duplicate(),
		"batch": batch_result.duplicate(true),
	}
	return _report_publish_result(team, word_id, success)


func _publish_word_to_legacy_target(team: String, word_id: String, neutral_unit_id: Variant) -> Dictionary:
	# 仅为旧 PB-01 主机夹具保留原子单颗入口；正式 PB-06 UI 始终提交 Vector2 坐标。
	var failure: Dictionary = {"ok": false, "reason": &"invalid_request"}
	if _battle_state != BattleState.RUNNING:
		failure["reason"] = &"battle_not_running"
		return _report_publish_result(team, word_id, failure)
	if team != "player" and team != "opponent":
		failure["reason"] = &"invalid_team"
		return _report_publish_result(team, word_id, failure)
	var definition: Dictionary = get_word_definition(word_id)
	if definition.is_empty():
		failure["reason"] = &"unknown_word"
		return _report_publish_result(team, word_id, failure)
	if _used_word_ids.has(word_id):
		failure["reason"] = &"word_already_used"
		return _report_publish_result(team, word_id, failure)
	var cooldown_remaining: float = _get_legacy_publish_cooldown_remaining(team)
	if cooldown_remaining > 0.0:
		failure["reason"] = &"cooldown"
		failure["cooldown_remaining"] = cooldown_remaining
		return _report_publish_result(team, word_id, failure)
	var target_id: Variant = _normalize_unit_id(neutral_unit_id)
	var target: Dictionary = _simulation.call("get_unit_snapshot", target_id)
	if target.is_empty() or String(target.get("team", "")) != "neutral":
		failure["reason"] = &"invalid_target"
		return _report_publish_result(team, word_id, failure)
	var candidate_order: int = _next_word_order
	if not bool(_simulation.call("seed_unit", target_id, StringName(team), definition, candidate_order)):
		failure["reason"] = &"seed_failed"
		return _report_publish_result(team, word_id, failure)
	_used_word_ids.append(word_id)
	_last_published_at[team] = _battle_elapsed
	_next_word_order += 1
	return _report_publish_result(team, word_id, {
		"ok": true,
		"reason": &"published",
		"word_order": candidate_order,
		"spawn_count": 1,
		"unit_ids": [target_id],
	})


func update_pk(delta: float) -> void:
	# PK 只按模拟模块真实棋子人数和经过时间变化；相等人数时变化量为零。
	if _battle_state != BattleState.RUNNING or delta <= 0.0:
		return
	var counts: Dictionary = _simulation.call("get_faction_counts")
	var total_count: int = int(counts.get("player", 0)) + int(counts.get("opponent", 0)) + int(counts.get("neutral", 0))
	if total_count <= 0:
		return
	var player_difference: float = float(int(counts.get("player", 0)) - int(counts.get("opponent", 0)))
	var change_ratio: float = pk_rate_pp_per_second * player_difference / float(total_count) * delta / 100.0
	var updated_pk: float = clampf(_pk + change_ratio, 0.0, 1.0)
	if not is_equal_approx(updated_pk, _pk):
		_pk = updated_pk
		_update_tier()
		pk_changed.emit(get_pk())
	if _pk <= 0.0:
		end_battle(&"failed")
	elif _pk >= 1.0:
		end_battle(&"enter_contradiction")


func update_battle(delta: float) -> void:
	# A 先结算实际人口 PK；战斗结束帧不再发话或启动反击。
	if _battle_state != BattleState.RUNNING or delta <= 0.0:
		return
	_battle_elapsed += delta
	update_pk(delta)
	if _battle_state != BattleState.RUNNING:
		return
	_update_player_slot_refills(delta)
	if opponent_auto_publish_enabled:
		_update_opponent_speech(delta)
	if opponent_counterattack_enabled:
		_update_opponent_counterattack(delta)


func _process(delta: float) -> void:
	update_battle(delta)


## 只在运行战斗期间推进玩家各自的补牌计时；替换词仍由 C 从可用池抽取。
func _update_player_slot_refills(delta: float) -> void:
	if _word_catalog == null or not _word_catalog.has_method("draw_player_speech_word"):
		return
	for slot_id: int in PLAYER_WORD_SLOT_COUNT:
		if _player_slot_refresh_remaining[slot_id] <= 0.0:
			continue
		_player_slot_refresh_remaining[slot_id] = maxf(
			0.0, _player_slot_refresh_remaining[slot_id] - maxf(delta, 0.0)
		)
		if _player_slot_refresh_remaining[slot_id] > 0.0:
			continue
		var expected_word_id: String = _player_slot_refresh_word_ids[slot_id]
		if expected_word_id.is_empty():
			continue
		if str(_player_slot_definitions[slot_id].get("word_id", "")) != expected_word_id:
			_player_slot_refresh_word_ids[slot_id] = ""
			continue
		var occupied_word_ids: Array[String] = []
		for other_slot_id: int in PLAYER_WORD_SLOT_COUNT:
			if other_slot_id == slot_id:
				continue
			var occupied_word_id: String = str(_player_slot_definitions[other_slot_id].get("word_id", ""))
			if not occupied_word_id.is_empty():
				occupied_word_ids.append(occupied_word_id)
		_player_slot_definitions[slot_id] = _draw_player_word_candidate(occupied_word_ids)
		_player_slot_refresh_word_ids[slot_id] = ""
		player_hand_changed.emit(get_player_hand())


func _get_legacy_publish_cooldown_remaining(team: String) -> float:
	if team != "player" and team != "opponent":
		return 0.0
	var cooldown: float = player_publish_cooldown_seconds if team == "player" else opponent_publish_cooldown_seconds
	var elapsed_since_publish: float = _battle_elapsed - float(_last_published_at.get(team, -1000000.0))
	return maxf(cooldown - elapsed_since_publish, 0.0)


func _update_tier() -> void:
	# 阈值取现有 Tier Catalog（由08表导入），只提供临时展示，不触发正式阶段演出。
	if _tier_source.is_valid():
		return
	var tier: int = _current_tier
	while tier < 5:
		var current_config: Resource = TIER_CATALOG.call("get_tier_config", tier)
		if current_config == null or _pk < float(current_config.get("upgrade_threshold")):
			break
		tier += 1
	while tier > 0:
		var tier_config: Resource = TIER_CATALOG.call("get_tier_config", tier)
		if tier_config == null or _pk >= float(tier_config.get("downgrade_threshold")):
			break
		tier -= 1
	if tier == _current_tier:
		return
	_current_tier = tier
	tier_changed.emit(_current_tier)


func _create_population(arena_size: Vector2, arena_origin: Vector2) -> Array:
	# B 创建时保持所有 seed slot 中立；A 负责选两条费米初始话并播种。
	if _simulation.has_method("clear_battle"):
		_simulation.call("clear_battle")
	if _simulation.has_method("set_play_area"):
		if not bool(_simulation.call("set_play_area", Rect2(arena_origin, arena_size))):
			return []
	if not _simulation.has_method("create_population"):
		return []
	var created_ids: Variant = _simulation.call("create_population", -1, initial_opponent_seed_count)
	return created_ids if created_ids is Array else []


func _seed_initial_opponents(created_ids: Array) -> bool:
	# 开局播种消耗两条话和两个顺序号，不启动对手主动发言冷却。
	if initial_opponent_seed_count <= 0:
		return true
	if created_ids.size() < initial_opponent_seed_count:
		return false
	var candidate_word_ids: Array[String] = get_available_word_ids("opponent")
	if candidate_word_ids.size() < initial_opponent_seed_count:
		return false
	var committed_seeds: Array[Dictionary] = []
	for seed_index: int in range(initial_opponent_seed_count):
		var word_id: String = candidate_word_ids[seed_index]
		var definition: Dictionary = get_word_definition(word_id)
		var unit_id: Variant = _normalize_unit_id(created_ids[seed_index])
		var target: Dictionary = _simulation.call("get_unit_snapshot", unit_id)
		if definition.is_empty() or String(target.get("team", "")) != "neutral":
			return false
		var candidate_order: int = _next_word_order + seed_index
		if not bool(_simulation.call("seed_unit", unit_id, StringName("opponent"), definition, candidate_order)):
			return false
		committed_seeds.append({"word_id": word_id, "word_order": candidate_order})
	for initial_seed: Dictionary in committed_seeds:
		_used_word_ids.append(String(initial_seed["word_id"]))
	_next_word_order += committed_seeds.size()
	return true


func _update_opponent_speech(delta: float) -> void:
	if _opponent_director == null or not _opponent_director.has_method("update_speech"):
		return
	var neutral_snapshots: Array[Dictionary] = []
	for snapshot: Dictionary in get_unit_snapshots():
		if String(snapshot.get("team", "")) == "neutral":
			neutral_snapshots.append(snapshot)
	_opponent_director.call(
		"update_speech", delta, neutral_snapshots, get_available_word_ids("opponent")
	)


func _update_opponent_counterattack(delta: float) -> void:
	if _opponent_director == null or not _opponent_director.has_method("update_counterattack"):
		return
	var opponent_snapshots: Array[Dictionary] = []
	for snapshot: Dictionary in get_unit_snapshots():
		if String(snapshot.get("team", "")) == "opponent":
			opponent_snapshots.append(snapshot)
	_opponent_director.call("update_counterattack", delta, get_faction_counts(), opponent_snapshots)


func _load_word_catalog() -> bool:
	if _word_catalog != null and _word_catalog.has_method("load_test_configuration"):
		return bool(_word_catalog.call("load_test_configuration"))
	return _word_catalog != null


func _configure_opponent_director() -> bool:
	if _opponent_director == null:
		return false
	if _opponent_director.has_method("configure"):
		return bool(_opponent_director.call("configure", _word_catalog, 20261017))
	if _opponent_director.has_method("reset"):
		_opponent_director.call("reset")
	return true


func _configure_counterattack_effect_handler() -> void:
	# C 只产生命令，请求效果的执行权由 A 委派给 B 的公开入口。
	if _opponent_director == null or not _opponent_director.has_method("set_counterattack_effect_handler"):
		return
	var effect_handler := Callable()
	if _simulation != null and _simulation.has_method("apply_counterattack_effect"):
		effect_handler = Callable(self, "_apply_counterattack_effect")
	_opponent_director.call("set_counterattack_effect_handler", effect_handler)


func _configure_simulation_type_matchups() -> void:
	# 正式原型中 C 提供唯一属性关系表，A 注入 B；临时模拟器使用本地候选表。
	if _simulation == null or _word_catalog == null \
		or not _simulation.has_method("set_type_counter_map") \
		or not _word_catalog.has_method("get_type_matchup"):
		return
	var battle_types: Array[String] = []
	for team: String in ["player", "opponent"]:
		for definition: Dictionary in get_word_definitions(team):
			var battle_type: String = str(definition.get("battle_type", ""))
			if not battle_type.is_empty() and not battle_types.has(battle_type):
				battle_types.append(battle_type)
	var counter_map: Dictionary = {}
	for attacker_type: String in battle_types:
		for defender_type: String in battle_types:
			if attacker_type == defender_type:
				continue
			var relation: StringName = StringName(
				_word_catalog.call("get_type_matchup", attacker_type, defender_type)
			)
			if relation == &"advantage":
				counter_map[attacker_type] = defender_type
				break
	if not counter_map.is_empty():
		_simulation.call("set_type_counter_map", counter_map)


func _bind_simulation_signals() -> void:
	if _simulation == null:
		return
	_connect_signal(_simulation, &"unit_changed", Callable(self, "_on_unit_changed"))
	_connect_signal(_simulation, &"unit_spawned", Callable(self, "_on_unit_spawned"))
	_connect_signal(_simulation, &"unit_despawned", Callable(self, "_on_unit_despawned"))


func _disconnect_simulation_signals() -> void:
	if _simulation == null:
		return
	_disconnect_signal(_simulation, &"unit_changed", Callable(self, "_on_unit_changed"))
	_disconnect_signal(_simulation, &"unit_spawned", Callable(self, "_on_unit_spawned"))
	_disconnect_signal(_simulation, &"unit_despawned", Callable(self, "_on_unit_despawned"))


func _bind_opponent_signal() -> void:
	_connect_signal(_opponent_director, &"publish_word_requested", Callable(self, "_on_opponent_publish_requested"))
	_connect_signal(_opponent_director, &"counterattack_windup_started", Callable(self, "_on_counterattack_windup_started"))
	_connect_signal(_opponent_director, &"counterattack_effect_requested", Callable(self, "_on_counterattack_effect_requested"))
	_connect_signal(_opponent_director, &"counterattack_resolved", Callable(self, "_on_counterattack_resolved"))


func _disconnect_opponent_signal() -> void:
	_disconnect_signal(
		_opponent_director, &"publish_word_requested", Callable(self, "_on_opponent_publish_requested")
	)
	_disconnect_signal(
		_opponent_director, &"counterattack_windup_started", Callable(self, "_on_counterattack_windup_started")
	)
	_disconnect_signal(
		_opponent_director, &"counterattack_effect_requested", Callable(self, "_on_counterattack_effect_requested")
	)
	_disconnect_signal(
		_opponent_director, &"counterattack_resolved", Callable(self, "_on_counterattack_resolved")
	)


func _connect_signal(source: Object, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)


func _disconnect_signal(source: Object, signal_name: StringName, callback: Callable) -> void:
	if source != null and source.has_signal(signal_name) and source.is_connected(signal_name, callback):
		source.disconnect(signal_name, callback)


func _normalize_unit_id(unit_id: Variant) -> Variant:
	if unit_id is int or not _simulation_uses_integer_unit_ids:
		return unit_id
	var unit_id_text: String = str(unit_id)
	return int(unit_id_text) if unit_id_text.is_valid_int() else -1


func _update_simulation_unit_id_kind() -> void:
	_simulation_uses_integer_unit_ids = false
	var snapshots: Array[Dictionary] = get_unit_snapshots()
	if not snapshots.is_empty():
		_simulation_uses_integer_unit_ids = snapshots[0].get("unit_id") is int


func _report_publish_result(team: String, word_id: String, result: Dictionary) -> Dictionary:
	publish_result.emit(team, word_id, result.duplicate(true))
	return result


func _on_opponent_publish_requested(word_id: String, spawn_position: Vector2) -> void:
	# C 给出棋盘坐标；A 通过同一事务回报成功与否，供 C 决定是否启动 AI 冷却。
	var result: Dictionary = publish_word("opponent", word_id, spawn_position)
	if _opponent_director != null and _opponent_director.has_method("report_speech_publish_result"):
		_opponent_director.call("report_speech_publish_result", word_id, bool(result.get("ok", false)))


func _on_counterattack_windup_started(request: Dictionary) -> void:
	counterattack_windup_started.emit(request.duplicate(true))


func _on_counterattack_effect_requested(request: Dictionary) -> void:
	# 没有可注入 Callable 时仍由 A 接收 C 的请求并转调 B，再回报 C。
	var applied: bool = _apply_counterattack_effect(request)
	if _opponent_director != null and _opponent_director.has_method("report_counterattack_result"):
		_opponent_director.call("report_counterattack_result", applied)


func _apply_counterattack_effect(request: Dictionary) -> bool:
	# C 的控制器不直接修改 B；A 将效果请求交给模拟模块公开入口。
	if _simulation == null or not _simulation.has_method("apply_counterattack_effect"):
		return false
	return bool(_simulation.call("apply_counterattack_effect", request))


func _on_counterattack_resolved(result: Dictionary) -> void:
	counterattack_resolved.emit(result.duplicate(true))


func _on_unit_changed(unit_id: Variant, reason: StringName) -> void:
	unit_changed.emit(str(unit_id), str(reason))


func _on_unit_spawned(unit_id: Variant) -> void:
	unit_spawned.emit(str(unit_id))


func _on_unit_despawned(unit_id: Variant) -> void:
	unit_despawned.emit(str(unit_id))
