extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const BUBBLE_DIALOGUE_CONFIG: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
const PRESENTATION_ASSETS: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const OPPONENT_IDLE: Texture2D = preload("res://assets/characters/opponents/alien/alien_idle.png")
const EVIDENCE_DIRECTORY: String = "res://docs/8. CombatStage/evidence/cs22_2026-10-11"
const EVENT_COMBAT_CONNECTED: StringName = &"combat_connected"
const EVENT_TIER1_TAUNT: StringName = &"combat_tier1_taunt"
const FIRST_OPENING_LINE: String = "TEST_ONLY 连线开场第一句"
const SECOND_OPENING_LINE: String = "TEST_ONLY 连线开场第二句"

const TIER1_TAUNT_LINE: String = "TEST_ONLY T2 降档嘲讽"

var _sandbox: Control
var _battle_flow: BattleAttemptFlow
var _battle_hud: Control
var _barrage_area: BarrageArea
var _attack_input: AttackChargeInput
var _aim_reticle: AimReticle
var _battle_area: Control
var _opponent_stack: StreamerBubbleStack
var _opponent_portrait: TextureRect
var _completed_events: Array[Dictionary] = []
var _pk_at_dialogue_completion: float = -1.0
var _checks: int = 0
var _failures: int = 0


# 用正式 Sandbox 和临时对白配置验收 T1 连线开场及给 CS-23 的完播通知。
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().borderless = true
		get_window().min_size = Vector2i(1280, 720)
		get_window().size = Vector2i(1280, 720)
	get_tree().create_timer(15.0).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	SaveManager.new_game()
	var test_config: BubbleDialogueConfig = BUBBLE_DIALOGUE_CONFIG.duplicate(true) as BubbleDialogueConfig
	test_config.entries.clear()
	_append_opening_line(test_config, FIRST_OPENING_LINE, 0.55)
	_append_opening_line(test_config, SECOND_OPENING_LINE, 0.55)
	_append_test_event(test_config, EVENT_TIER1_TAUNT, TIER1_TAUNT_LINE, 0.55)

	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set("bubble_dialogue_config", test_config)
	add_child(_sandbox)
	await _wait_frames(2)
	_battle_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	_battle_hud = _sandbox.get_node_or_null("BattleHud") as Control
	if _battle_hud != null:
		_battle_area = _battle_hud.get_node_or_null("BattleArea") as Control
	if _battle_flow != null:
		_barrage_area = _battle_flow.get_barrage_area()
		_attack_input = _battle_flow.get_attack_input()
		_aim_reticle = _battle_flow.get_aim_reticle()
	if _battle_flow != null and _battle_hud != null:
		_opponent_stack = _battle_hud.get_node_or_null("%OpponentBubbleStack") as StreamerBubbleStack
		_opponent_portrait = _battle_hud.find_child("OpponentPortraitArt", true, false) as TextureRect
	if (_battle_flow == null or _battle_hud == null or _barrage_area == null or _attack_input == null
			or _aim_reticle == null or _battle_area == null or _opponent_stack == null or _opponent_portrait == null):
		_check(false, "正式 Sandbox 提供战斗输入、弹幕区、对手立绘和 SD-03 气泡栈")
		await _finish()
		return
	_sandbox.connect("dialogue_event_sequence_completed", Callable(self, "_on_event_sequence_completed"))
	var current_level: LevelProfile = _battle_flow.get_current_level_profile()
	if current_level == null:
		_check(false, "正式 Sandbox 提供当前关卡配置")
		await _finish()
		return

	# 正式关卡尚未填写主播立绘映射；通过 HUD 入口注入仓库现有素材，只用于验收。
	_battle_hud.call(
		"configure_streamer_assets",
		PRESENTATION_ASSETS.player_streamer_portrait,
		PRESENTATION_ASSETS.player_live_background,
		PRESENTATION_ASSETS.player_fan_badge,
		OPPONENT_IDLE,
		current_level.streamer_live_background,
		current_level.fan_badge_texture
	)
	_check(_battle_flow.get_current_tier() == 0, "新尝试从 T0 开始")
	_check(not _opponent_portrait.is_visible_in_tree(), "T0 匹配期间对手立绘隐藏")
	_check(_completed_events.is_empty(), "T0 未提前通知连线开场完成")

	# 正式攻击升档后先暂停生成和回拉，再经过突破提示进入 T1 开场对白。
	_check(await _fire_real_tier1_attack(current_level), "正式攻击升档进入 T1")
	_check(_battle_flow.get_current_tier() == 1, "真实 CombatStage 从 T0 进入 T1")
	_check(await _wait_for_text(FIRST_OPENING_LINE, 4.0), "突破提示结束后 SD-06 启动对手开场第一句")
	_check(_opponent_portrait.is_visible_in_tree(), "连线开场对白启动前已显示对手待机立绘")
	_check(_completed_events.is_empty(), "开场对白播放期间尚未发送序列完成通知")
	_check(not _barrage_area.is_normal_generation_enabled(), "T1 开场对白期间普通话语生成保持暂停")
	var pk_during_dialogue: float = _battle_flow.get_hit_resolution().get_player_pk()
	await _wait(0.12)
	_check(is_equal_approx(_battle_flow.get_hit_resolution().get_player_pk(), pk_during_dialogue),
		"T1 开场对白期间 OpponentPKBar 回拉保持暂停")
	await _capture_evidence()

	_check(await _wait_for_text(SECOND_OPENING_LINE, 3.0), "第一句结束后播放配置中的第二句")
	_check(not _bubble_texts().has(FIRST_OPENING_LINE), "两句开场对白按顺序逐句播放")
	_check(_completed_events.is_empty(), "第二句播放期间仍未通知 CS-23 恢复战斗")
	_check(await _wait_for_completed_event(4.0), "最后一句实际结束后 Sandbox 转发序列完成通知")
	_check(_completed_events.size() == 1, "连线开场只发送一次完成通知")
	if _completed_events.size() == 1:
		var completed_event: Dictionary = _completed_events[0]
		_check(completed_event.get("event_id") == EVENT_COMBAT_CONNECTED, "完成通知带有稳定事件 ID combat_connected")
		_check(not String(completed_event.get("sequence_id", &"")).is_empty(), "完成通知带有 SD-03 序列 ID")
		_check(int(completed_event.get("side", -1)) == BubbleDialogueEntry.SpeakerSide.OPPONENT, "完成通知标记对手发言侧")
	_check(_barrage_area.is_normal_generation_enabled(), "T1 开场对白完播后恢复普通话语生成")
	var barrage_counts: Dictionary = _barrage_area.get_current_barrage_counts()
	_check(int(barrage_counts.get("normal", 0)) > 0, "对白完播后重新出现新档前景话语")
	var pk_at_completion: float = _pk_at_dialogue_completion
	await _wait(0.35)
	_check(pk_at_completion >= 0.0 and _battle_flow.get_hit_resolution().get_player_pk() < pk_at_completion,
		"T1 开场对白完播后按当前 Tier 恢复 PK 回拉")
	await _verify_tier1_taunt(0.65, 2, "T2→T1")
	await _verify_tier1_taunt(0.72, 3, "跨档 T3→T1")
	await _finish()


