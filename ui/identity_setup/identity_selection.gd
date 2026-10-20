extends Control

const CARD_BACK_TEXTURE: Texture2D = preload("res://assets/ui/identity/cards/identity_card_back.png")
const CARD_BLANK_TEXTURE: Texture2D = preload("res://assets/ui/identity/cards/identity_card_front_00_blank.png")
const PRIMARY_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/buttons/button_primary.png")
const SECONDARY_BUTTON_TEXTURE: Texture2D = preload("res://assets/ui/buttons/button_secondary.png")
const BUTTON_FONT: Font = preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const SYMBOL_INK_SHADER: Shader = preload("res://ui/identity_setup/identity_symbol_mask.gdshader")
const CARD_ASPECT_RATIO: float = 0.80
const CARD_MAX_WIDTH: float = 280.0
const CARD_MIN_WIDTH: float = 108.0
const CARD_GRID_GAP: float = 12.0
const CARD_GRID_COLUMNS: int = 6
const DETAILS_PANEL_MIN_WIDTH: float = 280.0
const DETAILS_PANEL_MAX_WIDTH: float = 365.0
const NAVIGATION_RESERVED_HEIGHT: float = 119.0

signal selection_changed(option: IdentityOption)
signal next_requested(option: IdentityOption)

var _selected_option: IdentityOption
var _detail_option: IdentityOption
var _locked: bool = false
var _buttons: Array[Button] = []
var _card_title_panels: Array[PanelContainer] = []
var _card_title_labels: Array[Label] = []
var _revealed_ids: Dictionary[StringName, bool] = {}
var _card_caption_style: StyleBoxFlat
var _grid_layout_pending := false
var _button_patch_cache: Dictionary[int, ImageTexture] = {}

@onready var _grid: GridContainer = %IdentityCards
@onready var _row_center: HBoxContainer = %CardRowCenter
@onready var _page_title: Label = $Margins/Content/Title
@onready var _instruction: Label = $Margins/Content/Instructions
@onready var _card_area: HBoxContainer = %CardArea
@onready var _scroll: ScrollContainer = %CardScroll
@onready var _details_panel: PanelContainer = %IdentityDetailsPanel
@onready var _details_holder: Control = %DetailsHolder
@onready var _details_header: Label = %IdentityDetailsTitle
@onready var _details_name_label: Label = %IdentityDetailsName
@onready var _details_symbol: TextureRect = %DetailsSymbol
@onready var _unknown_glyph: Label = %UnknownGlyph
@onready var _details_description_label: Label = %IdentityDetailsDescription
@onready var _unrevealed_hint: Label = %UnrevealedHint
@onready var _description_scroll: ScrollContainer = %DescriptionScroll
@onready var _details_content: VBoxContainer = $Margins/Content/CardArea/DetailsHolder/IdentityDetailsPanel/InnerPadding/DetailsContent
@onready var _status: Label = %SelectionStatus
@onready var _reveal_all: Button = %RevealAllButton
@onready var _next: Button = %NextButton
@onready var _margins: MarginContainer = $Margins
@onready var _header_spacer: Control = $Margins/Content/HeaderToCardsSpacer


# 临时选择、翻牌和详情只由此视图维护；正式确认与存档仍由 ID-09 调用方负责。
func _ready() -> void:
	_card_caption_style = _make_caption_style()
	_card_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_configure_detail_panel()
	_configure_navigation_buttons()
	_page_title.add_theme_color_override("font_color", Color("#4a2c20"))
	_page_title.add_theme_font_size_override("font_size", 44)
	_instruction.add_theme_color_override("font_color", Color("#624737"))
	_instruction.add_theme_font_size_override("font_size", 22)
	for option in IdentityOptions.CARDS:
		_add_identity_card(option)
	_reveal_all.pressed.connect(_reveal_all_cards)
	_next.pressed.connect(_request_next)
	_wire_focus()
	_refresh_selection()
	_set_detail_option(_selected_option if _selected_option != null else IdentityOptions.CARDS[0])
	resized.connect(_fit_layout)
	_card_area.resized.connect(_queue_grid_layout)
	_scroll.resized.connect(_queue_grid_layout)
	get_window().size_changed.connect(_fit_layout.call_deferred)
	_fit_layout()
	_queue_grid_layout()


