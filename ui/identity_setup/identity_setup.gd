extends Control

# 开场演出通过公开请求信号交给美术组件；完成后调用对应公开完成入口。
signal player_name_pawprint_presentation_requested(streamer_name: String)
signal player_name_pawprint_presentation_completed(streamer_name: String)
signal motive_panel_display_requested(panel_number: int)
signal motive_comic_completed
signal room_computer_transition_requested(identity_id: StringName)
signal room_computer_transition_completed

# 保存成功的事实通知；RS-12 接收后通过 SceneRouter 打开真正的开局房间。
signal opening_saved(run_data: SaveData)

enum Step { STREAMER, PLAYER_PRESENTATION, MOTIVE_COMIC, IDENTITY, ROOM_TRANSITION, FAN_GROUP }

# 美术确定正式格数与节奏前，使用三个 TEST_ONLY 编号验证既有 ID-12 控制器。
const PLACEHOLDER_PANEL_COUNT: int = 3
const PLACEHOLDER_PANEL_INTERVAL_SECONDS: float = 0.8

var _step: Step = Step.STREAMER
var _run_data: SaveData
var _confirmation_state := IdentityConfirmationState.new()
var _selected_option: IdentityOption
var _busy := false
var _completed := false
var _player_presentation_is_completed := false
var _motive_comic_is_completed := false
var _room_transition_is_completed := false
var _streamer_page: Control
var _player_presentation_page: Control
var _motive_comic_page: Control
var _room_transition_page: Control
var _fan_page: Control
var _streamer_name_input: LineEdit
var _fan_group_name_input: LineEdit
var _streamer_continue: Button
var _confirm_button: Button
var _fan_back: Button
var _identity_back: Button
var _player_presentation_status: Label
var _motive_comic_status: Label
var _motive_comic_action: Button
var _room_transition_status: Label
var _room_transition_action: Button
var _status_label: Label
var _comic_control: ComicPanelPlaybackControl

@onready var _selection: Control = $IdentitySelection


# 所有步骤由同一场景持有，回退仅切换可见页面并保留当前临时输入。
func _ready() -> void:
	opening_saved.connect(_on_opening_saved)
	_run_data = SaveManager.data
	_identity_back = $IdentitySelection.get_node("%BackButton")
	_identity_back.show()
	_identity_back.text = "返回动机分镜"
	$IdentitySelection.get_node("Margins/Content/Title").text = "④ 选择你的身份"
	$IdentitySelection.get_node("%NextButton").text = "确认身份"
	_identity_back.pressed.connect(_back_to_motive_comic)
	_selection.next_requested.connect(_advance_identity)
	_selection.selection_changed.connect(func(option: IdentityOption): _selected_option = option)

	_streamer_page = _build_name_page("StreamerPage", "我的名字是……")
	_streamer_name_input = _streamer_page.get_node("Center/Panel/Content/NameInput")
	_streamer_continue = _streamer_page.get_node("Center/Panel/Content/Continue")
	_streamer_continue.text = "确认名字"
	_streamer_continue.pressed.connect(_advance_streamer)
	_streamer_name_input.text_submitted.connect(func(_value: String): _advance_streamer())

	_player_presentation_page = _build_placeholder_page(
		"PlayerPresentationPage",
		"姓名与仓鼠爪印",
		"TEST_ONLY：此处等待美术展示玩家姓名与仓鼠爪印。",
		"演出完成（占位）",
		"返回修改名字"
	)
	_player_presentation_status = _player_presentation_page.get_node("Center/Panel/Content/Status")
	_player_presentation_page.get_node("Center/Panel/Content/Action").pressed.connect(complete_player_presentation)
	_player_presentation_page.get_node("Center/Panel/Content/Back").pressed.connect(_back_to_streamer)

	_motive_comic_page = _build_placeholder_page(
		"MotiveComicPage",
		"仓鼠动机分镜",
		"TEST_ONLY_PANEL_01",
		"点击推进分镜",
		"返回修改名字"
	)
	_motive_comic_status = _motive_comic_page.get_node("Center/Panel/Content/Status")
	_motive_comic_action = _motive_comic_page.get_node("Center/Panel/Content/Action")
	_motive_comic_action.pressed.connect(advance_motive_comic_on_click)
	_motive_comic_page.get_node("Center/Panel/Content/Back").pressed.connect(_back_to_streamer)

	_room_transition_page = _build_placeholder_page(
		"RoomComputerTransitionPage",
		"仓鼠进入房间并打开电脑",
		"TEST_ONLY：此处等待美术提供房间与电脑转场。",
		"转场完成（占位）",
		"返回身份选择"
	)
	_room_transition_status = _room_transition_page.get_node("Center/Panel/Content/Status")
	_room_transition_action = _room_transition_page.get_node("Center/Panel/Content/Action")
	_room_transition_action.pressed.connect(complete_room_computer_transition)
	_room_transition_page.get_node("Center/Panel/Content/Back").pressed.connect(_back_to_identity)

	_fan_page = _build_name_page("FanGroupPage", "我想让支持我的人们叫……")
	_fan_group_name_input = _fan_page.get_node("Center/Panel/Content/NameInput")
	_confirm_button = _fan_page.get_node("Center/Panel/Content/Continue")
	_confirm_button.text = "确认并保存"
	_confirm_button.pressed.connect(_confirm_opening)
	_fan_group_name_input.text_submitted.connect(func(_value: String): _confirm_opening())
	_fan_back = _fan_page.get_node("Center/Panel/Content/Back")
	_fan_back.text = "返回房间转场"
	_fan_back.show()
	_fan_back.pressed.connect(_back_to_room_transition)
	_status_label = _fan_page.get_node("Center/Panel/Content/Status")

	if _run_data != null:
		_streamer_name_input.text = _run_data.streamer_name
		_fan_group_name_input.text = _run_data.fan_group_name
		if not _run_data.identity_id.is_empty():
			_restore_confirmed_run()
			return
	_show_step(Step.STREAMER)
	if _run_data == null:
		_streamer_page.get_node("Center/Panel/Content/Status").text = "请从主菜单开始新周目。"
		_streamer_continue.disabled = true


