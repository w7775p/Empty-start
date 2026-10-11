extends Control

const REPEAT_BACKGROUND_ID: StringName = &"cs14_repeat_background"

var _sandbox: Control
var _flow: BattleAttemptFlow
var _barrage_area: BarrageArea
var _attack_input: AttackChargeInput
var _aim_reticle: AimReticle
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _checks: int = 0
var _failures: Array[String] = []
var _resolved_shots: int = 0
var _resolved_tier: int = -1
var _resolved_total_pk_delta: float = 0.0
var _resolved_valid_normal_hits: int = 0
var _resolved_barrage_counts: Dictionary = {}
var _resolved_comment_count: int = -1
var _transition_results: Array[Dictionary] = []
var _inject_cross_tier_on_arrival: bool = false
var _cross_tier_injected: bool = false
var _capture_path: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capture_path = OS.get_environment("CS14_EVIDENCE_PATH")
	call_deferred("_run_smoke")


# 使用正式 Sandbox 和攻击链覆盖普通升档、跨档清屏及生成状态保留。
func _run_smoke() -> void:
	await _wait_frames(2)
	# 延后加载 Sandbox，让项目资源导入和 Autoload 有机会完成首次初始化。
	var presentation_assets: PresentationAssetConfig = (
		load("res://data/shared/presentation_asset_config.tres") as PresentationAssetConfig
	)
	var sandbox_scene: PackedScene = load("res://scenes/sandbox/sandbox.tscn") as PackedScene
	if presentation_assets == null or sandbox_scene == null:
		_check(false, "加载 Sandbox 所需共享资源和正式场景")
		await _finish()
		return
	_sandbox = sandbox_scene.instantiate() as Control
	_sandbox.name = "Sandbox"
	add_child(_sandbox)
	await _wait_frames(2)
	if not _sandbox.has_method("get_battle_attempt_flow"):
		_check(false, "正式 Sandbox 提供 BattleAttemptFlow")
		await _finish()
		return

	_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	_barrage_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_attack_input = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_aim_reticle = _sandbox.get_node("%AimReticle") as AimReticle
	if _flow == null or _barrage_area == null or _attack_input == null or _aim_reticle == null:
		_check(false, "Sandbox 提供正式战斗流程、弹幕区域与攻击输入")
		await _finish()
		return

	_flow.get_opponent_pk_bar().stop_pullback()
	_barrage_area.clear_barrages()
	_barrage_area.set_generation_multipliers(1.0, 0.0, 0.0)
	_check(_barrage_area.resume_normal_generation(), "测试开始时普通生成状态已启用")

	var level: LevelProfile = _flow.get_current_level_profile()
	var speech: LevelSpeech = _strongest_normal_speech(level)
	if speech == null:
		_check(false, "当前关卡提供可用于真实攻击的普通话语")
		await _finish()
		return

	_flow.shot_resolved.connect(_on_shot_resolved)
	_flow.tier_transition_cleared.connect(_on_tier_transition_cleared)
	_attack_input.shot_arrival_resolved.connect(_on_shot_arrival_resolved)

	await _run_transition_case(level, speech, 0.559, 0, 1, false, true)
	await _run_transition_case(level, speech, 0.6395, 1, 2, false, false)
	await _run_transition_case(level, speech, -1.0, 2, 5, true, false)
	await _finish()


