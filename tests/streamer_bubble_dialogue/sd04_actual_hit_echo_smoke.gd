extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")
const BUBBLE_DIALOGUE_CONFIG: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
const EVIDENCE_DIRECTORY: String = "res://docs/21. StreamerBubbleDialogue/evidence/SD-04_2026-10-11"

var _sandbox: Control
var _battle_flow: BattleAttemptFlow
var _barrage_area: BarrageArea
var _aim_reticle: AimReticle
var _attack_input: AttackChargeInput
var _battle_hud: Node
var _player_stack: StreamerBubbleStack
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _flow_resolutions: Array[Dictionary] = []
var _checks: int = 0
var _failures: Array[String] = []


# 在正式 Sandbox 中运行实际攻击链，验证复述、复读过滤与遮挡落空。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_acceptance")


# 通过真实发射、目标快照、HitResolution 与 BattleAttemptFlow 检查实际消费者。
func _run_acceptance() -> void:
	SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	add_child(_sandbox)
	await _wait_frames(2)
	_battle_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	if _battle_flow == null:
		_check(false, "Sandbox 公开接口提供 BattleAttemptFlow")
		await _finish()
		return
	_barrage_area = _battle_flow.get_barrage_area()
	_aim_reticle = _battle_flow.get_aim_reticle()
	_attack_input = _battle_flow.get_attack_input()
	_battle_hud = _sandbox.get_node_or_null("BattleHud")
	if _barrage_area == null or _aim_reticle == null or _attack_input == null or _battle_hud == null:
		_check(false, "正式 Sandbox 公开战斗与 HUD 接口可用")
		await _finish()
		return
	_player_stack = _battle_hud.get_node("%PlayerBubbleStack") as StreamerBubbleStack
	if _player_stack == null:
		_check(false, "正式 HUD 提供玩家侧 SD-03 气泡栈")
		await _finish()
		return
	_battle_flow.shot_resolved.connect(_on_flow_shot_resolved)
	_check(DisplayServer.get_name() != "headless", "运行于 Windows 可见 Godot 窗口")
	_check(_attack_input.configure_attack_timing(SHORT_ATTACK_TIMING), "正式攻击组件接受已有短计时测试配置")
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await _wait_frames(2)

	var level: LevelProfile = _battle_flow.get_current_level_profile()
	var speeches: Array[LevelSpeech] = level.get_normal_speech_pool() if level != null else []
	var positive_speech: LevelSpeech
	var negative_speech: LevelSpeech
	if not speeches.is_empty():
		positive_speech = speeches[0]
	for speech: LevelSpeech in speeches:
		if positive_speech != null and speech.original_sentence_id != positive_speech.original_sentence_id:
			negative_speech = speech
			break
	_check(positive_speech != null and negative_speech != null, "正式关卡含两个原句 ID 不同的话语")
	if positive_speech == null or negative_speech == null:
		await _finish()
		return

	await _run_group_hit_case(level, positive_speech, negative_speech)
	await _clear_attempt_targets()
	await _wait_for_attack_ready()
	await _run_negative_only_case(level, negative_speech)
	await _clear_attempt_targets()
	await _wait_for_attack_ready()
	await _run_occlusion_miss_case(level, positive_speech, negative_speech)
	print("SD-04 INPUT source=Input.parse_input_event synthetic mouse; physical mouse=NOT TESTED")
	await _finish()


# 同一发真实群体命中需按结算顺序复述正向与负向原句，并过滤复读。
func _run_group_hit_case(
	level: LevelProfile, positive_speech: LevelSpeech, negative_speech: LevelSpeech
) -> void:
	var positive: BarrageView = _spawn_normal_target(level, positive_speech)
	var negative: BarrageView = _spawn_normal_target(level, negative_speech)
	var repeat: BarrageView = _spawn_repeat_target(positive_speech)
	if not _check_targets([positive, negative, repeat], "群体命中用例"):
		return
	_check(negative.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "负向目标装配 fake_card 效果")
	await _place_overlapped_targets([positive, negative, repeat])
	var before_count: int = _flow_resolutions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_for_flow_count(before_count + 1)
	if _flow_resolutions.size() <= before_count:
		return
	var submission: Dictionary = _flow_resolutions.back()["submission"]
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var target_results: Array = hit_result.get("target_results", [])
	var expected_texts: Array[String] = []
	var expected_ids: Array[String] = []
	var negative_retained: bool = false
	for target_result: Dictionary in target_results:
		var sentence_id: String = str(target_result.get("original_sentence_id", ""))
		var sentence_text: String = str(target_result.get("original_sentence_text", ""))
		if bool(target_result.get("is_repeat", false)):
			continue
		expected_ids.append(sentence_id)
		expected_texts.append(sentence_text)
		var entry: BubbleDialogueEntry = BUBBLE_DIALOGUE_CONFIG.create_hit_echo(
			sentence_id, sentence_text, true, false
		)
		_check(
			entry != null and entry.original_sentence_id == sentence_id and entry.text == sentence_text,
			"玩家复述条目原样保留目标原句 ID 与文本"
		)
		if sentence_id == negative_speech.original_sentence_id:
			negative_retained = not bool(target_result.get("is_valid_hit", true))
	_check(target_results.size() == 3, "最终逐目标结果保留正向、负向与复读三条事实")
	_check(expected_ids.size() == 2, "每个实际非复读目标各生成一个复述请求")
	_check(negative_retained, "负向实际命中保留在逐目标结果且无常规收益")
	_check(expected_ids.has(positive_speech.original_sentence_id), "玩家复述保留正向目标原句 ID")
	_check(expected_ids.has(negative_speech.original_sentence_id), "玩家复述保留负向目标原句 ID")
	await get_tree().create_timer(0.35).timeout
	var visible_texts: Array[String] = _player_bubble_texts()
	_check(visible_texts == expected_texts, "SD-03 玩家队列按真实逐目标顺序显示原句")
	_check(visible_texts.size() == 2, "复读目标没有生成额外复述气泡")
	await _capture_evidence()


