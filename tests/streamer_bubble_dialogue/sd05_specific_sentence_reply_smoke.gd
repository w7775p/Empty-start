extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")
const BUBBLE_DIALOGUE_CONFIG: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
const EVIDENCE_DIRECTORY: String = "res://docs/21. StreamerBubbleDialogue/evidence/SD-05_2026-10-11"

var _sandbox: Control
var _battle_flow: BattleAttemptFlow
var _barrage_area: BarrageArea
var _aim_reticle: AimReticle
var _attack_input: AttackChargeInput
var _battle_hud: Node
var _player_stack: StreamerBubbleStack
var _opponent_stack: StreamerBubbleStack
var _mapped_speech: LevelSpeech
var _other_speech: LevelSpeech
var _test_reply: BubbleDialogueEntry
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _flow_resolutions: Array[Dictionary] = []
var _checks: int = 0
var _failures: Array[String] = []


# 使用正式 Sandbox、攻击链与结算事实验证命中回复和遮挡整发落空。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_acceptance")


# 将 TEST_ONLY 配置在内存中注入正式 Sandbox，不修改空的正式对白资源。
func _run_acceptance() -> void:
	SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	var level_catalog: LevelCatalog = _sandbox.get("level_catalog") as LevelCatalog
	var current_level: LevelProfile = LevelRunState.new(level_catalog).get_current_level_profile()
	var speeches: Array[LevelSpeech] = current_level.get_normal_speech_pool() if current_level != null else []
	if speeches.size() < 2:
		_check(false, "当前正式关卡提供至少两条可用于映射和对照的原句")
		await _finish()
		return
	_mapped_speech = speeches[1]
	_other_speech = speeches[0]
	var test_config: BubbleDialogueConfig = BUBBLE_DIALOGUE_CONFIG.duplicate(true) as BubbleDialogueConfig
	test_config.entries.clear()
	_test_reply = BubbleDialogueEntry.new()
	_test_reply.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	_test_reply.text = "TEST_ONLY 对手回应：这句我记住了。"
	_test_reply.original_sentence_id = _mapped_speech.original_sentence_id
	_test_reply.display_duration_seconds = 5.0
	# 用低优先级来源验证消费者会以剧情优先级请求，而不改写配置条目。
	_test_reply.priority = BubbleDialogueEntry.Priority.TIMED_IDLE
	test_config.entries.append(_test_reply)
	var player_only_entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	player_only_entry.side = BubbleDialogueEntry.SpeakerSide.PLAYER
	player_only_entry.text = "TEST_ONLY 玩家侧同 ID 配置"
	player_only_entry.original_sentence_id = _mapped_speech.original_sentence_id
	test_config.entries.append(player_only_entry)
	_sandbox.set("bubble_dialogue_config", test_config)
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
		_check(false, "正式 Sandbox 提供攻击组件和 HUD")
		await _finish()
		return
	_player_stack = _battle_hud.get_node_or_null("%PlayerBubbleStack") as StreamerBubbleStack
	_opponent_stack = _battle_hud.get_node_or_null("%OpponentBubbleStack") as StreamerBubbleStack
	if _player_stack == null or _opponent_stack == null:
		_check(false, "正式 HUD 提供双方 SD-03 气泡栈")
		await _finish()
		return
	_battle_flow.shot_resolved.connect(_on_flow_shot_resolved)
	_check(DisplayServer.get_name() != "headless", "运行于 Windows 可见 Godot 窗口")
	_check(_attack_input.configure_attack_timing(SHORT_ATTACK_TIMING), "正式攻击组件接受已有短计时测试配置")
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await _wait_frames(2)
	# Sandbox 从 T0 开始；通过 CombatStage 公开入口进入已连线的 T1 场次。
	var combat_stage: CombatStage = _battle_flow.get_combat_stage()
	_check(combat_stage.enter_terminal_tier(1), "CombatStage 公开接口进入 T1 对手连线场次")
	_check(_test_reply.original_sentence_id == _mapped_speech.original_sentence_id, "TEST_ONLY 对手答话绑定指定稳定原句 ID")
	await _run_mapped_reply_case(current_level)
	await _clear_attempt_targets()
	await _wait_for_attack_ready()
	await _run_occlusion_miss_case(current_level)
	print("SD-05 INPUT source=Input.parse_input_event synthetic mouse; physical mouse=NOT TESTED")
	await _finish()


