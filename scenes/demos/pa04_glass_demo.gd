extends Control

const BARRAGE_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const CAPTURE_DIR: String = "res://docs/Shared/PresentationAssets/previews"
const TENDENCIES: Array[String] = ["orthodox", "heretical", "absurd", "neutral"]
const COLORS: Array[Color] = [Color("#1658A2"), Color("#B9502D"), Color("#B7865B"), Color("#ADA4A3")]
const TITLES: Array[String] = ["ORTHODOX  正统", "HERETICAL  异端", "ABSURD  荒谬", "NEUTRAL  中立"]
const SENTENCES: Array[Array] = [
	["神说：你必须被看见", "光照着每一个虔诚信徒", "我即众人见证的神迹"],
	["神谕应该由我重新解释", "偏离经文也能走向真理", "神的沉默由我亲自翻译"],
	["神今天上了热门推荐", "宇宙其实是仓鼠滚轮", "教主是一颗发光的土豆"],
	["欢迎来到今日直播间", "谢谢大家今晚的支持", "你的关注是我的动力"]
]

@onready var _area: Control = $BarrageZone
var _views: Array[BarrageView] = []
var _pulse_active: bool = false
var _capture: bool = false
var _footer: Label


# 使用原版 BarrageView 实例生成四倾向三强度，用真实贴图作为检验背景。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_visual_hud()
	_spawn_grid()
	_spawn_variants()
	if OS.get_cmdline_user_args().has("--capture-pa04"):
		_capture = true
		call_deferred("_capture_sequence")


# 工具面板只改变美术参数，运行记录和判定仍由 BarrageView 持有。
func _build_visual_hud() -> void:
	_add_label("PA-04   /   GLASS NOIR", Vector2(83, 47), 46, Color("#f0f8ff"))
	_add_label("Four tendencies   ×   three strengths      |      real Godot CanvasItem + Label render", Vector2(88, 113), 22, Color("#afcad3"))
	for index in range(4):
		_add_label(TITLES[index], Vector2(100 + 450 * index, 188), 24, COLORS[index])
	for tier in range(3):
		_add_label("S%d" % (tier + 1), Vector2(37, 285 + 175 * tier), 23, Color("#a7c6ce"))
	_add_label("SPECIAL PREVIEW   /   TEXT COMPOSITION & REPEAT LAYER", Vector2(88, 773), 22, Color("#e4eeff"))
	_footer = _add_label("PA-04  ·  visual demo  ·  [SPACE] pulse    [R] reset", Vector2(95, 998), 22, Color("#b4c4da"))
	var button := Button.new()
	button.position = Vector2(1462, 971)
	button.custom_minimum_size = Vector2(190, 60)
	button.text = "REPLAY PULSE"
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.pressed.connect(_replay_pulse)
	add_child(button)
	var reset_button := Button.new()
	reset_button.position = Vector2(1682, 971)
	reset_button.custom_minimum_size = Vector2(153, 60)
	reset_button.text = "RESET"
	reset_button.process_mode = Node.PROCESS_MODE_ALWAYS
	reset_button.pressed.connect(_reset_motion)
	add_child(reset_button)


# 预览使用 RuntimeRecord 的真实字段配置，不构造第二套倾向与强度状态。
func _spawn_grid() -> void:
	for tendency_index in range(4):
		for tier in range(3):
			var record := _make_record(SENTENCES[tendency_index][0], TENDENCIES[tendency_index], tier + 1)
			_spawn_record(record, Vector2(93 + 450 * tendency_index, 240 + tier * 175))


# 富文本直接走预留独立接口；灰色纯文本作为正常复读最低层对照。
func _spawn_variants() -> void:
	var repeat := _make_record("神说：你必须被看见", "orthodox", 1)
	repeat.is_repeat = true
	var echo: BarrageView = _spawn_record(repeat, Vector2(97, 845))
	echo.z_index = 0
	var rich := _make_record("神说要有光，然后有了广告", "absurd", 2)
	var mixed: BarrageView = _spawn_record(rich, Vector2(620, 845))
	mixed.set_visual_bbcode("[color=#fff5cf]神说[/color]要有[font_size=32][b][color=#ffe16b]光[/color][/b][/font_size]，然后有了广告")
	var normal := _make_record("所有人都在注视你", "heretical", 3)
	_spawn_record(normal, Vector2(1215, 845))


# 只复制真实需要的字段；超长寿命用于视觉 demo，记录中不存美术状态。
func _make_record(message: String, tendency: String, tier: int) -> BarrageRuntimeRecord:
	var record := BarrageRuntimeRecord.new()
	record.text = message
	record.original_sentence_text = message
	record.original_sentence_id = "pa04_%s_%d" % [tendency, tier]
	record.tendency_id = tendency
	record.strength = float(tier)
	record.expires_at_msec = Time.get_ticks_msec() + 360000
	return record


# 与真实战斗共用同一 PackedScene；零移动速度只为静态颜色对照。
func _spawn_record(record: BarrageRuntimeRecord, where: Vector2) -> BarrageView:
	var view: BarrageView = BARRAGE_SCENE.instantiate() as BarrageView
	view.setup(record, 0.0, _area)
	_area.add_child(view)
	view.position = where
	_views.append(view)
	return view


# 复用已有弹幕缩放 API 进行真人可见的重播验收。
func _replay_pulse() -> void:
	for view in _views:
		if is_instance_valid(view) and not view.runtime_record.is_repeat:
			view.pulse_presentation(1.075, 0.25)
	_pulse_active = true
	_footer.text = "PA-04   ·   PULSE PLAYING   ·   0.25s"


# 重置演示动画，不触碰生命周期与原句记录。
func _reset_motion() -> void:
	for view in _views:
		if is_instance_valid(view):
			view.scale = Vector2.ONE
	_footer.text = "PA-04  ·  visual demo  ·  [SPACE] pulse    [R] reset"


# 编辑器直接 F6 启动时可使用键盘模拟表现 API。
func _input(event: InputEvent) -> void:
	if _capture or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_replay_pulse()
	elif event.keycode == KEY_R:
		_reset_motion()


# 标注文字和玻璃层级，不使用额外图片假装特效。
func _add_label(message: String, where: Vector2, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = message
	label.position = where
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


# 独立真实 GPU 截图模式：固定画面、缩放演出中与恢复后三张。
func _capture_sequence() -> void:
	var directory: String = ProjectSettings.globalize_path(CAPTURE_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("PA04_CAPTURE_DIR_ERROR")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.50).timeout
	await RenderingServer.frame_post_draw
	_save_capture("palette")
	_replay_pulse()
	await get_tree().create_timer(0.075).timeout
	await RenderingServer.frame_post_draw
	_save_capture("pulse")
	await get_tree().create_timer(0.40).timeout
	_reset_motion()
	await RenderingServer.frame_post_draw
	_save_capture("reset")
	print("PA04_CAPTURE_PASS: 3 screenshots, views=%d" % _views.size())
	get_tree().quit()


# 从渲染设备真实视口读取像素并写入仓库 evidence。
func _save_capture(stage: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var out_file := ProjectSettings.globalize_path(CAPTURE_DIR.path_join("pa04_" + stage + ".png"))
	var err: Error = image.save_png(out_file)
	print("PA04_CAPTURE_%s=%d; size=%s" % [stage.to_upper(), err, image.get_size()])
	if err != OK:
		push_error("PA04_CAPTURE_WRITE_FAILED")
