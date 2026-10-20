extends Control

const TABLES: Array[Dictionary] = [
	{
		"label": "20 · 主播气泡对白",
		"path": "res://data/source_tables/20_主播气泡对白.csv",
		"id_key": "dialogue_id",
		"text_key": "text",
		"editable": ["text", "trigger_key", "line_order", "display_duration_s", "trigger_time_s", "enabled", "notes", "random_weight"],
		"readonly": ["dialogue_id", "streamer_id", "story_config_id", "speaker_side", "trigger_type", "source_word_id", "priority"],
		"numeric": ["display_duration_s", "trigger_time_s", "line_order", "random_weight"]
	},
	{
		"label": "19 · 直播评论",
		"path": "res://data/source_tables/19_直播评论词库.csv",
		"id_key": "comment_id",
		"text_key": "text",
		"editable": ["text", "viewer_id", "weight", "enabled", "notes"],
		"readonly": ["comment_id", "streamer_id"],
		"numeric": ["weight"]
	},
	{
		"label": "25 · 观众昵称",
		"path": "res://data/source_tables/25_直播观众账号.csv",
		"id_key": "viewer_id",
		"text_key": "display_name",
		"editable": ["display_name", "weight", "enabled", "notes"],
		"readonly": ["viewer_id", "audience_type", "side_scope", "streamer_id"],
		"numeric": ["weight"]
	},
	{
		"label": "03 · 神谕话语",
		"path": "res://data/source_tables/03_普通词库.csv",
		"id_key": "word_id",
		"text_key": "text",
		"editable": ["text", "tendency", "strength", "weight", "enabled", "notes", "rich_text"],
		"readonly": ["word_id", "pool_id", "source_streamer_id"],
		"numeric": ["strength", "weight"]
	},
	{
		"label": "04 · 矛盾话语",
		"path": "res://data/source_tables/04_矛盾内容.csv",
		"id_key": "contradiction_id",
		"text_key": "text",
		"editable": ["text", "enabled", "notes"],
		"readonly": ["contradiction_id", "set_id", "streamer_id", "type"],
		"numeric": []
	}
]

var _table_index := 0
var _headers := PackedStringArray()
var _rows: Array[Dictionary] = []
var _visible_indices: Array[int] = []
var _selected_row := -1
var _syncing := false
var _dirty := false
var _loaded := false
var _pending_table_index := -1
var _field_controls: Dictionary = {}

var _source_picker: OptionButton
var _search: LineEdit
var _item_list: ItemList
var _form: VBoxContainer
var _preview_panel: PanelContainer
var _preview_text: RichTextLabel
var _preview_meta: Label
var _reference_ids_cache: Dictionary = {}
var _status: Label
var _validation: Label
var _switch_confirm: ConfirmationDialog
var _reload_confirm: ConfirmationDialog


func _ready() -> void:
	_build_ui()
	_load_table(0)


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	var title := Label.new()
	title.text = "游戏文案库"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(title)
	_source_picker = OptionButton.new()
	_source_picker.custom_minimum_size = Vector2(235, 0)
	for index in TABLES.size():
		_source_picker.add_item(str(TABLES[index]["label"]))
		_source_picker.set_item_metadata(index, index)
	_source_picker.item_selected.connect(_on_source_selected)
	toolbar.add_child(_source_picker)
	_button(toolbar, "复制条目（默认禁用）", _duplicate_selected)
	_button(toolbar, "重载", _ask_reload)
	_button(toolbar, "保存当前表  Ctrl+S", _save)

	_search = LineEdit.new()
	_search.placeholder_text = "搜索 ID、文案、主播、触发类型、备注……"
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	root.add_child(_search)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_child(_label("条目列表"))
	_item_list = ItemList.new()
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_select_visible_row)
	left.add_child(_item_list)
	split.add_child(left)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(480, 0)
	split.add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_form.add_theme_constant_override("separation", 6)
	scroll.add_child(_form)

	_validation = _label("")
	root.add_child(_validation)
	_status = _label("准备就绪")
	root.add_child(_status)

	_switch_confirm = ConfirmationDialog.new()
	_switch_confirm.title = "切换文案表？"
	_switch_confirm.dialog_text = "当前表有未保存修改。切换会丢弃这些修改；如需保留，请先保存。"
	_switch_confirm.confirmed.connect(_confirm_switch_table)
	add_child(_switch_confirm)

	_reload_confirm = ConfirmationDialog.new()
	_reload_confirm.title = "放弃未保存修改？"
	_reload_confirm.dialog_text = "重载会丢弃当前表的未保存修改。"
	_reload_confirm.confirmed.connect(_reload_current_table)
	add_child(_reload_confirm)


