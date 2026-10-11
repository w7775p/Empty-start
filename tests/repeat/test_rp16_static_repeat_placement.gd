extends SceneTree

const AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const AIM_RETICLE_SCENE: PackedScene = preload("res://systems/combat_attack/aim_reticle.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")
const BATTLE_AREA_SIZE := Vector2(1024.0, 760.0)
const EVIDENCE_DIR := "res://docs/10. Repeat/evidence"
const SPAWN_SCREENSHOT := EVIDENCE_DIR + "/RP16_static_repeat_spawn.png"
const SETTLED_SCREENSHOT := EVIDENCE_DIR + "/RP16_static_repeat_after_0.75s.png"

var _failures: Array[String] = []
var _shot_submissions: Array[Dictionary] = []
var _sampled_positions: Array[Vector2] = []
var _evidence_header: Label


func _initialize() -> void:
	call_deferred("_run")


# 通过两条正式生成调用链验证随机静止、复读身份、攻击目标与容量行为。
func _run() -> void:
	seed(161611)
	var area: BarrageArea = AREA_SCENE.instantiate() as BarrageArea
	if area == null:
		push_error("RP-16: BarrageArea 加载失败")
		quit(1)
		return
	if DisplayServer.get_name() != "headless":
		_prepare_visual_canvas()
	root.add_child(area)
	_set_area_rect(area)
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.repeat_barrage_screen_cap = 24

	var profile := LevelProfile.new()
	profile.streamer_id = "rp16_test_streamer"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 360.0
	profile.normal_barrage_screen_cap = 200
	_check(area.start_normal_generation(profile), "测试关卡启动并为复读提供当前关卡")
	await process_frame

	var queue := RepeatDelayQueue.new(64)
	var t0_views: Array[BarrageView] = await _verify_normal_tier(area, queue, 0, 3)
	if not t0_views.is_empty():
		await _verify_repeat_is_shootable(area, t0_views[0])
	area.clear_current_barrages()
	await process_frame

	await _verify_normal_tier(area, queue, 3, 12)
	area.clear_current_barrages()
	await process_frame

	await _verify_normal_tier(area, queue, 5, 20)
	area.clear_current_barrages()
	await process_frame

	# T6 矛盾计划仍经过 RepeatDelayQueue；24 条满屏后续请求继续等待容量释放。
	var t6_plan := RepeatPlan.create_contradiction_hit_plan(
		&"rp16_t6_contradiction", "T6 矛盾原句", 6, 120, 8.0
	)
	_check(queue.enqueue_plan(t6_plan) == 120, "T6 矛盾计划保留其 120 条配置数量")
	var t6_generated: int = queue.advance_and_dispatch(5.0, area)
	var t6_views: Array[BarrageView] = _views_for_sentence(area, t6_plan.original_line_id)
	_check(t6_generated == 24 and t6_views.size() == 24, "T6 按复读同屏上限生成 24 条并等待其余请求")
	_check(queue.get_pending_contradiction_count() == 96, "T6 超出在场容量的矛盾复读仍留在队列")
	_check(queue.get_generation_stats().get_contradiction_count(t6_plan.original_line_id) == 24,
		"T6 统计只记录实际进入战斗区的矛盾复读")
	_check(queue.get_generation_stats().get_normal_count(t6_plan.original_line_id) == 0,
		"T6 矛盾复读不进入普通统计")
	await _verify_visible_static_views(area, t6_views, t6_plan.original_line_id)
	if not t6_views.is_empty():
		await _verify_repeat_is_shootable(area, t6_views[0])
		_check(area.end_barrage(t6_views[0].get_instance_id()), "命中后可通过区域公开入口移除 T6 复读")
		await process_frame
		_check(queue.advance_and_dispatch(0.0, area) == 1,
			"T6 移除一条复读后只补入一个等待请求")
	_check(queue.get_generation_stats().get_contradiction_count(t6_plan.original_line_id) == 25,
		"补位成功后矛盾统计按真实生成增至 25")
	queue.clear_contradiction_queue()
	area.clear_current_barrages()
	await process_frame

	# 神降临读取进入时冻结的普通历史，直接调用独立扩散组件的真实生成入口。
	var run_data := SaveData.new()
	run_data.committed_normal_hit_history.append({
		"original_sentence_id": "rp16_divine_history",
		"original_sentence_text": "神降临历史复读",
		"tendency": "orthodox",
		"hit_count": 1,
		"first_committed_hit_order": 1,
	})
	var session := DivineDescentSession.new()
	_check(session.enter(run_data), "神降临会话冻结历史候选")
	var spread := DivineDescentSpread.new()
	root.add_child(spread)
	var spread_rng := RandomNumberGenerator.new()
	spread_rng.seed = 161612
	_check(spread.start(session, area, null, 60.0, 8.0, "{原句}", spread_rng),
		"神降临扩散读取冻结候选并启动")
	var history_view: BarrageView = spread.generate_next_repeat()
	_check(history_view != null, "神降临真实生成一条历史复读")
	if history_view != null:
		_check(history_view.runtime_record.is_repeat and not history_view.runtime_record.is_contradiction_repeat,
			"神降临历史句仍沿用普通复读类型和原句身份")
		_check(history_view.runtime_record.original_sentence_id == &"rp16_divine_history",
			"神降临复读保留冻结历史原句 ID")
		var history_views: Array[BarrageView] = [history_view]
		await _verify_visible_static_views(area, history_views, &"rp16_divine_history")

	# 同屏展示四个 Tier 样本和神降临历史句，分别保留两张运行时画面证据。
	await _spawn_visual_sample(area, queue, &"rp16_visual_t0", "T0 普通复读", 0, false)
	await _spawn_visual_sample(area, queue, &"rp16_visual_t3", "T3 普通复读", 3, false)
	await _spawn_visual_sample(area, queue, &"rp16_visual_t5", "T5 普通复读", 5, false)
	await _spawn_visual_sample(area, queue, &"rp16_visual_t6", "T6 矛盾复读", 6, true)

	var visual_views: Array[BarrageView] = _all_repeat_views(area)
	_check(visual_views.size() == 5, "运行时画面同时显示五条不同来源的复读")
	var visual_positions: Array[Vector2] = []
	for view: BarrageView in visual_views:
		_check(_is_fully_inside(area, view), "GUI 样本完整位于中央战斗区")
		_check(not visual_positions.has(view.position), "GUI 样本的随机落点彼此不同")
		visual_positions.append(view.position)
	if _evidence_header != null:
		_evidence_header.text = "RP-16 · 复读随机静止落点 · 生成帧"
	await _save_evidence(SPAWN_SCREENSHOT)
	await create_timer(0.75, true).timeout
	await process_frame
	for index in range(visual_views.size()):
		_check(is_instance_valid(visual_views[index]) and visual_views[index].position == visual_positions[index],
			"GUI 样本在 0.75 秒后位置保持不变")
	if _evidence_header != null:
		_evidence_header.text = "RP-16 · 复读随机静止落点 · 0.75 秒后"
		await process_frame
	await _save_evidence(SETTLED_SCREENSHOT)

	spread.stop()
	spread.queue_free()
	area.clear_barrages()
	area.queue_free()
	await process_frame
	if _failures.is_empty():
		print("RP16_STATIC_REPEAT_PASS normal=T0:3,T3:12,T5:20 contradiction=T6:24/120 pending=96")
		if DisplayServer.get_name() != "headless":
			print("RP16_GUI_EVIDENCE: %s | %s" % [
				ProjectSettings.globalize_path(SPAWN_SCREENSHOT),
				ProjectSettings.globalize_path(SETTLED_SCREENSHOT),
			])
		quit(0)
	else:
		for failure: String in _failures:
			push_error("FAIL RP-16: " + failure)
		quit(1)