# 构建仅由现有主题与控件组成的演出占位页，未来美术可替换显示层。
func _build_placeholder_page(node_name: String, title_text: String, status_text: String, action_text: String, back_text: String) -> Control:
	var page := Control.new()
	page.name = node_name
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	var background := ColorRect.new()
	background.color = Color("191611")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(background)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(700, 0)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("453b2c")
	paper.border_color = Color("bba477")
	paper.set_border_width_all(2)
	paper.content_margin_left = 32
	paper.content_margin_right = 32
	paper.content_margin_top = 28
	paper.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", paper)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)
	var title := Label.new()
	title.name = "Title"
	title.text = title_text
	title.theme_type_variation = &"TitleLabel"
	content.add_child(title)
	var status := Label.new()
	status.name = "Status"
	status.text = status_text
	status.custom_minimum_size.y = 96
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(status)
	var action := Button.new()
	action.name = "Action"
	action.text = action_text
	action.custom_minimum_size.y = 64
	content.add_child(action)
	var back := Button.new()
	back.name = "Back"
	back.text = back_text
	back.custom_minimum_size.y = 56
	content.add_child(back)
	return page


# 名称输入沿用统一主题，主播名和粉丝团名都只在各自页面暂存。
func _build_name_page(node_name: String, title_text: String) -> Control:
	var page := Control.new()
	page.name = node_name
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(page)
	var background := ColorRect.new()
	background.color = Color("191611")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(background)
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(560, 0)
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("453b2c")
	paper.border_color = Color("bba477")
	paper.set_border_width_all(2)
	paper.content_margin_left = 32
	paper.content_margin_right = 32
	paper.content_margin_top = 28
	paper.content_margin_bottom = 28
	panel.add_theme_stylebox_override("panel", paper)
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)
	var title := Label.new()
	title.text = title_text
	title.theme_type_variation = &"TitleLabel"
	content.add_child(title)
	var input := LineEdit.new()
	input.name = "NameInput"
	input.custom_minimum_size.y = 58
	input.placeholder_text = "留空使用默认名称"
	content.add_child(input)
	var status := Label.new()
	status.name = "Status"
	status.text = "空白名称沿用默认值。"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	var next := Button.new()
	next.name = "Continue"
	next.text = "继续"
	next.custom_minimum_size.y = 64
	content.add_child(next)
	var back := Button.new()
	back.name = "Back"
	back.text = "返回身份选择"
	back.hide()
	content.add_child(back)
	return page