func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _button(parent: Control, value: String, action: Callable) -> void:
	var button := Button.new()
	button.text = value
	button.pressed.connect(action)
	parent.add_child(button)


func _on_source_selected(index: int) -> void:
	if index == _table_index:
		return
	if _dirty:
		_pending_table_index = index
		_source_picker.select(_table_index)
		_switch_confirm.popup_centered()
		return
	_load_table(index)


func _confirm_switch_table() -> void:
	if _pending_table_index >= 0:
		_load_table(_pending_table_index)
	_pending_table_index = -1


func _load_table(index: int) -> void:
	if index < 0 or index >= TABLES.size():
		return
	_loaded = false
	var config: Dictionary = TABLES[index]
	var file := FileAccess.open(str(config["path"]), FileAccess.READ)
	if file == null:
		_source_picker.select(_table_index)
		_set_status("读取失败：" + str(config["path"]) + " · " + error_string(FileAccess.get_open_error()))
		return
	var headers := file.get_csv_line()
	if headers.is_empty() or not headers.has(str(config["id_key"])) or not headers.has(str(config["text_key"])):
		file.close()
		_source_picker.select(_table_index)
		_set_status("读取失败：CSV 缺少 ID 或文案字段，已禁止保存。")
		return
	var rows: Array[Dictionary] = []
	var line_number := 1
	while not file.eof_reached():
		var values := file.get_csv_line()
		line_number += 1
		if values.size() == 1 and values[0].is_empty():
			continue
		if values.size() != headers.size():
			file.close()
			_source_picker.select(_table_index)
			_set_status("读取失败：第 %d 行字段数异常，已禁止保存以保护原始数据。" % line_number)
			return
		var row: Dictionary = {}
		for column in headers.size():
			row[headers[column]] = values[column]
		rows.append(row)
	file.close()

	_table_index = index
	_headers = headers
	_rows = rows
	_selected_row = -1
	_dirty = false
	_loaded = true
	_syncing = true
	_source_picker.select(index)
	_search.text = ""
	_syncing = false
	_refresh_list()
	_set_status("已载入 %s：%d 条。每张表独立保存，保留原有数据结构。" % [config["label"], _rows.size()])


func _on_search_changed(_value: String) -> void:
	_refresh_list(_selected_row)


func _refresh_list(preferred_row: int = -1) -> void:
	_item_list.clear()
	_visible_indices.clear()
	var query := _search.text.strip_edges().to_lower()
	var config: Dictionary = TABLES[_table_index]
	var id_key := str(config["id_key"])
	var text_key := str(config["text_key"])
	for row_index in _rows.size():
		var row: Dictionary = _rows[row_index]
		var searchable := ""
		for value in row.values():
			searchable += " " + str(value)
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		_visible_indices.append(row_index)
		var entry_id := str(row.get(id_key, "未命名"))
		var copy := str(row.get(text_key, "")).replace("\n", " ")
		if copy.length() > 48:
			copy = copy.substr(0, 48) + "…"
		var enabled_text := ""
		if row.has("enabled"):
			enabled_text = "✓ " if str(row["enabled"]).to_lower() == "true" else "○ "
		var context := _context_for_row(row)
		_item_list.add_item("%s%s · %s · %s" % [enabled_text, entry_id, context, copy])
	var visible_index := _visible_indices.find(preferred_row)
	if visible_index < 0 and not _visible_indices.is_empty():
		visible_index = 0
	if visible_index >= 0:
		_item_list.select(visible_index)
		_select_visible_row(visible_index)
	else:
		_selected_row = -1
		_refresh_form()


func _context_for_row(row: Dictionary) -> String:
	var keys := ["streamer_id", "story_config_id", "speaker_side", "trigger_type", "tendency", "strength", "audience_type", "side_scope", "type"]
	var parts: Array[String] = []
	for key in keys:
		var value := str(row.get(key, ""))
		if not value.is_empty():
			parts.append(value)
	return " / ".join(parts)


func _select_visible_row(visible_index: int) -> void:
	if visible_index < 0 or visible_index >= _visible_indices.size():
		return
	_selected_row = _visible_indices[visible_index]
	_refresh_form()


