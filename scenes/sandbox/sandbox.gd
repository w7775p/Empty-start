extends Control

signal final_oracle_opened(session: FinalOracleSession)
signal rest_opened(session: RestSession)
signal rest_continue_requested(session: RestSession)
signal divine_descent_entered(session: DivineDescentSession)

const SAMPLE_TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const PRESENTATION_ASSETS: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const CONTRADICTION_WINDOW_CONFIG: ContradictionWindowConfig = preload("res://systems/contradiction_break/contradiction_window_config.tres")
const REST_RESULT_VIEW_SCENE: PackedScene = preload("res://ui/rest/rest_result_view.tscn")
# 关卡资料统一由目录提供，运行验证可注入独立临时目录。
@export var level_catalog: LevelCatalog = preload("res://data/level_configuration/level_catalog.tres")
@export var battle_config: SandboxBattleConfig = preload("res://data/sandbox/playable_battle_config.tres")
# 只从正式败者卡目录发卡；目录缺少资料时由 16 的写入接口拒绝。
@export var loser_card_catalog: LoserCardCatalog = preload("res://data/loser_card/loser_card_catalog.tres")
# 未批准的演出参数默认留空，仅由明确 TEST_ONLY 夹具或后续正式配置注入。
@export var divine_decay_config: DivineDescentDecayConfig = preload("res://data/divine_descent/divine_descent_decay_config.tres")
@export var divine_repeat_interval_seconds: float = 0.0
@export var divine_fade_seconds: float = 0.0
@export var divine_hold_seconds: float = 0.0
@export var divine_input_scale: float = 0.0
@export var divine_input_return_seconds: float = 0.0
@export var divine_trait_colors: Dictionary = {}

@onready var _barrage_area: BarrageArea = %BarrageArea
@onready var _aim_reticle: AimReticle = %AimReticle
@onready var _attack_charge_input: AttackChargeInput = %AttackChargeInput
@onready var _oracle_candidate_display: FinalOracleCandidateDisplay = %OracleCandidateDisplay
@onready var _battle_hud = %BattleHud
@onready var _debug_panel: CanvasLayer = %DebugPanel

var _run_state: LevelRunState
var _battle_attempt_flow: BattleAttemptFlow
var _rest_session: RestSession
var _rest_result_view: RestResultView
var _contradiction_oracle_flow: ContradictionOracleFlow
var _divine_descent_flow: DivineDescentFlow


# 场景只创建生命周期对象并接线；PK、Tier、倾向等状态留在各自所有者。
func _ready() -> void:
	# 直接运行场景时等待 Autoload 完成初始化，再创建周目并显式绑定已就绪的子 HUD。
	if SaveManager.data == null:
		SaveManager.new_game()
	%LiveDataHud.bind_live_session(SaveManager.data.live_session)
	# 敌方尚无数据所有者，本卡仅显式提供四个显示占位值。
	%OpponentLiveDataHud.set_values(0, 0, 0, 0)
	_run_state = LevelRunState.new(level_catalog)
	_contradiction_oracle_flow = ContradictionOracleFlow.new()
	add_child(_contradiction_oracle_flow)
	_contradiction_oracle_flow.state_text_changed.connect(_battle_hud.show_battle_state)
	_contradiction_oracle_flow.oracle_opened.connect(func(session): final_oracle_opened.emit(session))
	_contradiction_oracle_flow.rest_ready.connect(_on_rest_ready)
	var opponent_pk_bar := OpponentPKBar.new()
	opponent_pk_bar.name = "OpponentPKBar"
	add_child(opponent_pk_bar)
	_barrage_area.barrage_generated.connect(_on_barrage_generated)
	_attack_charge_input.configure_target_query(_aim_reticle, _barrage_area)
	_rest_result_view = REST_RESULT_VIEW_SCENE.instantiate() as RestResultView
	add_child(_rest_result_view)
	# 创建时注入一次准心，休息及历史页面统一冻结输入，隐藏时恢复。
	_rest_result_view.configure_battle_aim(_aim_reticle)
	_rest_result_view.continue_requested.connect(_on_rest_continue_requested)
	_battle_attempt_flow = BattleAttemptFlow.new()
	_battle_attempt_flow.name = "BattleAttemptFlow"
	add_child(_battle_attempt_flow)
	_battle_attempt_flow.attempt_started.connect(_on_attempt_started)
	_battle_attempt_flow.battle_state_changed.connect(_battle_hud.show_battle_state)
	_battle_attempt_flow.pk_feedback_changed.connect(_battle_hud.refresh_pk)
	_battle_attempt_flow.attempt_failed.connect(_on_attempt_failed)
	%RestartButton.pressed.connect(restart_current_attempt)
	%PauseMenu.restart_requested.connect(restart_current_attempt)
	_debug_panel.call("bind_sandbox", self)
	if not _battle_attempt_flow.configure(
			SaveManager.data, level_catalog, _run_state, battle_config, SAMPLE_TIER_CATALOG,
			_barrage_area, _aim_reticle, _attack_charge_input, opponent_pk_bar,
			_contradiction_oracle_flow, _oracle_candidate_display, loser_card_catalog,
			CONTRADICTION_WINDOW_CONFIG, AudioManager):
		push_error("Sandbox: 无法组合 BattleAttemptFlow。")
		return
	if not _battle_attempt_flow.start_first_attempt():
		push_error("Sandbox: 无法启动首场普通战斗。")


