extends Control

## PA-07 三套可重播、可暂停的 Godot 真实图形 Demo；正式逻辑需待玩家选择方案。
const PROJECTILE_SCRIPT: Script = preload("res://scenes/demos/pa07_variant_projectile.gd")
const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const OUT_DIR: String = "res://docs/Shared/PresentationAssets/previews"
const LEFTS := [72.0, 672.0, 1272.0]

@onready var _shots_layer: Node2D = $Shots
@onready var _targets_layer: Control = $Targets
@onready var _guides: Control = $Guides

var _shots: Array[PA07VariantProjectile] = []
var _auto_play: bool = true
var _elapsed: float = 0.0
var _phase: float = 0.0
var _capture_mode: bool = false
var _capture_720: bool = false
var _status: Label


func _ready() -> void:
	_capture_mode = OS.get_cmdline_user_args().has("--capture-pa07")
	_capture_720 = OS.get_cmdline_user_args().has("--capture-720")
	_auto_play = not _capture_mode
	_build_stage()
	_set_phase(0.0)
	if _capture_mode:
		call_deferred("_capture_sequence")


# 同时运行三条真实 CanvasItem 动画，使用相同的释放起点、距离和时间进行对照。
func _process(delta: float) -> void:
	if not _auto_play or _capture_mode:
		return
	_elapsed = fmod(_elapsed + delta, 1.65)
	if _elapsed < 0.72:
		_set_phase(_elapsed / 0.72 * 0.955)
	elif _elapsed < 1.06:
		_set_phase(0.99)
	else:
		_set_phase(1.0)


# 真实玻璃弹幕与本项目直播 PNG 共同形成清晰的对比环境。
func _build_stage() -> void:
	_add_label("PA-07    /    COMIC PROJECTILE ART STUDY", Vector2(72, 42), 43, Color("#f7f5e9"))
	_add_label("GODOT 4.7.2  •  THREE LIVE PROCEDURAL VFX VARIANTS  •  SAME FLIGHT PATH & TIMING", Vector2(76, 110), 20, Color("#a7c7d2"))
	var heads: Array[String] = ["A   ARMOR / 漫画穿甲弹", "B   ENERGY / 卡通能量弹", "C   WORD / 言语冲击弹"]
	var desc: Array[String] = ["INK + BRASS + 3 SPEED LINES", "SOFT CORE + HALO + STRETCH", "SHATTERED COMIC SHAPES"]
	var colors: Array[Color] = [Color("#f5b546"), Color("#5fdcfc"), Color("#ff7193")]
	for i in range(3):
		var x: float = LEFTS[i]
		_add_label(heads[i], Vector2(x+20, 264), 30, colors[i])
		_add_label(desc[i], Vector2(x+22, 316), 18, Color("#c2d2e2"))
		_add_label("RELEASE", Vector2(x+60, 654), 17, Color("#b8d9e1"))
		_add_label("FROZEN TARGET", Vector2(x+317, 654), 17, Color("#b8d9e1"))
		_add_label(["Hard shell", "Elastic liquid", "Graphic silhouette"][i], Vector2(x+23, 824), 24, colors[i])
		_add_label("one projectile • one frozen point", Vector2(x+23, 864), 16, Color("#8fb1c6"))
		_add_target(x+332, 545, ["神说：开火！", "福报弹回来！", "文字有重量"][i], i)
		_add_target(x+95, 718, ["凡事都有依据", "愿你平安", "此话不能复读"][i], (i+1)%3, true)
		var projectile: PA07VariantProjectile = PROJECTILE_SCRIPT.new() as PA07VariantProjectile
		projectile.art_style = i as PA07VariantProjectile.Style
		projectile.art_scale = 1.18
		_shots_layer.add_child(projectile)
		_shots.append(projectile)
	_add_label("VISUAL PREVIEW ONLY  /  no PK calculation, no hit mutation", Vector2(75, 942), 22, Color("#d9e4e8"))
	_add_label("R REPLAY    SPACE PAUSE    1 LAUNCH    2 MID-FLIGHT    3 IMPACT    4 PLAY", Vector2(75, 991), 18, Color("#9ec4d6"))
	_status = _add_label("STATE: LIVE FLIGHT", Vector2(1560, 105), 19, Color("#6bf5d4"))
	if not _capture_mode:
		_add_button("REPLAY", Vector2(1410, 966), _replay)
		_add_button("PAUSE", Vector2(1575, 966), _toggle_pause)


