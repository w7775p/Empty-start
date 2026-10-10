extends SceneTree

const LEVEL_PROFILE = preload("res://data/level_configuration/level_profile.gd")
const LEVEL_SPEECH = preload("res://data/level_configuration/level_speech.gd")
const SELECTOR = preload("res://systems/barrage_generation/normal_speech_selector.gd")
const HIT_RESOLUTION = preload("res://core/combat/hit_resolution.gd")
const TENDENCY_STATE = preload("res://core/tendencies/tendency_state.gd")
const ORACLE_POOL = preload("res://core/final_oracle/final_oracle_candidate_pool.gd")
const ORACLE_SESSION = preload("res://core/final_oracle/final_oracle_session.gd")
const ORACLE_CONFIRMATION = preload("res://core/final_oracle/final_oracle_confirmation_state.gd")
const REPEAT_STATS = preload("res://core/repeat/repeat_generation_stats.gd")
const SAVE_DATA = preload("res://core/save/save_data.gd")
const DIVINE_FILTER = preload("res://core/divine_descent/divine_descent_candidate_filter.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_selector_reads_neutral_ratio_and_weight():
		quit(1)
		return
	if not _test_neutral_hit_rewards_pk_without_tendency():
		quit(1)
		return
	if not _test_formal_candidates_exclude_neutral():
		quit(1)
		return
	print("PASS TT-13: neutral selection, PK/history without tendency, formal candidate filtering")
	quit(0)


# neutral 比例独立于三项倾向；旧关卡默认仍只选原三项。
func _test_selector_reads_neutral_ratio_and_weight() -> bool:
	var level: LevelProfile = LEVEL_PROFILE.new()
	var neutral: LevelSpeech = LEVEL_SPEECH.new()
	neutral.original_sentence_id = "neutral-live"
	neutral.text = "今天聊聊生活"
	neutral.tendency_id = "neutral"
	neutral.appearance_weight = 3.0
	var disabled: LevelSpeech = LEVEL_SPEECH.new()
	disabled.original_sentence_id = "neutral-disabled"
	disabled.text = "不应生成"
	disabled.tendency_id = "neutral"
	disabled.appearance_weight = 0.0
	var orthodox: LevelSpeech = LEVEL_SPEECH.new()
	orthodox.original_sentence_id = "orthodox-live"
	orthodox.text = "原有话语"
	orthodox.tendency_id = "orthodox"
	level.normal_speech_pool = [neutral, disabled, orthodox]
	var selector: NormalSpeechSelector = SELECTOR.new()
	level.neutral_ratio = 1.0
	if selector.select_next_normal_speech(level) != neutral:
		push_error("TT-13 neutral 比例与单句权重未生效")
		return false
	level.neutral_ratio = 0.0
	level.orthodox_ratio = 1.0
	if selector.select_next_normal_speech(level) != orthodox:
		push_error("TT-13 默认零 neutral 比例改变了原有关卡生成")
		return false
	return true


# neutral 保留普通命中身份和强度 PK，三项倾向仍为全零。
func _test_neutral_hit_rewards_pk_without_tendency() -> bool:
	var hit: HitResolution = HIT_RESOLUTION.new(0.5, 0.0, 1.0)
	var reward: Dictionary = hit.calculate_normal_word_reward(1, "neutral")
	if not is_equal_approx(float(reward.get("pk_delta", 0.0)), 0.0012) or int(reward.get("tendency_delta", -1)) != 0:
		push_error("TT-13 neutral 强度 1 应有普通 PK 收益且倾向增量为零")
		return false
	hit.apply_player_pk_delta(float(reward["pk_delta"]))
	hit.record_normal_word_hit("neutral-live", "neutral")
	var state: TendencyState = TENDENCY_STATE.new()
	state.opening_identity_tendency_id = "orthodox"
	state.record_normal_speech_tendency("neutral", int(reward["tendency_delta"]))
	state.commit_attempt_tendency()
	var history: Array[Dictionary] = hit.get_normal_hit_history()
	if not is_equal_approx(hit.get_player_pk(), 0.5012) or history.size() != 1 or str(history[0].get("tendency", "")) != "neutral":
		push_error("TT-13 neutral 未保留普通 PK 或命中历史")
		return false
	if not state.has_no_effective_behavior() or state.orthodox_total != 0 or state.heretical_total != 0 or state.absurd_total != 0:
		push_error("TT-13 neutral 改动了三项倾向全零状态")
		return false
	return true


# 神谕与终局都只从三项倾向历史建立正式候选。
func _test_formal_candidates_exclude_neutral() -> bool:
	var history: Array[Dictionary] = [
		{"original_sentence_id": "neutral-live", "tendency": "neutral", "hit_count": 9},
		{"original_sentence_id": "orthodox-live", "tendency": "orthodox", "hit_count": 1},
	]
	var oracle_candidates: Array[Dictionary] = ORACLE_POOL.new().build_from_normal_hit_history(history)
	var divine_candidates: Array[Dictionary] = DIVINE_FILTER.filter_three_tendency_history(history)
	if oracle_candidates.size() != 1 or divine_candidates.size() != 1:
		push_error("TT-13 neutral 进入了神谕或神降临正式候选")
		return false
	if str(oracle_candidates[0].get("original_sentence_id", "")) != "orthodox-live" or str(divine_candidates[0].get("original_sentence_id", "")) != "orthodox-live":
		push_error("TT-13 三项倾向候选筛选结果错误")
		return false
	var confirmation: FinalOracleConfirmationState = ORACLE_CONFIRMATION.new(SAVE_DATA.new())
	var session: FinalOracleSession = ORACLE_SESSION.new()
	if not session.open_after_breakthrough("tt13-level", history, REPEAT_STATS.new(), confirmation):
		push_error("TT-13 神谕入口未接收普通命中历史")
		return false
	if session.confirm_display_candidate(history[0]) or not confirmation.get_confirmed_selection("tt13-level").is_empty():
		push_error("TT-13 neutral 被提交成了神谕/圣典句")
		return false
	return true
