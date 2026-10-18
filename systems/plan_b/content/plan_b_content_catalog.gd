class_name PlanBContentCatalog
extends RefCounted

const WORD_POOL_PATH := "res://data/plan_b/word_pool.csv"
const TYPE_MATCHUPS_PATH := "res://data/plan_b/battle_type_matchups.csv"
const STRENGTH_RATES_PATH := "res://data/plan_b/strength_success_rates.csv"
const OPPONENT_CONFIG_PATH := "res://data/plan_b/opponent_config.csv"
const RETALIATION_MAP_PATH := "res://data/plan_b/retaliation_skill_map.csv"
const DEFAULT_LEVEL_ID := "level_001"
const DEFAULT_RANDOM_SEED := 20261017
const LEVEL_PROFILE_PATHS := {
	"level_001": "res://data/level_configuration/level_001.tres",
	"level_002": "res://data/level_configuration/level_002.tres",
	"level_003": "res://data/level_configuration/level_003.tres",
	"level_004": "res://data/level_configuration/level_004.tres",
}

const LEGACY_TENDENCIES := [&"orthodox", &"heresy", &"absurd", &"neutral"]

var _word_definitions: Dictionary = {}
var _word_ids_in_source_order: Array[String] = []
var _type_relations: Dictionary = {}
var _strength_probabilities: Dictionary = {}
var _strength_batch_spawn_counts: Dictionary = {}
var _opponent_configs: Dictionary = {}
var _retaliation_mappings: Array[Dictionary] = []
var _active_level_context: Dictionary = {}
var _random_seed: int = DEFAULT_RANDOM_SEED
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _loaded: bool = false


