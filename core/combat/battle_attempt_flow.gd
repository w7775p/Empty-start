class_name BattleAttemptFlow
extends Node

signal attempt_started(level: LevelProfile, hit_resolution: HitResolution, combat_stage: CombatStage, repeat_queue: RepeatDelayQueue)
signal attempt_restarted(level: LevelProfile, hit_resolution: HitResolution, combat_stage: CombatStage, repeat_queue: RepeatDelayQueue)
signal shot_resolved(snapshot: AttackTargetSnapshot, submission: Dictionary, current_tier: int, repeat_stats: RepeatGenerationStats)
signal tier_changed(current_tier: int, player_pk: float)
signal pk_feedback_changed(player_pk: float, current_tier: int)
signal battle_state_changed(text: String)
signal attempt_failed(level: LevelProfile, loss_streak_count: int, hit_resolution: HitResolution, repeat_stats: RepeatGenerationStats)
signal pk_maximum_reached(level: LevelProfile, hit_resolution: HitResolution, repeat_stats: RepeatGenerationStats)
signal normal_combat_completed(level: LevelProfile, hit_resolution: HitResolution, repeat_stats: RepeatGenerationStats)
signal contradiction_entered(level: LevelProfile, hit_resolution: HitResolution, repeat_stats: RepeatGenerationStats)

var _run_data: SaveData
var _level_catalog: LevelCatalog
var _run_state: LevelRunState
var _battle_config: SandboxBattleConfig
var _tier_catalog: CombatStageTierCatalog
var _barrage_area: BarrageArea
var _aim_reticle: AimReticle
var _attack_input: AttackChargeInput
var _opponent_pk_bar: OpponentPKBar
var _contradiction_flow: ContradictionOracleFlow
var _oracle_candidate_display: FinalOracleCandidateDisplay
var _loser_card_catalog: LoserCardCatalog
var _contradiction_window_config: ContradictionWindowConfig
var _audio_manager: Node

var _hit_resolution: HitResolution
var _combat_stage: CombatStage
var _repeat_queue: RepeatDelayQueue
var _opening_fan_count: int = 0
var _is_configured: bool = false
var _normal_combat_active: bool = false
var _normal_completion_pending: bool = false


# 组合本场已有系统；PK、Tier、复读统计继续由各自对象持有。
func configure(
	run_data: SaveData,
	level_catalog: LevelCatalog,
	run_state: LevelRunState,
	battle_config: SandboxBattleConfig,
	tier_catalog: CombatStageTierCatalog,
	barrage_area: BarrageArea,
	aim_reticle: AimReticle,
	attack_input: AttackChargeInput,
	opponent_pk_bar: OpponentPKBar,
	contradiction_flow: ContradictionOracleFlow,
	oracle_candidate_display: FinalOracleCandidateDisplay,
	loser_card_catalog: LoserCardCatalog,
	contradiction_window_config: ContradictionWindowConfig,
	audio_manager: Node
) -> bool:
	if _is_configured or not is_inside_tree():
		return false
	if run_data == null or level_catalog == null or run_state == null or battle_config == null or tier_catalog == null:
		return false
	if not is_instance_valid(barrage_area) or not is_instance_valid(aim_reticle) or not is_instance_valid(attack_input):
		return false
	if not is_instance_valid(opponent_pk_bar) or not is_instance_valid(contradiction_flow):
		return false
	if not is_instance_valid(oracle_candidate_display) or not is_instance_valid(audio_manager) or contradiction_window_config == null:
		return false

	_run_data = run_data
	_level_catalog = level_catalog
	_run_state = run_state
	_battle_config = battle_config
	_tier_catalog = tier_catalog
	_barrage_area = barrage_area
	_aim_reticle = aim_reticle
	_attack_input = attack_input
	_opponent_pk_bar = opponent_pk_bar
	_contradiction_flow = contradiction_flow
	_oracle_candidate_display = oracle_candidate_display
	_loser_card_catalog = loser_card_catalog
	_contradiction_window_config = contradiction_window_config
	_audio_manager = audio_manager
	_opening_fan_count = run_data.live_session.fan_count
	_opponent_pk_bar.attempt_failed.connect(_on_attempt_failed)
	_attack_input.shot_hit_resolution_submitted.connect(_on_shot_hit_resolution_submitted)
	_is_configured = true
	return true