# 用正式蓄力 / 飞行链命中普通话语，跨过 T0 升档阈值触发 CS-15 过渡。
func _fire_real_tier1_attack(level: LevelProfile) -> bool:
	var speech: LevelSpeech = _strongest_normal_speech(level)
	if speech == null:
		return false
	_barrage_area.stop_normal_generation()
	_barrage_area.clear_barrages()
	_barrage_area.set_generation_multipliers(1.0, 0.0, 0.0)
	if not _barrage_area.resume_normal_generation():
		return false
	_sandbox.call("debug_set_player_pk", 0.559)
	var target: BarrageView = _barrage_area.spawn_normal_barrage(level, speech, [], true)
	if target == null:
		return false
	await get_tree().process_frame
	var center_global: Vector2 = _barrage_area.get_global_rect().get_center()
	var center_local: Vector2 = _barrage_area.get_global_transform().affine_inverse() * center_global
	target.position = center_local - target.size * 0.5
	_send_mouse_motion(center_global)
	_send_mouse_button(true, center_global)
	await _wait(0.24)
	_check(_attack_input.is_fully_charged(), "T1 联调攻击完成蓄力")
	_send_mouse_motion(center_global)
	_send_mouse_button(false, center_global)
	var deadline_msec: int = Time.get_ticks_msec() + 3000
	while _battle_flow.get_current_tier() == CombatStage.INITIAL_TIER and Time.get_ticks_msec() < deadline_msec:
		await get_tree().process_frame
	return _battle_flow.get_current_tier() == CombatStage.INITIAL_TIER + 1


