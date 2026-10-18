extends Control

## PB-09 可见预览：复用真实 Host、Simulation 与 Catalog，窗口逻辑画布固定为 1920×1080。

const BATTLE_HOST_SCRIPT: Script = preload("res://systems/plan_b/battle/plan_b_battle_host.gd")
const UNIT_SIMULATION_SCRIPT: Script = preload("res://systems/plan_b/simulation/plan_b_unit_simulation.gd")
const CONTENT_CATALOG_SCRIPT: Script = preload("res://systems/plan_b/content/plan_b_content_catalog.gd")
const OPPONENT_DIRECTOR_SCRIPT: Script = preload("res://systems/plan_b/opponent/fermi_opponent_director.gd")
const BATTLE_UI_SCENE: PackedScene = preload("res://ui/plan_b/plan_b_battle_ui.tscn")
const BOARD_BOUNDS := Rect2(Vector2(448.0, 72.0), Vector2(1024.0, 828.0))

@export var review_window_size := Vector2i(1152, 648)
@export var review_content_size := Vector2i(1920, 1080)
@export var normal_capture_path := ""
@export var paradox_capture_path := ""
@export var quit_after_capture := false
@export var quit_after_sample := false

var _battle_ui: Control
var _battle_host: Object
var _unit_simulation: Object
var _sample_elapsed := 0.0
var _sample_frames := 0
var _sample_contacts := 0
var _sample_reported := false


func _ready() -> void:
	# 预览使用独立的窗口尺寸；正式窗口与导出设置由 E 管理。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_window().size = review_window_size
	get_window().content_scale_size = review_content_size
	get_window().title = "PB-09 · 复读感染 · %d×%d" % [review_window_size.x, review_window_size.y]

	_battle_host = BATTLE_HOST_SCRIPT.new()
	_unit_simulation = UNIT_SIMULATION_SCRIPT.new()
	var battle_host = _battle_host
	var unit_simulation = _unit_simulation
	unit_simulation.name = "Simulation"
	battle_host.add_child(unit_simulation)
	add_child(battle_host)
	unit_simulation.call("set_random_seed", 20261018)

	var content_catalog = CONTENT_CATALOG_SCRIPT.new()
	var opponent_director = OPPONENT_DIRECTOR_SCRIPT.new()
	var configured := bool(battle_host.call("configure_modules", unit_simulation, content_catalog, opponent_director))
	if not configured:
		push_error("PB-09 预览模块配置失败。")
		return

	_battle_ui = BATTLE_UI_SCENE.instantiate()
	var battle_ui := _battle_ui
	battle_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_ui)
	battle_ui.call("set_world_bounds", BOARD_BOUNDS)
	battle_ui.call("set_review_source_label", "PB-09 · 真实 A/B/C 接线预览")
	battle_ui.call("configure_streamers", "煲煲", "费米")
	battle_ui.call("configure_fan_group_names", "煲煲粉丝团", "费米粉丝团")
	battle_ui.call("bind_sources", battle_host, unit_simulation, content_catalog)
	battle_ui.call("set_word_definitions", battle_host.call("get_word_definitions", "player"))
	battle_ui.call("set_published_word_ids", battle_host.call("get_used_word_ids"))
	battle_ui.call("set_publish_cooldown_remaining", battle_host.call("get_publish_cooldown_remaining", "player"))
	battle_ui.call("set_battle_tier", battle_host.call("get_current_tier"))
	battle_ui.call("set_opponent_portrait_connected", true)
	_connect_player_hand(battle_ui, battle_host, content_catalog)
	battle_ui.connect("publish_requested", Callable(self, "_on_publish_requested").bind(battle_ui, battle_host, content_catalog))
	_connect_live_data(battle_ui)
	_connect_preview_signals(battle_ui, battle_host, unit_simulation)
	print("PB09_BOARD_BOUNDS=", battle_ui.call("get_board_world_bounds"))
	_report_board_layout.call_deferred()
	battle_host.call_deferred("start_battle", BOARD_BOUNDS.size, BOARD_BOUNDS.position)
	_show_preview_bubbles.call_deferred()
	_capture_evidence_sequence.call_deferred()


