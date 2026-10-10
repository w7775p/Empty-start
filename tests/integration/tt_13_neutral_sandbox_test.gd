extends Node

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")

var _sandbox: Control
var _area: BarrageArea
var _aim: AimReticle
var _attack: AttackChargeInput
var _submission: Dictionary = {}
var _mouse_position: Vector2
var _failures: Array[String] = []


# 用真实 Sandbox、鼠标事件和复读调度验收 neutral 的一条完整普通战斗链。
func _ready() -> void:
	SaveManager.new_game()
	var speech: LevelSpeech = LevelSpeech.new()
	speech.original_sentence_id = "tt13-neutral-live"
	speech.text = "今天聊聊生活"
	speech.tendency_id = "neutral"
	speech.strength = 1
	var level: LevelProfile = LevelProfile.new()
	level.level_id = "tt13-neutral-level"
	level.streamer_id = "tt13-streamer"
	level.streamer_name = "闲聊主播"
	level.normal_speech_pool = [speech]
	level.neutral_ratio = 1.0
	level.base_batch_count = 0
	level.base_spawn_interval_seconds = 60.0
	level.base_move_speed_pixels_per_second = 0.0
	var catalog: LevelCatalog = LevelCatalog.new()
	catalog.profiles = [level]
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set("level_catalog", catalog)
	add_child(_sandbox)
	await get_tree().process_frame
	await get_tree().process_frame
	_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_aim = _sandbox.get_node("%AimReticle") as AimReticle
	_attack = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_attack.shot_hit_resolution_submitted.connect(func(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void: _submission = submission)

	# 此入口负责跨系统命中链；选择器配置的纯逻辑由所属系统测试负责。
	var view: BarrageView = _area.spawn_normal_barrage(level, speech)
	_check(view != null and view.runtime_record.tendency_id == "neutral" and is_equal_approx(view.runtime_record.strength, 1.0), "neutral 使用普通弹幕及内容强度")
	if view != null:
		view.position = Vector2(_area.size.x * 0.65, _area.size.y * 0.38)
		_aim_at(view)
		_mouse_button(true)
		await get_tree().create_timer(0.24).timeout
		_aim_at(view)
		_mouse_button(false)
		await get_tree().create_timer(0.2).timeout

	var hit: HitResolution = _sandbox.get_battle_attempt_flow().get_hit_resolution()
	var history: Array[Dictionary] = hit.get_normal_hit_history()
	var results: Array = _submission.get("hit_resolution_result", {}).get("target_results", [])
	_check(hit.get_player_pk() > 0.5 and history.size() == 1 and str(history[0].get("tendency", "")) == "neutral", "neutral 命中增加 PK 并进入普通历史")
	_check(results.size() == 1 and str(results[0].get("tendency_id", "")) == "neutral" and int(results[0].get("tendency_delta", -1)) == 0, "neutral 结算事实保留类别且倾向增量为零")
	var state: TendencyState = SaveManager.data.tendency_state
	_check(state.attempt_orthodox_total == 0 and state.attempt_heretical_total == 0 and state.attempt_absurd_total == 0 and state.has_no_effective_behavior(), "只命中 neutral 保持三项全零")
	var queue: RepeatDelayQueue = _sandbox.get_battle_attempt_flow().get_repeat_queue()
	var comments_before_repeat: int = SaveManager.data.live_session.comment_count
	queue.advance_and_dispatch(3.1, _area)
	var neutral_repeat_found: bool = false
	for child: Node in _area.get_children():
		if child is BarrageView:
			var repeat_view := child as BarrageView
			if repeat_view.runtime_record.is_repeat and repeat_view.runtime_record.original_sentence_id == speech.original_sentence_id and repeat_view.runtime_record.tendency_id == "neutral":
				neutral_repeat_found = true
	_check(neutral_repeat_found and queue.get_generation_stats().get_normal_count(&"tt13-neutral-live") > 0, "neutral 复读保留原句和类别并实际生成")
	_check(SaveManager.data.live_session.comment_count > comments_before_repeat, "neutral 复读沿用直播评论表现")

	_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("PASS TT-13 Sandbox: neutral generated, hit, repeated, recorded without tendency")
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			printerr("FAIL TT-13 Sandbox: " + failure)
		get_tree().quit(1)


func _aim_at(target: BarrageView) -> void:
	_mouse_position = target.get_global_rect().get_center()
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim.get_canvas_transform() * _mouse_position)
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse_button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim.get_canvas_transform() * _mouse_position)
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
