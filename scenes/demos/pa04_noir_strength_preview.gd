extends Control

const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const STRENGTH_SURFACE: Script = preload("res://scenes/demos/pa04_noir_strength_surface.gd")
const OUTPUT: String = "res://docs/Shared/PresentationAssets/previews/pa04_noir_strength_comparison.jpg"
const COLOR_IDS: Array[String] = ["orthodox", "heretical", "absurd", "neutral"]
const COLOR_HEX: Array[String] = ["#1658A2", "#B9502D", "#B7865B", "#ADA4A3"]
const LABELS: Array[String] = ["ORTHODOX  /  正统", "HERETICAL  /  异端", "ABSURD  /  荒谬", "NEUTRAL  /  中立"]
const PHRASES: Array[String] = [
	"信仰赋予神明形体",
	"我有权解释神的沉默",
	"神灵正在连接 Wi-Fi",
	"今天直播还没结束吗"
]

@onready var _area: Control = $BarrageArea


# 01 冷暗电影配色保留固定，逐档对比玻璃结构和文字权重。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_label("01  /  GLASS NOIR  |  STRENGTH STUDY", Vector2(72, 37), 45, Color("#F8F8F5"))
	_make_label("PA-04    SAME TEXT × S1 / S2 / S3   ·   REAL GODOT RENDER   ·   1920 × 1080", Vector2(78, 105), 21, Color("#AABDD5"))
	for i in range(4):
		_make_label(LABELS[i], Vector2(92 + i * 454, 215), 23, Color(COLOR_HEX[i]))
	for tier in range(3):
		_make_label("S%d" % (tier + 1), Vector2(28, 311 + tier * 167), 28, Color("#D7E2F1"))
		_make_label(["01   Quiet glass", "02   Bright glass", "03   Luminous target"][tier],
			Vector2(86, 382 + tier * 167), 17, Color("#8B99A8"))
	for col in range(4):
		for tier in range(3):
			_spawn(COLOR_IDS[col], PHRASES[col], tier + 1, Vector2(90 + col * 454, 275 + tier * 167))
	_make_label("MATERIAL CLOSE-UP   /   SAME CONTENT, SAME 24PX BASE FONT", Vector2(88, 799), 22, Color("#DDE6F2"))
	for tier in range(3):
		_spawn("orthodox", "信仰赋予神明形体", tier + 1, Vector2(135 + tier * 600, 864), 1.45)
		_make_label(["S1   Subtle border", "S2   Bright border + halo", "S3   Breathing glow + bold"][tier],
			Vector2(132 + tier * 600, 960), 18, Color("#A1BBD0"))
	_make_label("PREVIEW ONLY  /  NO SCRATCHES  /  NO LEFT BAR", Vector2(1140, 1050), 17, Color("#99A9BA"))
	if OS.get_cmdline_user_args().has("--capture-strength"):
		call_deferred("_capture")


# 每条都是真实 BarrageView + RuntimeRecord；预览只替换材质脚本，不改变碰撞和生命周期。
func _spawn(tendency: String, message: String, tier: int, where: Vector2, zoom: float = 1.0) -> void:
	var record: BarrageRuntimeRecord = BarrageRuntimeRecord.new()
	record.text = message
	record.original_sentence_text = message
	record.original_sentence_id = "pa04_noir_%s_s%d" % [tendency, tier]
	record.tendency_id = tendency
	record.strength = float(tier)
	record.expires_at_msec = Time.get_ticks_msec() + 120000
	var view: BarrageView = VIEW.instantiate() as BarrageView
	var surface: BarrageGlassSurface = view.get_glass_surface()
	surface.set_script(STRENGTH_SURFACE)
	surface.orthodox_color = Color(COLOR_HEX[0])
	surface.heretical_color = Color(COLOR_HEX[1])
	surface.absurd_color = Color(COLOR_HEX[2])
	surface.neutral_color = Color(COLOR_HEX[3])
	# 三级强度：填色密度、描边和边缘折光一起增强，倾向色保持同一组。
	surface.max_border_width = 3.0
	surface.glass_alpha = [0.63, 0.77, 0.89][tier - 1]
	surface.tint_mix_base = [0.18, 0.27, 0.36][tier - 1]
	surface.tint_mix_strength = 0.0
	surface.highlight_alpha = 0.0
	view.visual_font_size = 24
	view.foreground_outline_size = 2 if tier < 3 else 3
	if tier >= 3:
		# 用 FontVariation 做独立文字字重，不依赖 BBCode 的溢出排版。
		var heavy: FontVariation = FontVariation.new()
		heavy.base_font = view.get_theme_font("font")
		heavy.variation_embolden = 0.34
		view.add_theme_font_override("font", heavy)
	view.setup(record, 0.0, _area)
	_area.add_child(view)
	view.position = where
	if zoom > 1.0:
		view.scale = Vector2.ONE * zoom


func _make_label(message: String, where: Vector2, font_size: int, tint: Color) -> Label:
	var l: Label = Label.new()
	l.text = message
	l.position = where
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", tint)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# Godot GPU 渲染完整一帧后输出；截图从真正的 1920×1080 SubViewport 取得。
func _capture() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir())) != OK:
		push_error("NOIR_STRENGTH_OUTPUT_DIRECTORY_ERROR")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: Error = image.save_jpg(ProjectSettings.globalize_path(OUTPUT), 0.92)
	print("PA04_NOIR_STRENGTH_RENDER=%d; size=%s" % [error, image.get_size()])
	if error == OK and image.get_size() == Vector2i(1920, 1080):
		await get_tree().create_timer(0.85).timeout
		await RenderingServer.frame_post_draw
		var second: Image = get_viewport().get_texture().get_image()
		var second_error: Error = second.save_jpg(ProjectSettings.globalize_path(OUTPUT.replace(".jpg", "_breathing.jpg")), 0.92)
		print("PA04_NOIR_STRENGTH_BREATHING=%d; size=%s" % [second_error, second.get_size()])
		if second_error != OK:
			error = second_error
	if error != OK or image.get_size() != Vector2i(1920, 1080):
		push_error("PA04_NOIR_STRENGTH_CAPTURE_FAILED")
		get_tree().quit(1)
		return
	get_tree().quit(0)
