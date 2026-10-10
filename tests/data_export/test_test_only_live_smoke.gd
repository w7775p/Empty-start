## 测试场景实际进入 SceneTree，执行 _ready、生成、蓄力发射与跨关重启。
## 真实经 Rest Continue 进入下一关，覆盖 RS-09 的完整信号链。
extends Node

const SCENE: PackedScene = preload("res://tests/fixtures/data_export/test_only_sandbox.tscn")
var _errors: Array[String] = []

func _ready() -> void:
    call_deferred("_execute")


func _execute() -> void:
    # 添加到 SceneTree 会真实运行所有 _ready()、Timer、Autoload 绑定。
    var sandbox: Control = SCENE.instantiate() as Control
    if sandbox == null:
        _fail("无法实例化 TEST_ONLY Sandbox")
        return
    add_child(sandbox)
    await get_tree().process_frame
    await get_tree().process_frame
    if not _check(sandbox.is_inside_tree(), "场景未进入 SceneTree"):
        return
    if not _check(sandbox._normal_combat_active, "Sandbox._ready 未正常启动普通战斗"):
        return
    if not _check(sandbox._run_state.get_current_level_profile().level_id == "test_level_01", "首关不是 test_level_01"):
        return
    if not _check(sandbox._barrage_area.is_normal_generation_enabled(), "普通弹幕生成没有启动"):
        return
    var counts: Dictionary = sandbox._barrage_area.get_current_barrage_counts()
    if int(counts.get("normal", 0)) <= 0:
        sandbox.debug_spawn_normal_batch()
    await get_tree().process_frame
    var target: BarrageView
    for child: Node in sandbox._barrage_area.get_children():
        if child is BarrageView and child.runtime_record != null and not child.runtime_record.is_repeat:
            target = child as BarrageView
            break
    if not _check(target != null, "真实战斗中没有生成普通弹幕"):
        return
    var target_id: String = target.runtime_record.original_sentence_id
    if not _check(target_id.begins_with("test_word_"), "没有读取 TEST_ONLY 弹幕 ID"):
        return
    # 用正式 AttackChargeInput 蓄力和射击过程验证真正的命中结算入口。
    var attack: AttackChargeInput = sandbox._attack_charge_input
    var cursor: AimReticle = sandbox._aim_reticle
    cursor._set_aim_center_global_position(target.get_global_rect().get_center())
    var previous_pk: float = sandbox._hit_resolution.get_player_pk()
    var pressed: InputEventMouseButton = InputEventMouseButton.new()
    pressed.button_index = MOUSE_BUTTON_LEFT
    pressed.pressed = true
    # 直接调用组件输入入口时仍需提供 Viewport 坐标，CA-12 按下会读取本次事件位置。
    pressed.position = cursor.get_canvas_transform() * target.get_global_rect().get_center()
    attack._input(pressed)
    attack._charge_progress.advance(attack._attack_timing.charge_time_s + 0.02, true)
    if not _check(attack.is_fully_charged(), "未能真实完成蓄力"):
        return
    var released: InputEventMouseButton = InputEventMouseButton.new()
    released.button_index = MOUSE_BUTTON_LEFT
    released.pressed = false
    released.position = pressed.position
    attack._input(released)
    # 飞行到达由现有 Timer、HitResolution 与 Sandbox 信号处理。
    var flight_s: float = attack._attack_timing.projectile_flight_s
    await get_tree().create_timer(maxf(flight_s + 0.12, 0.25)).timeout
    if not _check(sandbox._hit_resolution.get_player_pk() > previous_pk, "发射后未产生真实 PK 命中收益"):
        return
    if not _check(sandbox._hit_resolution.get_normal_hit_history().size() > 0, "没有产生真实的普通命中历史"):
        return
    if not _check(sandbox._hit_resolution.get_normal_hit_history()[0].get("original_sentence_id", "") == target_id, "命中原句 ID 不正确"):
        return

    # Exercise the actual PK completion, unbroken Rest and Continue button signal.
    # The test already confirmed a real normal hit above; now use the existing PK debug API.
    sandbox.debug_set_player_pk(sandbox.battle_config.maximum_player_pk)
    await get_tree().process_frame
    await get_tree().process_frame
    var phase_flow: ContradictionOracleFlow = sandbox.get_contradiction_oracle_flow()
    if not _check(phase_flow.get_contradiction_system() != null and phase_flow.is_contradiction_active(), "PK win did not enter contradiction stage"):
        return
    # Consume the one official CB shot without a true contradiction hit.
    if not _check(phase_flow.get_contradiction_system().register_launched_shot(), "Contradiction shot was rejected"):
        return
    var no_hits: Array[String] = []
    if not _check(phase_flow.get_contradiction_system().resolve_shot_hit_ids(no_hits), "Contradiction miss was rejected"):
        return
    await get_tree().process_frame
    if not _check(sandbox._rest_session != null and sandbox._rest_session.is_open(), "Unbroken outcome did not open Rest"):
        return
    if not _check(sandbox._rest_result_view._overlay.visible, "Rest view did not show the result"):
        return
    # Press the actual Rest button; this must reach RestSession and Sandbox RS-09 routing.
    sandbox._rest_result_view._continue_button.pressed.emit()
    await get_tree().process_frame
    if not _check(sandbox._run_state.get_current_level_profile().level_id == "test_level_02", "Rest Continue failed to enter second level"):
        return
    if not _check(sandbox._normal_combat_active, "Second-level normal combat did not start"):
        return
    if not _check(sandbox._barrage_area.is_normal_generation_enabled(), "Second-level normal barrage generation did not start"):
        return
    # Repeating the same UI action cannot complete the next level.
    sandbox._rest_result_view._continue_button.pressed.emit()
    await get_tree().process_frame
    if not _check(sandbox._run_state.get_current_level_profile().level_id == "test_level_02", "Repeated Continue advanced a second time"):
        return
    print("PASS TEST_ONLY live smoke: SceneTree _ready, spawned ", target_id,
          ", charged attack, PK/hit history, Rest Continue -> level 2.")
    sandbox.queue_free()
    await get_tree().process_frame
    get_tree().quit(0)


func _check(condition: bool, reason: String) -> bool:
    if condition:
        return true
    _fail(reason)
    return false


func _fail(reason: String) -> void:
    push_error("FAIL TEST_ONLY live smoke: " + reason)
    get_tree().quit(1)