## 读取正式来源词句与 Plan B 临时战斗映射；测试词不得混入正式词池。
func load_configuration() -> bool:
	_loaded = false
	_word_definitions.clear()
	_word_ids_in_source_order.clear()
	_type_relations.clear()
	_strength_probabilities.clear()
	_strength_batch_spawn_counts.clear()
	_opponent_configs.clear()
	_retaliation_mappings.clear()
	_active_level_context.clear()

	var raw_matchups: Array[Dictionary] = _read_csv_rows(TYPE_MATCHUPS_PATH)
	var raw_strengths: Array[Dictionary] = _read_csv_rows(STRENGTH_RATES_PATH)
	var raw_words: Array[Dictionary] = _read_csv_rows(WORD_POOL_PATH)
	var raw_opponents: Array[Dictionary] = _read_csv_rows(OPPONENT_CONFIG_PATH)
	var raw_retaliations: Array[Dictionary] = _read_csv_rows(RETALIATION_MAP_PATH)
	if raw_matchups.is_empty() or raw_strengths.is_empty() or raw_words.is_empty() \
		or raw_opponents.is_empty() or raw_retaliations.is_empty():
		return false

	for row: Dictionary in raw_matchups:
		var attacker: String = str(row.get("attacker_type", "")).strip_edges()
		var defender: String = str(row.get("defender_type", "")).strip_edges()
		var relation: String = str(row.get("relation", "")).strip_edges()
		if attacker.is_empty() or defender.is_empty() or relation not in ["same", "advantage", "disadvantage"]:
			return false
		var relation_key := _make_matchup_key(attacker, defender)
		if _type_relations.has(relation_key):
			return false
		_type_relations[relation_key] = StringName(relation)
	if not _has_complete_matchup_table():
		return false

	for row: Dictionary in raw_strengths:
		var strength_text: String = str(row.get("strength", "")).strip_edges()
		var chance_text: String = str(row.get("conversion_probability", "")).strip_edges()
		var batch_count_text: String = str(row.get("batch_spawn_count", "")).strip_edges()
		if not strength_text.is_valid_int() or not chance_text.is_valid_float() \
			or not batch_count_text.is_valid_int():
			return false
		var strength: int = int(strength_text)
		var chance: float = float(chance_text)
		var batch_count: int = int(batch_count_text)
		if strength < 1 or strength > 3 or chance < 0.0 or chance > 1.0 \
			or batch_count < 1 or batch_count > 8 \
			or _strength_probabilities.has(strength) or _strength_batch_spawn_counts.has(strength):
			return false
		_strength_probabilities[strength] = chance
		_strength_batch_spawn_counts[strength] = batch_count
	if _strength_probabilities.size() != 3 or _strength_batch_spawn_counts.size() != 3:
		return false

	for row: Dictionary in raw_words:
		if not _has_required_word_fields(row):
			return false
		var word_id: String = str(row.get("word_id", "")).strip_edges()
		var text: String = str(row.get("text", ""))
		var battle_type: String = str(row.get("battle_type", "")).strip_edges()
		var strength_text: String = str(row.get("strength", "")).strip_edges()
		var source_tendency := StringName(str(row.get("tendency", "")).strip_edges())
		var tendency := _normalize_tendency_id(source_tendency)
		var audience := StringName(str(row.get("available_to", "")).strip_edges())
		var available_level := str(row.get("available_level", "")).strip_edges()
		var appearance_weight_text := str(row.get("appearance_weight", "1")).strip_edges()
		if word_id.is_empty() or text.is_empty() or _word_definitions.has(word_id) \
			or not strength_text.is_valid_int() or not appearance_weight_text.is_valid_float() \
			or float(appearance_weight_text) <= 0.0 or not LEGACY_TENDENCIES.has(source_tendency) \
			or audience not in [&"player", &"opponent"] \
			or not _type_relations.has(_make_matchup_key(battle_type, battle_type)) \
			or not _strength_probabilities.has(int(strength_text)) \
			or str(row.get("test_only", "")).to_lower() != "false":
			return false

		var definition := {
			"word_id": word_id,
			"text": text,
			"battle_type": StringName(battle_type),
			"strength": int(strength_text),
			"batch_spawn_count": int(_strength_batch_spawn_counts.get(int(strength_text), 0)),
			"traits": _parse_trait_ids(str(row.get("traits", ""))),
			"tendency": tendency,
			"tendency_id": tendency,
			"source_tendency": source_tendency,
			"original_sentence_id": word_id if audience == &"player" else "",
			"available_level": StringName(available_level),
			"available_to": audience,
			"streamer_id": str(row.get("streamer_id", "")).strip_edges(),
			"source_table": str(row.get("source_table", "")).strip_edges(),
			"source_id": str(row.get("source_id", "")).strip_edges(),
			"source_pool_id": str(row.get("source_pool_id", "")).strip_edges(),
			"source_story_config_id": str(row.get("source_story_config_id", "")).strip_edges(),
			"source_trigger_type": str(row.get("source_trigger_type", "")).strip_edges(),
			"source_trigger_key": str(row.get("source_trigger_key", "")).strip_edges(),
			"appearance_weight": float(appearance_weight_text),
			"mapping_status": str(row.get("mapping_status", "")).strip_edges(),
			"test_only": false,
			"notes": str(row.get("notes", "")),
		}
		if available_level != "all" and not LEVEL_PROFILE_PATHS.has(available_level):
			return false
		if str(definition["source_table"]).is_empty() or str(definition["source_id"]).is_empty() \
			or str(definition["mapping_status"]).is_empty():
			return false
		if audience == &"player" and str(definition["source_pool_id"]).is_empty():
			return false
		if audience == &"opponent" and (available_level == "all" or str(definition["streamer_id"]).is_empty()):
			return false
		_word_definitions[word_id] = definition
		_word_ids_in_source_order.append(word_id)

	for row: Dictionary in raw_opponents:
		var opponent_id: String = str(row.get("opponent_id", "")).strip_edges()
		if opponent_id.is_empty() or _opponent_configs.has(opponent_id):
			return false
		var config := _parse_opponent_config(row)
		if config.is_empty():
			return false
		_opponent_configs[opponent_id] = config

	for row: Dictionary in raw_retaliations:
		_retaliation_mappings.append(_parse_retaliation_mapping(row))

	_loaded = _word_definitions.size() > 0 \
		and _opponent_configs.size() == LEVEL_PROFILE_PATHS.size() \
		and not _retaliation_mappings.is_empty()
	if not _loaded or not _has_valid_four_level_content():
		_loaded = false
		return false

	var default_profile: LevelProfile = _load_level_profile(DEFAULT_LEVEL_ID)
	return configure_level(default_profile)


