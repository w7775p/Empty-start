class_name EndingPage
extends Control

const SCRIPTURE_ROW: PackedScene = preload("res://ui/ending/ending_scripture_row.tscn")
signal credits_stage_changed(stage: StringName)

# 所有时长使用游戏时间，暂停后保留阅读进度；每阶段内容完全退场才进入下一段。
const PRODUCTION_HOLD: float = 8.0
const SPECIAL_THANKS_HOLD: float = 12.0

var _display_data: Dictionary = {}
var _ending_music: EndingMusicPresenter
var _scripture_heading: Control
var _production_group: VBoxContainer
var _production_title: Label
var _production_roster: VBoxContainer
var _special_group: VBoxContainer
var _performance: Control
var _credits_tween: Tween
var _credits_stage: StringName = &"static"
var _credits_body_font: FontVariation
var _credits_heading_font: FontVariation

@onready var _main_art: TextureRect = %MainArt
@onready var _religion_name: Label = %ReligionName
@onready var _religion_description: Label = %ReligionDescription
@onready var _scripture_rows: VBoxContainer = %ScriptureRows
@onready var _empty_scripture: Label = %EmptyScripture
@onready var _judgement_section: PanelContainer = %JudgementSection
@onready var _judgement_text: Label = %JudgementText
@onready var _scroll: ScrollContainer = %PageScroll


# 初始化完成后呈现已收到的数据；单独启动时采用空资源的安全显示状态。
func _ready() -> void:
	_build_credits()
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
	_religion_description.text = str(_display_data.get("religion_description", ""))
	_religion_description.visible = not _religion_description.text.is_empty()
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

# 鸣谢放在通关动画之后；圣典与判词仍保留在同页下方，不重新结算周目。
func _build_credits() -> void:
	# 局部使用项目已有思源黑体的正常/半粗字重，不改变全局主题或其他页面。
	_credits_body_font = _credit_font(500.0)
	_credits_heading_font = _credit_font(650.0)
	var content: VBoxContainer = $Margin/PageScroll/Content
	_scripture_heading = content.get_node("Title")
	(_scripture_heading as Label).text = "本次圣典"
	content.get_node("MusicCredit").hide()
	var margin := MarginContainer.new()
	margin.name = "Credits"
	margin.custom_minimum_size.y = 1000
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_"+side, 96)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_"+side, 32)
	content.add_child(margin)
	# 静态结局页保留主图、教名、圣典与判词优先，鸣谢滚动区放在末尾。
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	_credit_label(column,"鸣谢",48)
	_credit_label(column,"感谢游玩",24,Color("#b7c4c9"))
	# 静态成果页与通关演出共用同一组实际控件，标题、完整名单分别作为动画对象。
	_production_group = _credit_column(column,"ProductionGroup")
	_production_title = _credit_label(_production_group,"制作组",24,Color("#d5bc7e"))
	_production_roster = _credit_column(_production_group,"ProductionRoster")
	_credit_label(_production_roster,"策划：昂昂\n程序：昂昂、Akai\n场景美术：小火车\n角色美术：番茄牛腩\nUI：番茄牛腩、小火车\n音乐音效：Akai",23)
	column.add_child(HSeparator.new())
	_special_group = _credit_column(column,"SpecialThanks")
	_credit_label(_special_group,"特别鸣谢",30,Color("#d5bc7e"))
	_credit_label(_special_group,"音乐　煉獄庭園 ／ 作曲・編曲：煉獄小僧",24)
	_credit_label(_special_group,"街 ／ Cafe de Fineday ／ Pop Sky ／ Pure Soul ／ 夢灯 -YumeAkari-\n天導 -Tendoh- ／ Teek Teek Teek ／ 美哀 -Blai- ／ 草原ダンスィング♪-RemakeVer- ／ FELT LOVE\nhttps://note.com/rengokuteien",18,Color("#bdc8ce"))
	# 用户取消片尾CC0音效致谢；原作者、许可与加工记录继续保留在素材README。
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation",24)
	column.add_child(row)
	var scripture := Button.new()
	scripture.text = "查看本次圣典"
	scripture.custom_minimum_size = Vector2(260,64)
	row.add_child(scripture)
	AudioManager.bind_ui_button(scripture)
	scripture.pressed.connect(func(): _scroll.scroll_vertical = int(_scripture_heading.position.y))
	var menu := Button.new()
	menu.name = "CreditsMainMenu"
	menu.text = "返回主菜单"
	menu.custom_minimum_size = Vector2(260,64)
	row.add_child(menu)
	AudioManager.bind_ui_button(menu)
	menu.pressed.connect(func():
		var error := SceneRouter.goto_main_menu()
		if error != OK: push_error("EndingPage: 返回主菜单失败：%s" % error_string(error)))