# 创建统一比例的可点击缩略卡，名称留在卡面内，完整描述放在固定详情区。
func _add_identity_card(option: IdentityOption) -> void:
	var button := Button.new()
	button.name = String(option.identity_id)
	button.custom_minimum_size = Vector2(220.0, 275.0)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.toggle_mode = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_configure_card_button(button)
	_grid.add_child(button)

	var selected_style := button.get_theme_stylebox("pressed").duplicate() as StyleBoxFlat
	if selected_style != null:
		selected_style.set_border_width_all(4)
		selected_style.border_color = Color("#e9c76c")
		button.add_theme_stylebox_override("pressed", selected_style)
		button.add_theme_stylebox_override("hover_pressed", selected_style)
		# Keep the keyboard focus border independent of the selected state.

	var card_art := TextureRect.new()
	card_art.name = "CardArt"
	card_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card_art.offset_left = 4.0
	card_art.offset_top = 4.0
	card_art.offset_right = -4.0
	card_art.offset_bottom = -4.0
	button.add_child(card_art)

	var margin := MarginContainer.new()
	margin.name = "CardFace"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 61)
	button.add_child(margin)

	var front := VBoxContainer.new()
	front.name = "Front"
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_theme_constant_override("separation", 0)
	margin.add_child(front)

	var art_clearance := Control.new()
	art_clearance.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_clearance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_child(art_clearance)

	var title_panel := PanelContainer.new()
	title_panel.name = "CardTitlePanel"
	title_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel.custom_minimum_size.y = 28.0
	title_panel.add_theme_stylebox_override("panel", _card_caption_style.duplicate())
	front.add_child(title_panel)

	var title := _make_label(option.display_name, 16)
	title.name = "CardTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("#3d271e"))
	title.add_theme_font_override("font", BUTTON_FONT)
	title_panel.add_child(title)
	_card_title_panels.append(title_panel)
	_card_title_labels.append(title)

	var back := _make_label("", 14)
	back.name = "Back"
	back.size_flags_vertical = Control.SIZE_EXPAND_FILL
	back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	margin.add_child(back)

	_present_card_face(button, false)
	button.pressed.connect(_on_card_pressed.bind(option, button))
	button.focus_entered.connect(_on_card_focus_entered.bind(option, button))
	_buttons.append(button)


# 正式空白身份牌作为详情底板，复用原图边饰，中间区域九宫格拉伸以容纳长文本。
func _configure_detail_panel() -> void:
	var panel_style := StyleBoxTexture.new()
	panel_style.texture = CARD_BLANK_TEXTURE
	panel_style.texture_margin_left = 38.0
	panel_style.texture_margin_top = 52.0
	panel_style.texture_margin_right = 38.0
	panel_style.texture_margin_bottom = 56.0
	panel_style.content_margin_left = 36.0
	panel_style.content_margin_top = 38.0
	panel_style.content_margin_right = 36.0
	panel_style.content_margin_bottom = 72.0
	_details_panel.add_theme_stylebox_override("panel", panel_style)
	_details_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_details_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_details_panel.size_flags_vertical = Control.SIZE_FILL
	_details_panel.custom_minimum_size.y = 420.0
	_details_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_header.add_theme_font_size_override("font_size", 24)
	_details_header.add_theme_color_override("font_color", Color("#795036"))
	var symbol_material := ShaderMaterial.new()
	symbol_material.shader = SYMBOL_INK_SHADER
	_details_symbol.material = symbol_material
	_unknown_glyph.add_theme_font_size_override("font_size", 76)
	_unknown_glyph.add_theme_color_override("font_color", Color("#946e52"))
	_unknown_glyph.add_theme_font_override("font", BUTTON_FONT)
	_details_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_name_label.add_theme_font_size_override("font_size", 30)
	_details_name_label.add_theme_color_override("font_color", Color("#321c13"))
	_details_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_unrevealed_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_unrevealed_hint.add_theme_font_size_override("font_size", 19)
	_unrevealed_hint.add_theme_color_override("font_color", Color("#362119"))
	_details_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_description_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_details_description_label.size_flags_vertical = Control.SIZE_FILL
	_description_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_description_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_description_scroll.get_v_scroll_bar().modulate = Color(0.5, 0.33, 0.19, 0.85)
	_details_description_label.add_theme_font_size_override("font_size", 19)
	_details_description_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	_details_description_label.add_theme_constant_override("line_spacing", 5)
	_details_description_label.add_theme_color_override("font_color", Color("#362119"))
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_color", Color("#56321e"))


