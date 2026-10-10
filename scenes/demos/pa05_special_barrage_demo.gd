extends Control

const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const OUT_DIR: String = "res://docs/Shared/PresentationAssets/previews"

@onready var _area: Control = $BarrageZone
var _views: Array[BarrageView] = []
var _capturing: bool = false


# 演示始终实例化实际 BarrageView；F6 运行可用 R 重播、Space 暂停/恢复。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capturing = OS.get_cmdline_user_args().has("--capture-pa05")
	_build_labels()
	_spawn_all()
	if _capturing:
		call_deferred("_capture")


# 每张卡只展示一份实例，最后一组展示组合优先级和分裂子话语的普通玻璃。
func _spawn_all() -> void:
	_spawn("glass", "神说：大家好", [], Vector2(96, 254), 2)
	_spawn("steel", "经文不可撼动", [&"occlusion"], Vector2(690, 254), 2)
	_spawn("crack", "真理正在分裂", [&"split"], Vector2(1300, 254), 2)
	_spawn("jelly", "弹回去！", [&"reflect"], Vector2(96, 505), 2)
	_spawn("outline", "你碰不到我", [&"unselectable"], Vector2(690, 505), 2)
	_spawn("fake", "神说：大家好", [&"fake_card"], Vector2(1290, 505), 3)
	_spawn("copy", "神正在看着你", [&"retaliation_copy"], Vector2(96, 748), 2)
	_spawn("combo", "反弹遮挡组合", [&"occlusion", &"reflect"], Vector2(690, 748), 3)
	_spawn("child", "分裂出的短句", [], Vector2(1310, 790), 1)
	_spawn("repeat", "神说：大家好", [], Vector2(1290, 614), 1, true)


# 稳定记录和特性输入来自 4 系统；一张视图只对应一个运行对象。
func _spawn(label: String, phrase: String, traits: Array[StringName],
	where: Vector2, strength: int, repeat: bool = false) -> BarrageView:
	var record: BarrageRuntimeRecord = BarrageRuntimeRecord.new()
	record.text = phrase
	record.original_sentence_text = phrase
	record.original_sentence_id = "pa05_" + label
	record.tendency_id = "orthodox" if label == "jelly" else ("heretical" if label == "combo" else ["orthodox", "heretical", "absurd", "neutral"][_views.size() % 4])
	record.strength = float(strength)
	record.is_repeat = repeat
	record.expires_at_msec = Time.get_ticks_msec() + 150000
	for id: StringName in traits:
		record.trait_set.add_trait(id)
	var view: BarrageView = VIEW.instantiate() as BarrageView
	view.setup(record, 0.0, _area)
	_area.add_child(view)
	view.position = where
	_views.append(view)
	return view


# 保留交付背景和正式立绘；材质名称与游戏中渲染出的实例并列显示。
func _build_labels() -> void:
	_label("PA-05  /  SPECIAL BARRAGE MATERIALS", Vector2(70, 40), 45, Color.WHITE)
	_label("GLASS NOIR FAMILY   ·   REAL GODOT 4.7.2 RENDER   ·   1920×1080", Vector2(76, 108), 21, Color("#B7C7D7"))
	var names: Array[String] = [
		"NORMAL GLASS / 普通", "OCCLUSION / 铁质", "SPLIT / 预裂玻璃",
		"REFLECT / 果冻", "UNSELECTABLE / 镂空字", "FAKE CARD / 假复读",
		"RETALIATION / 单块水军", "REFLECT + OCCLUSION", "SPLIT CHILD / 普通子句"
	]
	for i in range(names.size()):
		var col: int = i % 3
		var row: int = i / 3
		_label(names[i], Vector2(95 + col * 600, 206 + row * 249), 23, Color("#D1DBE8"))
	_label("TRUE REPEAT  /  同色同透明度", Vector2(1290, 573), 18, Color("#98A5B4"))
	_label("R : RESET   ·   SPACE : PAUSE / RESUME   ·   ALL ARE ONE BARRAGE INSTANCE EACH", Vector2(70, 1014), 18, Color("#A9BCCF"))
	if not _capturing:
		var reset := Button.new()
		reset.text = "REPLAY"
		reset.position = Vector2(1590, 973)
		reset.custom_minimum_size = Vector2(125, 57)
		reset.pressed.connect(_replay)
		add_child(reset)
		var pause := Button.new()
		pause.text = "PAUSE"
		pause.position = Vector2(1744, 973)
		pause.custom_minimum_size = Vector2(115, 57)
		pause.pressed.connect(_pause)
		add_child(pause)


func _label(message: String, where: Vector2, font_size: int, tint: Color) -> void:
	var label := Label.new()
	label.text = message
	label.position = where
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


# 重播只更换视图，原模型和命中/有效期接口继续由正式组件使用。
func _replay() -> void:
	for view: BarrageView in _views:
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	_spawn_all()


func _pause() -> void:
	get_tree().paused = not get_tree().paused


func _input(event: InputEvent) -> void:
	if _capturing or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		_replay()
	elif key.keycode == KEY_SPACE:
		_pause()


# 两帧真实渲染截图用于比较果冻正常颤动，不以 headless 截图代替美术验收。
func _capture() -> void:
	var directory: String = ProjectSettings.globalize_path(OUT_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("PA05_CAPTURE_DIR_ERROR")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	_save("pa05_all_materials.jpg")
	await get_tree().create_timer(0.47).timeout
	await RenderingServer.frame_post_draw
	_save("pa05_jelly_wobble.jpg")
	print("PA05_CAPTURE_COMPLETE views=%d" % _views.size())
	get_tree().quit(0)


func _save(name: String) -> void:
	var pic: Image = get_viewport().get_texture().get_image()
	var error: Error = pic.save_jpg(ProjectSettings.globalize_path(OUT_DIR.path_join(name)), 0.92)
	print("PA05_CAPTURE %s error=%d size=%s" % [name, error, pic.get_size()])
	if error != OK or pic.get_size() != Vector2i(1920, 1080):
		push_error("PA05_CAPTURE_FAILED " + name)
		get_tree().quit(1)
