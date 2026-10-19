extends Control

# Comic copy layout tool. Run this scene with F6 (Godot 4.7.2).
# Only the two configured .tres resources are written when "保存两段文案" is pressed.
const OPENING_PATH := "res://data/comics/opening.tres"
const ENDING_PATH := "res://data/comics/ending.tres"
const DESIGN_SIZE := Vector2(1920, 1080)
const FONT_PATHS: Array[String] = [
	"",
	"res://assets/fonts/NotoSansSC-VF.ttf",
	"res://assets/fonts/ZCOOLKuaiLe-Regular.ttf",
]
const CAPTION_KINDS: Array[String] = ["speech", "narration", "danmaku", "label"]

var _opening: ComicSequence
var _ending: ComicSequence
var _sequence: ComicSequence
var _part: int = 0
var _frame_index: int = 0
var _caption_index: int = -1
var _dirty: Array[bool] = [false, false]
var _syncing: bool = false
var _dragging: bool = false
var _drag_mouse_origin: Vector2
var _drag_rect_origin: Vector2

var _frame_list: ItemList
var _caption_list: ItemList
var _preview_host: Control
var _canvas: Control
var _caption_text: TextEdit
var _frame_text: TextEdit
var _kind_select: OptionButton
var _font_select: OptionButton
var _font_size_spin: SpinBox
var _font_color_button: ColorPickerButton
var _seconds_spin: SpinBox
var _field_spins: Dictionary = {}
var _status: Label
var _section_label: Label
var _hint: Label


func _ready() -> void:
	_opening = load(OPENING_PATH) as ComicSequence
	_ending = load(ENDING_PATH) as ComicSequence
	if _opening == null or _ending == null:
		push_error("ComicCopyEditor: 开场或结局 .tres 无法加载")
		return
	_sequence = _opening
	_build_ui()
	_switch_sequence(0)


