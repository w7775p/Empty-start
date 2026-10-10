extends Control

const BARRAGE: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const FX_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_fx.gd")
const TEXTURES: Array[Texture2D] = [
	preload("res://assets/ui/combat/impact_marks/impact_01_razor.png"),
	preload("res://assets/ui/combat/impact_marks/impact_02_ink.png"),
	preload("res://assets/ui/combat/impact_marks/impact_03_krak.png"),
	preload("res://assets/ui/combat/impact_marks/impact_04_manga.png")
]
const TITLES: Array[String] = ["01  RAZOR COLLAGE", "02  BRUSH / INK", "03  COMIC KRAK", "04  MANGA BURST"]
const SUBTITLES: Array[String] = ["尖锐剪纸 · Persona 灵感", "粗笔触 · 手绘裂痕", "手绘拟声字形 · KRAK", "破裂漫符 · 放射冲击"]
const EXPORT: String = "res://docs/Shared/PresentationAssets/previews/"

@onready var _zone: Control = $BarrageZone
var _targets: Array[BarrageView] = []
var _fxs: Array[BarrageImpactFx] = []
var _capturing: bool = false


# 四种独立透明 PNG；同一文本、同一弹幕材质、同一碰撞位置逻辑。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_capturing = OS.get_cmdline_user_args().has("--capture-pa06-marks")
	_build_stage()
	_build_targets()
	if _capturing:
		call_deferred("_capture_sequence")


func _build_stage() -> void:
	_label("PA-06  /  FOUR FRACTURE MARKS", Vector2(65, 32), 45, Color("#FFF6E8"))
	_label("FOUR INDEPENDENT TRANSPARENT ASSETS     GODOT 4.7.2     1920 × 1080", Vector2(68, 103), 21, Color("#AFC1D1"))
	for i in range(4):
		var x: float = 40.0 + float(i) * 475.0
		var panel := Panel.new()
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color("#101725", 0.86)
		panel_style.border_color = Color("#506077", 0.65)
		panel_style.set_border_width_all(2)
		panel_style.set_corner_radius_all(11)
		panel.add_theme_stylebox_override("panel", panel_style)
		panel.position = Vector2(x, 170)
		panel.size = Vector2(425, 798)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		_label(TITLES[i], Vector2(x + 26, 203), 28, Color("#F6F2E9"))
		_label(SUBTITLES[i], Vector2(x + 26, 247), 18, Color("#A8B9CC"))
		var preview := TextureRect.new()
		preview.texture = TEXTURES[i]
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.position = Vector2(x + 88, 307)
		preview.size = Vector2(248, 248)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(preview)
		_label("SAME BARRAGE / SAME HIT", Vector2(x + 27, 795), 17, Color("#BBCDDC"))
		_label("asset %d / transparent PNG" % (i + 1), Vector2(x + 27, 870), 18, Color("#98AFC0"))
	_label("R = REPLAY     SPACE = PAUSE     ACTUAL SHATTER FX / PNG TEXTURES", Vector2(68, 1002), 20, Color("#B6C8D6"))


func _build_targets() -> void:
	_targets.clear()
	for i in range(4):
		var rec := BarrageRuntimeRecord.new()
		rec.text = "信仰正在破裂"
		rec.original_sentence_text = rec.text
		rec.original_sentence_id = "pa06_mark_compare_" + str(i + 1)
		rec.tendency_id = "orthodox"
		rec.strength = 3.0
		rec.expires_at_msec = Time.get_ticks_msec() + 70000
		var view: BarrageView = BARRAGE.instantiate() as BarrageView
		view.setup(rec, 0.0, _zone)
		_zone.add_child(view)
		view.position = Vector2(89.0 + float(i) * 475.0, 660.0)
		_targets.append(view)


# 真实 PA-06 BarrageImpactFx，每组只改变选中的独立图像资源。
func _play_all() -> void:
	for i in range(4):
		var view: BarrageView = _targets[i]
		if not is_instance_valid(view):
			continue
		var fx: BarrageImpactFx = FX_SCRIPT.new() as BarrageImpactFx
		_zone.add_child(fx)
		fx.position = view.position
		fx.accent_texture = TEXTURES[i]
		fx.accent_size = 134
		fx.accent_offset = Vector2(-2, -109)
		_fxs.append(fx)
		fx.play_fracture(view)
		view.queue_free()


func _label(content: String, where: Vector2, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = content
	l.position = where
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)


func _input(event: InputEvent) -> void:
	if _capturing or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_R:
		for fx: BarrageImpactFx in _fxs:
			if is_instance_valid(fx):
				fx.queue_free()
		for view: BarrageView in _targets:
			if is_instance_valid(view):
				view.queue_free()
		_fxs.clear()
		await get_tree().process_frame
		_build_targets()
		_play_all()
	elif key.keycode == KEY_SPACE:
		get_tree().paused = not get_tree().paused


# 比对两类证据：四套独立资产静态外观，以及相同命中时各自真正进入 PA-06 FX。
func _capture_sequence() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT)) != OK:
		push_error("PA06_MARK_PREVIEW_DIRECTORY_ERROR")
		get_tree().quit(1)
		return
	await get_tree().create_timer(0.38).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_four_marks_before.jpg")
	_play_all()
	await get_tree().create_timer(0.18).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_four_marks_impact.jpg")
	await get_tree().create_timer(0.08).timeout
	await RenderingServer.frame_post_draw
	_save("pa06_four_marks_followthrough.jpg")
	print("PA06_FOUR_MARKS_DONE variants=4")
	get_tree().quit(0)


func _save(filename: String) -> void:
	var snapshot: Image = get_viewport().get_texture().get_image()
	var result: Error = snapshot.save_jpg(ProjectSettings.globalize_path(EXPORT + filename), 0.93)
	print("PA06_MARK_CAPTURE: %s error=%d size=%s" % [filename, result, snapshot.get_size()])
	if result != OK or snapshot.get_size() != Vector2i(1920, 1080):
		push_error("PA06_MARK_CAPTURE_FAILED")
		get_tree().quit(1)
