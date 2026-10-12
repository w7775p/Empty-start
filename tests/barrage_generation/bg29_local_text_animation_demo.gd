extends Control

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const VIEW_COUNT: int = 8
const DEMO_TEXT: String = "同一原句：命中数据保持不变，局部文字轻柔变化。"
const DEMO_STYLE: String = "同一原句：[b]命中数据[/b]保持不变，[color=#f2c86d]局部文字[/color]轻柔变化。"

var _area: BarrageArea
var _profile: LevelProfile
var _status_label: Label
var _failures: Array[String] = []


## 使用真实生成入口播放多条同原句视图，并把截图写入 D 盘本机目录。
func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = Vector2i(1600, 900)
		get_window().min_size = Vector2i(1280, 720)
	_build_canvas()
	call_deferred("_run_demo")


## 检查普通原句、局部样式和状态型视图边界，再展示随机效果样本。
func _run_demo() -> void:
	seed(29029)
	_area = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if _area == null:
		_failures.append("BarrageArea Scene loads")
		_finish_headless_if_needed()
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	_area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_area.position = Vector2((viewport_size.x - 1280.0) * 0.5, 155.0)
	_area.size = Vector2(1280.0, 600.0)
	_area.base_lifetime_seconds = 60.0
	_area.normal_foreground_local_text_animation_probability = 1.0
	_area.normal_foreground_wandering_enabled = false
	_area.curved_foreground_motion_enabled = false
	_area.speed_change_foreground_motion_enabled = false
	_area.normal_foreground_layer_change_interval_seconds = 0.0
	var background: ColorRect = _area.get_node_or_null("AreaBackground") as ColorRect
	if background != null:
		background.color = Color("#17212c")
	add_child(_area)
	await get_tree().process_frame

	_profile = LevelProfile.new()
	_profile.level_id = "test_bg29_local_animation"
	_profile.streamer_id = "test_bg29_demo"
	_profile.base_batch_count = 0
	_profile.base_spawn_interval_seconds = 60.0
	_profile.base_move_speed_pixels_per_second = 0.0
	_profile.normal_barrage_screen_cap = VIEW_COUNT + 2
	_profile.special_trait_ids = ["occlusion"]
	_area.set_foreground_slot_count(VIEW_COUNT + 2)
	if not _area.start_normal_generation(_profile):
		_failures.append("TEST_ONLY profile starts the real normal generation owner")
	_area.stop_normal_generation()

	# 带状态特性的话语保持现有表现，不进入局部动画。
	var trait_speech: LevelSpeech = _make_speech("bg29_trait_guard", "特性表现保持原样。")
	var trait_ids: Array[StringName] = [BarrageTraitSet.OCCLUSION]
	var trait_view: BarrageView = _area.spawn_normal_barrage(_profile, trait_speech, trait_ids)
	if trait_view == null or trait_view.get_local_text_animation_kind() != &"":
		_failures.append("trait-bearing foreground stays outside local text animation")
	if trait_view != null:
		_area.end_barrage(trait_view.get_instance_id())
		await get_tree().process_frame

	# 复读继续使用原纯文本层，不安装任何局部动画。
	var repeat_plan: RepeatPlan = RepeatPlan.new()
	repeat_plan.original_line_id = &"bg29_repeat_source"
	repeat_plan.original_line_text = DEMO_TEXT
	repeat_plan.display_text = DEMO_TEXT
	repeat_plan.lifetime_seconds = 60.0
	var repeat_view: BarrageView = _area.spawn_repeat_barrage(repeat_plan, true)
	var repeat_rich: RichTextLabel = repeat_view.get_node_or_null("RichBody") as RichTextLabel if repeat_view != null else null
	if (repeat_view == null or not repeat_view.runtime_record.is_repeat
			or repeat_view.get_local_text_animation_kind() != &""
			or (repeat_rich != null and repeat_rich.visible)):
		_failures.append("repeat remains pure text without a local animation layer")
	if repeat_view != null:
		_area.end_barrage(repeat_view.get_instance_id())
		await get_tree().process_frame

	_profile.special_trait_ids.clear()
	var animation_kinds: Dictionary = {}
	var unique_markup: Dictionary = {}
	var text_facts_preserved: bool = true
	for index: int in range(VIEW_COUNT):
		var speech: LevelSpeech = _make_speech(&"bg29_same_sentence", DEMO_TEXT)
		speech.local_style_bbcode = DEMO_STYLE
		# Demo 以 BG-42 静止落点隔离运动变量，集中检查同一普通原句的文字效果。
		var view: BarrageView = _area.spawn_normal_barrage(_profile, speech, [], true)
		if view == null:
			_failures.append("same-sentence ordinary view %02d spawns" % index)
			continue
		# Demo 只排布 TEST_ONLY 视图；生成、特性装配与效果仍由正式组件完成。
		var column: int = index % 2
		var row: int = floori(float(index) / 2.0)
		view.position = Vector2(24.0 + float(column) * 630.0, 48.0 + float(row) * 128.0)
		view.z_index = BarrageView.FOREGROUND_Z_INDEX
		var animation_kind: StringName = view.get_local_text_animation_kind()
		var rich: RichTextLabel = view.get_node_or_null("RichBody") as RichTextLabel
		if animation_kind == &"" or rich == null or rich.get_parsed_text() != DEMO_TEXT:
			_failures.append("view %02d keeps the exact sentence while a local effect is active" % index)
		else:
			animation_kinds[animation_kind] = true
			unique_markup[rich.text] = true
		if view.runtime_record.text != DEMO_TEXT or view.runtime_record.original_sentence_id != &"bg29_same_sentence":
			text_facts_preserved = false
		_add_view_caption(view, index, animation_kind)
	if animation_kinds.size() < 2:
		_failures.append("same source line demonstrates multiple randomly selected animation types")
	if unique_markup.size() < 2:
		_failures.append("same source line receives different fragment markup across instances")
	if not text_facts_preserved:
		_failures.append("runtime text and original sentence ID remain unchanged")

	_status_label.text = "概率：100%（仅 Demo）  |  类型：抖动 / 脉冲 / 波动 / 轻变形  |  原句 ID 与正文保持不变"
	if _failures.is_empty():
		print("BG29_LOCAL_ANIMATION_PASS views=%d types=%s unique_markup=%d original_id=bg29_same_sentence" % [
			VIEW_COUNT, str(animation_kinds.keys()), unique_markup.size()
		])
	else:
		_status_label.text += "  |  FAIL: " + "; ".join(_failures)
		push_error("BG29_LOCAL_ANIMATION_FAIL: %s" % "; ".join(_failures))
	_finish_headless_if_needed()


