extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")

var _sandbox: Control
var _barrage_area: BarrageArea
var _aim_reticle: AimReticle
var _attack_input: AttackChargeInput
var _battle_flow: BattleAttemptFlow
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _snapshots: Array[AttackTargetSnapshot] = []
var _arrivals: Array[Dictionary] = []
var _submissions: Array[Dictionary] = []
var _flow_resolutions: Array[Dictionary] = []
var _check_count: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_acceptance")


# 使用正式 Sandbox、弹幕生成、攻击 Timer、HitResolution 与 BattleAttemptFlow 验收整发规则。
func _run_acceptance() -> void:
	SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_sandbox)
	await _wait_frames(2)

	_barrage_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_aim_reticle = _sandbox.get_node("%AimReticle") as AimReticle
	_attack_input = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_battle_flow = _sandbox.get("_battle_attempt_flow") as BattleAttemptFlow
	if _barrage_area == null or _aim_reticle == null or _attack_input == null or _battle_flow == null:
		_check(false, "正式 Sandbox 提供攻击、弹幕区域与普通战斗流程")
		await _finish()
		return

	_attack_input.shot_snapshot_created.connect(_on_snapshot_created)
	_attack_input.shot_arrival_resolved.connect(_on_arrival_resolved)
	_attack_input.shot_hit_resolution_submitted.connect(_on_hit_resolution_submitted)
	_battle_flow.shot_resolved.connect(_on_flow_shot_resolved)
	_check(_attack_input.configure_attack_timing(SHORT_ATTACK_TIMING), "正式攻击组件接受已有短计时验收配置")
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await _wait_frames(2)

	var level: LevelProfile = _battle_flow.get_current_level_profile()
	var speeches: Array[LevelSpeech] = level.get_normal_speech_pool() if level != null else []
	_check(level != null and not speeches.is_empty(), "当前正式关卡提供可复用话语定义")
	if level == null or speeches.is_empty():
		await _finish()
		return
	print("CA15_CONTENT level_id=%s test_only_traits=true" % level.level_id)

	await _run_occlusion_mix_case(level, speeches[0])
	await _clear_targets()
	await _wait_for_attack_ready()
	await _run_occlusion_reflect_case(level, speeches[0])
	await _clear_targets()
	await _wait_for_attack_ready()
	await _run_unobstructed_control(level, speeches[0])

	print("CA15_INPUT source=Input.parse_input_event synthetic mouse events; physical mouse=NOT TESTED")
	await _finish()


# 遮挡与正向、负向、复读目标重叠时，整发只提交普通 MISS 且保留所有实例。
func _run_occlusion_mix_case(level: LevelProfile, speech: LevelSpeech) -> void:
	var occlusion: BarrageView = _spawn_normal_target(level, speech)
	var positive: BarrageView = _spawn_normal_target(level, speech)
	var negative: BarrageView = _spawn_normal_target(level, speech)
	var repeat: BarrageView = _spawn_repeat_target(speech)
	if not _check_required_views([occlusion, positive, negative, repeat], "遮挡混合用例"):
		return

	_check(occlusion.runtime_record.trait_set.add_trait(BarrageTraitSet.OCCLUSION), "遮挡目标装配 TEST_ONLY occlusion")
	_check(negative.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "负向目标装配已有 fake_card 特性")
	var targets: Array[BarrageView] = [occlusion, positive, negative, repeat]
	await _place_overlapped_targets(targets)
	var before_submission_count: int = _submissions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_frames(2)

	_check(_submissions.size() == before_submission_count + 1, "混合重叠目标只产生一次结算提交")
	if _submissions.size() <= before_submission_count:
		return
	var snapshot: AttackTargetSnapshot = _submissions.back()["snapshot"] as AttackTargetSnapshot
	var submission: Dictionary = _submissions.back()["submission"] as Dictionary
	_check(snapshot != null and snapshot.get_target_instance_ids().size() == targets.size(), "释放快照冻结四个不同运行目标")
	var has_occlusion_snapshot_api: bool = snapshot != null and snapshot.has_method("get_occlusion_target_instance_ids")
	_check(has_occlusion_snapshot_api, "释放快照公开保留原始遮挡目标 ID")
	if has_occlusion_snapshot_api:
		_check(_contains_once(_get_snapshot_occlusion_ids(snapshot), occlusion.get_instance_id()), "原始释放快照保留遮挡目标稳定 ID")
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.MISS, "混合整发选择普通 MISS")
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var settled_targets: Array = hit_result.get("target_results", [])
	_check(settled_targets.is_empty(), "MISS 不提交任何逐目标命中或收益")
	_check(is_equal_approx(float(hit_result.get("total_pk_delta", 0.0)), -0.01), "整发只扣一次既有 MISS 惩罚 -0.01")
	_check(_all_views_persist(targets), "正常、负向、复读及遮挡实例全部留在场上")
	_check(_battle_flow.get_hit_resolution().get_normal_hit_history().is_empty(), "遮挡整发没有写入普通命中历史")
	_check(_tendencies_are_zero(), "遮挡整发没有增加任何倾向")
	var generated_repeat_count: int = _battle_flow.get_repeat_queue().advance_and_dispatch(1000.0, _barrage_area)
	_check(generated_repeat_count == 0, "遮挡整发没有排入普通复读计划")
	_check(_flow_resolutions.size() == before_submission_count + 1, "BattleAttemptFlow 只收到这一份 MISS 结果")


