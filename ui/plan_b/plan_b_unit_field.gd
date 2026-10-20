extends Control

signal unit_clicked(unit_id: String, team: String)
signal empty_field_clicked
signal board_position_clicked(spawn_position: Vector2)

const PB14_PERFORMANCE_TRACKER_SCRIPT: Script = preload("res://systems/plan_b/performance/pb14_performance_tracker.gd")

const TEAM_COLORS := {
	"neutral": Color("#92a2ad"),
	"player": Color("#50c7ff"),
	"opponent": Color("#ff9f68"),
}
const TENDENCY_COLORS := {
	"orthodox": Color("#62d3ab"),
	"heretical": Color("#c49aff"),
	"heresy": Color("#c49aff"),
	"absurd": Color("#ffd477"),
	"neutral": Color("#94a3b8"),
}
const UNIT_VISUAL_RADIUS: float = 32.0
const TYPE_ICON_STONE: Texture2D = preload("res://assets/ui/plan_b/battle_type/ui_PK_shitou.png")
const TYPE_ICON_SCISSORS: Texture2D = preload("res://assets/ui/plan_b/battle_type/ui_PK_jiandao.png")
const TYPE_ICON_PAPER: Texture2D = preload("res://assets/ui/plan_b/battle_type/ui_PK_bu.png")

var world_bounds := Rect2(Vector2.ZERO, Vector2(900.0, 490.0))

var _snapshots: Array = []
var _performance_tracker: Node
var _snapshots_by_id: Dictionary = {}
var _frame_unit_centers: Dictionary = {}
var _word_texts: Dictionary = {}
var _unit_sprite_textures: Dictionary = {}
var _active_opponent_sprite_id := "alien"
var _word_groups: Array = []
var _active_group_bubble_ids: Dictionary = {}
var _group_bubble_layouts: Dictionary = {}
var _group_bubble_styles: Dictionary = {}
var _word_group_signature := ""
var _selected_unit_id := ""
var _hovered_unit_id := ""
var _unit_layer_visible := true
var _feedback_pulses: Dictionary = {}
var _previous_points: Dictionary = {}
var _physics_unit_ids := PackedInt32Array()
var _physics_previous_positions := PackedVector2Array()
var _physics_current_positions := PackedVector2Array()
var _physics_position_index_by_unit_id: Dictionary = {}
var _physics_position_index_dirty := true
var _render_interpolation_fraction := 0.0
var _movement_segments: Dictionary = {}
var _contact_feedback: Array[Dictionary] = []
var _word_batch_bursts: Array[Dictionary] = []
var _counterable_unit_ids: Dictionary = {}
var _rephrase_feedback: Dictionary = {}
var _last_drawn_group_bubbles: int = 0
var _last_group_tail_candidates: int = 0
var _tracker_group_layout_cache_hits: int = 0


## 三倾向颜色由卡牌与棋子共用；阵营色继续由 TEAM_COLORS 独立表达。
static func get_tendency_color(tendency_id: String) -> Color:
	return TENDENCY_COLORS.get(tendency_id, TENDENCY_COLORS["neutral"])


## 将内部 battle_type 映射到玩家能直接理解的话语名称。
static func get_battle_type_name(battle_type: String) -> String:
	match battle_type:
		"type_a":
			return "铁拳布道"
		"type_b":
			return "断章取义"
		"type_c":
			return "博爱包容"
		_:
			return "话语"


## 缺少 Emoji 字形时，卡牌用同义文字代替；棋盘棋子使用原生线条徽标。
static func get_battle_type_fallback_mark(battle_type: String) -> String:
	match battle_type:
		"type_a":
			return "石"
		"type_b":
			return "剪"
		"type_c":
			return "布"
		_:
			return "·"

func _ready() -> void:
	# 场地只消费只读快照；鼠标和触控按有效棋盘区域提交坐标，不按头像尺寸改动发表规则。
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 512px头像缩放到64px时使用线性过滤，保持边缘平滑。
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	theme_changed.connect(_on_theme_changed)
	queue_redraw()


# 主题字体更换后清除缓存；下一次布局读取新字体实际字宽。
func _on_theme_changed() -> void:
	_group_bubble_layouts.clear()
	queue_redraw()


## D 只在 A 显式启用 PB14 Tracker 时接收观测器。
func set_performance_tracker(tracker: Node) -> void:
	_performance_tracker = tracker if is_instance_valid(tracker) else null


func set_world_bounds(bounds: Rect2) -> void:
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		world_bounds = bounds
	queue_redraw()


func set_unit_snapshots(snapshots: Array) -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	if not _unit_layer_visible:
		_snapshots.clear()
		_snapshots_by_id.clear()
		for value in snapshots:
			if value is Dictionary:
				_snapshots.append(value)
				var unit_id := str(value.get("unit_id", ""))
				if not unit_id.is_empty():
					_snapshots_by_id[unit_id] = value
		_previous_points.clear()
		_movement_segments.clear()
		if _performance_tracker != null:
			_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UI_UNIT_SNAPSHOT, Time.get_ticks_usec() - tracker_start_usec, snapshots.size())
		return
	var next_points: Dictionary = {}
	_movement_segments.clear()
	_snapshots.clear()
	_snapshots_by_id.clear()
	for value in snapshots:
		if not value is Dictionary:
			continue
		var snapshot: Dictionary = value
		var unit_id := str(snapshot.get("unit_id", ""))
		if unit_id.is_empty():
			continue
		_snapshots.append(snapshot)
		_snapshots_by_id[unit_id] = snapshot
		next_points[unit_id] = _world_to_local(_unit_position(snapshot))
		if _previous_points.has(unit_id):
			var previous: Vector2 = _previous_points[unit_id]
			var current: Vector2 = next_points[unit_id]
			if previous.distance_squared_to(current) > 0.5:
				_movement_segments[unit_id] = {"from": previous, "to": current}
			_previous_points[unit_id] = current
		else:
			_previous_points[unit_id] = next_points[unit_id]
	for old_id in _previous_points.keys():
		if not next_points.has(old_id):
			_previous_points.erase(old_id)
	queue_redraw()
	if _performance_tracker != null:
		_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UI_UNIT_SNAPSHOT, Time.get_ticks_usec() - tracker_start_usec, _snapshots.size())


