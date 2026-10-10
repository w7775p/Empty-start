extends SceneTree


# 同一次确认链核对原文、首次节号和重建状态后的同关去重。
func _initialize() -> void:
	seed(1503)
	if not _test_first_confirmation_writes_entry():
		quit(1)
		return
	print("PASS SC-02/03: 确认原文、1～99 节号、重建状态及重复写入保持首次结果")
	quit(0)


# 真实确认信号把关卡和原句快照写进当前 SaveData 的圣典。
func _test_first_confirmation_writes_entry() -> bool:
	var run_data: SaveData = SaveData.new()
	var catalog: LevelCatalog = _make_catalog()
	var confirmation_state: FinalOracleConfirmationState = FinalOracleConfirmationState.new(run_data)
	run_data.scripture_data.bind_confirmation_state(confirmation_state, catalog)
	confirmation_state.confirm_selection("scripture_level", {"original_sentence_id": "scripture_line", "tendency": "orthodox"})
	var entry: ScriptureEntry = run_data.scripture_data.get_entry_for_level(&"scripture_level")
	if entry == null or run_data.scripture_data.entries.size() != 1:
		push_error("SC-02 首次神谕确认没有写入经文")
		return false
	if entry.streamer_name != "测试主播" or entry.chapter_number != 3 or entry.original_line_text != "测试原句" or entry.tendency_id != "orthodox":
		push_error("SC-02 经文没有保留真实关卡与原句信息")
		return false
	if entry.verse_number < 1 or entry.verse_number > 99:
		push_error("SC-03 首次节号超出 1～99")
		return false
	var first_verse: int = entry.verse_number
	# 查看副本和再次提交都保持首次保存的原句及节号。
	entry.verse_number = 0
	var second_state: FinalOracleConfirmationState = FinalOracleConfirmationState.new(run_data)
	run_data.scripture_data.bind_confirmation_state(second_state, catalog)
	second_state.confirm_selection("scripture_level", {"original_sentence_id": "scripture_other_line", "tendency": "absurd"})
	var other_candidate: Dictionary = {"original_sentence_id": "scripture_other_line", "tendency": "absurd"}
	if run_data.scripture_data.write_confirmed_oracle(catalog.profiles[0], other_candidate):
		push_error("SC-02 重复写入应拒绝")
		return false
	entry = run_data.scripture_data.get_entry_for_level(&"scripture_level")
	if run_data.scripture_data.get_ordered_entries().size() != 1 or entry == null or entry.original_line_id != &"scripture_line" or entry.verse_number != first_verse:
		push_error("SC-02 同关再次提交新增或覆盖了首次经文")
		return false
	return true


# 构造与真实候选字段一致的最小关卡来源。
func _make_catalog() -> LevelCatalog:
	var level_profile: LevelProfile = LevelProfile.new()
	level_profile.level_id = "scripture_level"
	level_profile.level_order = 3
	level_profile.streamer_name = "测试主播"
	var speech: LevelSpeech = LevelSpeech.new()
	speech.original_sentence_id = "scripture_line"
	speech.text = "测试原句"
	var other_speech: LevelSpeech = LevelSpeech.new()
	other_speech.original_sentence_id = "scripture_other_line"
	other_speech.text = "测试另一原句"
	level_profile.normal_speech_pool.assign([speech, other_speech])
	var catalog: LevelCatalog = LevelCatalog.new()
	catalog.profiles.append(level_profile)
	return catalog