# 同一 TraitSet 同时有反射与遮挡时保留单目标反射优先级，但整发仍按遮挡 MISS。
func _run_occlusion_reflect_case(level: LevelProfile, speech: LevelSpeech) -> void:
	var target: BarrageView = _spawn_normal_target(level, speech)
	if not _check_required_views([target], "遮挡反射混合用例"):
		return
	_check(target.runtime_record.trait_set.add_trait(BarrageTraitSet.OCCLUSION), "混合特性目标装配 TEST_ONLY occlusion")
	_check(target.runtime_record.trait_set.add_trait(BarrageTraitSet.REFLECT), "混合特性目标装配既有 reflect")
	_check(target.runtime_record.trait_set.get_hit_result().kind == BarrageTraitResult.Kind.REFLECT, "单目标 TraitResult 继续保留反射优先级")

	var targets: Array[BarrageView] = [target]
	await _place_overlapped_targets(targets)
	var before_submission_count: int = _submissions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_frames(2)

	if _submissions.size() <= before_submission_count:
		_check(false, "反射与遮挡组合提交一次结果")
		return
	var arrival: Dictionary = _arrivals.back()
	var arrival_results: Array = arrival.get("target_results", [])
	var arrival_trait_result: BarrageTraitResult
	if not arrival_results.is_empty():
		arrival_trait_result = arrival_results[0].get("trait_result") as BarrageTraitResult
	_check(arrival_trait_result != null and arrival_trait_result.kind == BarrageTraitResult.Kind.REFLECT, "到达表现接口继续收到原始反射 TraitResult")
	var snapshot: AttackTargetSnapshot = _submissions.back()["snapshot"] as AttackTargetSnapshot
	var submission: Dictionary = _submissions.back()["submission"] as Dictionary
	var has_occlusion_snapshot_api: bool = snapshot != null and snapshot.has_method("get_occlusion_target_instance_ids")
	_check(has_occlusion_snapshot_api, "反射目标保留原始遮挡快照接口")
	if has_occlusion_snapshot_api:
		_check(_contains_once(_get_snapshot_occlusion_ids(snapshot), target.get_instance_id()), "反射结果未覆盖快照中的遮挡 ID")
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.MISS, "单目标反射优先结果不能取消整发遮挡 MISS")
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	_check((hit_result.get("target_results", []) as Array).is_empty(), "反射与遮挡组合仍没有目标命中结果")
	_check(is_equal_approx(float(hit_result.get("total_pk_delta", 0.0)), -0.01), "反射与遮挡组合仍只扣一次普通 MISS 惩罚")
	_check(_all_views_persist(targets), "反射与遮挡组合的原实例继续存在")
	_check(_battle_flow.get_hit_resolution().get_normal_hit_history().is_empty(), "反射与遮挡组合没有记录普通命中")
	_check(_tendencies_are_zero(), "反射与遮挡组合没有增加倾向")
	var generated_repeat_count: int = _battle_flow.get_repeat_queue().advance_and_dispatch(1000.0, _barrage_area)
	_check(generated_repeat_count == 0, "反射与遮挡组合没有新增复读")


