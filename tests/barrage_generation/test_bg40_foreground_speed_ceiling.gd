extends SceneTree

const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")
const TIER_CATALOG := preload("res://data/combat_stage/tier_catalog.tres")
const EVIDENCE_PATH := "res://docs/3. BarrageGeneration/evidence/BG40_foreground_speed_ceiling_test.png"
const AREA_SIZE := Vector2(1024.0, 760.0)
const GUI_SAMPLE_SECONDS := 8.0
const SPEED_SAMPLE_SECONDS := 0.2
const SPEED_TOLERANCE := 12.0

class FrameDeltaRecorder extends Node:
	var elapsed_seconds: float = 0.0

	func _process(delta: float) -> void:
		elapsed_seconds += delta

var _frame_delta_recorder: FrameDeltaRecorder


func _initialize() -> void:
	call_deferred("_run_test")


## 使用真实 Tier、BarrageArea 和 BarrageView 验证限速归属及当前动态倍率行为。
func _run_test() -> void:
	var failures: Array[String] = []
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	var tier_catalog: CombatStageTierCatalog = TIER_CATALOG as CombatStageTierCatalog
	if area == null or tier_catalog == null:
		push_error("FAIL BG-40: BarrageArea 或 Tier Catalog 加载失败")
		quit(1)
		return

	if DisplayServer.get_name() != "headless":
		_prepare_visual_canvas()
	root.add_child(area)
	_set_area_rect(area)
	_frame_delta_recorder = FrameDeltaRecorder.new()
	root.add_child(_frame_delta_recorder)
	if not is_equal_approx(area.maximum_foreground_move_speed_pixels_per_second, 100.0):
		failures.append("default ceiling follows the current 100 px/s LevelProfile baseline")
	area.maximum_foreground_move_speed_pixels_per_second = 150.0
	area.base_lifetime_seconds = 60.0
	area.repeat_barrage_screen_cap = 8
	await process_frame

	var profile := LevelProfile.new()
	profile.streamer_id = "bg40_test_streamer"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 100.0
	profile.normal_barrage_screen_cap = 24
	var short_speech: LevelSpeech = _make_speech("bg40_short_test", "TEST_ONLY：短句易读")

	var stage := CombatStage.new(tier_catalog)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	if not area.start_normal_generation(profile):
		failures.append("normal generation accepts the TEST_ONLY profile")

	# T1–T5 都經現有 Tier 訊號入口更新；同一速度 API 按可調 Inspector 上限回傳結果。
	var pk_for_tier: Array[float] = [0.0, 0.60, 0.64, 0.71, 0.79, 1.0]
	for tier: int in range(1, 6):
		if not stage.update_tier_for_pk(pk_for_tier[tier]) or stage.get_current_tier() != tier:
			failures.append("CombatStage reaches T%d for the speed check" % tier)
			continue
		var tier_config: CombatStageTierConfig = tier_catalog.get_tier_config(tier)
		var uncapped_speed: float = profile.base_move_speed_pixels_per_second * tier_config.movement_speed_multiplier
		var expected_speed: float = minf(uncapped_speed, area.maximum_foreground_move_speed_pixels_per_second)
		var actual_speed: float = area.get_foreground_move_speed_pixels_per_second(profile)
		if not is_equal_approx(actual_speed, expected_speed) or actual_speed > area.maximum_foreground_move_speed_pixels_per_second:
			failures.append("T%d speed %.1f must equal capped base × Tier speed %.1f" % [tier, actual_speed, expected_speed])

	# T1 是低档未触顶的实际运动样本，确认现有线性路径使用统一速度入口。
	stage.update_tier_for_pk(pk_for_tier[1])
	var low_tier_view: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	var low_tier_speed: float = await _measure_horizontal_speed(low_tier_view, SPEED_SAMPLE_SECONDS)
	_expect_speed("T1 ordinary foreground", low_tier_speed, 120.0, failures)
	if low_tier_view != null:
		area.end_barrage(low_tier_view.get_instance_id())
		await process_frame

	# T5 超过可调上限时，已创建实例和降档后新实例分别保留各自创建时的速度。
	stage.update_tier_for_pk(pk_for_tier[5])
	var high_tier_view: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	if high_tier_view == null:
		failures.append("T5 ordinary foreground spawns")
	else:
		var high_start_x: float = high_tier_view.position.x
		var sample_started_seconds: float = _frame_delta_recorder.elapsed_seconds
		await create_timer(SPEED_SAMPLE_SECONDS).timeout
		var elapsed_seconds: float = _frame_delta_recorder.elapsed_seconds - sample_started_seconds
		var high_tier_speed: float = (high_start_x - high_tier_view.position.x) / elapsed_seconds
		_expect_speed("T5 capped ordinary foreground", high_tier_speed, 150.0, failures)

	var downgraded_to_t1: bool = stage.update_tier_for_pk(pk_for_tier[1]) and stage.get_current_tier() == 1
	var dynamic_view: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	if not downgraded_to_t1 or dynamic_view == null or high_tier_view == null:
		failures.append("the dynamic Tier downgrade creates a new ordinary foreground view")
	else:
		var high_start_x: float = high_tier_view.position.x
		var dynamic_start_x: float = dynamic_view.position.x
		var sample_started_seconds: float = _frame_delta_recorder.elapsed_seconds
		await create_timer(SPEED_SAMPLE_SECONDS).timeout
		var elapsed_seconds: float = _frame_delta_recorder.elapsed_seconds - sample_started_seconds
		_expect_speed("existing T5 view after downgrade", (high_start_x - high_tier_view.position.x) / elapsed_seconds, 150.0, failures)
		_expect_speed("new T1 view after downgrade", (dynamic_start_x - dynamic_view.position.x) / elapsed_seconds, 120.0, failures)

	# Repeat 保持既有公式；BG-42 静止请求直接保持零速度，不经过移动速度上限。
	stage.update_tier_for_pk(pk_for_tier[5])
	var repeat_plan := RepeatPlan.new()
	repeat_plan.original_line_id = &"bg40_test_repeat"
	repeat_plan.original_line_text = "TEST_ONLY 复读原句"
	repeat_plan.display_text = "TEST_ONLY：复读独立速度"
	repeat_plan.lifetime_seconds = 60.0
	var repeat_view: BarrageView = area.spawn_repeat_barrage(repeat_plan)
	var repeat_speed: float = await _measure_horizontal_speed(repeat_view, SPEED_SAMPLE_SECONDS)
	_expect_speed("Repeat with independent speed semantics", repeat_speed, 220.0, failures)

	var stationary_view: BarrageView = area.spawn_normal_barrage(profile, short_speech, [], true)
	if stationary_view == null:
		failures.append("opt-in BG-42 static normal foreground spawns")
	else:
		var stationary_position: Vector2 = stationary_view.position
		await create_timer(SPEED_SAMPLE_SECONDS).timeout
		if stationary_view.position != stationary_position:
			failures.append("opt-in BG-42 zero-speed static view remains stationary")

	if DisplayServer.get_name() != "headless":
		await _show_visual_example(area, profile, short_speech, failures)

	# Paradox 使用六条独立候选与自身 Config 速度，不受普通前景上限影响。
	area.clear_barrages()
	await process_frame
	var true_lines: Array[LevelContradiction] = [_make_contradiction("bg40_test_true", "TEST_ONLY 真候选")]
	var false_lines: Array[LevelContradiction] = []
	for index: int in range(ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT):
		false_lines.append(_make_contradiction("bg40_test_false_%d" % index, "TEST_ONLY 假候选 %d" % index))
	var paradox_config := ContradictionWindowConfig.new()
	paradox_config.duration_seconds = 60.0
	paradox_config.movement_speed_multiplier = 2.5
	var paradox_started: bool = area.start_contradiction_generation(profile, true_lines, false_lines, paradox_config)
	var paradox_views: Array[BarrageView] = _get_contradiction_views(area)
	if not paradox_started or paradox_views.size() != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT:
		failures.append("Paradox keeps its one-true/five-false six-candidate set")
	else:
		var paradox_speed: float = await _measure_horizontal_speed(paradox_views[0], SPEED_SAMPLE_SECONDS)
		_expect_speed("Paradox config speed", paradox_speed, 250.0, failures)
		if paradox_speed <= area.maximum_foreground_move_speed_pixels_per_second:
			failures.append("Paradox candidate speed remains independent of the normal foreground ceiling")

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS BG-40: T1–T5 cap API, T1/T5/dynamic movement, Repeat/Paradox isolation and BG-42 static request")
	else:
		push_error("FAIL BG-40: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)


func _measure_horizontal_speed(view: BarrageView, sample_seconds: float) -> float:
	if view == null or not is_instance_valid(view):
		return -1.0
	var initial_x: float = view.position.x
	var started_seconds: float = _frame_delta_recorder.elapsed_seconds
	await create_timer(sample_seconds).timeout
	if not is_instance_valid(view):
		return -1.0
	var elapsed_seconds: float = _frame_delta_recorder.elapsed_seconds - started_seconds
	return (initial_x - view.position.x) / elapsed_seconds


func _expect_speed(label: String, actual: float, expected: float, failures: Array[String]) -> void:
	if actual < 0.0 or absf(actual - expected) > SPEED_TOLERANCE:
		failures.append("%s speed %.1f px/s; expected %.1f ± %.1f" % [label, actual, expected, SPEED_TOLERANCE])


func _make_speech(sentence_id: String, sentence_text: String) -> LevelSpeech:
	var speech := LevelSpeech.new()
	speech.original_sentence_id = sentence_id
	speech.text = sentence_text
	speech.tendency_id = "orthodox"
	return speech


func _make_contradiction(sentence_id: String, sentence_text: String) -> LevelContradiction:
	var contradiction := LevelContradiction.new()
	contradiction.original_sentence_id = sentence_id
	contradiction.text = sentence_text
	return contradiction


func _get_contradiction_views(area: BarrageArea) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child in area.get_children():
		if child is BarrageView and child.runtime_record != null and child.runtime_record.is_contradiction:
			views.append(child as BarrageView)
	return views


func _set_area_rect(area: BarrageArea) -> void:
	area.anchor_left = 0.0
	area.anchor_top = 0.0
	area.anchor_right = 0.0
	area.anchor_bottom = 0.0
	if DisplayServer.get_name() == "headless":
		area.offset_left = 0.0
		area.offset_top = 0.0
	else:
		area.offset_left = 448.0
		area.offset_top = 72.0
	area.offset_right = area.offset_left + AREA_SIZE.x
	area.offset_bottom = area.offset_top + AREA_SIZE.y


func _prepare_visual_canvas() -> void:
	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(1920.0, 1080.0)
	background.color = Color("#10141b")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	root.move_child(background, 0)

	var status_bar := ColorRect.new()
	status_bar.position = Vector2(448.0, 0.0)
	status_bar.size = Vector2(1024.0, 72.0)
	status_bar.color = Color("#222a35")
	status_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_bar)

	var title := Label.new()
	title.position = Vector2(472.0, 12.0)
	title.size = Vector2(920.0, 48.0)
	title.text = "BG-40 TEST_ONLY 速度上限演示 · Tier 5 原始 220 → 当前上限 150 px/s"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f4f6fa"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)


## GUI 仅用脚本生成的 TEST_ONLY 短句确认真实渲染，不代表正式词库的可读性验收。
func _show_visual_example(area: BarrageArea, profile: LevelProfile, short_speech: LevelSpeech, failures: Array[String]) -> void:
	area.clear_barrages()
	await process_frame
	area.maximum_foreground_move_speed_pixels_per_second = 150.0
	var sample: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	if sample == null:
		failures.append("GUI TEST_ONLY short speech renders in the current BarrageArea")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var evidence_directory: String = ProjectSettings.globalize_path("res://docs/3. BarrageGeneration/evidence")
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var save_error: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(EVIDENCE_PATH))
	if save_error != OK:
		failures.append("GUI TEST_ONLY screenshot saves (%s)" % error_string(save_error))
	else:
		print("BG-40 visual evidence: %s" % ProjectSettings.globalize_path(EVIDENCE_PATH))
	await create_timer(GUI_SAMPLE_SECONDS, true).timeout
