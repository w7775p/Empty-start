extends Control

var _run_data: SaveData
var _starting := false
var _room_music: RoomMusicPresenter
const PAUSE_MENU: PackedScene = preload("res://ui/pause_menu/pause_menu.tscn")
const LEVEL_CATALOG: LevelCatalog = preload("res://data/level_configuration/level_catalog.tres")
const LOSER_CARD_CATALOG: LoserCardCatalog = preload("res://data/loser_card/loser_card_catalog.tres")

@onready var _environment: RestRoomEnvironment = $RoomEnvironment
@onready var _names: Label = %Names
@onready var _status: Label = %Status
@onready var _start_button: Button = %StartLiveButton
@onready var _laptop_button: TextureButton = $LaptopButton
@onready var _menu_layer: Control = $MenuLayer
@onready var _gallery_button: Button = %GalleryButton
@onready var _scripture_button: Button = %ScriptureButton
@onready var _gallery_view: LoserCardHistoryView = %LoserCardHistoryView
@onready var _scripture_view: ScriptureHistoryView = %ScriptureHistoryView

# 入口只负责房间电脑和只读历史页；旧周目、暂停、开播路由保持原状。
func _ready() -> void:
	var pause := PAUSE_MENU.instantiate()
	add_child(pause)
	pause.set_restart_available(false)
	_room_music = RoomMusicPresenter.new()
	add_child(_room_music)
	pause.paused_changed.connect(_room_music.set_paused)
	_run_data = SaveManager.data
	_laptop_button.pressed.connect(_open_computer_menu)
	$MenuLayer/Backdrop.gui_input.connect(_on_backdrop_input)
	_start_button.pressed.connect(start_live)
	_gallery_button.pressed.connect(_open_gallery)
	_scripture_button.pressed.connect(_open_scripture)
	_gallery_view.back_requested.connect(_return_to_computer_menu)
	_scripture_view.back_requested.connect(_return_to_computer_menu)

	# 按原 PNG 透明区域生成点击形状，玩家必须点在桌面电脑上。
	var laptop_image: Image = _laptop_button.texture_normal.get_image()
	if laptop_image != null:
		var click_mask := BitMap.new()
		click_mask.create_from_image_alpha(laptop_image, 0.12)
		_laptop_button.texture_click_mask = click_mask

	_menu_layer.hide()
	_gallery_view.hide()
	_scripture_view.hide()
	if _run_data == null or _run_data.identity_id.is_empty() or _run_data.tendency_state == null:
		_status.text = "开局资料暂不可用，请从主菜单完成身份确认。"
		_start_button.disabled = true
		_environment.apply_tendency("")
		return
	_names.text = "主播：%s\n粉丝团：%s" % [_run_data.streamer_name, _run_data.fan_group_name]
	_environment.apply_tendency(_run_data.tendency_state.get_primary_tendency_id())
	if _run_data.next_normal_level_order > 1:
		_status.text = "准备开始第 %d 场直播" % _run_data.next_normal_level_order
	_laptop_button.grab_focus()
	_room_music.start(_run_data.next_normal_level_order > 1)


# 桌面电脑的高亮形状是唯一开菜单入口；菜单仅在点击后出现。
func _open_computer_menu() -> void:
	if get_tree().paused:
		return
	_menu_layer.show()
	_start_button.grab_focus()


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_computer_menu()
		get_viewport().set_input_as_handled()


func _close_computer_menu() -> void:
	_menu_layer.hide()
	_laptop_button.grab_focus()


# 图鉴沿用正式败者卡收藏组件，尚未获得的卡片显示已有空态。
func _open_gallery() -> void:
	if _run_data == null:
		return
	_menu_layer.hide()
	_gallery_view.show_history(_run_data.loser_card_data, LOSER_CARD_CATALOG)


# 圣典复用现有已提交章节的只读历史组件，不修改任何经文。
func _open_scripture() -> void:
	if _run_data == null:
		return
	_menu_layer.hide()
	_scripture_view.show_history(_run_data.scripture_data, LEVEL_CATALOG)


func _return_to_computer_menu() -> void:
	_gallery_view.hide()
	_scripture_view.hide()
	_menu_layer.show()
	_start_button.grab_focus()


# ESC 关闭电脑菜单；历史子页仍由各自返回按钮管理。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _menu_layer.visible and not get_tree().paused:
		_close_computer_menu()
		get_viewport().set_input_as_handled()


# 请求成功后直到页面退出都保持锁定，同帧连点和直接重复调用只启动一次。
func start_live() -> Error:
	if get_tree().paused:
		return ERR_BUSY
	if _starting:
		return ERR_ALREADY_IN_USE
	if _run_data == null or SaveManager.data != _run_data or _run_data.identity_id.is_empty() or _run_data.tendency_state == null:
		_status.text = "当前周目已变化，请从主菜单重新开始。"
		_start_button.disabled = true
		return ERR_UNCONFIGURED
	_starting = true
	_start_button.disabled = true
	_status.text = "正在开始直播……"
	var error := SceneRouter.goto_game()
	if error != OK:
		_starting = false
		_status.text = "开始直播失败：%s。可重试。" % error_string(error)
		_start_button.disabled = false
		_start_button.grab_focus()
	return error
