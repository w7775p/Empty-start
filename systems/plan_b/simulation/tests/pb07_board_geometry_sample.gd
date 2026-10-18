extends Control

const BOARD_RECT: Rect2 = Rect2(Vector2(448.0, 72.0), Vector2(1024.0, 828.0))
const SAMPLE_SECONDS: float = 16.0
const UNIT_FIELD_SCRIPT: Script = preload("res://ui/plan_b/plan_b_unit_field.gd")

var _simulation: PlanBUnitSimulation
var _unit_field: Control
var _status_label: Label
var _elapsed_seconds: float = 0.0
var _sample_started_at_ms: int = 0

var _rendered_frames: int = 0
var _physics_frames: int = 0
var _ui_refresh_elapsed: float = 0.0
var _validation_elapsed: float = 0.0
var _player_seeded: bool = false
var _split_applied: bool = false
var _finished: bool = false
var _position_checks: int = 0
var _out_of_bounds_checks: int = 0
var _neutral_pick_checks: int = 0
var _neutral_pick_misses: int = 0
var _unit_click_checks: int = 0
var _unit_click_misses: int = 0
var _last_clicked_unit_id: String = ""
var _maximum_population_seen: int = 0
var _spawned_count: int = 0
var _despawned_count: int = 0
var _contact_counts: Dictionary = {}
var _change_counts: Dictionary = {}
var _recent_events: Array[String] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_physics_process(true)
	_create_board_preview()
	_create_simulation()
	call_deferred("_start_sample")


## 触发时序使用固定物理 tick，固定 seed 样例可逐次重放。
func _physics_process(delta: float) -> void:
	if _finished or _simulation == null or not _simulation.is_running():
		return
	_elapsed_seconds += delta
	_physics_frames += 1
	if not _split_applied and _elapsed_seconds >= 2.0:
		_apply_split_sample()
	if not _player_seeded and _elapsed_seconds >= 4.0:
		_seed_player_sample()
	if _elapsed_seconds >= SAMPLE_SECONDS:
		_finish_sample()


## 每帧将 B 的全局快照交给 D 的棋盘字段，验证两者共用同一个世界 Rect2。
func _process(delta: float) -> void:
	if _finished or _simulation == null or not _simulation.is_running():
		return
	_rendered_frames += 1
	_ui_refresh_elapsed += delta
	_validation_elapsed += delta
	if _ui_refresh_elapsed >= 0.10:
		_ui_refresh_elapsed = 0.0
		var snapshots: Array[Dictionary] = _simulation.get_unit_snapshots()
		_unit_field.call("set_unit_snapshots", snapshots)
		_maximum_population_seen = maxi(_maximum_population_seen, snapshots.size())
		if _validation_elapsed >= 0.50:
			_validation_elapsed = 0.0
			_validate_screen_positions(snapshots)
		_refresh_sample_status(snapshots)


## 使用 D 的正式棋盘字段绘制 1024×828 世界范围，世界位置来自 B 快照。
func _create_board_preview() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_unit_field = UNIT_FIELD_SCRIPT.new() as Control
	_unit_field.position = BOARD_RECT.position
	_unit_field.size = BOARD_RECT.size
	_unit_field.mouse_filter = Control.MOUSE_FILTER_STOP
	_unit_field.call("set_world_bounds", BOARD_RECT)
	_unit_field.call("set_density_profile", "clear")
	_unit_field.connect("unit_clicked", _on_unit_field_clicked)
	if _unit_field.get("world_bounds") != BOARD_RECT:
		_finish_with_error("D UnitField 未使用与 B 相同的全局 Rect2")
		return
	canvas.add_child(_unit_field)
	_status_label = Label.new()
	_status_label.position = BOARD_RECT.position + Vector2(18.0, 14.0)
	_status_label.custom_minimum_size = Vector2(900.0, 84.0)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	canvas.add_child(_status_label)