func _refresh_form() -> void:
	_syncing = true
	_field_controls.clear()
	for child in _form.get_children():
		child.queue_free()
	var active := _selected_row >= 0 and _selected_row < _rows.size()
	if not active:
		_form.add_child(_label("从左侧选择一条文案。"))
		_preview_panel = null
		_preview_text = null
		_preview_meta = null
		_syncing = false
		return

	var row: Dictionary = _rows[_selected_row]
	var config: Dictionary = TABLES[_table_index]
	var id_key := str(config["id_key"])
	var text_key := str(config["text_key"])
	var heading := _label("%s  ·  %s" % [str(config["label"]), str(row.get(id_key, ""))])
	heading.add_theme_font_size_override("font_size", 18)
	_form.add_child(heading)

	var context := _label("关联信息（用于定位条目；请勿随意修改）\n" + _readonly_summary(row, config))
	context.add_theme_color_override("font_color", Color("#a9b3c2"))
	_form.add_child(context)
	_form.add_child(HSeparator.new())

	for key_value in config["editable"]:
		var key := str(key_value)
		if not _headers.has(key):
			continue
		_add_editor_field(key, str(row.get(key, "")), key == text_key)
	_form.add_child(HSeparator.new())
	_form.add_child(_label("气泡预览（示意样式；实际运行效果以游戏渲染为准）"))
	_build_preview(row, config)
	_syncing = false
	_update_validation()



func _build_preview(row: Dictionary, config: Dictionary) -> void:
	_preview_panel = PanelContainer.new()
	_preview_panel.custom_minimum_size = Vector2(0, 132)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("#292631")
	panel_style.border_color = Color("#d7b86c")
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.content_margin_left = 16
	panel_style.content_margin_top = 12
	panel_style.content_margin_right = 16
	panel_style.content_margin_bottom = 12
	if _table_index == 1:
		panel_style.bg_color = Color("#202b37")
		panel_style.border_color = Color("#83a6c9")
	elif _table_index in [3, 4]:
		panel_style.bg_color = Color("#342e23")
		panel_style.border_color = Color("#d7b86c")
	_preview_panel.add_theme_stylebox_override("panel", panel_style)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 5)
	_preview_meta = Label.new()
	_preview_meta.add_theme_font_size_override("font_size", 12)
	_preview_meta.add_theme_color_override("font_color", Color("#c5bda9"))
	stack.add_child(_preview_meta)
	_preview_text = RichTextLabel.new()
	_preview_text.bbcode_enabled = true
	_preview_text.fit_content = true
	_preview_text.scroll_active = false
	_preview_text.custom_minimum_size = Vector2(0, 68)
	_preview_text.add_theme_font_size_override("normal_font_size", 20)
	_preview_text.add_theme_color_override("default_color", Color("#fff4dd"))
	stack.add_child(_preview_text)
	_preview_panel.add_child(stack)
	_form.add_child(_preview_panel)
	_update_preview(row, config)


func _update_preview(row: Dictionary, config: Dictionary) -> void:
	if _preview_text == null or _preview_meta == null:
		return
	var body := str(row.get(str(config["text_key"]), ""))
	var rich_text := str(row.get("rich_text", "")).strip_edges()
	var style_warning := ""
	_preview_text.bbcode_enabled = false
	_preview_text.text = body
	if _table_index == 3 and not rich_text.is_empty():
		_preview_text.bbcode_enabled = true
		_preview_text.text = rich_text
		if _preview_text.get_parsed_text() != body:
			_preview_text.bbcode_enabled = false
			_preview_text.text = body
			style_warning = "富文本与正文不一致，游戏运行时会回退纯文本"
	var parts: Array[String] = []
	for key in ["speaker_side", "streamer_id", "trigger_type", "viewer_id", "audience_type", "side_scope", "tendency", "strength", "type"]:
		var value := str(row.get(key, ""))
		if not value.is_empty():
			parts.append(value)
	if not style_warning.is_empty():
		parts.append("⚠ " + style_warning)
	_preview_meta.text = " · ".join(parts) if not parts.is_empty() else str(config["label"])
	_preview_meta.add_theme_color_override("font_color", Color("#ff9a8b") if not style_warning.is_empty() else Color("#c5bda9"))