# 按真实 T0 / T3 / T5 数量从普通延迟队列派发并检查随机位置、寿命和原句。
func _verify_normal_tier(
		area: BarrageArea, queue: RepeatDelayQueue, tier: int, repeat_count: int
	) -> Array[BarrageView]:
	var sentence_id := StringName("rp16_t%d" % tier)
	var plan := RepeatPlan.create_normal_hit_plan(
		sentence_id, "T%d 普通复读原句" % tier, tier, repeat_count, 8.0, "orthodox"
	)
	plan.apply_display_template("{原句}")
	_check(queue.enqueue_plan(plan) == repeat_count, "T%d 普通复读计划完整入队" % tier)
	var generated: int = queue.advance_and_dispatch(5.0, area)
	var views: Array[BarrageView] = _views_for_sentence(area, sentence_id)
	_check(generated == repeat_count and views.size() == repeat_count,
		"T%d 普通复读按既有数量实际生成" % tier)
	_check(queue.get_generation_stats().get_normal_count(sentence_id) == repeat_count,
		"T%d 统计记录实际普通生成数量" % tier)
	_check(queue.get_generation_stats().get_contradiction_count(sentence_id) == 0,
		"T%d 普通复读不写入矛盾统计" % tier)
	await _verify_visible_static_views(area, views, sentence_id)
	return views


