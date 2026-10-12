extends Control

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const TEST_TIER_CATALOG: CombatStageTierCatalog = preload("res://data/test_only/combat_stage/bg39_tier_motion_catalog.tres")
const DEMO_SECONDS: float = 2.5
const VIEW_COUNT: int = 4
const EVIDENCE_PATH: String = "res://.godot/bg39-local-evidence/BG39_tier_motion_distribution.png"
const MODE_COLORS: Array[Color] = [
	Color("#4db9f2"), Color("#f59e0b"), Color("#a78bfa"), Color("#4ade80"),
]

var _areas: Array[BarrageArea] = []
var _stages: Array[CombatStage] = []
var _mode_counts: Array[Array] = [[0, 0, 0, 0], [0, 0, 0, 0]]
var _trails: Dictionary = {}
var _elapsed_seconds: float = 0.0
var _finished: bool = false
var _status_labels: Array[Label] = []


## 创建 TEST_ONLY 的 T1 与 T4 真实弹幕区域，并由各自 CombatStage 发布运动权重。
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1600, 900)
		get_window().min_size = Vector2i(1280, 720)
	_build_canvas()
	call_deferred("_start_demo")


## 每帧记录真实视图位置，供截图展示实际运动轨迹。
func _process(delta: float) -> void:
	if _finished:
		return
	_elapsed_seconds += maxf(delta, 0.0)
	for view_id: int in _trails:
		var view: BarrageView = instance_from_id(view_id) as BarrageView
		var trail: Line2D = _trails[view_id] as Line2D
		if is_instance_valid(view) and is_instance_valid(trail) and not view.is_queued_for_deletion():
			trail.add_point(view.position + view.size * 0.5)
	_update_status()
	if _elapsed_seconds >= DEMO_SECONDS:
		call_deferred("_finish_demo")


## 用真实 Tier Catalog 将两块区域分别推进到 T1 与 T4 后生成同量 TEST_ONLY 话语。
func _start_demo() -> void:
	seed(39039)
	var profile := LevelProfile.new()
	profile.level_id = "test_bg39_motion_demo"
	profile.streamer_id = "test_bg39"
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 140.0
	profile.normal_barrage_screen_cap = 64

	for index: int in range(2):
		var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
		if area == null:
			push_error("BG39 demo failed to load BarrageArea")
			get_tree().quit(1)
			return
		area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		area.position = Vector2(60.0 + float(index) * 760.0, 180.0)
		area.size = Vector2(700.0, 620.0)
		area.maximum_foreground_move_speed_pixels_per_second = 110.0
		area.random_straight_direction_spread_degrees = 30.0
		area.curved_foreground_motion_amplitude_pixels = 108.0
		area.speed_change_foreground_motion_cycle_seconds = 4.0
		area.normal_foreground_wandering_speed_multiplier = 0.35
		area.normal_foreground_wandering_direction_change_interval_seconds = 0.8
		area.normal_foreground_layer_change_interval_seconds = 0.0
		area.get_node("AreaBackground").set("color", Color("#172433" if index == 0 else "#1e2b25"))
		add_child(area)
		area.barrage_generated.connect(_on_barrage_generated.bind(index))
		await get_tree().process_frame

		var stage := CombatStage.new(TEST_TIER_CATALOG)
		stage.bind_barrage_area(area)
		stage.begin_combat()
		var target_pk: float = 0.60 if index == 0 else 0.85
		if not stage.update_tier_for_pk(target_pk) or stage.get_current_tier() != (1 if index == 0 else 4):
			push_error("BG39 demo failed to reach requested TEST_ONLY Tier")
			get_tree().quit(1)
			return
		_areas.append(area)
		_stages.append(stage)
		if not area.start_normal_generation(profile):
			push_error("BG39 demo failed to start normal generation")
			get_tree().quit(1)
			return
		for view_index: int in range(VIEW_COUNT):
			var speech := LevelSpeech.new()
			speech.original_sentence_id = "test_bg39_t%d_%02d" % [stage.get_current_tier(), view_index]
			speech.text = "%s-%02d" % ["T1" if index == 0 else "T4", view_index + 1]
			speech.tendency_id = "neutral"
			if area.spawn_normal_barrage(profile, speech) == null:
				push_error("BG39 demo failed to spawn a TEST_ONLY view")
				get_tree().quit(1)
				return
	print("BG39_DEMO_READY tiers=%s views_per_tier=%d" % [
		str([_stages[0].get_current_tier(), _stages[1].get_current_tier()]), VIEW_COUNT
	])