# 固定逻辑分辨率下按实际窗口高度适配右侧字阶；每档连续变化，避免 720p 偏大、1080p 偏小。
func _fit_detail_typography(physical_height: float) -> void:
	var t := clampf((physical_height - 720.0) / 360.0, 0.0, 1.0)
	var detail_sizes := [
		{"label": _details_header, "size": roundi(lerpf(21.0, 28.0, t))},
		{"label": _unknown_glyph, "size": roundi(lerpf(60.0, 76.0, t))},
		{"label": _details_name_label, "size": roundi(lerpf(24.0, 34.0, t))},
		{"label": _status, "size": roundi(lerpf(14.0, 18.0, t))},
		{"label": _unrevealed_hint, "size": roundi(lerpf(16.0, 22.0, t))},
		{"label": _details_description_label, "size": roundi(lerpf(16.0, 22.0, t))},
	]
	for entry in detail_sizes:
		var label: Label = entry["label"]
		var target_size: int = entry["size"]
		if label.get_theme_font_size("font_size") != target_size:
			label.add_theme_font_size_override("font_size", target_size)
	var line_spacing := roundi(lerpf(3.0, 6.0, t))
	if _details_description_label.get_theme_constant("line_spacing") != line_spacing:
		_details_description_label.add_theme_constant_override("line_spacing", line_spacing)


# 旧图 391x359 是正方形按钮；直接在 900px 横条上九宫格裁 88px 边会变成夸张胶囊。
# 先等比缩小有效图，再切四角及边框；宽度仅由中段延展。
func _button_patch(texture: Texture2D) -> ImageTexture:
	var id := texture.get_instance_id()
	if _button_patch_cache.has(id):
		return _button_patch_cache[id]
	var image: Image = texture.get_image()
	var region := image.get_region(Rect2i(27, 66, 391, 359))
	region.resize(112, 103, Image.INTERPOLATE_LANCZOS)
	var result := ImageTexture.create_from_image(region)
	_button_patch_cache[id] = result
	return result


func _button_style(texture: Texture2D, shade: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = _button_patch(texture)
	style.texture_margin_left = 23.0
	style.texture_margin_top = 23.0
	style.texture_margin_right = 23.0
	style.texture_margin_bottom = 23.0
	style.content_margin_left = 26.0
	style.content_margin_top = 16.0
	style.content_margin_right = 26.0
	style.content_margin_bottom = 16.0
	style.modulate_color = shade
	return style

func _configure_navigation_buttons() -> void:
	for entry in [
		{"button": _reveal_all, "texture": SECONDARY_BUTTON_TEXTURE},
		{"button": _next, "texture": PRIMARY_BUTTON_TEXTURE},
	]:
		var button: Button = entry["button"]
		var texture: Texture2D = entry["texture"]
		button.add_theme_stylebox_override("normal", _button_style(texture, Color.WHITE))
		button.add_theme_stylebox_override("hover", _button_style(texture, Color("#fff1d5")))
		button.add_theme_stylebox_override("pressed", _button_style(texture, Color("#d9b391")))
		button.add_theme_stylebox_override("disabled", _button_style(texture, Color("#a49b92")))
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var is_secondary := button == _reveal_all
		button.add_theme_color_override("font_color", Color("#fff0d7") if is_secondary else Color("#472819"))
		button.add_theme_color_override("font_hover_color", Color("#fff9e8") if is_secondary else Color("#382012"))
		button.add_theme_color_override("font_pressed_color", Color("#fff0d7") if is_secondary else Color("#382012"))
		button.add_theme_color_override("font_disabled_color", Color("#cfb59c") if is_secondary else Color("#655346"))
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_font_override("font", BUTTON_FONT)
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


# 暖褐柔影保持低对比，让十二张卡从纸面抬起，不盖过原画线稿。
func _configure_card_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.26, 0.14, 0.09, 0.0)
	normal.shadow_color = Color(0.22, 0.10, 0.06, 0.13)
	normal.shadow_size = 5
	normal.shadow_offset = Vector2(0, 3)
	normal.set_corner_radius_all(4)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 0.86, 0.55, 0.07)
	hover.border_color = Color("#b2814b")
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override("hover", hover)
	var selected := hover.duplicate() as StyleBoxFlat
	selected.border_color = Color("#f5c568")
	selected.set_border_width_all(3)
	button.add_theme_stylebox_override("pressed", selected)
	button.add_theme_stylebox_override("hover_pressed", selected)
	var focus_style := hover.duplicate() as StyleBoxFlat
	focus_style.border_color = Color("#78543e")
	focus_style.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("disabled", normal)


