class_name BattleAttemptFlow
extends Node

const FORMAL_COMBAT_NUMERICS: CombatNumericsConfig = preload("res://data/combat_stage/combat_numerics.tres")

signal attempt_started(level: LevelProfile, hit_resolution: HitResolution, combat_stage: CombatStage, repeat_queue: RepeatDelayQueue)
## 首批生成前通知根场景重置独立的对手表现数据。
signal attempt_preparing(level: LevelProfile)
signal attempt_restarted(level: LevelProfile, hit_resolution: HitResolution, combat_stage: CombatStage, repeat_queue: RepeatDelayQueue)
signal shot_resolved(snapshot: AttackTargetSnapshot, submission: Dictionary, current_tier: int, repeat_stats: RepeatGenerationStats)
# 整发通知与升档清理完成后广播，供 Sandbox 和后续阶段演出接入。
signal tier_transition_cleared(previous_tier: int, current_tier: int, cleared_barrage_count: int)
# 突破提示完成后交给状态对白消费者，再按阶段恢复战斗。
signal tier_transition_completed(previous_tier: int, current_tier: int)
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
var _external_pk_source: Callable
var _normal_completion_pending: bool = false
var _contradiction_start_pending: bool = false
var _tier_transition_active: bool = false
var _tier1_dialogue_pending: bool = false
var _tier_transition_hit_resolution: HitResolution
var _tier_transition_previous_tier: int = CombatStage.INITIAL_TIER
var _tier_transition_current_tier: int = CombatStage.INITIAL_TIER
var _shot_tier_at_arrival: int = CombatStage.INITIAL_TIER
var _has_shot_tier_at_arrival: bool = false
var _previous_live_tier: int = CombatStage.INITIAL_TIER


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
	_attack_input.shot_arrival_resolved.connect(_on_shot_arrival_resolved)
	_attack_input.shot_hit_resolution_submitted.connect(_on_shot_hit_resolution_submitted)
	_is_configured = true
	return true


## 普通战斗由外部 PK 拥有者推进时，沿用本 Flow 的关卡、Tier、失败与矛盾交接。
func set_external_pk_source(source: Callable) -> bool:
	if _normal_combat_active:
		return false
	if not source.is_valid():
		return false
	_external_pk_source = source
	return true


func uses_external_pk_source() -> bool:
	return _external_pk_source.is_valid()


## 从外部唯一 PK 源同步观察值；零值仍通过旧失败入口，满值仍走旧矛盾流程。
func notify_external_pk_changed() -> bool:
	if (not uses_external_pk_source() or not _normal_combat_active
			or _normal_completion_pending or _hit_resolution == null):
		return false
	var previous_tier: int = _combat_stage.get_current_tier() if _combat_stage != null else CombatStage.INITIAL_TIER
	var current_pk: float = _hit_resolution.notify_external_player_pk_changed()
	if current_pk <= _battle_config.minimum_player_pk:
		_on_attempt_failed()
		return true
	var current_tier: int = _combat_stage.get_current_tier() if _combat_stage != null else previous_tier
	if _normal_combat_active and current_tier > previous_tier:
		# 外部 PK 源跨档时复用旧清屏与突破演出入口。
		tier_transition_cleared.emit(previous_tier, current_tier, 0)
	return true


## 成功发表的玩家原句沿用旧倾向与历史结算，PK 数值仍只由外部 Host 决定。
func record_plan_b_player_publication(definition: Dictionary) -> bool:
	if (not uses_external_pk_source() or not _normal_combat_active
			or _hit_resolution == null or _run_data == null):
		return false
	var word_id: String = String(definition.get("word_id", "")).strip_edges()
	var original_sentence_id: String = String(
		definition.get("source_id", definition.get("original_sentence_id", word_id))
	).strip_edges()
	var tendency_id: String = String(definition.get("tendency", "")).strip_edges()
	var strength: int = int(definition.get("strength", 0))
	if word_id.is_empty() or original_sentence_id.is_empty() or strength not in [1, 2, 3]:
		return false
	var reward: Dictionary = _hit_resolution.calculate_normal_word_reward(strength, tendency_id)
	if reward.is_empty():
		return false
	_hit_resolution.record_normal_word_hit(StringName(original_sentence_id), StringName(tendency_id))
	_run_data.tendency_state.record_normal_speech_tendency(
		tendency_id, int(reward.get("tendency_delta", 0))
	)
	_run_data.live_session.record_normal_hit_live_rule()
	return true


