extends SceneTree

const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")
const AREA_SIZE := Vector2(1024.0, 760.0)
const EVIDENCE_PATH := "res://docs/3. BarrageGeneration/evidence/BG22_speed_change_motion_gui.png"
const SPEED_CEILING := 96.0
const SPEED_TOLERANCE := 6.0

class FrameDeltaRecorder extends Node:
	var elapsed_seconds: float = 0.0

	## 累计引擎模拟时间，避免用墙钟测量 Godot 节点运动。
	func _process(delta: float) -> void:
		elapsed_seconds += delta


class MotionMonitor extends Node:
	var view: BarrageView
	var previous_position: Vector2 = Vector2.ZERO
	var max_step_speed: float = 0.0
	var max_speed_change_per_second: float = 0.0
	var _previous_step_speed: float = 0.0

	## 逐帧记录可见视图的真实速度上限与相邻帧速度变化。
	func watch(target: BarrageView) -> void:
		view = target
		previous_position = target.position
		max_step_speed = 0.0
		max_speed_change_per_second = 0.0
		_previous_step_speed = 0.0

	func _process(delta: float) -> void:
		if not is_instance_valid(view) or delta <= 0.0:
			return
		var current_position: Vector2 = view.position
		var current_step_speed: float = previous_position.distance_to(current_position) / delta
		max_step_speed = maxf(max_step_speed, current_step_speed)
		max_speed_change_per_second = maxf(
			max_speed_change_per_second, absf(current_step_speed - _previous_step_speed) / delta
		)
		_previous_step_speed = current_step_speed
		previous_position = current_position


class MotionTrailRecorder extends Node:
	var view: BarrageView
	var line: Line2D

	## 沿实际视图位置追加轨迹点，便于在图形运行中观察曲线和速度变化路径。
	func _process(_delta: float) -> void:
		if is_instance_valid(view) and is_instance_valid(line):
			line.add_point(view.position + Vector2(view.size.x * 0.5, view.size.y + 9.0))


var _frame_delta_recorder: FrameDeltaRecorder
var _evidence_subtitle: Label


## 等 SceneTree 完成初始化后再装配实际 BarrageArea 组件。
func _initialize() -> void:
	call_deferred("_run_test")


