class_name AttackChargeInput
extends Node

signal shot_snapshot_created(snapshot: AttackTargetSnapshot)
signal shot_arrival_resolved(snapshot: AttackTargetSnapshot, target_results: Array[Dictionary])
signal shot_hit_resolution_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary)

enum AttackPhase { READY, PROJECTILE_FLIGHT, RECOVERY }

var _charge_progress: AttackChargeProgress
var _aim_reticle: AimReticle
var _barrage_area: BarrageArea
var _attack_timing: AttackTimingConfig
var _hit_resolution: HitResolution
var _attack_phase: AttackPhase = AttackPhase.READY
var _phase_timer: Timer
var _active_snapshot: AttackTargetSnapshot
var _attack_held: bool = false
var _combat_active: bool = true
var _contradiction_mode: bool = false
var _new_attacks_locked: bool = false


# 按住输入且没有暂停或飞行 / 硬直时才推进蓄力。
func _process(delta: float) -> void:
	if not _combat_active or _charge_progress == null or get_tree().paused:
		return
	if _attack_phase != AttackPhase.READY:
		# 飞行和硬直期间不推进蓄力。
		return
	if _attack_held:
		_charge_progress.advance(delta, true)


func _ready() -> void:
	# 暂停期间仍接收鼠标抬起以清理按住状态，蓄力本身由下方显式跳过。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_phase_timer = Timer.new()
	# 计时器沿用 Godot 的暂停处理，在暂停中保留剩余时间。
	_phase_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_phase_timer.one_shot = true
	_phase_timer.timeout.connect(_on_attack_phase_timer_timeout)
	add_child(_phase_timer)


# 注入本场读取到的数值配置；正式运行时由共享数值表提供，测试可注入 fixture。
func configure_attack_timing(timing_config: AttackTimingConfig) -> bool:
	if timing_config == null or timing_config.charge_time_s <= 0.0:
		return false
	if timing_config.projectile_flight_s < 0.0 or timing_config.recovery_time_s < 0.0:
		return false
	if _attack_phase != AttackPhase.READY:
		return false

	_attack_timing = timing_config
	_charge_progress = AttackChargeProgress.new(timing_config.charge_time_s)
	return true


# 注入 HitResolution 的现有实例；PK 状态仍由该对象唯一持有。
func configure_hit_resolution(hit_resolution: HitResolution) -> bool:
	if hit_resolution == null or _attack_phase != AttackPhase.READY:
		return false
	_hit_resolution = hit_resolution
	return true


# 由 Sandbox 注入已存在的准心和弹幕区域，避免依赖场景内部 NodePath。
func configure_target_query(aim_reticle: AimReticle, barrage_area: BarrageArea) -> void:
	_aim_reticle = aim_reticle
	_barrage_area = barrage_area


# 矛盾阶段在释放时交付快照；飞行不再复核目标或提交普通收益。
func set_contradiction_mode(active: bool) -> void:
	_contradiction_mode = active
	if not active:
		_new_attacks_locked = false


# 结果在释放时已固定；只封锁下一发，保留当前飞行计时作为演出。
func lock_new_attacks() -> void:
	_new_attacks_locked = true
	_attack_held = false

## 战斗生命周期由场景协调；停止时本组件取消整发和计时，重开可直接回到 READY。
func set_combat_active(active: bool) -> void:
	_combat_active = active
	if active:
		return
	_attack_held = false
	_active_snapshot = null
	_attack_phase = AttackPhase.READY
	if _phase_timer != null:
		_phase_timer.stop()
	if _attack_timing != null:
		_charge_progress = AttackChargeProgress.new(_attack_timing.charge_time_s)


# 在鼠标松开输入事件上冻结当前候选，之后进入准心的弹幕不加入本发。
func _input(event: InputEvent) -> void:
	if not _combat_active or _new_attacks_locked or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		if not get_tree().paused and can_start_charging():
			_attack_held = true
		return

	var was_attack_held: bool = _attack_held
	_attack_held = false
	if was_attack_held and not get_tree().paused:
		_handle_attack_release()


