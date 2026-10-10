## TEST_ONLY 数据消费 smoke；调试 PK、矛盾结算和按钮信号均为合成推进。
## 验证场景实际生成与跨关换池；物理点击、蓄力与手感需要人工验收。
extends Node

const SCENE: PackedScene = preload("res://tests/fixtures/data_export/test_only_sandbox.tscn")

func _ready() -> void:
    get_tree().create_timer(15.0).timeout.connect(func(): _check(false, "数据消费 smoke 超时"))
    call_deferred("_execute")

# 复用正式 Sandbox 启动和 Rest 接线；攻击链交由 INT-04 验证。
func _execute() -> void:
    var sandbox: Control = SCENE.instantiate() as Control
    if not _check(sandbox != null and sandbox.level_catalog != null, "测试场景或目录加载失败"):
        return
    add_child(sandbox)
    await get_tree().process_frame
    await get_tree().process_frame
    if not _check_pool(sandbox, sandbox.level_catalog.profiles[0]):
        return
    sandbox.debug_set_player_pk(sandbox.battle_config.maximum_player_pk)
    await get_tree().process_frame
    await get_tree().process_frame
    var flow: ContradictionOracleFlow = sandbox.get_contradiction_oracle_flow()
    if not _check(flow.is_contradiction_active(), "PK 达标未启动矛盾"):
        return
    var system = flow.get_contradiction_system()
    var no_hits: Array[String] = []
    if not _check(system.register_launched_shot() and system.resolve_shot_hit_ids(no_hits), "矛盾未击破结算失败"):
        return
    await get_tree().process_frame
    if not _check(sandbox._rest_session != null and sandbox._rest_session.is_open(), "未击破没有打开 Rest"):
        return
    # 只验证信号接线，避免将合成信号描述为玩家物理点击。
    sandbox._rest_result_view._continue_button.pressed.emit()
    await get_tree().process_frame
    if not _check_pool(sandbox, sandbox.level_catalog.profiles[1]):
        return
    sandbox.queue_free()
    await get_tree().process_frame
    print("PASS TEST_ONLY data smoke: SceneTree generation, Rest signal -> second pool; physical input UNVERIFIED")
    get_tree().quit(0)

# 启动与切关后核对实际新弹幕均来自该关词库，禁止只检查目录注入。
func _check_pool(sandbox: Control, profile: LevelProfile) -> bool:
    var snapshot: Dictionary = sandbox.get_debug_snapshot()
    if not _check(snapshot.get("level", "") == "第%d关" % profile.level_order and snapshot.get("normal_generation_enabled", false), "当前关卡或普通生成状态错误"):
        return false
    var ids: Array[String] = []
    for speech: LevelSpeech in profile.get_normal_speech_pool():
        ids.append(speech.original_sentence_id)
    var count: int = 0
    for child: Node in sandbox._barrage_area.get_children():
        if child is BarrageView and child.runtime_record != null and not child.runtime_record.is_repeat:
            if not _check(ids.has(child.runtime_record.original_sentence_id), "新批次使用了其他关卡词库"):
                return false
            count += 1
    return _check(count > 0, "关卡没有实际生成普通弹幕")

func _check(condition: bool, reason: String) -> bool:
    if not condition:
        push_error("FAIL TEST_ONLY data smoke: " + reason)
        get_tree().quit(1)
    return condition