## 将棋盘根节点偏移后，再向 B 传全局 Rect2，检查其本地边界转换。
func _create_simulation() -> void:
	_simulation = PlanBUnitSimulation.new()
	_simulation.name = "Simulation"
	_simulation.position = BOARD_RECT.position
	add_child(_simulation)
	_simulation.unit_changed.connect(_on_unit_changed)
	_simulation.unit_spawned.connect(_on_unit_spawned)
	_simulation.unit_despawned.connect(_on_unit_despawned)
	_simulation.contact_resolved.connect(_on_contact_resolved)


## 固定随机流，按 76 中立 + 2 个开局播种位重放，再加入 split 和玩家发言样本。
func _start_sample() -> void:
	await get_tree().process_frame
	_simulation.set_random_seed(20261018)
	_simulation.maximum_population = 96
	_simulation.initial_neutral_count = 76
	_simulation.initial_seed_slot_count = 2
	_simulation.unit_collision_radius = 13.0
	_simulation.base_speed_min = 30.0
	_simulation.base_speed_max = 52.0
	_simulation.maximum_speed = 78.0
	_simulation.detection_radius = 220.0
	_simulation.collision_cooldown_seconds = 0.7
	_simulation.neutral_spawn_interval_seconds = 0.75
	_simulation.lifespan_min_seconds = 53.0
	_simulation.lifespan_max_seconds = 77.0
	if not _simulation.set_type_counter_map({"type_a": "type_b", "type_b": "type_c", "type_c": "type_a"}):
		_finish_with_error("无法注入 PB-07 TEST_ONLY 克制表")
		return
	if not _simulation.set_play_area(BOARD_RECT):
		_finish_with_error("B 拒绝 1024×828 全局棋盘 Rect2")
		return
	if _simulation.play_area != Rect2(Vector2.ZERO, BOARD_RECT.size):
		_finish_with_error("偏移后的模拟节点没有转换到局部 1024×828 碰撞边界")
		return
	var created_ids: Array[int] = _simulation.create_population()
	if created_ids.size() != 78:
		_finish_with_error("开局人口候选不是 76 中立 + 2 播种位")
		return
	if not _simulation.seed_unit(created_ids[76], &"opponent", _sample_word("fermi-a", "费米：我先占个位", "type_a", 1), 1):
		_finish_with_error("费米播种位 1 失败")
		return
	if not _simulation.seed_unit(created_ids[77], &"opponent", _sample_word("fermi-b", "费米：再来一位", "type_a", 1), 2):
		_finish_with_error("费米播种位 2 失败")
		return
	# 两名初始费米在棋盘内相邻出生，固定重现同阵营新话接力。
	_set_unit_global_position(created_ids[76], BOARD_RECT.position + Vector2(570.0, 410.0))
	_set_unit_global_position(created_ids[77], BOARD_RECT.position + Vector2(590.0, 410.0))
	_unit_field.call("set_selected_unit", str(created_ids[76]))
	var opening_counts: Dictionary = _simulation.get_faction_counts()
	if opening_counts != {"player": 0, "opponent": 2, "neutral": 76}:
		_finish_with_error("开局人数不是 76 中立 + 2 对手")
		return
	_sample_started_at_ms = Time.get_ticks_msec()
	_simulation.start_simulation()
	_record_visible_event("sample start · 76 neutral + 2 Fermi")
	var opening_snapshots: Array[Dictionary] = _simulation.get_unit_snapshots()
	_unit_field.call("set_unit_snapshots", opening_snapshots)
	_run_unit_click_sample(opening_snapshots[0])
	_refresh_sample_status(opening_snapshots)


