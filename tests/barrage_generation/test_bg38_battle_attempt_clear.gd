extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")

var _sandbox: Control
var _barrage_area: BarrageArea
var _aim_reticle: AimReticle
var _attack_input: AttackChargeInput
var _battle_flow: BattleAttemptFlow
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _flow_events: Array[Dictionary] = []
var _check_count: int = 0
var _failures: Array[String] = []


# 自动运行两条真实普通战斗流程，检查逐目标移除与整发遮挡落空的边界。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_acceptance")


# 复用正式 Sandbox、攻击输入、HitResolution、BattleAttemptFlow 与 BarrageArea。
func _run_acceptance() -> void:
	SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_sandbox)
	await _wait_frames(2)

	_battle_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	if _battle_flow != null:
		_barrage_area = _battle_flow.get_barrage_area()
		_aim_reticle = _battle_flow.get_aim_reticle()
		_attack_input = _battle_flow.get_attack_input()
	if _barrage_area == null or _aim_reticle == null or _attack_input == null:
		_check(false, "正式 Sandbox 暴露普通战斗流程、弹幕区域与攻击输入")
		await _finish()
		return

	_battle_flow.shot_resolved.connect(_on_shot_resolved)
	_check(_attack_input.configure_attack_timing(SHORT_ATTACK_TIMING), "正式攻击输入接受已有短计时验收配置")
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await _wait_frames(2)

	var level: LevelProfile = _battle_flow.get_current_level_profile()
	var speeches: Array[LevelSpeech] = level.get_normal_speech_pool() if level != null else []
	_check(level != null and not speeches.is_empty(), "当前正式关卡提供可复用普通话语")
	if level == null or speeches.is_empty():
		await _finish()
		return
	print("BG38_CONTENT level_id=%s test_only_traits=true" % level.level_id)

	await _run_unobstructed_multi_hit(level, speeches[0])
	_check(_battle_flow.restart_current_attempt(), "同一 BattleAttemptFlow 可重建下一次普通尝试")
	await _wait_for_attack_ready()
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await _wait_frames(2)
	await _run_global_occlusion_miss(level, speeches[0])

	print("BG38_INPUT source=Input.parse_input_event synthetic mouse events; physical mouse=NOT TESTED")
	await _finish()


