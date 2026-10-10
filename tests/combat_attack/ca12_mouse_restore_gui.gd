## TEST_ONLY GUI 探针：合成事件分发、实际帧和 Timer；Android 物理触摸另验。
extends Node

var aim: AimReticle
var attack: AttackChargeInput
var area: BarrageArea
var profile: LevelProfile
var hit: HitResolution
var shots: Array[AttackTargetSnapshot] = []
var submissions: Array[Dictionary] = []
var checks := 0
var failures := 0
var point := Vector2(727.2, 86.4)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(20.0, true).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run")

# 仅装配当前系统对象，避免准心按下回归依赖 Sandbox 私有实现。
func _run() -> void:
	area = preload("res://systems/barrage_generation/barrage_area.tscn").instantiate()
	add_child(area)
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(1100, 600)
	profile = LevelProfile.new()
	profile.streamer_id = "TEST_ONLY_CA12"
	profile.base_batch_count = 0
	profile.base_move_speed_pixels_per_second = 0
	profile.base_spawn_interval_seconds = 60
	profile.normal_barrage_screen_cap = 10
	area.start_normal_generation(profile)
	area.stop_normal_generation()
	aim = preload("res://systems/combat_attack/aim_reticle.tscn").instantiate()
	add_child(aim)
	attack = AttackChargeInput.new()
	add_child(attack)
	attack.configure_target_query(aim, area)
	attack.configure_attack_timing(preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres"))
	attack.shot_snapshot_created.connect(func(snapshot): shots.append(snapshot))
	attack.shot_hit_resolution_submitted.connect(func(_snapshot, submission): submissions.append(submission))
	await _wait(0.05)
	# 首次按下没有 MouseMotion，也没有按下后的补定位；输出系统读数作对照。
	_mouse(true, point)
	print("CA12 first press system_mouse=", aim.get_global_mouse_position(), " event=", point, " aim=", aim.get_aim_center_global_position())
	_check(aim.get_aim_center_global_position().distance_to(point) < 0.01, "first press uses event without motion")
	_mouse(false, point)
	# 非单位 Canvas 与父级缩放下，仍须按同一逆变换定位几何中心。
	get_viewport().canvas_transform = Transform2D(Vector2(0.8, 0), Vector2(0, 1.2), Vector2(20, 30))
	aim.scale = Vector2(1.3, 0.7)
	_mouse(true, point)
	_check(aim.get_aim_center_global_position().distance_to(get_viewport().canvas_transform.affine_inverse() * point) < 0.01, "screen to canvas and scaled center")
	_mouse(false, point)
	get_viewport().canvas_transform = Transform2D.IDENTITY
	aim.scale = Vector2.ONE
	_touch(true)
	_check(not attack.is_charge_held(), "missing mobile config disables touch")
	_touch(false)
	_check(not attack.configure_mobile_input(MobileAttackInputConfig.new()), "zero config rejected")
	_check(attack.configure_mobile_input(preload("res://tests/fixtures/combat_attack/ca12_test_only_mobile_input.tres")), "explicit TEST_ONLY config")
	_touch(true)
	_check(attack.is_charge_held(), "touch starts charge")
	_drag(point + Vector2(0, 30))
	_check(aim.get_aim_center_global_position().distance_to(point + Vector2(0, 30)) < 0.01 and aim.reticle_diameter == 80, "drag center and diameter")
	_check(attack.is_charge_held(), "drag preserves hold")
	_touch(true, 1, point + Vector2(100, 100))
	_check(aim.get_aim_center_global_position().distance_to(point + Vector2(0, 30)) < 0.01, "second finger isolated")
	_touch(false, 1)
	_touch(false)
	_check(shots.is_empty() and is_zero_approx(attack.get_charge_progress()), "undercharge cancels")
	hit = HitResolution.new(0.5, 0, 1)
	attack.configure_hit_resolution(hit)
	_touch(true)
	await _wait(0.25)
	_check(attack.is_fully_charged(), "touch fully charges")
	_mouse(false, point, InputEvent.DEVICE_ID_EMULATION)
	_check(attack.is_charge_held(), "emulated release ignored")
	_touch(false, 0, point + Vector2(0, 20))
	_check(shots.size() == 1 and shots[0].get_aim_center_global_position().distance_to(point + Vector2(0, 20)) < 0.01, "touch release freezes final center")
	_mouse(false, point, InputEvent.DEVICE_ID_EMULATION)
	_check(shots.size() == 1, "no duplicate shot")
	_touch(true)
	_check(not attack.is_charge_held(), "flight refuses touch")
	_touch(false)
	await _wait(0.3)
	_check(attack.can_start_charging(), "real timer recovery")
	_check(submissions.back().shot_anomaly == HitResolution.ShotAnomaly.MISS, "empty touch shot MISS")
	_check(is_equal_approx(hit.get_player_pk(), 0.49), "MISS penalty once")
	_check(hit.get_normal_hit_history().is_empty(), "MISS no normal history")
	_touch(true)
	await _wait(0.25)
	_touch(false, 0, point, true)
	_check(shots.size() == 1 and not attack.is_charge_held(), "OS cancelled full charge discarded")
	_touch(true)
	await _wait(0.05)
	get_tree().paused = true
	var progress := attack.get_charge_progress()
	await _wait(0.1)
	_check(is_equal_approx(progress, attack.get_charge_progress()), "pause freezes charge")
	_touch(false)
	get_tree().paused = false
	_check(shots.size() == 1 and not attack.is_charge_held(), "paused release cancels")
	_touch(true)
	attack.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not attack.is_charge_held(), "focus out cancels")
	_touch(true)
	attack.set_combat_active(false)
	attack.set_combat_active(true)
	_touch(false)
	_check(shots.size() == 1 and not attack.is_charge_held(), "restart rejects stale release")
	# 原生 Control 消费触屏首次按下，攻击只能接收 unhandled 事件。
	var ui := Control.new()
	ui.position = point - Vector2(50, 30)
	ui.size = Vector2(100, 60)
	ui.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.gui_input.connect(func(_event): ui.accept_event())
	add_child(ui)
	await _wait(0.05)
	_touch(true)
	_check(not attack.is_charge_held(), "GUI consumes touch")
	_touch(false)
	ui.queue_free()
	await _wait(0.05)
	_mouse(true, point)
	_check(aim.reticle_diameter == 144 and aim.get_aim_center_global_position().distance_to(point) < 0.01, "touch to mouse restores current PC size and event center without motion")
	_mouse(false, point)
	# 实际弹幕特性与 HR 结算；每发等待真实到达，绝不注入结果。
	for trait_id: StringName in [&"", &"reflect", &"occlusion"]:
		await _target_shot(trait_id)
		var anomaly: int = HitResolution.ShotAnomaly.NONE if trait_id == &"" else (HitResolution.ShotAnomaly.BOUNCE if trait_id == &"reflect" else HitResolution.ShotAnomaly.OBSTRUCTION)
		_check(submissions.back().shot_anomaly == anomaly, "touch anomaly " + String(trait_id))
		_check(is_equal_approx(hit.get_player_pk(), 0.5012 if trait_id == &"" else 0.49), "single PK settlement " + String(trait_id))
		_check(hit.get_normal_hit_history().size() == (1 if trait_id == &"" else 0), "history boundary " + String(trait_id))
	await _target_shot(&"", true)
	_check(submissions.back().hit_resolution_result.get("terminal_mode", false), "HR13 late arrival terminal mode")
	_check(hit.get_player_pk() == 0.5 and hit.get_normal_hit_history().is_empty(), "HR13 PK and history frozen")
	print("CA12 GUI RESULT checks=", checks, " shots=", shots.size(), " submissions=", submissions.size(), " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

# 每轮独立 HR，只替换内存测试数据；目标沿用真实区域生成和特性装配。
func _target_shot(trait_id: StringName, terminal := false) -> void:
	area.clear_current_barrages()
	hit = HitResolution.new(0.5, 0, 1)
	attack.configure_hit_resolution(hit)
	var speech := LevelSpeech.new()
	speech.original_sentence_id = "TEST_ONLY_CA12_normal"
	speech.text = "TEST_ONLY normal"
	speech.tendency_id = "orthodox"
	var view: BarrageView = area.spawn_normal_barrage(profile, speech)
	if trait_id != &"":
		view.runtime_record.trait_set.add_trait(trait_id)
	await _wait(0.03)
	var center := view.get_global_rect().get_center()
	_touch(true, 0, center)
	await _wait(0.25)
	_touch(false, 0, center)
	if terminal:
		hit.set_normal_pk_resolution_enabled(false)
	await _wait(0.3)

# 输入位置从 Viewport 转为物理窗口，交给引擎转换回事件坐标。
func _emit(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _mouse(pressed: bool, position: Vector2, device := 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = get_viewport().get_final_transform() * position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device
	_emit(event)

func _touch(pressed: bool, index := 0, position := Vector2(727.2, 86.4), canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = get_viewport().get_final_transform() * position
	event.index = index
	event.pressed = pressed
	event.canceled = canceled
	_emit(event)

func _drag(position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = get_viewport().get_final_transform() * position
	event.index = 0
	_emit(event)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CA12 FAIL " + label)
	else:
		print("CA12 PASS " + label)