# 按实际窗口像素排版，抵消固定逻辑视口的缩放，保证 1280 与 1920 同样可读。
func _fit_layout() -> void:
	if not is_inside_tree():
		return
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	if is_zero_approx(canvas_scale.x) or is_zero_approx(canvas_scale.y):
		return
	_header_spacer.custom_minimum_size.y = 18.0 if canvas_scale.y < 0.9 else 85.0
	_margins.scale = Vector2.ONE / canvas_scale
	_margins.size = size * canvas_scale
	_margins.size.y = maxf(0.0, _margins.size.y - NAVIGATION_RESERVED_HEIGHT)
	_queue_grid_layout()


# 将连续的尺寸信号合并为每帧至多一次布局，避免跨容器反复缩放阻塞主循环。
func _queue_grid_layout() -> void:
	if _grid_layout_pending:
		return
	_grid_layout_pending = true
	call_deferred("_run_grid_layout")


func _run_grid_layout() -> void:
	_grid_layout_pending = false
	_fit_grid_columns()
	# Keep the margin container bounded even when a child changed its minimum size.
	var canvas_scale := get_viewport().get_final_transform().get_scale()
	var target_height := get_viewport().get_visible_rect().size.y * canvas_scale.y - NAVIGATION_RESERVED_HEIGHT
	var bounded_height := maxf(target_height, _margins.get_combined_minimum_size().y)
	if absf(_margins.size.y - bounded_height) > 0.5:
		_margins.size.y = bounded_height


# 按实际可用宽高分配缩略卡；空间不足时才减少列数并允许滚动。
func _fit_grid_columns() -> void:
	if not is_inside_tree() or _card_area.size.x <= 0.0:
		return
	# 固定使用物理视口宽度分配六列，避免子卡片最小宽度撑大滚动容器后反向扩张根节点。
	var canvas_scale_x := get_viewport().get_final_transform().get_scale().x
	var content_width_limit := get_viewport().get_visible_rect().size.x * canvas_scale_x - 64.0
	var details_width := clampf(content_width_limit * 0.21, DETAILS_PANEL_MIN_WIDTH, DETAILS_PANEL_MAX_WIDTH)
	if not is_equal_approx(_details_holder.custom_minimum_size.x, details_width):
		_details_holder.custom_minimum_size.x = details_width
		_details_panel.custom_minimum_size.x = details_width
	if _scroll.size.y <= 0.0:
		return
	# Detail sheet stays within the right column; footer actions use their own full-width row.
	var canvas_scale_y := get_viewport().get_final_transform().get_scale().y
	var physical_height := get_viewport().get_visible_rect().size.y * canvas_scale_y
	_fit_detail_typography(physical_height)
	var compact := canvas_scale_y < 0.9
	var vertical_spacing := 8 if compact else 16
	if _details_content.get_theme_constant("separation") != vertical_spacing:
		_details_content.add_theme_constant_override("separation", vertical_spacing)
	var details_height := 425.0 if compact else 565.0
	if not is_equal_approx(_details_panel.custom_minimum_size.y, details_height):
		_details_panel.custom_minimum_size.y = details_height
	_details_symbol.custom_minimum_size.y = 64.0 if compact else 104.0
	var available_card_width := maxf(CARD_MIN_WIDTH, content_width_limit - details_width - 12.0)
	var fitting_columns := int(floor((available_card_width + CARD_GRID_GAP) / (CARD_MIN_WIDTH + CARD_GRID_GAP)))
	var next_columns := clampi(fitting_columns, 1, CARD_GRID_COLUMNS)
	if _grid.columns != next_columns:
		_grid.columns = next_columns
		_wire_focus()

	var cards_per_column := float(next_columns)
	var row_count := maxi(1, ceili(float(IdentityOptions.CARDS.size()) / cards_per_column))
	var width_per_card := (available_card_width - CARD_GRID_GAP * float(next_columns - 1)) / cards_per_column
	var height_per_row := (_scroll.size.y - CARD_GRID_GAP * float(row_count - 1)) / float(row_count)
	var width_by_height := height_per_row * CARD_ASPECT_RATIO
	var card_width := minf(CARD_MAX_WIDTH, width_per_card)
	if width_by_height >= CARD_MIN_WIDTH:
		card_width = minf(card_width, width_by_height)
	card_width = maxf(CARD_MIN_WIDTH, card_width)
	var card_height := card_width / CARD_ASPECT_RATIO

	for index in range(_buttons.size()):
		_buttons[index].custom_minimum_size = Vector2(card_width, card_height)
		_card_title_panels[index].custom_minimum_size.y = clampf(card_width * 0.15, 26.0, 34.0)
		_card_title_labels[index].add_theme_font_size_override("font_size", clampi(roundi(card_width * 0.108), 18, 23))

	var content_width := card_width * cards_per_column + CARD_GRID_GAP * float(next_columns - 1)
	var content_height := card_height * float(row_count) + CARD_GRID_GAP * float(row_count - 1)
	# 卡片容器填充可用高度，禁止以滚动高度反向修改父容器最小高度。
	# 这样在不同分辨率下均可稳定结束布局更新。
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if content_width > available_card_width + 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if content_height > _scroll.size.y + 0.5 else ScrollContainer.SCROLL_MODE_DISABLED
	if _scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		_scroll.scroll_horizontal = 0
	if _scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		_scroll.scroll_vertical = 0