func _report_board_layout() -> void:
	await get_tree().process_frame
	print("PB09_LAYOUT_BOUNDS=", _battle_ui.call("get_board_world_bounds"))


func _process(delta: float) -> void:
	if _sample_reported:
		return
	_sample_elapsed += delta
	_sample_frames += 1
	if _sample_elapsed < 16.0:
		return
	_sample_reported = true
	var snapshots: Variant = _battle_host.call("get_unit_snapshots") if _battle_host != null else []
	var unit_count: int = snapshots.size() if snapshots is Array else 0
	var average_fps := float(_sample_frames) / maxf(_sample_elapsed, 0.001)
	print("PB09_RUNTIME_SAMPLE seconds=%.1f average_fps=%.1f units=%d contacts=%d" % [
		_sample_elapsed, average_fps, unit_count, _sample_contacts
	])
	if quit_after_sample:
		get_tree().quit()


func _on_contact_resolved(_first_unit_id: Variant, _second_unit_id: Variant, _outcome: StringName) -> void:
	_sample_contacts += 1


func _show_preview_bubbles() -> void:
	var player_bubble := BubbleDialogueEntry.new()
	player_bubble.side = BubbleDialogueEntry.SpeakerSide.PLAYER
	player_bubble.event_id = &"pb09_preview_player"
	player_bubble.text = "看我这句，带中立观众一起改口。"
	player_bubble.display_duration_seconds = 25.0
	var opponent_bubble := BubbleDialogueEntry.new()
	opponent_bubble.side = BubbleDialogueEntry.SpeakerSide.OPPONENT
	opponent_bubble.event_id = &"pb09_preview_opponent"
	opponent_bubble.text = "费米观众正在盯着场内变化。"
	opponent_bubble.display_duration_seconds = 25.0
	_battle_ui.call("show_dialogue_bubble", player_bubble)
	_battle_ui.call("show_dialogue_bubble", opponent_bubble)


func _capture_evidence_sequence() -> void:
	if not normal_capture_path.is_empty():
		# 预览等真实 B 场地补满 96 个单位后取图，避免用低人口画面代替验收状态。
		for _wait_index in range(80):
			var snapshots: Variant = _battle_host.call("get_unit_snapshots")
			if snapshots is Array and snapshots.size() >= 96:
				break
			await get_tree().create_timer(0.25).timeout
		var final_snapshots: Variant = _battle_host.call("get_unit_snapshots")
		print("PB09_EVIDENCE_POPULATION=", final_snapshots.size() if final_snapshots is Array else 0)
		await _save_window_capture(normal_capture_path)
	if paradox_capture_path.is_empty():
		return
	# 仅预览脚本锁住高 Tier 视觉事实；正式 Tier 仍由 Host 流程拥有。
	_battle_host.set_process(false)
	_battle_host.set("_pk", 0.99)
	_battle_host.set("_current_tier", 5)
	_battle_ui.call("set_battle_tier", 5)
	_battle_ui.call("play_tier_breakthrough", 0, 5)
	await get_tree().create_timer(1.3).timeout
	_battle_ui.call("set_paradox_stage_active", true, 5)
	_battle_ui.call("move_touch_aim", BOARD_BOUNDS.get_center(), 144.0)
	_battle_ui.call("refresh_attack", 0.68, 1)
	_battle_ui.call("show_battle_state", "矛盾阶段 · 蓄力射击")
	await get_tree().create_timer(0.45).timeout
	await _save_window_capture(paradox_capture_path)
	_battle_ui.call("set_paradox_stage_active", false, 5)
	_battle_ui.call("set_final_oracle_stage_active", true)
	await get_tree().process_frame
	print("PB09_FINAL_ORACLE_BOUNDS=", _battle_ui.call("get_board_world_bounds"))
	_battle_ui.call("set_final_oracle_stage_active", false)
	if quit_after_capture:
		get_tree().quit()