## PK 胜利时把真实玩家棋子复读数量投给旧神谕排序与神降临历史。
func record_plan_b_population_repeats(
		unit_snapshots: Array[Dictionary], word_catalog: Object
) -> bool:
	if (not uses_external_pk_source() or not _normal_combat_active
			or _repeat_queue == null or word_catalog == null
			or not word_catalog.has_method("get_word_definition")):
		return false
	var counts_by_sentence_id: Dictionary = {}
	for snapshot: Dictionary in unit_snapshots:
		if String(snapshot.get("team", "")) != "player":
			continue
		var word_id: String = String(snapshot.get("word_id", "")).strip_edges()
		if word_id.is_empty():
			continue
		var definition: Dictionary = word_catalog.call("get_word_definition", word_id)
		var sentence_id: String = String(
			definition.get("source_id", definition.get("original_sentence_id", word_id))
		).strip_edges()
		if sentence_id.is_empty():
			continue
		counts_by_sentence_id[sentence_id] = int(counts_by_sentence_id.get(sentence_id, 0)) + 1
	for sentence_id: String in counts_by_sentence_id:
		var plan := RepeatPlan.new()
		plan.original_line_id = StringName(sentence_id)
		plan.repeat_type = RepeatPlan.RepeatType.NORMAL
		_repeat_queue.get_generation_stats().record_generated(
			plan, int(counts_by_sentence_id[sentence_id])
		)
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
	attempt_preparing.emit(restarting_level)
	_opponent_pk_bar.reset_current_attempt()
	_run_data.tendency_state.rollback_attempt_tendency()
	_run_data.live_session.initialize_session(_opening_fan_count)
	_run_data.live_session.configure_formal_rules(FORMAL_COMBAT_NUMERICS)
	_run_data.live_session.set_opening_viewers(randf_range(
		FORMAL_COMBAT_NUMERICS.opening_viewer_multiplier_min,
		FORMAL_COMBAT_NUMERICS.opening_viewer_multiplier_max
	))
	_normal_completion_pending = false
	_contradiction_start_pending = false
	_tier_transition_active = false
	_tier1_dialogue_pending = false
	_tier_transition_hit_resolution = null
	_has_shot_tier_at_arrival = false
	_previous_live_tier = CombatStage.INITIAL_TIER

	_hit_resolution = HitResolution.new(
		FORMAL_COMBAT_NUMERICS.initial_player_pk,
		FORMAL_COMBAT_NUMERICS.minimum_player_pk,
		FORMAL_COMBAT_NUMERICS.maximum_player_pk,
		FORMAL_COMBAT_NUMERICS.positive_pk_shot_cap,
		FORMAL_COMBAT_NUMERICS.negative_pk_shot_cap,
		FORMAL_COMBAT_NUMERICS
	)
	if uses_external_pk_source() and not _hit_resolution.bind_external_player_pk_getter(_external_pk_source):
		push_error("BattleAttemptFlow: 外部 PK 查询入口无效。")
		return false
	_repeat_queue = RepeatDelayQueue.new(_battle_config.maximum_pending_repeat_count)
	_barrage_area.begin_combat_attempt()
	_combat_stage = CombatStage.new(_tier_catalog)
	# Tier 先绑定 PK，再连接本流程；本发回调会读到已经更新的 Tier。
	_combat_stage.bind_hit_resolution(_hit_resolution)
	_combat_stage.bind_barrage_area(_barrage_area)
	_combat_stage.bind_opponent_pk_bar(_opponent_pk_bar)
	_combat_stage.bind_audio_manager(_audio_manager)
	_combat_stage.tier_state_changed.connect(_on_tier_state_changed.bind(_combat_stage))
	_hit_resolution.final_player_pk_updated.connect(_on_final_player_pk_updated.bind(_hit_resolution))
	_barrage_area.configure_combat_numerics(FORMAL_COMBAT_NUMERICS)
	_barrage_area.repeat_barrage_screen_cap = _battle_config.repeat_screen_cap
	_combat_stage.begin_combat()

	var current_level: LevelProfile = get_current_level_profile()
	if current_level == null:
		battle_state_changed.emit("当前没有关卡配置")
		return false
	if not _attack_input.configure_attack_timing(FORMAL_COMBAT_NUMERICS.create_attack_timing_config()):
		push_error("BattleAttemptFlow: 攻击时长配置无效。")
		return false
	if not _attack_input.configure_hit_resolution(_hit_resolution):
		push_error("BattleAttemptFlow: 无法接入本场命中结算。")
		return false
	if not _attack_input.configure_combat_aim_radii(FORMAL_COMBAT_NUMERICS):
		push_error("BattleAttemptFlow: 无法应用正式准心判定半径。")
		return false

	_normal_combat_active = true
	_attack_input.set_contradiction_mode(false)
	if uses_external_pk_source():
		# Plan B 使用棋子传播；旧弹幕与回拉仅在矛盾阶段重新启用攻击输入。
		_attack_input.set_combat_active(false)
		_barrage_area.stop_normal_generation()
		_opponent_pk_bar.stop_pullback()
	else:
		_attack_input.set_combat_active(true)
		if not _barrage_area.start_normal_generation(current_level):
			_stop_normal_combat()
			push_error("BattleAttemptFlow: 无法启动普通弹幕生成。")
			return false
		_opponent_pk_bar.start_pullback(_hit_resolution, FORMAL_COMBAT_NUMERICS.base_pullback_speed_pk_per_second)
	if not uses_external_pk_source():
		_refresh_pk_feedback()
	attempt_started.emit(current_level, _hit_resolution, _combat_stage, _repeat_queue)
	if is_restart:
		attempt_restarted.emit(current_level, _hit_resolution, _combat_stage, _repeat_queue)
	return true


