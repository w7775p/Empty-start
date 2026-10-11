class_name AttackChargeInput
extends Node

signal shot_snapshot_created(snapshot: AttackTargetSnapshot)
signal shot_arrival_resolved(snapshot: AttackTargetSnapshot, target_results: Array[Dictionary])
signal shot_hit_resolution_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary)
signal selection_target_hit(target: Control)

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
var _selection_mode_active: bool = false
var _selection_targets: Array[Control] = []
var _new_attacks_locked: bool = false
var _mobile_input_config: MobileAttackInputConfig
var _touch_index: int = -1


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
	# 暂停期间仍接收抬起以清理按住状态，蓄力本身由下方显式跳过。
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


# 场景注入移动端数值表；缺正式数值时只能显式注入 TEST_ONLY fixture。
func configure_mobile_input(config: MobileAttackInputConfig) -> bool:
	if config == null or not is_finite(config.touch_reticle_diameter) or config.touch_reticle_diameter <= 0.0:
		return false
	if _attack_held or _attack_phase != AttackPhase.READY:
		return false
	_mobile_input_config = config
	return true


# 注入临时可选目标；命中只发选择事实，不进入 HitResolution。
func set_selection_targets(targets: Array[Control]) -> bool:
	_selection_targets.clear()
	for target: Control in targets:
		if target == null or not is_instance_valid(target):
			continue
		_selection_targets.append(target)
	_selection_mode_active = not _selection_targets.is_empty()
	return _selection_mode_active


# 选择结束后移除目标来源，恢复普通攻击的弹幕查询路径。
func clear_selection_targets() -> void:
	_selection_targets.clear()
	_selection_mode_active = false


# 矛盾阶段在释放时交付快照；飞行不再复核目标或提交普通收益。
func set_contradiction_mode(active: bool) -> void:
	_contradiction_mode = active
	if not active:
		_new_attacks_locked = false


# 结果在释放时已固定；只封锁下一发，保留当前飞行计时作为演出。
func lock_new_attacks() -> void:
	_cancel_touch_charge()
	_new_attacks_locked = true
	_attack_held = false

## 战斗生命周期由场景协调；停止时本组件取消整发和计时，重开可直接回到 READY。
func set_combat_active(active: bool) -> void:
	_combat_active = active
	if active:
		return
	_cancel_touch_charge()
	_attack_held = false
	_active_snapshot = null
	_attack_phase = AttackPhase.READY
	if _phase_timer != null:
		_phase_timer.stop()
	if _attack_timing != null:
		_charge_progress = AttackChargeProgress.new(_attack_timing.charge_time_s)


# 在松开输入事件上冻结当前候选，之后进入准心的弹幕不加入本发。
func _input(event: InputEvent) -> void:
	# 已接管的手指在 UI 上方松开也必须清理；其他手指留给 UI。
	if _touch_index >= 0:
		if event is InputEventScreenDrag and event.index == _touch_index:
			if not get_tree().paused:
				_aim_reticle.move_touch_aim(event.position, _mobile_input_config.touch_reticle_diameter)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventScreenTouch and event.index == _touch_index and (not event.pressed or event.canceled):
			if event.canceled or get_tree().paused:
				_cancel_touch_charge()
			else:
				_aim_reticle.move_touch_aim(event.position, _mobile_input_config.touch_reticle_diameter)
				_touch_index = -1
				_attack_held = false
				_handle_attack_release()
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			return
	if not _combat_active or _new_attacks_locked or not event is InputEventMouseButton:
		return
	# Godot 默认会把触屏模拟成鼠标；攻击只处理原始触屏，防止重复发射。
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		if not get_tree().paused and can_start_charging():
			if _aim_reticle != null:
				_aim_reticle.restore_mouse_aim(mouse_event.position)
			_attack_held = true
		return

	var was_attack_held: bool = _attack_held
	_attack_held = false
	if was_attack_held and not get_tree().paused:
		_handle_attack_release()


# 只接管 UI 未消费的首次按下，避免暂停按钮或结果页触摸同时开始攻击。
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventScreenTouch or not event.pressed or event.canceled:
		return
	if _touch_index >= 0 or _attack_held or _mobile_input_config == null or _aim_reticle == null:
		return
	if not can_start_charging():
		return
	_touch_index = event.index
	_aim_reticle.move_touch_aim(event.position, _mobile_input_config.touch_reticle_diameter)
	_attack_held = true
	get_viewport().set_input_as_handled()


# 系统取消、后台切换和停止战斗丢弃触屏蓄力，满蓄也不能意外发射。
func _cancel_touch_charge() -> void:
	if _touch_index < 0:
		return
	_touch_index = -1
	_attack_held = false
	if _attack_timing != null:
		_charge_progress = AttackChargeProgress.new(_attack_timing.charge_time_s)


