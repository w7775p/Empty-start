extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const BUBBLE_DIALOGUE_CONFIG: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
const EVIDENCE_DIRECTORY: String = "res://docs/21. StreamerBubbleDialogue/evidence/SD-07_2026-10-11"
const EVENT_COMBAT_CONNECTED: StringName = &"combat_connected"
const EVENT_TIMED: StringName = &"timed"

var _sandbox: Control
var _battle_flow: BattleAttemptFlow
var _battle_hud: Node
var _opponent_stack: StreamerBubbleStack
var _completed_connected_sequences: int = 0
var _timed_visible_when_plot_completed: bool = false
var _checks: int = 0
var _failures: Array[String] = []


# 在真实 Sandbox 中验证定时配置、SD-03 优先级、暂停和重开时钟。
func _ready() -> void:
	call_deferred("_run_acceptance")


func _run_acceptance() -> void:
	SaveManager.new_game()
	var test_config: BubbleDialogueConfig = BUBBLE_DIALOGUE_CONFIG.duplicate(true) as BubbleDialogueConfig
	test_config.entries.clear()
	_append_entry(test_config, EVENT_COMBAT_CONNECTED, "TEST_ONLY 连线剧情第一句", 0.55)
	_append_entry(test_config, EVENT_COMBAT_CONNECTED, "TEST_ONLY 连线剧情第二句", 0.55)
	var first_timed_entry: BubbleDialogueEntry = _append_entry(
		test_config, EVENT_TIMED, "TEST_ONLY 首个定时对白", 0.24, 0.2
	)
	var second_timed_entry: BubbleDialogueEntry = _append_entry(
		test_config, EVENT_TIMED, "TEST_ONLY 暂停与重开定时对白", 0.24, 3.0
	)
	_check(first_timed_entry.priority == BubbleDialogueEntry.Priority.HIT, "fixture 保留源 Resource 优先级供消费者复制验证")
	_check(second_timed_entry.trigger_time_seconds > first_timed_entry.trigger_time_seconds, "fixture 配置两个不同触发时点")

	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set("bubble_dialogue_config", test_config)
	add_child(_sandbox)
	await _wait_frames(2)
	_battle_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	_battle_hud = _sandbox.get_node_or_null("BattleHud")
	_opponent_stack = _battle_hud.get_node_or_null("%OpponentBubbleStack") as StreamerBubbleStack if _battle_hud != null else null
	if _battle_flow == null or _battle_hud == null or _opponent_stack == null:
		_check(false, "真实 Sandbox 提供 BattleAttemptFlow 和 SD-03 对手栈")
		await _finish()
		return
	_sandbox.connect("dialogue_event_sequence_completed", Callable(self, "_on_dialogue_event_sequence_completed"))
	_check(_battle_flow.get_current_tier() == CombatStage.INITIAL_TIER, "新尝试从 T0 开始")

	# T0 时先让第一个时间点到期，重连后确认待提交闲聊仍让位于连接剧情。
	await get_tree().create_timer(0.35).timeout
	_check(_bubble_texts(_opponent_stack).is_empty(), "T0 离线期间不显示对手定时对白")
	_sandbox.call("debug_set_player_pk", 0.56)
	_check(_battle_flow.get_current_tier() == 1, "真实 CombatStage 到达对手在线 T1")
	_check(await _wait_for_text("TEST_ONLY 连线剧情第一句", 1.0), "连线后优先显示配置剧情第一句")
	_check(not _bubble_texts(_opponent_stack).has(first_timed_entry.text), "定时闲聊没有打断关键剧情序列")
	_check(await _wait_for_text("TEST_ONLY 连线剧情第二句", 2.0), "关键剧情仍逐句完整播放")
	_check(await _wait_for_connected_completion(3.0), "最后一句真实到期后收到连线序列完成通知")
	_check(not _timed_visible_when_plot_completed, "剧情完成回调发生时定时对白仍在队列等待")
	_check(await _wait_for_text(first_timed_entry.text, 1.0), "关键剧情结束后显示首个到期的闲聊")
	_check(await _capture_evidence(), "保存真实 Sandbox 定时气泡截图")
	_check(first_timed_entry.priority == BubbleDialogueEntry.Priority.HIT, "运行副本提优先级没有改写静态配置")
	_check(await _wait_for_text_absent(first_timed_entry.text, 1.5), "首个定时气泡按时到期并回收")

	# 第二个时间点落在暂停期间；恢复后仍需累计剩余战斗时间才会入队。
	get_tree().paused = true
	await get_tree().create_timer(1.2, true, false, true).timeout
	_check(not _bubble_texts(_opponent_stack).has(second_timed_entry.text), "暂停期间没有触发后续定时对白")
	get_tree().paused = false
	await get_tree().create_timer(0.2).timeout
	_check(not _bubble_texts(_opponent_stack).has(second_timed_entry.text), "恢复后计时从暂停时的剩余时间继续")
	_check(await _wait_for_text(second_timed_entry.text, 2.0), "累计到第二时间点后显示对应对白")

	# 重开重新读取配置并把本场计时归零，较晚的行不会沿用上一次累计值。
	_sandbox.call("restart_current_attempt")
	await _wait_frames(2)
	_check(_battle_flow.get_current_tier() == CombatStage.INITIAL_TIER, "重开恢复到 T0")
	_check(_bubble_texts(_opponent_stack).is_empty(), "重开清理双方已有气泡")
	_sandbox.call("debug_set_player_pk", 0.56)
	_check(await _wait_for_text("TEST_ONLY 连线剧情第一句", 1.0), "重开后仍由新尝试触发连线剧情")
	_check(await _wait_for_connected_completion(3.0), "重开后的剧情序列完整结束")
	_check(await _wait_for_text(first_timed_entry.text, 1.0), "重开后重新从首个定时点开始")
	_check(not _bubble_texts(_opponent_stack).has(second_timed_entry.text), "重开后较晚时间点没有继承旧计时")
	_check(await _wait_for_text(second_timed_entry.text, 2.0), "重开后的较晚时间点按新时钟触发")

	print("SD-07 INPUT source=BattleAttemptFlow signals + timed fixture; physical mouse=NOT TESTED")
	await _finish()


