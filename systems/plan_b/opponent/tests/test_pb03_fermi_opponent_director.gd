extends SceneTree

const ContentCatalogScript := preload("res://systems/plan_b/content/plan_b_content_catalog.gd")
const OpponentDirectorScript := preload("res://systems/plan_b/opponent/fermi_opponent_director.gd")
const LEVEL_PATHS: Array[String] = [
	"res://data/level_configuration/level_001.tres",
	"res://data/level_configuration/level_002.tres",
	"res://data/level_configuration/level_003.tres",
	"res://data/level_configuration/level_004.tres",
]
const EXPECTED_SKILLS: Array[String] = [
	"alien_t3_split",
	"kiwi_t3_retaliation_copy",
	"frog_t3_split",
	"fox_t4_retaliation_copy",
]


func _init() -> void:
	var catalog = ContentCatalogScript.new()
	assert(catalog.load_configuration())
	for index: int in LEVEL_PATHS.size():
		var level: LevelProfile = load(LEVEL_PATHS[index]) as LevelProfile
		assert(catalog.configure_level(level))
		var director = OpponentDirectorScript.new()
		assert(director.configure(catalog, 20261017))
		assert(director.set_spawn_area(Rect2(40.0, 60.0, 640.0, 420.0)))
		assert(director.get_debug_snapshot()["streamer_id"] == level.streamer_id)
		_test_level_speech(catalog, director, level)
		_test_counterattack(director, level, EXPECTED_SKILLS[index])
		_test_exhaustion_signal(director, level)
	print("PB13_OPPONENT_TEST_OK")
	quit()


func _test_level_speech(catalog: Object, director: Object, level: LevelProfile) -> void:
	var speech_requests: Array[Dictionary] = []
	director.publish_word_requested.connect(
		func(word_id: String, spawn_position: Vector2) -> void:
			speech_requests.append({"word_id": word_id, "spawn_position": spawn_position})
	)
	var neutral_snapshots: Array[Dictionary] = []
	var opponent_word_ids: Array[String] = catalog.get_word_ids(level, "opponent")
	director.update_speech(11.49, neutral_snapshots, opponent_word_ids)
	assert(speech_requests.is_empty())
	director.update_speech(0.02, neutral_snapshots, opponent_word_ids)
	assert(speech_requests.size() == 1)
	assert(opponent_word_ids.has(str(speech_requests[0]["word_id"])))
	var spawn_position: Vector2 = speech_requests[0]["spawn_position"]
	assert(spawn_position.x >= 56.0 and spawn_position.x <= 664.0)
	assert(spawn_position.y >= 76.0 and spawn_position.y <= 464.0)
	assert(director.get_debug_snapshot()["awaiting_speech_publish_result"])
	assert(is_zero_approx(float(director.get_debug_snapshot()["speech_cooldown_remaining"])))
	assert(not director.report_speech_publish_result("unknown", true))
	assert(catalog.get_word_ids(level, "opponent").size() == opponent_word_ids.size())
	director.update_speech(20.0, neutral_snapshots, opponent_word_ids)
	assert(speech_requests.size() == 1)
	assert(director.report_speech_publish_result(str(speech_requests[0]["word_id"]), false))
	director.update_speech(0.0, neutral_snapshots, opponent_word_ids)
	assert(speech_requests.size() == 2)
	assert(director.report_speech_publish_result(str(speech_requests[1]["word_id"]), true))
	assert(is_equal_approx(float(director.get_debug_snapshot()["speech_cooldown_remaining"]), 11.5))
	director.update_speech(11.49, neutral_snapshots, opponent_word_ids)
	assert(speech_requests.size() == 2)
	director.update_speech(0.02, neutral_snapshots, opponent_word_ids)
	assert(speech_requests.size() == 3)
	assert(director.report_speech_publish_result(str(speech_requests[2]["word_id"]), true))
	for request: Dictionary in speech_requests:
		assert(catalog.get_word_definition(str(request["word_id"]))["streamer_id"] == level.streamer_id)


func _test_counterattack(director: Object, level: LevelProfile, expected_skill: String) -> void:
	var warnings: Array[Dictionary] = []
	var effect_requests: Array[Dictionary] = []
	var resolved: Array[Dictionary] = []
	director.counterattack_windup_started.connect(func(request: Dictionary) -> void: warnings.append(request))
	director.counterattack_resolved.connect(func(result: Dictionary) -> void: resolved.append(result))
	director.set_counterattack_effect_handler(
		func(request: Dictionary) -> bool:
			effect_requests.append(request)
			return str(request.get("effect_id", "")) == "split"
	)
	var opponent_unit_id := "%s_unit_01" % level.streamer_id
	var opponent_snapshots: Array[Dictionary] = [{"unit_id": opponent_unit_id, "team": "opponent"}]
	director.counterattack_enabled = false
	director.update_counterattack(0.0, {"player": 3, "opponent": 1}, opponent_snapshots)
	assert(warnings.is_empty())
	director.counterattack_enabled = true
	director.update_counterattack(0.0, {"player": 3, "opponent": 1, "neutral": 4}, opponent_snapshots)
	assert(warnings.size() == 1)
	assert(warnings[0]["skill_id"] == expected_skill)
	assert(warnings[0]["effect_id"] == &"split")
	assert(warnings[0]["effect_parameters"]["child_count"] == 2)
	assert(effect_requests.is_empty())
	director.update_counterattack(1.19, {"player": 3, "opponent": 1}, opponent_snapshots)
	assert(effect_requests.is_empty())
	director.update_counterattack(0.02, {"player": 3, "opponent": 1}, opponent_snapshots)
	assert(effect_requests.size() == 1)
	assert(effect_requests[0]["target_unit_id"] == opponent_unit_id)
	assert(not director.report_counterattack_result(true))
	director.update_counterattack(0.0, {"player": 3, "opponent": 1}, opponent_snapshots)
	assert(warnings.size() == 1)
	assert(resolved.size() == 1)
	assert(resolved[0]["applied"])
	assert(director.get_debug_snapshot()["counterattack_uses"] == 1)
	assert(not director.report_counterattack_result(true))


func _test_exhaustion_signal(director: Object, level: LevelProfile) -> void:
	var exhausted_levels: Array[Dictionary] = []
	director.opponent_word_pool_exhausted.connect(
		func(level_id: String, streamer_id: String) -> void:
			exhausted_levels.append({"level_id": level_id, "streamer_id": streamer_id})
	)
	var neutral_snapshots: Array[Dictionary] = [{"unit_id": "viewer_neutral_01", "team": "neutral"}]
	var no_available_words: Array[String] = []
	director.update_speech(0.0, neutral_snapshots, no_available_words)
	director.update_speech(0.0, neutral_snapshots, no_available_words)
	assert(exhausted_levels.size() == 1)
	assert(exhausted_levels[0]["level_id"] == level.level_id)
	assert(exhausted_levels[0]["streamer_id"] == level.streamer_id)
