extends Control

const EntryScript = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_entry.gd")

var _checks: int = 0
var _failures: int = 0
var _completed_sequences: Array[Dictionary] = []


# 通过内存 TEST_ONLY 事件检查真实 Sandbox HUD 的队列和生命周期。
func _ready() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var sandbox: Control = $Sandbox
	var hud: Node = sandbox.get_node("BattleHud")
	var player_stack: StreamerBubbleStack = hud.get_node("%PlayerBubbleStack")
	var opponent_stack: StreamerBubbleStack = hud.get_node("%OpponentBubbleStack")
	hud.connect("dialogue_sequence_completed", Callable(self, "_on_sequence_completed"))
	_check(true, "runtime=%s window=%s; smoke uses TEST_ONLY API events and sends no input"
		% [DisplayServer.get_name(), DisplayServer.window_get_size()])
	_check(
		int(hud.get("max_visible_dialogue_bubbles_per_side")) == 3,
		"HUD 默认同侧上限为 3 且保留导出配置"
	)
	var sandbox_root_loaded: bool = sandbox.has_method("get_debug_snapshot")
	var barrage_count: int = 0
	if sandbox_root_loaded:
		barrage_count = await _wait_for_normal_barrages(sandbox)
		_check(barrage_count > 0, "真实 Sandbox 普通战斗已启动")
	else:
		print("UNVERIFIED: Sandbox root script could not load; continuing real HUD/Stack scene checks.")

	# 连续四条即时命中保留到达顺序；第四条通过旧命中气泡提前退场获得名额。
	var four_hits: Array[BubbleDialogueEntry] = [
		_make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "命中一", BubbleDialogueEntry.Priority.HIT, 8.0),
		_make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "命中二", BubbleDialogueEntry.Priority.HIT, 8.0),
		_make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "命中三", BubbleDialogueEntry.Priority.HIT, 8.0),
		_make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "命中四", BubbleDialogueEntry.Priority.HIT, 8.0),
	]
	for entry: BubbleDialogueEntry in four_hits:
		_check(bool(hud.call("enqueue_dialogue_bubble", entry)), "玩家命中事件已接受：" + entry.text)
	await get_tree().create_timer(0.4).timeout
	var player_texts: Array[String] = _bubble_texts(player_stack)
	_check(player_texts.size() <= 3, "满额命中退场期间同侧同时气泡不超过 3 条")
	_check(player_texts == ["命中二", "命中三", "命中四"], "较旧命中提前退场后仍按到达顺序显示")

	# 双侧状态独立，右侧剧情抢占只处理右侧队列。
	hud.call("clear_dialogue_bubbles")
	hud.call("set_opponent_portrait_connected", true)
	for line: String in ["旧命中一", "旧命中二", "旧命中三"]:
		_check(
			bool(hud.call("enqueue_dialogue_bubble", _make_entry(
				BubbleDialogueEntry.SpeakerSide.OPPONENT, line,
				BubbleDialogueEntry.Priority.HIT, 8.0
			))),
			"对手普通命中事件已接受：" + line
		)
	_check(
		bool(hud.call("enqueue_dialogue_bubble", _make_entry(
			BubbleDialogueEntry.SpeakerSide.OPPONENT, "等待闲聊",
			BubbleDialogueEntry.Priority.TIMED_IDLE, 8.0
		))),
		"低优先级闲聊进入等待"
	)
	var plot_entries: Array[BubbleDialogueEntry] = [
		_make_entry(BubbleDialogueEntry.SpeakerSide.OPPONENT, "剧情第一句", BubbleDialogueEntry.Priority.PLOT, 0.9),
		_make_entry(BubbleDialogueEntry.SpeakerSide.OPPONENT, "剧情第二句", BubbleDialogueEntry.Priority.PLOT, 0.9),
	]
	var sequence_id: StringName = hud.call("enqueue_dialogue_sequence", plot_entries, &"sd03_test_opening")
	_check(sequence_id == &"sd03_test_opening", "关键剧情序列取得可供 CS-23 匹配的 ID")
	_check(
		bool(hud.call("enqueue_dialogue_bubble", _make_entry(
			BubbleDialogueEntry.SpeakerSide.PLAYER, "左侧独立命中",
			BubbleDialogueEntry.Priority.HIT, 8.0
		))),
		"对手剧情播放期间玩家侧队列仍可独立显示"
	)
	var first_plot_visible: bool = await _wait_for_text(opponent_stack, "剧情第一句", 1.5)
	_check(first_plot_visible, "较高优先级剧情先于等待命中与闲聊开始")
	_check(not _bubble_texts(opponent_stack).has("等待闲聊"), "剧情占用期间定时闲聊保持等待")
	_check(_bubble_texts(player_stack).has("左侧独立命中"), "玩家侧事件不被对手侧剧情阻塞")
	var second_plot_visible: bool = await _wait_for_text(opponent_stack, "剧情第二句", 1.5)
	_check(second_plot_visible, "第一句完整结束后才显示第二句")
	_check(not _has_completed_sequence(sequence_id), "最后一句仍播放时没有提前通知完成")
	var sequence_finished: bool = await _wait_for_sequence(sequence_id, 1.5)
	_check(sequence_finished, "最后一句实际结束后发出序列完成通知")
	await get_tree().create_timer(0.05).timeout
	_check(_bubble_texts(opponent_stack) == ["等待闲聊"], "剧情结束后恢复等待中的定时闲聊")

	# SceneTree 暂停期间，绑定于气泡节点的 Tween 不推进；恢复后生命周期继续。
	hud.call("clear_dialogue_bubbles")
	var pause_entry: BubbleDialogueEntry = _make_entry(
		BubbleDialogueEntry.SpeakerSide.PLAYER, "暂停验证", BubbleDialogueEntry.Priority.HIT, 1.4
	)
	hud.call("enqueue_dialogue_bubble", pause_entry)
	await get_tree().create_timer(0.2).timeout
	var pause_bubbles: Array[StreamerBubbleView] = _get_bubbles(player_stack)
	_check(pause_bubbles.size() == 1, "暂停验证气泡已经显示")
	if pause_bubbles.size() == 1:
		var paused_progress: float = pause_bubbles[0].float_progress
		get_tree().paused = true
		await get_tree().create_timer(0.4, true).timeout
		var progress_while_paused: float = pause_bubbles[0].float_progress
		get_tree().paused = false
		_check(
			is_equal_approx(progress_while_paused, paused_progress),
			"暂停期间气泡 Tween 与生命周期保持冻结"
		)
		await get_tree().create_timer(0.1).timeout
		_check(pause_bubbles[0].float_progress > progress_while_paused, "恢复后气泡 Tween 继续推进")

	# 重开清空双方活动和待播对白；T0 离线清理对手侧并拒绝后续请求。
	hud.call("clear_dialogue_bubbles")
	var cancelled_entries: Array[BubbleDialogueEntry] = [
		_make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "重开前剧情", BubbleDialogueEntry.Priority.PLOT, 1.0)
	]
	var cancelled_sequence: StringName = hud.call(
		"enqueue_dialogue_sequence",
		cancelled_entries,
		&"sd03_test_cancelled"
	)
	_check(not String(cancelled_sequence).is_empty(), "重开验证剧情已进入队列")
	hud.call("reset_for_attempt")
	await get_tree().process_frame
	_check(_get_bubbles(player_stack).is_empty(), "战斗重开清理玩家侧活动气泡")
	_check(_get_bubbles(opponent_stack).is_empty(), "战斗重开清理对手侧活动气泡")
	await get_tree().create_timer(1.2).timeout
	_check(not _has_completed_sequence(cancelled_sequence), "重开取消的序列不会延迟触发完成通知")
	hud.call("set_opponent_portrait_connected", true)
	var opponent_entry: BubbleDialogueEntry = _make_entry(
		BubbleDialogueEntry.SpeakerSide.OPPONENT, "离线前命中", BubbleDialogueEntry.Priority.HIT, 8.0
	)
	_check(bool(hud.call("enqueue_dialogue_bubble", opponent_entry)), "T1 对手在线时接受气泡事件")
	hud.call("set_opponent_portrait_connected", false)
	var offline_bubbles: Array[StreamerBubbleView] = _get_bubbles(opponent_stack)
	var offline_bubbles_hidden: bool = true
	for bubble: StreamerBubbleView in offline_bubbles:
		if bubble.visible:
			offline_bubbles_hidden = false
	_check(offline_bubbles_hidden, "T0 对手离线当帧隐藏当前气泡")
	_check(
		not bool(hud.call("enqueue_dialogue_bubble", opponent_entry)),
		"T0 离线期间拒绝新的对手气泡事件"
	)
	await get_tree().process_frame
	_check(_get_bubbles(opponent_stack).is_empty(), "离线气泡在下一帧从场景树回收")
	await get_tree().create_timer(0.35).timeout
	_check(_get_bubbles(opponent_stack).is_empty(), "对手离线后没有待播气泡重新出现")

	print(
		"SD-03 SMOKE RESULT checks=%d failures=%d display=%s window=%s sandbox_root_loaded=%s barrage_count=%d input=none"
		% [_checks, _failures, DisplayServer.get_name(), DisplayServer.window_get_size(), sandbox_root_loaded, barrage_count]
	)
	get_tree().quit(0 if _failures == 0 else 1)