# 验证生成目标会进入真实攻击快照并按现有 HitResolution 作为有效复读命中。
func _verify_repeat_is_shootable(area: BarrageArea, view: BarrageView) -> void:
	var before_submission_count: int = _shot_submissions.size()
	var aim: AimReticle = AIM_RETICLE_SCENE.instantiate() as AimReticle
	var attack := AttackChargeInput.new()
	root.add_child(aim)
	root.add_child(attack)
	await process_frame
	_check(attack.configure_attack_timing(SHORT_ATTACK_TIMING), "攻击组件接受已有短计时配置")
	_check(attack.configure_hit_resolution(HitResolution.new(0.5, 0.0, 1.0)),
		"攻击组件接收独立本场 HitResolution")
	attack.configure_target_query(aim, area)
	attack.shot_hit_resolution_submitted.connect(_on_shot_submitted)
	var window_point: Vector2 = root.get_final_transform() * (
		aim.get_canvas_transform() * view.get_global_rect().get_center()
	)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = window_point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed:
			await create_timer(SHORT_ATTACK_TIMING.charge_time_s + 0.05).timeout
	await create_timer(SHORT_ATTACK_TIMING.projectile_flight_s + 0.05).timeout
	_check(_shot_submissions.size() == before_submission_count + 1, "真实攻击输入提交命中结算")
	if _shot_submissions.size() > before_submission_count:
		var submitted: Dictionary = _shot_submissions.back()
		var snapshot: AttackTargetSnapshot = submitted.get("snapshot") as AttackTargetSnapshot
		var hit_result: Dictionary = submitted.get("submission", {}).get("hit_resolution_result", {})
		var target_results: Array = hit_result.get("target_results", [])
		var found_valid_repeat := false
		for target_result: Dictionary in target_results:
			if bool(target_result.get("is_repeat", false)) and bool(target_result.get("is_valid_hit", false)):
				found_valid_repeat = true
		_check(snapshot != null and snapshot.get_target_instance_ids().has(view.get_instance_id()),
			"静止复读进入准心释放快照")
		_check(found_valid_repeat, "静止复读结算为有效、可命中的复读目标")
	attack.set_combat_active(false)
	attack.queue_free()
	aim.queue_free()
	await process_frame


# 神降临与普通队列共享实际区域约束，位置样本必须完整可见且经过帧推进后不移动。
func _verify_visible_static_views(
		area: BarrageArea, views: Array[BarrageView], sentence_id: StringName
	) -> void:
	var initial_positions: Array[Vector2] = []
	var has_valid_position: Array[bool] = []
	for view: BarrageView in views:
		_check(is_instance_valid(view) and view.is_inside_tree(), "%s 的视图真实在场" % sentence_id)
		if not is_instance_valid(view) or view.runtime_record == null:
			initial_positions.append(Vector2.ZERO)
			has_valid_position.append(false)
			continue
		_check(view.runtime_record.is_repeat, "%s 保持复读身份" % sentence_id)
		_check(view.runtime_record.original_sentence_id == sentence_id, "%s 保留来源原句 ID" % sentence_id)
		_check(view.runtime_record.expires_at_msec > Time.get_ticks_msec(), "%s 沿用正寿命" % sentence_id)
		_check(_is_fully_inside(area, view), "%s 生成在当前中央战斗区域内" % sentence_id)
		_check(area.get_visible_barrage_records().has(view.runtime_record), "%s 进入可见弹幕记录" % sentence_id)
		_check(not _sampled_positions.has(view.position), "%s 与先前实例落在不同随机位置" % sentence_id)
		initial_positions.append(view.position)
		has_valid_position.append(true)
		_sampled_positions.append(view.position)
	for _frame in range(8):
		await process_frame
	for index in range(views.size()):
		var view: BarrageView = views[index]
		if not is_instance_valid(view) or index >= initial_positions.size() or not has_valid_position[index]:
			continue
		_check(view.position == initial_positions[index], "%s 经过八帧后仍静止" % sentence_id)
	_check(views.size() <= 1 or initial_positions.size() == views.size(),
		"%s 每条复读均获得独立位置样本" % sentence_id)