## 保留 PB-03 入口名，正式数据由 load_configuration() 统一读取。
func load_test_configuration() -> bool:
	return load_configuration()


## 依 A 提供的正式 LevelProfile 建立本关词池，并重置本局随机序列。
func configure_level(level: LevelProfile) -> bool:
	_active_level_context.clear()
	if not _loaded or level == null:
		return false

	var context: Dictionary = _context_from_level_profile(level)
	if context.is_empty() or _get_opponent_config_for_context(context).is_empty():
		return false
	if _get_word_ids_for_context(context, "player").is_empty() \
		or _get_word_ids_for_context(context, "opponent").is_empty():
		return false

	_active_level_context = context
	_rng.seed = _random_seed
	return true


## 设置后续候选抽取的固定种子，不改动任何卡槽内容。
func set_random_seed(seed_value: int) -> void:
	_random_seed = seed_value
	_rng.seed = seed_value


## 按 A 的本局已用词和其他卡槽占用词抽一条玩家候选；槽位状态归 D / A 管理。
func draw_player_speech_word(
	used_word_ids: Array[String],
	occupied_word_ids: Array[String],
	level_context: Variant = null
) -> Dictionary:
	if not _loaded:
		return {}
	var excluded_word_ids: Array[String] = used_word_ids.duplicate()
	for occupied_word_id: String in occupied_word_ids:
		if not excluded_word_ids.has(occupied_word_id):
			excluded_word_ids.append(occupied_word_id)
	var context: Variant = _active_level_context if level_context == null else level_context
	var candidates: Array[String] = get_available_word_ids("player", excluded_word_ids, context)
	if candidates.is_empty():
		return {}
	var selected_index: int = _rng.randi_range(0, candidates.size() - 1)
	return get_word_definition(candidates[selected_index])


## 返回指定正式关卡、主播或 LevelProfile 对应的可用词条 ID。
func get_word_ids(level_context: Variant, audience: String) -> Array[String]:
	if not _loaded or audience not in ["player", "opponent"]:
		return []
	var context: Dictionary = _resolve_level_context(level_context)
	if context.is_empty():
		return []
	return _get_word_ids_for_context(context, audience)


## 按 A 的阵营已用词记录过滤静态池；相同 word_id 不会再次进入候选。
func get_available_word_ids(
	team: String,
	used_word_ids: Array[String],
	level_context: Variant = DEFAULT_LEVEL_ID
) -> Array[String]:
	var result: Array[String] = []
	for word_id: String in get_word_ids(level_context, team):
		if not used_word_ids.has(word_id):
			result.append(word_id)
	return result


