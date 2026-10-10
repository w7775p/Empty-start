class_name RestResultView
extends CanvasLayer

signal continue_requested
signal result_performance_finished

var _result_active: bool = false
var _menu_input_enabled: bool = false
var _presentation_id: int = 0
var _battle_aim: AimReticle
var _aim_input_was_enabled: bool = false
var _aim_suspended: bool = false

# 只保留当前休息上下文引用，历史事实由 15 / 16 各自持有。
var _history_scripture: ScriptureData
var _history_level_catalog: LevelCatalog
var _history_loser_cards: LoserCardData
var _history_loser_card_catalog: LoserCardCatalog

@onready var _overlay: Control = %Overlay
@onready var _room_environment: RestRoomEnvironment = %RoomEnvironment
@onready var _result_title: Label = %ResultTitle
@onready var _result_description: Label = %ResultDescription
@onready var _live_result: Label = %LiveResult
@onready var _new_rewards_empty: Label = %NewRewardsEmpty
@onready var _history_empty_states: VBoxContainer = %HistoryEmptyStates
@onready var _scripture_history_empty: Label = %ScriptureHistoryEmpty
@onready var _loser_card_history_empty: Label = %LoserCardHistoryEmpty
@onready var _scripture_history_button: Button = %ScriptureHistoryButton
@onready var _scripture_history_unavailable: Label = %ScriptureHistoryUnavailable
@onready var _scripture_history: ScriptureHistoryView = %ScriptureHistoryView
@onready var _loser_card_history_button: Button = %LoserCardHistoryButton
@onready var _loser_card_history_unavailable: Label = %LoserCardHistoryUnavailable
@onready var _loser_card_history: LoserCardHistoryView = %LoserCardHistoryView
@onready var _continue_button: Button = %ContinueButton


# 隐藏结果及历史面板，连接查看、返回与继续请求。
func _ready() -> void:
	_overlay.hide()
	_scripture_history.hide()
	_loser_card_history.hide()
	_continue_button.pressed.connect(_on_continue_pressed)
	_scripture_history_button.pressed.connect(_on_scripture_history_requested)
	_scripture_history.back_requested.connect(_on_scripture_history_back_requested)
	_loser_card_history_button.pressed.connect(_on_loser_card_history_requested)
	_loser_card_history.back_requested.connect(_on_loser_card_history_back_requested)


# 场景离树时只取消待完成展示；子控件已离树，不能再访问 Viewport 或抢焦点。
func _exit_tree() -> void:
	_result_active = false
	_presentation_id += 1


# 保留未击破专用入口；没有周目数据时只显示本场说明。
func show_unbroken_result(session: RestSession) -> bool:
	if session == null or not session.is_open():
		return false
	var result_snapshot: Dictionary = session.get_result_snapshot()
	if String(result_snapshot.get("result_kind", "")) != "pk_win_unbroken":
		return false
	return show_result(session)


# 每次打开都只刷新已提交结果和历史；显示与隐藏页面不发奖、不触发继续请求。
func show_result(
		session: RestSession,
		run_data: SaveData = null,
		level_catalog: LevelCatalog = null,
		loser_card_catalog: LoserCardCatalog = null,
		wait_for_performance: bool = false
	) -> bool:
	if session == null or not session.is_open():
		return false
	var result_kind: String = String(session.get_result_snapshot().get("result_kind", ""))
	if run_data == null and result_kind != "pk_win_unbroken":
		return false
	if result_kind == "pk_win_unbroken":
		_result_title.text = "PK 胜利 · 矛盾未击破"
		_result_description.text = "你赢下了本场 PK，但未能确认真正的矛盾。\n本场没有神谕或击败奖励，仍可继续后续流程。"
	else:
		_result_title.text = "本场直播结束"
		_result_description.text = "本场结果已保存。"
	# 首次展示冻结真实数据；重复查看只读同一快照，粉丝提交仍归 PK 胜利入口。
	session.capture_live_result(run_data)
	_render_live_result(session.get_live_result_snapshot())

	var rewards: Dictionary = session.read_committed_rewards(run_data, level_catalog, loser_card_catalog)
	var new_assimilation: Dictionary = rewards["new_assimilation"]
	_new_rewards_empty.visible = (
		rewards["new_scripture_entry"] == null
		and rewards["new_loser_card"] == null
		and new_assimilation.is_empty()
	)
	_history_scripture = run_data.scripture_data if run_data != null else null
	_history_level_catalog = level_catalog
	_scripture_history_button.disabled = _history_scripture == null or _history_level_catalog == null
	_scripture_history_unavailable.visible = _scripture_history_button.disabled
	_history_loser_cards = run_data.loser_card_data if run_data != null else null
	_history_loser_card_catalog = loser_card_catalog
	# 目录缺失仍能查看已获 ID；只有缺少周目获卡数据才禁用入口。
	_loser_card_history_button.disabled = _history_loser_cards == null
	_loser_card_history_unavailable.visible = _loser_card_history_button.disabled
	# 缺少数据表示未知；真实历史集合为空时才显示对应空提示。
	_scripture_history_empty.visible = (
		_history_scripture != null and _history_level_catalog != null
		and _history_scripture.get_ordered_entries().is_empty()
	)
	_loser_card_history_empty.visible = (
		_history_loser_cards != null
		and _history_loser_cards.get_acquired_cards(loser_card_catalog).is_empty()
	)
	_history_empty_states.visible = _scripture_history_empty.visible or _loser_card_history_empty.visible
	# 环境只消费 17 已提交的主导倾向，不读取精确分数或本场暂存。
	var tendency_id: String = ""
	if run_data != null and run_data.tendency_state != null:
		tendency_id = run_data.tendency_state.get_primary_tendency_id()
	_room_environment.apply_tendency(tendency_id)
	_scripture_history.hide()
	_loser_card_history.hide()
	_overlay.show()
	_result_active = true
	_suspend_battle_aim()
	_presentation_id += 1
	_set_menu_input_enabled(false)
	# 当前为静态展示，布局完成后开放菜单；外部演出可显式报告结束。
	if not wait_for_performance:
		_finish_static_performance(_presentation_id)
	return true


