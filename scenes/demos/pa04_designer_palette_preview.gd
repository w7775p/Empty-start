extends Control

const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const OUTPUT: String = "res://docs/Shared/PresentationAssets/previews"
const PREVIEW_DATA: Array[Dictionary] = [
	{
		"id": "01_NOIR",
		"title": "01   GLASS NOIR  /  冷暗电影",
		"source": "Inspired by Aavatto / Dribbble glassmorphism chat",
		"colors": ["#1658A2", "#B9502D", "#B7865B", "#ADA4A3"],
		"backdrop": "#070C16",
		"tint": 0.23
	},
	{
		"id": "02_SOFT",
		"title": "02   SOFT GLASS  /  柔光彩玻璃",
		"source": "Inspired by Yatish / Dribbble direct messaging glass",
		"colors": ["#66CADE", "#C8948F", "#E3B688", "#C4D4C3"],
		"backdrop": "#17121A",
		"tint": 0.30
	},
	{
		"id": "03_RITUAL",
		"title": "03   DIGITAL RITUAL  /  秘仪紫蓝",
		"source": "Inspired by Jasmine Shahinpour / Dribbble dark chat",
		"colors": ["#5B99D9", "#9A69A5", "#B7865B", "#C5BECA"],
		"backdrop": "#090A20",
		"tint": 0.26
	}
]
const HEADINGS: Array[String] = ["ORTHODOX  /  正统", "HERETICAL  /  异端", "ABSURD  /  荒谬", "NEUTRAL  /  中立"]
const LINES: Array[Array] = [
	["万物终将归于祂", "神爱世人的第七次直播", "信仰将创造真神"],
	["经文已经改写", "我将重译神的所有诫命", "我即神意的解释者"],
	["圣光连接了 Wi-Fi", "本日神迹由仓鼠友情赞助", "神已正式开通会员"],
	["大家晚上好", "直播间怎么越来越热闹", "我只是路过直播间"]
]

@onready var _area: Control = $BarrageArea
@onready var _overlay: ColorRect = $BackdropShade
var _views: Array[BarrageView] = []
var _heads: Array[Label] = []
var _title: Label
var _source: Label
var _index: int = 0
var _auto_capture: bool = false


# 三种设计师网站参考色只作为预览配置，不写回 PA-04 正式组件默认值。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_auto_capture = OS.get_cmdline_user_args().has("--capture-designer")
	_build_layout()
	_create_barrages()
	_apply_palette(0)
	if _auto_capture:
		call_deferred("_capture_all")


# 四倾向列、三强度行使用现有 BarrageView PackedScene，展示真实着色结果。
func _create_barrages() -> void:
	for column in range(4):
		for tier in range(3):
			var r: BarrageRuntimeRecord = BarrageRuntimeRecord.new()
			r.text = LINES[column][tier]
			r.original_sentence_text = r.text
			r.original_sentence_id = "pa04_color_preview_%d_%d" % [column, tier]
			r.tendency_id = ["orthodox", "heretical", "absurd", "neutral"][column]
			r.strength = float(tier + 1)
			r.expires_at_msec = Time.get_ticks_msec() + 120000
			var view: BarrageView = VIEW.instantiate() as BarrageView
			# S1–S3 阶段感仅供演示：后续确定材质后再进入 PA-04 正式实现。
			var surface: BarrageGlassSurface = view.get_glass_surface()
			surface.max_border_width = float(tier + 1)
			surface.highlight_alpha = 0.12 + 0.12 * float(tier)
			surface.glass_alpha = 0.69 + 0.075 * float(tier)
			view.foreground_outline_size = 2 if tier < 2 else 3
			view.visual_font_size = 24
			view.setup(r, 0.0, _area)
			_area.add_child(view)
			view.position = Vector2(90 + column * 454, 300 + tier * 168)
			_views.append(view)