# 分别验证相邻档位和多档上升；第三次在到达后注入终档，仍由真实整发结算收尾。
func _run_transition_case(
	level: LevelProfile,
	speech: LevelSpeech,
	starting_pk: float,
	expected_previous_tier: int,
	expected_current_tier: int,
	inject_cross_tier: bool,
	capture_evidence: bool
) -> void:
	await _wait_for_attack_ready()
	_barrage_area.stop_normal_generation()
	_barrage_area.clear_current_barrages()
	_barrage_area.set_generation_multipliers(1.0, 0.0, 0.0)
	_check(_barrage_area.resume_normal_generation(), "清屏前后普通生成状态可恢复")
	if starting_pk >= 0.0:
		_sandbox.call("debug_set_player_pk", starting_pk)
	_check(_flow.get_current_tier() == expected_previous_tier, "本发升档基线 Tier 正确")

	var target: BarrageView = _barrage_area.spawn_normal_barrage(level, speech, [], true)
	var plain_background: BarrageView = _barrage_area.spawn_normal_barrage(level, speech, [], true)
	var trait_background: BarrageView = _barrage_area.spawn_normal_barrage(level, speech, [], true)
	var repeat_plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		REPEAT_BACKGROUND_ID, "CS-14 背景复读", expected_previous_tier, 1, 10.0
	)
	repeat_plan.apply_display_template("{原句}")
	var repeat_background: BarrageView = _barrage_area.spawn_repeat_barrage(repeat_plan, true)
	_check(target != null and plain_background != null and trait_background != null and repeat_background != null,
		"区域同时容纳普通、带特性和复读视图")
	if target == null or plain_background == null or trait_background == null or repeat_background == null:
		return
	_check(trait_background.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "背景普通弹幕装配现有特性")

	await _wait_frames(1)
	var center_global: Vector2 = _barrage_area.get_global_rect().get_center()
	var center_local: Vector2 = _barrage_area.get_global_transform().affine_inverse() * center_global
	target.position = center_local - target.size * 0.5
	plain_background.position = Vector2(18.0, 18.0)
	trait_background.position = Vector2(18.0, _barrage_area.size.y - trait_background.size.y - 18.0)
	repeat_background.position = Vector2(_barrage_area.size.x - repeat_background.size.x - 18.0, 18.0)
	_send_mouse_motion(center_global)

	var current_counts: Dictionary = _barrage_area.get_current_barrage_counts()
	_check(int(current_counts.get("normal", 0)) == 3 and int(current_counts.get("repeat", 0)) == 1,
		"射击前场上保留普通、特性和复读弹幕")
	var pre_shot_comment_count: int = int(_sandbox.call("get_debug_snapshot").get("comment_count", -1))
	var previous_transition_count: int = _transition_results.size()
	_resolved_shots = 0
	_inject_cross_tier_on_arrival = inject_cross_tier
	_cross_tier_injected = false
	await _fire_at(center_global)
	await _wait_frames(1)

	_check(_resolved_shots == 1, "正式攻击链提交整发结算")
	_check(_resolved_tier == expected_current_tier and _flow.get_current_tier() == expected_current_tier,
		"shot_resolved 携带本发最终 Tier")
	_check(_resolved_total_pk_delta > 0.0 and _resolved_valid_normal_hits > 0,
		"清屏前已完成真实有效命中和 PK 结算")
	_check(_resolved_comment_count >= pre_shot_comment_count,
		"清屏前本场评论统计已记录")
	_check(_resolved_barrage_counts.get("normal", -1) == 2 and _resolved_barrage_counts.get("repeat", -1) == 1,
		"shot_resolved 消费者运行时，背景普通、特性及复读视图仍可见")
	_check(_transition_results.size() == previous_transition_count + 1,
		"一次整发升档只交付一次清屏完成事件")
	if _transition_results.size() <= previous_transition_count:
		return

	var transition: Dictionary = _transition_results[previous_transition_count]
	_check(int(transition.get("previous_tier", -1)) == expected_previous_tier
		and int(transition.get("current_tier", -1)) == expected_current_tier,
		"清屏完成事件携带升档前后 Tier")
	_check(int(transition.get("cleared_count", 0)) == 3,
		"清屏移除剩余普通、特性和复读视图")
	_check(int(transition.get("normal_count", -1)) == 0
		and int(transition.get("repeat_count", -1)) == 0,
		"清屏完成事件发出时区域内无可见弹幕")
	_check(bool(transition.get("generation_enabled", false))
		and bool(transition.get("normal_combat_active", false)),
		"升档清屏后普通生成与战斗流程继续运行")
	_check(int(transition.get("resolved_shots", -1)) == 1,
		"清屏完成事件发生在所有 shot_resolved 消费者之后")
	_check(int(transition.get("comment_count", -1)) == _resolved_comment_count,
		"清屏不回滚已记录的评论统计")
	if inject_cross_tier:
		_check(_cross_tier_injected, "跨档用例在本发到达后触发确定性 Tier 注入")
		_check(expected_current_tier - expected_previous_tier > 1, "跨档事件只清屏一次并抵达最终 Tier")
	if capture_evidence and not _capture_path.is_empty():
		# 截图只用于交接证据；读取清屏后首帧前暂停生成计时器。
		_barrage_area.stop_normal_generation()
		await RenderingServer.frame_post_draw
		var screenshot: Image = get_viewport().get_texture().get_image()
		_check(screenshot.save_png(_capture_path) == OK, "保存 T0→T1 清屏后的 Sandbox 画面")
	await _wait_for_attack_ready()