# 单条 T0/T3/T5/T6 截图样本复用正常 / 矛盾计划与真实队列派发。
func _spawn_visual_sample(
		area: BarrageArea, queue: RepeatDelayQueue, sentence_id: StringName,
		label_text: String, tier: int, is_contradiction: bool
	) -> void:
	var plan: RepeatPlan
	if is_contradiction:
		plan = RepeatPlan.create_contradiction_hit_plan(sentence_id, label_text, tier, 1, 8.0)
	else:
		plan = RepeatPlan.create_normal_hit_plan(sentence_id, label_text, tier, 1, 8.0, "orthodox")
	plan.display_text = label_text
	_check(queue.enqueue_plan(plan) == 1, "%s 截图样本入队" % label_text)
	_check(queue.advance_and_dispatch(5.0, area) == 1, "%s 截图样本生成" % label_text)


func _views_for_sentence(area: BarrageArea, sentence_id: StringName) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child: Node in area.get_children():
		if child is BarrageView:
			var view := child as BarrageView
			if view.runtime_record != null and view.runtime_record.original_sentence_id == sentence_id:
				views.append(view)
	return views


func _all_repeat_views(area: BarrageArea) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child: Node in area.get_children():
		if child is BarrageView:
			var view := child as BarrageView
			if view.runtime_record != null and view.runtime_record.is_repeat and not view.is_queued_for_deletion():
				views.append(view)
	return views


func _is_fully_inside(area: BarrageArea, view: BarrageView) -> bool:
	return view.position.x >= 0.0 and view.position.y >= 0.0 \
		and view.position.x + view.size.x <= area.size.x \
		and view.position.y + view.size.y <= area.size.y


func _set_area_rect(area: BarrageArea) -> void:
	area.anchor_left = 0.0
	area.anchor_top = 0.0
	area.anchor_right = 0.0
	area.anchor_bottom = 0.0
	area.offset_left = 448.0
	area.offset_top = 72.0
	area.offset_right = 448.0 + BATTLE_AREA_SIZE.x
	area.offset_bottom = 72.0 + BATTLE_AREA_SIZE.y


func _prepare_visual_canvas() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#111720")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	root.move_child(background, 0)

	var stage := ColorRect.new()
	stage.position = Vector2(448.0, 72.0)
	stage.size = BATTLE_AREA_SIZE
	stage.color = Color("#202b37")
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)
	root.move_child(stage, 1)

	_evidence_header = Label.new()
	_evidence_header.position = Vector2(448.0, 10.0)
	_evidence_header.size = Vector2(BATTLE_AREA_SIZE.x, 48.0)
	_evidence_header.text = "RP-16 · 复读随机静止落点"
	_evidence_header.add_theme_color_override("font_color", Color("#f0f4fa"))
	_evidence_header.add_theme_font_size_override("font_size", 22)
	_evidence_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_evidence_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_evidence_header)


func _save_evidence(resource_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var evidence_directory: String = ProjectSettings.globalize_path(EVIDENCE_DIR)
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var screenshot_path: String = ProjectSettings.globalize_path(resource_path)
	var save_error: Error = root.get_texture().get_image().save_png(screenshot_path)
	_check(save_error == OK, "GUI 运行截图保存到 %s" % resource_path)


func _on_shot_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_shot_submissions.append({"snapshot": snapshot, "submission": submission.duplicate(true)})


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
