extends Control

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const VIEW_COUNT: int = 8
const DEMO_SECONDS: float = 1.2
const SPEED_TOLERANCE: float = 12.0
const EVIDENCE_PATH: String = "res://docs/3. BarrageGeneration/evidence/BG20_random_straight_motion.png"
const TRAIL_COLORS: Array[Color] = [
	Color("#48dbe5"), Color("#f4b942"), Color("#a5dd69"), Color("#f27d9b"),
	Color("#9b8cff"), Color("#58a6ff"), Color("#ff9671"), Color("#9dd1b8"),
]

var _area: BarrageArea
var _profile: LevelProfile
var _views: Array[BarrageView] = []
var _spawn_positions: Dictionary = {}
var _spawn_edges: Dictionary = {}
var _trail_by_instance: Dictionary = {}
var _edge_counts: Dictionary = {"top": 0, "bottom": 0, "left": 0, "right": 0}
var _elapsed_seconds: float = 0.0
var _expected_speed: float = 0.0
var _running: bool = false
var _finished: bool = false
var _failures: Array[String] = []
var _status_label: Label


# 准备 TEST_ONLY 关卡与真实弹幕区域，记录出生位置后运行真实视图。
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1600, 900)
		get_window().min_size = Vector2i(1280, 720)
	_build_canvas()
	SaveManager.new_game()
	call_deferred("_start_demo")


# 累计引擎帧时间并沿真实 BarrageView 位置绘制轨迹。
func _process(delta: float) -> void:
	if not _running or _finished:
		return
	_elapsed_seconds += maxf(delta, 0.0)
	for view: BarrageView in _views:
		if not is_instance_valid(view) or view.is_queued_for_deletion():
			continue
		var trail: Line2D = _trail_by_instance.get(view.get_instance_id()) as Line2D
		if trail != null:
			trail.add_point(view.position + view.size * 0.5)
	if _elapsed_seconds >= DEMO_SECONDS:
		call_deferred("_finish_demo")


# 以随机边缘和方向生成多条普通前景，检查内向角度与 BG-40 速度上限。
func _start_demo() -> void:
	seed(20261021)
	_area = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if _area == null:
		_failures.append("BarrageArea scene loads")
		await _finish_demo()
		return
	_area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_area.position = Vector2(320.0, 160.0)
	_area.size = Vector2(1280.0, 760.0)
	_area.maximum_foreground_move_speed_pixels_per_second = 120.0
	_area.random_straight_direction_spread_degrees = 30.0
	_area.set_foreground_motion_weights(1.0, 0.0, 0.0, 0.0)
	_area.normal_foreground_layer_change_interval_seconds = 0.0
	var background: ColorRect = _area.get_node_or_null("AreaBackground") as ColorRect
	if background != null:
		background.color = Color("#1b2430")
	add_child(_area)
	_area.barrage_generated.connect(_on_barrage_generated)
	await get_tree().process_frame

	_profile = LevelProfile.new()
	_profile.level_id = "test_bg20_direction_demo"
	_profile.streamer_id = "test_bg20_demo"
	_profile.base_batch_count = 0
	_profile.base_spawn_interval_seconds = 60.0
	_profile.base_move_speed_pixels_per_second = 360.0
	_profile.normal_barrage_screen_cap = VIEW_COUNT
	_expected_speed = _area.get_foreground_move_speed_pixels_per_second(_profile)

	for index: int in range(VIEW_COUNT):
		var speech: LevelSpeech = LevelSpeech.new()
		speech.original_sentence_id = "test_bg20_sentence_%02d" % index
		speech.text = "TEST_ONLY %02d" % (index + 1)
		speech.tendency_id = "neutral"
		var view: BarrageView = _area.spawn_normal_barrage(_profile, speech)
		if view == null:
			_failures.append("TEST_ONLY ordinary foreground %02d spawns" % index)
			continue
		_views.append(view)
		_spawn_positions[view.get_instance_id()] = view.position
		var edge_name: String = _classify_spawn_edge(view)
		_spawn_edges[view.get_instance_id()] = edge_name
		_edge_counts[edge_name] = int(_edge_counts.get(edge_name, 0)) + 1
	if _views.size() != VIEW_COUNT:
		_failures.append("all %d TEST_ONLY foreground views spawn" % VIEW_COUNT)
	_running = true


# 在每条视图出生后记录它的真实轨迹，线条仅用于本次方向演示。
func _on_barrage_generated(view: BarrageView) -> void:
	var trail: Line2D = Line2D.new()
	trail.width = 3.0
	trail.default_color = TRAIL_COLORS[_trail_by_instance.size() % TRAIL_COLORS.size()]
	trail.z_index = 0
	trail.add_point(view.position + view.size * 0.5)
	_area.add_child(trail)
	_trail_by_instance[view.get_instance_id()] = trail


# 根据四边出生坐标识别本次普通弹幕的起始边。
func _classify_spawn_edge(view: BarrageView) -> String:
	var max_x: float = maxf(_area.size.x - view.size.x, 0.0)
	var max_y: float = maxf(_area.size.y - view.size.y, 0.0)
	if is_zero_approx(view.position.y):
		return "top"
	if is_equal_approx(view.position.y, max_y):
		return "bottom"
	if is_zero_approx(view.position.x):
		return "left"
	if is_equal_approx(view.position.x, max_x):
		return "right"
	return "unknown"