func _save_window_capture(relative_path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_window().get_texture().get_image()
	var absolute_path := ProjectSettings.globalize_path(relative_path)
	var directory := absolute_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(directory)
	var error := image.save_png(absolute_path)
	print("PB09_CAPTURE path=%s size=%s error=%s" % [relative_path, image.get_size(), error])


func _connect_live_data(battle_ui: Control) -> void:
	var player_session := LiveSessionData.new()
	player_session.viewer_count = 12800
	player_session.like_count = 17400
	player_session.comment_count = 3650
	player_session.fan_count = 61200
	battle_ui.call("bind_player_live_session", player_session)

	var opponent_session := LiveSessionData.new()
	opponent_session.viewer_count = 9630
	opponent_session.like_count = 7200
	opponent_session.comment_count = 2180
	opponent_session.fan_count = 43800
	battle_ui.call("bind_opponent_live_session", opponent_session)

	var comments: Array[Dictionary] = [
		{"viewer": {"display_name": "煲煲守夜人", "audience_type": "fan"}, "text": "这波播种稳了", "weight": 3.0},
		{"viewer": {"display_name": "路过的鱼", "audience_type": "visitor"}, "text": "中立观众要改口了吗", "weight": 2.0},
		{"viewer": {"display_name": "费米同学", "audience_type": "fan"}, "text": "我方反击快好了", "weight": 1.0},
	]
	var comment_parameters := {
		"comment_spawn_interval_min_s": 1.4,
		"comment_spawn_interval_max_s": 2.4,
		"comment_visible_row_cap": 5,
		"comment_font_size_px": 18,
		"comment_row_spacing_px": 6,
		"comment_fan_probability": 0.45,
	}
	battle_ui.call("configure_player_formal_comments", comments, comment_parameters)
	battle_ui.call("configure_opponent_formal_comments", comments, comment_parameters)


func _connect_preview_signals(battle_ui: Control, battle_host: Object, unit_simulation: Object) -> void:
	if battle_host.has_signal("counterattack_windup_started"):
		battle_host.connect("counterattack_windup_started", Callable(battle_ui, "show_counterattack_windup"))
	if battle_host.has_signal("counterattack_resolved"):
		battle_host.connect("counterattack_resolved", Callable(battle_ui, "show_counterattack_result"))
	if unit_simulation.has_signal("contact_resolved"):
		unit_simulation.connect("contact_resolved", Callable(self, "_on_contact_resolved"))


func _connect_player_hand(battle_ui: Control, battle_host: Object, content_catalog: Object) -> void:
	# PB-08 C 提供抽取补位 API 时预览直接消费；旧目录继续使用 D 的四词条回退。
	if content_catalog.has_method("get_player_hand"):
		var hand: Array = content_catalog.call("get_player_hand")
		battle_ui.call("set_word_hand", hand, _get_hand_remaining_count(content_catalog, battle_host, hand))
	if content_catalog.has_signal("player_hand_changed"):
		content_catalog.connect("player_hand_changed", Callable(self, "_on_player_hand_changed").bind(battle_ui, battle_host, content_catalog))


func _get_hand_remaining_count(content_catalog: Object, battle_host: Object, hand: Array) -> int:
	if not content_catalog.has_method("get_available_word_ids"):
		return 0
	var available: Variant = content_catalog.call("get_available_word_ids", "player", battle_host.call("get_used_word_ids"))
	return maxi(0, available.size() - hand.size()) if available is Array else 0


func _on_player_hand_changed(hand: Array, battle_ui: Control, battle_host: Object, content_catalog: Object) -> void:
	battle_ui.call("set_word_hand", hand, _get_hand_remaining_count(content_catalog, battle_host, hand))


func _on_publish_requested(word_id: String, unit_id: String, battle_ui: Control, battle_host: Object, content_catalog: Object) -> void:
	var result: Variant = battle_host.call("publish_word", "player", word_id, unit_id)
	if result is Dictionary and bool(result.get("ok", false)) and content_catalog.has_method("consume_player_hand_word"):
		content_catalog.call("consume_player_hand_word", word_id, battle_host.call("get_used_word_ids"))
	battle_ui.call("resolve_publish_request", word_id, unit_id, result)
