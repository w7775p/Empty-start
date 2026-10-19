extends SceneTree

const ContentCatalogScript := preload("res://systems/plan_b/content/plan_b_content_catalog.gd")
const LEVEL_PATHS: Array[String] = [
	"res://data/level_configuration/level_001.tres",
	"res://data/level_configuration/level_002.tres",
	"res://data/level_configuration/level_003.tres",
	"res://data/level_configuration/level_004.tres",
]
const EXPECTED_OPPONENT_WORD_COUNTS: Array[int] = [5, 6, 5, 6]


func _init() -> void:
	var catalog = ContentCatalogScript.new()
	assert(catalog.load_configuration())
	assert(catalog.is_loaded())
	assert(catalog.get_word_ids("level_001", "player").size() == 163)
	assert(catalog.get_word_ids("level_002", "player").size() == 163)
	assert(catalog.get_word_ids("level_001", "unknown").is_empty())

	for index: int in LEVEL_PATHS.size():
		var level: LevelProfile = load(LEVEL_PATHS[index]) as LevelProfile
		assert(level != null)
		assert(catalog.configure_level(level))
		var context: Dictionary = catalog.get_current_level_context()
		assert(context["level_id"] == level.level_id)
		assert(context["streamer_id"] == level.streamer_id)
		assert(context["pool_id"] == level.normal_speech_pool_source.pool_id)
		assert(catalog.get_word_ids(level, "player").size() == 163)
		var opponent_word_ids: Array[String] = catalog.get_word_ids(level, "opponent")
		assert(opponent_word_ids.size() == EXPECTED_OPPONENT_WORD_COUNTS[index])
		assert(catalog.get_opponent_config()["streamer_id"] == level.streamer_id)
		for opponent_word_id: String in opponent_word_ids:
			assert(catalog.get_word_definition(opponent_word_id)["streamer_id"] == level.streamer_id)

	var no_used_words: Array[String] = []
	var used_player_words: Array[String] = ["w_0001"]
	assert(catalog.get_available_word_ids("player", no_used_words, "level_001").size() == 163)
	assert(catalog.get_available_word_ids("player", used_player_words, "level_001").size() == 162)
	var alien_opponent_word_ids: Array[String] = catalog.get_word_ids("level_001", "opponent")
	var used_opponent_words: Array[String] = [alien_opponent_word_ids[0]]
	assert(catalog.get_available_word_ids("opponent", used_opponent_words, "level_001").size() == 4)

	var definition: Dictionary = catalog.get_word_definition("w_0001")
	assert(definition["text"] == "天堂名额少，先点点关注！")
	assert(definition["battle_type"] == &"type_a")
	assert(definition["battle_type_emoji"] == "✊")
	assert(definition["strength"] == 1)
	assert(definition["tendency"] == &"heretical")
	assert(definition["tendency_id"] == &"heretical")
	assert(definition["source_tendency"] == &"heresy")
	assert(definition["original_sentence_id"] == "w_0001")
	assert(definition["available_level"] == &"all")
	assert(definition["batch_spawn_count"] == 2)
	assert(definition["source_pool_id"] == "pool_streamer_a")
	assert(not definition["test_only"])
	assert(definition["traits"].is_empty())
	definition["text"] = "caller changed only its snapshot"
	definition["traits"].append(&"caller_only")
	var unchanged: Dictionary = catalog.get_word_definition("w_0001")
	assert(unchanged["text"] == "天堂名额少，先点点关注！")
	assert(unchanged["traits"].is_empty())
	assert(catalog.get_word_definition("missing").is_empty())

	assert(catalog.get_type_matchup("type_a", "type_b") == &"advantage")
	assert(catalog.get_type_matchup("type_b", "type_c") == &"advantage")
	assert(catalog.get_type_matchup("type_c", "type_a") == &"advantage")
	assert(catalog.get_type_matchup("type_a", "type_a") == &"same")
	assert(catalog.get_type_matchup("type_b", "type_a") == &"disadvantage")
	assert(catalog.get_battle_type_emoji("type_a") == "✊")
	assert(catalog.get_battle_type_emoji("type_b") == "✌️")
	assert(catalog.get_battle_type_emoji("type_c") == "✋")
	assert(catalog.get_battle_type_emoji("missing").is_empty())
	assert(is_equal_approx(catalog.get_strength_success_probability(1), 0.50))
	assert(is_equal_approx(catalog.get_strength_success_probability(2), 0.60))
	assert(is_equal_approx(catalog.get_strength_success_probability(3), 0.70))
	assert(catalog.get_strength_success_probability(4) == 0.0)
	assert(catalog.get_strength_batch_spawn_count(1) == 2)
	assert(catalog.get_strength_batch_spawn_count(2) == 4)
	assert(catalog.get_strength_batch_spawn_count(3) == 8)
	assert(catalog.get_strength_batch_spawn_count(4) == 0)

	var opponent_definition: Dictionary = catalog.get_word_definition(alien_opponent_word_ids[0])
	assert(opponent_definition["available_to"] == &"opponent")
	assert(opponent_definition["source_table"] == "20_主播气泡对白.csv")
	assert(opponent_definition["source_id"] == alien_opponent_word_ids[0])
	var mappings: Array[Dictionary] = catalog.get_retaliation_skill_mappings("alien")
	assert(mappings.size() == 8)
	assert(_find_mapping(mappings, "alien_t3_split").get("trait_name", "") == "分裂")
	assert(_find_mapping(mappings, "alien_t3_split").get("prototype_status", "") == "ACTIVE_PROFILE")
	assert(catalog.get_retaliation_skill_mappings().size() == 32)

	var alien_config: Dictionary = catalog.get_opponent_config("alien")
	assert(alien_config["level_id"] == "level_001")
	assert(is_equal_approx(float(alien_config["speech_cooldown_seconds"]), 11.5))
	assert(is_equal_approx(float(alien_config["counterattack_pre_windup_seconds"]), 1.2))
	assert(catalog.get_opponent_config("kiwi")["counterattack_skill_id"] == "kiwi_t3_retaliation_copy")
	assert(catalog.get_opponent_config("fox")["counterattack_effect_id"] == "split")
	assert(catalog.get_opponent_config("fermi").is_empty())
	alien_config["speech_cooldown_seconds"] = 0.0
	assert(is_equal_approx(float(catalog.get_opponent_config("alien")["speech_cooldown_seconds"]), 11.5))
	var population_config: Dictionary = catalog.get_population_config()
	assert(population_config["initial_neutral_count"] == 30)
	assert(population_config["initial_seed_slot_count"] == 0)
	assert(is_equal_approx(float(population_config["neutral_spawn_interval_seconds"]), 0.75))
	assert(is_equal_approx(float(population_config["neutral_spawn_jitter_ratio"]), 0.25))
	assert(is_equal_approx(float(population_config["neutral_spawn_min_seconds"]), 0.5625))
	assert(is_equal_approx(float(population_config["neutral_spawn_max_seconds"]), 0.9375))

	_test_slot_draw(catalog)
	print("PB12_PB15_CONTENT_TEST_OK")
	quit()


