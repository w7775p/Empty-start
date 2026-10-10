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

var _hit_resolution: HitResolution
var _combat_stage: CombatStage
var _opponent_pk_bar: OpponentPKBar
var _repeat_queue: RepeatDelayQueue
var _run_state: LevelRunState
var _normal_combat_active: bool = false
var _rest_session: RestSession
var _rest_result_view: RestResultView
var _opening_fan_count: int = 0
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
	_opening_fan_count = SaveManager.data.live_session.fan_count
	_opponent_pk_bar = OpponentPKBar.new()
	_opponent_pk_bar.name = "OpponentPKBar"
	add_child(_opponent_pk_bar)
	_opponent_pk_bar.attempt_failed.connect(_on_attempt_failed)
	_barrage_area.barrage_generated.connect(_on_barrage_generated)
	_attack_charge_input.shot_hit_resolution_submitted.connect(_on_shot_hit_resolution_submitted)
	_attack_charge_input.configure_target_query(_aim_reticle, _barrage_area)
	_rest_result_view = REST_RESULT_VIEW_SCENE.instantiate() as RestResultView
	add_child(_rest_result_view)
	# 创建时注入一次准心，休息及历史页面统一冻结输入，隐藏时恢复。
	_rest_result_view.configure_battle_aim(_aim_reticle)
	_rest_result_view.continue_requested.connect(_on_rest_continue_requested)
	%RestartButton.pressed.connect(restart_current_attempt)
	%PauseMenu.restart_requested.connect(restart_current_attempt)
	_debug_panel.call("bind_sandbox", self)
	restart_current_attempt()


# 按当前关重建尝试；重开与切到下一关共用清理，保留此前周目成果。
func restart_current_attempt() -> void:
	# 已进入终局后不能通过普通重开入口恢复 PK、档位与矛盾规则。
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		return
	var restarting_level: LevelProfile = _run_state.get_current_level_profile()
	if restarting_level != null:
		SaveManager.data.scripture_data.rollback_uncommitted(StringName(restarting_level.level_id))
	if _hit_resolution != null:
		_hit_resolution.discard_uncommitted_normal_hit_history()
	if _repeat_queue != null:
		_repeat_queue.get_generation_stats().discard_uncommitted_normal_repeat_history()
	_stop_normal_combat()
	_contradiction_oracle_flow.stop()
	_rest_session = null
	_rest_result_view.hide_result()
	_attack_charge_input.set_contradiction_mode(false)
	%PauseMenu.resume_game()
	_opponent_pk_bar.reset_current_attempt()
	SaveManager.data.tendency_state.rollback_attempt_tendency()
	SaveManager.data.live_session.initialize_session(_opening_fan_count)
	_hit_resolution = HitResolution.new(
		battle_config.initial_player_pk,
		battle_config.minimum_player_pk,
		battle_config.maximum_player_pk
	)
	_repeat_queue = RepeatDelayQueue.new(battle_config.maximum_pending_repeat_count)
	_combat_stage = CombatStage.new(SAMPLE_TIER_CATALOG)
	# Tier 的同步回调必须先于场景读取结果，复读计划才能使用整发结算后的档位。
	_combat_stage.bind_hit_resolution(_hit_resolution)
	_combat_stage.bind_barrage_area(_barrage_area)
	_combat_stage.bind_opponent_pk_bar(_opponent_pk_bar)
	_combat_stage.bind_audio_manager(AudioManager)
	_combat_stage.tier_state_changed.connect(_on_tier_state_changed)
	_hit_resolution.final_player_pk_updated.connect(_on_final_player_pk_updated)
	_barrage_area.base_lifetime_seconds = battle_config.normal_lifetime_seconds
	_barrage_area.repeat_barrage_screen_cap = battle_config.repeat_screen_cap
	_battle_hud.reset_for_attempt()
	_combat_stage.begin_combat()
	var current_level: LevelProfile = _run_state.get_current_level_profile()
	if current_level == null:
		_battle_hud.show_battle_state("当前没有关卡配置")
		return
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
	if not _attack_charge_input.configure_attack_timing(battle_config.attack_timing):
		push_error("Sandbox: 攻击时长配置无效。")
		return
	if not _attack_charge_input.configure_hit_resolution(_hit_resolution):
		push_error("Sandbox: 无法接入本场命中结算。")
		return
	_normal_combat_active = true
	_attack_charge_input.set_combat_active(true)
	if not _barrage_area.start_normal_generation(current_level):
		_stop_normal_combat()
		push_error("Sandbox: 无法启动普通弹幕生成。")
		return
	_opponent_pk_bar.start_pullback(_hit_resolution, battle_config.base_pullback_speed)
	_refresh_pk_feedback()


