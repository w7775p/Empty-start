extends Node

# 统一维护主菜单和游戏入口的目标路径，避免 UI 分散保存场景路径。
# 剧情播放入口独立于正式 EndingSession；只保存本次路由参数。
const COMIC_SCENE_PATH: String = "res://ui/comic/comic_player.tscn"
var comic_kind: StringName = &"opening"
var comic_record_first_view: bool = false

func goto_comic(kind: StringName, record_first_view: bool = false) -> Error:
	# 仅接受已配置的两段漫画，不创建周目或伪造结局对象。
	if kind not in [&"intro", &"opening", &"ending"]:
		return ERR_INVALID_PARAMETER
	var scene: PackedScene = _load_scene(COMIC_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	comic_kind = kind
	comic_record_first_view = record_first_view
	return _change_scene(scene)

const MAIN_MENU_SCENE_PATH: String = "res://ui/main_menu/main_menu.tscn"
const IDENTITY_SETUP_SCENE_PATH: String = "res://ui/identity_setup/identity_setup.tscn"
const OPENING_ROOM_SCENE_PATH: String = "res://ui/rest/rest_opening_room.tscn"
const GAME_SCENE_PATH: String = "res://scenes/sandbox/sandbox_plan_b.tscn"
const ENDING_SCENE_PATH: String = "res://ui/ending/ending_page.tscn"

# 集成夹具可显式替换游戏入口，默认仍加载正式场景。
var game_scene_override: PackedScene
var _ending_session: EndingSession
var _saved_ending_display: Dictionary = {}


func goto_main_menu() -> Error:
	# 加载并切换到项目约定的主菜单场景。
	var scene: PackedScene = _load_scene(MAIN_MENU_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	return _change_scene(scene)


func goto_identity_setup() -> Error:
	# 新周目的身份设置作为顶层页面统一通过 SceneRouter 切换。
	var scene: PackedScene = _load_scene(IDENTITY_SETUP_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	return _change_scene(scene)


func goto_opening_room() -> Error:
	# 身份保存后先进入独立房间；此阶段尚未实例化普通战斗。
	var scene: PackedScene = _load_scene(OPENING_ROOM_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	return _change_scene(scene)


func goto_game() -> Error:
	# 加载并切换到项目约定的游戏入口场景。
	var scene: PackedScene = game_scene_override if game_scene_override != null else _load_scene(GAME_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	return _change_scene(scene)


# 保留唯一接收对象，实际顶层切换完成后把固定显示结果交给现有页面。
func goto_ending(session: EndingSession) -> Error:
	if session == null or not session.is_received():
		return ERR_INVALID_PARAMETER
	if _ending_session == session:
		return ERR_ALREADY_IN_USE
	var scene := _load_scene(ENDING_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	_ending_session = session
	_saved_ending_display.clear()
	get_tree().scene_changed.connect(_show_ending, CONNECT_ONE_SHOT)
	var error := _change_scene(scene)
	if error != OK:
		get_tree().scene_changed.disconnect(_show_ending)
		_ending_session = null
	return error


# 新页面由 Godot 初始化完成；不再查询可变的 SaveData。
func _show_ending() -> void:
	var page := get_tree().current_scene as EndingPage
	if page != null and _ending_session != null:
		page.show_ending(_ending_session.get_display_data())
	elif page != null and not _saved_ending_display.is_empty():
		page.show_ending(_saved_ending_display)


## 已完成周目读档只呈现保存的 Ending 显示快照，不再次执行终局或奖励。
func goto_saved_ending(display_data: Dictionary) -> Error:
	if display_data.is_empty() or not display_data.has("scripture"):
		return ERR_INVALID_DATA
	var scene := _load_scene(ENDING_SCENE_PATH)
	if scene == null:
		return ERR_FILE_NOT_FOUND
	_ending_session = null
	_saved_ending_display = display_data.duplicate(true)
	get_tree().scene_changed.connect(_show_ending, CONNECT_ONE_SHOT)
	var error := _change_scene(scene)
	if error != OK:
		get_tree().scene_changed.disconnect(_show_ending)
		_saved_ending_display.clear()
	return error


func reload_current_scene() -> Error:
	# 直接委托 Godot 重载当前场景，保留引擎原生生命周期行为。
	var error: Error = get_tree().reload_current_scene()
	if error != OK:
		push_error("SceneRouter: reload_current_scene failed: %s" % error_string(error))
	return error


func _load_scene(scene_path: String) -> PackedScene:
	# 空场景或损坏资源不能进入切换流程，统一在这里留下可定位的错误。
	if not ResourceLoader.exists(scene_path, "PackedScene"):
		push_error("SceneRouter: scene resource not found: %s" % scene_path)
		return null

	var resource: Resource = ResourceLoader.load(scene_path, "PackedScene")
	if resource == null or not resource is PackedScene:
		push_error("SceneRouter: scene resource is not a valid PackedScene: %s" % scene_path)
		return null
	return resource as PackedScene


func _change_scene(scene: PackedScene) -> Error:
	# 固定目标场景统一通过 Godot 原生 PackedScene 接口切换并回传错误。
	if scene == null:
		var invalid_error: Error = ERR_INVALID_PARAMETER
		push_error("SceneRouter: cannot change to a null PackedScene")
		return invalid_error

	var error: Error = get_tree().change_scene_to_packed(scene)
	if error == OK:
		# 顶层目标场景独立开始，退出旧暂停页时清除全树暂停状态。
		get_tree().paused = false
	if error != OK:
		push_error("SceneRouter: change_scene_to_packed failed: %s" % error_string(error))
	return error
