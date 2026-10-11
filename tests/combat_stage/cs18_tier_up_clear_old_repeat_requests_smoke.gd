extends Control

const TARGET_HIT_COUNT: int = 9

var _sandbox: Control
var _flow: BattleAttemptFlow
var _barrage_area: BarrageArea
var _attack_input: AttackChargeInput
var _aim_reticle: AimReticle
var _repeat_queue: RepeatDelayQueue
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _checks: int = 0
var _failures: Array[String] = []
var _old_request_accepted: int = 0
var _resolved_shots: int = 0
var _tier_when_resolved: int = -1
var _valid_normal_hit_count: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_smoke")


# 使用正式 Sandbox 和 Godot 输入链，检查升档清理先前与本发新建的请求。
func _run_smoke() -> void:
	await _wait_frames(2)
	_sandbox = get_node_or_null("Sandbox") as Control
	if _sandbox == null or not _sandbox.has_method("get_battle_attempt_flow"):
		_check(false, "测试加载正式 Sandbox 与 BattleAttemptFlow")
		await _finish()
		return

	_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	if _flow == null:
		_check(false, "Sandbox 启动普通战斗流程")
		await _finish()
		return
	_barrage_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_attack_input = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_aim_reticle = _sandbox.get_node("%AimReticle") as AimReticle
	_repeat_queue = _flow.get_repeat_queue()
	if _barrage_area == null or _attack_input == null or _aim_reticle == null or _repeat_queue == null:
		_check(false, "Sandbox 提供当前尝试的攻击、弹幕区域、准心和复读队列")
		await _finish()
		return

	_flow.get_opponent_pk_bar().stop_pullback()
	_barrage_area.stop_normal_generation()
	_barrage_area.clear_barrages()
	# 仅在本场测试对象中停住普通弹幕，确保一次快照包含所有重叠命中目标。
	_barrage_area.set_generation_multipliers(1.0, 1.0, 0.0)
	_sandbox.call("debug_set_player_pk", 0.55)
	_check(_flow.get_current_tier() == 0, "测试起始 PK 位于 T0 升档阈值下方")

	_attack_input.shot_snapshot_created.connect(_on_shot_snapshot_created)
	_flow.shot_resolved.connect(_on_shot_resolved)
	var level: LevelProfile = _flow.get_current_level_profile()
	var speech: LevelSpeech = level.normal_speech_pool[0] if level != null and not level.normal_speech_pool.is_empty() else null
	if speech == null:
		_check(false, "当前正式关卡提供普通话语供真实攻击命中")
		await _finish()
		return

	var targets: Array[BarrageView] = []
	for _index in range(TARGET_HIT_COUNT):
		var target: BarrageView = _barrage_area.spawn_normal_barrage(level, speech)
		if target == null:
			break
		targets.append(target)
	await _wait_frames(1)
	var center_global: Vector2 = _barrage_area.get_global_rect().get_center()
	var center_local: Vector2 = _barrage_area.get_global_transform().affine_inverse() * center_global
	for target: BarrageView in targets:
		target.position = center_local - target.size * 0.5
	_send_mouse_motion(center_global)
	await _wait_frames(1)
	_check(targets.size() == TARGET_HIT_COUNT, "正式 BarrageArea 接受九个普通目标")
	var all_targets_intersect_aim: bool = true
	for target: BarrageView in targets:
		if not _aim_reticle.intersects_target_area(target.get_global_rect()):
			all_targets_intersect_aim = false
	_check(all_targets_intersect_aim, "九个普通目标都进入同一发的准心范围")

	await _fire_at(center_global)
	await _wait_frames(1)
	_check(_old_request_accepted == 1, "Tier 上升前队列已有一个普通请求")
	_check(_resolved_shots == 1, "正式命中链提交一发完整结算")
	_check(_tier_when_resolved == 1 and _flow.get_current_tier() == 1, "九条普通命中使本发由 T0 升至 T1")
	_check(_valid_normal_hit_count == TARGET_HIT_COUNT, "升档前已消费同发九条有效命中事实")
	var remaining_old_tier_requests: Array[RepeatPlan] = _repeat_queue.advance(
		RepeatDelayQueue.DELAY_CONFIG.maximum_delay_seconds + 0.1
	)
	_check(remaining_old_tier_requests.is_empty(), "整发通知后旧档及本发新建普通复读请求均已清空")
	_check(int(_barrage_area.get_current_barrage_counts().get("repeat", 0)) == 0, "被清理的普通请求没有迟到生成")

	var new_stage_plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		&"cs18_new_stage", "T1 新阶段复读", _flow.get_current_tier(), 1, 4.0
	)
	new_stage_plan.apply_display_template("{原句}")
	var accepted_new_stage_request: int = _repeat_queue.enqueue_plan(new_stage_plan)
	var generated_new_stage_repeats: int = _repeat_queue.advance_and_dispatch(
		RepeatDelayQueue.DELAY_CONFIG.maximum_delay_seconds + 0.1, _barrage_area
	)
	_check(accepted_new_stage_request == 1 and generated_new_stage_repeats == 1, "升档后的普通复读请求仍能进入生成")
	_check(_repeat_queue.get_generation_stats().get_normal_count(&"cs18_new_stage") == 1, "新阶段复读实际生成并计入普通统计")
	_check(_flow.is_normal_combat_active(), "T1 普通战斗继续运行")
	await _finish()


# 命中到达前插入一个旧请求，确保升档覆盖已有队列内容。
func _on_shot_snapshot_created(_snapshot: AttackTargetSnapshot) -> void:
	var old_plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		&"cs18_old_stage", "T0 旧阶段复读", _flow.get_current_tier(), 1, 4.0
	)
	_old_request_accepted = _repeat_queue.enqueue_plan(old_plan)


# 保留正式整发信号携带的 Tier 和逐目标结算结果供本测试核对。
func _on_shot_resolved(
	_snapshot: AttackTargetSnapshot,
	submission: Dictionary,
	current_tier: int,
	_repeat_stats: RepeatGenerationStats
) -> void:
	_resolved_shots += 1
	_tier_when_resolved = current_tier
	_valid_normal_hit_count = 0
	var result: Dictionary = submission.get("hit_resolution_result", {})
	for target_result: Dictionary in result.get("target_results", []):
		if bool(target_result.get("is_valid_hit", false)) and not bool(target_result.get("is_repeat", false)):
			_valid_normal_hit_count += 1


# 攻击使用合成鼠标事件，仍由正式蓄力、飞行 Timer 与命中提交驱动。
func _fire_at(canvas_position: Vector2) -> void:
	_mouse_canvas_position = canvas_position
	_send_mouse_motion(canvas_position)
	_send_mouse_button(true)
	await _wait(0.24)
	_check(_attack_input.is_fully_charged(), "正式攻击完成蓄力")
	_send_mouse_motion(canvas_position)
	_send_mouse_button(false)
	for _index in range(120):
		if _resolved_shots > 0:
			return
		await get_tree().process_frame
	_check(_resolved_shots > 0, "攻击飞行 Timer 发出整发结算")


func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (
		_aim_reticle.get_canvas_transform() * canvas_position
	)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _send_mouse_button(pressed: bool) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (
		_aim_reticle.get_canvas_transform() * _mouse_canvas_position
	)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS CS-18: " + description)
	else:
		_failures.append(description)
		push_error("FAIL CS-18: " + description)


func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("CS-18 RESULT checks=%d failures=0" % _checks)
		get_tree().quit(0)
	else:
		print("CS-18 RESULT checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)
