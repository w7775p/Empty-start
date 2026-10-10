extends Control

## PA-09 三风格 Godot 动态对照，完整游戏 UI 背景 + 正式 BarrageView + 正式受击素材。
const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const PREVIEW_DIR := "res://docs/Shared/PresentationAssets/previews"
const STYLE_NAMES := ["A  /  HADES  —  QUIET VALUE", "B  /  PERSONA  —  SLASHED TAG", "C  /  HI-FI RUSH  —  COMIC BEAT"]
const STYLE_DESC := [
	"Warm gold number • short lift • subtle response",
	"Red/black diagonal tag • assertive contrast • cut-paper motion",
	"Heavy outline • pop-and-shake • syncopated comic impact"
]
const EVENT_NAMES := ["NORMAL HIT", "BLOCK / OCCLUSION", "REFLECT", "MULTI x3 / NET NEGATIVE", "MISS"]

@onready var _stage: Control = $Stage
@onready var _barrage_zone: Control = $BarrageZone
@onready var _feedback: Control = $Feedback
var _title: Label
var _desc: Label
var _status: Label
var _hotkeys: Label
var _case_label: Label
var _buttons: Array[Button] = []
var _targets: Array[BarrageView] = []
var _style_idx: int = 0
var _event_idx: int = 1
var _capture: bool = false
var _capture720: bool = false
var _auto_events: bool = false
var _auto_timer: float = 0.0
var _paused: bool = false


# 自动演示循环五种本发结果，保持真实节点的正常可操作状态。
func _process(delta: float) -> void:
	if _capture or not _auto_events or _paused:
		return
	_auto_timer += delta
	if _auto_timer >= 2.0:
		_auto_timer = 0.0
		_select(_style_idx, (_event_idx + 1) % EVENT_NAMES.size())


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture-pa09")
	_capture720 = OS.get_cmdline_user_args().has("--capture-720")
	_build_real_barrage_views()
	_build_ui()
	_select(0, 1)
	if _capture:
		call_deferred("_capture_all")


# 目标是真正的项目 BarrageView（包含 PA-04/05 玻璃材质），背景来自项目正式贴图。
func _build_real_barrage_views() -> void:
	var entries := [
		{"text":"神说：今晚必须早睡","pos":Vector2(475,324),"tendency":"orthodox"},
		{"text":"这是你应得的福报","pos":Vector2(780,411),"tendency":"heretical"},
		{"text":"不许质疑我的教条","pos":Vector2(1110,318),"tendency":"absurd"},
		{"text":"我只是想要点赞","pos":Vector2(543,643),"tendency":"neutral"},
		{"text":"谁同意谁就复读","pos":Vector2(991,653),"tendency":"orthodox"}
	]
	for item in entries:
		var record := BarrageRuntimeRecord.new()
		record.text = String(item["text"])
		record.original_sentence_text = record.text
		record.original_sentence_id = "pa09_preview_" + String(item["tendency"])
		record.tendency_id = String(item["tendency"])
		record.strength = 2.0
		record.expires_at_msec = Time.get_ticks_msec() + 1200000
		var view := VIEW.instantiate() as BarrageView
		view.setup(record, 0.0, _barrage_zone)
		_barrage_zone.add_child(view)
		view.position = item["pos"]
		_targets.append(view)


func _build_ui() -> void:
	_title = _label("", Vector2(429, 199), 37, Color("#fff7eb"))
	_desc = _label("", Vector2(433, 254), 20, Color("#c5e1df"))
	_status = _label("", Vector2(423, 933), 22, Color("#f6edda"))
	_hotkeys = _label("1/2/3  STYLE     Q/W/E/R/T  EVENTS     SPACE  PAUSE     P  REPLAY     TAB  AUTO", Vector2(421, 998), 19, Color("#a8becf"))
	_case_label = _label("", Vector2(1307, 258), 18, Color("#f5d793"))
	_label("PA-09 / PROGRAMMATIC FEEDBACK", Vector2(42, 25), 24, Color("#ffffff"))
	_label("VISUAL STYLE LAB  •  1920 × 1080", Vector2(42, 65), 18, Color("#b7d0d7"))
	_label("P  K", Vector2(914, 60), 26, Color("#fff3d7"))
	_label("PLAYER PK", Vector2(470, 62), 18, Color("#6be9ef"))
	_label("OPPONENT PK", Vector2(1320, 62), 18, Color("#fb8296"))
	_label("LIVE  ·  我方", Vector2(42, 194), 23, Color("#9de9d9"))
	_label("LIVE  ·  对手", Vector2(1566, 194), 23, Color("#fcaac4"))
	_label("煲煲", Vector2(62, 722), 36, Color("#fff5e6"))
	_label("❤ 吱吱叫 ❤", Vector2(145, 738), 21, Color("#ffcfaa"))
	_label("观看 233      喜爱 88", Vector2(48, 798), 20, Color("#d8f6e5"))
	_label("评论 123      粉丝 60", Vector2(48, 831), 20, Color("#d8f6e5"))
	_label("对手主播", Vector2(1580, 724), 35, Color("#fff5e6"))
	_label("❤ 小教会 ❤", Vector2(1700, 744), 18, Color("#ffc7d2"))
	_label("观看 920      喜爱 56", Vector2(1575, 798), 19, Color("#fbe8ef"))
	_label("评论 122      粉丝 400", Vector2(1575, 831), 19, Color("#fbe8ef"))
	_label("CENTRAL BARRAGE FIELD", Vector2(475, 847), 19, Color("#a9cdd8"))
	_label("REAL BARRAGE VIEW  /  HUD ART TEST", Vector2(956, 848), 18, Color("#9dc4cf"))
	_label("DEMO ONLY · READ-ONLY PK", Vector2(43, 970), 17, Color("#acbcc9"))
	if not _capture:
		_add_button("A", Vector2(1511, 958), func(): _select(0, _event_idx))
		_add_button("B", Vector2(1632, 958), func(): _select(1, _event_idx))
		_add_button("C", Vector2(1753, 958), func(): _select(2, _event_idx))


