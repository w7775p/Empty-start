extends SceneTree

const AREA_SCENE = preload("res://systems/barrage_generation/barrage_area.tscn")
const TIERS = preload("res://data/combat_stage/tier_catalog.tres")
const CATALOG = preload("res://data/test_only/generated/level_configuration/test_only_level_catalog.tres")
const BATTLE = preload("res://data/sandbox/playable_battle_config.tres")

var _notifications: int = 0
var _passed: bool = true


# 仅覆盖抽取引入的完成与中断边界；完整两路复用 INT-04。
func _init() -> void:
	_run.call_deferred()


# 空历史只通知一次；空态延迟回调与真实 Tween 中断均不能补发 Ending。
func _run() -> void:
	var area := AREA_SCENE.instantiate() as BarrageArea
	root.add_child(area)
	area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(1024, 1008)
	var attack := AttackChargeInput.new()
	root.add_child(attack)
	attack.set_combat_active(false)
	var catalog: LevelCatalog = CATALOG.duplicate(true)
	var profile: LevelProfile = catalog.profiles[0]
	profile.base_move_speed_pixels_per_second = 0.0
	var battle: SandboxBattleConfig = BATTLE.duplicate(true)
	battle.repeat_lifetime_seconds = 2.0
	var decay := DivineDescentDecayConfig.new()
	decay.new_word_decay_duration_seconds = 0.1
	var presentation := {"repeat_interval_seconds": 0.05, "fade_seconds": 0.1,
		"hold_seconds": 0.5, "input_scale": 1.35, "input_return_seconds": 0.2}
	var empty := DivineDescentFlow.new()
	root.add_child(empty)
	empty.completed.connect(func(_result): _notifications += 1)
	var data := SaveData.new()
	_check(empty.start(data, catalog, profile, TIERS, null, null, null, area, null,
		attack, battle, decay, presentation), "空历史启动失败")
	var session := empty.get_session()
	var frozen := session.get_entry_snapshot()
	data.streamer_name = "TEST_ONLY changed after freeze"
	await process_frame
	await process_frame
	_check(_notifications == 1 and empty.get_result().is_received(), "空历史完成次数错误")
	_check(empty.get_session() == session and session.get_entry_snapshot() == frozen,
		"会话或冻结结果改变")
	_check(empty.get_result().get_final_snapshot()["streamer_name"] == frozen["streamer_name"],
		"Ending 重读了源数据")
	_check(not empty.start(data, catalog, profile, TIERS, null, null, null, area, null,
		attack, battle, decay, presentation), "重复启动被接受")
	empty.stop()
	empty.queue_free()
	var cancelled := DivineDescentFlow.new()
	root.add_child(cancelled)
	cancelled.completed.connect(func(_result): _notifications += 1)
	_check(cancelled.start(SaveData.new(), catalog, profile, TIERS, null, null, null,
		area, null, attack, battle, decay, presentation), "中断空态启动失败")
	cancelled.stop()
	await process_frame
	_check(cancelled.get_result() == null and _notifications == 1, "中断空态仍完成")
	cancelled.queue_free()
	var interrupted := DivineDescentFlow.new()
	root.add_child(interrupted)
	interrupted.completed.connect(func(_result): _notifications += 1)
	data = SaveData.new()
	var speech: LevelSpeech = profile.get_normal_speech_pool()[0]
	data.committed_normal_hit_history = [{"original_sentence_id": speech.original_sentence_id,
		"original_sentence_text": speech.text, "tendency": "orthodox",
		"hit_count": 1, "first_committed_hit_order": 1}]
	_check(interrupted.start(data, catalog, profile, TIERS, null, null, null,
		area, null, attack, battle, decay, presentation), "非空启动失败")
	var spread := interrupted.get_spread()
	interrupted.advance(0.1)
	_check(spread.is_sentence_locked(), "实际衰减未锁句")
	_check(spread.generate_next_repeat() != null, "真实复读未生成")
	var deadline := Time.get_ticks_msec() + 5000
	while not spread.is_converging() and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(spread.is_converging() and not spread.is_completed(), "演出未进入真实收束")
	interrupted.stop()
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	_check(not interrupted.handle_input(key), "中断后接受输入")
	await create_timer(0.9).timeout
	_check(_notifications == 1 and interrupted.get_result() == null, "中断 Tween 仍交付 Ending")
	_check(not is_instance_valid(spread), "中断后扩散未销毁")
	interrupted.queue_free()
	area.queue_free()
	attack.queue_free()
	await process_frame
	print("PASS INT-07 flow completion/cancellation" if _passed else "FAIL INT-07 flow")
	quit(0 if _passed else 1)


# 每个断言同时记录失败信息与最终退出码。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_passed = false
		push_error("FAIL INT-07: " + message)
		quit(1)