## 验证默认匀速、可调周期加减速、BG-40 上限、曲线复用及隔离路径。
func _run_test() -> void:
	seed(22022)
	var failures: Array[String] = []
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if area == null:
		push_error("FAIL BG-22: BarrageArea Scene failed to load")
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
	area.maximum_foreground_move_speed_pixels_per_second = SPEED_CEILING
	if area.speed_change_foreground_motion_enabled:
		failures.append("speed-change mode is disabled by default")
	var profile := LevelProfile.new()
	profile.streamer_id = "bg22_test_streamer"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 360.0
	profile.normal_barrage_screen_cap = 24
	if not area.start_normal_generation(profile):
		failures.append("test profile starts normal generation")
	var speech := _make_speech("bg22_normal", "前景话语保持平缓的加速与减速。")

	# 默认开关保持关闭时，普通前景继续按 BG-40 上限匀速直线移动。
	area.curved_foreground_motion_enabled = false
	area.speed_change_foreground_motion_enabled = false
	var default_view: BarrageView = area.spawn_normal_barrage(profile, speech)
	if default_view == null:
		failures.append("default ordinary foreground still spawns")
	else:
		var default_start: Vector2 = default_view.position
		var default_motion: Dictionary = await _measure_motion(default_view, 0.35)
		if absf(default_view.position.y - default_start.y) > 0.1:
			failures.append("default ordinary foreground keeps its existing horizontal path")
		_expect_speed("default ordinary foreground", float(default_motion.get("horizontal_speed", -1.0)), SPEED_CEILING, failures)
		area.end_barrage(default_view.get_instance_id())
		await process_frame

	# 同时启用曲线和周期变速，确认路径沿弧长读取当帧速度并保留速度上限。
	area.curved_foreground_motion_enabled = true
	area.curved_foreground_motion_amplitude_pixels = 128.0
	area.speed_change_foreground_motion_enabled = true
	# 使用不同于默认值的 4 秒周期，确认 Inspector 配置真实影响后续实例。
	area.speed_change_foreground_motion_cycle_seconds = 4.0
	var changing_view: BarrageView = area.spawn_normal_barrage(profile, speech)
	var monitor: MotionMonitor
	var gui_trail: Dictionary = {}
	if changing_view == null:
		failures.append("enabled speed-change ordinary foreground spawns")
	else:
		var start_position: Vector2 = changing_view.position
		var cycle_started_seconds: float = _frame_delta_recorder.elapsed_seconds
		monitor = MotionMonitor.new()
		monitor.watch(changing_view)
		root.add_child(monitor)
		if DisplayServer.get_name() != "headless":
			gui_trail = _begin_gui_motion_trail(area, changing_view)

		var early_motion: Dictionary = await _measure_motion(changing_view, 0.35)
		await _wait_until_elapsed(cycle_started_seconds + 0.8)
		var accelerating_motion: Dictionary = await _measure_motion(changing_view, 0.35)
		await _wait_until_elapsed(cycle_started_seconds + 1.8)
		var peak_motion: Dictionary = await _measure_motion(changing_view, 0.35)
		await _wait_until_elapsed(cycle_started_seconds + 2.8)
		var decelerating_motion: Dictionary = await _measure_motion(changing_view, 0.35)

		var early_speed: float = float(early_motion.get("speed", -1.0))
		var accelerating_speed: float = float(accelerating_motion.get("speed", -1.0))
		var peak_speed: float = float(peak_motion.get("speed", -1.0))
		var decelerating_speed: float = float(decelerating_motion.get("speed", -1.0))
		print(
			"BG-22 measured cycle: early %.1f, accelerating %.1f, peak %.1f, decelerating %.1f px/s; "
			% [early_speed, accelerating_speed, peak_speed, decelerating_speed],
			"max step %.1f px/s; max speed change %.1f px/s²"
			% [monitor.max_step_speed, monitor.max_speed_change_per_second]
		)
		if not (early_speed < accelerating_speed and accelerating_speed < peak_speed):
			failures.append("ordinary foreground speed rises smoothly from the cycle start toward its peak")
		if decelerating_speed >= peak_speed:
			failures.append("ordinary foreground speed decelerates after the cycle peak")
		if changing_view.position.x >= start_position.x or absf(changing_view.position.y - start_position.y) < 5.0:
			failures.append("accelerating ordinary view follows the enabled curved path across the area")
		if monitor.max_step_speed > SPEED_CEILING + 0.1:
			failures.append("combined curve and acceleration stay within the BG-40 speed ceiling")
		if monitor.max_speed_change_per_second > 80.0:
			failures.append("ordinary foreground acceleration has no abrupt per-frame speed jump")
		if DisplayServer.get_name() != "headless":
			await _save_gui_evidence(
				gui_trail, failures, early_speed, accelerating_speed, peak_speed, decelerating_speed
			)

		await _wait_until_elapsed(cycle_started_seconds + 3.7)
		var cycle_end_motion: Dictionary = await _measure_motion(changing_view, 0.2)
		if float(cycle_end_motion.get("speed", SPEED_CEILING)) >= 20.0:
			failures.append("configured cycle returns smoothly to low speed before repeating")
		area.end_barrage(changing_view.get_instance_id())
		await process_frame

	# 区域变速开关不能覆盖 BG-42 的显式静止请求。
	var static_view: BarrageView = area.spawn_normal_barrage(profile, speech, [], true)
	if static_view == null:
		failures.append("BG-42 static request still spawns with speed-change mode enabled")
	else:
		var static_position: Vector2 = static_view.position
		await create_timer(0.25).timeout
		if static_view.position != static_position:
			failures.append("BG-42 static request bypasses acceleration and curved movement")
		area.end_barrage(static_view.get_instance_id())
		await process_frame

	# Repeat 继续使用原始直线速度，不读取普通前景的变速、曲线或速度上限。
	var repeat_plan := RepeatPlan.new()
	repeat_plan.original_line_id = &"bg22_repeat"
	repeat_plan.original_line_text = "Repeat original line"
	repeat_plan.display_text = "复读沿用自己的匀速直线。"
	repeat_plan.lifetime_seconds = 60.0
	var repeat_view: BarrageView = area.spawn_repeat_barrage(repeat_plan)
	if repeat_view == null:
		failures.append("Repeat spawns while ordinary speed-change mode is enabled")
	else:
		var repeat_start: Vector2 = repeat_view.position
		var repeat_motion: Dictionary = await _measure_motion(repeat_view, 0.25)
		if absf(repeat_view.position.y - repeat_start.y) > 0.1:
			failures.append("Repeat retains its existing straight path")
		_expect_speed("Repeat independent speed", float(repeat_motion.get("horizontal_speed", -1.0)), 360.0, failures)
		area.end_barrage(repeat_view.get_instance_id())
		await process_frame

	# Paradox 候选继续读取自己的配置速度与直线路径。
	area.clear_barrages()
	await process_frame
	var true_lines: Array[LevelContradiction] = [_make_contradiction("bg22_true", "TEST_ONLY 真候选")]
	var false_lines: Array[LevelContradiction] = []
	for index: int in range(ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT):
		false_lines.append(_make_contradiction("bg22_false_%d" % index, "TEST_ONLY 假候选 %d" % index))
	var paradox_config := ContradictionWindowConfig.new()
	paradox_config.duration_seconds = 60.0
	paradox_config.movement_speed_multiplier = 1.5
	var paradox_started: bool = area.start_contradiction_generation(profile, true_lines, false_lines, paradox_config)
	var paradox_views: Array[BarrageView] = _get_contradiction_views(area)
	if not paradox_started or paradox_views.size() != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT:
		failures.append("Paradox keeps the existing fixed candidate generation")
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
		print("PASS BG-22: adjustable smooth speed cycle, BG-40 ceiling, BG-21 curve, BG-42 static, Repeat and Paradox isolation")
	else:
		push_error("FAIL BG-22: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)


## 按引擎帧时间累计实际路径长度与水平位移。
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
	return {
		"speed": path_distance / elapsed_seconds if elapsed_seconds > 0.0 else -1.0,
		"horizontal_speed": absf(view.position.x - start_position.x) / elapsed_seconds if elapsed_seconds > 0.0 else -1.0,
		"max_step_speed": max_step_speed,
	}


## 等待累计模拟时间抵达指定阶段，和移动测量使用同一帧时间来源。
func _wait_until_elapsed(target_seconds: float) -> void:
	while _frame_delta_recorder.elapsed_seconds < target_seconds:
		await process_frame


## 核对实际路径速度与对应配置的允许误差。
func _expect_speed(label: String, actual: float, expected: float, failures: Array[String]) -> void:
	if actual < 0.0 or absf(actual - expected) > SPEED_TOLERANCE:
		failures.append("%s speed %.1f px/s; expected %.1f ± %.1f" % [label, actual, expected, SPEED_TOLERANCE])


## 使用脚本内 TEST_ONLY 短句验证真实 BarrageView 组件，不读取正式存档或词库。
func _make_speech(sentence_id: String, sentence_text: String) -> LevelSpeech:
	var speech := LevelSpeech.new()
	speech.original_sentence_id = sentence_id
	speech.text = sentence_text
	speech.tendency_id = "orthodox"
	return speech


## 为 Paradox 隔离验证构造单个候选定义。
func _make_contradiction(sentence_id: String, sentence_text: String) -> LevelContradiction:
	var contradiction := LevelContradiction.new()
	contradiction.original_sentence_id = sentence_id
	contradiction.text = sentence_text
	return contradiction


## 从真实 BarrageArea 子节点读取当前 Paradox 候选视图。
func _get_contradiction_views(area: BarrageArea) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child in area.get_children():
		if child is BarrageView and child.runtime_record != null and child.runtime_record.is_contradiction:
			views.append(child as BarrageView)
	return views


## 与 Sandbox 当前中央战斗区域保持相同逻辑尺寸。
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


## 图形证据使用当前系统的深色战斗区样式，清楚显示本次运动验证范围。
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
	title.text = "BG-22 加减速组件实测 · TEST_ONLY · BG-40 上限 %.0f px/s" % SPEED_CEILING
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f4f6fa"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(472.0, 42.0)
	subtitle.size = Vector2(920.0, 24.0)
	subtitle.text = "青色尾迹跟随实际 BarrageView；仅验证组件运动，不代表正式局内体验。"
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", Color("#c4cbd5"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle)
	_evidence_subtitle = subtitle


## GUI 运行时跟踪真实视图坐标，尾迹只显示该实例已走过的路径。
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


## 保存当前真实组件运行画面；截图明确标注 TEST_ONLY 及验收范围。
func _save_gui_evidence(
	gui_trail: Dictionary,
	failures: Array[String],
	early_speed: float,
	accelerating_speed: float,
	peak_speed: float,
	decelerating_speed: float
) -> void:
	if is_instance_valid(_evidence_subtitle):
		_evidence_subtitle.text = "4.0s 周期 | 实测 %.1f → %.1f → %.1f → %.1f px/s | 仅组件验收" % [
			early_speed, accelerating_speed, peak_speed, decelerating_speed
		]
	for _frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var evidence_path: String = ProjectSettings.globalize_path(EVIDENCE_PATH)
	var evidence_directory: String = evidence_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var save_error: Error = root.get_texture().get_image().save_png(evidence_path)
	if save_error != OK:
		failures.append("GUI movement evidence saves (%s)" % error_string(save_error))
	else:
		print("BG-22 GUI movement evidence: %s" % evidence_path)
	var trail_recorder: MotionTrailRecorder = gui_trail.get("recorder") as MotionTrailRecorder
	if trail_recorder != null:
		trail_recorder.queue_free()