# 未满蓄释放只取消；满蓄释放发送快照事实，不在攻击系统改动 PK。
func _handle_attack_release() -> void:
	if not _combat_active or _charge_progress == null or _attack_phase != AttackPhase.READY:
		return
	if not _charge_progress.is_fully_charged():
		_charge_progress.cancel_if_undercharged()
		return

	var snapshot: AttackTargetSnapshot = _capture_target_snapshot()
	if _charge_progress.consume_fully_charged():
		_active_snapshot = snapshot
		_attack_phase = AttackPhase.PROJECTILE_FLIGHT
		_phase_timer.start(_attack_timing.projectile_flight_s)
		shot_snapshot_created.emit(snapshot)


# 飞行计时结束时复核快照目标并提交到达事实，随后开始硬直计时。
func _on_attack_phase_timer_timeout() -> void:
	if not _combat_active:
		return
	if _attack_phase == AttackPhase.PROJECTILE_FLIGHT:
		var completed_snapshot: AttackTargetSnapshot = _active_snapshot
		if not _contradiction_mode:
			var valid_targets: Array[Node] = completed_snapshot.resolve_present_targets(_barrage_area)
			var target_results: Array[Dictionary] = _build_target_trait_results(valid_targets)
			shot_arrival_resolved.emit(completed_snapshot, target_results)
			if not _combat_active or _active_snapshot != completed_snapshot:
				return
			_submit_arrival_to_hit_resolution(completed_snapshot, target_results)
		# PK 更新和整发提交同步发信号；满值 / 失败可能已经停止本发，不能重新启动硬直。
		if not _combat_active or _active_snapshot != completed_snapshot:
			return
		_attack_phase = AttackPhase.RECOVERY
		_phase_timer.start(_attack_timing.recovery_time_s)
		return

	if _attack_phase == AttackPhase.RECOVERY:
		_active_snapshot = null
		_attack_phase = AttackPhase.READY


# 将真实有效目标的最终特性结果随目标一起交给后续结算，不复制 4 系统规则。
func _build_target_trait_results(valid_targets: Array[Node]) -> Array[Dictionary]:
	var target_results: Array[Dictionary] = []
	for target_node in valid_targets:
		if not target_node is BarrageView:
			continue
		var barrage_view := target_node as BarrageView
		if barrage_view.runtime_record == null or barrage_view.runtime_record.trait_set == null:
			continue

		var trait_result: BarrageTraitResult = barrage_view.runtime_record.trait_set.get_hit_result()
		target_results.append(
			{
				"target_instance_id": barrage_view.get_instance_id(),
				"target": barrage_view,
				"trait_result": trait_result,
			}
		)
	return target_results


