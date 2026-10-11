extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const BUBBLE_DIALOGUE_CONFIG: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
const PRESENTATION_ASSETS: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const OPPONENT_IDLE: Texture2D = preload("res://assets/characters/opponents/alien/alien_idle.png")
const EVIDENCE_DIRECTORY: String = "res://docs/8. CombatStage/evidence/cs22_2026-10-11"
const EVENT_COMBAT_CONNECTED: StringName = &"combat_connected"
const FIRST_OPENING_LINE: String = "TEST_ONLY 连线开场第一句"
const SECOND_OPENING_LINE: String = "TEST_ONLY 连线开场第二句"

var _sandbox: Control
var _battle_flow: BattleAttemptFlow
var _battle_hud: Control
var _opponent_stack: StreamerBubbleStack
var _opponent_portrait: TextureRect
var _completed_events: Array[Dictionary] = []
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

	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set("bubble_dialogue_config", test_config)
	add_child(_sandbox)
	await _wait_frames(2)
	_battle_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	_battle_hud = _sandbox.get_node_or_null("BattleHud") as Control
	if _battle_flow != null and _battle_hud != null:
		_opponent_stack = _battle_hud.get_node_or_null("%OpponentBubbleStack") as StreamerBubbleStack
		_opponent_portrait = _battle_hud.find_child("OpponentPortraitArt", true, false) as TextureRect
	if _battle_flow == null or _battle_hud == null or _opponent_stack == null or _opponent_portrait == null:
		_check(false, "正式 Sandbox 提供 BattleAttemptFlow、对手立绘与 SD-03 气泡栈")
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

	# 真实 Tier 信号先刷新 HUD 立绘，再由 SD-06 查询 combat_connected 并提交 SD-03 序列。
	_sandbox.call("debug_set_player_pk", 0.56)
	_check(_battle_flow.get_current_tier() == 1, "真实 CombatStage 从 T0 进入 T1")
	_check(_opponent_portrait.is_visible_in_tree(), "连线开场启动前已显示对手待机立绘")
	_check(_bubble_texts().has(FIRST_OPENING_LINE), "SD-06 按配置顺序启动对手开场第一句")
	_check(_completed_events.is_empty(), "开场对白播放期间尚未发送序列完成通知")
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
	await _finish()


# TEST_ONLY 开场条目只存在于深复制的配置 Resource 中，不写入正式策划数据。
func _append_opening_line(config: BubbleDialogueConfig, text: String, duration_seconds: float) -> void:
	var entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	entry.event_id = EVENT_COMBAT_CONNECTED
	entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	entry.text = text
	entry.display_duration_seconds = duration_seconds
	entry.priority = BubbleDialogueEntry.Priority.HIT
	config.entries.append(entry)


func _on_event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int) -> void:
	_completed_events.append({"event_id": event_id, "sequence_id": sequence_id, "side": side})


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


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS CS-22: " + message)
	else:
		_failures += 1
		push_error("FAIL CS-22: " + message)


func _finish() -> void:
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	print("CS-22 RESULT checks=%d failures=%d display=%s viewport=%s" % [
		_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size
	])
	get_tree().quit(0 if _failures == 0 else 1)
