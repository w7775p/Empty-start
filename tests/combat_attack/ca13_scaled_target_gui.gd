extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const SCALE_CASES: Array[Dictionary] = [
	{"name": "reduced", "scale": 0.5},
	{"name": "normal", "scale": 1.0},
	{"name": "enlarged", "scale": 1.5},
]
const RETICLE_RADIUS: float = 72.0
const BG27_TEST_CYCLE_SECONDS: float = 6.0

var _sandbox: Control
var _barrage_area: BarrageArea
var _attack_input: AttackChargeInput
var _aim_reticle: AimReticle
var _targets: Array[BarrageView] = []
var _snapshots: Array[AttackTargetSnapshot] = []
var _check_count: int = 0
var _failures: Array[String] = []


func _ready() -> void:
	# 从独立验收场景启动真实 Sandbox 测试流程。
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run_acceptance")


# 用正式 Sandbox 和真实攻击释放，验证缩放视图边缘与目标快照相交一致。
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

	var timing := AttackTimingConfig.new()
	timing.charge_time_s = 0.005
	timing.projectile_flight_s = 10.0
	timing.recovery_time_s = 0.0
	_check(_attack_input.configure_attack_timing(timing), "正式攻击组件接受 CA-13 短蓄力配置")

	var level_catalog: LevelCatalog = _sandbox.get("level_catalog") as LevelCatalog
	var level: LevelProfile = _get_first_level(level_catalog)
	var speeches: Array[LevelSpeech] = level.get_normal_speech_pool() if level != null else []
	_check(level != null and not speeches.is_empty(), "正式关卡目录提供普通话语")
	if level == null or speeches.is_empty():
		await _finish()
		return

	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	await get_tree().process_frame

	# 将测试范围临时放大，用正式普通生成路径观察 BG-27 的实时缩放周期。
	_barrage_area.normal_foreground_min_scale = 0.5
	_barrage_area.normal_foreground_max_scale = 1.5
	_barrage_area.normal_foreground_scale_cycle_seconds = BG27_TEST_CYCLE_SECONDS
	# 测试保持话语停在区域中间，避免移动离场影响尺寸采样。
	_barrage_area.set_generation_multipliers(1.0, 1.0, 0.0)
	var view: BarrageView = _barrage_area.spawn_normal_barrage(level, speeches[0])
	_check(view != null, "动态缩放目标由正式普通生成入口创建")
	if view == null:
		await _finish()
		return
	view.runtime_record.expires_at_msec = Time.get_ticks_msec() + 60_000
	view.position = Vector2(
		(_barrage_area.size.x - view.size.x) * 0.5,
		(_barrage_area.size.y - view.size.y) * 0.5
	)
	_targets.append(view)
	await get_tree().process_frame

	var evidence_dir: String = ProjectSettings.globalize_path("res://docs/5. CombatAttack/evidence")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	for case_data: Dictionary in SCALE_CASES:
		var case_name: String = str(case_data["name"])
		var expected_scale: float = float(case_data["scale"])
		var reached_scale: bool = await _wait_for_scale(
			view, expected_scale, 0.02, BG27_TEST_CYCLE_SECONDS + 0.5
		)
		_check(reached_scale, "BG-27 实时缩放到达 %s 倍" % case_name)
		# 命中几何检查期间冻结刚观测到的倍率，避免蓄力帧改变边界。
		view.set_process(false)
		var actual_scale: float = view.scale.x
		var target_rect: Rect2 = view.get_global_rect()
		_check(absf(actual_scale - expected_scale) <= 0.02, "%s 读取到对应的实时动画倍率" % case_name)
		_check(_matches_transformed_control_rect(view, target_rect), "%s get_global_rect 对应当前四角变换" % case_name)
		var glass: BarrageSpecialSurface = view.get_glass_surface()
		_check(glass != null and _rects_match(glass.get_global_rect(), target_rect), "%s 可见玻璃区域与目标矩形一致" % case_name)
		print("CA13_BOUNDS name=%s live_scale=%.4f rect=%s" % [case_name, actual_scale, target_rect])

		# 准心圆边缘进入目标 1px；移出 4px 验证实际缩放边界。
		var edge_center: Vector2 = Vector2(target_rect.position.x - RETICLE_RADIUS + 1.0, target_rect.get_center().y)
		_send_mouse_motion(edge_center)
		await RenderingServer.frame_post_draw
		var screenshot_path: String = ProjectSettings.globalize_path(
			"res://docs/5. CombatAttack/evidence/CA-13_2026-10-12_%s.png" % case_name
		)
		var screenshot_error: Error = get_viewport().get_texture().get_image().save_png(screenshot_path)
		_check(screenshot_error == OK, "%s 缩放场景截图已保存" % case_name)
		print("CA13_SCREENSHOT=" + screenshot_path)

		var edge_snapshot: AttackTargetSnapshot = await _fire_at(edge_center)
		_check(
			_contains_only_id(edge_snapshot, view.get_instance_id()),
			"%s 可见边界内 1px 进入真实释放快照" % case_name
		)
		var outside_center: Vector2 = Vector2(target_rect.position.x - RETICLE_RADIUS - 4.0, target_rect.get_center().y)
		var outside_snapshot: AttackTargetSnapshot = await _fire_at(outside_center)
		_check(
			outside_snapshot != null and outside_snapshot.get_target_instance_ids().is_empty(),
			"%s 可见边界外 4px 不进入真实释放快照" % case_name
		)
		view.set_process(true)

	print("CA13 RESULT checks=%d targets=%d failures=%d" % [_check_count, _targets.size(), _failures.size()])
	for failure: String in _failures:
		push_error("CA13 FAIL: " + failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


# 选取正式关卡目录中顺序最靠前的配置。
func _get_first_level(catalog: LevelCatalog) -> LevelProfile:
	if catalog == null or catalog.profiles.is_empty():
		return null
	var selected: LevelProfile = catalog.profiles[0]
	for profile: LevelProfile in catalog.profiles:
		if profile.level_order < selected.level_order:
			selected = profile
	return selected


# 等待普通前景动画自然经过指定倍率，不直接修改视图的 scale。
func _wait_for_scale(view: BarrageView, target_scale: float, tolerance: float, timeout_seconds: float) -> bool:
	var deadline_msec: int = Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline_msec:
		if absf(view.scale.x - target_scale) <= tolerance:
			return true
		await get_tree().process_frame
	return absf(view.scale.x - target_scale) <= tolerance


# 等比缩放时 Control 的全局矩形应包住其当前变换后的四角。
func _matches_transformed_control_rect(control: Control, actual: Rect2) -> bool:
	var transform: Transform2D = control.get_global_transform()
	var corners: Array[Vector2] = [
		transform * Vector2.ZERO,
		transform * Vector2(control.size.x, 0.0),
		transform * control.size,
		transform * Vector2(0.0, control.size.y),
	]
	var minimum: Vector2 = corners[0]
	var maximum: Vector2 = corners[0]
	for corner: Vector2 in corners:
		minimum.x = minf(minimum.x, corner.x)
		minimum.y = minf(minimum.y, corner.y)
		maximum.x = maxf(maximum.x, corner.x)
		maximum.y = maxf(maximum.y, corner.y)
	return _rects_match(actual, Rect2(minimum, maximum - minimum))


# 比较两个矩形的画布坐标及尺寸，容忍亚像素绘制舍入。
func _rects_match(first: Rect2, second: Rect2) -> bool:
	return first.position.distance_to(second.position) <= 0.1 and first.size.distance_to(second.size) <= 0.1


# 通过真实鼠标事件完成一次蓄满释放并读取冻结快照。
func _fire_at(canvas_position: Vector2) -> AttackTargetSnapshot:
	var previous_snapshot_count: int = _snapshots.size()
	_attack_input.set_combat_active(false)
	_attack_input.set_combat_active(true)
	_send_mouse_motion(canvas_position)
	_send_mouse_button(true, canvas_position)
	for frame_index in range(6):
		if _attack_input.is_fully_charged():
			break
		await get_tree().process_frame
	var was_charged: bool = _attack_input.is_fully_charged()
	_send_mouse_button(false, canvas_position)
	await get_tree().process_frame
	_check(was_charged, "真实攻击组件完成短时蓄力")
	var snapshot: AttackTargetSnapshot
	if _snapshots.size() == previous_snapshot_count + 1:
		snapshot = _snapshots.back()
	_attack_input.set_combat_active(false)
	_attack_input.set_combat_active(true)
	return snapshot


# 画布目标先转换到窗口坐标，沿用项目已有输入管线。
func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * canvas_position)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 通过 Godot 鼠标事件分发正式攻击按下与释放。
func _send_mouse_button(pressed: bool, canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim_reticle.get_canvas_transform() * canvas_position)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 只把结构化任务检查记录到运行日志。
func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if not condition:
		_failures.append(description)
		push_error("CA13 CHECK FAILED: " + description)


# 退出时返回失败状态，便于 CLI 自动验收。
func _finish() -> void:
	print("CA13 RESULT checks=%d targets=%d failures=%d" % [_check_count, _targets.size(), _failures.size()])
	get_tree().quit(1)


# 释放信号保存当前一发原始目标快照。
func _on_snapshot_created(snapshot: AttackTargetSnapshot) -> void:
	_snapshots.append(snapshot)


# 目标 ID 必须独占快照，避免相邻尺寸的控制区误入本发。
func _contains_only_id(snapshot: AttackTargetSnapshot, expected_instance_id: int) -> bool:
	if snapshot == null:
		return false
	var ids: Array[int] = snapshot.get_target_instance_ids()
	return ids.size() == 1 and ids[0] == expected_instance_id