## 开局分裂先作用于现存费米棋子，表现 C 配置的两个同话语跟随者。
func _apply_split_sample() -> void:
	var target_id: int = -1
	for snapshot: Dictionary in _simulation.get_unit_snapshots():
		if str(snapshot.get("team", "")) == "opponent":
			target_id = int(snapshot.get("unit_id", -1))
			break
	if target_id < 0:
		_finish_with_error("split 样例没有可用费米目标")
		return
	var request: Dictionary = {
		"skill_id": "alien_t3_split",
		"target_unit_id": str(target_id),
		"effect_id": &"split",
		"effect_parameters": {"child_count": 2},
	}
	_split_applied = _simulation.apply_counterattack_effect(request)
	if _split_applied:
		_unit_field.call("show_unit_feedback", str(target_id), "counterattack")
		_record_visible_event("Fermi split #%d · +2 followers" % target_id)
	else:
		_finish_with_error("split 反击样例没有生成子体")


## 中立目标和棋子中心均使用场景全局位置，验证 B 输入查询与 D 显示坐标相同。
func _seed_player_sample() -> void:
	var neutral_ids: Array[int] = _simulation.get_neutral_unit_ids()
	if neutral_ids.is_empty():
		_finish_with_error("玩家样例播种时已经没有中立观众")
		return
	var neutral_snapshot: Dictionary = _simulation.get_unit_snapshot(neutral_ids[0])
	var neutral_position: Vector2 = neutral_snapshot.get("position", Vector2.ZERO)
	if _simulation.get_neutral_unit_at(neutral_position) != neutral_ids[0]:
		_finish_with_error("snapshot 全局位置无法命中同一中立 unit_id")
		return
	_player_seeded = _simulation.seed_unit(
		neutral_ids[0], &"player", _sample_word("player-first", "煲煲：传播从这里开始", "type_c", 2), 3
	)
	if not _player_seeded:
		_finish_with_error("玩家样例播种失败")
		return
	_unit_field.call("set_selected_unit", str(neutral_ids[0]))
	_unit_field.call("show_unit_feedback", str(neutral_ids[0]), "seed")
	_record_visible_event("player seed #%d · sample word_order=3" % neutral_ids[0])


## 每半秒检查棋子完整碰撞半径始终落在同一个全局棋盘 Rect2 内。
func _validate_screen_positions(snapshots: Array[Dictionary]) -> void:
	var radius: float = _simulation.unit_collision_radius
	var minimum_position: Vector2 = BOARD_RECT.position + Vector2.ONE * radius
	var maximum_position: Vector2 = BOARD_RECT.end - Vector2.ONE * radius
	for snapshot: Dictionary in snapshots:
		_position_checks += 1
		var unit_position: Vector2 = snapshot.get("position", Vector2.ZERO)
		# Rect2.has_point excludes the right / bottom edge; collision clamping includes it.
		if (unit_position.x < minimum_position.x - 0.02 or unit_position.x > maximum_position.x + 0.02
				or unit_position.y < minimum_position.y - 0.02 or unit_position.y > maximum_position.y + 0.02):
			_out_of_bounds_checks += 1
	if _neutral_pick_checks > 0:
		return
	var checked_neutrals: int = 0
	for snapshot: Dictionary in snapshots:
		if str(snapshot.get("team", "")) != "neutral":
			continue
		var unit_id: int = int(snapshot.get("unit_id", -1))
		var unit_position: Vector2 = snapshot.get("position", Vector2.ZERO)
		_neutral_pick_checks += 1
		checked_neutrals += 1
		if _simulation.get_neutral_unit_at(unit_position) != unit_id:
			_neutral_pick_misses += 1
		if checked_neutrals >= 12:
			break