## 创建 Demo 用的原句样式；每份副本保持同一稳定 ID 和正文。
func _make_speech(sentence_id: StringName, sentence_text: String) -> LevelSpeech:
	var speech: LevelSpeech = LevelSpeech.new()
	speech.original_sentence_id = String(sentence_id)
	speech.text = sentence_text
	speech.tendency_id = "neutral"
	speech.appearance_weight = 1.0
	return speech


## 在每个真实视图上方标出实际生效的原生动画类型。
func _add_view_caption(view: BarrageView, index: int, animation_kind: StringName) -> void:
	var caption: Label = Label.new()
	caption.position = view.position + Vector2(2.0, -26.0)
	caption.size = Vector2(300.0, 24.0)
	caption.text = "%02d  ·  %s" % [index + 1, _get_animation_name(animation_kind)]
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color("#aabbd0"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	_area.add_child(caption)


## 把稳定动画 ID 映射为中文 Demo 标注。
func _get_animation_name(animation_kind: StringName) -> String:
	match animation_kind:
		&"shake":
			return "轻抖动"
		&"pulse":
			return "轻脉冲"
		&"wave":
			return "小波动"
		&"tornado":
			return "轻变形"
	return "无动画"


## headless 只验证真实生成与正文边界；GUI 由 Godot 外部按帧数关闭。
func _finish_headless_if_needed() -> void:
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0 if _failures.is_empty() else 1)


## 准备不修改正式 Sandbox 的阅读背景与说明文字。
func _build_canvas() -> void:
	var background: ColorRect = ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#0d141d")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)
	var title: Label = Label.new()
	title.position = Vector2(260.0, 24.0)
	title.size = Vector2(1400.0, 42.0)
	title.text = "BG-29 局部文字动画 · TEST_ONLY · 同一原句的随机片段演示"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color("#f4f6fa"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var subtitle: Label = Label.new()
	subtitle.position = Vector2(260.0, 72.0)
	subtitle.size = Vector2(1400.0, 34.0)
	subtitle.text = "轻抖动 / 轻脉冲 / 小波动 / 轻变形；主游戏默认概率仅 8%，此 Demo 单独设为 100%。"
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", Color("#c4cbd5"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(subtitle)
	_status_label = Label.new()
	_status_label.position = Vector2(240.0, 820.0)
	_status_label.size = Vector2(1440.0, 36.0)
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("#e2edf8"))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)