func set_physics_tick_position_arrays(
	unit_ids: PackedInt32Array,
	previous_positions: PackedVector2Array,
	current_positions: PackedVector2Array
) -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	# 直接保存 B 的紧凑位置数组；ID 索引只在棋子出生/离场时重建。
	var item_count: int = mini(unit_ids.size(), mini(previous_positions.size(), current_positions.size()))
	var rebuild_index := _physics_position_index_dirty or _physics_unit_ids.size() != item_count
	if not rebuild_index:
		for index in item_count:
			if _physics_unit_ids[index] != unit_ids[index]:
				rebuild_index = true
				break
	_physics_unit_ids = unit_ids
	_physics_previous_positions = previous_positions
	_physics_current_positions = current_positions
	if rebuild_index:
		_physics_position_index_by_unit_id.clear()
		for index in item_count:
			_physics_position_index_by_unit_id[str(unit_ids[index])] = index
		_physics_position_index_dirty = false
	queue_redraw()
	if _performance_tracker != null:
		_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UI_POSITION_SNAPSHOT, Time.get_ticks_usec() - tracker_start_usec, item_count, 1 if rebuild_index else 0)


func forget_unit_position(unit_id: String) -> void:
	# 离场后清除插值历史，重开时复用 ID 也不会从旧位置拖出残影。
	_physics_position_index_by_unit_id.erase(unit_id)
	_physics_position_index_dirty = true
	queue_redraw()


func reset_physics_interpolation_history() -> void:
	_physics_unit_ids = PackedInt32Array()
	_physics_previous_positions = PackedVector2Array()
	_physics_current_positions = PackedVector2Array()
	_physics_position_index_by_unit_id.clear()
	_physics_position_index_dirty = true
	queue_redraw()


func set_word_texts(word_texts: Dictionary) -> void:
	# 詞文字典只在內容變更時替換；渲染幀保留同一個只讀引用。
	_word_texts = word_texts
	_group_bubble_layouts.clear()
	queue_redraw()


func set_word_groups(groups: Array, active_bubble_ids: Dictionary) -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	# D 只消費 B 已算好的连通团体，不在显示层重复做邻近扫描。
	var signature := _build_word_group_signature(groups)
	if signature != _word_group_signature:
		_word_group_signature = signature
		_group_bubble_layouts.clear()
	_word_groups = groups
	_active_group_bubble_ids = active_bubble_ids
	queue_redraw()
	if _performance_tracker != null:
		_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UI_GROUP_SNAPSHOT, Time.get_ticks_usec() - tracker_start_usec, groups.size(), active_bubble_ids.size())


func set_team_textures(neutral_texture: Texture2D, player_texture: Texture2D, opponent_texture: Texture2D) -> void:
	# 兼容旧接线；正式头像映射由 set_unit_sprite_textures 提供。
	_unit_sprite_textures["npc"] = neutral_texture
	_unit_sprite_textures["ham"] = player_texture
	_unit_sprite_textures[_active_opponent_sprite_id] = opponent_texture
	queue_redraw()


func set_unit_sprite_textures(textures: Dictionary) -> void:
	# 静态头像表由 UI 注入；本函数只保存只读引用，避免每帧复制纹理字典。
	_unit_sprite_textures = textures
	queue_redraw()


func set_active_opponent_sprite_id(streamer_id: String) -> void:
	_active_opponent_sprite_id = streamer_id if _unit_sprite_textures.has(streamer_id) else "alien"
	queue_redraw()


func set_selected_unit(unit_id: String) -> void:
	_selected_unit_id = unit_id
	queue_redraw()


## 接收 UI 按当前克制表计算好的敌方目标 ID 集合；集合未变时不重绘。
func set_counterable_unit_ids(unit_ids: Array) -> void:
	var next_ids: Dictionary = {}
	for value in unit_ids:
		var unit_id := str(value)
		if not unit_id.is_empty():
			next_ids[unit_id] = true
	if next_ids.size() == _counterable_unit_ids.size():
		var identical := true
		for unit_id in next_ids:
			if not _counterable_unit_ids.has(unit_id):
				identical = false
				break
		if identical:
			return
	_counterable_unit_ids = next_ids
	queue_redraw()


## 同一条 S1 话语的 relay 只累积真正改口的棋子，并在它们落点显示一次汇总。
func show_rephrase_feedback(unit_ids: Array, feedback_key: String) -> void:
	if feedback_key.is_empty():
		return
	var feedback: Dictionary = _rephrase_feedback.get(feedback_key, {"unit_ids": []})
	var changed_ids: Array = feedback.get("unit_ids", [])
	for value in unit_ids:
		var unit_id := str(value)
		if not unit_id.is_empty() and not changed_ids.has(unit_id):
			changed_ids.append(unit_id)
	feedback["unit_ids"] = changed_ids
	feedback["time"] = Time.get_ticks_msec()
	_rephrase_feedback[feedback_key] = feedback
	while _rephrase_feedback.size() > 3:
		var oldest_key: String = str(_rephrase_feedback.keys()[0])
		var oldest_time: int = int(_rephrase_feedback[oldest_key].get("time", 0))
		for key in _rephrase_feedback:
			var current_time: int = int(_rephrase_feedback[key].get("time", 0))
			if current_time < oldest_time:
				oldest_key = str(key)
				oldest_time = current_time
		_rephrase_feedback.erase(oldest_key)
	queue_redraw()


func set_unit_layer_visible(visible: bool) -> void:
	# 矛盾阶段隐藏普通棋子与接触提示，保留棋盘底板给蓄力准星使用。
	if _unit_layer_visible == visible:
		return
	_unit_layer_visible = visible
	mouse_filter = Control.MOUSE_FILTER_STOP if visible else Control.MOUSE_FILTER_IGNORE
	_hovered_unit_id = ""
	_movement_segments.clear()
	_previous_points.clear()
	reset_physics_interpolation_history()
	if not visible:
		_selected_unit_id = ""
		_feedback_pulses.clear()
		_contact_feedback.clear()
	queue_redraw()


func set_density_profile(_profile: String) -> void:
	# PB-19统一头像直径64px，密度档不改变头像尺寸；保留兼容入口。
	pass


func show_unit_feedback(unit_id: String, reason: String) -> void:
	if not unit_id.is_empty():
		_feedback_pulses[unit_id] = {"reason": reason, "time": Time.get_ticks_msec()}
	queue_redraw()


func show_contact_feedback(first_unit_id: String, second_unit_id: String, outcome: String) -> void:
	# 接触对来自 B 的裁决事件；线段只提示位置与结果，不影响模拟状态。
	_contact_feedback.push_front({
		"first_id": first_unit_id,
		"second_id": second_unit_id,
		"outcome": outcome,
		"time": Time.get_ticks_msec(),
	})
	while _contact_feedback.size() > 5:
		_contact_feedback.pop_back()
	queue_redraw()


