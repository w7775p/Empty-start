extends Control

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const BUBBLE_DIALOGUE_CONFIG: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
const EVIDENCE_DIRECTORY: String = "res://docs/21. StreamerBubbleDialogue/evidence/SD-06_2026-10-11"
const EVENT_COMBAT_CONNECTED: StringName = &"combat_connected"
const EVENT_TIER_UP: StringName = &"combat_tier_up"
const EVENT_TIER_DOWN: StringName = &"combat_tier_down"
const EVENT_TIER1_TAUNT: StringName = &"combat_tier1_taunt"
const EVENT_COMBAT_WIN: StringName = &"combat_win"
const EVENT_COMBAT_LOSE: StringName = &"combat_lose"
const EVENT_PARADOX_NOT_BROKEN: StringName = &"paradox_not_broken"

var _sandbox: Control
var _battle_flow: BattleAttemptFlow
var _oracle_flow: ContradictionOracleFlow
var _battle_hud: Node
var _opponent_stack: StreamerBubbleStack
var _completed_events: Array[Dictionary] = []
var _rest_ready_count: int = 0
var _checks: int = 0
var _failures: Array[String] = []


# 使用真实 Sandbox 与内存 TEST_ONLY 配置，验证状态事实、剧情优先级和完整完成时点。
func _ready() -> void:
	call_deferred("_run_acceptance")