# Android 进入后台时抬指事件可能丢失，返回前清理当前手势。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_cancel_touch_charge()


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
		if _selection_mode_active:
			_resolve_selection_target_hit(completed_snapshot)
		elif not _contradiction_mode:
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


# 同发覆盖多条候选时只命中快照准心中心最近的一条；等距时保留展示顺序。
func _resolve_selection_target_hit(snapshot: AttackTargetSnapshot) -> void:
	if snapshot == null:
		return
	var present_targets: Array[Control] = snapshot.resolve_present_selection_targets(_selection_targets)
	var selected_target: Control
	var closest_distance_squared: float = INF
	var aim_center: Vector2 = snapshot.get_aim_center_global_position()
	for target: Control in present_targets:
		var target_center: Vector2 = target.get_global_rect().get_center()
		var distance_squared: float = target_center.distance_squared_to(aim_center)
		if distance_squared < closest_distance_squared:
			selected_target = target
			closest_distance_squared = distance_squared
	if selected_target != null:
		selection_target_hit.emit(selected_target)


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
	var has_release_snapshot_occlusion: bool = not snapshot.get_occlusion_target_instance_ids().is_empty()

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
				reward = _hit_resolution.calculate_normal_word_reward(int(runtime_record.strength), runtime_record.tendency_id)
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
		is_miss,
		has_release_snapshot_occlusion
	)
	if has_release_snapshot_occlusion:
		# 整发遮挡只提交普通 MISS；清空逐目标结果可保留重叠实例及所有正负命中副作用。
		hit_resolution_targets.clear()
		normal_hit_records.clear()
	# 只传递已选异常，惩罚数值与整发 PK 更新继续由 6 统一处理。
	var hit_resolution_result: Dictionary = _hit_resolution.resolve_shot_results(hit_resolution_targets, shot_anomaly)
	# 只记录实际完成普通结算的整发；打满 PK 的这一发仍保留，阶段关闭后的旧提交丢弃。
	if not bool(hit_resolution_result.get("cancelled_by_zero_pk", false)) and not bool(hit_resolution_result.get("terminal_mode", false)):
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


# 扫描真实可见弹幕并检查准心相交，再逐个调用 BT-02 排除不可选目标。
func _capture_target_snapshot() -> AttackTargetSnapshot:
	var candidates: Array[Node] = []
	var aim_center: Vector2 = _aim_reticle.get_aim_center_global_position() if _aim_reticle != null else Vector2.ZERO
	if _selection_mode_active:
		if _aim_reticle == null:
			return AttackTargetSnapshot.capture_at_release(candidates, aim_center)
		for target: Control in _selection_targets:
			if target == null or not is_instance_valid(target):
				continue
			if not target.is_inside_tree() or target.is_queued_for_deletion() or not target.is_visible_in_tree():
				continue
			if _aim_reticle.intersects_target_area(target.get_global_rect()):
				candidates.append(target)
		return AttackTargetSnapshot.capture_at_release(candidates, aim_center)
	if _aim_reticle == null or _barrage_area == null:
		return AttackTargetSnapshot.capture_at_release(candidates, aim_center)

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
		if current_time_msec >= barrage_view.runtime_record.expires_at_msec:
			continue

		var target_rect: Rect2 = barrage_view.get_global_rect()
		var visible_target_rect: Rect2 = area_rect.intersection(target_rect)
		if visible_target_rect.size.x <= 0.0 or visible_target_rect.size.y <= 0.0:
			continue
		if not _aim_reticle.intersects_target_area(visible_target_rect):
			continue
		# 可选规则归特性组件；全部被排除时保留空快照，由原有结算链判断落空。
		if not barrage_view.runtime_record.trait_set.is_selectable():
			continue
		candidates.append(barrage_view)

	return AttackTargetSnapshot.capture_at_release(candidates, aim_center)


# 提供给后续攻击反馈和释放流程读取当前蓄力比例。
func get_charge_progress() -> float:
	return _charge_progress.get_progress() if _charge_progress != null else 0.0


# 提供给后续释放流程判断是否已经蓄满。
func is_fully_charged() -> bool:
	return _charge_progress != null and _charge_progress.is_fully_charged()


# 供 UI 和后续攻击流程读取当前阶段，不复制组件内部计时状态。
func get_attack_phase() -> AttackPhase:
	return _attack_phase


func is_charge_held() -> bool:
	# 调试状态读取真实蓄力输入，不从进度或界面文字反推按住状态。
	return _attack_held


# 蓄力配置有效且未处于飞行或硬直时才能开始下一发。
func can_start_charging() -> bool:
	return _combat_active and not _new_attacks_locked and _charge_progress != null and _attack_phase == AttackPhase.READY and not get_tree().paused