# 选取本关强度最高的普通话语，减少命中不确定性并沿用正式结算规则。
func _strongest_normal_speech(level: LevelProfile) -> LevelSpeech:
	if level == null or level.normal_speech_pool.is_empty():
		return null
	var strongest: LevelSpeech = level.normal_speech_pool[0]
	for speech: LevelSpeech in level.normal_speech_pool:
		if speech.strength > strongest.strength:
			strongest = speech
	return strongest


# 将测试画布坐标换成窗口坐标，按正式鼠标输入驱动准心和蓄力。
func _send_mouse_motion(canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (
		_aim_reticle.get_canvas_transform() * canvas_position
	)
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 按下并松开指定位置的鼠标，触发正式蓄力 / 发射处理。
func _send_mouse_button(pressed: bool, canvas_position: Vector2) -> void:
	var window_position: Vector2 = get_viewport().get_final_transform() * (
		_aim_reticle.get_canvas_transform() * canvas_position
	)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# TEST_ONLY 开场条目只存在于深复制的配置 Resource 中，不写入正式策划数据。
func _append_test_event(
		config: BubbleDialogueConfig,
		event_id: StringName,
		text: String,
		duration_seconds: float
) -> void:
	var entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	entry.event_id = event_id
	entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	entry.text = text
	entry.display_duration_seconds = duration_seconds
	entry.priority = BubbleDialogueEntry.Priority.HIT
	config.entries.append(entry)


# 通过 BattleAttemptFlow 最终 Tier 事件验收 T1 嘲讽与 CS-16 震动同帧发生。

func _append_opening_line(config: BubbleDialogueConfig, text: String, duration_seconds: float) -> void:
	var entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	entry.event_id = EVENT_COMBAT_CONNECTED
	entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	entry.text = text
	entry.display_duration_seconds = duration_seconds
	entry.priority = BubbleDialogueEntry.Priority.HIT
	config.entries.append(entry)


func _verify_tier1_taunt(starting_pk: float, starting_tier: int, transition_name: String) -> void:
	_sandbox.call("debug_set_player_pk", starting_pk)
	await get_tree().process_frame
	_check(_battle_flow.get_current_tier() == starting_tier, transition_name + " 的起始档位正确", "CS-27")
	var taunt_count_before: int = _count_completed_events(EVENT_TIER1_TAUNT)
	var battle_area_origin: Vector2 = _battle_area.position
	_sandbox.call("debug_set_player_pk", 0.60)
	_check(_battle_flow.get_current_tier() == 1, transition_name + " 以最终 T1 触发嘲讽", "CS-27")
	_check(_opponent_portrait.is_visible_in_tree(), transition_name + " 嘲讽时对手立绘仍已连线", "CS-27")
	_check(await _wait_for_text(TIER1_TAUNT_LINE, 2.0), transition_name + " 播放已配置的对手嘲讽", "CS-27")
	await get_tree().process_frame
	_check(not _battle_area.position.is_equal_approx(battle_area_origin), transition_name + " 同时触发 CS-16 震动", "CS-27")
	_check(_count_completed_events(EVENT_TIER1_TAUNT) == taunt_count_before,
		transition_name + " 嘲讽对白在实际结束前保持活动", "CS-27")
	await _wait(0.25)
	_check(_battle_area.position.is_equal_approx(battle_area_origin), transition_name + " 震动结束后回到原位", "CS-27")
	var barrage_area: BarrageArea = _battle_flow.get_barrage_area()
	_check(barrage_area.is_normal_generation_enabled(), transition_name + " 后 T1 普通生成保持开启", "CS-27")
	_check(await _wait_for_event_count(EVENT_TIER1_TAUNT, taunt_count_before + 1, 2.0),
		transition_name + " 嘲讽气泡实际播放完毕", "CS-27")
	_check(_count_completed_events(EVENT_TIER1_TAUNT) == taunt_count_before + 1,
		transition_name + " 根据最终 Tier 只提交一次嘲讽事件", "CS-27")
	var player_pk_at_taunt_end: float = _battle_flow.get_hit_resolution().get_player_pk()
	await _wait(0.35)
	_check(
		_battle_flow.get_current_tier() == 1 and _battle_flow.get_hit_resolution().get_player_pk() < player_pk_at_taunt_end,
		transition_name + " 后继续 T1 并按当前倍率回拉",
		"CS-27"
	)

func _on_event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int) -> void:
	_completed_events.append({"event_id": event_id, "sequence_id": sequence_id, "side": side})
	if event_id == EVENT_COMBAT_CONNECTED and _battle_flow != null:
		_pk_at_dialogue_completion = _battle_flow.get_hit_resolution().get_player_pk()