# 用 6 系统公开接口计算正常收益、异常优先级与整发 PK；CombatAttack 只组装输入。
func _submit_arrival_to_hit_resolution(
	snapshot: AttackTargetSnapshot,
	trait_target_results: Array[Dictionary]
) -> void:
	if _hit_resolution == null:
		return

	var valid_instance_ids: Dictionary = {}
	var hit_resolution_targets: Array[Dictionary] = []
	var normal_hit_records: Array[Dictionary] = []
	var has_bounce: bool = false
	var has_obstruction: bool = false

	for trait_target_result: Dictionary in trait_target_results:
		var target_instance_id: int = int(trait_target_result.get("target_instance_id", -1))
		var barrage_view := trait_target_result.get("target") as BarrageView
		var trait_result := trait_target_result.get("trait_result") as BarrageTraitResult
		if target_instance_id < 0 or barrage_view == null or trait_result == null:
			continue

		valid_instance_ids[target_instance_id] = true
		if trait_result.anomaly_type == &"reflect":
			has_bounce = true
		elif trait_result.anomaly_type == &"occlusion":
			has_obstruction = true

		var hit_resolution_target: Dictionary = trait_target_result.duplicate()
		var runtime_record: BarrageRuntimeRecord = barrage_view.runtime_record
		if runtime_record != null:
			# 复制内容事实，协调方据结算结果驱动复读 / 倾向，无需回读可能已结束的视图。
			hit_resolution_target["original_sentence_id"] = runtime_record.original_sentence_id
			hit_resolution_target["original_sentence_text"] = runtime_record.original_sentence_text
			hit_resolution_target["source_id"] = runtime_record.source_id
			hit_resolution_target["is_repeat"] = runtime_record.is_repeat
			hit_resolution_target["tendency_id"] = runtime_record.tendency_id
		hit_resolution_target["is_valid_hit"] = trait_result.receives_normal_reward
		hit_resolution_target["tendency_delta"] = 0
		if trait_result.receives_normal_reward and runtime_record != null:
			var reward: Dictionary
			if runtime_record.is_repeat:
				reward = _hit_resolution.calculate_repeat_hit_result()
			else:
				reward = _hit_resolution.calculate_normal_word_reward(int(runtime_record.strength))
			for reward_key in reward:
				hit_resolution_target[reward_key] = reward[reward_key]
			if not runtime_record.is_repeat:
				normal_hit_records.append(
					{
						"original_sentence_id": runtime_record.original_sentence_id,
						"tendency": runtime_record.tendency_id,
					}
				)
		hit_resolution_targets.append(hit_resolution_target)

	var target_validity: Array[bool] = []
	for target_instance_id in snapshot.get_target_instance_ids():
		target_validity.append(valid_instance_ids.has(target_instance_id))
	var is_miss: bool = _hit_resolution.is_shot_fully_missed(target_validity)
	var shot_anomaly: HitResolution.ShotAnomaly = _hit_resolution.select_shot_anomaly(
		has_bounce,
		has_obstruction,
		is_miss
	)
	var hit_resolution_result: Dictionary = _hit_resolution.resolve_shot_results(hit_resolution_targets)
	if not bool(hit_resolution_result.get("cancelled_by_zero_pk", false)):
		for normal_hit_record: Dictionary in normal_hit_records:
			_hit_resolution.record_normal_word_hit(
				normal_hit_record["original_sentence_id"],
				normal_hit_record["tendency"]
			)

	shot_hit_resolution_submitted.emit(
		snapshot,
		{
			"target_validity": target_validity,
			"shot_anomaly": shot_anomaly,
			"hit_resolution_result": hit_resolution_result,
		}
	)


# 只从 BarrageArea 当前真实视图中筛选有效、可选、在区域内且与准心相交的弹幕。
func _capture_target_snapshot() -> AttackTargetSnapshot:
	var candidates: Array[Node] = []
	if _aim_reticle == null or _barrage_area == null:
		return AttackTargetSnapshot.capture_at_release(candidates)

	var current_time_msec: int = Time.get_ticks_msec()
	var area_rect: Rect2 = _barrage_area.get_global_rect()
	for child in _barrage_area.get_children():
		if not child is BarrageView:
			continue
		var barrage_view := child as BarrageView
		if not barrage_view.is_inside_tree() or barrage_view.is_queued_for_deletion():
			continue
		if barrage_view.runtime_record == null or barrage_view.runtime_record.trait_set == null:
			continue
		if not barrage_view.runtime_record.trait_set.is_selectable():
			continue
		if current_time_msec >= barrage_view.runtime_record.expires_at_msec:
			continue

		var target_rect: Rect2 = barrage_view.get_global_rect()
		var visible_target_rect: Rect2 = area_rect.intersection(target_rect)
		if visible_target_rect.size.x <= 0.0 or visible_target_rect.size.y <= 0.0:
			continue
		if _aim_reticle.intersects_target_area(visible_target_rect):
			candidates.append(barrage_view)

	return AttackTargetSnapshot.capture_at_release(candidates)


# 提供给后续攻击反馈和释放流程读取当前蓄力比例。
func get_charge_progress() -> float:
	return _charge_progress.get_progress() if _charge_progress != null else 0.0


# 提供给后续释放流程判断是否已经蓄满。
func is_fully_charged() -> bool:
	return _charge_progress != null and _charge_progress.is_fully_charged()


# 供 UI 和后续攻击流程读取当前阶段，不复制组件内部计时状态。
func get_attack_phase() -> AttackPhase:
	return _attack_phase


# 蓄力配置有效且未处于飞行或硬直时才能开始下一发。
func is_charge_held() -> bool:
	# 调试状态读取真实鼠标蓄力输入，不从进度或界面文字反推按住状态。
	return _attack_held


# 蓄力配置有效且未处于飞行或硬直时才能开始下一发。

func can_start_charging() -> bool:
	return _combat_active and not _new_attacks_locked and _charge_progress != null and _attack_phase == AttackPhase.READY and not get_tree().paused