func _refresh_sample_status(snapshots: Array[Dictionary]) -> void:
	_maximum_population_seen = maxi(_maximum_population_seen, snapshots.size())
	var counts: Dictionary = _simulation.get_faction_counts()
	var intent_counts: Dictionary = {"wander": 0, "chase": 0, "flee": 0}
	for snapshot: Dictionary in snapshots:
		var intent: String = str(snapshot.get("motion_intent", "wander"))
		intent_counts[intent] = int(intent_counts.get(intent, 0)) + 1
	var total_contact_count: int = 0
	for outcome: Variant in _contact_counts.keys():
		total_contact_count += int(_contact_counts[outcome])
	_status_label.text = "PB-07 TEST_ONLY board 1024×828 · global Rect2(448,72,1024,828)\n" \
		+ "player %d · Fermi %d · neutral %d · total %d/96 · radius %.0f px" % [
			int(counts.get("player", 0)), int(counts.get("opponent", 0)),
			int(counts.get("neutral", 0)), snapshots.size(), _simulation.unit_collision_radius,
		] + "\n" \
		+ "contacts %d · relay %d · convert %d · split %s · spawn %d · despawn %d" % [
			total_contact_count, int(_change_counts.get("relay", 0)),
			int(_change_counts.get("convert", 0)), "yes" if _split_applied else "pending",
			_spawned_count, _despawned_count,
		] + "\n" \
		+ "motion wander %d / chase %d / flee %d · out of bounds %d" % [
			int(intent_counts.get("wander", 0)), int(intent_counts.get("chase", 0)),
			int(intent_counts.get("flee", 0)), _out_of_bounds_checks,
		] + "\n" + "\n".join(_recent_events.slice(0, 3))


## 样例结束时输出人口、碰撞和坐标观测，便于 A/D/E 复现当前参数。
func _finish_sample() -> void:
	if _finished:
		return
	_finished = true
	_simulation.pause_simulation()
	var counts: Dictionary = _simulation.get_faction_counts()
	var final_snapshots: Array[Dictionary] = _simulation.get_unit_snapshots()
	var wall_seconds: float = maxf(float(Time.get_ticks_msec() - _sample_started_at_ms) / 1000.0, 0.001)
	var average_fps: float = float(_rendered_frames) / wall_seconds
	var total_contact_count: int = 0
	for outcome: Variant in _contact_counts.keys():
		total_contact_count += int(_contact_counts[outcome])
	var passed: bool = (
		final_snapshots.size() >= 80 and final_snapshots.size() <= 96
		and _maximum_population_seen <= 96 and _out_of_bounds_checks == 0
		and _neutral_pick_misses == 0 and _unit_click_checks > 0 and _unit_click_misses == 0
		and total_contact_count > 0
		and _player_seeded and _split_applied
	)
	var summary := "PB07_TEST_ONLY_GEOMETRY_%s · player=%d · opponent=%d · neutral=%d · total=%d\n" % [
		"PASS" if passed else "FAIL",
		int(counts.get("player", 0)), int(counts.get("opponent", 0)),
		int(counts.get("neutral", 0)), final_snapshots.size(),
	]
	summary += "Rect2=%s · radius=%.0f · speed=%.0f-%.0f · max=%.0f · detect=%.0f · cooldown=%.2f\n" % [
		str(BOARD_RECT), _simulation.unit_collision_radius,
		_simulation.base_speed_min, _simulation.base_speed_max,
		_simulation.maximum_speed, _simulation.detection_radius,
		_simulation.collision_cooldown_seconds,
	]
	summary += "simulated=%.1fs physics=%d contacts=%d (%.2f/s) · outcomes=%s · changed=%s · spawned=%d · despawned=%d · positions=%d/%d_oob · B_pick=%d/%d_misses · D_click=%d/%d_misses · wall=%.1fs draw=%d · fps_avg=%.1f/end=%.1f\n" % [
		_elapsed_seconds, _physics_frames,
		total_contact_count, float(total_contact_count) / maxf(_elapsed_seconds, 0.001),
		str(_contact_counts), str(_change_counts),
		_spawned_count, _despawned_count, _position_checks,
		_out_of_bounds_checks, _neutral_pick_checks, _neutral_pick_misses,
		_unit_click_checks, _unit_click_misses,
		wall_seconds, _rendered_frames, average_fps,
		Engine.get_frames_per_second(),
	]
	print(summary)
	_status_label.text = summary
	if not passed:
		push_error("PB07 geometry sample did not satisfy the board-position/population checks.")
	call_deferred("_quit_after_preview", 0 if passed else 1)


func _quit_after_preview(exit_code: int) -> void:
	await get_tree().create_timer(2.0).timeout
	get_tree().quit(exit_code)