func _run_acceptance() -> void:
	SaveManager.new_game()
	var test_config: BubbleDialogueConfig = BUBBLE_DIALOGUE_CONFIG.duplicate(true) as BubbleDialogueConfig
	test_config.entries.clear()
	var opening_first: BubbleDialogueEntry = _append_event(
		test_config, EVENT_COMBAT_CONNECTED, BubbleDialogueEntry.SpeakerSide.OPPONENT,
		"TEST_ONLY 连线开场第一句", 0.65
	)
	_append_event(
		test_config, EVENT_COMBAT_CONNECTED, BubbleDialogueEntry.SpeakerSide.OPPONENT,
		"TEST_ONLY 连线开场第二句", 0.65
	)
	_append_event(test_config, EVENT_TIER_UP, BubbleDialogueEntry.SpeakerSide.OPPONENT, "TEST_ONLY 升档", 0.12)
	_append_event(test_config, EVENT_TIER_DOWN, BubbleDialogueEntry.SpeakerSide.OPPONENT, "TEST_ONLY 降档", 0.12)
	_append_event(test_config, EVENT_TIER1_TAUNT, BubbleDialogueEntry.SpeakerSide.OPPONENT, "TEST_ONLY T1 嘲讽", 0.12)
	_append_event(test_config, EVENT_COMBAT_WIN, BubbleDialogueEntry.SpeakerSide.OPPONENT, "TEST_ONLY 普通 PK 胜利", 0.12)
	_append_event(test_config, EVENT_COMBAT_LOSE, BubbleDialogueEntry.SpeakerSide.PLAYER, "TEST_ONLY 普通战斗失败", 0.12)
	_append_event(test_config, EVENT_PARADOX_NOT_BROKEN, BubbleDialogueEntry.SpeakerSide.OPPONENT, "TEST_ONLY 未击破矛盾", 0.12)
	_check(opening_first.priority == BubbleDialogueEntry.Priority.HIT, "fixture 源条目保留原优先级，运行副本才提升为 PLOT")

	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set("bubble_dialogue_config", test_config)
	add_child(_sandbox)
	await _wait_frames(2)
	_battle_flow = _sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	_oracle_flow = _sandbox.call("get_contradiction_oracle_flow") as ContradictionOracleFlow
	_battle_hud = _sandbox.get_node_or_null("BattleHud")
	_opponent_stack = _battle_hud.get_node_or_null("%OpponentBubbleStack") as StreamerBubbleStack if _battle_hud != null else null
	if _battle_flow == null or _oracle_flow == null or _battle_hud == null or _opponent_stack == null:
		_check(false, "真实 Sandbox 提供战斗流程、ContradictionOracleFlow 与 SD-03 HUD")
		await _finish()
		return
	_sandbox.connect("dialogue_event_sequence_completed", Callable(self, "_on_event_sequence_completed"))
	_oracle_flow.rest_ready.connect(_on_rest_ready)
	print("SD-06 DISPLAY: %s window=%s" % [DisplayServer.get_name(), DisplayServer.window_get_size()])
	_check(_battle_flow.get_current_tier() == 0, "新尝试从 T0 等待连线开始")

	# T0→T1 时序列进入对手侧 PLOT 队列；HIT 等待整段开场播放完。
	_sandbox.call("debug_set_player_pk", 0.56)
	_check(_battle_flow.get_current_tier() == 1, "真实 HitResolution / CombatStage 到达 T1")
	var low_priority_entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	low_priority_entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	low_priority_entry.text = "TEST_ONLY 开场后的普通命中"
	low_priority_entry.priority = BubbleDialogueEntry.Priority.HIT
	low_priority_entry.display_duration_seconds = 0.5
	_check(bool(_battle_hud.call("enqueue_dialogue_bubble", low_priority_entry)), "连线剧情播放期间普通命中仍能进入 SD-03 等待队列")
	_check(await _wait_for_text("TEST_ONLY 连线开场第一句", 1.0), "T0→T1 按稳定连接事件 ID 播放配置第一句")
	_check(_event_count(EVENT_COMBAT_CONNECTED) == 0, "开场第一句播放期间尚未通知 CS-23 完成")
	_check(not _bubble_texts(_opponent_stack).has(low_priority_entry.text), "普通命中没有插入关键开场序列")
	await _capture_evidence()
	var opening_bubbles: Array[StreamerBubbleView] = _get_opponent_bubbles()
	if not opening_bubbles.is_empty():
		var progress_before_pause: float = opening_bubbles[0].float_progress
		get_tree().paused = true
		await get_tree().create_timer(0.4, true, false, true).timeout
		var progress_while_paused: float = opening_bubbles[0].float_progress if is_instance_valid(opening_bubbles[0]) else -1.0
		_check(_event_count(EVENT_COMBAT_CONNECTED) == 0, "暂停期间没有提前发出开场序列完成通知")
		_check(is_equal_approx(progress_before_pause, progress_while_paused), "暂停期间开场气泡生命周期冻结")
		get_tree().paused = false
	else:
		_check(false, "暂停检查前开场气泡仍在真实 HUD 中")
	_check(await _wait_for_text("TEST_ONLY 连线开场第二句", 2.0), "第一句完整结束后才播放连接序列第二句")
	_check(await _wait_for_event_count(EVENT_COMBAT_CONNECTED, 1, 4.0), "最后一句结束后 Sandbox 才转发 CS-23 所需完成事件")
	_check(_event_count(EVENT_COMBAT_CONNECTED) == 1, "完整连接序列只完成一次")
	await _wait_frames(2)
	_check(_bubble_texts(_opponent_stack).has(low_priority_entry.text), "开场序列结束后 SD-03 恢复等待中的普通命中")

	# 逐档运行正式 Tier 规则，检查通用升降与 CS-27 的 T1 专属嘲讽映射。
	_battle_hud.call("clear_dialogue_bubbles")
	_sandbox.call("debug_set_player_pk", 0.64)
	_check(_battle_flow.get_current_tier() == 2, "真实 PK 达到 Tier 2 升档阈值")
	_check(await _wait_for_event_count(EVENT_TIER_UP, 1, 2.0), "Tier 1→2 进入通用升档语义事件")
	_battle_hud.call("clear_dialogue_bubbles")
	_sandbox.call("debug_set_player_pk", 0.71)
	_check(_battle_flow.get_current_tier() == 3, "真实 PK 达到 Tier 3 升档阈值")
	_check(await _wait_for_event_count(EVENT_TIER_UP, 2, 2.0), "第二次实际升档只提交一次升档事件")
	_battle_hud.call("clear_dialogue_bubbles")
	_sandbox.call("debug_set_player_pk", 0.67)
	_check(_battle_flow.get_current_tier() == 2, "真实 PK 低于 Tier 3 降档阈值")
	_check(await _wait_for_event_count(EVENT_TIER_DOWN, 1, 2.0), "普通降档进入通用降档语义事件")
	_battle_hud.call("clear_dialogue_bubbles")
	_sandbox.call("debug_set_player_pk", 0.60)
	_check(_battle_flow.get_current_tier() == 1, "真实 PK 跨档最终降至 T1")
	_check(await _wait_for_event_count(EVENT_TIER1_TAUNT, 1, 2.0), "T2+→T1 只触发供 CS-27 使用的稳定嘲讽事件 ID")
	_battle_hud.call("clear_dialogue_bubbles")
	var event_count_before_disconnect: int = _completed_events.size()
	_sandbox.call("debug_set_player_pk", 0.52)
	_check(_battle_flow.get_current_tier() == 0, "真实 PK 降至 T0 并让对手离线")
	await _wait_frames(2)
	_check(_completed_events.size() == event_count_before_disconnect, "T1→T0 离线清理不额外提交降档对白")
	_check(_get_opponent_bubbles().is_empty(), "T0 离线清理对手侧活动气泡")

	# 原地重开会收到 attempt_started 与 attempt_restarted；消费者只处理一次启动事实。
	var event_count_before_restart: int = _completed_events.size()
	_sandbox.call("restart_current_attempt")
	await _wait_frames(2)
	_check(_battle_flow.get_current_tier() == 0, "重开恢复到 T0")
	_check(_completed_events.size() == event_count_before_restart, "重开本身不会重复显示或完成状态对白")
	_sandbox.call("debug_set_player_pk", 0.56)
	_check(await _wait_for_text("TEST_ONLY 连线开场第一句", 1.0), "重开后新的连线重新获得独立完整序列")
	_battle_hud.call("clear_dialogue_bubbles")
	await _wait_frames(2)
	_check(_event_count(EVENT_COMBAT_CONNECTED) == 1, "被离线取消的旧序列不会延迟完成，也不会误认新序列")
	_sandbox.call("debug_set_player_pk", 0.52)
	await _wait_frames(2)
	_check(_event_count(EVENT_COMBAT_CONNECTED) == 1, "对手离线后被清理的连接序列不发出完成信号")

	# 普通失败与 PK 胜利来自 BattleAttemptFlow；Paradox 结果走独立事件 ID。
	_sandbox.call("restart_current_attempt")
	await _wait_frames(2)
	_sandbox.call("debug_set_player_pk", 0.0)
	_check(await _wait_for_event_count(EVENT_COMBAT_LOSE, 1, 2.0), "OpponentPKBar 的真实 PK0 失败经 BattleAttemptFlow 映射为战败事件")
	_battle_hud.call("clear_dialogue_bubbles")
	_sandbox.call("restart_current_attempt")
	await _wait_frames(2)
	_check(_event_count(EVENT_COMBAT_LOSE) == 1, "失败后的重开不重复提交旧失败事件")
	_sandbox.call("debug_set_player_pk", 1.0)
	_check(await _wait_for_event_count(EVENT_COMBAT_CONNECTED, 2, 6.0), "跨档直达正 Tier 时仍产生一次连接事实")
	_check(await _wait_for_event_count(EVENT_TIER_UP, 3, 6.0), "跨档直达高 Tier 时追加一次升档事实")
	_check(await _wait_for_event_count(EVENT_COMBAT_WIN, 1, 6.0), "普通 PK 满值由 BattleAttemptFlow 完成信号映射为胜利事件")
	_check(await _wait_for_contradiction(), "满 PK 后正式 ContradictionOracleFlow 进入 Paradox")
	var contradiction_system: ContradictionBreakSystem = _oracle_flow.get_contradiction_system()
	_check(contradiction_system.register_launched_shot(), "真实矛盾系统接受测试发射")
	_check(contradiction_system.resolve_shot_hit_ids([]), "矛盾系统按实际空命中结果锁定未击破")
	_check(await _wait_for_event_count(EVENT_PARADOX_NOT_BROKEN, 1, 6.0), "ContradictionOracleFlow 只提交独立未击破事件")
	await _wait_for_rest_ready()
	var completed_before_rest_hold: int = _completed_events.size()
	await get_tree().create_timer(0.4, true, false, true).timeout
	_check(_completed_events.size() == completed_before_rest_hold, "进入 Rest 后没有重复触发胜负或 Paradox 对白")

	print("SD-06 INPUT source=Sandbox.debug_set_player_pk + real ContradictionBreakSystem; physical mouse=NOT TESTED")
	await _finish()


