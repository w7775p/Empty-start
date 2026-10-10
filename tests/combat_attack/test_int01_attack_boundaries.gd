extends SceneTree

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const AIM_RETICLE_SCENE: PackedScene = preload("res://systems/combat_attack/aim_reticle.tscn")
const ATTACK_TIMING: AttackTimingConfig = preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres")

var _failures: Array[String] = []
var _submission: Dictionary = {}
var _generated_count: int = 0


## 使用真实场上实例与攻击 Timer，验证同步停止及同帧清场容量。
func _init() -> void:
	call_deferred("_run_boundaries")


## 复用已有计时 fixture，复读零收益由 INT-01 整合入口负责。
func _run_boundaries() -> void:
	var profile: LevelProfile = LevelProfile.new()
	profile.streamer_id = "int01_source"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 0.0
	profile.normal_barrage_screen_cap = 1
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.add_child(area)
	area.size = Vector2(1024.0, 800.0)
	area.repeat_barrage_screen_cap = 1
	area.start_normal_generation(profile)
	area.barrage_generated.connect(_on_generated)
	var aim: AimReticle = AIM_RETICLE_SCENE.instantiate() as AimReticle
	root.add_child(aim)
	var attack: AttackChargeInput = AttackChargeInput.new()
	root.add_child(attack)
	attack.configure_attack_timing(ATTACK_TIMING)
	attack.configure_target_query(aim, area)
	attack.shot_hit_resolution_submitted.connect(_on_submitted)
	await process_frame

	var plan: RepeatPlan = RepeatPlan.new()
	plan.original_line_id = &"int01_repeat"
	plan.original_line_text = "边界原句"
	plan.display_text = "复读：边界原句"
	plan.lifetime_seconds = 3.0
	var repeat_view: BarrageView
	var resolution: HitResolution

	# PK 满值信号同步停止攻击，结算事实仍保留，停止后的硬直不得重新启动。
	area.start_normal_generation(profile)
	var speech: LevelSpeech = LevelSpeech.new()
	speech.original_sentence_id = "int01_normal"
	speech.text = "普通边界原句"
	speech.tendency_id = "orthodox"
	var normal_view: BarrageView = area.spawn_normal_barrage(profile, speech)
	resolution = HitResolution.new(0.9994, 0.0, 1.0)
	attack.configure_hit_resolution(resolution)
	resolution.final_player_pk_updated.connect(func(_pk: float) -> void: attack.set_combat_active(false))
	await _fire_at(attack, aim, normal_view)
	_check(is_equal_approx(resolution.get_player_pk(), 1.0), "普通收益应将 PK 限制在满值")
	_check(attack.get_attack_phase() == AttackChargeInput.AttackPhase.READY, "同步停止后应保持 READY")
	_check(not attack.can_start_charging(), "停止战斗后应拒绝新的攻击")
	_check(is_zero_approx(attack.get_charge_progress()), "停止战斗后应清空蓄力")
	_check(resolution.get_normal_hit_history().size() == 1, "已结算普通命中仍应进入历史")
	var normal_results: Array = _submission.get("hit_resolution_result", {}).get("target_results", [])
	_check(normal_results.size() == 1, "停止回调后仍应发出本发结算事实")
	attack.set_combat_active(true)
	_check(attack.can_start_charging(), "重开攻击入口后应可以蓄力")

	# 清场立即释放两套容量，下一局可以在同一帧生成普通话语和复读。
	area.clear_barrages()
	area.start_normal_generation(profile)
	normal_view = area.spawn_normal_barrage(profile, speech)
	repeat_view = area.spawn_repeat_barrage(plan)
	_check(normal_view != null and repeat_view != null, "首次普通与复读应同时生成")
	var generated_before_clear: int = _generated_count
	area.clear_barrages()
	area.start_normal_generation(profile)
	var restarted_normal: BarrageView = area.spawn_normal_barrage(profile, speech)
	var restarted_repeat: BarrageView = area.spawn_repeat_barrage(plan)
	_check(restarted_normal != null and restarted_repeat != null, "清场后同帧应释放普通与复读容量")
	_check(_generated_count == generated_before_clear + 2, "成功生成事实每条应只发送一次")
	var ended_instance_id: int = restarted_normal.get_instance_id()
	_check(area.end_barrage(ended_instance_id), "公开入口应结束所属目标")
	_check(not area.end_barrage(ended_instance_id), "重复结束应返回 false")
	restarted_repeat.queue_free()
	area.clear_barrages()
	area.start_normal_generation(profile)
	_check(area.spawn_repeat_barrage(plan) != null, "已排队自然结束的视图也应在清场时立即释放容量")

	area.clear_barrages()
	attack.set_combat_active(false)
	attack.queue_free()
	aim.queue_free()
	area.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS INT-01 attack boundaries: synchronous stop, clear capacity, generated fact")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("FAIL INT-01 attack boundary: " + failure)
		quit(1)


## 合成鼠标按钮使用目标的窗口坐标，首按后不直接移动准心。
func _fire_at(_attack: AttackChargeInput, aim: AimReticle, view: BarrageView) -> void:
	_submission = {}
	# 新 Label 的最小尺寸在布局帧确定，随后再计算目标中心。
	await process_frame
	var point: Vector2 = root.get_final_transform() * (aim.get_canvas_transform() * view.get_global_rect().get_center())
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		if pressed:
			await create_timer(0.25).timeout
	await create_timer(0.13).timeout


## 保留公开提交事实，断言不读取攻击组件的私有业务状态。
func _on_submitted(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_submission = submission


## 计数实际成功生成，验证通知时节点已完成入树。
func _on_generated(view: BarrageView) -> void:
	_check(view.is_inside_tree(), "成功生成通知时节点应已经入树")
	_generated_count += 1


## 汇总失败信息，让场景清理和其他独立边界仍能执行完。
func _check(condition: bool, failure: String) -> void:
	if not condition:
		_failures.append(failure)