# 长曲目和来源自动换行，避免低分辨率与窗口缩放时裁切署名。
func _credit_label(parent: Control, text: String, font_size: int, tint: Color = Color("#eee9dc")) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_font_override("font",_credits_heading_font if font_size>=30 or text=="制作组" else _credits_body_font)
	label.add_theme_color_override("font_color",tint)
	parent.add_child(label)
	return label

# 可变字体必须显式选择wght，不能依赖默认细字重。
func _credit_font(weight: float) -> FontVariation:
	var font := FontVariation.new()
	font.base_font = preload("res://assets/fonts/NotoSansSC-VF.ttf")
	font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"):weight}
	return font

# 分组只提供透明度动画边界，保留原VBox的20px间距、居中和字体参数。
func _credit_column(parent: Control, node_name: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	column.add_theme_constant_override("separation",20)
	parent.add_child(column)
	return column

# 由路由在正式结尾后调用；普通打开鸣谢仅显示静态内容，不能启动解锁链。
func start_credits_performance() -> void:
	if _credits_stage != &"static" or not SceneRouter.is_ending_performance_active():
		return
	_credits_stage = &"waiting"
	# 用户要求通关片尾纯黑；静态圣典页保留原来的背景。
	$Background.color = Color.BLACK
	$Margin.hide()
	_performance = MarginContainer.new()
	_performance.name = "CreditsPerformance"
	add_child(_performance)
	_performance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		_performance.add_theme_constant_override("margin_"+side,96)
	for side in ["top", "bottom"]:
		_performance.add_theme_constant_override("margin_"+side,32)
	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	_performance.add_child(center)
	_production_group.reparent(center)
	_special_group.reparent(center)
	_production_group.hide()
	_special_group.hide()
	# 等路由揭幕结束再开始，保证标题渐显的0.5秒完整可见。
	if SceneRouter.is_transitioning():
		SceneRouter.transition_finished.connect(_on_credits_revealed,CONNECT_ONE_SHOT)
	else:
		_play_credits()

func get_credits_stage() -> StringName:
	return _credits_stage

func _on_credits_revealed(_path: String) -> void:
	_play_credits()

# 全名单只Tween父容器一次，不触碰内部行的相对位置或字数。
func _play_credits() -> void:
	if _credits_stage != &"waiting":
		return
	_production_group.modulate.a = 1.0
	_production_title.modulate.a = 0.0
	_production_roster.modulate.a = 0.0
	_production_group.show()
	_set_credits_stage(&"production_title")
	_credits_tween = create_tween()
	_credits_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_credits_tween.tween_property(_production_title,"modulate:a",1.0,0.5)
	_credits_tween.tween_callback(_set_credits_stage.bind(&"production_roster"))
	_credits_tween.tween_property(_production_roster,"modulate:a",1.0,0.8)
	_credits_tween.tween_callback(_set_credits_stage.bind(&"production_hold"))
	_credits_tween.tween_interval(PRODUCTION_HOLD)
	_credits_tween.tween_property(_production_group,"modulate:a",0.0,0.6)
	_credits_tween.tween_callback(_show_special_thanks)
	_credits_tween.tween_property(_special_group,"modulate:a",1.0,0.8)
	_credits_tween.tween_callback(_set_credits_stage.bind(&"special_hold"))
	_credits_tween.tween_interval(SPECIAL_THANKS_HOLD)
	_credits_tween.tween_property(_special_group,"modulate:a",0.0,0.6)
	_credits_tween.tween_callback(_finish_credits)

# 旧组完全透明并隐藏后再显示下一组，不会同时占用布局或叠加文字。
func _show_special_thanks() -> void:
	_production_group.hide()
	_special_group.modulate.a = 0.0
	_special_group.show()
	_set_credits_stage(&"special_thanks")

func _set_credits_stage(stage: StringName) -> void:
	_credits_stage = stage
	credits_stage_changed.emit(stage)

# 只发出本页的完成请求；存档解锁由路由在标题显现后提交。
func _finish_credits() -> void:
	_special_group.hide()
	_set_credits_stage(&"complete")
	var error := SceneRouter.finish_ending_credits(self)
	if error != OK:
		push_error("EndingPage: 片尾返回标题失败：%s" % error_string(error))

# 场景被关闭时取消时间线，中断不会调用完成回调。
func _exit_tree() -> void:
	if _credits_tween != null and _credits_tween.is_valid():
		_credits_tween.kill()
