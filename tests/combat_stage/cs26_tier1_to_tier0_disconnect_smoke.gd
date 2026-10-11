extends Control

const OPPONENT_IDLE: Texture2D = preload("res://assets/characters/opponents/alien/alien_idle.png")
const PRESENTATION_ASSETS: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const SCREENSHOT_DIRECTORY: String = "res://docs/8. CombatStage/evidence/cs26_2026-10-11"

var _checks: int = 0
var _failures: int = 0
var _completed_sequence_count: int = 0


# 使用正式 Sandbox 验收 T1→T0 对手离线、SD-03 清理和重新连线。
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().borderless = true
		get_window().min_size = Vector2i(1920, 1080)
		get_window().size = Vector2i(1920, 1080)
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit(2))
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var sandbox: Control = $Sandbox
	var hud: Control = sandbox.get_node("BattleHud") as Control
	var attempt_flow: BattleAttemptFlow = sandbox.call("get_battle_attempt_flow") as BattleAttemptFlow
	if hud == null or attempt_flow == null:
		_check(false, "正式 Sandbox 已装配 BattleHud 与 BattleAttemptFlow")
		_finish()
		return
	var barrage_area: BarrageArea = attempt_flow.get_barrage_area()
	var opponent_portrait: TextureRect = hud.find_child("OpponentPortraitArt", true, false) as TextureRect
	var state_label: Label = hud.find_child("BattleStateFeedback", true, false) as Label
	var opponent_stack: Node = hud.find_child("OpponentBubbleStack", true, false)
	if barrage_area == null or opponent_portrait == null or state_label == null or opponent_stack == null:
		_check(false, "正式 Sandbox 提供弹幕区、对手立绘、状态文案和对白栈")
		_finish()
		return
	var current_level: LevelProfile = attempt_flow.get_current_level_profile()
	if current_level == null:
		_check(false, "正式 Sandbox 提供当前关卡配置")
		_finish()
		return

	await get_tree().process_frame
	# 使用仓库已有待机图验收显示边界，不写入关卡素材映射。
	hud.call(
		"configure_streamer_assets",
		PRESENTATION_ASSETS.player_streamer_portrait,
		PRESENTATION_ASSETS.player_live_background,
		PRESENTATION_ASSETS.player_fan_badge,
		OPPONENT_IDLE,
		current_level.streamer_live_background,
		current_level.fan_badge_texture
	)
	hud.connect("dialogue_sequence_completed", Callable(self, "_on_dialogue_sequence_completed"))

	_check(attempt_flow.get_current_tier() == 0, "新战斗从 T0 开始")
	_check(state_label.text == "等待对手连线……", "新战斗显示 T0 匹配文案")
	_check(not opponent_portrait.is_visible_in_tree(), "T0 隐藏对手待机立绘")
	await _capture("cs26_t0_waiting")

	sandbox.call("debug_set_player_pk", 0.60)
	_check(attempt_flow.get_current_tier() == 1, "正式 CombatStage 进入 T1")
	_check(state_label.text == "对手已连线", "进入 T1 后显示已连线状态")
	_check(opponent_portrait.is_visible_in_tree(), "T1 显示当前对手待机立绘")
	var spawned_count: int = int(sandbox.call("debug_spawn_normal_batch"))
	await get_tree().process_frame
	var retained_barrage: BarrageView = _find_first_barrage(barrage_area)
	_check(spawned_count > 0 and retained_barrage != null, "T1 可生成并取得真实场上话语")
	if retained_barrage == null:
		_finish()
		return

	var first_entry: BubbleDialogueEntry = _make_plot_entry("离线前正在播放的对手对白", 60.0)
	var second_entry: BubbleDialogueEntry = _make_plot_entry("离线后不应继续播放的对白", 60.0)
	var entries: Array[BubbleDialogueEntry] = [first_entry, second_entry]
	var sequence_id: StringName = StringName(hud.call("enqueue_dialogue_sequence", entries, &"cs26_disconnect_sequence"))
	await get_tree().process_frame
	_check(not String(sequence_id).is_empty(), "T1 接受对手剧情对白序列")
	_check(_count_bubbles(opponent_stack) == 1, "SD-03 正在显示第一句对手剧情对白")
	_check(_completed_sequence_count == 0, "离线前剧情序列尚未完成")
	await _capture("cs26_t1_connected_with_dialogue")

	var barrage_position_before: Vector2 = retained_barrage.position
	hud.call("show_battle_state", "关键战斗警告：PK 正在下滑")
	sandbox.call("debug_set_player_pk", 0.50)
	_check(attempt_flow.get_current_tier() == 0, "正式 CombatStage 从 T1 降至 T0")
	_check(state_label.text == "等待对手连线……", "对手离线时匹配状态覆盖先前战斗提示")
	_check(not opponent_portrait.is_visible_in_tree(), "降至 T0 隐藏已连线对手立绘")
	_check(not bool(hud.call("enqueue_dialogue_bubble", _make_plot_entry("T0 对手不应接收新对白", 1.0))), "T0 拒绝新的对手对白事件")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_count_bubbles(opponent_stack) == 0, "对手离线清空当前活动气泡和待播序列")
	await _wait(0.35)
	_check(_completed_sequence_count == 0, "离线中断序列不会错误发出完成通知")
	_check(is_instance_valid(retained_barrage) and retained_barrage.is_visible_in_tree(), "降档保留原有场上话语")
	if is_instance_valid(retained_barrage):
		_check(not retained_barrage.position.is_equal_approx(barrage_position_before), "既有话语继续沿原运动自然回落")
	await _capture("cs26_t0_opponent_disconnected")

	sandbox.call("debug_set_player_pk", 0.60)
	_check(attempt_flow.get_current_tier() == 1, "对手离线后可以重新进入 T1")
	_check(state_label.text == "对手已连线", "重新连线恢复 T1 状态文案")
	_check(opponent_portrait.is_visible_in_tree(), "重新进入 T1 显示对手待机立绘")
	var reconnect_entries: Array[BubbleDialogueEntry] = [_make_plot_entry("重新连线后的对白", 60.0)]
	var reconnect_sequence_id: StringName = StringName(hud.call("enqueue_dialogue_sequence", reconnect_entries, &"cs26_reconnect_sequence"))
	_check(not String(reconnect_sequence_id).is_empty(), "重新连线后 SD-03 接受对手对白")
	await get_tree().process_frame
	_check(_count_bubbles(opponent_stack) == 1, "重新连线后可以继续显示新对白")
	await _capture("cs26_t1_reconnected")
	_finish()