func _test_slot_draw(catalog: Object) -> void:
	var level: LevelProfile = load(LEVEL_PATHS[0]) as LevelProfile
	catalog.set_random_seed(731)
	assert(catalog.configure_level(level))
	var first_ids: Array[String] = _draw_three_cards(catalog, level)
	assert(first_ids.size() == 3)
	assert(_has_unique_ids(first_ids))

	# 新卡候选同时排除已发表词和仍占用另两个卡位的词。
	var used_word_ids: Array[String] = [first_ids[0]]
	var occupied_word_ids: Array[String] = [first_ids[1], first_ids[2]]
	var replacement: Dictionary = catalog.draw_player_speech_word(used_word_ids, occupied_word_ids)
	assert(not replacement.is_empty())
	assert(str(replacement["word_id"]) not in used_word_ids)
	assert(str(replacement["word_id"]) not in occupied_word_ids)

	# 同一 seed 与关卡的三次初始抽取次序可复现。
	var replay_catalog = ContentCatalogScript.new()
	assert(replay_catalog.load_configuration())
	replay_catalog.set_random_seed(731)
	assert(replay_catalog.configure_level(level))
	assert(_draw_three_cards(replay_catalog, level) == first_ids)

	# 池尾只剩一条时能补入该句；该句被占用后返回耗尽状态。
	var all_player_ids: Array[String] = catalog.get_word_ids(level, "player")
	var used_except_two: Array[String] = []
	for word_id: String in all_player_ids:
		if word_id not in ["w_0001", "w_0002"]:
			used_except_two.append(word_id)
	var occupied_w1: Array[String] = ["w_0001"]
	var occupied_w1_w2: Array[String] = ["w_0001", "w_0002"]
	var last_candidate: Dictionary = catalog.draw_player_speech_word(used_except_two, occupied_w1)
	assert(last_candidate.get("word_id", "") == "w_0002")
	assert(catalog.draw_player_speech_word(used_except_two, occupied_w1_w2).is_empty())


func _draw_three_cards(catalog: Object, level: LevelProfile) -> Array[String]:
	var result: Array[String] = []
	var used_word_ids: Array[String] = []
	var occupied_word_ids: Array[String] = []
	for _slot_index: int in range(3):
		var definition: Dictionary = catalog.draw_player_speech_word(used_word_ids, occupied_word_ids, level)
		assert(not definition.is_empty())
		var word_id: String = str(definition["word_id"])
		result.append(word_id)
		occupied_word_ids.append(word_id)
	return result


func _has_unique_ids(word_ids: Array[String]) -> bool:
	var unique_ids: Dictionary = {}
	for word_id: String in word_ids:
		if unique_ids.has(word_id):
			return false
		unique_ids[word_id] = true
	return true


func _find_mapping(mappings: Array[Dictionary], skill_id: String) -> Dictionary:
	for mapping: Dictionary in mappings:
		if str(mapping.get("skill_id", "")) == skill_id:
			return mapping
	return {}