func show_word_batch_burst(batch: Dictionary) -> void:
	# 发表事实只负责约半秒的扇形入场提示；棋子位置仍取 B 的实时快照。
	if _performance_tracker != null:
		_performance_tracker.call("record_event", PB14_PERFORMANCE_TRACKER_SCRIPT.EVENT_BATCH_BURST_STARTED)
	var visual: Dictionary = batch.duplicate(false)
	visual["started_at_msec"] = Time.get_ticks_msec()
	_word_batch_bursts.push_front(visual)
	while _word_batch_bursts.size() > 6:
		_word_batch_bursts.pop_back()
	queue_redraw()


func _process(_delta: float) -> void:
	# 只保留短暂提示；棋子位置仍由每帧的新快照决定。
	var now := Time.get_ticks_msec()
	var had_transient_feedback := (
		not _feedback_pulses.is_empty() or not _contact_feedback.is_empty()
		or not _word_batch_bursts.is_empty() or not _rephrase_feedback.is_empty()
	)
	for unit_id in _feedback_pulses.keys():
		if now - int(_feedback_pulses[unit_id].get("time", now)) > 1500:
			_feedback_pulses.erase(unit_id)
	for index in range(_contact_feedback.size() - 1, -1, -1):
		if now - int(_contact_feedback[index].get("time", now)) > 1200:
			_contact_feedback.remove_at(index)
	for index in range(_word_batch_bursts.size() - 1, -1, -1):
		if now - int(_word_batch_bursts[index].get("started_at_msec", now)) > 650:
			_word_batch_bursts.remove_at(index)
	for feedback_key in _rephrase_feedback.keys():
		if now - int(_rephrase_feedback[feedback_key].get("time", now)) > 1200:
			_rephrase_feedback.erase(feedback_key)
	if (had_transient_feedback or not _feedback_pulses.is_empty()
			or not _contact_feedback.is_empty() or not _rephrase_feedback.is_empty()):
		queue_redraw()


func _draw() -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	_render_interpolation_fraction = clampf(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var arena := _arena_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("#07121b"), true)
	draw_rect(arena, Color("#0b1c27"), true)
	draw_rect(arena, Color("#25404c"), false, 1.5)
	for column in range(1, 8):
		var x := arena.position.x + arena.size.x * float(column) / 8.0
		draw_line(Vector2(x, arena.position.y), Vector2(x, arena.end.y), Color(0.25, 0.42, 0.49, 0.18), 1.0)
	for row in range(1, 5):
		var y := arena.position.y + arena.size.y * float(row) / 5.0
		draw_line(Vector2(arena.position.x, y), Vector2(arena.end.x, y), Color(0.25, 0.42, 0.49, 0.18), 1.0)
	if not _unit_layer_visible:
		if _performance_tracker != null:
			_performance_tracker.call("set_ui_draw_work", 0, 0, 0)
			_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UI_DRAW, Time.get_ticks_usec() - tracker_start_usec, 0)
		return

	# 移动尾迹来自前一帧只读位置，用低对比度避免遮住密集棋子。
	for segment in _movement_segments.values():
		draw_line(segment["from"], segment["to"], Color(0.60, 0.78, 0.83, 0.22), 1.2)
	_draw_contact_feedback()
	_draw_word_batch_bursts()

	var unit_draw_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	# 复用当前帧的头像中心，供共享气泡选择较少遮挡的位置。
	_frame_unit_centers.clear()
	for snapshot in _snapshots:
		_draw_unit(snapshot)
	_draw_rephrase_feedback()
	if _performance_tracker != null:
		_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UNIT_DRAW_BATCH, Time.get_ticks_usec() - unit_draw_start_usec, _snapshots.size())
	_draw_group_bubbles()
	if _performance_tracker != null:
		_performance_tracker.call("set_ui_draw_work", _snapshots.size(), _last_drawn_group_bubbles, _last_group_tail_candidates)
		_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_UI_DRAW, Time.get_ticks_usec() - tracker_start_usec, _snapshots.size(), _last_drawn_group_bubbles + _last_group_tail_candidates)


func _draw_unit(snapshot: Dictionary) -> void:
	var unit_id := str(snapshot.get("unit_id", ""))
	var team := str(snapshot.get("team", "neutral"))
	var center := _display_local_position(unit_id, snapshot)
	# 与实际绘制共用同一中心，气泡避让判断不引入第二套头像坐标。
	if not unit_id.is_empty():
		_frame_unit_centers[unit_id] = center
	var tint: Color = TEAM_COLORS.get(team, TEAM_COLORS["neutral"])
	var radius := _visual_radius(snapshot)
	var is_neutral := team == "neutral"
	var is_selected := unit_id == _selected_unit_id
	var is_hovered := unit_id == _hovered_unit_id

	if is_selected or is_hovered:
		draw_circle(center, radius + 9.0, Color(tint.r, tint.g, tint.b, 0.18))
	var sprite_id := _sprite_id_for(snapshot, team)
	var token_texture: Texture2D = _unit_sprite_textures.get(sprite_id) as Texture2D
	if token_texture != null:
		draw_texture_rect(token_texture, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false)
	else:
		draw_circle(center, radius + 1.0, Color("#07121b"))
		draw_circle(center, radius, tint)
	draw_arc(center, radius + 1.25, 0.0, TAU, 20, tint, 1.5, true)
	if not is_neutral:
		var tendency_color := get_tendency_color(str(snapshot.get("tendency", "neutral")))
		draw_arc(center, radius + 4.25, 0.0, TAU, 32, tendency_color, 2.0, true)
	if _counterable_unit_ids.has(unit_id):
		draw_arc(center, radius + 7.0, 0.0, TAU, 32, Color("#b5f2a1", 0.82), 1.6, true)
	_draw_battle_type_badge(center, radius, str(snapshot.get("battle_type", "")))

	if _feedback_pulses.has(unit_id):
		var feedback: Dictionary = _feedback_pulses[unit_id]
		var age := float(Time.get_ticks_msec() - int(feedback.get("time", 0))) / 1500.0
		var reason := str(feedback.get("reason", ""))
		var pulse_color := _feedback_color(reason)
		draw_arc(center, radius + 6.0 + 4.0 * age, 0.0, TAU, 32, Color(pulse_color.r, pulse_color.g, pulse_color.b, 1.0 - age), 1.5, true)
		if reason == "split":
			draw_arc(center, radius + 2.0 + 2.5 * age, 0.0, TAU, 24, Color(pulse_color.r, pulse_color.g, pulse_color.b, 0.85 * (1.0 - age)), 1.0, true)
		elif reason == "reflect":
			draw_arc(center, radius + 3.5, -PI * 0.8, -PI * 0.2, 16, Color(pulse_color.r, pulse_color.g, pulse_color.b, 1.0 - age), 1.5, true)
			draw_arc(center, radius + 3.5, PI * 0.2, PI * 0.8, 16, Color(pulse_color.r, pulse_color.g, pulse_color.b, 1.0 - age), 1.5, true)