# 无遮挡时保留现有正向、负向与复读逐目标结算，作为对照组。
func _run_unobstructed_control(level: LevelProfile, speech: LevelSpeech) -> void:
	var positive: BarrageView = _spawn_normal_target(level, speech)
	var negative: BarrageView = _spawn_normal_target(level, speech)
	var repeat: BarrageView = _spawn_repeat_target(speech)
	if not _check_required_views([positive, negative, repeat], "无遮挡对照用例"):
		return
	_check(negative.runtime_record.trait_set.add_trait(BarrageTraitSet.FAKE_CARD), "对照负向目标装配已有 fake_card 特性")

	var targets: Array[BarrageView] = [positive, negative, repeat]
	await _place_overlapped_targets(targets)
	var before_submission_count: int = _submissions.size()
	await _fire_at(_barrage_area.get_global_rect().get_center())
	await _wait_frames(2)

	if _submissions.size() <= before_submission_count:
		_check(false, "无遮挡对照组提交一次结果")
		return
	var snapshot: AttackTargetSnapshot = _submissions.back()["snapshot"] as AttackTargetSnapshot
	var submission: Dictionary = _submissions.back()["submission"] as Dictionary
	var has_occlusion_snapshot_api: bool = snapshot != null and snapshot.has_method("get_occlusion_target_instance_ids")
	_check(has_occlusion_snapshot_api and _get_snapshot_occlusion_ids(snapshot).is_empty(), "对照快照确认没有遮挡目标")
	_check(submission.get("shot_anomaly") == HitResolution.ShotAnomaly.NONE, "无遮挡目标沿用原逐目标结算")
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var settled_targets: Array = hit_result.get("target_results", [])
	var successful_hit_count: int = 0
	var found_repeat: bool = false
	for target_result: Dictionary in settled_targets:
		if bool(target_result.get("is_valid_hit", false)):
			successful_hit_count += 1
			found_repeat = found_repeat or bool(target_result.get("is_repeat", false))
	_check(settled_targets.size() == targets.size() and successful_hit_count == 2 and found_repeat, "对照组保留普通与复读命中、同时结算负向目标")
	_check(is_equal_approx(float(hit_result.get("total_pk_delta", INF)), 0.0), "对照组沿用正负目标贡献相抵")
	_check(_battle_flow.get_hit_resolution().get_normal_hit_history().size() == 1, "无遮挡普通命中继续写入命中历史")
	_check(SaveManager.data.tendency_state.attempt_orthodox_total > 0, "无遮挡普通命中继续累计倾向")


# 使用当前正式话语创建独立运行实例；TEST_ONLY 强度和倾向仅供结果路径验收。
func _spawn_normal_target(level: LevelProfile, speech: LevelSpeech) -> BarrageView:
	var view: BarrageView = _barrage_area.spawn_normal_barrage(level, speech)
	if view != null and view.runtime_record != null:
		view.runtime_record.tendency_id = "orthodox"
		view.runtime_record.strength = 3.0
	return view


# 复读目标经现有计划和 BarrageArea 正式入口生成，计划数量及寿命仅为 TEST_ONLY。
func _spawn_repeat_target(speech: LevelSpeech) -> BarrageView:
	var plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		StringName(speech.original_sentence_id), speech.text,
		_battle_flow.get_current_tier(), 1, 30.0, "orthodox"
	)
	plan.apply_display_template("{原句}")
	return _barrage_area.spawn_repeat_barrage(plan)


func _check_required_views(targets: Array, label: String) -> bool:
	var valid: bool = true
	for target in targets:
		if target == null or not is_instance_valid(target):
			valid = false
	_check(valid, label + " 创建真实 BarrageView")
	return valid


