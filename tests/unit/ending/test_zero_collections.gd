extends SceneTree


# 只执行 EN-09 的一个用例：所有收藏为空仍接收并构建最终结果。
func _initialize() -> void:
	if not _test_zero_collections_complete():
		push_error("FAIL EN-09: zero collections")
		quit(1)
		return
	print("PASS EN-09: 1/1 zero-collection completion case")
	quit(0)


# TEST_ONLY 样本全部在内存创建，生产文案与主图配置保持原状。
func _test_zero_collections_complete() -> bool:
	var run_data: SaveData = SaveData.new()
	var identity: IdentityOption = IdentityOption.new()
	identity.identity_id = &"TEST_ONLY_EN09_IDENTITY"
	identity.tendency_id = "orthodox"
	run_data.identity_id = identity.identity_id
	run_data.streamer_name = "TEST_ONLY_EN09_STREAMER"
	run_data.tendency_state.initialize_from_identity_option(identity)
	run_data.tendency_state.record_normal_speech_tendency("heretical", 2)
	run_data.tendency_state.commit_attempt_tendency()
	var level: LevelProfile = LevelProfile.new()
	level.level_id = "TEST_ONLY_EN09_LEVEL"
	level.level_order = 3
	var catalog: LevelCatalog = LevelCatalog.new()
	catalog.profiles.append(level)
	var descent: DivineDescentSession = DivineDescentSession.new()
	if not descent.enter(run_data):
		return false
	# 冻结后改变实时倾向，零收藏结局仍须消费进入时的主导与身份比较依据。
	run_data.tendency_state.record_normal_speech_tendency("absurd", 10)
	run_data.tendency_state.commit_attempt_tendency()
	var names: EndingReligionNameConfig = EndingReligionNameConfig.new()
	names.heretical_name = "TEST_ONLY_EN09_RELIGION"
	var judgements: EndingJudgementTextConfig = EndingJudgementTextConfig.new()
	judgements.shifted_text = "TEST_ONLY_EN09_JUDGEMENT"
	var art := EndingMainArtConfig.new()
	var sample_art := GradientTexture2D.new()
	art.heretical_main_art = sample_art
	var ending: EndingSession = EndingSession.new()
	if not ending.receive_final_state(descent, catalog, art, names, judgements):
		return false
	var display: Dictionary = ending.get_display_data()
	var scripture: Dictionary = display["scripture"]
	var rows: Array = scripture["rows"]
	if (
		display["primary_tendency_id"] != "heretical"
		or display["secondary_tendency_id"] != "heretical"
		or display["identity_result_class"] != EndingIdentityResultClassifier.SHIFTED
		or display["religion_name"] != "TEST_ONLY_EN09_RELIGION"
		or display["judgement_text"] != "TEST_ONLY_EN09_JUDGEMENT"
		or display["main_art"] != sample_art
		or not scripture["is_empty"]
		or scripture["status"] != EndingScriptureDisplayData.STATUS_NOT_FORMED_ORACLE
		or rows.size() != 1
	):
		return false
	if rows[0]["has_oracle"] or rows[0]["chapter_number"] != 3 or rows[0]["verse_number"] != 0:
		return false
	# 接收后源倾向、显示配置和返回副本变化均不能替换首次页面结果。
	names.heretical_name = "TEST_ONLY_CHANGED_NAME"
	var viewed: Dictionary = ending.get_display_data()
	viewed["religion_name"] = "TEST_ONLY_CHANGED_COPY"
	if ending.receive_final_state(descent, catalog, art, names, judgements) or ending.get_display_data()["religion_name"] != "TEST_ONLY_EN09_RELIGION":
		return false
	# 同一用例同时确认缺少正式文案 / 美术时可完成，且不会补写猜测内容。
	var production_ending: EndingSession = EndingSession.new()
	if not production_ending.receive_final_state(descent, catalog):
		return false
	var production_display: Dictionary = production_ending.get_display_data()
	return (
		production_ending.is_received()
		and production_display["religion_name"].is_empty()
		and production_display["judgement_text"].is_empty()
		and production_display["main_art"] == null
		and production_display["scripture"]["is_empty"]
		and run_data.scripture_data.get_ordered_entries().is_empty()
		and run_data.loser_card_data.acquired_streamer_ids.is_empty()
		and run_data.assimilation_data.inherited_word_weights.is_empty()
		and run_data.assimilation_data.inherited_trait_ids.is_empty()
	)