func _label(message: String, at: Vector2, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = message
	result.position = at
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_constant_override("outline_size", 2)
	result.add_theme_color_override("font_outline_color", Color("#172026"))
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(result)
	return result


func _add_button(caption: String, at: Vector2, callback: Callable) -> void:
	var b := Button.new()
	b.text = caption
	b.position = at
	b.custom_minimum_size = Vector2(104, 62)
	b.pressed.connect(callback)
	b.add_theme_font_size_override("font_size", 28)
	add_child(b)
	_buttons.append(b)


# 所有样式只改变 UI 演出，不修改 BarrageView/CombatAttack 的真实数据。
func _select(style_value: int, event_value: int) -> void:
	_style_idx = style_value
	_event_idx = event_value
	_title.text = STYLE_NAMES[_style_idx]
	_desc.text = STYLE_DESC[_style_idx]
	_case_label.text = EVENT_NAMES[_event_idx]
	_stage.call("select_style", _style_idx, _event_idx)
	_feedback.call("select_visual", _style_idx, _event_idx)
	var change: String = ["+8 PK", "-6 PK", "-12 PK", "-9 PK", "+0 PK"][_event_idx]
	_status.text = "SAMPLE : %s     FINAL SHOT : %s   /   PLAYER COMIC ONLY IF NET < 0" % [EVENT_NAMES[_event_idx], change]
	for i in range(_buttons.size()):
		_buttons[i].disabled = i == _style_idx
	for i in range(_targets.size()):
		_targets[i].modulate.a = 0.52 if i == 3 else 1.0


func _input(event: InputEvent) -> void:
	if _capture or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3:
			_select(int(key.keycode) - int(KEY_1), _event_idx)
		KEY_Q:
			_select(_style_idx, 0)
		KEY_W:
			_select(_style_idx, 1)
		KEY_E:
			_select(_style_idx, 2)
		KEY_R:
			_select(_style_idx, 3)
		KEY_T:
			_select(_style_idx, 4)
		KEY_SPACE:
			_paused = not _paused
			_feedback.call("set_playing", not _paused)
		KEY_P:
			_paused = false
			_feedback.call("restart")
		KEY_TAB:
			_auto_events = not _auto_events
			_auto_timer = 0.0
			_paused = false
			_feedback.call("set_playing", true)


# 图形卡用 GPU Viewport 捕获；每个风格同数据同进度，避免视觉比较时信息不同。
func _capture_all() -> void:
	var target_dir := ProjectSettings.globalize_path(PREVIEW_DIR)
	var ok := DirAccess.make_dir_recursive_absolute(target_dir)
	if ok != OK:
		push_error("PA09_CAPTURE_DIR_FAILED=%d" % ok)
		get_tree().quit(2)
		return
	for next_style in range(3):
		var cases: Array[int] = [0, 1, 2, 3, 4]
		if _capture720:
			cases.clear()
			cases.append(1)
		for next_case in cases:
			_select(next_style, next_case)
			_feedback.call("seek_at", 0.25)
			await get_tree().create_timer(0.30).timeout
			await RenderingServer.frame_post_draw
			var style_label: String = ["hades", "persona", "hifi"][next_style]
			var case_label: String = ["normal", "block", "reflect", "multi", "miss"][next_case]
			var resolution := "1280" if _capture720 else "1920"
			_save_frame("pa09_%s_%s_%s.jpg" % [style_label, case_label, resolution])
	print("PA09_GPU_CAPTURE_DONE styles=3 variant_cases=%d" % (1 if _capture720 else 5))
	get_tree().quit(0)


func _save_frame(filename: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var full_path := ProjectSettings.globalize_path(PREVIEW_DIR.path_join(filename))
	var err := image.save_jpg(full_path, 0.93)
	print("PA09_GPU_CAPTURE %s error=%d size=%s" % [filename,err,image.get_size()])
	if err != OK:
		push_error("PA09_CAPTURE_FAILED")
		get_tree().quit(2)