# 等待真实控件尺寸稳定后对齐，确认所有类型目标同时与本发准心相交。
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
	var every_target_intersects_aim: bool = true
	for target: BarrageView in targets:
		if not _aim_reticle.intersects_target_area(target.get_global_rect()):
			every_target_intersects_aim = false
	_check(every_target_intersects_aim, "同一快照中的真实普通、特殊及复读目标都与准心相交")


# 使用真实攻击输入和 Godot Timer 走完蓄力、释放与飞行，等待一次实际结算信号。
func _fire_at(canvas_position: Vector2) -> void:
	var before_snapshot_count: int = _snapshots.size()
	var before_submission_count: int = _submissions.size()
	_mouse_canvas_position = canvas_position
	_send_mouse_motion(_mouse_canvas_position)
	_check(_aim_reticle.get_aim_center_global_position().distance_to(canvas_position) < 1.0, "合成输入把准心移动到重叠目标")
	_send_mouse_button(true)
	await _wait(0.24)
	_check(_attack_input.is_fully_charged(), "正式攻击组件完成蓄力")
	_send_mouse_button(false)
	await _wait_for_submission_count(before_submission_count + 1)
	_check(_snapshots.size() == before_snapshot_count + 1, "一次释放创建一份不可变目标快照")


# 画布坐标经视口完整变换转换为窗口输入位置，避免 headless 缩放造成误判。
func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * canvas_position)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 合成按下 / 释放仍通过 Godot 输入分发与正式攻击组件。
func _send_mouse_button(pressed: bool) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * _mouse_canvas_position)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _wait_for_submission_count(required_count: int) -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while _submissions.size() < required_count and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	_check(_submissions.size() >= required_count, "攻击飞行 Timer 发出结算提交")


func _wait_for_attack_ready() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while not _attack_input.can_start_charging() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	_check(_attack_input.can_start_charging(), "攻击硬直结束后回到 READY")


func _clear_targets() -> void:
	_barrage_area.clear_barrages()
	await _wait_frames(2)


func _wait_frames(frame_count: int) -> void:
	for _index in range(frame_count):
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _all_views_persist(targets: Array[BarrageView]) -> bool:
	for target: BarrageView in targets:
		if target == null or not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			return false
	return true


func _contains_once(instance_ids: Array[int], expected_id: int) -> bool:
	var matches: int = 0
	for instance_id: int in instance_ids:
		if instance_id == expected_id:
			matches += 1
	return matches == 1


func _get_snapshot_occlusion_ids(snapshot: AttackTargetSnapshot) -> Array[int]:
	if snapshot == null or not snapshot.has_method("get_occlusion_target_instance_ids"):
		return []
	return snapshot.call("get_occlusion_target_instance_ids") as Array[int]


func _tendencies_are_zero() -> bool:
	var state: TendencyState = SaveManager.data.tendency_state
	return state.attempt_orthodox_total == 0 and state.attempt_heretical_total == 0 and state.attempt_absurd_total == 0


func _on_snapshot_created(snapshot: AttackTargetSnapshot) -> void:
	_snapshots.append(snapshot)


func _on_arrival_resolved(snapshot: AttackTargetSnapshot, target_results: Array[Dictionary]) -> void:
	_arrivals.append({"snapshot": snapshot, "target_results": target_results.duplicate(true)})


func _on_hit_resolution_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_submissions.append({"snapshot": snapshot, "submission": submission.duplicate(true)})


func _on_flow_shot_resolved(
		snapshot: AttackTargetSnapshot, submission: Dictionary,
		_current_tier: int, _repeat_stats: RepeatGenerationStats
) -> void:
	_flow_resolutions.append({"snapshot": snapshot, "submission": submission.duplicate(true)})


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("CA15 OK: " + description)
	else:
		_failures.append(description)
		printerr("CA15 FAIL: " + description)


# 退出时释放本测试创建的正式 Sandbox，并显式输出场景验收结果。
func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("CA15 RESULT checks=%d submissions=%d failures=0" % [_check_count, _submissions.size()])
		get_tree().quit(0)
	else:
		print("CA15 RESULT checks=%d submissions=%d failures=%d" % [_check_count, _submissions.size(), _failures.size()])
		get_tree().quit(1)