## 64px头像内使用正式石头／剪刀／布图标，外圈继续标识克制类别。
func _draw_battle_type_badge(center: Vector2, radius: float, battle_type: String) -> void:
	if battle_type not in ["type_a", "type_b", "type_c"]:
		return
	var badge_center := center + Vector2(radius * 0.66, -radius * 0.66)
	var type_color := _battle_type_color(battle_type)
	draw_circle(badge_center, 10.0, Color("#07141d", 0.94))
	draw_arc(badge_center, 9.2, 0.0, TAU, 24, type_color, 1.5, true)
	var icon_texture := _battle_type_icon_texture(battle_type)
	if icon_texture != null:
		draw_texture_rect(icon_texture, Rect2(badge_center - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), false)


func _battle_type_icon_texture(battle_type: String) -> Texture2D:
	match battle_type:
		"type_a":
			return TYPE_ICON_STONE
		"type_b":
			return TYPE_ICON_SCISSORS
		"type_c":
			return TYPE_ICON_PAPER
		_:
			return null


func _draw_fist_mark(center: Vector2, tint: Color) -> void:
	draw_rect(Rect2(center + Vector2(-5.0, -1.0), Vector2(10.0, 6.0)), tint, true)
	for finger_index in 3:
		draw_rect(Rect2(center + Vector2(-5.0 + finger_index * 3.4, -5.0), Vector2(2.8, 4.5)), tint, true)
	draw_rect(Rect2(center + Vector2(-7.5, 0.0), Vector2(3.4, 3.2)), tint, true)


func _draw_scissors_mark(center: Vector2, tint: Color) -> void:
	draw_line(center + Vector2(-1.0, 0.0), center + Vector2(5.5, -5.0), tint, 1.8, true)
	draw_line(center + Vector2(-1.0, 0.0), center + Vector2(5.5, 5.0), tint, 1.8, true)
	draw_circle(center + Vector2(-4.0, -3.3), 2.0, tint)
	draw_circle(center + Vector2(-4.0, 3.3), 2.0, tint)


func _draw_paper_mark(center: Vector2, tint: Color) -> void:
	draw_line(center + Vector2(-5.0, -6.0), center + Vector2(2.0, -6.0), tint, 1.6, true)
	draw_line(center + Vector2(2.0, -6.0), center + Vector2(5.0, -3.0), tint, 1.6, true)
	draw_line(center + Vector2(5.0, -3.0), center + Vector2(5.0, 6.0), tint, 1.6, true)
	draw_line(center + Vector2(5.0, 6.0), center + Vector2(-5.0, 6.0), tint, 1.6, true)
	draw_line(center + Vector2(-5.0, 6.0), center + Vector2(-5.0, -6.0), tint, 1.6, true)
	draw_line(center + Vector2(-2.5, -1.5), center + Vector2(2.5, -1.5), tint, 1.2, true)
	draw_line(center + Vector2(-2.5, 2.0), center + Vector2(2.5, 2.0), tint, 1.2, true)


## 以当帧真实头像中心为锚点，将同一话语的实际改口单位合并成一条短提示。
func _draw_rephrase_feedback() -> void:
	var now := Time.get_ticks_msec()
	for feedback in _rephrase_feedback.values():
		var unit_ids: Array = feedback.get("unit_ids", [])
		var center := Vector2.ZERO
		var visible_count := 0
		for unit_id_value in unit_ids:
			var unit_id := str(unit_id_value)
			if not _frame_unit_centers.has(unit_id):
				continue
			center += _frame_unit_centers[unit_id]
			visible_count += 1
		if visible_count == 0:
			continue
		center /= float(visible_count)
		var age := clampf(float(now - int(feedback.get("time", now))) / 1200.0, 0.0, 1.0)
		var alpha := 1.0 - age
		var bounds := Rect2(
			Vector2(
				clampf(center.x - 55.0, 4.0, maxf(4.0, size.x - 114.0)),
				clampf(center.y - UNIT_VISUAL_RADIUS - 34.0, 4.0, maxf(4.0, size.y - 28.0))
			),
			Vector2(110.0, 24.0)
		)
		draw_rect(bounds, Color(0.04, 0.09, 0.13, 0.86 * alpha), true)
		draw_rect(bounds, Color(0.58, 0.89, 0.75, 0.88 * alpha), false, 1.0)
		var text := "改口 ×%d" % unit_ids.size()
		draw_string(ThemeDB.fallback_font, bounds.position + Vector2(8.0, 17.0), text, HORIZONTAL_ALIGNMENT_LEFT, 96.0, 14, Color(0.81, 0.98, 0.84, alpha))