func _finish_with_error(message: String) -> void:
	push_error("PB07 geometry sample: " + message)
	_finished = true
	call_deferred("_quit_after_preview", 1)


func _sample_word(word_id: String, text: String, battle_type: String, strength: int) -> Dictionary:
	return {
		"word_id": word_id,
		"text": text,
		"battle_type": battle_type,
		"strength": strength,
		"traits": [],
		"tendency": "neutral",
		"available_level": "level_001",
	}


func _set_unit_global_position(unit_id: int, scene_position: Vector2) -> void:
	for child: Node in _simulation.get_children():
		var unit := child as PlanBUnit
		if unit != null and unit.unit_id == unit_id:
			unit.global_position = scene_position
			return


## 以 B 快照的全局位置驱动 Viewport 鼠标事件，检查 D 的公开点击信号返回同一 ID。
func _run_unit_click_sample(snapshot: Dictionary) -> void:
	var expected_unit_id := str(snapshot.get("unit_id", ""))
	var world_position: Vector2 = snapshot.get("position", Vector2.ZERO)
	var field_position := _sample_world_to_field_local(world_position)
	var viewport_position: Vector2 = _unit_field.get_global_transform_with_canvas() * field_position
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = viewport_position
	_last_clicked_unit_id = ""
	get_viewport().push_input(event, true)
	_unit_click_checks += 1
	if _last_clicked_unit_id != expected_unit_id:
		_unit_click_misses += 1
	else:
		_unit_field.call("set_selected_unit", expected_unit_id)


## 按棋盘 Rect2 与控件可用尺寸计算样例点击点，覆盖 D 的等比居中显示区域。
func _sample_world_to_field_local(world_position: Vector2) -> Vector2:
	var available := Rect2(Vector2(16.0, 16.0), _unit_field.size - Vector2(32.0, 32.0))
	var world_ratio: float = BOARD_RECT.size.x / BOARD_RECT.size.y
	var arena_width: float = available.size.x
	var arena_height: float = arena_width / world_ratio
	if arena_height > available.size.y:
		arena_height = available.size.y
		arena_width = arena_height * world_ratio
	var arena_position := available.position + (available.size - Vector2(arena_width, arena_height)) * 0.5
	var relative_position := Vector2(
		(world_position.x - BOARD_RECT.position.x) / BOARD_RECT.size.x,
		(world_position.y - BOARD_RECT.position.y) / BOARD_RECT.size.y
	)
	return arena_position + Vector2(relative_position.x * arena_width, relative_position.y * arena_height)


func _on_unit_field_clicked(unit_id: String, _team: String) -> void:
	_last_clicked_unit_id = unit_id


func _on_unit_changed(unit_id: int, reason: StringName) -> void:
	var key: String = str(reason)
	_change_counts[key] = int(_change_counts.get(key, 0)) + 1
	_unit_field.call("show_unit_feedback", str(unit_id), key)
	_record_visible_event("unit %d %s" % [unit_id, key])


func _on_unit_spawned(unit_id: int) -> void:
	_spawned_count += 1
	_record_visible_event("spawn %d" % unit_id)


func _on_unit_despawned(unit_id: int) -> void:
	_despawned_count += 1
	_record_visible_event("despawn %d" % unit_id)


func _on_contact_resolved(first_unit_id: int, second_unit_id: int, outcome: StringName) -> void:
	var key: String = str(outcome)
	_contact_counts[key] = int(_contact_counts.get(key, 0)) + 1
	_unit_field.call("show_contact_feedback", str(first_unit_id), str(second_unit_id), key)
	if outcome == &"converted" or outcome == &"same_team_bounce" or outcome == &"same_type_bounce":
		_record_visible_event("contact %d/%d %s" % [first_unit_id, second_unit_id, key])


func _record_visible_event(message: String) -> void:
	_recent_events.push_front(message)
	while _recent_events.size() > 3:
		_recent_events.pop_back()