# 按当前关重建尝试；重开与切到下一关共用清理，保留此前周目成果。
func restart_current_attempt() -> void:
	# 已进入终局后不能通过普通重开入口恢复 PK、档位与矛盾规则。
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		return
	_contradiction_oracle_flow.stop()
	_rest_session = null
	_rest_result_view.hide_result()
	_attack_charge_input.set_contradiction_mode(false)
	%PauseMenu.resume_game()
	if not _battle_attempt_flow.restart_current_attempt():
		push_error("Sandbox: 无法重建当前战斗尝试。")


# 当前关的角色和素材由一次尝试启动事实提供；HUD 只呈现组合方状态。
func _on_attempt_started(current_level: LevelProfile, _hit: HitResolution, _stage: CombatStage, _queue: RepeatDelayQueue) -> void:
	_battle_hud.reset_for_attempt()
	var player_name: String = SaveManager.data.streamer_name
	_battle_hud.configure_streamers(player_name if not player_name.is_empty() else "玩家主播", current_level.streamer_name)
	_battle_hud.configure_streamer_assets(
		PRESENTATION_ASSETS.player_streamer_portrait,
		PRESENTATION_ASSETS.player_live_background,
		PRESENTATION_ASSETS.player_fan_badge,
		current_level.streamer_portrait,
		current_level.streamer_live_background,
		current_level.fan_badge_texture
	)

# 流程已回滚尝试状态并停止攻击；HUD 只负责显示失败界面。
func _on_attempt_failed(_level: LevelProfile, _loss_streak_count: int, _hit: HitResolution, _repeat_stats: RepeatGenerationStats) -> void:
	_battle_hud.show_failure()


# 暂停由 SceneTree 冻结此节点，复读等待只使用实际游戏帧时间。
func _process(delta: float) -> void:
	if _divine_descent_flow != null:
		_divine_descent_flow.advance(delta)
	# 直播上涨只推进表现数据；SceneTree 暂停时此帧回调也暂停。
	SaveManager.data.live_session.advance_short_boosts(delta)
	_battle_attempt_flow.advance(delta)
	_contradiction_oracle_flow.advance(delta)
	_battle_hud.refresh_attack(_attack_charge_input.get_charge_progress(), _attack_charge_input.get_attack_phase())


