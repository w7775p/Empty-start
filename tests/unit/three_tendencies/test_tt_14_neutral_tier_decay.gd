extends SceneTree

const TIER_CATALOG = preload("res://data/combat_stage/tier_catalog.tres")
const TIER_CONFIG = preload("res://core/combat/combat_stage_tier_config.gd")
const COMBAT_STAGE = preload("res://core/combat/combat_stage.gd")
const BARRAGE_AREA = preload("res://systems/barrage_generation/barrage_area.tscn")
const LEVEL_PROFILE = preload("res://data/level_configuration/level_profile.gd")
const LEVEL_SPEECH = preload("res://data/level_configuration/level_speech.gd")
const SELECTOR = preload("res://systems/barrage_generation/normal_speech_selector.gd")


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_tier_table():
		quit(1)
		return
	if not _test_selector_tier_zero_and_five():
		quit(1)
		return
	if not _test_tier_change_affects_next_generation():
		quit(1)
		return
	print("PASS TT-14: Tier table, Tier 0/5 selection, next generation after Tier change")
	quit(0)


# 正式配置逐档核对，旧 Resource 未填写字段仍保持 1 倍。
func _test_tier_table() -> bool:
	var expected: Array[float] = [1.0, 0.99, 0.7, 0.4, 0.15, 0.0]
	for tier in range(expected.size()):
		var config: CombatStageTierConfig = TIER_CATALOG.get_tier_config(tier)
		if config == null or not is_equal_approx(config.neutral_weight_multiplier, expected[tier]):
			push_error("TT-14 Tier %d Neutral 倍率不符合任务卡" % tier)
			return false
	var legacy_config: CombatStageTierConfig = TIER_CONFIG.new()
	if not is_equal_approx(legacy_config.neutral_weight_multiplier, 1.0):
		push_error("TT-14 旧 Tier 配置默认值应为 1 倍")
		return false
	return true


# 同一关卡在 Tier 0 可抽到 Neutral，在 Tier 5 只抽有效的其他类别。
func _test_selector_tier_zero_and_five() -> bool:
	var level: LevelProfile = _make_level()
	var selector: NormalSpeechSelector = SELECTOR.new()
	level.orthodox_ratio = 0.0
	if selector.select_next_normal_speech(level, 1.0).tendency_id != "neutral":
		push_error("TT-14 Tier 0 未保留 Neutral 基础权重")
		return false
	level.orthodox_ratio = 1.0
	if selector.select_next_normal_speech(level, 0.0).tendency_id != "orthodox":
		push_error("TT-14 Tier 5 仍抽到 Neutral")
		return false
	return true


# CombatStage 绑定真实弹幕区域后，升降档影响下一次新批次，不回写现有弹幕。
func _test_tier_change_affects_next_generation() -> bool:
	var area: BarrageArea = BARRAGE_AREA.instantiate() as BarrageArea
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(1024.0, 760.0)
	root.add_child(area)
	var stage: CombatStage = COMBAT_STAGE.new(TIER_CATALOG)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	var level: LevelProfile = _make_level()
	level.orthodox_ratio = 0.0
	level.base_batch_count = 1
	level.base_spawn_interval_seconds = 100.0
	if not area.start_normal_generation(level) or area.get_current_barrage_counts()["normal"] != 1:
		push_error("TT-14 Tier 0 首批 Neutral 未生成")
		area.free()
		return false
	stage.update_tier_for_pk(1.0)
	area.stop_normal_generation()
	area.start_normal_generation(level)
	if area.get_current_barrage_counts()["normal"] != 1:
		push_error("TT-14 Tier 5 后续批次仍生成 Neutral 或改动了已生成弹幕")
		area.free()
		return false
	stage.update_tier_for_pk(0.0)
	area.stop_normal_generation()
	area.start_normal_generation(level)
	if area.get_current_barrage_counts()["normal"] != 2:
		push_error("TT-14 降回 Tier 0 后 Neutral 未恢复生成")
		area.free()
		return false
	area.free()
	return true


func _make_level() -> LevelProfile:
	var level: LevelProfile = LEVEL_PROFILE.new()
	level.neutral_ratio = 1.0
	level.orthodox_ratio = 1.0
	var neutral: LevelSpeech = LEVEL_SPEECH.new()
	neutral.original_sentence_id = "neutral-test"
	neutral.text = "普通闲聊"
	neutral.tendency_id = "neutral"
	var orthodox: LevelSpeech = LEVEL_SPEECH.new()
	orthodox.original_sentence_id = "orthodox-test"
	orthodox.text = "正统话语"
	orthodox.tendency_id = "orthodox"
	level.normal_speech_pool = [neutral, orthodox]
	return level
