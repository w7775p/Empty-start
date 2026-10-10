extends Control

const EntryScript = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_entry.gd")

var _checks: int = 0
var _failures: int = 0


# 启动真实 Sandbox 后通过 HUD 公开入口提交 TEST_ONLY 对白，避免改正式配置。
func _ready() -> void:
	call_deferred("_run_smoke")


# 按单侧与双方三个状态运行正式 Sandbox，并在寿命结束前检查渐隐。
func _run_smoke() -> void:
	var sandbox: Control = $Sandbox
	var hud: Control = sandbox.get_node("BattleHud")
	var player_stack: StreamerBubbleStack = hud.get_node("%PlayerBubbleStack")
	var opponent_stack: StreamerBubbleStack = hud.get_node("%OpponentBubbleStack")
	_check(DisplayServer.get_name() != "headless", "运行在可见窗口的 Godot GUI")
	var reticle: CanvasItem = sandbox.get_node("%AimReticle") as CanvasItem
	_check(reticle.is_visible_in_tree(), "正式 Sandbox 准心仍可见")
	var barrage_count: int = 0
	var waited_seconds: float = 0.0
	while waited_seconds < 4.0:
		var snapshot: Dictionary = sandbox.call("get_debug_snapshot")
		barrage_count = int(snapshot.get("normal_barrage_count", 0))
		if barrage_count > 0:
			break
		await get_tree().create_timer(0.1).timeout
		waited_seconds += 0.1
	_check(barrage_count > 0, "正式弹幕生成器持续运行")
	var player_short: BubbleDialogueEntry = _make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "看我的！")
	var player_long: BubbleDialogueEntry = _make_entry(
		BubbleDialogueEntry.SpeakerSide.PLAYER,
		"这一波弹幕沿着主播画面边缘飞来，我会继续盯准中心的准心再发射！"
	)
	var player_newest: BubbleDialogueEntry = _make_entry(BubbleDialogueEntry.SpeakerSide.PLAYER, "打中了吗？")
	var opponent_short: BubbleDialogueEntry = _make_entry(BubbleDialogueEntry.SpeakerSide.OPPONENT, "接招！")
	var opponent_long: BubbleDialogueEntry = _make_entry(
		BubbleDialogueEntry.SpeakerSide.OPPONENT,
		"我已经看见弹幕从左边过来，这次轮到我的直播间说句话了。"
	)
	var opponent_newest: BubbleDialogueEntry = _make_entry(BubbleDialogueEntry.SpeakerSide.OPPONENT, "来吧！")
	var player_lines: Array[BubbleDialogueEntry] = [player_short, player_long, player_newest]
	var opponent_lines: Array[BubbleDialogueEntry] = [opponent_short, opponent_long, opponent_newest]
	for entry: BubbleDialogueEntry in player_lines:
		hud.call("show_dialogue_bubble", entry)
	await get_tree().create_timer(0.25).timeout
	var player_bubbles: Array[StreamerBubbleView] = _get_bubbles(player_stack)
	_check(player_bubbles.size() == 3, "玩家侧三条气泡同时显示")
	if player_bubbles.size() == 3:
		_check(player_bubbles[0].position.y < player_bubbles[2].position.y, "玩家侧保留到达顺序，自上而下堆叠")
		_check(player_bubbles[1].size.x <= player_stack.max_bubble_width, "玩家侧长文本宽度不超过可调上限")
		_check(player_bubbles[1].size.y > player_bubbles[0].size.y, "玩家侧长文本自动换行并增加气泡高度")
		_check(player_bubbles[0].tail_direction == StreamerBubbleView.TailDirection.RIGHT, "玩家尾巴朝向主播内侧")
		_check(player_bubbles[0].float_progress > 0.0, "气泡随显示时长持续上浮")
	if player_bubbles.size() == 3:
		_check(absf(player_bubbles[1].size.y - player_bubbles[1].custom_minimum_size.y) < 0.5,
			"历史气泡缩小时实际高度与目标高度一致")
	await _capture("player_left")
	player_stack.clear_bubbles()
	for entry: BubbleDialogueEntry in opponent_lines:
		hud.call("show_dialogue_bubble", entry)
	await get_tree().create_timer(0.25).timeout
	var opponent_bubbles: Array[StreamerBubbleView] = _get_bubbles(opponent_stack)
	_check(opponent_bubbles.size() == 3, "对手侧三条气泡同时显示")
	if opponent_bubbles.size() == 3:
		_check(opponent_bubbles[0].position.y < opponent_bubbles[2].position.y, "对手侧保留到达顺序，自上而下堆叠")
		_check(opponent_bubbles[1].tail_direction == StreamerBubbleView.TailDirection.LEFT, "对手尾巴朝向主播内侧")
	await _capture("opponent_right")
	opponent_stack.clear_bubbles()
	for entry: BubbleDialogueEntry in player_lines:
		hud.call("show_dialogue_bubble", entry)
	for entry: BubbleDialogueEntry in opponent_lines:
		hud.call("show_dialogue_bubble", entry)
	await get_tree().create_timer(0.25).timeout
	player_bubbles = _get_bubbles(player_stack)
	opponent_bubbles = _get_bubbles(opponent_stack)
	_check(player_bubbles.size() == 3 and opponent_bubbles.size() == 3, "双方各三条气泡同时显示")
	await _capture("both_sides")
	await get_tree().create_timer(3.8).timeout
	player_bubbles = _get_bubbles(player_stack)
	opponent_bubbles = _get_bubbles(opponent_stack)
	_check(player_bubbles.size() == 3 and player_bubbles[0].modulate.a < 1.0, "玩家气泡到期前进入渐隐")
	_check(opponent_bubbles.size() == 3 and opponent_bubbles[0].modulate.a < 1.0, "对手气泡到期前进入渐隐")
	await get_tree().create_timer(0.7).timeout
	_check(_get_bubbles(player_stack).is_empty(), "玩家气泡在配置寿命后全部退出")
	_check(_get_bubbles(opponent_stack).is_empty(), "对手气泡在配置寿命后全部退出")
	print(
		"SD-02 GUI RESULT checks=%d failures=%d display=%s viewport=%s window=%s barrage_count=%d"
		% [_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size, DisplayServer.window_get_size(), barrage_count]
	)
	get_tree().quit(0 if _failures == 0 else 1)