func _make_entry(side: int, line: String, priority: int, duration: float) -> BubbleDialogueEntry:
	var entry: BubbleDialogueEntry = EntryScript.new()
	entry.side = side
	entry.text = line
	entry.event_id = &"sd03_test_only"
	entry.priority = priority
	entry.display_duration_seconds = duration
	return entry


func _wait_for_normal_barrages(sandbox: Control) -> int:
	var waited: float = 0.0
	while waited < 4.0:
		var snapshot: Dictionary = sandbox.call("get_debug_snapshot")
		var count: int = int(snapshot.get("normal_barrage_count", 0))
		if count > 0:
			return count
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return 0


func _get_bubbles(stack: StreamerBubbleStack) -> Array[StreamerBubbleView]:
	var bubbles: Array[StreamerBubbleView] = []
	for child: Node in stack.get_children():
		if child is StreamerBubbleView:
			bubbles.append(child)
	return bubbles


func _bubble_texts(stack: StreamerBubbleStack) -> Array[String]:
	var result: Array[String] = []
	for bubble: StreamerBubbleView in _get_bubbles(stack):
		var label: RichTextLabel = bubble.get_node("Text")
		result.append(label.text)
	return result


func _wait_for_text(stack: StreamerBubbleStack, expected: String, timeout: float) -> bool:
	var waited: float = 0.0
	while waited < timeout:
		if _bubble_texts(stack).has(expected):
			return true
		await get_tree().create_timer(0.02).timeout
		waited += 0.02
	return _bubble_texts(stack).has(expected)


func _wait_for_sequence(sequence_id: StringName, timeout: float) -> bool:
	var waited: float = 0.0
	while waited < timeout:
		if _has_completed_sequence(sequence_id):
			return true
		await get_tree().create_timer(0.02).timeout
		waited += 0.02
	return _has_completed_sequence(sequence_id)


func _has_completed_sequence(sequence_id: StringName) -> bool:
	for completed: Dictionary in _completed_sequences:
		if completed.get("sequence_id", &"") == sequence_id:
			return true
	return false


func _on_sequence_completed(sequence_id: StringName, side: int) -> void:
	_completed_sequences.append({"sequence_id": sequence_id, "side": side})


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