# 多目标有效命中应结束普通、假牌、水军复制品和复读四种实际实例。
func _run_unobstructed_multi_hit(level: LevelProfile, speech: LevelSpeech) -> void:
	var ordinary_a: BarrageView = _spawn_normal_target(level, speech)
	var ordinary_b: BarrageView = _spawn_normal_target(level, speech)
	var fake_card: BarrageView = _spawn_normal_target(level, speech)
	var water_army: BarrageView = _spawn_normal_target(level, speech)
	var repeat: BarrageView = _spawn_repeat_target(speech)
	var targets: Array[BarrageView] = [ordinary_a, ordinary_b, fake_card, water_army, repeat]
	if not _check_required_views(targets, "无遮挡多目标用例"):
		return
	# 流程会在 shot_resolved 前结束并释放目标，先冻结 ID 供事后核对。
	var target_instance_ids: Array[int] = _get_instance_ids(targets)

	_check(fake_card.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "假牌目标装配 TEST_ONLY fake_card")
	_check(water_army.runtime_record.trait_set.mark_as_retaliation_copy(), "水军目标装配既有 retaliation_copy 特性")
	_check(water_army.runtime_record.trait_set.get_hit_result().kind == BarrageTraitResult.Kind.RETALIATION_COPY, "水军目标使用既有复制品结算结果")
	await _place_overlapped_targets(targets)
	var event_index: int = _flow_events.size()
	await _fire_at(_barrage_area.get_global_rect().get_center(), event_index + 1)
	await _wait_frames(2)

	var event: Dictionary = _flow_events[event_index] if _flow_events.size() > event_index else {}
	if event.is_empty():
		_check(false, "多目标命中到达 BattleAttemptFlow.shot_resolved")
		return
	var snapshot: AttackTargetSnapshot = event.get("snapshot") as AttackTargetSnapshot
	var submission: Dictionary = event.get("submission", {})
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var target_results: Array = hit_result.get("target_results", [])
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.NONE, "无遮挡多目标沿用逐目标结算")
	_check(snapshot != null and _id_set_matches(snapshot.get_target_instance_ids(), target_instance_ids), "释放快照冻结五个不同目标实例")
	_check(target_results.size() == targets.size(), "BattleAttemptFlow 收到全部五项逐目标结果")
	_check(_result_matches(target_results, target_instance_ids[0], BarrageTraitResult.Kind.NORMAL, true, false), "普通话语作为有效目标结算")
	_check(_result_matches(target_results, target_instance_ids[1], BarrageTraitResult.Kind.NORMAL, true, false), "第二条普通话语同发结算")
	_check(_result_matches(target_results, target_instance_ids[2], BarrageTraitResult.Kind.FAKE_CARD, false, false), "假牌目标产生负向结果并参与结束")
	_check(_result_matches(target_results, target_instance_ids[3], BarrageTraitResult.Kind.RETALIATION_COPY, false, false), "水军复制品产生负向结果并参与结束")
	_check(_result_matches(target_results, target_instance_ids[4], BarrageTraitResult.Kind.NORMAL, true, true), "复读作为有效零收益目标结算")
	_check(_all_views_ended(targets), "BattleAttemptFlow 经 BarrageArea.end_barrage 结束全部五个实例")
	_check(int(_barrage_area.get_current_barrage_counts().get("normal", -1)) == 0, "有效命中后普通与特殊实例都已离开区域")
	_check(int(_barrage_area.get_current_barrage_counts().get("repeat", -1)) == 0, "有效命中后复读实例也已离开区域")

	var history: Array[Dictionary] = _battle_flow.get_hit_resolution().get_normal_hit_history()
	var history_hit_count: int = 0
	for history_record: Dictionary in history:
		history_hit_count += int(history_record.get("hit_count", 0))
	_check(history_hit_count == 2, "两条普通有效命中各写入一次普通命中历史")
	_check(SaveManager.data.tendency_state.attempt_orthodox_total == 20, "普通命中倾向只累计两条普通话语")
	var expected_repeat_count: int = _battle_flow.get_combat_stage().get_current_repeat_count_per_hit() * 2
	var generated_repeat_count: int = _battle_flow.get_repeat_queue().advance_and_dispatch(1000.0, _barrage_area)
	_check(generated_repeat_count == expected_repeat_count, "两条普通命中生成配置数量复读，复读命中不追加计划")
	_check(
		_battle_flow.get_repeat_generation_stats().get_normal_count(StringName(speech.original_sentence_id))
			== expected_repeat_count,
		"复读生成统计只消费两条普通命中的计划"
	)


# 快照含遮挡时整发 MISS 应保留同发全部实例并跳过命中副作用。
func _run_global_occlusion_miss(level: LevelProfile, speech: LevelSpeech) -> void:
	var occlusion: BarrageView = _spawn_normal_target(level, speech)
	var ordinary: BarrageView = _spawn_normal_target(level, speech)
	var fake_card: BarrageView = _spawn_normal_target(level, speech)
	var water_army: BarrageView = _spawn_normal_target(level, speech)
	var repeat: BarrageView = _spawn_repeat_target(speech)
	var targets: Array[BarrageView] = [occlusion, ordinary, fake_card, water_army, repeat]
	if not _check_required_views(targets, "全局遮挡 MISS 用例"):
		return
	var target_instance_ids: Array[int] = _get_instance_ids(targets)
	_check(occlusion.runtime_record.trait_set.add_trait(BarrageTraitSet.OCCLUSION), "遮挡目标装配 TEST_ONLY occlusion")
	_check(fake_card.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "MISS 同发仍包含 fake_card 目标")
	_check(water_army.runtime_record.trait_set.mark_as_retaliation_copy(), "MISS 同发仍包含水军复制品")
	await _place_overlapped_targets(targets)
	var event_index: int = _flow_events.size()
	var pk_before: float = _battle_flow.get_hit_resolution().get_player_pk()
	await _fire_at(_barrage_area.get_global_rect().get_center(), event_index + 1)
	await _wait_frames(2)

	var event: Dictionary = _flow_events[event_index] if _flow_events.size() > event_index else {}
	if event.is_empty():
		_check(false, "遮挡整发落空到达 BattleAttemptFlow.shot_resolved")
		return
	var snapshot: AttackTargetSnapshot = event.get("snapshot") as AttackTargetSnapshot
	var submission: Dictionary = event.get("submission", {})
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	_check(snapshot != null and _id_set_matches(snapshot.get_target_instance_ids(), target_instance_ids), "MISS 快照仍冻结全部五个目标实例")
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.MISS, "CA-15 遮挡按整发 MISS 提交")
	_check((hit_result.get("target_results", []) as Array).is_empty(), "整发 MISS 不提交部分目标结果")
	_check(is_equal_approx(float(hit_result.get("total_pk_delta", 0.0)), -0.01), "整发 MISS 只扣一次既有惩罚")
	_check(is_equal_approx(_battle_flow.get_hit_resolution().get_player_pk() - pk_before, -0.01), "整发 MISS 的实际 PK 变化为一次 -0.01")
	_check(_all_views_persist(targets), "遮挡、普通、假牌、水军与复读原实例全部保留")
	_check(int(_barrage_area.get_current_barrage_counts().get("normal", -1)) == 4, "全局 MISS 保留四个普通及特殊实例")
	_check(int(_barrage_area.get_current_barrage_counts().get("repeat", -1)) == 1, "全局 MISS 保留原复读实例")
	_check(_battle_flow.get_hit_resolution().get_normal_hit_history().is_empty(), "整发 MISS 没有写入普通命中历史")
	_check(_tendencies_are_zero(), "整发 MISS 没有增加任何倾向")
	var repeat_stats: RepeatGenerationStats = _battle_flow.get_repeat_generation_stats()
	_check(repeat_stats != null and repeat_stats.normal_counts_by_line_id.is_empty(), "整发 MISS 没有生成或记录普通复读")
	var dispatched_repeats: int = _battle_flow.get_repeat_queue().advance_and_dispatch(1000.0, _barrage_area)
	_check(dispatched_repeats == 0, "整发 MISS 后队列没有可消费的普通复读计划")
	_check(_all_views_persist(targets), "推进复读队列后原始目标实例仍在场")