# 单独命中负向目标仍按真实碰撞复述，不受常规收益标志影响。
func _run_negative_only_case(level: LevelProfile, negative_speech: LevelSpeech) -> void:
	_battle_hud.call("clear_dialogue_bubbles")
	var negative: BarrageView = _spawn_normal_target(level, negative_speech)
	if not _check_targets([negative], "单独负向命中用例"):
		return
	_check(negative.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "单独负向目标装配 fake_card 效果")
	await _place_overlapped_targets([negative])
	var before_count: int = _flow_resolutions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_for_flow_count(before_count + 1)
	if _flow_resolutions.size() <= before_count:
		return
	var submission: Dictionary = _flow_resolutions.back()["submission"]
	var target_results: Array = submission.get("hit_resolution_result", {}).get("target_results", [])
	_check(target_results.size() == 1, "负向碰撞仍保留一条最终逐目标事实")
	if target_results.size() == 1:
		_check(not bool(target_results[0].get("is_valid_hit", true)), "负向碰撞的常规收益标志为 false")
	await get_tree().create_timer(0.35).timeout
	_check(_player_bubble_texts() == [negative_speech.text], "负向碰撞仍显示其原句复述")


# CA-15 遮挡整发清空逐目标结果，队列因此不产生任何命中复述。
func _run_occlusion_miss_case(
	level: LevelProfile, positive_speech: LevelSpeech, negative_speech: LevelSpeech
) -> void:
	_battle_hud.call("clear_dialogue_bubbles")
	var occlusion: BarrageView = _spawn_normal_target(level, positive_speech)
	var positive: BarrageView = _spawn_normal_target(level, positive_speech)
	var negative: BarrageView = _spawn_normal_target(level, negative_speech)
	if not _check_targets([occlusion, positive, negative], "遮挡整发用例"):
		return
	_check(occlusion.runtime_record.trait_set.add_trait(BarrageTraitSet.OCCLUSION), "遮挡目标装配 CA-15 特性")
	_check(negative.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "遮挡对照中的负向目标装配 fake_card")
	await _place_overlapped_targets([occlusion, positive, negative])
	var before_count: int = _flow_resolutions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_for_flow_count(before_count + 1)
	if _flow_resolutions.size() <= before_count:
		return
	var submission: Dictionary = _flow_resolutions.back()["submission"]
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.MISS, "遮挡整发采用最终 MISS 判定")
	_check((hit_result.get("target_results", []) as Array).is_empty(), "遮挡最终结果没有逐目标命中事实")
	await get_tree().process_frame
	_check(_player_bubble_texts().is_empty(), "遮挡整发没有新增玩家侧复述气泡")


# 使用正式弹幕入口生成测试目标，测试数据仅存在本进程内。
func _spawn_normal_target(level: LevelProfile, speech: LevelSpeech) -> BarrageView:
	var view: BarrageView = _barrage_area.spawn_normal_barrage(level, speech)
	if view != null and view.runtime_record != null:
		view.runtime_record.tendency_id = "orthodox"
		view.runtime_record.strength = 3.0
	return view


# 通过既有复读计划和弹幕入口创建测试复读目标。
func _spawn_repeat_target(speech: LevelSpeech) -> BarrageView:
	var plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		StringName(speech.original_sentence_id), speech.text,
		_battle_flow.get_current_tier(), 1, 30.0, "orthodox"
	)
	plan.apply_display_template("{原句}")
	return _barrage_area.spawn_repeat_barrage(plan)