func _bubble_texts() -> Array[String]:
	var texts: Array[String] = []
	for child: Node in _opponent_stack.get_children():
		if child is StreamerBubbleView:
			texts.append((child.get_node("Text") as RichTextLabel).text)
	return texts


func _wait_for_text(expected_text: String, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _bubble_texts().has(expected_text):
			return true
		await get_tree().process_frame
	return _bubble_texts().has(expected_text)


func _wait_for_completed_event(timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while _completed_events.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return not _completed_events.is_empty()


# 以实际游戏帧推进测试时长，不手动修改 PK 或回拉状态。
func _wait_for_event_count(event_id: StringName, target_count: int, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while _count_completed_events(event_id) < target_count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _count_completed_events(event_id) >= target_count


# 从 Sandbox 已转发的完成事实统计单个稳定事件 ID。
func _count_completed_events(event_id: StringName) -> int:
	var count: int = 0
	for completed_event: Dictionary in _completed_events:
		if completed_event.get("event_id", &"") == event_id:
			count += 1
	return count


# 推进真实游戏时间，等待气泡与回拉系统处理帧更新。

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _capture_evidence() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var evidence_path: String = ProjectSettings.globalize_path(EVIDENCE_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(evidence_path) != OK:
		_check(false, "创建 CS-22 GUI 截图目录")
		return
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = evidence_path.path_join("cs22_t1_opening_dialogue_1280x720.png")
	_check(image.save_png(output_path) == OK, "保存 T1 对手开场对白 GUI 截图")


func _wait_frames(frame_count: int) -> void:
	for _frame_index: int in range(frame_count):
		await get_tree().process_frame


func _check(condition: bool, message: String, card_id: String = "CS-22") -> void:
	_checks += 1
	if condition:
		print("PASS %s: %s" % [card_id, message])
	else:
		_failures += 1
		push_error("FAIL %s: %s" % [card_id, message])


func _finish() -> void:
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	print("CS-22 RESULT checks=%d failures=%d display=%s viewport=%s" % [
		_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size
	])
	get_tree().quit(0 if _failures == 0 else 1)