# 每个步骤切换只隐藏其他视图，保留名称、身份翻开状态及漫画播放进度。
func _show_step(step: Step) -> void:
	_step = step
	_streamer_page.visible = step == Step.STREAMER
	_player_presentation_page.visible = step == Step.PLAYER_PRESENTATION
	_motive_comic_page.visible = step == Step.MOTIVE_COMIC
	_selection.visible = step == Step.IDENTITY
	_room_transition_page.visible = step == Step.ROOM_TRANSITION
	_fan_page.visible = step == Step.FAN_GROUP
	match step:
		Step.STREAMER:
			_streamer_name_input.grab_focus()
		Step.PLAYER_PRESENTATION:
			_player_presentation_page.get_node("Center/Panel/Content/Action").grab_focus()
		Step.MOTIVE_COMIC:
			_motive_comic_action.text = "继续身份选择" if _motive_comic_is_completed else "点击推进分镜"
			_motive_comic_action.grab_focus()
		Step.IDENTITY:
			_selection.restore_selection(_selected_option.identity_id if _selected_option != null else &"")
			_selection.focus_selection()
		Step.ROOM_TRANSITION:
			_room_transition_action.text = "继续粉丝团取名" if _room_transition_is_completed else "转场完成（占位）"
			_room_transition_action.grab_focus()
		Step.FAN_GROUP:
			_fan_group_name_input.grab_focus()


# 主播名只暂存于输入控件，确认后请求爪印展示并等待公开完成入口。
func _advance_streamer() -> void:
	if _step != Step.STREAMER or _busy or _run_data == null:
		return
	_streamer_name_input.text = IdentityNameRules.confirm_streamer_name(_streamer_name_input.text)
	_player_presentation_is_completed = false
	_player_presentation_status.text = "TEST_ONLY：我的名字是「%s」。等待仓鼠爪印展示完成。" % _streamer_name_input.text
	_show_step(Step.PLAYER_PRESENTATION)
	player_name_pawprint_presentation_requested.emit(_streamer_name_input.text)


# 美术表现完成后发出完成事实，再启动已有的 ID-12 分镜控制器。
func complete_player_presentation() -> void:
	if _step != Step.PLAYER_PRESENTATION or _busy or _player_presentation_is_completed:
		return
	_player_presentation_is_completed = true
	player_name_pawprint_presentation_completed.emit(_streamer_name_input.text)
	_motive_comic_is_completed = false
	_create_motive_comic_control()
	_show_step(Step.MOTIVE_COMIC)
	if not _comic_control.start_playback():
		push_error("IdentitySetup: ID-12 comic playback could not start.")


# 创建本次展示所需的 ID-12 控制器实例；重看名字后使用新实例从首格播放。
func _create_motive_comic_control() -> void:
	if _comic_control != null:
		remove_child(_comic_control)
		_comic_control.free()
	_comic_control = ComicPanelPlaybackControl.new()
	_comic_control.name = "MotiveComicPlaybackControl"
	_comic_control.panel_count = PLACEHOLDER_PANEL_COUNT
	_comic_control.panel_interval_seconds = PLACEHOLDER_PANEL_INTERVAL_SECONDS
	_comic_control.panel_display_requested.connect(_on_motive_panel_display_requested)
	_comic_control.playback_completed.connect(_on_motive_comic_completed)
	add_child(_comic_control)


# ID-12 的格数请求同时交给占位显示和公开美术接口。
func _on_motive_panel_display_requested(panel_number: int) -> void:
	_motive_comic_status.text = "TEST_ONLY_PANEL_%02d · 自动计时或点击均可推进" % panel_number
	motive_panel_display_requested.emit(panel_number)


# ID-12 只在末格确认时通知完成；身份页仅在收到该事实后打开。
func _on_motive_comic_completed() -> void:
	_motive_comic_is_completed = true
	_motive_comic_status.text = "TEST_ONLY：动机分镜播放完成。"
	_motive_comic_action.text = "继续身份选择"
	motive_comic_completed.emit()
	if _step == Step.MOTIVE_COMIC:
		_show_step(Step.IDENTITY)


# 公开点击入口供漫画表现层复用；完成后再次点击可返回身份选择。
func advance_motive_comic_on_click() -> void:
	if _step != Step.MOTIVE_COMIC:
		return
	if _motive_comic_is_completed:
		_show_step(Step.IDENTITY)
	elif _comic_control != null:
		_comic_control.advance_on_click()


# 身份页下一步表示玩家确认当前已翻开的选项，之后请求房间电脑转场。
func _advance_identity(option: IdentityOption) -> void:
	if _step != Step.IDENTITY or _busy or not IdentityOptions.CARDS.has(option):
		return
	_selected_option = option
	_room_transition_is_completed = false
	_room_transition_status.text = "TEST_ONLY：进入房间并打开电脑 · 身份 %s" % option.identity_id
	_room_transition_action.text = "转场完成（占位）"
	_show_step(Step.ROOM_TRANSITION)
	room_computer_transition_requested.emit(option.identity_id)