# 用正式 BarrageArea 入口创建目标，并写入仅服务本次规则验证的运行时强度与倾向。
func _spawn_normal_target(level: LevelProfile, speech: LevelSpeech) -> BarrageView:
	var view: BarrageView = _barrage_area.spawn_normal_barrage(level, speech)
	if view != null and view.runtime_record != null:
		view.runtime_record.tendency_id = "orthodox"
		view.runtime_record.strength = 3.0
	return view


# 通过正式复读计划和生成入口创建一个在场复读目标。
func _spawn_repeat_target(speech: LevelSpeech) -> BarrageView:
	var plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		StringName(speech.original_sentence_id), speech.text,
		_battle_flow.get_current_tier(), 1, 30.0, "orthodox"
	)
	plan.apply_display_template("{原句}")
	return _barrage_area.spawn_repeat_barrage(plan)


# 等待真实控件尺寸后把所有目标放到同一准心区域。
func _place_overlapped_targets(targets: Array[BarrageView]) -> void:
	var center_global: Vector2 = _barrage_area.get_global_rect().get_center()
	var area_to_global: Transform2D = _barrage_area.get_global_transform()
	var center_local: Vector2 = area_to_global.affine_inverse() * center_global
	await get_tree().process_frame
	for target: BarrageView in targets:
		target.position = center_local - target.size * 0.5
	_mouse_canvas_position = center_global
	_send_mouse_motion(_mouse_canvas_position)
	await get_tree().process_frame
	var all_targets_intersect: bool = true
	for target: BarrageView in targets:
		if not _aim_reticle.intersects_target_area(target.get_global_rect()):
			all_targets_intersect = false
	_check(all_targets_intersect, "实际普通、特殊与复读视图均与准心相交")


# 使用正式 AttackChargeInput 与 Timer 完成蓄力、释放和飞行结算。
func _fire_at(canvas_position: Vector2, expected_event_count: int) -> void:
	_mouse_canvas_position = canvas_position
	_send_mouse_motion(_mouse_canvas_position)
	_check(_aim_reticle.get_aim_center_global_position().distance_to(canvas_position) < 1.0, "合成输入将准心移动至重叠目标")
	_send_mouse_button(true)
	await _wait(0.24)
	_check(_attack_input.is_fully_charged(), "正式攻击输入完成蓄力")
	_send_mouse_button(false)
	await _wait_for_flow_event_count(expected_event_count)


# 将画布坐标按当前 Canvas 与 Viewport 变换换成正式鼠标事件坐标。
func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * canvas_position)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 按变换后的鼠标位置分发正式按下与释放事件。
func _send_mouse_button(pressed: bool) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * _mouse_canvas_position)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 等待 BattleAttemptFlow 发出本发结束事实，超时会明确计为失败。
func _wait_for_flow_event_count(expected_count: int) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while _flow_events.size() < expected_count and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	_check(_flow_events.size() >= expected_count, "攻击飞行 Timer 发出 shot_resolved")