# 新 Sandbox 首次进入时创建并启动本关尝试。
func start_first_attempt() -> bool:
	if not _is_configured:
		return false
	return _start_attempt(false)


# 失败重开或 Rest 下一关共用重建顺序；已提交周目成果由各系统保留。
func restart_current_attempt() -> bool:
	if not _is_configured:
		return false
	return _start_attempt(true)


func _start_attempt(is_restart: bool) -> bool:
	var restarting_level: LevelProfile = get_current_level_profile()
	if restarting_level != null:
		_run_data.scripture_data.rollback_uncommitted(StringName(restarting_level.level_id))
	if _hit_resolution != null:
		_hit_resolution.discard_uncommitted_normal_hit_history()
	if _repeat_queue != null:
		_repeat_queue.get_generation_stats().discard_uncommitted_normal_repeat_history()
	_stop_normal_combat()
	_opponent_pk_bar.reset_current_attempt()
	_run_data.tendency_state.rollback_attempt_tendency()
	_run_data.live_session.initialize_session(_opening_fan_count)
	_normal_completion_pending = false

	_hit_resolution = HitResolution.new(
		_battle_config.initial_player_pk,
		_battle_config.minimum_player_pk,
		_battle_config.maximum_player_pk
	)
	_repeat_queue = RepeatDelayQueue.new(_battle_config.maximum_pending_repeat_count)
	_combat_stage = CombatStage.new(_tier_catalog)
	# Tier 先绑定 PK，再连接本流程；本发回调会读到已经更新的 Tier。
	_combat_stage.bind_hit_resolution(_hit_resolution)
	_combat_stage.bind_barrage_area(_barrage_area)
	_combat_stage.bind_opponent_pk_bar(_opponent_pk_bar)
	_combat_stage.bind_audio_manager(_audio_manager)
	_combat_stage.tier_state_changed.connect(_on_tier_state_changed.bind(_combat_stage))
	_hit_resolution.final_player_pk_updated.connect(_on_final_player_pk_updated.bind(_hit_resolution))
	_barrage_area.base_lifetime_seconds = _battle_config.normal_lifetime_seconds
	_barrage_area.repeat_barrage_screen_cap = _battle_config.repeat_screen_cap
	_combat_stage.begin_combat()

	var current_level: LevelProfile = get_current_level_profile()
	if current_level == null:
		battle_state_changed.emit("当前没有关卡配置")
		return false
	if not _attack_input.configure_attack_timing(_battle_config.attack_timing):
		push_error("BattleAttemptFlow: 攻击时长配置无效。")
		return false
	if not _attack_input.configure_hit_resolution(_hit_resolution):
		push_error("BattleAttemptFlow: 无法接入本场命中结算。")
		return false

	_normal_combat_active = true
	_attack_input.set_contradiction_mode(false)
	_attack_input.set_combat_active(true)
	if not _barrage_area.start_normal_generation(current_level):
		_stop_normal_combat()
		push_error("BattleAttemptFlow: 无法启动普通弹幕生成。")
		return false
	_opponent_pk_bar.start_pullback(_hit_resolution, _battle_config.base_pullback_speed)
	_refresh_pk_feedback()
	attempt_started.emit(current_level, _hit_resolution, _combat_stage, _repeat_queue)
	if is_restart:
		attempt_restarted.emit(current_level, _hit_resolution, _combat_stage, _repeat_queue)
	return true