# 真正命中被映射的负收益原句时，验证对手剧情回复和玩家原句复述共存。
func _run_mapped_reply_case(level: LevelProfile) -> void:
	var low_priority_entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	low_priority_entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	low_priority_entry.text = "TEST_ONLY 低优先级对白"
	low_priority_entry.display_duration_seconds = 5.0
	low_priority_entry.priority = BubbleDialogueEntry.Priority.HIT
	_check(bool(_battle_hud.call("enqueue_dialogue_bubble", low_priority_entry)), "SD-03 接受对手侧即时对白")
	var mapped_target: BarrageView = _spawn_normal_target(level, _mapped_speech)
	var other_target: BarrageView = _spawn_normal_target(level, _other_speech)
	if not _check_targets([mapped_target, other_target], "映射及未映射目标"):
		return
	_check(mapped_target.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "映射原句装配负收益特性")
	await _place_overlapped_targets([mapped_target, other_target])
	var before_count: int = _flow_resolutions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_for_flow_count(before_count + 1)
	if _flow_resolutions.size() <= before_count:
		return
	var submission: Dictionary = _flow_resolutions.back()["submission"]
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var target_results: Array = hit_result.get("target_results", [])
	var matched_result_found: bool = false
	var other_result_found: bool = false
	for target_result: Dictionary in target_results:
		var sentence_id: String = str(target_result.get("original_sentence_id", ""))
		if sentence_id == _mapped_speech.original_sentence_id:
			matched_result_found = true
			_check(not bool(target_result.get("is_valid_hit", true)), "映射目标是实际碰撞但没有常规收益")
		if sentence_id == _other_speech.original_sentence_id:
			other_result_found = true
	_check(target_results.size() == 2, "最终结算保留两条逐目标命中事实")
	_check(matched_result_found and other_result_found, "最终事实保留映射 ID 与未映射 ID")
	await get_tree().create_timer(0.4, true, false, true).timeout
	var player_texts: Array[String] = _bubble_texts(_player_stack)
	var opponent_texts: Array[String] = _bubble_texts(_opponent_stack)
	_check(player_texts == [_mapped_speech.text, _other_speech.text], "SD-04 仍按结算顺序复述两条实际命中原句")
	_check(opponent_texts == [_test_reply.text], "仅命中指定稳定 ID 时显示对手配置回复")
	_check(_test_reply.priority == BubbleDialogueEntry.Priority.TIMED_IDLE, "消费过程没有改写静态配置优先级")
	_check(not opponent_texts.has(low_priority_entry.text), "剧情优先回复已结束较低优先级活动对白")
	await _capture_evidence()


# CA-15 遮挡整发最终没有目标结果，玩家复述和对手回复都不应新增。
func _run_occlusion_miss_case(level: LevelProfile) -> void:
	_battle_hud.call("clear_dialogue_bubbles")
	var occlusion: BarrageView = _spawn_normal_target(level, _mapped_speech)
	var mapped_target: BarrageView = _spawn_normal_target(level, _mapped_speech)
	var other_target: BarrageView = _spawn_normal_target(level, _other_speech)
	if not _check_targets([occlusion, mapped_target, other_target], "遮挡整发目标"):
		return
	_check(occlusion.runtime_record.trait_set.add_trait(BarrageTraitSet.OCCLUSION), "首个目标装配 CA-15 遮挡特性")
	await _place_overlapped_targets([occlusion, mapped_target, other_target])
	var before_count: int = _flow_resolutions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_for_flow_count(before_count + 1)
	if _flow_resolutions.size() <= before_count:
		return
	var submission: Dictionary = _flow_resolutions.back()["submission"]
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.MISS, "遮挡整发采用最终 MISS 判定")
	_check((hit_result.get("target_results", []) as Array).is_empty(), "MISS 最终结果没有逐目标命中事实")
	await get_tree().process_frame
	_check(_bubble_texts(_player_stack).is_empty(), "遮挡整发没有新增玩家侧复述")
	_check(_bubble_texts(_opponent_stack).is_empty(), "遮挡整发没有新增对手回复")


# 使用正式弹幕入口生成测试目标，测试话语只来自当前关卡 Resource。
func _spawn_normal_target(level: LevelProfile, speech: LevelSpeech) -> BarrageView:
	var view: BarrageView = _barrage_area.spawn_normal_barrage(level, speech)
	if view != null and view.runtime_record != null:
		view.runtime_record.tendency_id = "orthodox"
		view.runtime_record.strength = 3.0
	return view


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
	_send_mouse_motion(canvas_position)
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


# 清理当前目标和双方气泡，隔离不同射击用例。
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


# 从双方正式气泡栈读取当前可见文本。
func _bubble_texts(stack: StreamerBubbleStack) -> Array[String]:
	var result: Array[String] = []
	for child: Node in stack.get_children():
		if child is StreamerBubbleView:
			var text_label: RichTextLabel = child.get_node("Text") as RichTextLabel
			result.append(text_label.text)
	return result


# 保存真实 Godot GUI Viewport 渲染，作为本卡画面证据。
func _capture_evidence() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var directory: String = ProjectSettings.globalize_path(EVIDENCE_DIRECTORY)
	DirAccess.make_dir_recursive_absolute(directory)
	var filename: String = "sd05_specific_sentence_reply_%dx%d.png" % [image.get_width(), image.get_height()]
	var save_result: Error = image.save_png(directory.path_join(filename))
	_check(save_result == OK, "保存实际 Sandbox 回复气泡截图 %s" % filename)


# 逐条保存最终整发提交，测试不构造或改写战斗结算结果。
func _on_flow_shot_resolved(
	snapshot: AttackTargetSnapshot,
	submission: Dictionary,
	_current_tier: int,
	_repeat_stats: RepeatGenerationStats
) -> void:
	_flow_resolutions.append({"snapshot": snapshot, "submission": submission.duplicate(true)})


# 推进场景帧，等待尺寸、输入和队列更新。
func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame


# 使用引擎计时器等待蓄力、飞行与气泡动画。
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


# 释放本测试创建的 Sandbox 并输出明确运行结果。
func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("SD-05 GUI RESULT checks=%d failures=0 display=%s window=%s" % [_checks, DisplayServer.get_name(), DisplayServer.window_get_size()])
		get_tree().quit(0)
	else:
		print("SD-05 GUI RESULT checks=%d failures=%d display=%s window=%s" % [_checks, _failures.size(), DisplayServer.get_name(), DisplayServer.window_get_size()])
		get_tree().quit(1)
