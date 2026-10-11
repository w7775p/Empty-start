extends SceneTree

const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")
const AREA_SIZE := Vector2(1024.0, 760.0)
const EVIDENCE_PATH := "res://docs/3. BarrageGeneration/evidence/BG21_curved_motion_gui.png"
const SAMPLE_SECONDS := 1.0
const SPEED_TOLERANCE := 5.0

class FrameDeltaRecorder extends Node:
	var elapsed_seconds: float = 0.0

	## 记录引擎模拟时间，给移动速度断言提供稳定分母。
	func _process(delta: float) -> void:
		elapsed_seconds += delta


class MotionTrailRecorder extends Node:
	var view: BarrageView
	var line: Line2D

	## 沿真实视图下沿追加轨迹点，避免尾迹被文字卡片遮挡。
	func _process(_delta: float) -> void:
		if is_instance_valid(view) and is_instance_valid(line):
			line.add_point(view.position + Vector2(view.size.x * 0.5, view.size.y + 9.0))


var _frame_delta_recorder: FrameDeltaRecorder


## 延迟到 SceneTree 初始化后再装配测试节点。
func _initialize() -> void:
	call_deferred("_run_test")


## 覆盖普通前景曲线、BG-40 限速、BG-42 静止请求及 Repeat / Paradox 隔离。
func _run_test() -> void:
	seed(21021)
	var failures: Array[String] = []
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if area == null:
		push_error("FAIL BG-21: BarrageArea Scene failed to load")
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		_prepare_visual_canvas()
	root.add_child(area)
	_set_area_rect(area)
	_frame_delta_recorder = FrameDeltaRecorder.new()
	root.add_child(_frame_delta_recorder)
	await process_frame

	area.base_lifetime_seconds = 60.0
	area.repeat_barrage_screen_cap = 8
	area.maximum_foreground_move_speed_pixels_per_second = 96.0
	area.curved_foreground_motion_amplitude_pixels = 96.0
	var profile := LevelProfile.new()
	profile.streamer_id = "bg21_test_streamer"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 360.0
	profile.normal_barrage_screen_cap = 24
	if not area.start_normal_generation(profile):
		failures.append("test profile starts normal generation")
	if not is_equal_approx(area.get_foreground_move_speed_pixels_per_second(profile), 96.0):
		failures.append("ordinary curve speed uses the current BG-40 ceiling")

	var short_speech := _make_speech("bg21_short", "曲线移动保持句子完整可读。")
	area.curved_foreground_motion_enabled = false
	var straight_view: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	if straight_view == null:
		failures.append("disabled curve option preserves ordinary foreground spawning")
	else:
		var straight_start_y: float = straight_view.position.y
		var straight_speed: Dictionary = await _measure_motion(straight_view, SAMPLE_SECONDS)
		if absf(straight_view.position.y - straight_start_y) > 0.1:
			failures.append("disabled curve option preserves the existing horizontal path")
		_expect_speed("straight ordinary foreground", float(straight_speed.get("speed", -1.0)), 96.0, failures)
		area.end_barrage(straight_view.get_instance_id())
		await process_frame

	area.curved_foreground_motion_enabled = true
	var curved_view: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	var curve_height: float = 0.0
	if curved_view == null:
		failures.append("enabled curve option spawns an ordinary foreground view")
	else:
		var curve_start: Vector2 = curved_view.position
		var gui_trail: Dictionary = _begin_gui_motion_trail(area, curved_view) if DisplayServer.get_name() != "headless" else {}
		var curved_motion: Dictionary = await _measure_motion(curved_view, SAMPLE_SECONDS)
		curve_height = absf(curved_view.position.y - curve_start.y)
		if curve_height < 8.0 or curved_view.position.x >= curve_start.x:
			failures.append("ordinary foreground follows a visible curve while progressing across the area")
		if not _is_fully_inside(area, curved_view):
			failures.append("curved foreground keeps the full readable view inside the battle area")
		_expect_speed("curved ordinary foreground", float(curved_motion.get("speed", -1.0)), 96.0, failures)
		var max_step_speed: float = float(curved_motion.get("max_step_speed", -1.0))
		if max_step_speed > 96.1:
			failures.append("curved path frame speed %.1f px/s must stay within the 96 px/s BG-40 ceiling" % max_step_speed)
		if DisplayServer.get_name() != "headless":
			await _save_gui_evidence(curved_view, gui_trail, failures)
		area.end_barrage(curved_view.get_instance_id())
		await process_frame

	# 调低弧高后再次生成，确认 Inspector 参数改变后续普通实例的实际轨迹。
	area.curved_foreground_motion_amplitude_pixels = 32.0
	var small_curve_view: BarrageView = area.spawn_normal_barrage(profile, short_speech)
	if small_curve_view == null:
		failures.append("ordinary foreground spawns with a smaller configured curve amplitude")
	else:
		var small_curve_start: Vector2 = small_curve_view.position
		await _measure_motion(small_curve_view, SAMPLE_SECONDS)
		var small_curve_height: float = absf(small_curve_view.position.y - small_curve_start.y)
		if small_curve_height < 2.0 or small_curve_height >= curve_height:
			failures.append("configured curve amplitude controls the next ordinary view's arc height")
		area.end_barrage(small_curve_view.get_instance_id())
		await process_frame

	# BG-42 静止请求覆盖区域曲线开关，实例继续固定在自己的随机落点。
	var static_view: BarrageView = area.spawn_normal_barrage(profile, short_speech, [], true)
	if static_view == null:
		failures.append("BG-42 static foreground request still spawns with curved mode enabled")
	else:
		var static_position: Vector2 = static_view.position
		await create_timer(0.25).timeout
		if static_view.position != static_position:
			failures.append("BG-42 static foreground request bypasses curve movement")
		area.end_barrage(static_view.get_instance_id())
		await process_frame

	# Repeat 仍走原始横向速度公式；区域曲线开关只影响普通前景。
	var repeat_plan := RepeatPlan.new()
	repeat_plan.original_line_id = &"bg21_repeat"
	repeat_plan.original_line_text = "Repeat original line"
	repeat_plan.display_text = "复读保留原有直线和速度。"
	repeat_plan.lifetime_seconds = 60.0
	var repeat_static: BarrageView = area.spawn_repeat_barrage(repeat_plan, true)
	if repeat_static == null:
		failures.append("BG-42 static Repeat request still spawns with curved mode enabled")
	else:
		var repeat_static_position: Vector2 = repeat_static.position
		await create_timer(0.25).timeout
		if repeat_static.position != repeat_static_position:
			failures.append("BG-42 static Repeat request bypasses curve movement")
		area.end_barrage(repeat_static.get_instance_id())
		await process_frame

	var repeat_view: BarrageView = area.spawn_repeat_barrage(repeat_plan)
	if repeat_view == null:
		failures.append("Repeat spawns while ordinary curved motion is enabled")
	else:
		var repeat_start: Vector2 = repeat_view.position
		var repeat_motion: Dictionary = await _measure_motion(repeat_view, 0.25)
		if absf(repeat_view.position.y - repeat_start.y) > 0.1:
			failures.append("Repeat retains its straight horizontal path")
		_expect_speed("Repeat independent speed", float(repeat_motion.get("horizontal_speed", -1.0)), 360.0, failures)
		area.end_barrage(repeat_view.get_instance_id())
		await process_frame

	# Paradox 候选仍沿自己的配置速度直线移动，不读取普通前景曲线和限速选项。
	area.clear_barrages()
	await process_frame
	var true_lines: Array[LevelContradiction] = [_make_contradiction("bg21_true", "TEST_ONLY 真候选")]
	var false_lines: Array[LevelContradiction] = []
	for index: int in range(ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT):
		false_lines.append(_make_contradiction("bg21_false_%d" % index, "TEST_ONLY 假候选 %d" % index))
	var paradox_config := ContradictionWindowConfig.new()
	paradox_config.duration_seconds = 60.0
	paradox_config.movement_speed_multiplier = 1.5
	var paradox_started: bool = area.start_contradiction_generation(profile, true_lines, false_lines, paradox_config)
	var paradox_views: Array[BarrageView] = _get_contradiction_views(area)
	if not paradox_started or paradox_views.size() != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT:
		failures.append("Paradox keeps the existing fixed six-candidate generation")
	else:
		var paradox_start: Vector2 = paradox_views[0].position
		var paradox_motion: Dictionary = await _measure_motion(paradox_views[0], 0.2)
		if absf(paradox_views[0].position.y - paradox_start.y) > 0.1:
			failures.append("Paradox candidates retain their straight horizontal path")
		_expect_speed("Paradox config speed", float(paradox_motion.get("horizontal_speed", -1.0)), 540.0, failures)
		if float(paradox_motion.get("horizontal_speed", -1.0)) <= area.maximum_foreground_move_speed_pixels_per_second:
			failures.append("Paradox speed remains independent of the ordinary foreground ceiling")

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS BG-21: optional curved ordinary motion, BG-40 speed ceiling, BG-42 static requests, Repeat and Paradox isolation")
	else:
		push_error("FAIL BG-21: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)


## 按引擎帧时间累计实际轨迹长度，避免 headless 墙钟时间造成错误速度读数。
func _measure_motion(view: BarrageView, sample_seconds: float) -> Dictionary:
	if view == null or not is_instance_valid(view):
		return {"speed": -1.0, "horizontal_speed": -1.0, "max_step_speed": -1.0}
	var start_position: Vector2 = view.position
	var previous_position: Vector2 = start_position
	var started_seconds: float = _frame_delta_recorder.elapsed_seconds
	var previous_seconds: float = started_seconds
	var path_distance: float = 0.0
	var max_step_speed: float = 0.0
	while _frame_delta_recorder.elapsed_seconds - started_seconds < sample_seconds:
		await process_frame
		if not is_instance_valid(view):
			return {"speed": -1.0, "horizontal_speed": -1.0, "max_step_speed": -1.0}
		var current_seconds: float = _frame_delta_recorder.elapsed_seconds
		var current_position: Vector2 = view.position
		var frame_seconds: float = current_seconds - previous_seconds
		var frame_distance: float = previous_position.distance_to(current_position)
		if frame_seconds > 0.0:
			path_distance += frame_distance
			max_step_speed = maxf(max_step_speed, frame_distance / frame_seconds)
		previous_position = current_position
		previous_seconds = current_seconds
	var elapsed_seconds: float = _frame_delta_recorder.elapsed_seconds - started_seconds
	var horizontal_distance: float = absf(view.position.x - start_position.x)
	return {
		"speed": path_distance / elapsed_seconds if elapsed_seconds > 0.0 else -1.0,
		"horizontal_speed": horizontal_distance / elapsed_seconds if elapsed_seconds > 0.0 else -1.0,
		"max_step_speed": max_step_speed,
	}


## 将实际模拟速度与对应配置比较，并把偏差保留为明确失败原因。
func _expect_speed(label: String, actual: float, expected: float, failures: Array[String]) -> void:
	if actual < 0.0 or absf(actual - expected) > SPEED_TOLERANCE:
		failures.append("%s speed %.1f px/s; expected %.1f ± %.1f" % [label, actual, expected, SPEED_TOLERANCE])


## 为回归样本构造不依赖项目正式词库的短句。
func _make_speech(sentence_id: String, sentence_text: String) -> LevelSpeech:
	var speech := LevelSpeech.new()
	speech.original_sentence_id = sentence_id
	speech.text = sentence_text
	speech.tendency_id = "orthodox"
	return speech


## 为 Paradox 隔离验证构造独立候选。
func _make_contradiction(sentence_id: String, sentence_text: String) -> LevelContradiction:
	var contradiction := LevelContradiction.new()
	contradiction.original_sentence_id = sentence_id
	contradiction.text = sentence_text
	return contradiction


## 从真实区域子节点读取当前六条 Paradox 视图。
func _get_contradiction_views(area: BarrageArea) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child in area.get_children():
		if child is BarrageView and child.runtime_record != null and child.runtime_record.is_contradiction:
			views.append(child as BarrageView)
	return views


## 验证曲线路径尚未把完整话语移出有效战斗区。
func _is_fully_inside(area: BarrageArea, view: BarrageView) -> bool:
	return view.position.x >= 0.0 and view.position.y >= 0.0 \
		and view.position.x + view.size.x <= area.size.x \
		and view.position.y + view.size.y <= area.size.y


## 对齐 Sandbox 当前战斗区域的实际基准尺寸。
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


## GUI 证据使用与系统既有运行测试一致的深色中央战斗区。
func _prepare_visual_canvas() -> void:
	var background := ColorRect.new()
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
	title.position = Vector2(472.0, 8.0)
	title.size = Vector2(920.0, 36.0)
	title.text = "BG-21 曲线运动实测 · TEST_ONLY · 普通前景速度上限 96 px/s"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f4f6fa"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(472.0, 42.0)
	subtitle.size = Vector2(920.0, 24.0)
	subtitle.text = "青色尾迹随真实视图位置更新；正式词库可读性仍需实场人工验收。"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#c4cbd5"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle)


## GUI 实测时跟踪真实 BarrageView 坐标，尾迹只用于展示刚走过的路径。
func _begin_gui_motion_trail(area: BarrageArea, view: BarrageView) -> Dictionary:
	var line := Line2D.new()
	line.width = 4.0
	line.default_color = Color("#45dbe8")
	line.z_index = 0
	area.add_child(line)
	var trail_recorder := MotionTrailRecorder.new()
	trail_recorder.view = view
	trail_recorder.line = line
	root.add_child(trail_recorder)
	return {"line": line, "recorder": trail_recorder}


## 保存包含真实运行尾迹的画面；截图仅证明该实例运动，不代替正式词库验收。
func _save_gui_evidence(view: BarrageView, gui_trail: Dictionary, failures: Array[String]) -> void:
	if not is_instance_valid(view):
		failures.append("GUI curve view remains alive while saving moving evidence")
	await create_timer(5.0).timeout
	for _frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var evidence_directory: String = ProjectSettings.globalize_path("res://docs/3. BarrageGeneration/evidence")
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var save_error: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(EVIDENCE_PATH))
	if save_error != OK:
		failures.append("GUI moving evidence saves (%s)" % error_string(save_error))
	else:
		print("BG-21 GUI moving evidence: %s" % ProjectSettings.globalize_path(EVIDENCE_PATH))
	var trail_recorder: MotionTrailRecorder = gui_trail.get("recorder") as MotionTrailRecorder
	if trail_recorder != null:
		trail_recorder.queue_free()
