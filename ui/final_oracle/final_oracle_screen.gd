extends CanvasLayer

const MAX_DISPLAYED_CANDIDATES: int = 3

@onready var _overlay: Control = %Overlay
@onready var _candidate_list: VBoxContainer = %CandidateList
@onready var _empty_hint: Label = %EmptyHint

var _session: FinalOracleSession
var _display_snapshot: Array[Dictionary] = []


func _ready() -> void:
	_overlay.hide()


# 只读取 FinalOracleSession 已冻结的展示快照，不重新查询或排序候选。
func present_session(session: FinalOracleSession) -> void:
	if session == null or not session.is_open():
		return
	_session = session
	_display_snapshot = session.get_display_candidates()
	_render_display_snapshot()
	_overlay.show()


# 关卡重开时收起旧神谕页面并释放本地展示快照。
func close_screen() -> void:
	_overlay.hide()
	_session = null
	_display_snapshot.clear()
	_clear_candidate_list()


func _render_display_snapshot() -> void:
	_clear_candidate_list()
	var displayed_count: int = mini(_display_snapshot.size(), MAX_DISPLAYED_CANDIDATES)
	_empty_hint.visible = displayed_count == 0
	for index in range(displayed_count):
		_candidate_list.add_child(_create_candidate_card(index, _display_snapshot[index]))


# 从候选快照读取显示字段；原句正文由场景协调方按稳定 ID 补齐。
func _create_candidate_card(index: int, candidate: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0.0, 126.0)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var header := Label.new()
	header.theme_type_variation = &"MutedLabel"
	header.text = "%s · 候选 %d" % [
		_get_tendency_label(str(candidate.get("tendency", ""))),
		index + 1,
	]
	var sentence := Label.new()
	sentence.theme_type_variation = &"HeadingLabel"
	sentence.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sentence.custom_minimum_size = Vector2(0.0, 64.0)
	sentence.custom_maximum_size = Vector2(820.0, 0.0)
	sentence.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sentence_id: String = str(candidate.get("original_sentence_id", ""))
	sentence.text = str(candidate.get("original_sentence_text", sentence_id))
	content.add_child(header)
	content.add_child(sentence)
	card.add_child(content)
	return card


func _clear_candidate_list() -> void:
	for child in _candidate_list.get_children():
		_candidate_list.remove_child(child)
		child.queue_free()


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