# 复读气泡使用主播主泡的十汉字文字栏，团体人数只影响尾巴和锚点。
func _draw_group_bubbles() -> void:
	var tracker_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
	var drawn_bubble_count: int = 0
	var tail_candidate_count: int = 0
	var layout_call_count: int = 0
	var layout_total_usec: int = 0
	var layout_max_usec: int = 0
	var layout_member_total: int = 0
	var layout_member_max: int = 0
	var layout_cache_hits_before: int = _tracker_group_layout_cache_hits
	var position_call_count: int = 0
	var position_total_usec: int = 0
	var position_max_usec: int = 0
	var position_member_total: int = 0
	var position_member_max: int = 0
	var position_entry_total: int = 0
	var position_entry_max: int = 0
	var placed_bubble_rects: Array[Rect2] = []
	# 每帧只取可见团体成员的当前显示位置；文本测量和尾巴成员选择由布局缓存复用。
	if not _unit_layer_visible or _active_group_bubble_ids.is_empty():
		_last_drawn_group_bubbles = 0
		_last_group_tail_candidates = 0
		if _performance_tracker != null:
			_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_GROUP_BUBBLE_DRAW, Time.get_ticks_usec() - tracker_start_usec, _word_groups.size(), 0)
		return
	for group_value in _word_groups:
		if not group_value is Dictionary:
			continue
		var group: Dictionary = group_value
		var group_id := _group_id(group)
		if group_id.is_empty() or not _active_group_bubble_ids.has(group_id):
			continue
		var member_ids := _group_member_ids(group)
		if member_ids.is_empty():
			continue
		var word_id := str(group.get("word_id", ""))
		var phrase := _group_text(group, word_id)
		if word_id.is_empty() or phrase.is_empty() or str(group.get("team", "neutral")) == "neutral":
			continue
		var layout_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
		var layout := _get_group_bubble_layout(group, group_id, member_ids, phrase)
		if _performance_tracker != null:
			var layout_elapsed_usec: int = Time.get_ticks_usec() - layout_start_usec
			layout_call_count += 1
			layout_total_usec += layout_elapsed_usec
			layout_max_usec = maxi(layout_max_usec, layout_elapsed_usec)
			layout_member_total += member_ids.size()
			layout_member_max = maxi(layout_member_max, member_ids.size())
		var member_positions_start_usec: int = Time.get_ticks_usec() if _performance_tracker != null else 0
		var positions_by_id := _group_member_positions(group, member_ids)
		if _performance_tracker != null:
			var positions_elapsed_usec: int = Time.get_ticks_usec() - member_positions_start_usec
			position_call_count += 1
			position_total_usec += positions_elapsed_usec
			position_max_usec = maxi(position_max_usec, positions_elapsed_usec)
			position_member_total += member_ids.size()
			position_member_max = maxi(position_member_max, member_ids.size())
			position_entry_total += positions_by_id.size()
			position_entry_max = maxi(position_entry_max, positions_by_id.size())
		if positions_by_id.is_empty():
			continue
		if _performance_tracker != null:
			drawn_bubble_count += 1
			var tail_ids_value: Variant = layout.get("tail_ids", [])
			if tail_ids_value is Array:
				tail_candidate_count += tail_ids_value.size()
		var center := Vector2.ZERO
		var group_top_y := INF
		var group_bottom_y := -INF
		for position_value in positions_by_id.values():
			var local_position: Vector2 = position_value
			center += local_position
			group_top_y = minf(group_top_y, local_position.y)
			group_bottom_y = maxf(group_bottom_y, local_position.y)
		center /= float(positions_by_id.size())
		var bubble_width := float(layout.get("width", 100.0))
		var bubble_height := float(layout.get("height", 48.0))
		var bubble_rect := _choose_group_bubble_rect(
			center, group_top_y, group_bottom_y, bubble_width, bubble_height, member_ids, placed_bubble_rects
		)
		placed_bubble_rects.append(bubble_rect)
		var style: StyleBoxFlat = _get_group_bubble_style(str(group.get("team", "player")))
		_draw_group_bubble_tails(bubble_rect, layout, positions_by_id, style.bg_color, style.border_color, center)
		draw_style_box(style, bubble_rect)
		var font: Font = get_theme_default_font()
		if font == null:
			font = ThemeDB.fallback_font
		var text_margin: Vector2 = layout.get("text_margin", StreamerBubbleView.DEFAULT_TEXT_MARGIN)
		var text_width := float(layout.get("text_width", bubble_width - text_margin.x * 2.0))
		var text_block_height := minf(
			float(layout.get("text_block_height", bubble_rect.size.y - text_margin.y * 2.0)),
			bubble_rect.size.y - 4.0
		)
		var font_size := int(layout.get("font_size", StreamerBubbleView.DEFAULT_CURRENT_FONT_SIZE))
		# 实际文字块在泡体内居中；块内各行沿用主播气泡的左对齐规则。
		var text_block_width := minf(float(layout.get("text_block_width", text_width)), text_width)
		var text_origin_x := bubble_rect.position.x + (bubble_rect.size.x - text_block_width) * 0.5
		# 实际字形边界比排版测量框更靠上；补回字体 ascent，让墨迹落在居中安全区。
		var text_origin_y := bubble_rect.position.y + (bubble_rect.size.y - text_block_height) * 0.5 + font.get_ascent(font_size)
		draw_multiline_string(
			font,
			Vector2(text_origin_x, text_origin_y),
			phrase,
			HORIZONTAL_ALIGNMENT_LEFT,
			text_width,
			font_size,
			-1,
			Color("#36252f")
		)
	_last_drawn_group_bubbles = drawn_bubble_count
	_last_group_tail_candidates = tail_candidate_count
	if _performance_tracker != null:
		if layout_call_count > 0:
			_performance_tracker.call(
				"record_aggregate",
				PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_GROUP_BUBBLE_LAYOUT,
				layout_call_count,
				layout_total_usec,
				layout_max_usec,
				layout_member_total,
			_tracker_group_layout_cache_hits - layout_cache_hits_before,
				layout_member_max,
			1 if _tracker_group_layout_cache_hits > layout_cache_hits_before else 0
			)
		if position_call_count > 0:
			_performance_tracker.call(
				"record_aggregate",
				PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_GROUP_BUBBLE_POSITIONS,
				position_call_count,
				position_total_usec,
				position_max_usec,
				position_member_total,
				position_entry_total,
				position_member_max,
				position_entry_max
			)
		_performance_tracker.call("record_section", PB14_PERFORMANCE_TRACKER_SCRIPT.SECTION_GROUP_BUBBLE_DRAW, Time.get_ticks_usec() - tracker_start_usec, drawn_bubble_count, tail_candidate_count)