# 各边出生方向均应朝区域内；随机偏转不得抵消内向分量。
func _get_inward_direction(edge_name: String) -> Vector2:
	match edge_name:
		"top":
			return Vector2.DOWN
		"bottom":
			return Vector2.UP
		"left":
			return Vector2.RIGHT
		"right":
			return Vector2.LEFT
	return Vector2.ZERO


# 核验四边覆盖、随机偏转、连续直线速度和全程可见，再保存 GUI 证据。
func _finish_demo() -> void:
	if _finished:
		return
	_finished = true
	_running = false
	var angled_count: int = 0
	var visible_count: int = 0
	var speed_sum: float = 0.0
	var maximum_speed: float = 0.0
	var active_area_rect: Rect2 = Rect2(Vector2.ZERO, _area.size)
	for view: BarrageView in _views:
		if not is_instance_valid(view) or view.is_queued_for_deletion():
			_failures.append("spawned foreground remains alive during direction sample")
			continue
		var initial_position: Vector2 = _spawn_positions.get(view.get_instance_id(), view.position)
		var displacement: Vector2 = view.position - initial_position
		var actual_speed: float = displacement.length() / maxf(_elapsed_seconds, 0.001)
		var actual_direction: Vector2 = displacement.normalized()
		var inward_direction: Vector2 = _get_inward_direction(str(_spawn_edges.get(view.get_instance_id(), "")))
		var inward_dot: float = actual_direction.dot(inward_direction)
		if inward_direction == Vector2.ZERO or inward_dot < cos(deg_to_rad(33.0)):
			_failures.append("edge-born movement stays within the configured inward angle")
		if inward_dot <= 0.0:
			_failures.append("edge-born movement keeps a positive inward component")
		if absf(inward_direction.x * actual_direction.y - inward_direction.y * actual_direction.x) > 0.02:
			angled_count += 1
		if absf(actual_speed - _expected_speed) > SPEED_TOLERANCE:
			_failures.append("ordinary movement speed remains under the BG-40 limit")
		if active_area_rect.intersects(Rect2(view.position, view.size)):
			visible_count += 1
		speed_sum += actual_speed
		maximum_speed = maxf(maximum_speed, actual_speed)
	for edge_name: String in ["top", "bottom", "left", "right"]:
		if int(_edge_counts.get(edge_name, 0)) <= 0:
			_failures.append("spawn sample includes %s edge" % edge_name)
	if angled_count < 4:
		_failures.append("random directions include varied straight headings")
	if visible_count != VIEW_COUNT:
		_failures.append("all views remain visible during the initial inward motion")
	var average_speed: float = speed_sum / float(maxi(_views.size(), 1))
	_status_label.text = "边缘 TOP/BOTTOM/LEFT/RIGHT：%s | 偏转轨迹：%d | 平均 %.1f px/s | 上限 %.1f px/s" % [
		str(_edge_counts), angled_count, average_speed, _expected_speed
	]
	if _failures.is_empty():
		print("BG20_DIRECTION_SMOKE_PASS edges=%s angled=%d average_speed=%.1f max_speed=%.1f" % [
			str(_edge_counts), angled_count, average_speed, maximum_speed
		])
	else:
		_status_label.text += " | FAIL: " + "; ".join(_failures)
		push_error("BG20_DIRECTION_SMOKE_FAIL: %s" % "; ".join(_failures))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var evidence_path: String = ProjectSettings.globalize_path(EVIDENCE_PATH)
		DirAccess.make_dir_recursive_absolute(evidence_path.get_base_dir())
		var save_error: Error = get_viewport().get_texture().get_image().save_png(evidence_path)
		if save_error != OK:
			push_error("BG20 direction screenshot failed: %s" % error_string(save_error))
			get_tree().quit(1)
			return
		print("BG20_DIRECTION_SCREENSHOT=" + evidence_path)
	get_tree().quit(0 if _failures.is_empty() else 1)


# 加入 TEST_ONLY 演示标题和结果状态，不触碰正式 Sandbox 布局。
func _build_canvas() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("#10141b")
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	move_child(backdrop, 0)
	var title: Label = Label.new()
	title.position = Vector2(320.0, 24.0)
	title.size = Vector2(1280.0, 42.0)
	title.text = "BG-20 随机直线方向演示 · TEST_ONLY · 速度上限 120 px/s"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color("#f4f6fa"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var subtitle: Label = Label.new()
	subtitle.position = Vector2(320.0, 70.0)
	subtitle.size = Vector2(1280.0, 30.0)
	subtitle.text = "四边出生后沿内向法线随机偏转 ≤30°；颜色轨迹来自实际 BarrageView 位置。"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color("#c4cbd5"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)
	_status_label = Label.new()
	_status_label.position = Vector2(320.0, 1020.0)
	_status_label.size = Vector2(1280.0, 32.0)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("#f4f6fa"))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)