## 给 A / D 读取当前关卡只读内容，每个词条与缓存保持隔离。
func get_word_definitions(level_context: Variant, audience: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for word_id: String in get_word_ids(level_context, audience):
		result.append(get_word_definition(word_id))
	return result


## 返回词条值快照；嵌套 traits 也复制，运行单位无法改写词库缓存。
func get_word_definition(word_id: String) -> Dictionary:
	if not _loaded:
		return {}
	var definition: Dictionary = _word_definitions.get(word_id, {})
	return definition.duplicate(true)


## 返回攻击方相对防守方的关系：advantage / disadvantage / same。
func get_type_matchup(attacker_type: String, defender_type: String) -> StringName:
	if not _loaded:
		return &""
	return StringName(_type_relations.get(_make_matchup_key(attacker_type, defender_type), &""))


## strength 仅表示一次合法感染尝试的成功概率，其他系统不应挪用。
func get_strength_success_probability(strength: int) -> float:
	return float(_strength_probabilities.get(strength, 0.0)) if _loaded else 0.0


## 根据正式强度表返回一次话语批次应生成的棋子数量。
func get_strength_batch_spawn_count(strength: int) -> int:
	return int(_strength_batch_spawn_counts.get(strength, 0)) if _loaded else 0


## 无参数读取当前 LevelProfile 对应配置；传 ID 时兼容按关卡或主播查询。
func get_opponent_config(opponent_id: String = "") -> Dictionary:
	if not _loaded:
		return {}
	var config: Dictionary = {}
	if not opponent_id.is_empty():
		config = _opponent_configs.get(opponent_id, {})
		if config.is_empty():
			for candidate: Dictionary in _opponent_configs.values():
				if opponent_id in [
					str(candidate.get("streamer_id", "")),
					str(candidate.get("level_id", "")),
					str(candidate.get("story_config_id", "")),
				]:
					config = candidate
					break
	elif not _active_level_context.is_empty():
		config = _get_opponent_config_for_context(_active_level_context)
	if config.is_empty() and _active_level_context.is_empty():
		config = _opponent_configs.get("alien", {})
	return config.duplicate(true)


## 为导演和调试层暴露当前关卡的稳定 ID 值副本。
func get_current_level_context() -> Dictionary:
	return _active_level_context.duplicate(true)


## 将 21 表中各主播启用技能映射成 Plan B 行为候选。
func get_retaliation_skill_mappings(streamer_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _loaded:
		return result
	for mapping: Dictionary in _retaliation_mappings:
		if streamer_id.is_empty() or str(mapping.get("streamer_id", "")) == streamer_id:
			result.append(mapping.duplicate(true))
	return result


func is_loaded() -> bool:
	return _loaded


func _get_word_ids_for_context(context: Dictionary, audience: String) -> Array[String]:
	var result: Array[String] = []
	var level_id: String = str(context.get("level_id", ""))
	var streamer_id: String = str(context.get("streamer_id", ""))
	var pool_id: String = str(context.get("pool_id", ""))
	if level_id.is_empty() or streamer_id.is_empty() or (audience == "player" and pool_id.is_empty()):
		return result
	for word_id: String in _word_ids_in_source_order:
		var definition: Dictionary = _word_definitions[word_id]
		if str(definition.get("available_to", "")) != audience:
			continue
		if audience == "player":
			var available_level: String = str(definition.get("available_level", ""))
			if available_level != "all" and available_level != level_id:
				continue
			if str(definition.get("source_pool_id", "")) != pool_id:
				continue
			var player_streamer: String = str(definition.get("streamer_id", ""))
			if not player_streamer.is_empty() and player_streamer != streamer_id:
				continue
		else:
			if str(definition.get("available_level", "")) != level_id \
				or str(definition.get("streamer_id", "")) != streamer_id:
				continue
		result.append(word_id)
	return result


func _resolve_level_context(level_context: Variant) -> Dictionary:
	if level_context is LevelProfile:
		return _context_from_level_profile(level_context)
	if level_context is Dictionary:
		var requested_level_id: String = str(level_context.get("level_id", "")).strip_edges()
		if requested_level_id == str(_active_level_context.get("level_id", "")):
			return _active_level_context.duplicate(true)
		var base_context: Dictionary = _context_for_level_id(requested_level_id)
		if base_context.is_empty():
			return {}
		for key: String in ["streamer_id", "story_config_id", "pool_id"]:
			var override_value: String = str(level_context.get(key, "")).strip_edges()
			if not override_value.is_empty():
				base_context[key] = override_value
		return base_context
	var requested_id: String = str(level_context).strip_edges()
	if requested_id.is_empty():
		return _active_level_context.duplicate(true)
	if requested_id == str(_active_level_context.get("level_id", "")):
		return _active_level_context.duplicate(true)
	if LEVEL_PROFILE_PATHS.has(requested_id):
		return _context_for_level_id(requested_id)
	for config: Dictionary in _opponent_configs.values():
		if requested_id in [str(config.get("streamer_id", "")), str(config.get("story_config_id", ""))]:
			return _context_for_level_id(str(config.get("level_id", "")))
	return {}


func _context_for_level_id(level_id: String) -> Dictionary:
	if not LEVEL_PROFILE_PATHS.has(level_id):
		return {}
	var profile: LevelProfile = _load_level_profile(level_id)
	return _context_from_level_profile(profile)


func _context_from_level_profile(level: LevelProfile) -> Dictionary:
	if level == null or level.level_id.is_empty() or level.streamer_id.is_empty():
		return {}
	var pool_id := ""
	if level.normal_speech_pool_source != null:
		pool_id = level.normal_speech_pool_source.pool_id.strip_edges()
	if pool_id.is_empty():
		return {}
	return {
		"level_id": level.level_id,
		"streamer_id": level.streamer_id,
		"story_config_id": level.story_config_id,
		"pool_id": pool_id,
	}


func _load_level_profile(level_id: String) -> LevelProfile:
	var profile_path: String = str(LEVEL_PROFILE_PATHS.get(level_id, ""))
	if profile_path.is_empty():
		return null
	return load(profile_path) as LevelProfile


func _get_opponent_config_for_context(context: Dictionary) -> Dictionary:
	for config: Dictionary in _opponent_configs.values():
		if str(config.get("level_id", "")) == str(context.get("level_id", "")) \
			and str(config.get("streamer_id", "")) == str(context.get("streamer_id", "")):
			return config
	return {}


func _has_valid_four_level_content() -> bool:
	for level_id: String in LEVEL_PROFILE_PATHS:
		var profile: LevelProfile = _load_level_profile(level_id)
		var context: Dictionary = _context_from_level_profile(profile)
		var config: Dictionary = _get_opponent_config_for_context(context)
		if context.is_empty() or config.is_empty() \
			or str(config.get("story_config_id", "")) != str(context.get("story_config_id", "")) \
			or _get_word_ids_for_context(context, "player").is_empty() \
			or _get_word_ids_for_context(context, "opponent").is_empty():
			return false
	return true


func _has_required_word_fields(row: Dictionary) -> bool:
	for field: String in [
		"word_id", "text", "battle_type", "strength", "traits", "tendency",
		"available_level", "available_to", "streamer_id", "source_table", "source_id",
		"source_pool_id", "appearance_weight", "mapping_status", "test_only",
	]:
		if not row.has(field):
			return false
	return true


func _has_complete_matchup_table() -> bool:
	var type_ids: Array[StringName] = []
	for relation_key: String in _type_relations:
		var halves: PackedStringArray = relation_key.split("|", false)
		if halves.size() != 2:
			return false
		for half: String in halves:
			var type_id := StringName(half)
			if not type_ids.has(type_id):
				type_ids.append(type_id)
	if type_ids.size() != 3:
		return false
	for attacker: StringName in type_ids:
		for defender: StringName in type_ids:
			if not _type_relations.has(_make_matchup_key(attacker, defender)):
				return false
	return true


func _make_matchup_key(attacker_type: Variant, defender_type: Variant) -> String:
	return "%s|%s" % [str(attacker_type), str(defender_type)]


func _parse_trait_ids(raw_value: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var normalized: String = raw_value.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "none" or normalized == "[]":
		return result
	for part: String in raw_value.split("|", false):
		var trait_id := StringName(part.strip_edges())
		if not String(trait_id).is_empty() and not result.has(trait_id):
			result.append(trait_id)
	return result


func _normalize_tendency_id(source_tendency: StringName) -> StringName:
	# LevelSpeech 与 TendencyState 使用 heretical；03 原表的 heresy 保存在 source_tendency。
	return &"heretical" if source_tendency == &"heresy" else source_tendency


func _parse_opponent_config(row: Dictionary) -> Dictionary:
	var required_numbers: Dictionary = {
		"initial_speech_delay_seconds": 0.0,
		"speech_cooldown_seconds": 0.0,
		"counterattack_lead_margin": 0,
		"counterattack_cooldown_seconds": 0.0,
		"counterattack_pre_windup_seconds": 0.0,
		"counterattack_child_count": 0,
		"counterattack_max_uses": 0,
	}
	var parsed: Dictionary = {}
	for key: String in required_numbers:
		var raw_value: String = str(row.get(key, "")).strip_edges()
		if not raw_value.is_valid_float():
			return {}
		if key in ["counterattack_lead_margin", "counterattack_child_count", "counterattack_max_uses"]:
			if not raw_value.is_valid_int():
				return {}
			parsed[key] = int(raw_value)
		else:
			parsed[key] = float(raw_value)
	for key: String in [
		"opponent_id", "level_id", "streamer_id", "story_config_id", "word_pool_trigger_type",
		"word_pool_trigger_key", "counterattack_skill_id", "counterattack_trigger_event",
		"counterattack_effect_id", "counterattack_mapping_status", "source_skill_trait_id",
		"source_table", "source_id",
	]:
		parsed[key] = str(row.get(key, "")).strip_edges()
		if str(parsed[key]).is_empty():
			return {}
	parsed["speech_enabled"] = str(row.get("speech_enabled", "false")).to_lower() == "true"
	parsed["counterattack_enabled"] = str(row.get("counterattack_enabled", "false")).to_lower() == "true"
	parsed["test_only"] = str(row.get("test_only", "")).to_lower() == "true"
	parsed["notes"] = str(row.get("notes", ""))
	if parsed["test_only"] or not LEVEL_PROFILE_PATHS.has(str(parsed["level_id"])) \
		or float(parsed["speech_cooldown_seconds"]) <= 0.0 \
		or float(parsed["counterattack_pre_windup_seconds"]) < 0.0:
		return {}
	return parsed


func _parse_retaliation_mapping(row: Dictionary) -> Dictionary:
	return {
		"skill_id": str(row.get("skill_id", "")),
		"streamer_id": str(row.get("streamer_id", "")),
		"tier": int(str(row.get("tier", "0"))) if str(row.get("tier", "")).is_valid_int() else 0,
		"trait_id": StringName(str(row.get("trait_id", ""))),
		"trait_name": str(row.get("trait_name", "")),
		"weight": int(str(row.get("weight", "0"))) if str(row.get("weight", "")).is_valid_int() else 0,
		"candidate_plan_b_behavior": str(row.get("candidate_plan_b_behavior", "")),
		"prototype_effect_id": str(row.get("prototype_effect_id", "")),
		"prototype_status": str(row.get("prototype_status", "")),
		"source_table": str(row.get("source_table", "")),
		"source_id": str(row.get("source_id", "")),
		"source_notes": str(row.get("source_notes", "")),
	}


func _read_csv_rows(path: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		push_error("PlanBContentCatalog: 找不到原型配置 %s" % path)
		return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("PlanBContentCatalog: 无法打开原型配置 %s" % path)
		return result
	var headers: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var cells: PackedStringArray = file.get_csv_line()
		if cells.size() == 1 and cells[0].is_empty():
			continue
		if cells.size() != headers.size():
			push_error("PlanBContentCatalog: CSV 列数不匹配 %s" % path)
			return []
		var row: Dictionary = {}
		for index: int in headers.size():
			row[str(headers[index])] = cells[index]
		result.append(row)
	return result
