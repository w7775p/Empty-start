extends SceneTree

const LEVEL_CATALOG: LevelCatalog = preload("res://tests/fixtures/fo11/test_level_catalog.tres")
const CARD_CATALOG: LoserCardCatalog = preload("res://tests/fixtures/fo11/test_loser_card_catalog.tres")


# 本卡只保留一个关键用例：同一已提交结果重复读取不发奖或额外切关。
func _init() -> void:
	if _test_reopen_has_no_side_effects():
		print("PASS RS-08：重复打开只读已提交成果，奖励与关卡没有额外变化，1/1")
		quit()
	else:
		push_error("FAIL RS-08：重复读取改变了已提交成果或当前关卡")
		quit(1)


# 经真实提交 API 准备一场完整成果，再模拟重新接收、读取与继续后的旧结果查看。
func _test_reopen_has_no_side_effects() -> bool:
	var source: LevelProfile = LEVEL_CATALOG.profiles[0]
	var level_id := StringName(source.level_id)
	var streamer_id := StringName(source.streamer_id)
	var speech: LevelSpeech = source.get_normal_speech_pool()[0]
	var data := SaveData.new()
	if not data.scripture_data.write_confirmed_oracle(source, {"original_sentence_id": speech.original_sentence_id, "tendency": speech.tendency_id}):
		return false
	if not data.loser_card_data.grant_on_true_defeat(level_id, streamer_id, true, true, CARD_CATALOG):
		return false
	if not data.assimilation_data.register_defeated_streamer(level_id, streamer_id, true, true):
		return false
	var pool: WordPoolInheritanceConfig = source.normal_pool_inheritance
	if not data.assimilation_data.register_inherited_word_pool(level_id, pool.pool_id, pool.appearance_weight, pool.can_inherit, pool.is_contradiction_pool):
		return false
	if not data.assimilation_data.register_inherited_trait(level_id, source.inheritable_trait_ids[0], true):
		return false
	if not data.live_session.commit_pk_win_fans(level_id, 7):
		return false
	var result: Dictionary = {"level_id": source.level_id, "result_kind": "breakthrough_oracle_complete"}
	var session := RestSession.new()
	var run_state := LevelRunState.new(LEVEL_CATALOG)
	if not session.open_result(result):
		return false
	var rewards: Dictionary = session.read_committed_rewards(data, LEVEL_CATALOG, CARD_CATALOG)
	if rewards["new_scripture_entry"] == null or rewards["new_loser_card"] == null or rewards["new_assimilation"].is_empty():
		return false
	var expected: Dictionary = _reward_values(rewards)
	var inherited: Dictionary = data.assimilation_data.get_current_content_snapshot()
	if session.open_result(result) or _reward_values(session.read_committed_rewards(data, LEVEL_CATALOG, CARD_CATALOG)) != expected:
		return false
	if run_state.get_current_level_profile() != source:
		return false
	# 仅显式继续推进一次；旧结果重新查看后再继续，复用关卡所有者既有去重。
	if session.continue_to_next_level(run_state) != LevelRunState.CompletionResult.ADVANCED:
		return false
	var next_level: LevelProfile = run_state.get_current_level_profile()
	var reopened := RestSession.new()
	if not reopened.open_result(session.get_result_snapshot()):
		return false
	if _reward_values(reopened.read_committed_rewards(data, LEVEL_CATALOG, CARD_CATALOG)) != expected:
		return false
	if reopened.continue_to_next_level(run_state) != LevelRunState.CompletionResult.ALREADY_COMPLETED:
		return false
	return (
		run_state.get_current_level_profile() == next_level and next_level != source
		and not run_state.is_all_normal_levels_completed()
		and data.scripture_data.get_ordered_entries().size() == 1
		and data.scripture_data.get_entry_for_level(level_id).verse_number == expected["scripture"][3]
		and data.loser_card_data.get_acquired_cards(CARD_CATALOG).size() == 1
		and data.assimilation_data.get_current_content_snapshot() == inherited
		and data.live_session.fan_count == 7
	)


# 返回的 Resource 是独立副本，按正式字段比较内容，不依赖对象地址。
func _reward_values(rewards: Dictionary) -> Dictionary:
	var scripture: ScriptureEntry = rewards["new_scripture_entry"]
	var card: Dictionary = rewards["new_loser_card"]
	var profile: LoserCardProfile = card["profile"]
	return {
		"scripture": [scripture.level_id, scripture.original_line_id, scripture.chapter_number, scripture.verse_number, scripture.streamer_name, scripture.original_line_text],
		"card": [card["streamer_id"], profile.streamer_name, profile.card_text],
		"assimilation": rewards["new_assimilation"],
	}