# 按当前实际列数连接方向键，末行向下可到达确认按钮。
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


# 统一创建忽略鼠标事件的自动换行文字控件。
func _make_label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	return label


# 统一定义身份卡底部的纸色名称条。
func _make_caption_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0)
	style.border_color = Color(1, 1, 1, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.content_margin_left = 4.0
	style.content_margin_top = 2.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 2.0
	return style


# 键盘焦点与鼠标点击都会更新固定详情区；窄窗口下让聚焦卡保持可见。
func _on_card_focus_entered(option: IdentityOption, button: Button) -> void:
	_set_detail_option(option)
	_scroll.ensure_control_visible(button)


# 详情区显示当前浏览身份的完整配置文案和它相对选择状态的关系。
func _set_detail_option(option: IdentityOption) -> void:
	_detail_option = option
	_description_scroll.scroll_vertical = 0
	_refresh_detail_panel()


# 根据现有 ID 查找卡背/正面资源，缺少图案时使用空白正面。
func _present_card_face(button: Button, revealed: bool) -> void:
	var card_art := button.get_node("CardArt") as TextureRect
	var option := IdentityOptions.find_option(StringName(button.name))
	if revealed and option != null and option.icon != null:
		card_art.texture = option.icon
	else:
		card_art.texture = CARD_BLANK_TEXTURE if revealed else CARD_BACK_TEXTURE
	button.get_node("CardFace/Front").visible = revealed
	button.get_node("CardFace/Back").visible = not revealed


# 背面首次点击只翻本张；正面再次点击才进入既有单选流程。
func _on_card_pressed(option: IdentityOption, button: Button) -> void:
	if _locked:
		return
	_set_detail_option(option)
	if not _revealed_ids.has(option.identity_id):
		_revealed_ids[option.identity_id] = true
		_present_card_face(button, true)
		_refresh_selection()
		return
	_select_card(option)


# 一键翻开只改变卡面显示状态，不覆盖当前选择。
func _reveal_all_cards() -> void:
	if _locked:
		return
	for index in range(IdentityOptions.CARDS.size()):
		var option := IdentityOptions.CARDS[index]
		_revealed_ids[option.identity_id] = true
		_present_card_face(_buttons[index], true)
	_refresh_selection()


# 玩家可随时改选；最终确认与本周目保存由 ID-09 页面持有。
func _select_card(option: IdentityOption) -> void:
	if _locked:
		return
	_selected_option = option
	_detail_option = option
	_refresh_selection()
	AudioManager.play_event(&"ui_identity_switch")
	selection_changed.emit(option)


# 回退时恢复正式 ID 和锁定状态，保持已有卡面图案映射。
func restore_selection(identity_id: StringName, locked: bool = false) -> void:
	_locked = locked
	_selected_option = IdentityOptions.find_option(identity_id)
	if not locked and not IdentityOptions.CARDS.has(_selected_option):
		_selected_option = null
	if IdentityOptions.CARDS.has(_selected_option):
		_revealed_ids[_selected_option.identity_id] = true
	if is_node_ready():
		for index in range(_buttons.size()):
			var option := IdentityOptions.CARDS[index]
			_present_card_face(_buttons[index], _revealed_ids.has(option.identity_id))
		_detail_option = _selected_option if _selected_option != null else IdentityOptions.CARDS[0]
		_refresh_selection()


# 向流程持有者提供当前身份；此组件不保存或修改 SaveData。
func get_selected_option() -> IdentityOption:
	return _selected_option


# 身份步骤重新显示时恢复焦点；锁定周目把焦点交给可用确认操作。
func focus_selection() -> void:
	if _locked:
		if not _next.disabled:
			_next.grab_focus()
		return
	var index := IdentityOptions.CARDS.find(_selected_option)
	_buttons[maxi(index, 0)].grab_focus()


# 刷新卡片选中态、翻牌按钮状态与详情区，数据仍来自正式身份 Resource。
func _refresh_selection() -> void:
	var all_revealed := _revealed_ids.size() == IdentityOptions.CARDS.size()
	for index in range(_buttons.size()):
		_buttons[index].set_pressed_no_signal(_selected_option == IdentityOptions.CARDS[index])
		_buttons[index].disabled = _locked
	_reveal_all.disabled = _locked or all_revealed
	_reveal_all.text = "已翻开" if all_revealed else "全部翻开"
	_next.disabled = _selected_option == null
	if _detail_option == null:
		_detail_option = _selected_option if _selected_option != null else IdentityOptions.CARDS[0]
	_refresh_detail_panel()


# 显示焦点卡全文，并明确指出当前卡与已选择/已确认身份的关系。
func _refresh_detail_panel() -> void:
	var option := _detail_option
	var revealed := option != null and _revealed_ids.has(option.identity_id)
	# 卡背只显示纯文本提示；翻开后恢复配表描述及长文滚动。
	_unrevealed_hint.visible = not revealed
	_description_scroll.visible = revealed
	if option == null:
		_details_name_label.text = "身份详情"
		_status.text = "尚未选择身份"
		return
	# 卡背阶段只给出翻牌提示，防止焦点在卡背上时提前泄漏身份内容。
	if not revealed:
		_details_symbol.visible = false
		_unknown_glyph.visible = true
		_details_name_label.text = "尚未揭示"
		_status.text = "等待翻牌"
		return
	_unknown_glyph.visible = false
	_details_symbol.visible = option.icon != null
	if option.icon != null:
		var symbol_atlas := AtlasTexture.new()
		symbol_atlas.atlas = option.icon
		var full_size := option.icon.get_size()
		symbol_atlas.region = Rect2(
			Vector2(full_size.x * 0.18, full_size.y * 0.12),
			Vector2(full_size.x * 0.64, full_size.y * 0.41))
		_details_symbol.texture = symbol_atlas
	_details_name_label.text = option.display_name
	_details_description_label.text = option.description
	if _locked:
		_status.text = "当前身份已确认并锁定" if _selected_option == option else "本周目身份已锁定"
	elif _selected_option == option:
		_status.text = "当前选中，可确认"
	elif _selected_option != null:
		_status.text = "尚未选择此身份；当前选择：%s" % _selected_option.display_name
	elif _revealed_ids.has(option.identity_id):
		_status.text = "已翻开，点击可选择"
	else:
		_status.text = "点击卡片翻开并查看完整身份说明"


# 仅通知下一步；身份确认、存档和顶层场景切换仍由所属流程负责。
func _request_next() -> void:
	if _selected_option != null:
		next_requested.emit(_selected_option)
	else:
		AudioManager.play_event(&"ui_error")
