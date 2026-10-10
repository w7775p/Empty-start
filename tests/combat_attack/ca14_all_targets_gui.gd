extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SHORT_ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")
const TARGET_COUNT: int = 10

var _sandbox: Control
var _barrage_area: BarrageArea
var _attack_input: AttackChargeInput
var _aim_reticle: AimReticle
var _targets: Array[BarrageView] = []
var _snapshots: Array[AttackTargetSnapshot] = []
var _arrivals: Array[Dictionary] = []
var _submissions: Array[Dictionary] = []
var _mouse_canvas_position: Vector2 = Vector2.ZERO
var _check_count: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_acceptance")


# 用正式 Sandbox、正常话语生成入口与真实攻击 Timer 验收十目标同发快照。
func _run_acceptance() -> void:
	SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_sandbox)
	await get_tree().process_frame
	await get_tree().process_frame

	_barrage_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_attack_input = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_aim_reticle = _sandbox.get_node("%AimReticle") as AimReticle
	_attack_input.shot_snapshot_created.connect(_on_snapshot_created)
	_attack_input.shot_arrival_resolved.connect(_on_arrival_resolved)
	_attack_input.shot_hit_resolution_submitted.connect(_on_hit_resolution_submitted)
	_check(_attack_input.configure_attack_timing(SHORT_ATTACK_TIMING), "正式攻击组件接受现有 CA-07 短计时 fixture")

	var level_catalog: LevelCatalog = _sandbox.get("level_catalog") as LevelCatalog
	var profiles: Array[LevelProfile] = level_catalog.profiles if level_catalog != null else []
	if profiles.is_empty():
		_check(false, "正式关卡目录提供话语配置")
		await _finish()
		return
	var level: LevelProfile = profiles[0]
	for candidate: LevelProfile in profiles:
		if candidate.level_order < level.level_order:
			level = candidate
	var speeches: Array[LevelSpeech] = level.get_normal_speech_pool()
	_check(not speeches.is_empty(), "当前关卡提供正式话语定义")
	_check(level.normal_barrage_screen_cap >= TARGET_COUNT, "正式区域容量可容纳十条同发目标")
	if speeches.is_empty() or level.normal_barrage_screen_cap < TARGET_COUNT:
		await _finish()
		return
	print("CA14_CONTENT level_id=%s unique_speech_definitions=%d target_instances=%d" % [level.level_id, speeches.size(), TARGET_COUNT])

	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await get_tree().process_frame

	var target_center_global: Vector2 = _barrage_area.get_global_rect().get_center()
	var area_to_global: Transform2D = _barrage_area.get_global_transform()
	var target_center_local: Vector2 = area_to_global.affine_inverse() * target_center_global
	var expected_ids: Array[int] = []
	for index in range(TARGET_COUNT):
		# 当关卡词池条目少于十时复用正式定义，仍创建十个独立运行实例供快照按实例 ID 处理。
		var speech: LevelSpeech = speeches[index % speeches.size()]
		var view: BarrageView = _barrage_area.spawn_normal_barrage(level, speech)
		if view == null:
			_check(false, "正式生成入口创建第 %d 条话语" % (index + 1))
			await _finish()
			return
		# 纵向错开一像素，保留可见层次并让十个真实 Label 两两相交。
		var stagger_y: float = float(index) - float(TARGET_COUNT - 1) * 0.5
		view.position = target_center_local - view.size * 0.5 + Vector2(0.0, stagger_y)
		_targets.append(view)
		expected_ids.append(view.get_instance_id())
		_check(view.runtime_record.trait_set.is_selectable(), "第 %d 条正式话语可选" % (index + 1))

	await get_tree().process_frame
	var every_target_overlaps: bool = true
	var target_rects: Array[Rect2] = []
	for index in range(_targets.size()):
		var target_rect: Rect2 = _targets[index].get_global_rect()
		target_rects.append(target_rect)
		if not _aim_reticle.intersects_target_area(target_rect):
			every_target_overlaps = false
	for first_index in range(target_rects.size()):
		for second_index in range(first_index + 1, target_rects.size()):
			if not target_rects[first_index].intersects(target_rects[second_index]):
				every_target_overlaps = false
	_check(_targets.size() == TARGET_COUNT and every_target_overlaps, "十条真实话语视图相互重叠并逐条与准心相交")
	_check(_barrage_area.get_visible_barrage_records().size() == TARGET_COUNT, "区域公开查询能看到十条目标记录")

	# 保存正式 Sandbox 与十条重叠话语的真实 GUI 视口图，作为本次运行证据。
	await RenderingServer.frame_post_draw
	var screenshot_path: String = ProjectSettings.globalize_path("user://ca14_overlapped_targets.png")
	var screenshot_error: Error = get_viewport().get_texture().get_image().save_png(screenshot_path)
	_check(screenshot_error == OK, "保存十目标 GUI 运行截图")
	print("CA14_SCREENSHOT=" + screenshot_path)

	_mouse_canvas_position = target_center_global
	_send_mouse_motion(_mouse_canvas_position)
	_check(_aim_reticle.get_aim_center_global_position().distance_to(target_center_global) < 1.0, "合成鼠标事件将准心定位到十目标重叠处")
	_send_mouse_button(true)
	await _wait(0.24)
	_check(_attack_input.is_fully_charged(), "正式攻击组件实际完成蓄力")
	_send_mouse_button(false)
	await get_tree().process_frame

	_check(_snapshots.size() == 1, "一次合成鼠标释放只创建一份攻击快照")
	if _snapshots.size() != 1:
		await _finish()
		return
	var snapshot: AttackTargetSnapshot = _snapshots[0]
	var snapshot_ids: Array[int] = snapshot.get_target_instance_ids()
	_check(snapshot_ids.size() == TARGET_COUNT, "同一发快照冻结十个目标 ID")
	_check(snapshot_ids.size() == expected_ids.size() and _ids_match_once(snapshot_ids, expected_ids), "快照逐一包含十个真实目标且无重复 ID")

	# 飞行中移除一条、令一条先于到达过期，并将另一条移离准心但留在区域内。
	_check(_barrage_area.end_barrage(expected_ids[0]), "飞行中移除一个快照目标")
	_targets[1].runtime_record.expires_at_msec = Time.get_ticks_msec() + 20
	var moved_center_local: Vector2 = area_to_global.affine_inverse() * (target_center_global + Vector2(300.0, 0.0))
	_targets[2].position = moved_center_local - _targets[2].size * 0.5
	await _wait_for_arrival()

	_check(_arrivals.size() == 1, "真实飞行 Timer 触发一次到达复核")
	_check(_submissions.size() == 1, "复核结果提交至现有 HitResolution")
	if _arrivals.size() == 1:
		var arrived_ids: Array[int] = _ids_from_target_results(_arrivals[0]["target_results"])
		var expected_arrival_ids: Array[int] = expected_ids.slice(2, TARGET_COUNT)
		_check(arrived_ids.size() == TARGET_COUNT - 2 and _ids_match_once(arrived_ids, expected_arrival_ids), "到达保留移位目标，只排除已删除与已过期目标")
		_check(snapshot.get_target_instance_ids().size() == TARGET_COUNT, "飞行期间的生命周期变化未改写释放快照")
	if _submissions.size() == 1:
		var submission: Dictionary = _submissions[0]
		var target_validity: Array = submission.get("target_validity", [])
		var valid_count: int = 0
		var validity_matches: bool = target_validity.size() == TARGET_COUNT
		for index in range(mini(target_validity.size(), TARGET_COUNT)):
			var expected_valid: bool = index >= 2
			var actual_valid: bool = bool(target_validity[index])
			valid_count += 1 if actual_valid else 0
			if actual_valid != expected_valid:
				validity_matches = false
		_check(validity_matches and valid_count == TARGET_COUNT - 2, "HitResolution 收到十项目标有效性快照，其中八项仍有效")
		var settled_results: Array = submission.get("hit_resolution_result", {}).get("target_results", [])
		_check(settled_results.size() == TARGET_COUNT - 2, "HitResolution 只结算到达时仍有效的八条话语")

	print("CA14_INPUT source=Input.parse_input_event synthetic mouse events; physical mouse=NOT TESTED")
	await _finish()