# TEST_ONLY 剧情对白使用长时长，确保离线事件先结束展示再自然过期。
func _make_plot_entry(text: String, duration_seconds: float) -> BubbleDialogueEntry:
	var entry: BubbleDialogueEntry = BubbleDialogueEntry.new()
	entry.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	entry.text = text
	entry.display_duration_seconds = duration_seconds
	entry.priority = BubbleDialogueEntry.Priority.PLOT
	return entry


func _find_first_barrage(barrage_area: BarrageArea) -> BarrageView:
	for child: Node in barrage_area.get_children():
		if child is BarrageView and not child.is_queued_for_deletion():
			return child as BarrageView
	return null


func _count_bubbles(stack: Node) -> int:
	var count: int = 0
	for child: Node in stack.get_children():
		if child is StreamerBubbleView:
			count += 1
	return count


func _on_dialogue_sequence_completed(_sequence_id: StringName, _side: int) -> void:
	_completed_sequence_count += 1


# 等待运动与气泡节点处理真实帧，不直接改写目标状态。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# GUI 保存正式 Sandbox 视口；headless 仅运行状态与生命周期断言。
func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var evidence_directory: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(evidence_directory) != OK:
		_check(false, "创建 CS-26 GUI 证据目录")
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = evidence_directory.path_join(filename + ".png")
	_check(image.save_png(output_path) == OK, "保存 Godot GUI 截图 %s (%s)" % [filename, image.get_size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS CS-26: " + message)
	else:
		_failures += 1
		push_error("FAIL CS-26: " + message)


func _finish() -> void:
	print("CS-26 RESULT checks=%d failures=%d display=%s viewport=%s" % [
		_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size
	])
	get_tree().quit(0 if _failures == 0 else 1)