# 气泡主框只由十汉字文字栏宽度决定；团体人数只改变尾巴抽样。
func _get_group_bubble_layout(group: Dictionary, group_id: String, member_ids: Array, phrase: String) -> Dictionary:
	var signature := "%s|%d|%d|%s|%d|%d" % [str(group.get("team", "")), member_ids.size(), StreamerBubbleView.DEFAULT_CURRENT_FONT_SIZE, phrase, int(size.x), int(size.y)]
	var cached: Dictionary = _group_bubble_layouts.get(group_id, {})
	if str(cached.get("signature", "")) == signature:
		if _performance_tracker != null:
			_tracker_group_layout_cache_hits += 1
		return cached
	var text_margin: Vector2 = StreamerBubbleView.DEFAULT_TEXT_MARGIN
	var font: Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var font_size := StreamerBubbleView.DEFAULT_CURRENT_FONT_SIZE
	var text_width := StreamerBubbleView.measure_ten_hanzi_width(font, font_size)
	var available_height := maxf(24.0, size.y - 72.0)
	var measured := font.get_multiline_string_size(phrase, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size)
	var minimum_font_size := StreamerBubbleView.DEFAULT_MINIMUM_READABLE_FONT_SIZE
	while measured.y > available_height and font_size > minimum_font_size:
		font_size -= 1
		text_width = StreamerBubbleView.measure_ten_hanzi_width(font, font_size)
		measured = font.get_multiline_string_size(phrase, HORIZONTAL_ALIGNMENT_LEFT, text_width, font_size)
	var text_block_width: float = minf(measured.x, text_width)
	# 留出与主播主泡一致的水平/垂直安全边距，并额外预留描边宽度。
	var bubble_width := text_width + text_margin.x * 2.0 + 4.0
	var bubble_height := clampf(
		measured.y + text_margin.y * 2.0 + 4.0,
		54.0,
		maxf(54.0, size.y - 16.0)
	)
	var layout := {
		"signature": signature,
		"width": bubble_width,
		"height": bubble_height,
		"text_width": text_width,
		"text_block_width": text_block_width,
		"text_block_height": measured.y,
		"text_margin": text_margin,
		"font_size": font_size,
		"tail_ids": _choose_tail_member_ids(group, member_ids),
	}
	_group_bubble_layouts[group_id] = layout
	if _performance_tracker != null:
		_performance_tracker.call("record_event", PB14_PERFORMANCE_TRACKER_SCRIPT.EVENT_GROUP_BUBBLE_LAYOUT_MISS)
	return layout

func _choose_tail_member_ids(group: Dictionary, member_ids: Array) -> Array:
	var positions_value: Variant = group.get("member_positions", {})
	var positions: Dictionary = positions_value if positions_value is Dictionary else {}
	if positions_value is Array:
		for index in mini(member_ids.size(), positions_value.size()):
			positions[str(member_ids[index])] = _position_value(positions_value[index])
	var sorted_ids: Array = member_ids.duplicate()
	sorted_ids.sort_custom(func(first: Variant, second: Variant) -> bool:
		var first_position: Vector2 = _position_value(positions.get(str(first), positions.get(first, Vector2.ZERO)))
		var second_position: Vector2 = _position_value(positions.get(str(second), positions.get(second, Vector2.ZERO)))
		if not first_position.is_zero_approx() or not second_position.is_zero_approx():
			return first_position.x < second_position.x
		return str(first) < str(second)
	)
	var tail_count := _bubble_tail_count(sorted_ids.size())
	var selected: Array = []
	if tail_count <= 1:
		selected.append(sorted_ids[sorted_ids.size() / 2])
		return selected
	for tail_index in tail_count:
		var sample_index := roundi(float(tail_index) * float(sorted_ids.size() - 1) / float(tail_count - 1))
		selected.append(sorted_ids[sample_index])
	return selected


func _choose_group_bubble_rect(
	center: Vector2,
	group_top_y: float,
	group_bottom_y: float,
	bubble_width: float,
	bubble_height: float,
	member_ids: Array,
	placed_bubble_rects: Array[Rect2]
) -> Rect2:
	# 空间允许时气泡放在团体上方；顶部拥挤时比较左右与下方，减少遮住头像。
	var bubble_size := Vector2(bubble_width, bubble_height)
	var clearance := _unit_visual_radius() + 4.0
	var candidate_positions: Array[Vector2] = [
		Vector2(center.x - bubble_width * 0.5, group_top_y - bubble_height - clearance),
		Vector2(center.x - bubble_width - clearance, center.y - bubble_height * 0.5),
		Vector2(center.x + clearance, center.y - bubble_height * 0.5),
		Vector2(center.x - bubble_width * 0.5, group_bottom_y + clearance),
	]
	var best_rect := Rect2(Vector2.ZERO, bubble_size)
	var best_score := 2147483647
	for candidate_position in candidate_positions:
		var candidate := Rect2(candidate_position, bubble_size)
		candidate.position.x = clampf(candidate.position.x, 8.0, maxf(8.0, size.x - bubble_width - 8.0))
		candidate.position.y = clampf(candidate.position.y, 8.0, maxf(8.0, size.y - bubble_height - 8.0))
		var overlap_score := _group_bubble_overlap_score(candidate, member_ids, placed_bubble_rects, best_score)
		if overlap_score < best_score:
			best_rect = candidate
			best_score = overlap_score
		if best_score == 0:
			break
	return best_rect


func _group_bubble_overlap_score(
	bubble_rect: Rect2,
	member_ids: Array,
	placed_bubble_rects: Array[Rect2],
	stop_at_score: int
) -> int:
	var member_lookup: Dictionary = {}
	for member_id in member_ids:
		member_lookup[str(member_id)] = true
	var score := 0
	var avatar_radius_squared := _unit_visual_radius() * _unit_visual_radius()
	for unit_id_value in _frame_unit_centers.keys():
		var unit_id := str(unit_id_value)
		var unit_center: Vector2 = _frame_unit_centers[unit_id_value]
		var nearest_point := Vector2(
			clampf(unit_center.x, bubble_rect.position.x, bubble_rect.end.x),
			clampf(unit_center.y, bubble_rect.position.y, bubble_rect.end.y)
		)
		if unit_center.distance_squared_to(nearest_point) < avatar_radius_squared:
			score += 3 if member_lookup.has(unit_id) else 1
			if score >= stop_at_score:
				return score
	for placed_rect in placed_bubble_rects:
		if _bubble_rects_overlap(bubble_rect, placed_rect):
			score += 6
			if score >= stop_at_score:
				return score
	return score


func _bubble_rects_overlap(first: Rect2, second: Rect2) -> bool:
	return first.position.x < second.end.x and first.end.x > second.position.x and first.position.y < second.end.y and first.end.y > second.position.y