# 缺失数据保持明确空态，零增量与未知增量分开显示。
func _render_live_result(result: Dictionary) -> void:
	if result.is_empty():
		_live_result.text = "本场直播数据暂不可用。"
		return
	var fan_delta: Variant = result["fan_delta"]
	var fan_change: String = "本场粉丝变化记录暂缺"
	if fan_delta != null:
		fan_change = "本场粉丝 +%d" % int(fan_delta)
	_live_result.text = "观看 %d · 点赞 %d · 评论 %d\n%s · 总粉丝 %d" % [
		int(result["viewer_count"]), int(result["like_count"]), int(result["comment_count"]),
		fan_change, int(result["fan_count"]),
	]


# 重开时同步收起结果与历史面板，释放本次上下文引用。
func hide_result() -> void:
	_result_active = false
	_restore_battle_aim()
	_presentation_id += 1
	_set_menu_input_enabled(false)
	_overlay.hide()
	_room_environment.apply_tendency("")
	_scripture_history.hide()
	_loser_card_history.hide()
	_history_scripture = null
	_history_level_catalog = null
	_history_loser_cards = null
	_history_loser_card_catalog = null


# 主动查看当前周目正式圣典，子面板复用现成章节适配与显示组件。
func _on_scripture_history_requested() -> void:
	if not _menu_input_enabled or _scripture_history_button.disabled:
		return
	_loser_card_history.hide()
	_scripture_history.show_history(_history_scripture, _history_level_catalog)
	_overlay.hide()


# 返回原休息面板并恢复可用按钮焦点，结果与继续信号保持原状态。
func _on_scripture_history_back_requested() -> void:
	if not _menu_input_enabled:
		return
	_scripture_history.hide()
	_overlay.show()
	if _scripture_history_button.disabled:
		_continue_button.grab_focus()
	else:
		_scripture_history_button.grab_focus()


# 主动查看已获卡片，允许档案缺失时展示正式读取接口保留的 ID。
func _on_loser_card_history_requested() -> void:
	if not _menu_input_enabled or _loser_card_history_button.disabled:
		return
	_scripture_history.hide()
	_loser_card_history.show_history(_history_loser_cards, _history_loser_card_catalog)
	_overlay.hide()


# 返回原结果面板，恢复败者卡入口焦点并保留既有继续行为。
func _on_loser_card_history_back_requested() -> void:
	if not _menu_input_enabled:
		return
	_loser_card_history.hide()
	_overlay.show()
	if _loser_card_history_button.disabled:
		_continue_button.grab_focus()
	else:
		_loser_card_history_button.grab_focus()


# 继续流程由外层组合方决定；路由完成前保留结果提示。
func _on_continue_pressed() -> void:
	if not _menu_input_enabled:
		return
	continue_requested.emit()


# 等待静态展示布局完成；关闭或重开后旧等待不能解锁新页面。
func _finish_static_performance(presentation_id: int) -> void:
	await get_tree().process_frame
	if presentation_id == _presentation_id:
		finish_result_performance()


# 演出拥有者报告完成，仅开放 Rest 菜单，战斗启停继续归外层场景。
func finish_result_performance() -> void:
	if not _result_active or _menu_input_enabled:
		return
	_set_menu_input_enabled(true)
	_continue_button.grab_focus()
	result_performance_finished.emit()


# 菜单同时受展示阶段与资料上下文约束。
func _set_menu_input_enabled(enabled: bool) -> void:
	_menu_input_enabled = enabled
	_continue_button.disabled = not enabled
	_scripture_history_button.disabled = not enabled or _history_scripture == null or _history_level_catalog == null
	_loser_card_history_button.disabled = not enabled or _history_loser_cards == null
	if not enabled:
		var focus_owner: Control = get_viewport().gui_get_focus_owner()
		if focus_owner != null:
			focus_owner.release_focus()


# 展示时拦截操作；菜单阶段让原生 GUI 完整接收点击、悬停与滚动。
func _input(_event: InputEvent) -> void:
	if _result_active and not _menu_input_enabled:
		get_viewport().set_input_as_handled()


# 外层注入准心，Rest 不依赖 Sandbox 内部节点路径；攻击仍由战斗所有者关闭。
func configure_battle_aim(aim: AimReticle) -> void:
	_restore_battle_aim()
	_battle_aim = aim
	if _result_active:
		_suspend_battle_aim()


# 进入休息时暂停准心事件，历史页仍可使用原生鼠标拖动滚动。
func _suspend_battle_aim() -> void:
	if not _aim_suspended and is_instance_valid(_battle_aim):
		_aim_input_was_enabled = _battle_aim.is_processing_input()
		_battle_aim.set_process_input(false)
		_aim_suspended = true


# 离开休息时恢复进入前的准心处理状态，攻击启停由外层独立决定。
func _restore_battle_aim() -> void:
	if _aim_suspended and is_instance_valid(_battle_aim):
		_battle_aim.set_process_input(_aim_input_was_enabled)
	_aim_suspended = false
