extends Node

const HUD_SCENE = preload("res://ui/live_data/live_data_hud.tscn")
const BATTLE_SCENE = preload("res://scenes/sandbox/sandbox.tscn")
const METRICS = ["ViewerMetric", "LikeMetric", "CommentMetric", "FanMetric"]
var _failed: bool = false


# 使用真实控件和正式战斗场景验证显示入口，测试值仅存在于本次进程。
func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_title("LD-11 HUD smoke")
	var preview = HUD_SCENE.instantiate()
	preview.auto_bind_player_session = false
	preview.set_values(999, 1000, 1100, 12500)
	add_child(preview)
	_check_metrics(preview, ["999", "1.0k", "1.1k", "12.5k"], "入树前展示输入")
	preview.queue_free()
	await get_tree().process_frame
	var battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	await get_tree().process_frame
	var left = battle.get_node("BattleHud/PlayerStreamerArea/LiveDataHud")
	var right = battle.get_node("BattleHud/OpponentStreamerArea/OpponentLiveDataHud")
	var session: LiveSessionData = SaveManager.data.live_session
	# 暂停战斗推进，防止正常弹幕生成改变本次显示检查的评论数。
	battle.process_mode = Node.PROCESS_MODE_DISABLED
	for sample in [[0, "0"], [999, "999"], [1000, "1.0k"], [1100, "1.1k"], [12500, "12.5k"]]:
		var value: int = sample[0]
		var text: String = sample[1]
		session.viewer_count = value
		session.like_count = value
		session.comment_count = value
		session.fan_count = value
		right.set_values(value, value, value, value)
		_check_metrics(left, [text, text, text, text], "绑定数据 %d" % value)
		_check_metrics(right, [text, text, text, text], "显式数据 %d" % value)
		_check(session.viewer_count == value and session.like_count == value
			and session.comment_count == value and session.fan_count == value, "数据源保留整数 %d" % value)
		print("LD11_SAMPLE %d -> %s (all four, both sides)" % [value, text])
	# 混合数值与含数字的 BBCode 图标，确保排版完全不解析可见文字。
	right.set_values(999, 1000, 1100, 12500)
	right.display_side = 0
	right.viewer_icon = "[b]V7[/b]"
	right.like_icon = "[b]L8[/b]"
	right.comment_icon = "[b]C9[/b]"
	right.fan_icon = "[b]F6[/b]"
	_check_metrics(right, ["999", "1.0k", "1.1k", "12.5k"], "换方向与四项图标")
	right.display_side = 1
	_check_metrics(right, ["999", "1.0k", "1.1k", "12.5k"], "恢复右侧")
	right.viewer_icon = "👤"
	right.like_icon = "👍"
	right.comment_icon = "🔊"
	right.fan_icon = "👥"
	# 重新绑定后旧 Resource 的 changed 必须失效；解绑继续清零。
	var replacement := LiveSessionData.new()
	replacement.viewer_count = 1000
	replacement.like_count = 1100
	replacement.comment_count = 12500
	replacement.fan_count = 999
	left.bind_live_session(replacement)
	session.viewer_count = 77
	_check_metrics(left, ["1.0k", "1.1k", "12.5k", "999"], "替换数据源")
	left.display_side = 1
	left.display_side = 0
	_check_metrics(left, ["1.0k", "1.1k", "12.5k", "999"], "绑定方向切换")
	left.bind_live_session(null)
	_check_metrics(left, ["0", "0", "0", "0"], "显式解绑")
	left.bind_live_session(replacement)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	print("LD11_HUD_SMOKE_%s" % ("FAIL" if _failed else "PASS"))
	# GUI 验收保留窗口，供人工检查；无参数时直接以明确退出码结束。
	if "--gui-review" in OS.get_cmdline_user_args():
		# 保存当前实际渲染的视口，便于检查被桌面浮窗遮住的区域。
		get_viewport().get_texture().get_image().save_png("res://.godot/ld11/hud-gui.png")
		await get_tree().create_timer(45.0).timeout
	get_tree().quit(1 if _failed else 0)


# 只检查可见文本和左右对齐，不断言 HUD 的私有缓存。
func _check_metrics(hud, numbers: Array, context: String) -> void:
	var icons: Array = [hud.viewer_icon, hud.like_icon, hud.comment_icon, hud.fan_icon]
	for index in range(4):
		var metric: RichTextLabel = hud.get_node("Metrics/" + METRICS[index])
		var expected: String = numbers[index] + icons[index] if hud.display_side == 1 else icons[index] + numbers[index]
		_check(metric.text == expected, "%s %s: %s" % [context, METRICS[index], metric.text])
		_check(metric.horizontal_alignment == (HORIZONTAL_ALIGNMENT_RIGHT if hud.display_side == 1 else HORIZONTAL_ALIGNMENT_LEFT), context + " 对齐")


# 汇总失败并让场景最终返回非零退出码。
func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("LD11_FAIL " + message)