# 所有目标均是主分支原有 BarrageView + BarrageRuntimeRecord，非模拟气泡贴图。
func _add_target(x: float, y: float, phrase: String, variant: int, ghost: bool = false) -> void:
	var record := BarrageRuntimeRecord.new()
	record.text = phrase
	record.original_sentence_text = phrase
	record.original_sentence_id = "pa07_preview_" + phrase
	record.tendency_id = ["orthodox", "heretical", "absurd"][variant]
	record.strength = 2.0 if not ghost else 1.0
	record.expires_at_msec = Time.get_ticks_msec() + 900000
	var view := VIEW.instantiate() as BarrageView
	view.setup(record, 0.0, _targets_layer)
	_targets_layer.add_child(view)
	view.position = Vector2(x, y)
	if ghost:
		view.modulate.a = 0.55


func _add_label(content: String, pos: Vector2, size_px: int, tint: Color) -> Label:
	var node := Label.new()
	node.text = content
	node.position = pos
	node.add_theme_font_size_override("font_size", size_px)
	node.add_theme_color_override("font_color", tint)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(node)
	return node


func _add_button(text_value: String, at: Vector2, callback: Callable) -> void:
	var button := Button.new()
	button.text = text_value
	button.position = at
	button.custom_minimum_size = Vector2(140, 57)
	button.pressed.connect(callback)
	button.add_theme_font_size_override("font_size", 18)
	add_child(button)


func _set_phase(progress: float) -> void:
	_phase = progress
	for i in range(_shots.size()):
		var left: float = LEFTS[i]
		var start := Vector2(left+116, 592)
		var end := Vector2(left+380, 592)
		_shots[i].set_flight(start, end, progress)
	_guides.set("phase", progress)
	_guides.queue_redraw()
	if _status != null:
		_status.text = "PHASE  %03d%%" % mini(100, roundi(progress*100))


func _replay() -> void:
	_elapsed = 0.0
	_auto_play = true
	_set_phase(0.0)


func _toggle_pause() -> void:
	_auto_play = not _auto_play


func _input(event: InputEvent) -> void:
	if _capture_mode or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			_replay()
		KEY_SPACE:
			_toggle_pause()
		KEY_1:
			_auto_play = false
			_set_phase(0.10)
		KEY_2:
			_auto_play = false
			_set_phase(0.53)
		KEY_3:
			_auto_play = false
			_set_phase(0.99)
		KEY_4:
			_replay()


# 三个关键帧都从图形后端实际像素捕获，非离屏插画或无渲染的 smoke。
func _capture_sequence() -> void:
	var folder := ProjectSettings.globalize_path(OUT_DIR)
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		push_error("PA07_CAPTURE_DIR_FAILED")
		get_tree().quit(1)
		return
	if _capture_720:
		_set_phase(0.53)
		await get_tree().create_timer(0.30).timeout
		await RenderingServer.frame_post_draw
		_save("pa07_abc_flight_1280.jpg")
	else:
		for item in [{"name":"launch","progress":0.10}, {"name":"flight","progress":0.53}, {"name":"impact","progress":0.99}]:
			_set_phase(float(item["progress"]))
			await get_tree().create_timer(0.25).timeout
			await RenderingServer.frame_post_draw
			_save("pa07_abc_" + String(item["name"]) + "_1920.jpg")
	print("PA07_GODOT_CAPTURE_DONE")
	get_tree().quit(0)


func _save(name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(name))
	var result := image.save_jpg(path, 0.92)
	print("PA07_RENDER file=%s result=%d size=%s" % [name, result, image.get_size()])
	if result != OK:
		push_error("PA07_SAVE_FAILED")
		get_tree().quit(2)