# 为测试副本建立可编辑事件条目；正式对白 Resource、表格和导出器保持原样。
func _append_event(
	config: BubbleDialogueConfig,
	event_id: StringName,
	side: int,
	text: String,
	duration_seconds: float
) -> BubbleDialogueEntry:
	var entry := BubbleDialogueEntry.new()
	entry.event_id = event_id
	entry.side = side
	entry.text = text
	entry.priority = BubbleDialogueEntry.Priority.HIT
	entry.display_duration_seconds = duration_seconds
	config.entries.append(entry)
	return entry


func _on_event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int) -> void:
	_completed_events.append({"event_id": event_id, "sequence_id": sequence_id, "side": side})


func _on_rest_ready(_result: RestSession) -> void:
	_rest_ready_count += 1


func _event_count(event_id: StringName) -> int:
	var count: int = 0
	for event_record: Dictionary in _completed_events:
		if event_record.get("event_id") == event_id:
			count += 1
	return count


func _wait_for_event_count(event_id: StringName, required_count: int, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while _event_count(event_id) < required_count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _event_count(event_id) >= required_count


func _wait_for_text(expected_text: String, timeout_seconds: float) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _bubble_texts(_opponent_stack).has(expected_text):
			return true
		await get_tree().process_frame
	return _bubble_texts(_opponent_stack).has(expected_text)


func _wait_for_contradiction() -> bool:
	var deadline: int = Time.get_ticks_msec() + 3000
	while not _oracle_flow.is_contradiction_active() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _oracle_flow.is_contradiction_active()


func _wait_for_rest_ready() -> void:
	var deadline: int = Time.get_ticks_msec() + 3000
	while _rest_ready_count == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_rest_ready_count == 1, "未击破结果只进入一次正式 RestSession")


