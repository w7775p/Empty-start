extends SceneTree

const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")
const TIER_CATALOG_PATH := "res://data/combat_stage/tier_catalog.tres"
const PARADOX_CONFIG := preload("res://systems/contradiction_break/contradiction_window_config.tres")


func _initialize() -> void:
	call_deferred("_run_test")


## 用真实 BarrageArea 验证 Tier 覆盖、特性共槽、重开和 Paradox 回退。
func _run_test() -> void:
	var catalog: CombatStageTierCatalog = load(TIER_CATALOG_PATH) as CombatStageTierCatalog
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if catalog == null or area == null:
		push_error("FAIL BG-16: Tier Catalog 或 BarrageArea 加载失败")
		quit(1)
		return

	root.add_child(area)
	var stage := CombatStage.new(catalog)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	var profile := LevelProfile.new()
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 0.05
	profile.base_move_speed_pixels_per_second = 0.0
	profile.normal_barrage_screen_cap = 2
	profile.special_trait_ids.append("occlusion")
	profile.orthodox_ratio = 1.0
	var speech := LevelSpeech.new()
	speech.original_sentence_id = "bg16_test_sentence"
	speech.text = "前景容量"
	speech.tendency_id = "orthodox"
	profile.normal_speech_pool.append(speech)
	var trait_ids: Array[StringName] = [BarrageTraitSet.OCCLUSION]
	var failures: Array[String] = []

	if area.get_foreground_slot_count() != 0:
		failures.append("CombatStage T0 publishes the unfilled zero value")
	if not area.start_normal_generation(profile):
		failures.append("normal generation starts for the test profile")

	# 测试用一格名额，令 Tier 上限与关卡默认上限可区分。
	area.set_foreground_slot_count(1)
	var special_view: BarrageView = area.spawn_normal_barrage(profile, speech, trait_ids)
	var special_has_trait: bool = special_view != null and special_view.runtime_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION)
	var ordinary_blocked: bool = area.spawn_normal_barrage(profile, speech) == null
	var special_released: bool = special_view != null and area.end_barrage(special_view.get_instance_id())
	var ordinary_after_release: BarrageView = area.spawn_normal_barrage(profile, speech)
	if not special_has_trait or not ordinary_blocked or not special_released or ordinary_after_release == null:
		failures.append("ordinary and trait-bearing foreground instances share and release the Tier slot")

	# 容量满时 Timer 停止；升档扩容或实例释放后都应恢复批次。
	area.clear_barrages()
	profile.base_batch_count = 1
	area.set_foreground_slot_count(1)
	var timer_started: bool = area.start_normal_generation(profile)
	var timer_filled_slot: bool = area.get_current_barrage_counts()["normal"] == 1
	area.set_foreground_slot_count(2)
	var tier_increase_resumed: bool = false
	for _frame in range(60):
		if area.get_current_barrage_counts()["normal"] == 2:
			tier_increase_resumed = true
			break
		await process_frame
	var first_normal: BarrageView = null
	for child in area.get_children():
		if child is BarrageView and not child.is_queued_for_deletion():
			first_normal = child as BarrageView
			break
	var timer_slot_released: bool = first_normal != null and area.end_barrage(first_normal.get_instance_id())
	var timer_resumed: bool = false
	for _frame in range(60):
		if area.get_current_barrage_counts()["normal"] == 2:
			timer_resumed = true
			break
		await process_frame
	if not timer_started or not timer_filled_slot or not tier_increase_resumed or not timer_slot_released or not timer_resumed:
		failures.append("Tier increase and capacity release resume the ordinary generation Timer")

	# 清理并让 CombatStage 重开到 T0；0 应继续采用 LevelProfile 的两格 fallback。
	area.clear_barrages()
	profile.base_batch_count = 0
	stage.begin_combat()
	if area.get_foreground_slot_count() != 0 or not area.start_normal_generation(profile):
		failures.append("reopen resets the published Tier count to T0")
	var fallback_first: BarrageView = area.spawn_normal_barrage(profile, speech)
	var fallback_second: BarrageView = area.spawn_normal_barrage(profile, speech)
	var fallback_overflow: BarrageView = area.spawn_normal_barrage(profile, speech)
	if fallback_first == null or fallback_second == null or fallback_overflow != null:
		failures.append("T0 zero falls back to the LevelProfile capacity of two")

	# Paradox 固定生成六条矛盾，并使用独立容量；前景 Tier 与关卡普通上限不参与占位。
	area.clear_barrages()
	area.set_foreground_slot_count(1)
	var contradiction := LevelContradiction.new()
	contradiction.original_sentence_id = "test_bg16_paradox_true"
	contradiction.text = "TEST_ONLY 真句"
	var true_lines: Array[LevelContradiction] = [contradiction]
	var false_lines: Array[LevelContradiction] = []
	for index: int in range(ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT):
		var false_line := LevelContradiction.new()
		false_line.original_sentence_id = "test_bg16_paradox_false_%d" % index
		false_line.text = "TEST_ONLY 假句 %d" % index
		false_lines.append(false_line)
	var paradox_started: bool = area.start_contradiction_generation(profile, true_lines, false_lines, PARADOX_CONFIG)
	var paradox_count: int = int(area.get_current_barrage_counts().get("contradiction", 0))
	var paradox_overflow: BarrageView = area.spawn_contradiction_barrage(profile, false_lines[0])
	if not paradox_started or paradox_count != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT or paradox_overflow != null:
		failures.append("Paradox shows six candidates under its independent fixed-set capacity")

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS BG-16: Tier slot, special sharing, Timer resume, reopen fallback, and Paradox capacity")
	else:
		push_error("FAIL BG-16: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)