# 把画布坐标转换到窗口坐标，再通过 Godot 输入管线发送鼠标移动。
func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * canvas_position)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 按下和释放走 Godot 鼠标事件分发及正式攻击输入组件。
func _send_mouse_button(pressed: bool) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * _mouse_canvas_position)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# 等待正式飞行 Timer 发出到达事实，超时后由后续断言报告缺失。
func _wait_for_arrival() -> void:
	var deadline_msec: int = Time.get_ticks_msec() + 1000
	while _arrivals.is_empty() and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame


# 验证实例 ID 集合完全相等，且每个目标在快照中仅出现一次。
func _ids_match_once(actual_ids: Array[int], expected_ids: Array[int]) -> bool:
	if actual_ids.size() != expected_ids.size():
		return false
	var actual_counts: Dictionary = {}
	for instance_id: int in actual_ids:
		actual_counts[instance_id] = int(actual_counts.get(instance_id, 0)) + 1
	for instance_id: int in expected_ids:
		if actual_counts.get(instance_id, 0) != 1:
			return false
	return true


# 从正式到达结果复制各目标的稳定运行实例 ID。
func _ids_from_target_results(target_results: Array) -> Array[int]:
	var instance_ids: Array[int] = []
	for target_result: Dictionary in target_results:
		instance_ids.append(int(target_result.get("target_instance_id", 0)))
	return instance_ids


func _on_snapshot_created(snapshot: AttackTargetSnapshot) -> void:
	_snapshots.append(snapshot)


func _on_arrival_resolved(snapshot: AttackTargetSnapshot, target_results: Array[Dictionary]) -> void:
	_arrivals.append({"snapshot": snapshot, "target_results": target_results.duplicate(true)})


func _on_hit_resolution_submitted(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_submissions.append(submission.duplicate(true))


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("CA14 OK: " + description)
	else:
		_failures.append(description)
		printerr("CA14 FAIL: " + description)


# 退出前恢复暂停状态并释放正式 Sandbox，避免留存运行节点。
func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("CA14 RESULT checks=%d targets=%d arrivals=%d failures=0" % [_check_count, TARGET_COUNT, _arrivals.size()])
		get_tree().quit(0)
	else:
		print("CA14 RESULT checks=%d targets=%d arrivals=%d failures=%d" % [_check_count, TARGET_COUNT, _arrivals.size(), _failures.size()])
		get_tree().quit(1)
