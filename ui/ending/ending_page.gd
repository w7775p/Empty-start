class_name EndingPage
extends Control

const SCRIPTURE_ROW: PackedScene = preload("res://ui/ending/ending_scripture_row.tscn")

var _display_data: Dictionary = {}
var _ending_music: EndingMusicPresenter

@onready var _main_art: TextureRect = %MainArt
@onready var _religion_name: Label = %ReligionName
@onready var _scripture_rows: VBoxContainer = %ScriptureRows
@onready var _empty_scripture: Label = %EmptyScripture
@onready var _judgement_section: PanelContainer = %JudgementSection
@onready var _judgement_text: Label = %JudgementText
@onready var _scroll: ScrollContainer = %PageScroll


# 初始化完成后呈现已收到的数据；单独启动时采用空资源的安全显示状态。
func _ready() -> void:
	_ending_music = EndingMusicPresenter.new()
	add_child(_ending_music)
	_ending_music.start()
	_apply_display_data()


# 接收 EN-07 的显示结果；允许组合方在入树前设置，页面只持有显示快照。
func show_ending(display_data: Dictionary) -> void:
	_display_data = display_data.duplicate(true)
	if is_node_ready():
		_apply_display_data()


# 只绘制已有结果，章节顺序、编号、教名及判词均由数据提供方决定。
func _apply_display_data() -> void:
	_main_art.texture = _display_data.get("main_art") as Texture2D
	_main_art.visible = _main_art.texture != null
	# EN-10：仅给主图染色；倾向数据仍由现有冻结显示快照提供。
	# 每次刷新先恢复原色，避免不同结局/空结果复用页面时留下旧颜色。
	_main_art.modulate = Color.WHITE
	match str(_display_data.get("primary_tendency_id", "")):
		"orthodox":
			_main_art.modulate = Color(1.0, 0.83, 0.55)
		"heretical":
			_main_art.modulate = Color(0.76, 0.63, 1.0)
		"absurd":
			_main_art.modulate = Color(0.55, 1.0, 0.85)
	_religion_name.text = str(_display_data.get("religion_name", ""))
	_religion_name.visible = not _religion_name.text.is_empty()
	_judgement_text.text = str(_display_data.get("judgement_text", ""))
	_judgement_section.visible = not _judgement_text.text.is_empty()
	# 重复呈现先移除旧行，避免同一帧显示新旧两份经文。
	for child: Node in _scripture_rows.get_children():
		_scripture_rows.remove_child(child)
		child.queue_free()
	var scripture: Dictionary = _display_data.get("scripture", {})
	var rows: Array = scripture.get("rows", [])
	# 全空圣典沿用 EN-07 空态并继续绘制缺章，其余结局内容照常呈现。
	_empty_scripture.visible = bool(scripture.get("is_empty", true))
	for row: Dictionary in rows:
		var row_view: EndingScriptureRow = SCRIPTURE_ROW.instantiate() as EndingScriptureRow
		_scripture_rows.add_child(row_view)
		row_view.show_row(row)
	# 空配置收起内容后容器会重新布局，延后归零避免布局沿用旧滚动位置。
	_scroll.set_deferred("scroll_vertical", 0)
