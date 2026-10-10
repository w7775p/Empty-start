class_name DivineDescentFlow
extends Node

signal entered(session: DivineDescentSession)
signal completed(result: EndingSession)

var _session: DivineDescentSession
var _mode: DivineDescentCombatMode
var _spread: DivineDescentSpread
var _result: EndingSession
var _catalog: LevelCatalog
var _area: BarrageArea
var _attack_input: AttackChargeInput
var _presentation: Dictionary
var _stopped: bool = false


# 一次终局使用同一冻结会话和战斗组件；entered 让根场景先收起普通阶段。
func start(
		run_data: SaveData, catalog: LevelCatalog, current_level: LevelProfile,
		tier_catalog: CombatStageTierCatalog, hit_resolution: HitResolution,
		combat_stage: CombatStage, contradiction_break: ContradictionBreakSystem,
		area: BarrageArea, opponent_pk_bar: OpponentPKBar, attack_input: AttackChargeInput,
		battle_config: SandboxBattleConfig, decay_config: DivineDescentDecayConfig,
		presentation: Dictionary
) -> bool:
	if not is_inside_tree() or _session != null or _stopped:
		return false
	if catalog == null or current_level == null or battle_config == null or not is_instance_valid(area) or not is_instance_valid(attack_input):
		return false
	var session := DivineDescentSession.new()
	if not session.enter(run_data):
		return false
	var mode := DivineDescentCombatMode.new()
	if not mode.enter_terminal_mode(tier_catalog, hit_resolution, combat_stage,
			contradiction_break, area, opponent_pk_bar):
		return false
	_session = session
	_mode = mode
	_catalog = catalog
	_area = area
	_attack_input = attack_input
	_presentation = presentation.duplicate(true)
	entered.emit(session)
	if _stopped or not is_inside_tree():
		return true
	# 空原始历史直接接收；延迟到根场景完成本次 Continue 回调后再转场。
	if session.should_enter_empty_ending():
		_complete.call_deferred(session)
		return true
	if float(_presentation.get("repeat_interval_seconds", 0.0)) <= 0.0 or float(_presentation.get("fade_seconds", 0.0)) <= 0.0 or float(_presentation.get("hold_seconds", 0.0)) <= 0.0:
		push_warning("DivineDescentFlow: 终局演出参数待交付，请显式注入配置。")
		return true
	_spread = DivineDescentSpread.new()
	add_child(_spread)
	_spread.completed.connect(_complete)
	_spread.convergence_started.connect(_on_convergence)
	_spread.bind_new_word_decay(mode)
	if not _spread.start(session, area, catalog, float(_presentation["repeat_interval_seconds"]),
			battle_config.repeat_lifetime_seconds, battle_config.repeat_display_template,
			null, _presentation.get("trait_colors", {})):
		push_error("DivineDescentFlow: 神降临扩散无法读取冻结历史候选。")
		return true
	if not area.start_normal_generation(current_level) or not mode.start_new_word_decay(decay_config):
		_spread.stop()
		push_error("DivineDescentFlow: 神降临新话衰减启动失败。")
	return true


# 根场景按游戏帧推进，暂停或完成后停止衰减。
func advance(delta: float) -> void:
	if _stopped or _result != null or _spread == null or not is_inside_tree() or get_tree().paused:
		return
	_mode.advance_new_word_decay(delta)


# 只处理左键和非重复空格；返回值让调用方只消费实际接受的表现输入。
func handle_input(event: InputEvent) -> bool:
	if _stopped or _result != null or _spread == null or not is_inside_tree() or get_tree().paused:
		return false
	var requested: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	requested = requested or (event is InputEventKey and event.keycode == KEY_SPACE and event.pressed and not event.echo)
	return requested and _spread.emphasize_locked_sentence(
		float(_presentation.get("input_scale", 0.0)), float(_presentation.get("input_return_seconds", 0.0)))


# 真实可见占比收束后沿用 DD-17 时长，完成仍由 Tween 通知。
func _on_convergence(_candidate: Dictionary) -> void:
	if not _stopped and not _spread.begin_full_screen_emphasis(
			float(_presentation["fade_seconds"]), float(_presentation["hold_seconds"])):
		push_error("DivineDescentFlow: 神降临全屏强调启动失败。")


# 同一会话仅接收一次 Ending；存盘和顶层切换交给根场景。
func _complete(session: DivineDescentSession) -> void:
	if _stopped or not is_inside_tree() or session != _session or _result != null:
		return
	if not session.should_enter_empty_ending() and (_spread == null or not _spread.is_completed()):
		return
	var result := EndingSession.new()
	if not result.receive_final_state(session, _catalog):
		push_error("DivineDescentFlow: Ending 拒绝终局固定结果。")
		return
	_result = result
	_attack_input.set_combat_active(false)
	_area.stop_normal_generation()
	if _spread != null:
		_spread.stop()
	completed.emit(result)


# 显式中止取消 Timer、Tween 和输入；中断及离树均不产生完成事实。
func stop() -> void:
	_stopped = true
	if is_instance_valid(_attack_input):
		_attack_input.set_combat_active(false)
	if is_instance_valid(_area):
		_area.stop_normal_generation()
	if is_instance_valid(_spread):
		_spread.stop()
		# 离树立即触发 DD-17 的 Tween 清理，避免中断后收到延迟 finished。
		remove_child(_spread)
		_spread.queue_free()
		_spread = null


# 销毁作为最终清理；调用方也可在换场请求前显式停止。
func _exit_tree() -> void:
	stop()


# 读取原会话引用，冻结快照仍由 Session 的公开接口提供副本。
func get_session() -> DivineDescentSession:
	return _session


# 读取当前模式，规则继续归原组件。
func get_combat_mode() -> DivineDescentCombatMode:
	return _mode


# 读取当前扩散状态，工作池继续归原组件。
func get_spread() -> DivineDescentSpread:
	return _spread


# null 表示尚未完成接收；有结果时返回已经接收的同一 Ending。
func get_result() -> EndingSession:
	return _result