# 等待正式场景布局稳定后，将目标放在同一准心位置。
func _place_overlapped_targets(targets: Array) -> void:
	var center_global: Vector2 = _barrage_area.get_global_rect().get_center()
	var area_to_global: Transform2D = _barrage_area.get_global_transform()
	var center_local: Vector2 = area_to_global.affine_inverse() * center_global
	await get_tree().process_frame
	for target: BarrageView in targets:
		target.position = center_local - target.size * 0.5
	_mouse_canvas_position = center_global
	_send_mouse_motion(_mouse_canvas_position)
	await get_tree().process_frame
	var all_intersect: bool = true
	for target: BarrageView in targets:
		if not _aim_reticle.intersects_target_area(target.get_global_rect()):
			all_intersect = false
	_check(all_intersect, "同一攻击准心覆盖本次全部真实目标")


# 真实攻击组件完成蓄力、释放和飞行后等待整发信号。
func _fire_at(canvas_position: Vector2) -> void:
	_mouse_canvas_position = canvas_position
	_send_mouse_motion(_mouse_canvas_position)
	_check(_aim_reticle.get_aim_center_global_position().distance_to(canvas_position) < 1.0, "准心到达测试目标中心")
	_send_mouse_button(true)
	await _wait(0.24)
	_check(_attack_input.is_fully_charged(), "正式攻击组件完成测试蓄力")
	_send_mouse_button(false)


# 等待 BattleAttemptFlow 收到完整逐目标结算事件。
func _wait_for_flow_count(required_count: int) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while _flow_resolutions.size() < required_count and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	_check(_flow_resolutions.size() >= required_count, "BattleAttemptFlow 发出最终 shot_resolved")


# 攻击硬直结束后再建立下一发目标。
func _wait_for_attack_ready() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while not _attack_input.can_start_charging() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	_check(_attack_input.can_start_charging(), "攻击硬直结束并恢复 READY")


# 清理本用例的目标与气泡，避免相邻检查互相影响。
func _clear_attempt_targets() -> void:
	_battle_hud.call("clear_dialogue_bubbles")
	_barrage_area.clear_barrages()
	await _wait_frames(2)


# 将画布位置映射到真实窗口输入坐标，沿用正式攻击输入分发路径。
func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * canvas_position)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 将合成按下和释放事件交给 Godot 正式输入分发。
func _send_mouse_button(pressed: bool) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * _mouse_canvas_position)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 检查目标均为真实创建且仍在树中的实例。
func _check_targets(targets: Array, label: String) -> bool:
	var valid: bool = true
	for target: BarrageView in targets:
		if target == null or not is_instance_valid(target) or not target.is_inside_tree():
			valid = false
	_check(valid, label + " 创建正式 BarrageView")
	return valid


# 从玩家侧真实气泡控件读取展示顺序。
func _player_bubble_texts() -> Array[String]:
	var result: Array[String] = []
	for child: Node in _player_stack.get_children():
		if child is StreamerBubbleView:
			var text_label: RichTextLabel = child.get_node("Text") as RichTextLabel
			result.append(text_label.text)
	return result


# 保存实际 Godot GUI Viewport 渲染，作为本卡视觉证据。
func _capture_evidence() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var directory: String = ProjectSettings.globalize_path(EVIDENCE_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var filename: String = "sd04_actual_hit_echo_%dx%d.png" % [image.get_width(), image.get_height()]
	var save_result: Error = image.save_png(directory.path_join(filename))
	_check(save_result == OK, "保存真实 Sandbox 命中气泡截图 %s" % filename)


# 逐条保存最终整发提交，测试不合成或改写业务结果。
func _on_flow_shot_resolved(
	snapshot: AttackTargetSnapshot,
	submission: Dictionary,
	_current_tier: int,
	_repeat_stats: RepeatGenerationStats
) -> void:
	_flow_resolutions.append({"snapshot": snapshot, "submission": submission.duplicate(true)})


# 推进场景帧，等待尺寸和队列更新。
func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame


# 使用引擎计时器等待输入与气泡动画。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# 统一记录断言，失败会让 Godot 子进程返回非零码。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
		push_error("FAIL: " + message)


# 释放测试创建的 Sandbox 并输出明确结果码。
func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("SD-04 GUI RESULT checks=%d failures=0 display=%s window=%s" % [_checks, DisplayServer.get_name(), DisplayServer.window_get_size()])
		get_tree().quit(0)
	else:
		print("SD-04 GUI RESULT checks=%d failures=%d display=%s window=%s" % [_checks, _failures.size(), DisplayServer.get_name(), DisplayServer.window_get_size()])
		get_tree().quit(1)
