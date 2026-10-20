extends Control

const TABLE_PATH := "res://data/source_tables/24_新手教学配置.csv"
const LEVEL_TABLE_PATH := "res://data/source_tables/02_主播关卡.csv"
const DEFAULT_CONFIG_ID := "tutorial_level_001"
const REQUIRED_HEADERS: Array[String] = [
	"tutorial_config_id", "step_id", "step_order", "trigger_event",
	"hint_text", "completion_event", "enabled", "notes"
]

var _headers := PackedStringArray()
var _rows: Array[Dictionary] = []
var _visible_indices: Array[int] = []
var _known_configs: Dictionary = {}
var _filter := DEFAULT_CONFIG_ID
var _selected := -1
var _syncing := false
var _dirty := false
var _table_loaded := false

var _config_picker: OptionButton
var _step_list: ItemList
var _fields: Dictionary = {}
var _order: SpinBox
var _enabled: CheckBox
var _hint: TextEdit
var _preview: Label
var _validation: Label
var _status: Label
var _reload_confirm: ConfirmationDialog
var _delete_confirm: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	if _read_table():
		_read_level_configs()
		_refresh_config_picker(DEFAULT_CONFIG_ID)
		_status.text = "已载入正式 24 表。修改后点击「保存 CSV」；下一次启动教学时读取新内容。"
	else:
		_status.text = "读取失败：请检查 24 表路径和表头。"


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 7)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	var title := Label.new()
	title.text = "新手教学编辑器 · 24 表"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	_config_picker = OptionButton.new()
	_config_picker.custom_minimum_size = Vector2(290, 0)
	_config_picker.item_selected.connect(_on_filter_changed)
	toolbar.add_child(_config_picker)
	_button(toolbar, "＋ 新建步骤", _add_step)
	_button(toolbar, "复制步骤", _duplicate_step)
	_button(toolbar, "－ 删除", _ask_delete)
	_button(toolbar, "重载", _ask_reload)
	_button(toolbar, "保存 CSV  Ctrl+S", _save)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(340, 0)
	left.add_child(_label("步骤列表（按执行顺序）"))
	_step_list = ItemList.new()
	_step_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_step_list.item_selected.connect(_select_step)
	left.add_child(_step_list)
	var moves := HBoxContainer.new()
	left.add_child(moves)
	_button(moves, "↑ 上移", _move.bind(-1))
	_button(moves, "↓ 下移", _move.bind(1))
	left.add_child(_label("选择步骤后，在右侧修改字段。"))
	split.add_child(left)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(500, 0)
	split.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 7)
	scroll.add_child(form)

	form.add_child(_label("教学配置 ID（须与 02 关卡表关联）"))
	_add_line(form, "tutorial_config_id", "配置 ID")
	_add_line(form, "step_id", "步骤 ID（存档依赖此 ID）")
	var order_row := HBoxContainer.new()
	order_row.add_child(_label("执行顺序"))
	_order = SpinBox.new()
	_order.min_value = 1
	_order.max_value = 999
	_order.step = 1
	_order.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_order.value_changed.connect(_order_changed)
	order_row.add_child(_order)
	form.add_child(order_row)
	_enabled = CheckBox.new()
	_enabled.text = "启用此步骤"
	_enabled.toggled.connect(_enabled_changed)
	form.add_child(_enabled)

	form.add_child(_label("触发事件 ID（程序发出此事件时显示提示）"))
	_add_line(form, "trigger_event", "触发事件")
	form.add_child(_label("提示文案（支持多行和空行）"))
	_hint = TextEdit.new()
	_hint.custom_minimum_size.y = 145
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_hint.text_changed.connect(_hint_changed)
	form.add_child(_hint)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size.y = 105
	form.add_child(preview_panel)
	var preview_box := VBoxContainer.new()
	preview_panel.add_child(preview_box)
	preview_box.add_child(_label("文案预览（检查换行）"))
	_preview = _label("选择步骤以预览文案。")
	_preview.custom_minimum_size.y = 65
	_preview.add_theme_font_size_override("font_size", 22)
	_preview.add_theme_color_override("font_color", Color("#f3d89c"))
	preview_box.add_child(_preview)

	form.add_child(_label("完成事件 ID（发生后推进到下一步）"))
	_add_line(form, "completion_event", "完成事件")
	form.add_child(_label("策划备注（不在游戏内显示）"))
	_add_line(form, "notes", "备注")
	form.add_child(_label("Plan B 事件链：pb25_tutorial_begin → pb25_first_player_publish → pb25_paper_type_c_conversion → pb25_fermi_scissors_published → pb25_final_hint_finished。旧版事件链：tutorial_target_available → tutorial_aim_acquired → tutorial_charge_full → tutorial_normal_hit。事件 ID 必须与代码发出的字符串一致。"))
	_validation = _label("")
	form.add_child(_validation)
	_status = _label("准备就绪")
	root.add_child(_status)

	_reload_confirm = ConfirmationDialog.new()
	_reload_confirm.title = "放弃未保存修改？"
	_reload_confirm.dialog_text = "重载会丢弃编辑器内尚未保存的修改。"
	_reload_confirm.confirmed.connect(_reload)
	add_child(_reload_confirm)
	_delete_confirm = ConfirmationDialog.new()
	_delete_confirm.title = "删除教学步骤？"
	_delete_confirm.confirmed.connect(_delete_selected)
	add_child(_delete_confirm)