# 标签均为 Godot Label，预览截图记录的是实际运行帧。
func _build_layout() -> void:
	_title = _make_label("", Vector2(72, 40), 48, Color.WHITE)
	_source = _make_label("", Vector2(78, 115), 22, Color("#C5CED7"))
	_make_label("PA-04  /  DESIGNER PALETTE STUDY        1920 × 1080   GODOT 4.7.2", Vector2(1020, 47), 20, Color("#A5B6CB"))
	for i in range(4):
		var x: float = 92 + i * 454
		var caption: Label = _make_label(HEADINGS[i], Vector2(x, 222), 24, Color.WHITE)
		_heads.append(caption)
	for tier in range(3):
		_make_label("S%d" % (tier + 1), Vector2(30, 325 + tier * 168), 24, Color("#E6ECF5"))
	_make_label("S1  THIN / TRANSLUCENT", Vector2(90, 868), 22, Color("#A9B8C8"))
	_make_label("S2  RIM + REFLECTION", Vector2(650, 868), 22, Color("#B8CBDC"))
	_make_label("S3  BRIGHTER RIM + GLOSS", Vector2(1218, 868), 22, Color("#E5E5E8"))
	_make_label("PREVIEW ONLY   ·   1 / 2 / 3: PALETTE   ·   FROSTED PLASTIC GLASS  ·   NOT MERGED", Vector2(100, 985), 22, Color("#ADBACA"))


# 更新所有实例的透明度、玻璃浓度、边缘色和标题色。
func _apply_palette(next_index: int) -> void:
	_index = posmod(next_index, PREVIEW_DATA.size())
	var p: Dictionary = PREVIEW_DATA[_index]
	_title.text = p["title"]
	_source.text = p["source"]
	_overlay.color = Color(p["backdrop"], 0.85)
	var colors: Array = p["colors"]
	for column in range(4):
		_heads[column].add_theme_color_override("font_color", Color(colors[column]))
	for n in range(_views.size()):
		var view: BarrageView = _views[n]
		var surface: BarrageGlassSurface = view.get_glass_surface()
		surface.orthodox_color = Color(colors[0])
		surface.heretical_color = Color(colors[1])
		surface.absurd_color = Color(colors[2])
		surface.neutral_color = Color(colors[3])
		var tier: int = n % 3
		surface.tint_mix_base = float(p["tint"]) + 0.045 * float(tier)
		surface.tint_mix_strength = 0.08 + 0.08 * float(tier)
		surface.configure(view.runtime_record.tendency_id, tier + 1, false)


# 可在编辑器 F6 运行并按数字键查看三套色板。
func _input(event: InputEvent) -> void:
	if _auto_capture or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_1:
		_apply_palette(0)
	elif key.keycode == KEY_2:
		_apply_palette(1)
	elif key.keycode == KEY_3:
		_apply_palette(2)


func _make_label(message: String, where: Vector2, font_size: int, tint: Color) -> Label:
	var l: Label = Label.new()
	l.text = message
	l.position = where
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# SubViewport 逐张截图；Godot 渲染一帧后再保存实际 GPU 像素。
func _capture_all() -> void:
	var out: String = ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(out) != OK:
		push_error("PA04_DESIGNER_CAPTURE_DIR_ERROR")
		get_tree().quit(1)
		return
	for i in range(PREVIEW_DATA.size()):
		_apply_palette(i)
		await get_tree().create_timer(0.18).timeout
		await RenderingServer.frame_post_draw
		var pic: Image = get_viewport().get_texture().get_image()
		var save_path: String = OUTPUT.path_join("pa04_designer_" + PREVIEW_DATA[i]["id"] + ".jpg")
		var error: Error = pic.save_jpg(ProjectSettings.globalize_path(save_path), 0.9)
		print("DESIGNER_%d: error=%d size=%s" % [i + 1, error, pic.get_size()])
		if error != OK or pic.get_width() != 1920 or pic.get_height() != 1080:
			push_error("PA04_DESIGNER_CAPTURE_FAILED")
			get_tree().quit(1)
			return
	print("PA04_DESIGNER_PREVIEW_DONE")
	get_tree().quit(0)