func _get_opponent_bubbles() -> Array[StreamerBubbleView]:
	var bubbles: Array[StreamerBubbleView] = []
	if _opponent_stack == null:
		return bubbles
	for child: Node in _opponent_stack.get_children():
		if child is StreamerBubbleView:
			bubbles.append(child)
	return bubbles


func _bubble_texts(stack: StreamerBubbleStack) -> Array[String]:
	var texts: Array[String] = []
	if stack == null:
		return texts
	for child: Node in stack.get_children():
		if child is StreamerBubbleView:
			texts.append((child.get_node("Text") as RichTextLabel).text)
	return texts


func _capture_evidence() -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var evidence_path: String = ProjectSettings.globalize_path(EVIDENCE_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(evidence_path) != OK:
		_check(false, "创建 SD-06 GUI 截图目录")
		return
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = evidence_path.path_join("sd06_connected_sequence_%dx%d.png" % [image.get_width(), image.get_height()])
	_check(image.save_png(output_path) == OK, "保存真实 Sandbox 连线气泡截图 %s" % output_path.get_file())


func _wait_frames(frame_count: int) -> void:
	for _frame_index: int in range(frame_count):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS SD-06: " + message)
	else:
		_failures.append(message)
		push_error("FAIL SD-06: " + message)


func _finish() -> void:
	get_tree().paused = false
	if is_instance_valid(_sandbox):
		_sandbox.queue_free()
	await get_tree().process_frame
	print("SD-06 GUI RESULT checks=%d failures=%d display=%s window=%s" % [
		_checks, _failures.size(), DisplayServer.get_name(), DisplayServer.window_get_size()
	])
	get_tree().quit(0 if _failures.is_empty() else 1)