func _readonly_summary(row: Dictionary, config: Dictionary) -> String:
	var parts: Array[String] = []
	var seen: Dictionary = {}
	for key_value in config["readonly"]:
		var key := str(key_value)
		seen[key] = true
		if row.has(key) and not str(row[key]).is_empty():
			parts.append("%s: %s" % [key, str(row[key])])
	for key in ["trigger_type", "trigger_key", "line_order", "priority", "tendency", "strength", "pool_id", "viewer_id", "audience_type", "side_scope", "set_id", "type"]:
		if row.has(key) and not str(row[key]).is_empty() and not seen.has(key):
			parts.append("%s: %s" % [key, str(row[key])])
	return "\n".join(parts) if not parts.is_empty() else "无额外关联字段"


func _add_editor_field(key: String, value: String, is_main_text: bool) -> void:
	var title := _label(_field_title(key))
	_form.add_child(title)
	if key == "enabled":
		var check := CheckBox.new()
		check.text = "启用此条目"
		check.button_pressed = value.to_lower() == "true"
		check.toggled.connect(_on_checkbox_changed.bind(key))
		_form.add_child(check)
		_field_controls[key] = check
	elif key in ["text", "display_name", "rich_text", "notes"]:
		var edit := TextEdit.new()
		edit.text = value
		edit.custom_minimum_size = Vector2(0, 130 if is_main_text or key == "text" else 72)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		edit.text_changed.connect(_on_text_edit_changed.bind(key))
		_form.add_child(edit)
		_field_controls[key] = edit
	else:
		var edit := LineEdit.new()
		edit.text = value
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(_on_line_edit_changed.bind(key))
		_form.add_child(edit)
		_field_controls[key] = edit


func _field_title(key: String) -> String:
	var names := {
		"text": "文案正文",
		"display_name": "观众昵称",
		"rich_text": "富文本 / 效果标记",
		"enabled": "启用状态",
		"notes": "策划备注",
		"display_duration_s": "气泡显示时长（秒）",
		"trigger_time_s": "触发时间（秒；留空表示由事件/闲聊调度）",
		"random_weight": "随机权重",
		"weight": "抽取权重",
		"tendency": "倾向类型",
		"strength": "强度档位",
		"trigger_key": "触发键（必须对应程序事件或配置键）",
		"line_order": "同一事件内的台词顺序"
	}
	return str(names.get(key, key))


func _on_line_edit_changed(value: String, key: String) -> void:
	_set_field_value(key, value)


func _on_text_edit_changed(key: String) -> void:
	var control := _field_controls.get(key) as TextEdit
	if control == null:
		return
	_set_field_value(key, control.text)


func _on_checkbox_changed(value: bool, key: String) -> void:
	_set_field_value(key, "true" if value else "false")


func _set_field_value(key: String, value: String) -> void:
	if _syncing or not _loaded or _selected_row < 0:
		return
	_rows[_selected_row][key] = value
	_dirty = true
	var config: Dictionary = TABLES[_table_index]
	if _preview_text != null:
		_update_preview(_rows[_selected_row], config)
	_set_status("● 有未保存修改。点击「保存当前表」后才会写入 CSV。")
	_update_validation()


func _update_validation() -> void:
	if _validation == null or not _loaded:
		return
	var errors := _validate_rows()
	if errors.is_empty():
		_validation.add_theme_color_override("font_color", Color("#8bdc95"))
		_validation.text = "✓ 当前表结构检查通过：%d 条。" % _rows.size()
	else:
		_validation.add_theme_color_override("font_color", Color("#ff7777"))
		_validation.text = "❌ 保存阻断（%d 项）：\n" % errors.size()
		for i in mini(errors.size(), 6):
			_validation.text += "• " + errors[i] + "\n"
		if errors.size() > 6:
			_validation.text += "……还有 %d 项。" % (errors.size() - 6)


