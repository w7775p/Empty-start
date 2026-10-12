extends SceneTree

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const TEST_TIER_CATALOG: CombatStageTierCatalog = preload("res://data/test_only/combat_stage/bg39_tier_motion_catalog.tres")

const SAMPLE_COUNT: int = 100
const AREA_SIZE: Vector2 = Vector2(1920.0, 1080.0)


## 等场景树和全局脚本缓存就绪后再创建真实组件。
func _initialize() -> void:
	call_deferred("_run_test")


## 使用真实 CombatStage 把当前 Tier 权重发布给 BarrageArea 并抽样新视图类型。
func _run_test() -> void:
	seed(39039)
	var failures: Array[String] = []
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if area == null or TEST_TIER_CATALOG == null:
		push_error("FAIL BG-39: BarrageArea 或 TEST_ONLY Tier Catalog 加载失败")
		quit(1)
		return
	area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	area.size = AREA_SIZE
	area.base_lifetime_seconds = 60.0
	area.normal_foreground_layer_change_interval_seconds = 0.0
	root.add_child(area)
	await process_frame

	var profile := LevelProfile.new()
	profile.level_id = "test_bg39_motion_distribution"
	profile.streamer_id = "test_bg39"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 240.0
	profile.normal_barrage_screen_cap = 160
	profile.special_trait_ids.append("occlusion")
	var speech: LevelSpeech = _make_speech("test_bg39_sentence", "TEST_ONLY 按当前 Tier 选择运动类型。")
	var stage := CombatStage.new(TEST_TIER_CATALOG)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	area.start_normal_generation(profile)

	var tier_zero_counts: Dictionary = await _sample_mode_counts(area, profile, speech, 12, failures)
	if int(tier_zero_counts.get(BarrageView.ForegroundMotionMode.STRAIGHT, 0)) != 12:
		failures.append("unset T0 motion weights safely choose straight")
	area.clear_barrages()
	await process_frame

	var tier_one_counts: Dictionary = {}
	if not stage.update_tier_for_pk(0.60) or stage.get_current_tier() != 1:
		failures.append("real CombatStage advances to T1 using TEST_ONLY PK thresholds")
	else:
		tier_one_counts = await _sample_mode_counts(area, profile, speech, SAMPLE_COUNT, failures)
		if int(tier_one_counts.get(BarrageView.ForegroundMotionMode.STRAIGHT, 0)) <= int(
			tier_one_counts.get(BarrageView.ForegroundMotionMode.CURVED, 0)
		):
			failures.append("T1 test weights produce more straight than curved views")
		if int(tier_one_counts.get(BarrageView.ForegroundMotionMode.WANDERING, 0)) != 0:
			failures.append("T1 test weights exclude wandering")
		if int(tier_one_counts.get(BarrageView.ForegroundMotionMode.SPEED_CHANGE, 0)) != 0:
			failures.append("T1 test weights exclude speed change")
	area.clear_barrages()
	await process_frame

	var tier_two_counts: Dictionary = {}
	if not stage.update_tier_for_pk(0.68) or stage.get_current_tier() != 2:
		failures.append("real CombatStage advances to T2 from the configured PK range")
	else:
		tier_two_counts = await _sample_mode_counts(area, profile, speech, 24, failures)
		if int(tier_two_counts.get(BarrageView.ForegroundMotionMode.SPEED_CHANGE, 0)) != 24:
			failures.append("T2 test weights select speed-change motion")
	area.clear_barrages()
	await process_frame

	var tier_three_counts: Dictionary = {}
	if not stage.update_tier_for_pk(0.75) or stage.get_current_tier() != 3:
		failures.append("real CombatStage advances to T3 from the configured PK range")
	else:
		tier_three_counts = await _sample_mode_counts(area, profile, speech, SAMPLE_COUNT, failures)
		for motion_mode: int in range(4):
			if int(tier_three_counts.get(motion_mode, 0)) <= 0:
				failures.append("T3 mixed weights produce motion type %d" % motion_mode)
	area.clear_barrages()
	await process_frame

	var tier_four_counts: Dictionary = {}
	if not stage.update_tier_for_pk(0.85) or stage.get_current_tier() != 4:
		failures.append("real CombatStage advances to T4 from the configured PK range")
	else:
		tier_four_counts = await _sample_mode_counts(area, profile, speech, SAMPLE_COUNT, failures)
		if int(tier_four_counts.get(BarrageView.ForegroundMotionMode.WANDERING, 0)) != SAMPLE_COUNT:
			failures.append("T4 test weights select wandering motion")
		if int(tier_four_counts.get(BarrageView.ForegroundMotionMode.STRAIGHT, 0)) >= int(
			tier_one_counts.get(BarrageView.ForegroundMotionMode.STRAIGHT, 0)
		):
			failures.append("T1 and T4 test distributions differ for actual spawned views")

	# T4 只有游荡权重时，静止遮挡仍不进入普通运动抽选。
	var occlusion_view: BarrageView = area.spawn_normal_barrage(
		profile, speech, [BarrageTraitSet.OCCLUSION]
	)
	if (occlusion_view == null or occlusion_view.get_foreground_motion_mode() == BarrageView.ForegroundMotionMode.WANDERING
			or not occlusion_view.runtime_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION)):
		failures.append("static occlusion remains outside the Tier motion selection")
	else:
		var fixed_position: Vector2 = occlusion_view.position
		await create_timer(0.15).timeout
		if occlusion_view.position != fixed_position:
			failures.append("occlusion remains stationary under T4 wandering weights")
	area.clear_barrages()
	await process_frame

	var repeat_plan := RepeatPlan.new()
	repeat_plan.original_line_id = &"bg39_repeat"
	repeat_plan.original_line_text = "TEST_ONLY 原句"
	repeat_plan.display_text = "TEST_ONLY 复读不参与运动类型选择。"
	repeat_plan.lifetime_seconds = 60.0
	var repeat_view: BarrageView = area.spawn_repeat_barrage(repeat_plan)
	if repeat_view == null or not repeat_view.runtime_record.is_repeat:
		failures.append("Repeat retains its independent spawn path")
	elif repeat_view.get_foreground_motion_mode() == BarrageView.ForegroundMotionMode.WANDERING:
		failures.append("Repeat is excluded from T4 motion selection")
	area.clear_barrages()
	await process_frame

	var true_lines: Array[LevelContradiction] = [_make_contradiction("bg39_paradox_true")]
	var false_lines: Array[LevelContradiction] = []
	for index: int in range(ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT):
		false_lines.append(_make_contradiction("bg39_paradox_false_%d" % index))
	var paradox_config := ContradictionWindowConfig.new()
	paradox_config.duration_seconds = 60.0
	paradox_config.movement_speed_multiplier = 1.0
	var paradox_started: bool = area.start_contradiction_generation(
		profile, true_lines, false_lines, paradox_config
	)
	var paradox_views: Array[BarrageView] = _get_contradiction_views(area)
	if not paradox_started or paradox_views.size() != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT:
		failures.append("Paradox retains its fixed candidate set")
	else:
		for view: BarrageView in paradox_views:
			if view.get_foreground_motion_mode() == BarrageView.ForegroundMotionMode.WANDERING:
				failures.append("Paradox is excluded from T4 motion selection")
				break

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("BG39_TIER_MOTION_PASS T0=%s T1=%s T2=%s T3=%s T4=%s exclusions=occlusion/repeat/paradox" % [
			str(tier_zero_counts), str(tier_one_counts), str(tier_two_counts), str(tier_three_counts), str(tier_four_counts)
		])
	else:
		push_error("FAIL BG-39: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)


## 按当前 Tier 权重生成真实 BarrageView，并统计其只读运动类型。
func _sample_mode_counts(
	area: BarrageArea, profile: LevelProfile, speech: LevelSpeech, sample_count: int, failures: Array[String]
) -> Dictionary:
	var counts: Dictionary = {}
	for _index: int in range(sample_count):
		var view: BarrageView = area.spawn_normal_barrage(profile, speech)
		if view == null:
			failures.append("Tier motion sample spawns each normal foreground view")
			break
		var motion_mode: int = view.get_foreground_motion_mode()
		counts[motion_mode] = int(counts.get(motion_mode, 0)) + 1
	return counts


## 创建不依赖正式词库的 TEST_ONLY 普通话语。
func _make_speech(sentence_id: String, sentence_text: String) -> LevelSpeech:
	var speech := LevelSpeech.new()
	speech.original_sentence_id = sentence_id
	speech.text = sentence_text
	speech.tendency_id = "neutral"
	return speech


## 创建保留稳定 ID 的 TEST_ONLY 矛盾句。
func _make_contradiction(sentence_id: String) -> LevelContradiction:
	var line := LevelContradiction.new()
	line.original_sentence_id = sentence_id
	line.text = "TEST_ONLY " + sentence_id
	return line


## 从真实 BarrageArea 子节点读取当前矛盾候选。
func _get_contradiction_views(area: BarrageArea) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child: Node in area.get_children():
		if child is BarrageView and (child as BarrageView).runtime_record != null \
				and (child as BarrageView).runtime_record.is_contradiction:
			views.append(child as BarrageView)
	return views