## 按实际选中的类型为每条 BarrageView 记录不同颜色轨迹。
func _on_barrage_generated(view: BarrageView, area_index: int) -> void:
	var mode: int = view.get_foreground_motion_mode()
	var trail := Line2D.new()
	trail.width = 3.0
	trail.default_color = MODE_COLORS[mode]
	trail.z_index = 0
	trail.add_point(view.position + view.size * 0.5)
	_areas[area_index].add_child(trail)
	_trails[view.get_instance_id()] = trail
	_mode_counts[area_index][mode] += 1


## 汇总实际实例运动类型，放进两栏状态文字。
func _update_status() -> void:
	for index: int in range(_mode_counts.size()):
		var counts: Array = _mode_counts[index]
		var label: Label = _status_labels[index]
		label.text = "实际新实例：直线 %d · 曲线 %d · 加减速 %d · 游荡 %d" % [
			counts[0], counts[1], counts[2], counts[3]
		]


## 等画面绘制完成后把本机证据保存到 D 盘 worktree 的 .godot 目录。
func _finish_demo() -> void:
	if _finished:
		return
	_finished = true
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot_path: String = ProjectSettings.globalize_path(EVIDENCE_PATH)
		DirAccess.make_dir_recursive_absolute(screenshot_path.get_base_dir())
		var save_error: Error = get_viewport().get_texture().get_image().save_png(screenshot_path)
		if save_error != OK:
			push_error("BG39 screenshot save failed: %s" % error_string(save_error))
			get_tree().quit(1)
			return
		print("BG39_DEMO_SCREENSHOT=" + screenshot_path)
	get_tree().quit(0)


## 组合 T1/T4 标题、权重来源和实际类型计数，不引用正式档位权重。
func _build_canvas() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#0e141b")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)
	var title := Label.new()
	title.position = Vector2(60.0, 24.0)
	title.size = Vector2(1450.0, 42.0)
	title.text = "BG-39 每档运动类型权重 · TEST_ONLY · Godot 4.7.2"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#f2f5f8"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var subtitle := Label.new()
	subtitle.position = Vector2(60.0, 70.0)
	subtitle.size = Vector2(1450.0, 34.0)
	subtitle.text = "同一个 CombatStage 配置入口发布当前 Tier 权重；每条新普通话语独立抽选一种类型。"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color("#c2ccd6"))
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)
	for index: int in range(2):
		var heading := Label.new()
		heading.position = Vector2(60.0 + float(index) * 760.0, 126.0)
		heading.size = Vector2(700.0, 36.0)
		heading.text = "T1 · straight 8 / curve 2" if index == 0 else "T4 · wandering 10"
		heading.add_theme_font_size_override("font_size", 21)
		heading.add_theme_color_override("font_color", Color("#f2f5f8"))
		heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(heading)
		var status := Label.new()
		status.position = Vector2(60.0 + float(index) * 760.0, 820.0)
		status.size = Vector2(700.0, 32.0)
		status.add_theme_font_size_override("font_size", 17)
		status.add_theme_color_override("font_color", Color("#f2f5f8"))
		status.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_labels.append(status)
		add_child(status)
	var legend := Label.new()
	legend.position = Vector2(60.0, 862.0)
	legend.size = Vector2(1450.0, 28.0)
	legend.text = "轨迹颜色：直线 / 曲线 / 加减速 / 游荡    截图输出到本地 .godot/bg39-local-evidence，按 README 场景入口可重播。"
	legend.add_theme_font_size_override("font_size", 16)
	legend.add_theme_color_override("font_color", Color("#c2ccd6"))
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(legend)