# 等待前一发攻击硬直结束后再发起下一次输入。
func _wait_for_attack_ready() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while not _attack_input.can_start_charging() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	_check(_attack_input.can_start_charging(), "攻击硬直后回到 READY")


# 检查本次测试能否拿到完整的真实 BarrageView 集合。
func _check_required_views(targets: Array[BarrageView], label: String) -> bool:
	var all_valid: bool = true
	for target: BarrageView in targets:
		if target == null or not is_instance_valid(target):
			all_valid = false
	_check(all_valid, label + " 创建实际 BarrageView")
	return all_valid


# 按实例 ID 读取命中结果并核对类型、有效性及复读标记。
func _result_matches(
		target_results: Array, target_instance_id: int, expected_kind: BarrageTraitResult.Kind,
		is_valid_hit: bool, is_repeat: bool
) -> bool:
	for target_result: Dictionary in target_results:
		if int(target_result.get("target_instance_id", -1)) != target_instance_id:
			continue
		var trait_result: BarrageTraitResult = target_result.get("trait_result") as BarrageTraitResult
		return (trait_result != null and trait_result.kind == expected_kind
			and bool(target_result.get("is_valid_hit", false)) == is_valid_hit
			and bool(target_result.get("is_repeat", false)) == is_repeat)
	return false


# 比较快照 ID 与本次实际目标集合，排除漏选或重复实例。
func _get_instance_ids(targets: Array[BarrageView]) -> Array[int]:
	var instance_ids: Array[int] = []
	for target: BarrageView in targets:
		if target != null and is_instance_valid(target):
			instance_ids.append(target.get_instance_id())
	return instance_ids


# 在目标完成释放后仍可按冻结 ID 比较快照与结果，不再访问已释放 Node。
func _id_set_matches(instance_ids: Array[int], expected_instance_ids: Array[int]) -> bool:
	var expected_ids: Dictionary = {}
	var actual_ids: Dictionary = {}
	for instance_id: int in expected_instance_ids:
		expected_ids[instance_id] = true
	for instance_id: int in instance_ids:
		actual_ids[instance_id] = true
	if expected_ids.size() != actual_ids.size():
		return false
	for instance_id: int in expected_ids:
		if not actual_ids.has(instance_id):
			return false
	return true


# 确认有效命中目标已被 BarrageArea 立即移出，且可排队释放。
func _all_views_ended(targets: Array[BarrageView]) -> bool:
	for target: BarrageView in targets:
		if is_instance_valid(target) and target.get_parent() == _barrage_area:
			return false
	return true


# 检查整发 MISS 后每个 BarrageView 仍是原来的场景实例。
func _all_views_persist(targets: Array[BarrageView]) -> bool:
	for target: BarrageView in targets:
		if (not is_instance_valid(target) or target.get_parent() != _barrage_area
				or not target.is_inside_tree() or target.is_queued_for_deletion()):
			return false
	return true


# 读取当前周目三项倾向，确认全局 MISS 没有累计倾向。
func _tendencies_are_zero() -> bool:
	var state: TendencyState = SaveManager.data.tendency_state
	return (state.attempt_orthodox_total == 0 and state.attempt_heretical_total == 0
		and state.attempt_absurd_total == 0)


# 收集 BattleAttemptFlow 完成逐目标处理后的公开结果。
func _on_shot_resolved(
		snapshot: AttackTargetSnapshot, submission: Dictionary,
		_current_tier: int, _repeat_stats: RepeatGenerationStats
) -> void:
	_flow_events.append({"snapshot": snapshot, "submission": submission.duplicate(true)})


# 等待指定数量的实际引擎帧，供场景尺寸与节点释放稳定后断言。
func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame


# 用允许暂停时推进的场景计时器等待正式攻击蓄力。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# 汇总检查结果，让 Godot 进程退出码直接反映本次验收状态。
func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("BG38 OK: " + description)
	else:
		_failures.append(description)
		printerr("BG38 FAIL: " + description)


# 释放本测试创建的 Sandbox，并使用失败数返回进程退出码。
func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("BG38 RESULT checks=%d shots=%d failures=0" % [_check_count, _flow_events.size()])
		get_tree().quit(0)
	else:
		print("BG38 RESULT checks=%d shots=%d failures=%d" % [_check_count, _flow_events.size(), _failures.size()])
		get_tree().quit(1)
