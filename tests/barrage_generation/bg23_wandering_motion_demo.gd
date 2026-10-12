extends Control

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")

var _barrage_area: BarrageArea
var _barrage_view: BarrageView
var _trajectory: Line2D
var _status_label: Label
var _sample_elapsed_seconds: float = 0.0
var _previous_center: Vector2 = Vector2.ZERO
var _previous_direction: Vector2 = Vector2.ZERO
var _turn_count: int = 0


# 创建唯一普通话语并打开游荡配置，运行本场景即可反复观察同一实例。
func _ready() -> void:
	_build_demo_surface()
	_spawn_demo_barrage()


# 每隔短时采样实际视图位置，用轨迹与计数展示真实转向。
func _process(delta: float) -> void:
	if not is_instance_valid(_barrage_view):
		return
	_sample_elapsed_seconds += delta
	if _sample_elapsed_seconds < 0.08:
		return
	_sample_elapsed_seconds = fposmod(_sample_elapsed_seconds, 0.08)

	var current_center: Vector2 = _barrage_view.position + _barrage_view.size * 0.5
	var displacement: Vector2 = current_center - _previous_center
	if displacement.length_squared() > 0.25:
		var direction: Vector2 = displacement.normalized()
		if _previous_direction.length_squared() > 0.5 and _previous_direction.dot(direction) < 0.8:
			_turn_count += 1
			print("BG23_DEMO_TURN=%d" % _turn_count)
			_add_turn_marker(current_center)
		_previous_direction = direction
		_previous_center = current_center
		_trajectory.add_point(current_center)

	_status_label.text = "BG-23 低速游荡演示\n转向次数：%d    速度：40 px/s    每 1 秒选择一次新方向\n按 R 重新播放" % _turn_count


# 使用真实 BarrageArea 与 BarrageView 生成这条演示话语。
func _spawn_demo_barrage() -> void:
	var level_profile: LevelProfile = LevelProfile.new()
	level_profile.level_id = "bg23_demo"
	level_profile.streamer_id = "bg23_demo_streamer"
	level_profile.streamer_name = "BG-23 Demo"
	level_profile.base_move_speed_pixels_per_second = 100.0
	level_profile.normal_barrage_screen_cap = 1

	var speech: LevelSpeech = LevelSpeech.new()
	speech.original_sentence_id = "bg23_wandering_demo_line"
	speech.text = "同一条普通弹幕低速游荡，按时改变方向。"
	speech.tendency_id = "neutral"

	_barrage_view = _barrage_area.spawn_normal_barrage(level_profile, speech)
	if _barrage_view == null:
		_status_label.text = "BG-23 演示生成失败；请查看 Godot Output。"
		return
	print("BG23_DEMO_SPAWNED visible=%s text=%s position=%s size=%s z=%d" % [
		_barrage_view.visible, _barrage_view.text, _barrage_view.position,
		_barrage_view.size, _barrage_view.z_index
	])
	_previous_center = _barrage_view.position + _barrage_view.size * 0.5
	_trajectory.add_point(_previous_center)


# 组合战斗区域底色、轨迹和状态文案，方便独立播放验收。
func _build_demo_surface() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("#0b121a")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	_barrage_area = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	_barrage_area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var viewport_size: Vector2 = get_viewport_rect().size
	var horizontal_margin: float = maxf(viewport_size.x * 0.08, 40.0)
	var top_margin: float = maxf(viewport_size.y * 0.22, 96.0)
	_barrage_area.position = Vector2(horizontal_margin, top_margin)
	_barrage_area.size = Vector2(
		maxf(viewport_size.x - horizontal_margin * 2.0, 640.0),
		maxf(viewport_size.y - top_margin - 48.0, 360.0)
	)
	_barrage_area.base_lifetime_seconds = 40.0
	_barrage_area.set_foreground_motion_weights(0.0, 0.0, 0.0, 1.0)
	_barrage_area.normal_foreground_wandering_speed_multiplier = 0.4
	_barrage_area.normal_foreground_wandering_direction_change_interval_seconds = 1.0
	_barrage_area.normal_foreground_layer_change_interval_seconds = 0.0
	add_child(_barrage_area)
	_barrage_area.set_foreground_slot_count(1)

	_trajectory = Line2D.new()
	_trajectory.name = "WanderingTrajectory"
	_trajectory.width = 2.0
	_trajectory.default_color = Color("#57b6d7", 0.78)
	_trajectory.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	_barrage_area.add_child(_trajectory)

	_status_label = Label.new()
	_status_label.position = Vector2(64.0, 48.0)
	_status_label.size = Vector2(1100.0, 150.0)
	_status_label.add_theme_font_size_override("font_size", 30)
	_status_label.add_theme_color_override("font_color", Color("#e9f5fb"))
	_status_label.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	add_child(_status_label)


# 用醒目标记指出轨迹中检测到的实际方向变化。
func _add_turn_marker(center: Vector2) -> void:
	var marker: ColorRect = ColorRect.new()
	marker.position = center - Vector2(5.0, 5.0)
	marker.size = Vector2(10.0, 10.0)
	marker.color = Color("#ffc857")
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	_barrage_area.add_child(marker)


# R 键重载场景，重新生成同一配置的演示实例。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		get_tree().reload_current_scene()