# 暂停沿用 SceneTree；此入口只在普通战斗活动时推进普通复读。
func advance(delta: float) -> void:
	if (_normal_combat_active and not _tier_transition_active and not _tier1_dialogue_pending
			and _hit_resolution != null and _hit_resolution.allows_normal_pk_resolution()):
		_repeat_queue.advance_and_dispatch(delta, _barrage_area)


# 供阶段切换先清理旧复读请求，再按需清除当前可见弹幕。
func clear_pending_normal_repeats() -> int:
	return _repeat_queue.clear_normal_queue() if _repeat_queue != null else 0


# 升档时只移除当前视图，普通生成按新 Tier 配置继续运行。
func clear_barrages_for_stage_transition() -> int:
	if is_instance_valid(_barrage_area):
		return _barrage_area.clear_current_barrages()
	return 0


# 查询本发升档沿，避免仅用于调试的 PK 设置延迟对白事件。
func is_tier_breakthrough_pending() -> bool:
	return (
		_has_shot_tier_at_arrival
		and _combat_stage != null
		and _combat_stage.get_current_tier() > _shot_tier_at_arrival
	)


# 清屏后冻结输入、生成和回拉，等短暂突破提示结束再恢复。
func begin_tier_breakthrough_transition(previous_tier: int, current_tier: int) -> bool:
	if not _normal_combat_active or _tier_transition_active or _tier1_dialogue_pending:
		return false
	if previous_tier < CombatStage.INITIAL_TIER or current_tier <= previous_tier:
		return false
	if _combat_stage == null or _combat_stage.get_current_tier() != current_tier or _hit_resolution == null:
		return false
	_tier_transition_active = true
	_tier_transition_hit_resolution = _hit_resolution
	_tier_transition_previous_tier = previous_tier
	_tier_transition_current_tier = current_tier
	_attack_input.set_combat_active(false)
	_barrage_area.stop_normal_generation()
	_opponent_pk_bar.stop_pullback()
	return true


# 演出结束后发布阶段事实；T0→T1 等待连线对白完整播放后再恢复战斗。
func finish_tier_breakthrough_transition() -> bool:
	if not _tier_transition_active or _tier_transition_hit_resolution != _hit_resolution:
		return false
	var previous_tier: int = _tier_transition_previous_tier
	var current_tier: int = _tier_transition_current_tier
	var waits_for_tier1_dialogue: bool = (
		previous_tier == CombatStage.INITIAL_TIER and current_tier == CombatStage.INITIAL_TIER + 1
	)
	_tier_transition_active = false
	_tier1_dialogue_pending = waits_for_tier1_dialogue
	tier_transition_completed.emit(previous_tier, current_tier)
	# 无配置对白会在信号内同步结束；用本地事实避免重复恢复。
	if waits_for_tier1_dialogue:
		return true
	return _resume_after_tier_transition()