func _label(text: String) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result


func _button(parent: Control, text: String, action: Callable) -> void:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)


func _add_line(parent: Control, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_child(_label(title))
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(_line_changed.bind(key))
	row.add_child(edit)
	parent.add_child(row)
	_fields[key] = edit


func _read_table() -> bool:
	_table_loaded = false
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		push_error("TutorialEditor: 无法读取 24 表：" + error_string(FileAccess.get_open_error()))
		return false
	_headers = file.get_csv_line()
	for required in REQUIRED_HEADERS:
		if not _headers.has(required):
			push_error("TutorialEditor: 缺少表头 " + required)
			file.close()
			return false
	_rows.clear()
	var line_number := 1
	while not file.eof_reached():
		var values := file.get_csv_line()
		line_number += 1
		if values.size() == 1 and values[0].is_empty():
			continue
		if values.size() != _headers.size():
			push_error("TutorialEditor: 第 %d 行字段数不匹配；为避免漏写数据，已中止读取。" % line_number)
			file.close()
			return false
		var row: Dictionary = {}
		for i in _headers.size():
			row[_headers[i]] = values[i]
		_rows.append(row)
	file.close()
	_dirty = false
	_table_loaded = true
	return true


func _read_level_configs() -> void:
	_known_configs.clear()
	var file := FileAccess.open(LEVEL_TABLE_PATH, FileAccess.READ)
	if file == null:
		return
	var headers := file.get_csv_line()
	var column := headers.find("tutorial_config_id")
	if column >= 0:
		while not file.eof_reached():
			var values := file.get_csv_line()
			if values.size() != headers.size():
				continue
			var id := values[column].strip_edges()
			if not id.is_empty():
				_known_configs[id] = true
	file.close()


func _refresh_config_picker(preferred: String = "") -> void:
	var counts: Dictionary = {}
	for row in _rows:
		var id := str(row.get("tutorial_config_id", "")).strip_edges()
		if not id.is_empty():
			counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array[String] = []
	for id in counts:
		ids.append(str(id))
	ids.sort()
	_config_picker.clear()
	_config_picker.add_item("全部配置（%d 步）" % _rows.size())
	_config_picker.set_item_metadata(0, "*")
	for id in ids:
		_config_picker.add_item("%s（%d 步）" % [id, counts[id]])
		_config_picker.set_item_metadata(_config_picker.item_count - 1, id)
	var target := preferred if not preferred.is_empty() else _filter
	var choice := 0
	for i in _config_picker.item_count:
		if str(_config_picker.get_item_metadata(i)) == target:
			choice = i
			break
	_config_picker.select(choice)
	_filter = str(_config_picker.get_item_metadata(choice))
	_refresh_list()


func _on_filter_changed(index: int) -> void:
	_filter = str(_config_picker.get_item_metadata(index))
	_refresh_list()


func _matching_indices(config_id: String) -> Array[int]:
	var result: Array[int] = []
	for i in _rows.size():
		if config_id == "*" or str(_rows[i].get("tutorial_config_id", "")) == config_id:
			result.append(i)
	result.sort_custom(func(a: int, b: int) -> bool:
		var left := int(_rows[a].get("step_order", "0"))
		var right := int(_rows[b].get("step_order", "0"))
		return a < b if left == right else left < right
	)
	return result


func _refresh_list(preferred_row: int = -1) -> void:
	_step_list.clear()
	_visible_indices = _matching_indices(_filter)
	for index in _visible_indices:
		var row: Dictionary = _rows[index]
		var state := "✓" if str(row.get("enabled", "")).to_lower() == "true" else "○"
		var hint := _display_hint(str(row.get("hint_text", ""))).replace("\n", " / ")
		if hint.length() > 24:
			hint = hint.substr(0, 24) + "…"
		_step_list.add_item("%02d  %s  %s  ·  %s" % [
			int(row.get("step_order", "0")), state, row.get("step_id", "未命名"), hint
		])
	var selected_visible := _visible_indices.find(preferred_row)
	if selected_visible < 0 and not _visible_indices.is_empty():
		selected_visible = 0
	if selected_visible >= 0:
		_step_list.select(selected_visible)
		_select_step(selected_visible)
	else:
		_selected = -1
		_refresh_form()


func _select_step(visible_index: int) -> void:
	if visible_index < 0 or visible_index >= _visible_indices.size():
		return
	_selected = _visible_indices[visible_index]
	_refresh_form()


func _refresh_form() -> void:
	_syncing = true
	var active := _selected >= 0 and _selected < _rows.size()
	for key in _fields:
		var field := _fields[key] as LineEdit
		field.editable = active
		field.text = str(_rows[_selected].get(key, "")) if active else ""
	_order.editable = active
	_enabled.disabled = not active
	_hint.editable = active
	if active:
		_order.value = int(_rows[_selected].get("step_order", "1"))
		_enabled.button_pressed = str(_rows[_selected].get("enabled", "")).to_lower() == "true"
		_hint.text = _display_hint(str(_rows[_selected].get("hint_text", "")))
		_preview.text = _hint.text
	else:
		_order.value = 1
		_enabled.button_pressed = false
		_hint.text = ""
		_preview.text = "选择步骤以预览文案。"
	_syncing = false
	_update_validation()


func _line_changed(value: String, key: String) -> void:
	if _syncing or _selected < 0:
		return
	_rows[_selected][key] = value
	_mark_dirty()
	_update_validation()


func _order_changed(value: float) -> void:
	if _syncing or _selected < 0:
		return
	_rows[_selected]["step_order"] = str(roundi(value))
	_mark_dirty()
	_refresh_list(_selected)


func _enabled_changed(value: bool) -> void:
	if _syncing or _selected < 0:
		return
	_rows[_selected]["enabled"] = "true" if value else "false"
	_mark_dirty()
	_refresh_list(_selected)


func _hint_changed() -> void:
	if _syncing or _selected < 0:
		return
	_rows[_selected]["hint_text"] = _encode_hint(_hint.text)
	_preview.text = _hint.text
	_mark_dirty()
	_update_validation()


func _display_hint(value: String) -> String:
	return value.replace("\\n", "\n")


func _encode_hint(value: String) -> String:
	return value.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\\n")


func _mark_dirty() -> void:
	_dirty = true
	_status.text = "● 有未保存修改。保存会直接写入正式 24 表 CSV。"


func _errors() -> Array[String]:
	var errors: Array[String] = []
	var seen_ids: Dictionary = {}
	var seen_orders: Dictionary = {}
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var config_id := str(row.get("tutorial_config_id", "")).strip_edges()
		var step_id := str(row.get("step_id", "")).strip_edges()
		var enabled := str(row.get("enabled", "")).to_lower() == "true"
		var order := int(row.get("step_order", "0"))
		if config_id.is_empty():
			errors.append("第 %d 行：配置 ID 为空。" % (i + 2))
		if step_id.is_empty():
			errors.append("第 %d 行：步骤 ID 为空。" % (i + 2))
		elif seen_ids.has(step_id):
			errors.append("步骤 ID 重复：%s。" % step_id)
		else:
			seen_ids[step_id] = true
		if order < 1:
			errors.append("%s：执行顺序必须大于 0。" % step_id)
		var order_key := "%s|%d" % [config_id, order]
		if seen_orders.has(order_key):
			errors.append("%s：配置内执行顺序 %d 重复。" % [config_id, order])
		else:
			seen_orders[order_key] = true
		if enabled:
			if str(row.get("trigger_event", "")).strip_edges().is_empty():
				errors.append("%s：启用步骤缺少触发事件 ID。" % step_id)
			if str(row.get("completion_event", "")).strip_edges().is_empty():
				errors.append("%s：启用步骤缺少完成事件 ID。" % step_id)
			if str(row.get("hint_text", "")).strip_edges().is_empty():
				errors.append("%s：启用步骤的提示文案为空。" % step_id)
	return errors


func _update_validation() -> void:
	var errors := _errors()
	var warnings: Array[String] = []
	for row in _rows:
		var id := str(row.get("tutorial_config_id", "")).strip_edges()
		if not id.is_empty() and not _known_configs.is_empty() and not _known_configs.has(id):
			var warning := "配置 %s 未关联到 02 关卡表。" % id
			if not warnings.has(warning):
				warnings.append(warning)
	if not errors.is_empty():
		_validation.add_theme_color_override("font_color", Color("#ff7777"))
		_validation.text = "❌ 保存阻断（%d 项）：\n" % errors.size()
		for index in mini(errors.size(), 8):
			_validation.text += "• " + errors[index] + "\n"
		if errors.size() > 8:
			_validation.text += "……还有 %d 项。" % (errors.size() - 8)
	elif not warnings.is_empty():
		_validation.add_theme_color_override("font_color", Color("#e8c477"))
		_validation.text = "✓ 字段检查通过。\n⚠ " + "\n".join(warnings)
	else:
		_validation.add_theme_color_override("font_color", Color("#8bdc95"))
		_validation.text = "✓ 保存前检查通过：%d 个步骤。" % _rows.size()


func _save() -> void:
	if not _table_loaded:
		_status.text = "原始 24 表未成功读取，已禁止写入，避免覆盖数据。"
		return
	var errors := _errors()
	if not errors.is_empty():
		_update_validation()
		_status.text = "保存已阻止：先修复右侧列出的错误。"
		return
	var file := FileAccess.open(TABLE_PATH, FileAccess.WRITE)
	if file == null:
		_status.text = "保存失败：" + error_string(FileAccess.get_open_error())
		return
	file.store_csv_line(_headers)
	for row in _rows:
		var values := PackedStringArray()
		for header in _headers:
			values.append(str(row.get(header, "")))
		file.store_csv_line(values)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		_status.text = "写入失败：" + error_string(result)
		return
	_dirty = false
	var preferred := _filter
	if _selected >= 0 and _selected < _rows.size():
		preferred = str(_rows[_selected].get("tutorial_config_id", _filter))
	_refresh_config_picker(preferred)
	_status.text = "✓ 已保存正式 24 表。下次启动教学/新开一局时生效。"
	_update_validation()


func _add_step() -> void:
	var config_id := _filter if _filter != "*" else DEFAULT_CONFIG_ID
	var row: Dictionary = {}
	for header in _headers:
		row[header] = ""
	row["tutorial_config_id"] = config_id
	row["step_id"] = _unique_id("tutorial_new_step")
	row["step_order"] = str(_max_order(config_id) + 1)
	row["hint_text"] = "在这里填写教学提示"
	row["enabled"] = "false"
	row["notes"] = "新建步骤：填写有效事件 ID 后再启用。"
	_rows.append(row)
	_dirty = true
	var new_index := _rows.size() - 1
	_refresh_config_picker(config_id)
	_refresh_list(new_index)
	_status.text = "已新增禁用步骤。填写事件 ID、检查顺序后再启用。"


func _duplicate_step() -> void:
	if _selected < 0:
		_status.text = "请先选择要复制的步骤。"
		return
	var source: Dictionary = _rows[_selected]
	var row: Dictionary = source.duplicate(true)
	row["step_id"] = _unique_id(str(source.get("step_id", "tutorial_step")) + "_copy")
	row["step_order"] = str(_max_order(str(source.get("tutorial_config_id", ""))) + 1)
	row["trigger_event"] = ""
	row["completion_event"] = ""
	row["enabled"] = "false"
	row["notes"] = "复制自 %s；请填写有效的触发/完成事件 ID。" % str(source.get("step_id", ""))
	_rows.append(row)
	_dirty = true
	var new_index := _rows.size() - 1
	_refresh_config_picker(str(row.get("tutorial_config_id", "")))
	_refresh_list(new_index)
	_status.text = "已复制为禁用步骤，避免重复事件意外推进教学。"


func _ask_delete() -> void:
	if _selected < 0:
		_status.text = "请先选择要删除的步骤。"
		return
	_delete_confirm.dialog_text = "确定删除步骤「%s」？" % str(_rows[_selected].get("step_id", ""))
	_delete_confirm.popup_centered()


func _delete_selected() -> void:
	if _selected < 0:
		return
	var config_id := str(_rows[_selected].get("tutorial_config_id", ""))
	_rows.remove_at(_selected)
	_renumber(config_id)
	_dirty = true
	_refresh_config_picker(_filter)
	_status.text = "步骤已删除；点击保存 CSV 才会写入文件。"


func _ask_reload() -> void:
	if _dirty:
		_reload_confirm.popup_centered()
	else:
		_reload()


func _reload() -> void:
	var preferred := _filter
	if not _read_table():
		_status.text = "重载失败，请检查 CSV 文件。"
		return
	_read_level_configs()
	_refresh_config_picker(preferred)
	_status.text = "已从磁盘重载 24 表；未保存修改已丢弃。"


func _move(direction: int) -> void:
	if _selected < 0:
		_status.text = "请先选择要移动的步骤。"
		return
	var config_id := str(_rows[_selected].get("tutorial_config_id", ""))
	var indices := _matching_indices(config_id)
	var position := indices.find(_selected)
	var target := position + direction
	if position < 0 or target < 0 or target >= indices.size():
		return
	var temporary := indices[position]
	indices[position] = indices[target]
	indices[target] = temporary
	for i in indices.size():
		_rows[indices[i]]["step_order"] = str(i + 1)
	_dirty = true
	_refresh_config_picker(_filter)
	_refresh_list(_selected)
	_status.text = "步骤顺序已调整；保存后写入 CSV。"


func _renumber(config_id: String) -> void:
	var indices := _matching_indices(config_id)
	for i in indices.size():
		_rows[indices[i]]["step_order"] = str(i + 1)


func _max_order(config_id: String) -> int:
	var maximum := 0
	for row in _rows:
		if str(row.get("tutorial_config_id", "")) == config_id:
			maximum = maxi(maximum, int(row.get("step_order", "0")))
	return maximum


func _unique_id(base: String) -> String:
	var candidate := base
	var suffix := 2
	while _has_id(candidate):
		candidate = "%s_%02d" % [base, suffix]
		suffix += 1
	return candidate


func _has_id(id: String) -> bool:
	for row in _rows:
		if str(row.get("step_id", "")) == id:
			return true
	return false


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()