func _build_ui() -> void:
	var base := VBoxContainer.new()
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.add_theme_constant_override("separation", 5)
	add_child(base)

	var toolbar := HBoxContainer.new()
	base.add_child(toolbar)
	_make_button(toolbar, "开头 · P1–P4", _switch_sequence.bind(0))
	_make_button(toolbar, "结局 · P5–P6", _switch_sequence.bind(1))
	_section_label = Label.new()
	_section_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toolbar.add_child(_section_label)
	_make_button(toolbar, "保存两段文案  Ctrl+S", _save_all)

	var split_left := HSplitContainer.new()
	split_left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	base.add_child(split_left)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(215, 0)
	split_left.add_child(left)
	left.add_child(_make_label("分镜列表"))
	_frame_list = ItemList.new()
	_frame_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame_list.item_selected.connect(_pick_frame)
	left.add_child(_frame_list)
	var nav := HBoxContainer.new()
	left.add_child(nav)
	_make_button(nav, "◀ 上一格", _go_relative.bind(-1))
	_make_button(nav, "下一格 ▶", _go_relative.bind(1))
	left.add_child(_make_label("当前格最终合成画面。\n点选气泡或大字，可拖动位置。"))

	var split_right := HSplitContainer.new()
	split_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_left.add_child(split_right)

	_preview_host = Control.new()
	_preview_host.custom_minimum_size = Vector2(520, 300)
	_preview_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_host.clip_contents = true
	_preview_host.resized.connect(_fit_preview)
	split_right.add_child(_preview_host)
	var preview_bg := ColorRect.new()
	preview_bg.color = Color("171720")
	preview_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_host.add_child(preview_bg)
	_canvas = Control.new()
	_canvas.size = DESIGN_SIZE
	_preview_host.add_child(_canvas)

	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(320, 0)
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_right.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	right_scroll.add_child(right)

	right.add_child(_make_label("当前分镜"))
	var duration_row := HBoxContainer.new()
	right.add_child(duration_row)
	duration_row.add_child(_make_label("最短时长 / 秒"))
	_seconds_spin = SpinBox.new()
	_seconds_spin.min_value = 0.2
	_seconds_spin.max_value = 120
	_seconds_spin.step = 0.1
	_seconds_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seconds_spin.value_changed.connect(_change_frame_duration)
	duration_row.add_child(_seconds_spin)

	right.add_child(_make_label("主字幕（frame.text，可留空）"))
	_frame_text = TextEdit.new()
	_frame_text.custom_minimum_size = Vector2(0, 75)
	_frame_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_frame_text.text_changed.connect(_change_frame_text)
	right.add_child(_frame_text)

	right.add_child(_make_label("气泡 / 旁白 / 弹幕 / 纯Label大字"))
	_caption_list = ItemList.new()
	_caption_list.custom_minimum_size = Vector2(0, 115)
	_caption_list.item_selected.connect(_pick_caption)
	right.add_child(_caption_list)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	_make_button(actions, "＋ 文案框", _add_caption)
	_make_button(actions, "＋ 大字", _add_bare_label)
	_make_button(actions, "－ 删除", _delete_caption)

	right.add_child(_make_label("文案类型"))
	_kind_select = OptionButton.new()
	_kind_select.add_item("对话气泡 · speech")
	_kind_select.add_item("旁白 · narration")
	_kind_select.add_item("观众弹幕 · danmaku")
	_kind_select.add_item("纯Label · 无底框")
	_kind_select.item_selected.connect(_change_kind)
	right.add_child(_kind_select)

	right.add_child(_make_label("文案内容（直接预览换行）"))
	_caption_text = TextEdit.new()
	_caption_text.custom_minimum_size = Vector2(0, 155)
	_caption_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_caption_text.text_changed.connect(_change_caption_text)
	right.add_child(_caption_text)

	right.add_child(_make_label("选中文字后点效果；未选中时作用于整条文案"))
	var effects := HBoxContainer.new()
	right.add_child(effects)
	_make_button(effects, "粗体", _apply_text_tag.bind("[b]", "[/b]"))
	_make_button(effects, "金色", _apply_text_tag.bind("[color=#F2BD40]", "[/color]"))
	_make_button(effects, "抖动", _apply_text_tag.bind("[shake rate=18 level=4]", "[/shake]"))
	var effects_second := HBoxContainer.new()
	right.add_child(effects_second)
	_make_button(effects_second, "波浪", _apply_text_tag.bind("[wave amp=14 freq=3]", "[/wave]"))
	_make_button(effects_second, "脉冲", _apply_text_tag.bind("[pulse freq=2.5 color=#FFD45C]", "[/pulse]"))

	right.add_child(_make_label("字体"))
	_font_select = OptionButton.new()
	_font_select.add_item("项目默认字体")
	_font_select.add_item("思源黑体 / Noto Sans SC")
	_font_select.add_item("站酷快乐体 / ZCOOL KuaiLe")
	_font_select.item_selected.connect(_change_font)
	right.add_child(_font_select)

	var typography := HBoxContainer.new()
	right.add_child(typography)
	typography.add_child(_make_label("字号"))
	_font_size_spin = SpinBox.new()
	_font_size_spin.min_value = 12
	_font_size_spin.max_value = 300
	_font_size_spin.step = 1
	_font_size_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_font_size_spin.value_changed.connect(_change_font_size)
	typography.add_child(_font_size_spin)
	typography.add_child(_make_label("颜色"))
	_font_color_button = ColorPickerButton.new()
	_font_color_button.custom_minimum_size = Vector2(60, 30)
	_font_color_button.color_changed.connect(_change_text_color)
	typography.add_child(_font_color_button)

	right.add_child(_make_label("位置 / 尺寸（1920×1080 原图坐标）"))
	_add_spin(right, "X", "x", -800, 2600, 1)
	_add_spin(right, "Y", "y", -800, 1600, 1)
	_add_spin(right, "宽", "w", 50, 2400, 1)
	_add_spin(right, "高", "h", 40, 1500, 1)
	right.add_child(_make_label("气泡尾巴目标坐标，-1 表示隐藏"))
	_add_spin(right, "尾巴 X", "tail_x", -1, 2600, 1)
	_add_spin(right, "尾巴 Y", "tail_y", -1, 1800, 1)
	right.add_child(_make_label("入场时序"))
	_add_spin(right, "延迟 / 秒", "delay", 0, 60, 0.05)
	_hint = _make_label("纯Label没有背景或气泡尾巴。字体来自现有项目；原画只读。")
	right.add_child(_hint)

	_status = Label.new()
	_status.text = "载入完成；修改前请确认所在分支。"
	base.add_child(_status)


