extends Control

signal selection_changed(option: IdentityOption)
signal next_requested(option: IdentityOption)

var _selected_option: IdentityOption
var _locked: bool = false
var _buttons: Array[Button] = []
var _revealed_ids: Dictionary[StringName, bool] = {}

@onready var _grid: GridContainer = %IdentityCards
@onready var _scroll: ScrollContainer = %CardScroll
@onready var _status: Label = %SelectionStatus
@onready var _reveal_all: Button = %RevealAllButton
@onready var _next: Button = %NextButton
@onready var _margins: MarginContainer = $Margins

# 只维护临时选择；正式确认、存档和步骤切换由 ID-09 调用方负责。
func _ready() -> void:
	for option in IdentityOptions.CARDS:
		var button := Button.new()
		button.name = String(option.identity_id)
		button.custom_minimum_size = Vector2(280, 260)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		_grid.add_child(button)
		var selected_style := button.get_theme_stylebox("pressed").duplicate() as StyleBoxFlat
		selected_style.set_border_width_all(3)
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		var margin := MarginContainer.new()
		margin.name = "CardFace"
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 20)
		button.add_child(margin)
		var content := VBoxContainer.new()
		content.name = "Front"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 12)
		margin.add_child(content)
		var title := _make_label(option.display_name, 30)
		content.add_child(title)
		content.add_child(_make_label(option.description, 21))
		var back := _make_label("身份牌\n点击翻开", 30)
		back.name = "Back"
		back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		margin.add_child(back)
		_present_card_face(button, _revealed_ids.has(option.identity_id))
		button.pressed.connect(_on_card_pressed.bind(option, button))
		button.focus_entered.connect(_scroll_to_card.bind(button))
		_buttons.append(button)
	_reveal_all.pressed.connect(_reveal_all_cards)
	_next.pressed.connect(_request_next)
	_wire_focus()
	_refresh_selection()
	resized.connect(_fit_layout)
	get_window().size_changed.connect(_fit_layout.call_deferred)
	_fit_layout()

# 抵消项目默认画布缩放，按实际窗口像素排版；小窗口保留正文并滚动。
func _fit_layout() -> void:
	# 窗口缩放的延迟回调可能在切页后抵达，离树的视图无需继续排版。
	if not is_inside_tree():
		return
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	_margins.scale = Vector2.ONE / canvas_scale
	_margins.size = size * canvas_scale

# 换行标签交由卡片接收鼠标，完整正文随容器高度展开。
func _make_label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label

# 四列方向键按行列移动，底行向下到下一步。
func _wire_focus() -> void:
	for index in range(_buttons.size()):
		var button := _buttons[index]
		button.focus_neighbor_left = button.get_path_to(_buttons[index - 1] if index % 4 > 0 else button)
		button.focus_neighbor_right = button.get_path_to(_buttons[index + 1] if index % 4 < 3 else button)
		button.focus_neighbor_top = button.get_path_to(_buttons[index - 4] if index >= 4 else button)
		button.focus_neighbor_bottom = button.get_path_to(_buttons[index + 4] if index < 8 else _next)
	_next.focus_neighbor_top = _next.get_path_to(_buttons[8])

# 使用网格局部坐标滚动，避免缩放后的全局矩形重复影响滚动距离。
func _scroll_to_card(button: Button) -> void:
	_scroll.scroll_horizontal = int(clampf(_scroll.scroll_horizontal, button.position.x + button.size.x - _scroll.size.x + 12, button.position.x))
	_scroll.scroll_vertical = int(clampf(_scroll.scroll_vertical, button.position.y + button.size.y - _scroll.size.y + 12, button.position.y))

# 背面首次点击只翻本张；正面再次点击才进入既有单选流程。
func _on_card_pressed(option: IdentityOption, button: Button) -> void:
	if _locked:
		return
	if not _revealed_ids.has(option.identity_id):
		_revealed_ids[option.identity_id] = true
		_present_card_face(button, true)
		_refresh_selection()
		return
	_select_card(option)

# 卡背与翻面表现的统一占位入口；后续美术可在此接图或动画，状态由页面持有。
func _present_card_face(button: Button, revealed: bool) -> void:
	button.get_node("CardFace/Front").visible = revealed
	button.get_node("CardFace/Back").visible = not revealed

# 一次把全部翻开请求交给现有牌面表现入口，不改变当前选择。
func _reveal_all_cards() -> void:
	if _locked:
		return
	for index in range(IdentityOptions.CARDS.size()):
		var option := IdentityOptions.CARDS[index]
		_revealed_ids[option.identity_id] = true
		_present_card_face(_buttons[index], true)
	_refresh_selection()

# 玩家点选可反复切换，已确认周目由调用方传入锁定状态。
func _select_card(option: IdentityOption) -> void:
	if _locked:
		return
	_selected_option = option
	_refresh_selection()
	selection_changed.emit(option)

# 可在入树前设置；回退恢复临时 ID，旧身份只允许作为已确认记录恢复。
func restore_selection(identity_id: StringName, locked: bool = false) -> void:
	_locked = locked
	_selected_option = IdentityOptions.find_option(identity_id)
	if not locked and not IdentityOptions.CARDS.has(_selected_option):
		_selected_option = null
	# 恢复已有正式选择时保证该卡为正面，其他卡的本轮翻开状态保持。
	if IdentityOptions.CARDS.has(_selected_option):
		_revealed_ids[_selected_option.identity_id] = true
	if is_node_ready():
		for index in range(_buttons.size()):
			_present_card_face(_buttons[index], _revealed_ids.has(IdentityOptions.CARDS[index].identity_id))
		_refresh_selection()

# 向流程持有者提供当前具体身份及底层倾向。
func get_selected_option() -> IdentityOption:
	return _selected_option

# 再次显示步骤时由调用方恢复键盘焦点。
func focus_selection() -> void:
	if _locked:
		if not _next.disabled:
			_next.grab_focus()
		return
	var index := IdentityOptions.CARDS.find(_selected_option)
	_buttons[maxi(index, 0)].grab_focus()

# 同一套样式显示选择，未知已存身份锁住页面以保留存档事实。
func _refresh_selection() -> void:
	var all_revealed := _revealed_ids.size() == IdentityOptions.CARDS.size()
	for index in range(_buttons.size()):
		_buttons[index].set_pressed_no_signal(_selected_option == IdentityOptions.CARDS[index])
		_buttons[index].disabled = _locked
	_reveal_all.disabled = _locked or all_revealed
	_reveal_all.text = "已全部翻开" if all_revealed else "一键翻开"
	_next.disabled = _selected_option == null
	if _selected_option != null:
		_status.text = "已选择：%s" % _selected_option.display_name if IdentityOptions.CARDS.has(_selected_option) else "沿用本周目已确认身份"
	else:
		_status.text = "已保存身份无法识别，请保留存档并检查配置。" if _locked else "翻开后再点一次选择"

# 仅通知下一步；本视图不会修改 SaveData 或跳转 Game / Rest。
func _request_next() -> void:
	if _selected_option != null:
		next_requested.emit(_selected_option)