# 测试条目保留 HIT 源优先级，SD-07 应复制后将请求设为 TIMED_IDLE。
func _append_entry(
	config: BubbleDialogueConfig,
	event_id: StringName,
	text: String,
	display_duration_seconds: float,
	trigger_time_seconds: float = 0.0
) -> BubbleDialogueEntry:
	var entry := BubbleDialogueEntry.new()
	entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	entry.event_id = event_id
	entry.text = text
	entry.priority = BubbleDialogueEntry.Priority.HIT
	entry.display_duration_seconds = display_duration_seconds
	entry.trigger_time_seconds = trigger_time_seconds
	config.entries.append(entry)
	return entry


func _on_dialogue_event_sequence_completed(event_id: StringName, _sequence_id: StringName, _side: int) -> void:
	if event_id != EVENT_COMBAT_CONNECTED:
		return
	_completed_connected_sequences += 1
	if _bubble_texts(_opponent_stack).has("TEST_ONLY 首个定时对白"):
		_timed_visible_when_plot_completed = true


func _wait_for_connected_completion(timeout_seconds: float) -> bool:
	var required_count: int = _completed_connected_sequences + 1
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while _completed_connected_sequences < required_count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _completed_connected_sequences >= required_count


func _wait_for_text(expected_text: String, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _bubble_texts(_opponent_stack).has(expected_text):
			return true
		await get_tree().process_frame
	return _bubble_texts(_opponent_stack).has(expected_text)


func _wait_for_text_absent(text: String, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if not _bubble_texts(_opponent_stack).has(text):
			return true
		await get_tree().process_frame
	return not _bubble_texts(_opponent_stack).has(text)


func _bubble_texts(stack: StreamerBubbleStack) -> Array[String]:
	var texts: Array[String] = []
	if stack == null:
		return texts
	for child: Node in stack.get_children():
		if child is StreamerBubbleView:
			texts.append((child.get_node("Text") as RichTextLabel).text)
	return texts


func _capture_evidence() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path(EVIDENCE_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return false
	var image: Image = get_viewport().get_texture().get_image()
	var file_name: String = "sd07_timed_dialogue_%dx%d.png" % [image.get_width(), image.get_height()]
	return image.save_png(directory.path_join(file_name)) == OK


func _wait_frames(frame_count: int) -> void:
	for _frame_index: int in range(frame_count):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS SD-07: " + message)
	else:
		_failures.append(message)
		push_error("FAIL SD-07: " + message)


func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	print("SD-07 GUI RESULT checks=%d failures=%d display=%s window=%s" % [
		_checks, _failures.size(), DisplayServer.get_name(), DisplayServer.window_get_size()
	])
	get_tree().quit(0 if _failures.is_empty() else 1)