# 美术转场完成后才打开已有的粉丝团取名页。
func complete_room_computer_transition() -> void:
	if _step != Step.ROOM_TRANSITION or _busy:
		return
	if _room_transition_is_completed:
		_show_step(Step.FAN_GROUP)
		return
	_room_transition_is_completed = true
	room_computer_transition_completed.emit()
	_show_step(Step.FAN_GROUP)


# 从动机漫画返回主播名后，名称确认会重新请求展示并重启漫画播放。
func _back_to_streamer() -> void:
	if _step in [Step.PLAYER_PRESENTATION, Step.MOTIVE_COMIC] and not _busy:
		_show_step(Step.STREAMER)


# 身份页返回只重开当前已完成的漫画画面，保留卡片翻开及选择状态。
func _back_to_motive_comic() -> void:
	if _step == Step.IDENTITY and not _busy:
		_show_step(Step.MOTIVE_COMIC)


# 房间转场未完成时返回身份页；重新确认后会再次发送转场请求。
func _back_to_identity() -> void:
	if _step == Step.ROOM_TRANSITION and not _busy:
		_show_step(Step.IDENTITY)


# 从粉丝团名返回只重开已完成的转场占位页，不重复触发美术请求。
func _back_to_room_transition() -> void:
	if _step == Step.FAN_GROUP and not _busy and not _confirmation_state.has_confirmed_identity():
		_show_step(Step.ROOM_TRANSITION)


# 已存周目恢复锁定记录；旧 ID 原样保留，未知 ID 禁止重新确认。
func _restore_confirmed_run() -> void:
	_selected_option = IdentityOptions.find_option(_run_data.identity_id)
	_show_step(Step.FAN_GROUP)
	_lock_inputs()
	if _selected_option == null:
		_status_label.text = "已保存身份无法识别，请保留存档并检查配置。"
		_confirm_button.disabled = true
		return
	_confirmation_state.confirm_identity(_run_data.identity_id, [_run_data.identity_id])
	_status_label.text = "本周目身份已锁定；可重试保存并交接开局房间。"
	_confirm_button.grab_focus()


# 唯一最终提交入口；忙碌和完成标记在外部调用前设置，防止同步重入。
func _confirm_opening() -> void:
	if _step != Step.FAN_GROUP or _busy:
		return
	# 保存已经成功时只重试房间路由，保持同一周目及已锁定身份。
	if _completed:
		_on_opening_saved(_run_data)
		return
	if _run_data == null or SaveManager.data != _run_data:
		_status_label.text = "当前周目已变化，请从主菜单重新开始。"
		return
	_busy = true
	if not _confirmation_state.has_confirmed_identity():
		var error := SaveManager.confirm_opening_identity(
			_streamer_name_input.text, _selected_option, _fan_group_name_input.text, _confirmation_state)
		if error != OK:
			_status_label.text = "身份提交失败：%s。可重试。" % error_string(error)
			_busy = false
			return
		_streamer_name_input.text = _run_data.streamer_name
		_fan_group_name_input.text = _run_data.fan_group_name
		_lock_inputs()
	if _run_data.identity_id != _confirmation_state.get_confirmed_identity_id():
		_status_label.text = "当前存档与已确认身份不一致，请保留数据并检查。"
		_busy = false
		return
	var save_error := SaveManager.save_game()
	_busy = false
	if save_error != OK:
		_status_label.text = "身份已锁定，存档失败：%s。点击重试保存。" % error_string(save_error)
		_confirm_button.text = "重试保存"
		_confirm_button.grab_focus()
		return
	_completed = true
	_confirm_button.text = "已保存"
	_confirm_button.disabled = true
	_status_label.text = "身份已保存，正在进入房间。"
	opening_saved.emit(_run_data)


# 接收保存事实后请求顶层切换；失败时允许重试，成功期间拒绝重复请求。
func _on_opening_saved(run_data: SaveData) -> void:
	if _busy:
		return
	if run_data == null or SaveManager.data != run_data:
		_status_label.text = "当前周目已变化，请从主菜单重新开始。"
		_confirm_button.disabled = true
		return
	_busy = true
	_confirm_button.disabled = true
	var error := SceneRouter.goto_opening_room()
	if error != OK:
		_busy = false
		_status_label.text = "进入房间失败：%s。已保存身份保持，可重试。" % error_string(error)
		_confirm_button.text = "重试进入房间"
		_confirm_button.disabled = false
		_confirm_button.grab_focus()


# 名称和身份只在正式提交后锁定，保存重试沿用同一周目对象。
func _lock_inputs() -> void:
	_streamer_name_input.editable = false
	_fan_group_name_input.editable = false
	_fan_back.disabled = true
	_identity_back.disabled = true
	_selection.restore_selection(_run_data.identity_id, true)