func _draw_group_bubble_tails(
	bubble_rect: Rect2,
	layout: Dictionary,
	positions_by_id: Dictionary,
	fill_color: Color,
	border_color: Color,
	group_center: Vector2
) -> void:
	var tail_ids: Array = layout.get("tail_ids", [])
	if tail_ids.is_empty():
		return
	var horizontal_tail := group_center.x < bubble_rect.position.x or group_center.x > bubble_rect.end.x
	var point_right := bubble_rect.get_center().x < group_center.x
	var point_down := bubble_rect.get_center().y < group_center.y
	for tail_index in tail_ids.size():
		var member_id := str(tail_ids[tail_index])
		if not positions_by_id.has(member_id):
			continue
		var target: Vector2 = positions_by_id[member_id]
		var tail_offset := _unit_visual_radius() + 2.0
		var half_width := maxf(3.0, _unit_visual_radius() * 0.12)
		var triangle := PackedVector2Array()
		if horizontal_tail:
			var horizontal_spread := bubble_rect.size.y / float(tail_ids.size() + 1)
			var horizontal_root := Vector2(bubble_rect.end.x if point_right else bubble_rect.position.x, bubble_rect.position.y + horizontal_spread * float(tail_index + 1))
			var horizontal_tip := target + Vector2(-tail_offset if point_right else tail_offset, 0.0)
			if absf(horizontal_tip.x - horizontal_root.x) <= 0.001:
				continue
			triangle = PackedVector2Array([horizontal_root + Vector2(0.0, -half_width), horizontal_root + Vector2(0.0, half_width), horizontal_tip])
		else:
			var vertical_spread := bubble_rect.size.x / float(tail_ids.size() + 1)
			var vertical_root := Vector2(bubble_rect.position.x + vertical_spread * float(tail_index + 1), bubble_rect.end.y if point_down else bubble_rect.position.y)
			var vertical_tip := target + (Vector2(0.0, -tail_offset) if point_down else Vector2(0.0, tail_offset))
			if absf(vertical_tip.y - vertical_root.y) <= 0.001:
				continue
			triangle = PackedVector2Array([vertical_root + Vector2(-half_width, 0.0), vertical_root + Vector2(half_width, 0.0), vertical_tip])
		draw_colored_polygon(triangle, fill_color)
		draw_line(triangle[0], triangle[2], border_color, 1.2)
		draw_line(triangle[1], triangle[2], border_color, 1.2)


func _get_group_bubble_style(team: String) -> StyleBoxFlat:
	if _group_bubble_styles.has(team):
		return _group_bubble_styles[team] as StyleBoxFlat
	var border: Color = TEAM_COLORS.get(team, Color("#d887ab"))
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#fff4f7")
	style.border_color = border.lightened(0.2)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	style.corner_radius_bottom_left = 18
	style.corner_radius_bottom_right = 18
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	_group_bubble_styles[team] = style
	return style

func _bubble_tail_count(member_count: int) -> int:
	if member_count <= 1:
		return 1
	if member_count == 2:
		return 2
	if member_count == 3:
		return 3
	if member_count == 4:
		return 3
	if member_count <= 6:
		return 4
	return 5


func _group_id(group: Dictionary) -> String:
	return str(group.get("group_id", group.get("id", "")))


func _group_member_ids(group: Dictionary) -> Array:
	var values: Variant = group.get("member_ids", group.get("unit_ids", group.get("members", [])))
	if not values is Array:
		return []
	var result: Array = []
	for value in values:
		if value is Dictionary:
			var member_id := str(value.get("unit_id", value.get("id", "")))
			if not member_id.is_empty():
				result.append(member_id)
		else:
			result.append(str(value))
	return result


func _group_text(group: Dictionary, word_id: String) -> String:
	var direct_text := str(group.get("text", group.get("word_text", "")))
	if not direct_text.is_empty():
		return direct_text
	var word_snapshot: Variant = group.get("word_snapshot", {})
	if word_snapshot is Dictionary and not str(word_snapshot.get("text", "")).is_empty():
		return str(word_snapshot.get("text", ""))
	return str(_word_texts.get(word_id, ""))


func _group_member_positions(group: Dictionary, member_ids: Array) -> Dictionary:
	var positions: Dictionary = {}
	var provided: Variant = group.get("member_positions", {})
	for member_index in member_ids.size():
		var member_id := str(member_ids[member_index])
		var snapshot: Dictionary = _snapshots_by_id.get(member_id, {})
		var current_position := _physics_position_for_unit(member_id)
		if current_position.is_zero_approx() and not snapshot.is_empty():
			current_position = _unit_position(snapshot)
		var position := current_position
		if position.is_zero_approx():
			position = _provided_member_position(provided, member_id, member_index)
		if not position.is_zero_approx():
			var previous_position := _physics_position_for_unit(member_id, true)
			if previous_position.is_zero_approx():
				previous_position = position
			if current_position.is_zero_approx():
				current_position = position
			positions[member_id] = _world_to_local(previous_position.lerp(current_position, _render_interpolation_fraction))
	if positions.is_empty():
		var center: Vector2 = _position_value(group.get("center_position", Vector2.ZERO))
		if not center.is_zero_approx():
			positions["__center__"] = _world_to_local(center)
	return positions


func _provided_member_position(value: Variant, member_id: String, index: int) -> Vector2:
	if value is Dictionary:
		var position_value: Variant = value.get(member_id, Vector2.ZERO)
		if position_value == Vector2.ZERO and member_id.is_valid_int():
			position_value = value.get(member_id.to_int(), Vector2.ZERO)
		return _position_value(position_value)
	if value is Array and index < value.size():
		return _position_value(value[index])
	return Vector2.ZERO


func _position_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		var position_value: Variant = value.get("position", Vector2.ZERO)
		return position_value if position_value is Vector2 else Vector2.ZERO
	return Vector2.ZERO


func _physics_position_for_unit(unit_id: String, previous: bool = false) -> Vector2:
	var index := int(_physics_position_index_by_unit_id.get(unit_id, -1))
	if index < 0:
		return Vector2.ZERO
	if previous:
		return _physics_previous_positions[index] if index < _physics_previous_positions.size() else Vector2.ZERO
	return _physics_current_positions[index] if index < _physics_current_positions.size() else Vector2.ZERO


func _build_word_group_signature(groups: Array) -> String:
	var parts: Array[String] = []
	for group_value in groups:
		if not group_value is Dictionary:
			continue
		var group: Dictionary = group_value
		var members := _group_member_ids(group)
		members.sort_custom(func(first: Variant, second: Variant) -> bool: return str(first) < str(second))
		var member_parts: Array[String] = []
		for member_id in members:
			member_parts.append(str(member_id))
		parts.append("%s:%s:%s:%s" % [
			_group_id(group),
			str(group.get("team", "")),
			str(group.get("word_id", "")),
			",".join(member_parts),
		])
	return "|".join(parts)