func _make_label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _make_button(parent: Control, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _add_spin(parent: Control, title: String, field: String, low: float, high: float, increment: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _make_label(title)
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = increment
	spin.allow_greater = false
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_change_field.bind(field))
	row.add_child(spin)
	_field_spins[field] = spin


func _switch_sequence(part: int) -> void:
	_part = part
	_sequence = _opening if part == 0 else _ending
	_frame_index = 0
	_caption_index = -1
	_section_label.text = "开头 P1–P4 / 13格" if part == 0 else "结局 P5–P6 / 6格"
	_refresh_frame_list()
	_show_frame()
	_status.text = "当前：%s。● 代表未保存。" % ("开头" if part == 0 else "结局")


func _frame() -> ComicFrame:
	if _sequence == null or _frame_index < 0 or _frame_index >= _sequence.frames.size():
		return null
	return _sequence.frames[_frame_index]


func _caption() -> ComicCaption:
	var frame := _frame()
	if frame == null or _caption_index < 0 or _caption_index >= frame.captions.size():
		return null
	return frame.captions[_caption_index]


func _refresh_frame_list() -> void:
	_frame_list.clear()
	for i in range(_sequence.frames.size()):
		var frame: ComicFrame = _sequence.frames[i]
		var act := "分镜"
		if not frame.textures.is_empty() and frame.textures[-1] != null:
			act = frame.textures[-1].resource_path.get_base_dir().get_file()
		_frame_list.add_item("%02d  %s  · %d条文案" % [i + 1, act, frame.captions.size()])
	_frame_list.select(_frame_index)


func _pick_frame(index: int) -> void:
	_frame_index = index
	_caption_index = -1
	_show_frame()


func _go_relative(direction: int) -> void:
	_frame_index = clampi(_frame_index + direction, 0, _sequence.frames.size() - 1)
	_caption_index = -1
	_frame_list.select(_frame_index)
	_show_frame()


func _show_frame() -> void:
	_refresh_caption_list()
	_refresh_form()
	_render_preview()


func _refresh_caption_list() -> void:
	_caption_list.clear()
	var frame := _frame()
	if frame == null:
		return
	for i in range(frame.captions.size()):
		var value: ComicCaption = frame.captions[i]
		var fragment := value.text.replace("\n", " ")
		if fragment.length() > 13:
			fragment = fragment.substr(0, 13) + "…"
		_caption_list.add_item("%d · %s · %s" % [i + 1, value.kind, fragment])
	if _caption_index >= 0 and _caption_index < frame.captions.size():
		_caption_list.select(_caption_index)


func _pick_caption(index: int) -> void:
	_caption_index = index
	_refresh_form()
	_render_preview()


func _refresh_form() -> void:
	_syncing = true
	var frame := _frame()
	if frame != null:
		_seconds_spin.value = frame.seconds
		_frame_text.text = frame.text
	var value := _caption()
	var active := value != null
	_caption_text.editable = active
	_kind_select.disabled = not active
	_font_select.disabled = not active
	_font_size_spin.editable = active
	_font_color_button.disabled = not active
	for field in _field_spins:
		var spin: SpinBox = _field_spins[field]
		spin.editable = active
	if active:
		_caption_text.text = value.text
		_kind_select.select(maxi(0, CAPTION_KINDS.find(value.kind)))
		_font_select.select(maxi(0, FONT_PATHS.find(value.font_path)))
		_font_size_spin.value = value.font_size
		var default_color := Color("fff9e9") if value.kind in ["narration", "label"] else Color("31271f")
		_font_color_button.color = value.text_color if value.text_color.a > 0.0 else default_color
		_field_spins["x"].value = value.rect.position.x
		_field_spins["y"].value = value.rect.position.y
		_field_spins["w"].value = value.rect.size.x
		_field_spins["h"].value = value.rect.size.y
		_field_spins["tail_x"].value = value.tail.x
		_field_spins["tail_y"].value = value.tail.y
		_field_spins["delay"].value = value.delay
	else:
		_caption_text.text = ""
	_syncing = false


func _render_preview() -> void:
	if _canvas == null:
		return
	for child in _canvas.get_children():
		_canvas.remove_child(child)
		child.queue_free()
	var frame := _frame()
	if frame == null:
		return
	for i in range(frame.textures.size()):
		var texture := frame.textures[i]
		if texture == null or i >= frame.positions.size():
			continue
		var layer := TextureRect.new()
		layer.texture = texture
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.position = frame.positions[i]
		layer.size = texture.get_size()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(layer)

	if not frame.text.is_empty():
		var text_label := RichTextLabel.new()
		text_label.position = frame.text_position
		text_label.size = frame.text_size
		text_label.bbcode_enabled = true
		text_label.text = frame.text
		text_label.scroll_active = false
		text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text_label.add_theme_font_size_override("normal_font_size", 36)
		text_label.add_theme_color_override("default_color", Color.WHITE)
		text_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		text_label.add_theme_constant_override("shadow_offset_x", 3)
		text_label.add_theme_constant_override("shadow_offset_y", 3)
		text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_canvas.add_child(text_label)

	for i in range(frame.captions.size()):
		var value: ComicCaption = frame.captions[i]
		var view := ComicCaptionView.new()
		view.setup(value)
		_canvas.add_child(view)
		view.label.visible_characters = -1
		var hotspot := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color("fbbf24") if i == _caption_index else Color(0, 0, 0, 0)
		style.set_border_width_all(4 if i == _caption_index else 0)
		hotspot.add_theme_stylebox_override("panel", style)
		hotspot.position = value.rect.position
		hotspot.size = value.rect.size
		hotspot.mouse_filter = Control.MOUSE_FILTER_STOP
		hotspot.mouse_default_cursor_shape = Control.CURSOR_MOVE
		hotspot.gui_input.connect(_on_canvas_caption_input.bind(i))
		_canvas.add_child(hotspot)
	_fit_preview()


func _fit_preview() -> void:
	if _canvas == null or _preview_host == null:
		return
	var factor := minf(_preview_host.size.x / DESIGN_SIZE.x, _preview_host.size.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (_preview_host.size - DESIGN_SIZE * factor) / 2.0


func _on_canvas_caption_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_caption_index = index
		_dragging = true
		_drag_mouse_origin = get_global_mouse_position()
		_drag_rect_origin = _caption().rect.position
		_refresh_caption_list()
		_refresh_form()
		_render_preview()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode == KEY_S:
		_save_all()
		get_viewport().set_input_as_handled()
	if not _dragging:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		var value := _caption()
		if value == null or _canvas.scale.x <= 0.0:
			return
		var delta := (get_global_mouse_position() - _drag_mouse_origin) / _canvas.scale.x
		var p := _drag_rect_origin + Vector2(roundf(delta.x), roundf(delta.y))
		value.rect = Rect2(p, value.rect.size)
		_mark_dirty()
		_refresh_form()
		_render_preview()
		get_viewport().set_input_as_handled()


func _change_frame_duration(value: float) -> void:
	if _syncing or _frame() == null:
		return
	_frame().seconds = value
	_mark_dirty()


func _change_frame_text() -> void:
	if _syncing or _frame() == null:
		return
	_frame().text = _frame_text.text
	_mark_dirty()
	_render_preview()


func _change_kind(index: int) -> void:
	if _syncing or _caption() == null:
		return
	var caption := _caption()
	caption.kind = CAPTION_KINDS[index]
	if caption.kind == "label" and caption.font_size == 30:
		caption.font_size = 140
		if caption.text_color.a == 0:
			caption.text_color = Color("fff9e9")
	_refresh_form()
	_mark_dirty()
	_refresh_caption_list()
	_render_preview()


func _change_font(index: int) -> void:
	if _syncing or _caption() == null:
		return
	_caption().font_path = FONT_PATHS[index]
	_mark_dirty()
	_render_preview()


func _change_font_size(number: float) -> void:
	if _syncing or _caption() == null:
		return
	_caption().font_size = int(number)
	_mark_dirty()
	_render_preview()


func _change_text_color(color: Color) -> void:
	if _syncing or _caption() == null:
		return
	_caption().text_color = color
	_mark_dirty()
	_render_preview()


func _text_offset(source: String, line_number: int, column: int) -> int:
	var lines := source.split("\n", true)
	var offset := 0
	for index in range(mini(line_number, lines.size())):
		offset += lines[index].length() + 1
	return offset + column


func _apply_text_tag(open_tag: String, close_tag: String) -> void:
	if _caption() == null:
		return
	var source := _caption_text.text
	if source.is_empty():
		return
	var first := 0
	var last := source.length()
	if _caption_text.has_selection():
		first = _text_offset(source, _caption_text.get_selection_from_line(), _caption_text.get_selection_from_column())
		last = _text_offset(source, _caption_text.get_selection_to_line(), _caption_text.get_selection_to_column())
	var middle := source.substr(first, last - first)
	_caption_text.text = source.substr(0, first) + open_tag + middle + close_tag + source.substr(last)
	_change_caption_text()


func _change_caption_text() -> void:
	if _syncing or _caption() == null:
		return
	_caption().text = _caption_text.text
	_mark_dirty()
	_refresh_caption_list()
	_render_preview()


func _change_field(number: float, field: String) -> void:
	if _syncing or _caption() == null:
		return
	var value := _caption()
	match field:
		"x":
			value.rect = Rect2(Vector2(number, value.rect.position.y), value.rect.size)
		"y":
			value.rect = Rect2(Vector2(value.rect.position.x, number), value.rect.size)
		"w":
			value.rect = Rect2(value.rect.position, Vector2(number, value.rect.size.y))
		"h":
			value.rect = Rect2(value.rect.position, Vector2(value.rect.size.x, number))
		"tail_x":
			value.tail.x = number
		"tail_y":
			value.tail.y = number
		"delay":
			value.delay = number
	_mark_dirty()
	_render_preview()


func _add_caption() -> void:
	var frame := _frame()
	if frame == null:
		return
	var value := ComicCaption.new()
	value.kind = "narration"
	value.text = "【填写文案】"
	value.rect = Rect2(920, 790, 690, 165)
	value.tail = Vector2(-1, -1)
	value.delay = 0.55
	frame.captions.append(value)
	_caption_index = frame.captions.size() - 1
	_mark_dirty()
	_refresh_frame_list()
	_show_frame()


func _add_bare_label() -> void:
	var frame := _frame()
	if frame == null:
		return
	var existing_labels := 0
	for previous in frame.captions:
		if previous.kind == "label":
			existing_labels += 1
	var value := ComicCaption.new()
	value.kind = "label"
	value.text = "大字"
	value.font_size = 150
	value.font_path = FONT_PATHS[2]
	value.text_color = Color("fff9e9")
	value.rect = Rect2(180 if existing_labels % 2 == 0 else 1110, 430, 630, 240)
	value.tail = Vector2(-1, -1)
	value.delay = 0.3
	frame.captions.append(value)
	_caption_index = frame.captions.size() - 1
	_mark_dirty()
	_refresh_frame_list()
	_show_frame()


func _delete_caption() -> void:
	var frame := _frame()
	if frame == null or _caption() == null:
		return
	frame.captions.remove_at(_caption_index)
	_caption_index = mini(_caption_index, frame.captions.size() - 1)
	_mark_dirty()
	_refresh_frame_list()
	_show_frame()


func _mark_dirty() -> void:
	_dirty[_part] = true
	_status.text = "● %s文案已修改，记得 Ctrl+S 保存" % ("开头" if _part == 0 else "结局")


func _save_all() -> void:
	var failed: Array[String] = []
	var saved: Array[String] = []
	if _dirty[0]:
		var error := ResourceSaver.save(_opening, OPENING_PATH)
		if error == OK:
			_dirty[0] = false
			saved.append("开头")
		else:
			failed.append("开头：" + error_string(error))
	if _dirty[1]:
		var error := ResourceSaver.save(_ending, ENDING_PATH)
		if error == OK:
			_dirty[1] = false
			saved.append("结局")
		else:
			failed.append("结局：" + error_string(error))
	if not failed.is_empty():
		_status.text = "保存失败：" + "、".join(failed)
	elif saved.is_empty():
		_status.text = "当前没有未保存的改动。"
	else:
		_status.text = "已保存到 data/comics/*.tres：" + "、".join(saved)
