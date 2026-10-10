extends SceneTree

const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")
const CURRENT_BATTLE_AREA_SIZE := Vector2(1024.0, 760.0)
const EXPANDED_BATTLE_AREA_HEIGHT := 1008.0
const LONG_TEXT := "这是一段较长的弹幕文字，用来确认定位会依据完整视图尺寸计算边界。长文本在战斗区内需要自动折行，并继续保持原有的暂停、寿命和容量管理。"
const SCREENSHOT_PATH := "res://docs/3. BarrageGeneration/evidence/BG42_static_random_placement.png"


func _initialize() -> void:
	call_deferred("_run_test")


## 覆盖显式静止请求、完整边界、随机分布、暂停寿命和容量释放。
func _run_test() -> void:
	seed(42042)
	var failures: Array[String] = []
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if area == null:
		push_error("FAIL BG-42: BarrageArea Scene failed to load")
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		_prepare_visual_canvas()
	root.add_child(area)
	_set_area_rect(area, CURRENT_BATTLE_AREA_SIZE.y)

	var profile := LevelProfile.new()
	profile.streamer_id = "bg42_test_streamer"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 360.0
	profile.normal_barrage_screen_cap = 200
	profile.special_trait_ids.append("occlusion")
	if not area.start_normal_generation(profile):
		failures.append("test profile starts normal generation")

	# 未请求随机静止定位时仍走原有移动与定位。
	var moving_speech: LevelSpeech = _make_speech("bg42_default_motion", "普通弹幕仍沿原有路径移动。")
	var moving_view: BarrageView = area.spawn_normal_barrage(profile, moving_speech)
	if moving_view == null:
		failures.append("default moving barrage spawns")
	else:
		var moving_start_x: float = moving_view.position.x
		for _frame in range(8):
			await process_frame
		if moving_view.position.x >= moving_start_x:
			failures.append("default spawn remains on the existing movement path")
		area.end_barrage(moving_view.get_instance_id())
		await process_frame

	# 长句与遮挡特性保留原身份，在实际 1024×760 战斗区内稳定停留。
	var occlusion_ids: Array[StringName] = [BarrageTraitSet.OCCLUSION]
	var long_speech: LevelSpeech = _make_speech("bg42_long_text", LONG_TEXT)
	var static_view: BarrageView = area.spawn_normal_barrage(profile, long_speech, occlusion_ids, true)
	if static_view == null:
		failures.append("long static text spawns inside the current BattleArea")
	else:
		var fixed_position: Vector2 = static_view.position
		for _frame in range(8):
			await process_frame
		if not _is_fully_inside(area, static_view):
			failures.append("long static text stays completely inside 1024×760")
		if static_view.position != fixed_position:
			failures.append("explicit static placement remains stationary")
		if static_view.runtime_record == null or not static_view.runtime_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION):
			failures.append("static placement preserves the selected occlusion identity")

	var small_area_spread: Vector4 = await _sample_position_spread(area, profile, 64)
	if small_area_spread.x > 0.1 or small_area_spread.y < 0.9 or small_area_spread.z > 0.1 or small_area_spread.w < 0.9:
		failures.append("1024×760 static positions sample the available width and height")

	# 同一实例处理 BattleArea 扩高后的真实尺寸，不依赖固定布局常量。
	_set_area_rect(area, EXPANDED_BATTLE_AREA_HEIGHT)
	await process_frame
	var expanded_area_spread: Vector4 = await _sample_position_spread(area, profile, 64)
	if expanded_area_spread.x > 0.1 or expanded_area_spread.y < 0.9 or expanded_area_spread.z > 0.1 or expanded_area_spread.w < 0.9:
		failures.append("1024×1008 static positions sample the resized area")
	var long_in_expanded_area: BarrageView = area.spawn_normal_barrage(profile, long_speech, [], true)
	if long_in_expanded_area == null or not _is_fully_inside(area, long_in_expanded_area):
		failures.append("new requests use the current expanded BattleArea size")
	if long_in_expanded_area != null:
		area.end_barrage(long_in_expanded_area.get_instance_id())
		await process_frame

	# 区域缩小后夹回仍可容纳的视图；缩到无法容纳时由离树信号释放容量。
	area.clear_barrages()
	profile.normal_barrage_screen_cap = 1
	var resize_view: BarrageView = area.spawn_normal_barrage(profile, long_speech, [], true)
	if resize_view == null:
		failures.append("static view for resize checks spawns")
	else:
		resize_view.position = Vector2(1000.0, 900.0)
		_set_area_rect(area, 300.0, 640.0)
		for _frame in range(3):
			await process_frame
		var resized_view_inside: bool = resize_view != null and _is_fully_inside(area, resize_view)
		var capacity_retained_while_visible: bool = area.spawn_normal_barrage(profile, moving_speech, [], true) == null
		if not resized_view_inside or not capacity_retained_while_visible:
			failures.append("resizing a visible static view clamps it and retains its capacity")
		_set_area_rect(area, 40.0, 640.0)
		for _frame in range(3):
			await process_frame
		var removed_after_shrink: bool = not is_instance_valid(resize_view)
		_set_area_rect(area, CURRENT_BATTLE_AREA_SIZE.y)
		var capacity_reopened_after_shrink: BarrageView = area.spawn_normal_barrage(profile, moving_speech, [], true)
		if not removed_after_shrink or capacity_reopened_after_shrink == null:
			failures.append("an undersized resize removes the static view and releases its capacity")
		if capacity_reopened_after_shrink != null:
			area.end_barrage(capacity_reopened_after_shrink.get_instance_id())
			await process_frame

	# 区域小于视图时拒绝新生成，并让失败视图归还刚登记的容量。
	area.clear_barrages()
	_set_area_rect(area, 40.0)
	var too_tall_view: BarrageView = area.spawn_normal_barrage(profile, moving_speech, [], true)
	if too_tall_view != null:
		failures.append("placement rejects a view taller than the available area")
		area.end_barrage(too_tall_view.get_instance_id())
	_set_area_rect(area, CURRENT_BATTLE_AREA_SIZE.y)
	var after_rejected_view: BarrageView = area.spawn_normal_barrage(profile, moving_speech, [], true)
	if after_rejected_view == null or not _is_fully_inside(area, after_rejected_view):
		failures.append("failed oversized placement returns the normal capacity slot")
	if after_rejected_view != null:
		area.end_barrage(after_rejected_view.get_instance_id())
		await process_frame

	# 普通与复读各占自己的原容量账本；暂停期间保留位置和剩余寿命，到期后自动释放。
	area.base_lifetime_seconds = 0.2
	area.repeat_barrage_screen_cap = 1
	var lifetime_view: BarrageView = area.spawn_normal_barrage(profile, moving_speech, [], true)
	var blocked_normal: BarrageView = area.spawn_normal_barrage(profile, moving_speech, [], true)
	var repeat_plan := RepeatPlan.new()
	repeat_plan.original_line_id = &"bg42_repeat_lifetime"
	repeat_plan.original_line_text = LONG_TEXT
	repeat_plan.display_text = LONG_TEXT
	repeat_plan.lifetime_seconds = 0.2
	var repeat_view: BarrageView = area.spawn_repeat_barrage(repeat_plan, true)
	if lifetime_view == null or blocked_normal != null or repeat_view == null:
		failures.append("static normal and repeat requests use their existing independent capacity ledgers")
	if repeat_view != null and (repeat_view.runtime_record == null or not repeat_view.runtime_record.is_repeat or not _is_fully_inside(area, repeat_view)):
		failures.append("static repeat keeps its repeat identity and full-area bounds")

	var normal_deadline_before: int = lifetime_view.runtime_record.expires_at_msec if lifetime_view != null else 0
	var repeat_deadline_before: int = repeat_view.runtime_record.expires_at_msec if repeat_view != null else 0
	var pause_positions: Array[Vector2] = []
	if lifetime_view != null:
		pause_positions.append(lifetime_view.position)
	if repeat_view != null:
		pause_positions.append(repeat_view.position)
	paused = true
	for _frame in range(3):
		await process_frame
	await create_timer(0.35, true).timeout
	var survived_pause: bool = is_instance_valid(lifetime_view) and is_instance_valid(repeat_view)
	var normal_position_during_pause: bool = lifetime_view != null and lifetime_view.position == pause_positions[0]
	var repeat_position_during_pause: bool = repeat_view != null and repeat_view.position == pause_positions[1]
	paused = false
	for _frame in range(3):
		await process_frame
	var paused_lifetime_restored: bool = lifetime_view != null and repeat_view != null \
		and lifetime_view.runtime_record.expires_at_msec >= normal_deadline_before + 250 \
		and repeat_view.runtime_record.expires_at_msec >= repeat_deadline_before + 250
	if not survived_pause or not normal_position_during_pause or not repeat_position_during_pause or not paused_lifetime_restored:
		failures.append("pause preserves static positions and extends both existing lifetimes")

	var disappearance_deadline: int = Time.get_ticks_msec() + 1200
	while (is_instance_valid(lifetime_view) or is_instance_valid(repeat_view)) and Time.get_ticks_msec() < disappearance_deadline:
		await process_frame
	var lifetimes_disappeared: bool = not is_instance_valid(lifetime_view) and not is_instance_valid(repeat_view)
	var normal_capacity_released: BarrageView = area.spawn_normal_barrage(profile, moving_speech, [], true)
	var repeat_capacity_released: BarrageView = area.spawn_repeat_barrage(repeat_plan, true)
	if not lifetimes_disappeared or normal_capacity_released == null or repeat_capacity_released == null:
		failures.append("natural expiry removes static views and releases both existing capacity ledgers")

	if DisplayServer.get_name() != "headless":
		await _show_visual_examples(area, profile, failures)

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS BG-42: opt-in static placement, area bounds and resize, text lengths, pause, lifetime, and capacity")
	else:
		push_error("FAIL BG-42: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)


func _make_speech(sentence_id: String, sentence_text: String) -> LevelSpeech:
	var speech := LevelSpeech.new()
	speech.original_sentence_id = sentence_id
	speech.text = sentence_text
	speech.tendency_id = "orthodox"
	return speech


## 测试场景直接使用 Sandbox 当前中央区坐标，并允许验证后续全高尺寸。
func _set_area_rect(area: BarrageArea, height: float, width: float = 1024.0) -> void:
	area.anchor_left = 0.0
	area.anchor_top = 0.0
	area.anchor_right = 0.0
	area.anchor_bottom = 0.0
	area.offset_left = 448.0
	area.offset_top = 72.0
	area.offset_right = 448.0 + width
	area.offset_bottom = 72.0 + height


func _is_fully_inside(area: BarrageArea, view: BarrageView) -> bool:
	if not is_instance_valid(view):
		return false
	return view.position.x >= 0.0 and view.position.y >= 0.0 \
		and view.position.x + view.size.x <= area.size.x \
		and view.position.y + view.size.y <= area.size.y


## 返回样本在可用宽、高中的最小和最大归一化位置。
func _sample_position_spread(area: BarrageArea, profile: LevelProfile, sample_count: int) -> Vector4:
	var min_x: float = 1.0
	var max_x: float = 0.0
	var min_y: float = 1.0
	var max_y: float = 0.0
	for index in range(sample_count):
		var sentence: String = "短句" if index % 2 == 0 else LONG_TEXT
		var sample: BarrageView = area.spawn_normal_barrage(
			profile, _make_speech("bg42_distribution_%d" % index, sentence), [], true
		)
		if sample == null or not _is_fully_inside(area, sample):
			push_error("FAIL BG-42: random sample %d failed full-area bounds" % index)
			return Vector4(1.0, 0.0, 1.0, 0.0)
		var range_x: float = area.size.x - sample.size.x
		var range_y: float = area.size.y - sample.size.y
		var normalized_x: float = sample.position.x / range_x if range_x > 0.0 else 0.0
		var normalized_y: float = sample.position.y / range_y if range_y > 0.0 else 0.0
		min_x = minf(min_x, normalized_x)
		max_x = maxf(max_x, normalized_x)
		min_y = minf(min_y, normalized_y)
		max_y = maxf(max_y, normalized_y)
		area.end_barrage(sample.get_instance_id())
		await process_frame
	return Vector4(min_x, max_x, min_y, max_y)


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
	title.size = Vector2(800.0, 48.0)
	title.text = "BG-42 静止随机落点验收 · BattleArea 1024 × 760"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f4f6fa"))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)


## GUI 运行时展示短句、长句和遮挡实例，并保存真实渲染截图。
func _show_visual_examples(area: BarrageArea, profile: LevelProfile, failures: Array[String]) -> void:
	area.clear_barrages()
	profile.normal_barrage_screen_cap = 16
	area.base_lifetime_seconds = 10.0
	area.repeat_barrage_screen_cap = 16
	_set_area_rect(area, CURRENT_BATTLE_AREA_SIZE.y)
	seed(4242)
	var visual_texts: Array[String] = [
		"短句随机静止，原有寿命继续生效。",
		LONG_TEXT,
		"暂停时位置保持，恢复后剩余寿命继续计时。",
		"复读与遮挡特性共用同一套随机落点能力。",
	]
	for index in range(visual_texts.size()):
		var traits: Array[StringName] = []
		if index == 4:
			traits.append(BarrageTraitSet.OCCLUSION)
		var sample := area.spawn_normal_barrage(
			profile,
			_make_speech("bg42_visual_%d" % index, visual_texts[index]),
			traits,
			true
		)
		if sample == null:
			failures.append("visual sample %d renders" % index)
	await process_frame
	await RenderingServer.frame_post_draw
	var evidence_directory: String = ProjectSettings.globalize_path("res://docs/3. BarrageGeneration/evidence")
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var screenshot_error: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(SCREENSHOT_PATH))
	if screenshot_error != OK:
		failures.append("GUI evidence screenshot saves (%s)" % error_string(screenshot_error))
	else:
		print("BG-42 visual evidence: %s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))
	# 让图形验收窗口保持可见，便于人工检查并截图。
	await create_timer(8.0, true).timeout
