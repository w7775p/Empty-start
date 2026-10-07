extends CanvasLayer

signal selection_requested(candidate: Dictionary)

const MAX_DISPLAYED_CANDIDATES: int = 3

@onready var _overlay: Control = %Overlay
@onready var _candidate_list: VBoxContainer = %CandidateList
@onready var _empty_hint: Label = %EmptyHint
@onready var _countdown: Label = %Countdown

var _session: FinalOracleSession
var _display_snapshot: Array[Dictionary] = []
var _selection_timer: FinalOracleSelectionTimer
var _selection_buttons: Array[Button] = []
var _selection_confirmed: bool = false


func _ready() -> void:
	# 选择计时要在全局暂停时继续检查暂停状态，再由计时器冻结剩余时间。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.hide()
	_countdown.hide()
	selection_requested.connect(_confirm_candidate)


# 每帧传入真实 SceneTree 暂停状态，暂停期间计时器保持原剩余值。
func _process(delta_seconds: float) -> void:
	if _selection_timer == null:
		return
	_selection_timer.advance(delta_seconds, get_tree().paused)


# 只读取 FinalOracleSession 已冻结的展示快照，不重新查询或排序候选。
func present_session(session: FinalOracleSession) -> void:
	if session == null or not session.is_open():
		return
	_session = session
	_display_snapshot = session.get_display_candidates()
	_selection_confirmed = false
	_render_display_snapshot()
	_overlay.show()
	_selection_timer = null
	if not _session.get_confirmed_selection().is_empty():
		_countdown.show()
		_lock_selection_after_confirmation()
		return
	if not _display_snapshot.is_empty():
		_countdown.show()
		_selection_timer = FinalOracleSelectionTimer.new()
		_selection_timer.remaining_time_changed.connect(_on_selection_time_changed)
		_selection_timer.expired.connect(_on_selection_timer_expired)
		_selection_timer.start()


# 关卡重开时收起旧神谕页面并释放本地展示快照。
func close_screen() -> void:
	_overlay.hide()
	_session = null
	_display_snapshot.clear()
	_selection_timer = null
	_selection_confirmed = false
	_countdown.hide()
	_clear_candidate_list()


func _render_display_snapshot() -> void:
	_clear_candidate_list()
	var displayed_count: int = mini(_display_snapshot.size(), MAX_DISPLAYED_CANDIDATES)
	_empty_hint.visible = displayed_count == 0
	for index in range(displayed_count):
		var card := _create_candidate_card(index, _display_snapshot[index])
		_candidate_list.add_child(card)
		_apply_compact_card_styles(card, _selection_buttons.back())


# 从候选快照读取显示字段；原句正文由场景协调方按稳定 ID 补齐。
func _create_candidate_card(index: int, candidate: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 124.0)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 2)
	var header := Label.new()
	header.theme_type_variation = &"MutedLabel"
	header.add_theme_font_size_override("font_size", 18)
	header.text = "%s · 候选 %d" % [
		_get_tendency_label(str(candidate.get("tendency", ""))),
		index + 1,
	]
	var sentence_id: String = str(candidate.get("original_sentence_id", ""))
	var sentence_text: String = str(candidate.get("original_sentence_text", sentence_id))
	var select_button := Button.new()
	select_button.theme_type_variation = &"SecondaryButton"
	select_button.custom_minimum_size = Vector2(0.0, 64.0)
	select_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	select_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	select_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	select_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	select_button.text = "「%s」\n选择这句话" % sentence_text
	select_button.pressed.connect(_on_candidate_button_pressed.bind(candidate))
	content.add_child(header)
	content.add_child(select_button)
	card.add_child(content)
	_selection_buttons.append(select_button)
	return card


# 卡片和按钮沿用项目主题外观，同时压缩内边距让三条候选适配 720p 高度。
func _apply_compact_card_styles(card: PanelContainer, select_button: Button) -> void:
	var card_style := card.get_theme_stylebox("panel").duplicate() as StyleBox
	card_style.content_margin_left = 12.0
	card_style.content_margin_right = 12.0
	card_style.content_margin_top = 8.0
	card_style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", card_style)
	select_button.add_theme_font_size_override("font_size", 18)
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var button_style := select_button.get_theme_stylebox(style_name).duplicate() as StyleBox
		button_style.content_margin_left = 12.0
		button_style.content_margin_right = 12.0
		button_style.content_margin_top = 4.0
		button_style.content_margin_bottom = 4.0
		select_button.add_theme_stylebox_override(style_name, button_style)


func _clear_candidate_list() -> void:
	_selection_buttons.clear()
	for child in _candidate_list.get_children():
		_candidate_list.remove_child(child)
		child.queue_free()


# 把纯逻辑计时器广播的剩余秒数显示给玩家。
func _on_selection_time_changed(seconds_remaining: float) -> void:
	_countdown.text = "%.1f 秒" % seconds_remaining


# 超时只产生一个候选选择请求，后续确认由 FO-09 共用入口处理。
func _on_selection_timer_expired() -> void:
	if _session == null or _selection_confirmed:
		return
	var candidate: Dictionary = _session.select_timeout_candidate()
	if candidate.is_empty():
		return
	_countdown.text = "已自动选择"
	selection_requested.emit(candidate)


# 手动按钮把候选副本送到自动超时共用的选择请求信号。
func _on_candidate_button_pressed(candidate: Dictionary) -> void:
	if get_tree().paused or _selection_confirmed:
		return
	selection_requested.emit(candidate.duplicate(true))


# 手动和超时结果都只调用 Session 的单一确认入口。
func _confirm_candidate(candidate: Dictionary) -> void:
	if get_tree().paused or _selection_confirmed or _session == null:
		return
	if not _session.confirm_display_candidate(candidate):
		return
	_lock_selection_after_confirmation()


# 首次成功确认后停止计时并锁住所有候选按钮。
func _lock_selection_after_confirmation() -> void:
	_selection_confirmed = true
	_selection_timer = null
	_countdown.text = "选择已确认"
	for select_button: Button in _selection_buttons:
		select_button.disabled = true


func _get_tendency_label(tendency_id: String) -> String:
	match tendency_id:
		"orthodox":
			return "正统"
		"heretical":
			return "异端"
		"absurd":
			return "荒谬"
		_:
			return "未知倾向"