func _validate_rows() -> Array[String]:
	var errors: Array[String] = []
	var config: Dictionary = TABLES[_table_index]
	var id_key := str(config["id_key"])
	var text_key := str(config["text_key"])
	var seen: Dictionary = {}
	for index in _rows.size():
		var row: Dictionary = _rows[index]
		var row_id := str(row.get(id_key, "")).strip_edges()
		var enabled := str(row.get("enabled", "")).to_lower() == "true"
		if row_id.is_empty():
			errors.append("第 %d 行的稳定 ID 为空。" % (index + 2))
		elif seen.has(row_id):
			errors.append("稳定 ID 重复：%s。" % row_id)
		else:
			seen[row_id] = true
		if enabled and str(row.get(text_key, "")).strip_edges().is_empty():
			errors.append("%s 已启用但文案为空。" % row_id)
		if _table_index == 0 and enabled and str(row.get("trigger_key", "")).strip_edges().is_empty():
			errors.append("%s 已启用但触发键为空。" % row_id)
		if _table_index == 1 and enabled:
			var viewer_id := str(row.get("viewer_id", "")).strip_edges()
			if viewer_id.is_empty() or not _reference_ids("res://data/source_tables/25_直播观众账号.csv", "viewer_id").has(viewer_id):
				errors.append("%s 引用了不存在的观众 ID：%s。" % [row_id, viewer_id])
		for numeric_key_value in config["numeric"]:
			var numeric_key := str(numeric_key_value)
			var numeric_value := str(row.get(numeric_key, "")).strip_edges()
			var weight_not_applicable := numeric_key == "random_weight" and str(row.get("trigger_type", "")) != "random_idle"
			if numeric_value.is_empty() and (numeric_key in ["trigger_time_s", "line_order"] or not enabled or weight_not_applicable):
				continue
			if numeric_value.is_empty() or not numeric_value.is_valid_float():
				errors.append("%s 的 %s 必须是数字。" % [row_id, numeric_key])
				continue
			var number := float(numeric_value)
			if numeric_key == "display_duration_s" and number <= 0.0:
				errors.append("%s 的显示时长必须大于 0。" % row_id)
			elif numeric_key != "display_duration_s" and number < 0.0:
				errors.append("%s 的 %s 不能小于 0。" % [row_id, numeric_key])
	return errors


func _save() -> void:
	if not _loaded:
		_set_status("原始表未成功读取，已禁止写入。")
		return
	var errors := _validate_rows()
	if not errors.is_empty():
		_update_validation()
		_set_status("保存已阻止：请修复右侧列出的字段问题。")
		return
	var config: Dictionary = TABLES[_table_index]
	var file := FileAccess.open(str(config["path"]), FileAccess.WRITE)
	if file == null:
		_set_status("保存失败：" + error_string(FileAccess.get_open_error()))
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
		_set_status("写入失败：" + error_string(result))
		return
	_dirty = false
	_reference_ids_cache.clear()
	_set_status("✓ 已保存 %s：%d 条。游戏下一次加载对应数据时读取新内容。" % [config["label"], _rows.size()])
	_update_validation()


func _reference_ids(path: String, id_column: String) -> Dictionary:
	var cache_key := path + "::" + id_column
	if _reference_ids_cache.has(cache_key):
		return _reference_ids_cache[cache_key]
	var ids: Dictionary = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_reference_ids_cache[cache_key] = ids
		return ids
	var headers := file.get_csv_line()
	var id_index := headers.find(id_column)
	if id_index < 0:
		file.close()
		_reference_ids_cache[cache_key] = ids
		return ids
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.size() != headers.size():
			continue
		var value := str(values[id_index]).strip_edges()
		if not value.is_empty():
			ids[value] = true
	file.close()
	_reference_ids_cache[cache_key] = ids
	return ids


func _duplicate_selected() -> void:
	if not _loaded or _selected_row < 0:
		_set_status("请先选择要复制的条目。")
		return
	var config: Dictionary = TABLES[_table_index]
	var id_key := str(config["id_key"])
	var source: Dictionary = _rows[_selected_row]
	var copy: Dictionary = source.duplicate(true)
	var base := str(source.get(id_key, "entry")) + "_copy"
	var candidate := base
	var suffix := 2
	while _has_id(candidate, id_key):
		candidate = "%s_%02d" % [base, suffix]
		suffix += 1
	copy[id_key] = candidate
	if copy.has("enabled"):
		copy["enabled"] = "false"
	if copy.has("notes"):
		copy["notes"] = "复制自 %s；默认禁用，请检查关联字段后再启用。" % str(source.get(id_key, ""))
	if copy.has("trigger_key"):
		copy["trigger_key"] = ""
	_rows.append(copy)
	_dirty = true
	_refresh_list(_rows.size() - 1)
	_set_status("已复制为禁用条目。检查关联字段和事件后再启用。")


func _has_id(candidate: String, id_key: String) -> bool:
	for row in _rows:
		if str(row.get(id_key, "")) == candidate:
			return true
	return false


func _ask_reload() -> void:
	if _dirty:
		_reload_confirm.popup_centered()
	else:
		_reload_current_table()


func _reload_current_table() -> void:
	_load_table(_table_index)


func _set_status(value: String) -> void:
	if _status != null:
		_status.text = value


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.ctrl_pressed and key.keycode == KEY_S:
		_save()
		get_viewport().set_input_as_handled()