# DEBUG 面板每次刷新时从现有系统即时收集快照，不把可变业务值保存在 UI。
func get_debug_snapshot() -> Dictionary:
	if SaveManager.data == null or _run_state == null or _battle_attempt_flow == null:
		return {}
	var hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	var combat_stage: CombatStage = _battle_attempt_flow.get_combat_stage()
	if hit_resolution == null or combat_stage == null:
		return {}
	var current_level: LevelProfile = _battle_attempt_flow.get_current_level_profile()
	var live_session: LiveSessionData = SaveManager.data.live_session
	var tendency_state: TendencyState = SaveManager.data.tendency_state
	var barrage_counts: Dictionary = _barrage_area.get_current_barrage_counts()
	var battle_phase: String = "普通战斗中（NORMAL_COMBAT）" if _battle_attempt_flow.is_normal_combat_active() else "普通战斗未运行（INACTIVE）"
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		battle_phase = "神降临（DIVINE_DESCENT）"
	elif _contradiction_oracle_flow.is_contradiction_active():
		battle_phase = "矛盾击破（CONTRADICTION_BREAK）"
	elif _contradiction_oracle_flow.get_oracle_session() != null and _rest_session == null:
		battle_phase = "终结神谕（FINAL_ORACLE）"
	elif _rest_session != null and _rest_session.is_open():
		battle_phase = "休息时刻（REST）"
	elif hit_resolution.get_player_pk() >= battle_config.maximum_player_pk:
		battle_phase = "普通战斗完成（NORMAL_COMBAT_COMPLETE）"
	if get_tree().paused:
		battle_phase += " · 暂停中"
	return {
		"level": "第%d关" % current_level.level_order if current_level != null else "无关卡",
		"player_streamer": SaveManager.data.streamer_name if not SaveManager.data.streamer_name.is_empty() else "玩家主播",
		"opponent_streamer": current_level.streamer_name if current_level != null else "无对手",
		"battle_phase": battle_phase,
		"player_pk": hit_resolution.get_player_pk(),
		"tier": combat_stage.get_current_tier(),
		"attack_phase": _attack_charge_input.get_attack_phase(),
		"is_charging": _attack_charge_input.is_charge_held(),
		"normal_barrage_count": int(barrage_counts.get("normal", 0)),
		"repeat_barrage_count": int(barrage_counts.get("repeat", 0)),
		"normal_generation_enabled": _barrage_area.is_normal_generation_enabled(),
		"viewer_count": live_session.viewer_count,
		"like_count": live_session.like_count,
		"comment_count": live_session.comment_count,
		"fan_count": live_session.fan_count,
		"attempt_orthodox": tendency_state.attempt_orthodox_total,
		"attempt_heretical": tendency_state.attempt_heretical_total,
		"attempt_absurd": tendency_state.attempt_absurd_total,
	}


# F3 调试入口经 HitResolution 正式更新 PK，让 CombatStage 和 HUD 收到同一变化信号。
func debug_set_player_pk(player_pk: float) -> float:
	var hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	if hit_resolution == null:
		return 0.0
	return hit_resolution.set_player_pk_for_debug(player_pk)


# 直播调试值仍写入本场 LiveSessionData，由 Resource.changed 刷新当前 HUD。
func debug_set_live_data(viewer: int, likes: int, comments: int, fans: int) -> void:
	if SaveManager.data == null or SaveManager.data.live_session == null:
		return
	var live_session: LiveSessionData = SaveManager.data.live_session
	live_session.viewer_count = maxi(viewer, 0)
	live_session.like_count = maxi(likes, 0)
	live_session.comment_count = maxi(comments, 0)
	live_session.fan_count = maxi(fans, 0)


# 调试倾向只写当前关暂存值，不碰已提交的周目累计。
func debug_set_attempt_tendencies(orthodox: int, heretical: int, absurd: int) -> void:
	if SaveManager.data == null or SaveManager.data.tendency_state == null:
		return
	SaveManager.data.tendency_state.set_attempt_tendencies_for_debug(orthodox, heretical, absurd)


# 清空当前画面弹幕并取消尚未出现的复读请求，但保留普通生成开关状态。
func debug_clear_barrages() -> void:
	_barrage_area.clear_current_barrages()
	_battle_attempt_flow.clear_pending_normal_repeats()


# 使用当前关卡和 Tier 参数立即生成一批普通弹幕。
func debug_spawn_normal_batch() -> int:
	return _barrage_area.spawn_normal_batch_now()


# DEBUG 操作只切换 BarrageArea 的真实普通生成状态。
func debug_set_normal_generation_enabled(enabled: bool) -> bool:
	if enabled:
		return _barrage_area.resume_normal_generation()
	_barrage_area.stop_normal_generation()
	return true


# 流程已经提交成果并准备好 Rest；根场景只展示同一结果对象。
func _on_rest_ready(result: RestSession) -> void:
	_rest_session = result
	if not _rest_result_view.show_result(result, SaveManager.data, level_catalog, loser_card_catalog):
		push_error("Sandbox: 无法显示本场 Rest 结果。")
		return
	rest_opened.emit(result)


# 继续请求使用本场结果 ID 推进；仅下一普通关路线重建当前场景的尝试。
func _on_rest_continue_requested() -> void:
	if _rest_session == null or not _rest_session.is_open():
		return
	var finished_session: RestSession = _rest_session
	var completion: LevelRunState.CompletionResult = finished_session.continue_to_next_level(_run_state)
	if completion == LevelRunState.CompletionResult.ADVANCED:
		# 撤回旧关未提交暂存，已保存经文、卡片、吞并和粉丝继续使用同一 SaveData。
		var finished_level_id := StringName(str(finished_session.get_result_snapshot().get("level_id", "")))
		SaveManager.data.scripture_data.rollback_uncommitted(finished_level_id)
		_battle_attempt_flow.complete_current_level()
		restart_current_attempt()
	elif completion == LevelRunState.CompletionResult.ALL_NORMAL_LEVELS_COMPLETED:
		_enter_divine_descent()
	else:
		return
	rest_continue_requested.emit(finished_session)