# 连线对白结束事实只恢复仍处于 T1 的本次尝试。
func resume_after_tier1_dialogue() -> bool:
	if not _tier1_dialogue_pending or get_current_tier() != CombatStage.INITIAL_TIER + 1:
		return false
	_tier1_dialogue_pending = false
	return _resume_after_tier_transition()


# 恢复本档普通生成和回拉；若升档本发已打满 PK，则继续胜利入口。
func _resume_after_tier_transition() -> bool:
	var transition_hit: HitResolution = _tier_transition_hit_resolution
	if not _normal_combat_active or transition_hit == null or transition_hit != _hit_resolution:
		_tier_transition_hit_resolution = null
		return false
	_tier_transition_hit_resolution = null
	if transition_hit.get_player_pk() >= _battle_config.maximum_player_pk:
		_complete_normal_combat(transition_hit)
		return true
	if not transition_hit.allows_normal_pk_resolution():
		return false
	if uses_external_pk_source():
		return true
	var current_level: LevelProfile = get_current_level_profile()
	if current_level == null or not _barrage_area.start_normal_generation(current_level):
		push_error("BattleAttemptFlow: 突破提示结束后无法恢复本档普通弹幕。")
		return false
	_attack_input.set_combat_active(true)
	_opponent_pk_bar.resume_pullback()
	return true


func complete_current_level() -> void:
	if is_instance_valid(_opponent_pk_bar):
		_opponent_pk_bar.complete_current_level()


# 明确结束普通尝试并清除仍在等待的普通复读。
func stop() -> void:
	_stop_normal_combat()


func _stop_normal_combat() -> void:
	_normal_combat_active = false
	_tier_transition_active = false
	_tier1_dialogue_pending = false
	_tier_transition_hit_resolution = null
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


# 在本发 PK 结算前记录 Tier，避免把飞行期间的对手回拉误判为本发升档。
func _on_shot_arrival_resolved(_snapshot: AttackTargetSnapshot, _target_results: Array[Dictionary]) -> void:
	_has_shot_tier_at_arrival = _normal_combat_active and _combat_stage != null
	if _has_shot_tier_at_arrival:
		_shot_tier_at_arrival = _combat_stage.get_current_tier()