# 暂停沿用 SceneTree；此入口只在普通战斗活动时推进普通复读。
func advance(delta: float) -> void:
	if _normal_combat_active and _hit_resolution != null and _hit_resolution.allows_normal_pk_resolution():
		_repeat_queue.advance_and_dispatch(delta, _barrage_area)


# 供阶段切换先清理旧复读请求，再按需清除当前可见弹幕。
func clear_pending_normal_repeats() -> int:
	return _repeat_queue.clear_normal_queue() if _repeat_queue != null else 0


func clear_barrages_for_stage_transition() -> void:
	if is_instance_valid(_barrage_area):
		_barrage_area.clear_barrages()


func complete_current_level() -> void:
	if is_instance_valid(_opponent_pk_bar):
		_opponent_pk_bar.complete_current_level()


# 明确结束普通尝试并清除仍在等待的普通复读。
func stop() -> void:
	_stop_normal_combat()


func _stop_normal_combat() -> void:
	_normal_combat_active = false
	if is_instance_valid(_attack_input):
		_attack_input.set_combat_active(false)
	if is_instance_valid(_barrage_area):
		_barrage_area.stop_normal_generation()
		_barrage_area.clear_barrages()
	if is_instance_valid(_opponent_pk_bar):
		_opponent_pk_bar.stop_pullback()
	if _repeat_queue != null:
		_repeat_queue.clear_normal_queue()


# PK 归零只回滚本场暂存；既有周目历史与收藏仍由原数据所有者保存。
func _on_attempt_failed() -> void:
	if not _normal_combat_active:
		return
	var failed_level: LevelProfile = get_current_level_profile()
	var loss_streak_count: int = _opponent_pk_bar.record_current_level_failure()
	_stop_normal_combat()
	_hit_resolution.discard_uncommitted_normal_hit_history()
	_repeat_queue.get_generation_stats().discard_uncommitted_normal_repeat_history()
	_run_data.tendency_state.rollback_attempt_tendency()
	if failed_level != null:
		battle_state_changed.emit("本关挑战失败，请重开")
	attempt_failed.emit(failed_level, loss_streak_count, _hit_resolution, _repeat_queue.get_generation_stats())


# 命中信号到达时，HitResolution 和 CombatStage 已完成本发唯一结算。
func _on_shot_hit_resolution_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
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
		# 遮挡命中保留原目标，其余已到达目标沿用弹幕系统的结束入口。
		if trait_result.kind != BarrageTraitResult.Kind.OCCLUSION:
			_barrage_area.end_barrage(int(target_result.get("target_instance_id", -1)))
		if not bool(target_result.get("is_valid_hit", false)) or not trait_result.receives_normal_reward:
			continue
		if bool(target_result.get("is_repeat", false)):
			repeat_hit_count += 1
			continue
		normal_hit_count += 1
		_run_data.tendency_state.record_normal_speech_tendency(
			str(target_result.get("tendency_id", "")), int(target_result.get("tendency_delta", 0))
		)
		var plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
			StringName(target_result.get("original_sentence_id", "")),
			str(target_result.get("original_sentence_text", "")),
			_combat_stage.get_current_tier(),
			_combat_stage.get_current_repeat_count_per_hit(),
			_battle_config.repeat_lifetime_seconds,
			str(target_result.get("tendency_id", ""))
		)
		plan.apply_display_template(_battle_config.repeat_display_template)
		_repeat_queue.enqueue_plan(plan)
	if normal_hit_count > 0:
		battle_state_changed.emit("命中 %d 条 · PK +%.2f%% · 等待复读" % [normal_hit_count, float(result.get("total_pk_delta", 0.0)) * 100.0])
	elif repeat_hit_count > 0:
		battle_state_changed.emit("复读命中 %d 条 · 零收益" % repeat_hit_count)
	else:
		battle_state_changed.emit("未命中有效话语")
	shot_resolved.emit(snapshot, submission.duplicate(true), _combat_stage.get_current_tier(), _repeat_queue.get_generation_stats())
	if _hit_resolution.get_player_pk() >= _battle_config.maximum_player_pk:
		_complete_normal_combat(_hit_resolution)