# 暂停由 SceneTree 冻结此节点，复读等待只使用实际游戏帧时间。
func _process(delta: float) -> void:
	if _divine_descent_flow != null:
		_divine_descent_flow.advance(delta)
	# 直播上涨只推进表现数据；SceneTree 暂停时此帧回调也暂停。
	SaveManager.data.live_session.advance_short_boosts(delta)
	# 普通复读仍归战斗；满值后的矛盾复读和选择计时交给流程。
	if _normal_combat_active and _hit_resolution.allows_normal_pk_resolution():
		_repeat_queue.advance_and_dispatch(delta, _barrage_area)
	_contradiction_oracle_flow.advance(delta)
	_battle_hud.refresh_attack(_attack_charge_input.get_charge_progress(), _attack_charge_input.get_attack_phase())


# DEBUG 面板每次刷新时从现有系统即时收集快照，不把可变业务值保存在 UI。
func get_debug_snapshot() -> Dictionary:
	if SaveManager.data == null or _run_state == null or _hit_resolution == null or _combat_stage == null:
		return {}
	var current_level: LevelProfile = _run_state.get_current_level_profile()
	var live_session: LiveSessionData = SaveManager.data.live_session
	var tendency_state: TendencyState = SaveManager.data.tendency_state
	var barrage_counts: Dictionary = _barrage_area.get_current_barrage_counts()
	var battle_phase: String = "普通战斗中（NORMAL_COMBAT）" if _normal_combat_active else "普通战斗未运行（INACTIVE）"
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		battle_phase = "神降临（DIVINE_DESCENT）"
	elif _contradiction_oracle_flow.is_contradiction_active():
		battle_phase = "矛盾击破（CONTRADICTION_BREAK）"
	elif _contradiction_oracle_flow.get_oracle_session() != null and _rest_session == null:
		battle_phase = "终结神谕（FINAL_ORACLE）"
	elif _rest_session != null and _rest_session.is_open():
		battle_phase = "休息时刻（REST）"
	elif _hit_resolution.get_player_pk() >= battle_config.maximum_player_pk:
		battle_phase = "普通战斗完成（NORMAL_COMBAT_COMPLETE）"
	if get_tree().paused:
		battle_phase += " · 暂停中"
	return {
		"level": "第%d关" % current_level.level_order if current_level != null else "无关卡",
		"player_streamer": SaveManager.data.streamer_name if not SaveManager.data.streamer_name.is_empty() else "玩家主播",
		"opponent_streamer": current_level.streamer_name if current_level != null else "无对手",
		"battle_phase": battle_phase,
		"player_pk": _hit_resolution.get_player_pk(),
		"tier": _combat_stage.get_current_tier(),
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
	if _hit_resolution == null:
		return 0.0
	return _hit_resolution.set_player_pk_for_debug(player_pk)


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
	if _repeat_queue != null:
		_repeat_queue.clear_normal_queue()


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
		_opponent_pk_bar.complete_current_level()
		_opening_fan_count = SaveManager.data.live_session.fan_count
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
	if not _divine_descent_flow.start(
			SaveManager.data, level_catalog, _run_state.get_current_level_profile(),
			SAMPLE_TIER_CATALOG, _hit_resolution, _combat_stage, _contradiction_oracle_flow.get_contradiction_system(),
			_barrage_area, _opponent_pk_bar, _attack_charge_input, battle_config, divine_decay_config,
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
	_stop_normal_combat()
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


# 终局读取同一流程对象。
func get_divine_descent_flow() -> DivineDescentFlow:
	return _divine_descent_flow


# 普通与复读都由同一生成事实计评论，等待请求和失败生成不提前入账。
func _on_barrage_generated(_view: BarrageView) -> void:
	SaveManager.data.live_session.record_generated_comments(1)


# 完成整发结算后协调移除、倾向和复读，收益继续读取 HitResolution 的逐目标结果。
func _on_shot_hit_resolution_submitted(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	if not _normal_combat_active:
		return
	var result: Dictionary = submission.get("hit_resolution_result", {})
	if bool(result.get("cancelled_by_zero_pk", false)):
		return
	var normal_hit_count: int = 0
	var repeat_hit_count: int = 0
	for target_result: Dictionary in result.get("target_results", []):
		var trait_result := target_result.get("trait_result") as BarrageTraitResult
		if trait_result == null:
			continue
		# 只有遮挡未命中的目标留场；其余到达结果结束实例，收益由结算结果独立决定。
		if trait_result.kind != BarrageTraitResult.Kind.OCCLUSION:
			_barrage_area.end_barrage(int(target_result.get("target_instance_id", -1)))
		if not bool(target_result.get("is_valid_hit", false)) or not trait_result.receives_normal_reward:
			continue
		if bool(target_result.get("is_repeat", false)):
			repeat_hit_count += 1
			continue
		normal_hit_count += 1
		SaveManager.data.tendency_state.record_normal_speech_tendency(
			str(target_result.get("tendency_id", "")), int(target_result.get("tendency_delta", 0))
		)
		var plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
			StringName(target_result.get("original_sentence_id", "")),
			str(target_result.get("original_sentence_text", "")),
			_combat_stage.get_current_tier(),
			_combat_stage.get_current_repeat_count_per_hit(),
			battle_config.repeat_lifetime_seconds,
			str(target_result.get("tendency_id", ""))
		)
		plan.apply_display_template(battle_config.repeat_display_template)
		_repeat_queue.enqueue_plan(plan)
	if normal_hit_count > 0:
		_battle_hud.show_battle_state("命中 %d 条 · PK +%.2f%% · 等待复读" % [normal_hit_count, float(result.get("total_pk_delta", 0.0)) * 100.0])
	elif repeat_hit_count > 0:
		_battle_hud.show_battle_state("复读命中 %d 条 · 零收益" % repeat_hit_count)
	else:
		_battle_hud.show_battle_state("未命中有效话语")
	if _hit_resolution.get_player_pk() >= battle_config.maximum_player_pk:
		_complete_normal_combat()


# 满值先立刻停回拉和生成；攻击提交完本发事实后统一停止输入和清理。
func _on_final_player_pk_updated(player_pk: float) -> void:
	_refresh_pk_feedback()
	if _normal_combat_active and _combat_stage.get_stage_result(player_pk, battle_config.maximum_player_pk) == CombatStage.StageResult.ENTER_CONTRADICTION:
		# 满值立即冻结，避免延迟切换前的扣分或旧普通结算改低 PK。
		_hit_resolution.set_normal_pk_resolution_enabled(false)
		_opponent_pk_bar.stop_pullback()
		_barrage_area.stop_normal_generation()
		_complete_normal_combat.call_deferred()


# 档位反馈读取系统当前值，UI 不保存第二份可写 Tier。
func _on_tier_state_changed(_current_tier: int) -> void:
	_refresh_pk_feedback()


# 对手份额由玩家唯一 PK 即时派生，所有 PK 修改都留在 HitResolution。
func _refresh_pk_feedback() -> void:
	_battle_hud.refresh_pk(_hit_resolution.get_player_pk(), _combat_stage.get_current_tier())


# 失败只执行一次，回滚本场暂存后开放当前关重开。
func _on_attempt_failed() -> void:
	if not _normal_combat_active:
		return
	_opponent_pk_bar.record_current_level_failure()
	_stop_normal_combat()
	_hit_resolution.discard_uncommitted_normal_hit_history()
	_repeat_queue.get_generation_stats().discard_uncommitted_normal_repeat_history()
	SaveManager.data.tendency_state.rollback_attempt_tendency()
	_battle_hud.show_failure()


# 普通 PK 满后读取本关矛盾内容，并以 Paradox 专属数值启动生成。
func _complete_normal_combat() -> void:
	if not _normal_combat_active or _hit_resolution.get_player_pk() < battle_config.maximum_player_pk:
		return
	_stop_normal_combat()
	var current_level: LevelProfile = _run_state.get_current_level_profile()
	# PK 胜利已经成立，先提交普通复读；后续击破或神谕分支不再次提交。
	if current_level != null:
		# 粉丝由直播数据按周目和关卡去重，矛盾结果与重复打开均不再次加粉。
		SaveManager.data.live_session.commit_pk_win_fans(
			StringName(current_level.level_id), battle_config.pk_win_fan_gain
		)
		# 已入账粉丝成为重开基数，防止重放已胜利关卡时回退已保存的增长。
		_opening_fan_count = SaveManager.data.live_session.fan_count
		_repeat_queue.get_generation_stats().commit_normal_repeat_history(
			SaveManager.data, StringName(current_level.level_id)
		)
	if not _contradiction_oracle_flow.start(
			SaveManager.data, level_catalog, current_level, _hit_resolution, _combat_stage,
			_barrage_area, _opponent_pk_bar, _attack_charge_input, _repeat_queue,
			_oracle_candidate_display, battle_config, loser_card_catalog,
			CONTRADICTION_WINDOW_CONFIG, AudioManager):
		push_error("Sandbox: 无法启动矛盾/神谕流程。")


# 阶段结束显式停止系统，避免旧输入或等待请求在下一次尝试继续推进。
func _stop_normal_combat() -> void:
	_normal_combat_active = false
	_attack_charge_input.set_combat_active(false)
	_barrage_area.stop_normal_generation()
	_barrage_area.clear_barrages()
	if _opponent_pk_bar != null:
		_opponent_pk_bar.stop_pullback()
	if _repeat_queue != null:
		_repeat_queue.clear_normal_queue()


# 离开验收场时撤销尚未提交的本场倾向，已有周目成果由 SaveData 保留。
func _exit_tree() -> void:
	if _contradiction_oracle_flow != null:
		_contradiction_oracle_flow.stop()
	if _divine_descent_flow != null:
		_divine_descent_flow.stop()
	if is_instance_valid(_attack_charge_input):
		_attack_charge_input.set_combat_active(false)
	if SaveManager.data != null:
		SaveManager.data.tendency_state.rollback_attempt_tendency()