# 临时对白只通过公开数据 Resource 造数，正式对白配置保持空白。
func _make_entry(side: int, line: String) -> BubbleDialogueEntry:
	var entry: BubbleDialogueEntry = EntryScript.new()
	entry.side = side
	entry.text = line
	entry.display_duration_seconds = 4.2
	return entry


# 只收集气泡场景节点，测试覆盖层活动数时不依赖实现私有数组。
func _get_bubbles(stack: StreamerBubbleStack) -> Array[StreamerBubbleView]:
	var bubbles: Array[StreamerBubbleView] = []
	for child: Node in stack.get_children():
		if child is StreamerBubbleView:
			bubbles.append(child)
	return bubbles


# 直接保存 Godot 实际渲染 Viewport，文件名记录本次窗口帧缓冲分辨率。
func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var client_size: Vector2i = DisplayServer.window_get_size()
	var evidence_directory: String = ProjectSettings.globalize_path("res://.godot/sd02")
	DirAccess.make_dir_recursive_absolute(evidence_directory)
	var filename: String = "sd02_%dx%d_%s.png" % [image.get_width(), image.get_height(), label]
	var screenshot_result: int = image.save_png(evidence_directory.path_join(filename))
	_check(
		screenshot_result == OK
			and image.get_width() == client_size.x
			and image.get_height() == client_size.y,
		"Godot 窗口 Viewport 截图 %s 图像=%s client=%s 逻辑Viewport=%s 保存状态=%d"
		% [label, image.get_size(), client_size, get_viewport_rect().size, screenshot_result]
	)


# 统一记录运行断言，任一实际行为失败会让 Godot 进程以非零退出。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
