extends Control

const VIEW_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const PRESENTER_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_presenter.gd")
const CAPTURE_DIR: String = "res://docs/Shared/PresentationAssets/previews"

var _presenter: BarrageImpactPresenter
var _area: Control
var _views: Dictionary = {}
var _capturing: bool = false


# 独立展示真实 PA-05 弹幕、BT 的 Trait Result 和 PA-06 特效；F6 可按 R 重播。
func _ready() -> void:
	_capturing = OS.get_cmdline_user_args().has("--capture-pa06")
	_area = get_node("BarrageZone") as Control
	_presenter = PRESENTER_SCRIPT.new() as BarrageImpactPresenter
	_presenter.name = "ImpactPresenter"
	add_child(_presenter)
	_presenter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_presenter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_make_labels()
	_make_targets()
	if _capturing:
		call_deferred("_capture_all")
	else:
		call_deferred("_play_when_ready")


func _make_labels() -> void:
	_label("PA-06   /   BARRAGE IMPACT", Vector2(73, 37), 49, Color.WHITE)
	_label("CURVED SHATTER  ·  COMIC ACCENT  ·  MATERIAL RESPONSE   /   GODOT 4.7.2", Vector2(78, 109), 22, Color("#B8C8DA"))
	var headings: Array[String] = [
		"01  GLASS / 弧线碎裂", "02  OCCLUSION / 铁质硬碰", "03  SPLIT / 母体碎裂",
		"04  REFLECT / 果冻回弹", "05  FAKE CARD / 椭圆碎裂", "06  RETALIATION / 整板碎裂"
	]
	for i in range(headings.size()):
		var col: int = i % 3
		var row: int = i / 3
		_label(headings[i], Vector2(90 + col * 595, 209 + row * 310), 23, Color("#D6E1EB"))
	_label("SPLIT: REAL CHILD VIEWS APPEAR BELOW THEIR MOTHER (BG INPUT EXTERNAL)",
		Vector2(100, 935), 21, Color("#B3C5D3"))
	_label("R = REPLAY   SPACE = PAUSE   /   TARGETS KEEP ORIGINAL COMBAT RECORDS", Vector2(104, 1010), 20, Color("#A8BAD0"))


# 两行六列以真实 TraitSet 提供外观/命中种类，记录持有同一份原始文本。
func _make_targets() -> void:
	_views.clear()
	_spawn("normal", "信仰令神明降临", [], Vector2(115, 325), 3, "orthodox")
	_spawn("occlusion", "圣典不可撼动", [&"occlusion"], Vector2(705, 325), 2, "neutral")
	_spawn("split", "经文即将裂开", [&"split"], Vector2(1303, 325), 2, "absurd")
	_spawn("reflect", "神迹弹回去了", [&"reflect"], Vector2(112, 625), 2, "orthodox")
	_spawn("fake_card", "神说大家好", [&"fake_card"], Vector2(715, 625), 3, "neutral")
	_spawn("retaliation", "神正看着你", [&"retaliation_copy"], Vector2(1311, 620), 2, "heretical")


func _spawn(key: String, line: String, traits: Array[StringName], where: Vector2,
	strength: int, tendency: String) -> BarrageView:
	var record: BarrageRuntimeRecord = BarrageRuntimeRecord.new()
	record.text = line
	record.original_sentence_id = "pa06_" + key
	record.original_sentence_text = line
	record.tendency_id = tendency
	record.strength = float(strength)
	record.expires_at_msec = Time.get_ticks_msec() + 130000
	for trait_id: StringName in traits:
		record.trait_set.add_trait(trait_id)
	var view: BarrageView = VIEW_SCENE.instantiate() as BarrageView
	view.setup(record, 0.0, _area)
	_area.add_child(view)
	view.position = where
	_views[key] = view
	return view


# 效果触发读取每个 TraitSet 的正式 hit_result；消失发生在已有弹幕退出后。
func _play_all() -> void:
	for key: String in ["normal", "occlusion", "split", "reflect", "fake_card", "retaliation"]:
		var view: BarrageView = _views[key]
		if not is_instance_valid(view):
			continue
		var result: BarrageTraitResult = view.runtime_record.trait_set.get_hit_result()
		_presenter.play_target_result(view, result)
		if key not in ["occlusion"]:
			view.queue_free()
	# 演示使用同生成接口样式创建两条真实新记录，正式内容由 BT-06/BG 生成系统提供。
	_spawn_split_children()


func _spawn_split_children() -> void:
	var child_a: BarrageView = _spawn("child_a", "经文的前半句", [], Vector2(1259, 837), 1, "absurd")
	var child_b: BarrageView = _spawn("child_b", "经文的后半句", [], Vector2(1490, 854), 1, "absurd")
	var children: Array[BarrageView] = [child_a, child_b]
	_presenter.play_spawned_split_children(children)


func _play_when_ready() -> void:
	await get_tree().create_timer(1.0).timeout
	_play_all()


func _input(event: InputEvent) -> void:
	if _capturing or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		_presenter.reset_effects()
		for view: BarrageView in _views.values():
			if is_instance_valid(view):
				view.queue_free()
		await get_tree().process_frame
		_make_targets()
		_play_all()
	elif key.keycode == KEY_SPACE:
		get_tree().paused = not get_tree().paused


func _label(msg: String, where: Vector2, font_size: int, tint: Color) -> void:
	var n: Label = Label.new()
	n.text = msg
	n.position = where
	n.add_theme_font_size_override("font_size", font_size)
	n.add_theme_color_override("font_color", tint)
	add_child(n)


# 1920×1080 SubViewport 实际 GPU 输出命中前/命中瞬间/收束三阶段。
func _capture_all() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR)) != OK:
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_before.jpg")
	_play_all()
	await get_tree().create_timer(0.17).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_impact.jpg")
	await get_tree().create_timer(0.10).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_followthrough.jpg")
	await get_tree().create_timer(0.42).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_recovered.jpg")
	print("PA06_CAPTURE_DONE modes=%d" % _presenter.get_active_effect_count())
	get_tree().quit(0)


func _save(name: String) -> void:
	var pic: Image = get_viewport().get_texture().get_image()
	var err: Error = pic.save_jpg(ProjectSettings.globalize_path(CAPTURE_DIR.path_join(name)), 0.92)
	print("PA06_SCREEN %s error=%d size=%s" % [name, err, pic.get_size()])
	if err != OK or pic.get_size() != Vector2i(1920, 1080):
		push_error("PA06_CAPTURE_FAILED " + name)
		get_tree().quit(1)