# 满值立即冻结回拉和普通生成；延迟到整发回调之后再切换矛盾阶段。
func _on_final_player_pk_updated(player_pk: float, source_hit_resolution: HitResolution) -> void:
	if source_hit_resolution != _hit_resolution:
		return
	_refresh_pk_feedback()
	if (_normal_combat_active and not _normal_completion_pending
			and _combat_stage.get_stage_result(player_pk, _battle_config.maximum_player_pk) == CombatStage.StageResult.ENTER_CONTRADICTION):
		_hit_resolution.set_normal_pk_resolution_enabled(false)
		_opponent_pk_bar.stop_pullback()
		_barrage_area.stop_normal_generation()
		_normal_completion_pending = true
		_complete_normal_combat.call_deferred(source_hit_resolution)


func _on_tier_state_changed(current_tier: int, source_stage: CombatStage) -> void:
	if source_stage != _combat_stage:
		return
	_refresh_pk_feedback()
	tier_changed.emit(current_tier, _hit_resolution.get_player_pk())


func _refresh_pk_feedback() -> void:
	if _hit_resolution != null and _combat_stage != null:
		pk_feedback_changed.emit(_hit_resolution.get_player_pk(), _combat_stage.get_current_tier())


# 普通 PK 胜利先停掉尝试、保存粉丝与复读历史，再注入同一组状态进入矛盾阶段。
func _complete_normal_combat(source_hit_resolution: HitResolution) -> void:
	if (source_hit_resolution != _hit_resolution or not _normal_combat_active
			or _hit_resolution.get_player_pk() < _battle_config.maximum_player_pk):
		return
	var current_level: LevelProfile = get_current_level_profile()
	_stop_normal_combat()
	if current_level == null:
		return
	_run_data.live_session.commit_pk_win_fans(StringName(current_level.level_id), _battle_config.pk_win_fan_gain)
	_opening_fan_count = _run_data.live_session.fan_count
	var repeat_stats: RepeatGenerationStats = _repeat_queue.get_generation_stats()
	repeat_stats.commit_normal_repeat_history(_run_data, StringName(current_level.level_id))
	pk_maximum_reached.emit(current_level, _hit_resolution, repeat_stats)
	normal_combat_completed.emit(current_level, _hit_resolution, repeat_stats)
	if not _contradiction_flow.start(
			_run_data, _level_catalog, current_level, _hit_resolution, _combat_stage,
			_barrage_area, _opponent_pk_bar, _attack_input, _repeat_queue,
			_oracle_candidate_display, _battle_config, _loser_card_catalog,
			_contradiction_window_config, _audio_manager):
		push_error("BattleAttemptFlow: 无法启动矛盾/神谕流程。")
		return
	contradiction_entered.emit(current_level, _hit_resolution, repeat_stats)


func get_current_level_profile() -> LevelProfile:
	return _run_state.get_current_level_profile() if _run_state != null else null


func get_hit_resolution() -> HitResolution:
	return _hit_resolution


func get_combat_stage() -> CombatStage:
	return _combat_stage


func get_repeat_queue() -> RepeatDelayQueue:
	return _repeat_queue


func get_repeat_generation_stats() -> RepeatGenerationStats:
	return _repeat_queue.get_generation_stats() if _repeat_queue != null else null


func get_opponent_pk_bar() -> OpponentPKBar:
	return _opponent_pk_bar


func get_barrage_area() -> BarrageArea:
	return _barrage_area


func get_attack_input() -> AttackChargeInput:
	return _attack_input


func get_aim_reticle() -> AimReticle:
	return _aim_reticle


func get_current_tier() -> int:
	return _combat_stage.get_current_tier() if _combat_stage != null else CombatStage.INITIAL_TIER


func is_normal_combat_active() -> bool:
	return _normal_combat_active