func _draw_contact_feedback() -> void:
	var now := Time.get_ticks_msec()
	for contact in _contact_feedback:
		var first := _snapshot_for_id(str(contact.get("first_id", "")))
		var second := _snapshot_for_id(str(contact.get("second_id", "")))
		if first.is_empty() or second.is_empty():
			continue
		var age := clampf(float(now - int(contact.get("time", now))) / 1200.0, 0.0, 1.0)
		var tint := _contact_color(str(contact.get("outcome", "")))
		var alpha := (1.0 - age) * 0.72
		var first_point := _display_local_position(str(first.get("unit_id", "")), first)
		var second_point := _display_local_position(str(second.get("unit_id", "")), second)
		var first_radius := _visual_radius(first)
		var second_radius := _visual_radius(second)
		draw_line(first_point, second_point, Color(tint.r, tint.g, tint.b, alpha), 1.5)
		draw_arc(first_point, first_radius + 4.0 + age * 3.5, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, alpha), 1.5, true)
		draw_arc(second_point, second_radius + 4.0 + age * 3.5, 0.0, TAU, 24, Color(tint.r, tint.g, tint.b, alpha), 1.5, true)


func _draw_word_batch_bursts() -> void:
	# 环与短线强调同一次发表产生的完整批次，不参与感染或碰撞。
	var now := Time.get_ticks_msec()
	for batch in _word_batch_bursts:
		var age := clampf(float(now - int(batch.get("started_at_msec", now))) / 520.0, 0.0, 1.0)
		var alpha := 1.0 - age
		var team := str(batch.get("team", "player"))
		var color: Color = TEAM_COLORS.get(team, TEAM_COLORS["player"])
		var origin := _world_to_local(_vector_from_variant(batch.get("spawn_position", Vector2.ZERO)))
		draw_arc(origin, _unit_visual_radius() + age * 38.0, 0.0, TAU, 40, Color(color.r, color.g, color.b, alpha * 0.9), 1.5, true)
		var unit_ids: Array = batch.get("unit_ids", [])
		for unit_id in unit_ids:
			var snapshot := _snapshot_for_id(str(unit_id))
			if snapshot.is_empty():
				continue
			var target := _display_local_position(str(unit_id), snapshot)
			draw_line(origin.lerp(target, age), target, Color(color.r, color.g, color.b, alpha * 0.75), 1.2)


func _sprite_id_for(snapshot: Dictionary, team: String) -> String:
	if team == "neutral":
		return "npc"
	if team == "player":
		return "ham"
	var streamer_id := str(snapshot.get("streamer_id", _active_opponent_sprite_id))
	return streamer_id if _unit_sprite_textures.has(streamer_id) else _active_opponent_sprite_id


func _battle_type_color(battle_type: String) -> Color:
	match battle_type:
		"type_a":
			return Color("#70def5")
		"type_b":
			return Color("#d5a2ff")
		"type_c":
			return Color("#ffd477")
		_:
			return Color("#e4eef2")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if not _hovered_unit_id.is_empty():
			_hovered_unit_id = ""
			queue_redraw()
		return

	var click_position := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		click_position = event.position
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		click_position = event.position
		pressed = true
	if not pressed:
		return

	if not _arena_rect().has_point(click_position):
		return
	board_position_clicked.emit(_local_to_world(click_position))
	accept_event()


func _arena_rect() -> Rect2:
	var available := Rect2(Vector2.ZERO, size)
	if available.size.x <= 0.0 or available.size.y <= 0.0:
		return Rect2(Vector2.ZERO, size)
	var world_ratio := world_bounds.size.x / world_bounds.size.y
	var width := available.size.x
	var height := width / world_ratio
	if height > available.size.y:
		height = available.size.y
		width = height * world_ratio
	return Rect2(available.position + (available.size - Vector2(width, height)) * 0.5, Vector2(width, height))


func _visual_radius(_snapshot: Dictionary) -> float:
	# 显示半径与碰撞半径分离；PB-19头像直径为64逻辑像素，碰撞半径由B独立维护。
	return _unit_visual_radius()


func _unit_visual_radius() -> float:
	return UNIT_VISUAL_RADIUS


func _world_to_local(world_position: Vector2) -> Vector2:
	var arena := _arena_rect()
	var relative := Vector2(
		(world_position.x - world_bounds.position.x) / world_bounds.size.x,
		(world_position.y - world_bounds.position.y) / world_bounds.size.y
	)
	return arena.position + Vector2(relative.x * arena.size.x, relative.y * arena.size.y)


func _local_to_world(local_position: Vector2) -> Vector2:
	var arena := _arena_rect()
	var relative := Vector2(
		(local_position.x - arena.position.x) / arena.size.x,
		(local_position.y - arena.position.y) / arena.size.y
	)
	return world_bounds.position + Vector2(relative.x * world_bounds.size.x, relative.y * world_bounds.size.y)


func _unit_position(snapshot: Dictionary) -> Vector2:
	var value: Variant = snapshot.get("position", Vector2.ZERO)
	return value if value is Vector2 else Vector2.ZERO


func _display_local_position(unit_id: String, snapshot: Dictionary) -> Vector2:
	var current := _physics_position_for_unit(unit_id)
	if not current.is_zero_approx():
		var previous := _physics_position_for_unit(unit_id, true)
		if previous.is_zero_approx():
			previous = current
		return _world_to_local(previous.lerp(current, _render_interpolation_fraction))
	return _world_to_local(_unit_position(snapshot))


func _actual_local_position(unit_id: String, snapshot: Dictionary) -> Vector2:
	var actual := _physics_position_for_unit(unit_id)
	if actual.is_zero_approx():
		actual = _unit_position(snapshot)
	return _world_to_local(actual)


func _vector_from_variant(value: Variant) -> Vector2:
	return value if value is Vector2 else Vector2.ZERO


func _snapshot_for_id(unit_id: String) -> Dictionary:
	if unit_id.is_empty():
		return {}
	for snapshot in _snapshots:
		if str(snapshot.get("unit_id", "")) == unit_id:
			return snapshot
	return {}


func _feedback_color(reason: String) -> Color:
	match reason:
		"seed":
			return Color("#74e2ff")
		"split":
			return Color("#a8ed7b")
		"reflect":
			return Color("#e6a1ff")
		"convert":
			return Color("#ff806e")
		"relay":
			return Color("#d7a8ff")
		"counterattack":
			return Color("#f17de3")
		_:
			return Color("#d7edf3")


func _contact_color(outcome: String) -> Color:
	match outcome:
		"converted":
			return Color("#ff806e")
		"reflected":
			return Color("#e6a1ff")
		"infection_failed":
			return Color("#ffc77d")
		"same_team_bounce":
			return Color("#d7a8ff")
		"same_type_bounce":
			return Color("#79c9e8")
		"no_counter_bounce":
			return Color("#a1adbc")
		_:
			return Color("#91a4ae")