# 选取当前关强度最高的话语，减少测试命中数量并保留正式命中规则。
func _strongest_normal_speech(level: LevelProfile) -> LevelSpeech:
	if level == null or level.normal_speech_pool.is_empty():
		return null
	var strongest: LevelSpeech = level.normal_speech_pool[0]
	for speech: LevelSpeech in level.normal_speech_pool:
		if speech.strength > strongest.strength:
			strongest = speech
	return strongest


# 记录整发信号时的结果和仍在场的背景弹幕，证明清理晚于结算消费者。
func _on_shot_resolved(
	_snapshot: AttackTargetSnapshot,
	submission: Dictionary,
	current_tier: int,
	_repeat_stats: RepeatGenerationStats
) -> void:
	_resolved_shots += 1
	_resolved_tier = current_tier
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	_resolved_total_pk_delta = float(hit_result.get("total_pk_delta", 0.0))
	_resolved_valid_normal_hits = 0
	for target_result: Dictionary in hit_result.get("target_results", []):
		if bool(target_result.get("is_valid_hit", false)) and not bool(target_result.get("is_repeat", false)):
			_resolved_valid_normal_hits += 1
	_resolved_barrage_counts = _barrage_area.get_current_barrage_counts()
	_resolved_comment_count = int(_sandbox.call("get_debug_snapshot").get("comment_count", -1))


# 清屏事件只在旧 Tier 弹幕已移除后广播，演出消费者可直接接入。
func _on_tier_transition_cleared(previous_tier: int, current_tier: int, cleared_count: int) -> void:
	_transition_results.append({
		"previous_tier": previous_tier,
		"current_tier": current_tier,
		"cleared_count": cleared_count,
		"normal_count": int(_barrage_area.get_current_barrage_counts().get("normal", -1)),
		"repeat_count": int(_barrage_area.get_current_barrage_counts().get("repeat", -1)),
		"generation_enabled": _barrage_area.is_normal_generation_enabled(),
		"normal_combat_active": _flow.is_normal_combat_active(),
		"resolved_shots": _resolved_shots,
		"comment_count": int(_sandbox.call("get_debug_snapshot").get("comment_count", -1)),
	})


# 第三组用例在 BattleAttemptFlow 记录到达 Tier 后注入终档，覆盖同一整发跨多档分支。
func _on_shot_arrival_resolved(_snapshot: AttackTargetSnapshot, _target_results: Array[Dictionary]) -> void:
	if not _inject_cross_tier_on_arrival:
		return
	_inject_cross_tier_on_arrival = false
	_cross_tier_injected = float(_sandbox.call("debug_set_player_pk", 0.92)) >= 0.92


# 攻击继续经过正式蓄力、鼠标快照和飞行结算信号。
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


# 每发之间等待正式攻击组件结束恢复阶段，避免把硬直误判成清屏失败。
func _wait_for_attack_ready() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while (_attack_input.get_attack_phase() != AttackChargeInput.AttackPhase.READY
			and Time.get_ticks_msec() < deadline_msec):
		await get_tree().process_frame
	_check(_attack_input.get_attack_phase() == AttackChargeInput.AttackPhase.READY,
		"正式攻击完成恢复并可开始下一发")


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS CS-14: " + description)
	else:
		_failures.append(description)
		push_error("FAIL CS-14: " + description)


func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	if _failures.is_empty():
		print("CS-14 RESULT checks=%d failures=0" % _checks)
		get_tree().quit(0)
	else:
		print("CS-14 RESULT checks=%d failures=%d" % [_checks, _failures.size()])
		get_tree().quit(1)