# 末关只发起独立终局流程，战斗事实和演出由组件持有。
func _enter_divine_descent() -> void:
	if _divine_descent_flow != null or not _run_state.is_all_normal_levels_completed():
		return
	_divine_descent_flow = DivineDescentFlow.new()
	add_child(_divine_descent_flow)
	_divine_descent_flow.entered.connect(_on_divine_descent_entered)
	_divine_descent_flow.completed.connect(_finish_divine_descent)
	var attempt_hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	var attempt_stage: CombatStage = _battle_attempt_flow.get_combat_stage()
	var attempt_opponent: OpponentPKBar = _battle_attempt_flow.get_opponent_pk_bar()
	if not _divine_descent_flow.start(
			SaveManager.data, level_catalog, _run_state.get_current_level_profile(),
			SAMPLE_TIER_CATALOG, attempt_hit_resolution, attempt_stage, _contradiction_oracle_flow.get_contradiction_system(),
			_barrage_area, attempt_opponent, _attack_charge_input, battle_config, divine_decay_config,
			{
				"repeat_interval_seconds": divine_repeat_interval_seconds,
				"fade_seconds": divine_fade_seconds, "hold_seconds": divine_hold_seconds,
				"input_scale": divine_input_scale, "input_return_seconds": divine_input_return_seconds,
				"trait_colors": divine_trait_colors,
			}):
		_divine_descent_flow.queue_free()
		_divine_descent_flow = null
		push_error("Sandbox: 无法启动神降临流程。")


# 根场景收起普通、神谕和休息阶段，再通知外部终局已经进入。
func _on_divine_descent_entered(session: DivineDescentSession) -> void:
	_battle_attempt_flow.stop()
	_contradiction_oracle_flow.stop()
	_rest_result_view.hide_result()
	_rest_session = null
	_battle_hud.show_battle_state("神降临")
	divine_descent_entered.emit(session)


# 完成信号已经携带接收结果；根场景只存盘并请求顶层路由。
func _finish_divine_descent(result: EndingSession) -> void:
	if not is_inside_tree():
		return
	# 同一真实存档保留已提交倾向与奖励；写盘失败必须留下明确证据。
	if SaveManager.save_game() != OK:
		push_error("Sandbox: 终局成果存盘失败。")
	var error := SceneRouter.goto_ending(result)
	if error != OK:
		push_error("Sandbox: Ending 顶层路由失败：%s" % error_string(error))


# 根场景只消费流程实际接受的终局输入。
func _input(event: InputEvent) -> void:
	if _divine_descent_flow != null and _divine_descent_flow.handle_input(event):
		get_viewport().set_input_as_handled()


# 联调和后续普通战斗流程通过公开入口读取阶段与 Rest 结果。
func get_contradiction_oracle_flow() -> ContradictionOracleFlow:
	return _contradiction_oracle_flow


# 普通战斗与后续阶段通过此入口订阅同一尝试流程。
func get_battle_attempt_flow() -> BattleAttemptFlow:
	return _battle_attempt_flow


# Rest 页面验收与结果展示共用同一视图实例。
func get_rest_result_view() -> RestResultView:
	return _rest_result_view


# 终局读取同一流程对象。
func get_divine_descent_flow() -> DivineDescentFlow:
	return _divine_descent_flow


# 普通与复读都由同一生成事实计评论，等待请求和失败生成不提前入账。
func _on_barrage_generated(_view: BarrageView) -> void:
	SaveManager.data.live_session.record_generated_comments(1)


# 离开验收场时撤销尚未提交的本场倾向，已有周目成果由 SaveData 保留。
func _exit_tree() -> void:
	if _contradiction_oracle_flow != null:
		_contradiction_oracle_flow.stop()
	if _divine_descent_flow != null:
		_divine_descent_flow.stop()
	if is_instance_valid(_battle_attempt_flow):
		_battle_attempt_flow.stop()
	if SaveManager.data != null:
		SaveManager.data.tendency_state.rollback_attempt_tendency()