# 命中信号到达时，HitResolution 和 CombatStage 已完成本发唯一结算。
func _on_shot_hit_resolution_submitted(snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	var has_arrival_tier: bool = _has_shot_tier_at_arrival
	var arrival_tier: int = _shot_tier_at_arrival
	_has_shot_tier_at_arrival = false
	if not _normal_combat_active:
		return
	var result: Dictionary = submission.get("hit_resolution_result", {})
	if bool(result.get("cancelled_by_zero_pk", false)):
		return
	var resolved_tier: int = _combat_stage.get_current_tier()
	var tier_increased_this_shot: bool = (
		has_arrival_tier and resolved_tier > arrival_tier
	)
	var normal_hit_count: int = 0
	var repeat_hit_count: int = 0
	for target_result: Dictionary in result.get("target_results", []):
		var trait_result := target_result.get("trait_result") as BarrageTraitResult
		if trait_result == null:
			continue
		# 遮挡命中保留原目标，其余已到达目标沿用弹幕系统的结束入口。
		if trait_result.kind != BarrageTraitResult.Kind.OCCLUSION:
			_barrage_area.end_barrage(int(target_result.get("target_instance_id", -1)))
		if trait_result != null and trait_result.kind in [BarrageTraitResult.Kind.FAKE_CARD, BarrageTraitResult.Kind.RETALIATION_COPY, BarrageTraitResult.Kind.REFLECT]:
			_run_data.live_session.record_trap_hit_live_rule()
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
			FORMAL_COMBAT_NUMERICS.get_lifetime_seconds(
				"repeat", _tier_catalog.get_tier_config(_combat_stage.get_current_tier()).lifetime_multiplier
			),
			str(target_result.get("tendency_id", ""))
		)
		plan.apply_display_template(_battle_config.repeat_display_template)
		_repeat_queue.enqueue_plan(plan)
	if normal_hit_count > 0:
		for _hit_index in range(normal_hit_count):
			_run_data.live_session.record_normal_hit_live_rule()
		# 普通与陷阱可能同发命中，符号必须读取整发净结果。
		battle_state_changed.emit("命中 %d 条 · PK %+.2f%% · 等待复读" % [normal_hit_count, float(result.get("total_pk_delta", 0.0)) * 100.0])
	elif repeat_hit_count > 0:
		battle_state_changed.emit("复读命中 %d 条 · 零收益" % repeat_hit_count)
	else:
		battle_state_changed.emit("未命中有效话语")
	shot_resolved.emit(snapshot, submission.duplicate(true), resolved_tier, _repeat_queue.get_generation_stats())
	if tier_increased_this_shot:
		# 本发命中消费者和同发复读登记完成后，清除旧档位及本发新建的普通等待请求。
		clear_pending_normal_repeats()
		# 等所有整发消费者返回后清屏，保留当前普通生成状态并交付最终档位。
		var cleared_barrage_count: int = clear_barrages_for_stage_transition()
		tier_transition_cleared.emit(arrival_tier, resolved_tier, cleared_barrage_count)
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
	if _normal_combat_active:
		_run_data.live_session.record_tier_transition(_previous_live_tier, current_tier)
	# 降档也刷新已观察档位，使下一次真实升档可正确触发。
	_previous_live_tier = current_tier
	_refresh_pk_feedback()
	tier_changed.emit(current_tier, _hit_resolution.get_player_pk())


func _refresh_pk_feedback() -> void:
	if _hit_resolution != null and _combat_stage != null:
		pk_feedback_changed.emit(_hit_resolution.get_player_pk(), _combat_stage.get_current_tier())


# 普通 PK 胜利先停掉尝试、保存粉丝与复读历史，再注入同一组状态进入矛盾阶段。
func _complete_normal_combat(source_hit_resolution: HitResolution) -> void:
	if (source_hit_resolution != _hit_resolution or not _normal_combat_active
			or _tier_transition_active or _tier1_dialogue_pending
			or _hit_resolution.get_player_pk() < _battle_config.maximum_player_pk):
		return
	var current_level: LevelProfile = get_current_level_profile()
	_stop_normal_combat()
	if current_level == null:
		return
	_run_data.live_session.commit_pk_win_fans(
		StringName(current_level.level_id), FORMAL_COMBAT_NUMERICS.pk_win_fan_gain
	)
	_opening_fan_count = _run_data.live_session.fan_count
	var repeat_stats: RepeatGenerationStats = _repeat_queue.get_generation_stats()
	repeat_stats.commit_normal_repeat_history(_run_data, StringName(current_level.level_id))
	_contradiction_start_pending = true
	pk_maximum_reached.emit(current_level, _hit_resolution, repeat_stats)
	normal_combat_completed.emit(current_level, _hit_resolution, repeat_stats)


# 满值结算后由 Sandbox 等待转场完成，再启动矛盾窗口与输入。
func begin_contradiction_after_transition(
		current_level: LevelProfile,
		source_hit_resolution: HitResolution,
		repeat_stats: RepeatGenerationStats
) -> bool:
	if (not _contradiction_start_pending or _normal_combat_active
			or source_hit_resolution == null or source_hit_resolution != _hit_resolution
			or current_level != get_current_level_profile() or repeat_stats == null):
		return false
	_contradiction_start_pending = false
	if not _contradiction_flow.start(
			_run_data, _level_catalog, current_level, _hit_resolution, _combat_stage,
			_barrage_area, _opponent_pk_bar, _attack_input, _repeat_queue,
			_oracle_candidate_display, _battle_config, _loser_card_catalog,
			_contradiction_window_config, _audio_manager):
		push_error("BattleAttemptFlow: 无法启动矛盾/神谕流程。")
		return false
	contradiction_entered.emit(current_level, _hit_resolution, repeat_stats)
	return true


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
