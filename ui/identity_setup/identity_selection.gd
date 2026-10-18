extends Control

const CARD_BACK_TEXTURE: Texture2D = preload("res://assets/ui/identity/cards/identity_card_back.png")
const CARD_BLANK_TEXTURE: Texture2D = preload("res://assets/ui/identity/cards/identity_card_front_00_blank.png")
const CARD_WIDTH: float = 280.0
const CARD_HEIGHT: float = 350.0
const CARD_GRID_GAP: float = 16.0
const CARD_MAX_COLUMNS: int = 4

signal selection_changed(option: IdentityOption)
signal next_requested(option: IdentityOption)

var _selected_option: IdentityOption
var _locked: bool = false
var _buttons: Array[Button] = []
var _revealed_ids: Dictionary[StringName, bool] = {}

@onready var _grid: GridContainer = %IdentityCards
@onready var _card_row_center: HBoxContainer = %CardRowCenter
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
		# 保留297×371原卡面的0.80比例，按钮不再跟随整列横向扩张。
		button.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		button.toggle_mode = true
		_grid.add_child(button)
		# 在原有 Button 状态层内部绘制卡面，保留按钮焦点与选中描边。
		var card_art := TextureRect.new()
		card_art.name = "CardArt"
		card_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card_art.offset_left = 0.0
		card_art.offset_top = 0.0
		card_art.offset_right = 0.0
		card_art.offset_bottom = 0.0
		button.add_child(card_art)
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
		content.add_theme_constant_override("separation", 8)
		margin.add_child(content)
		var art_clearance := Control.new()
		art_clearance.custom_minimum_size.y = 120.0
		art_clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(art_clearance)
		var title := _make_label(option.display_name, 26)
		title.add_theme_color_override("font_color", Color("#49312b"))
		content.add_child(title)
		var description := _make_label(option.description, 18)
		description.add_theme_color_override("font_color", Color("#49312b"))
		content.add_child(description)
		var back := _make_label("身份牌\n点击翻开", 30)
		back.name = "Back"
		back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		back.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
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
	_scroll.resized.connect(_fit_grid_columns)
	get_window().size_changed.connect(_fit_layout.call_deferred)
	_fit_layout()
	call_deferred("_fit_grid_columns")

# 抵消项目默认画布缩放，按实际窗口像素排版；小窗口保留正文并滚动。
func _fit_layout() -> void:
	# 窗口缩放的延迟回调可能在切页后抵达，离树的视图无需继续排版。
	if not is_inside_tree():
		return
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	_margins.scale = Vector2.ONE / canvas_scale
	_margins.size = size * canvas_scale
	call_deferred("_fit_grid_columns")


# 4列优先；窗口变窄时减列数，让固定宽度卡片仍留在可见横向范围内。
func _fit_grid_columns() -> void:
	if not is_inside_tree() or _scroll.size.x <= 0.0:
		return
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fitting_columns := int((_scroll.size.x + CARD_GRID_GAP) / (CARD_WIDTH + CARD_GRID_GAP))
	var next_columns := clampi(fitting_columns, 1, CARD_MAX_COLUMNS)
	if _grid.columns != next_columns:
		_grid.columns = next_columns
		_wire_focus()

# 换行标签交由卡片接收鼠标，完整正文随容器高度展开。
func _make_label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label

# 按当前自适应列数布置方向键，底行向下到下一步。
func _wire_focus() -> void:
	var columns := maxi(_grid.columns, 1)
	for index in range(_buttons.size()):
		var button := _buttons[index]
		var column := index % columns
		var next_row_index := index + columns
		button.focus_neighbor_left = button.get_path_to(_buttons[index - 1] if column > 0 else button)
		button.focus_neighbor_right = button.get_path_to(_buttons[index + 1] if column + 1 < columns and index + 1 < _buttons.size() else button)
		button.focus_neighbor_top = button.get_path_to(_buttons[index - columns] if index >= columns else button)
		button.focus_neighbor_bottom = button.get_path_to(_buttons[next_row_index] if next_row_index < _buttons.size() else _next)
	_next.focus_neighbor_top = _next.get_path_to(_buttons[maxi(0, _buttons.size() - columns)])

# 只在卡片实际离开可视区域时滚动；比视口更高的卡片始终以顶边为准。
func _scroll_to_card(button: Button) -> void:
	var card_position := _card_row_center.position + _grid.position + button.position
	var card_left := card_position.x
	var card_right := card_left + button.size.x
	var visible_left := float(_scroll.scroll_horizontal)
	var visible_right := visible_left + _scroll.size.x
	if card_left < visible_left:
		_scroll.scroll_horizontal = maxi(0, ceili(card_left))
	elif card_right > visible_right:
		var target_left := card_left if button.size.x >= _scroll.size.x else card_right - _scroll.size.x
		_scroll.scroll_horizontal = maxi(0, ceili(target_left))
	var card_top := card_position.y
	var card_bottom := card_top + button.size.y
	var visible_top := float(_scroll.scroll_vertical)
	var visible_bottom := visible_top + _scroll.size.y
	if card_top < visible_top:
		_scroll.scroll_vertical = maxi(0, ceili(card_top))
	elif card_bottom > visible_bottom:
		var target_top := card_top if button.size.y >= _scroll.size.y else card_bottom - _scroll.size.y
		_scroll.scroll_vertical = maxi(0, ceili(target_top))

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
	# 从 IdentityOption.icon 读取暂定图案映射；无资源时回退空白正面。
	var card_art := button.get_node("CardArt") as TextureRect
	var option := IdentityOptions.find_option(StringName(button.name))
	if revealed and option != null and option.icon != null:
		card_art.texture = option.icon
	else:
		card_art.texture = CARD_BLANK_TEXTURE if revealed else CARD_BACK_TEXTURE
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
	AudioManager.play_event(&"ui_identity_switch")
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
	else:
		# 空选择只反馈错误，不改变身份步骤或存档。
		AudioManager.play_event(&"ui_error")
