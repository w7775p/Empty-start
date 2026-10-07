extends Control

signal final_oracle_opened(session: FinalOracleSession)
signal rest_opened(session: RestSession)

const SAMPLE_LEVEL_CATALOG: LevelCatalog = preload("res://data/level_configuration/level_catalog.tres")
const SAMPLE_TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const CONTRADICTION_WINDOW_CONFIG: ContradictionWindowConfig = preload("res://systems/contradiction_break/contradiction_window_config.tres")
const FINAL_ORACLE_SCREEN_SCENE: PackedScene = preload("res://ui/final_oracle/final_oracle_screen.tscn")
@export var battle_config: SandboxBattleConfig = preload("res://data/sandbox/playable_battle_config.tres")

@onready var _barrage_area: BarrageArea = %BarrageArea
@onready var _aim_reticle: AimReticle = %AimReticle
@onready var _attack_charge_input: AttackChargeInput = %AttackChargeInput
@onready var _battle_hud = %BattleHud
@onready var _debug_panel: CanvasLayer = %DebugPanel

var _hit_resolution: HitResolution
var _combat_stage: CombatStage
var _opponent_pk_bar: OpponentPKBar
var _repeat_queue: RepeatDelayQueue
var _run_state: LevelRunState
var _normal_combat_active: bool = false
var _contradiction_stage_active: bool = false
var _contradiction_break: ContradictionBreakSystem
var _final_oracle_session: FinalOracleSession
var _final_oracle_screen: CanvasLayer
var _oracle_confirmation_state: FinalOracleConfirmationState
var _rest_session: RestSession
var _oracle_transition_timer: Timer
var _oracle_transition_started: bool = false
var _opening_fan_count: int = 0


# 场景只创建生命周期对象并接线；PK、Tier、倾向等状态留在各自所有者。
func _ready() -> void:
	# 直接运行场景时等待 Autoload 完成初始化，再创建周目并显式绑定已就绪的子 HUD。
	if SaveManager.data == null:
		SaveManager.new_game()
	%LiveDataHud.bind_live_session(SaveManager.data.live_session)
	# 敌方尚无数据所有者，本卡仅显式提供四个显示占位值。
	%OpponentLiveDataHud.set_values(0, 0, 0, 0)
	_run_state = LevelRunState.new(SAMPLE_LEVEL_CATALOG)
	_oracle_confirmation_state = FinalOracleConfirmationState.new(SaveManager.data)
	_oracle_confirmation_state.confirmation_committed.connect(_on_oracle_confirmation_committed)
	_opening_fan_count = SaveManager.data.live_session.fan_count
	_opponent_pk_bar = OpponentPKBar.new()
	_opponent_pk_bar.name = "OpponentPKBar"
	add_child(_opponent_pk_bar)
	_opponent_pk_bar.attempt_failed.connect(_on_attempt_failed)
	_barrage_area.barrage_generated.connect(_on_barrage_generated)
	_attack_charge_input.shot_hit_resolution_submitted.connect(_on_shot_hit_resolution_submitted)
	_attack_charge_input.shot_snapshot_created.connect(_on_contradiction_shot_created)
	_attack_charge_input.configure_target_query(_aim_reticle, _barrage_area)
	_oracle_transition_timer = Timer.new()
	_oracle_transition_timer.one_shot = true
	_oracle_transition_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_oracle_transition_timer.timeout.connect(_on_oracle_silence_finished)
	add_child(_oracle_transition_timer)
	_final_oracle_screen = FINAL_ORACLE_SCREEN_SCENE.instantiate() as CanvasLayer
	if _final_oracle_screen == null:
		push_error("Sandbox: 无法创建终结神谕界面。")
	else:
		add_child(_final_oracle_screen)
		final_oracle_opened.connect(Callable(_final_oracle_screen, "present_session"))
	%RestartButton.pressed.connect(restart_current_attempt)
	%PauseMenu.restart_requested.connect(restart_current_attempt)
	_debug_panel.call("bind_sandbox", self)
	restart_current_attempt()


# 原地重开同一关；替换本场结算和队列，保留当前关卡及此前周目成果。
func restart_current_attempt() -> void:
	if _hit_resolution != null:
		_hit_resolution.discard_uncommitted_normal_hit_history()
	_stop_normal_combat()
	_contradiction_stage_active = false
	_oracle_transition_started = false
	_oracle_transition_timer.stop()
	_final_oracle_session = null
	if _final_oracle_screen != null:
		_final_oracle_screen.call("close_screen")
	_rest_session = null
	if _contradiction_break != null:
		remove_child(_contradiction_break)
		_contradiction_break.queue_free()
		_contradiction_break = null
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
	if _normal_combat_active or _contradiction_stage_active:
		_repeat_queue.advance_and_dispatch(delta, _barrage_area)
	if _contradiction_stage_active and _contradiction_break != null and not _contradiction_break.is_result_locked():
		_battle_hud.show_battle_state("击破矛盾：%.1f 秒 · 剩余 %d 发" % [_contradiction_break.get_remaining_seconds(), _contradiction_break.get_remaining_shots()])
	elif _contradiction_stage_active and _contradiction_break != null and _contradiction_break.get_outcome() == ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		_try_start_oracle_transition()
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
	if _contradiction_stage_active:
		battle_phase = "矛盾击破（CONTRADICTION_BREAK）"
	elif _final_oracle_session != null and _final_oracle_session.is_open():
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


# 成功分支必须等本发矛盾复读全部生成并离场，才开始一次静音过渡。
func _try_start_oracle_transition() -> void:
	if _oracle_transition_started or _repeat_queue.get_pending_contradiction_count() > 0:
		return
	if _barrage_area.has_visible_contradiction_repeats():
		return
	_oracle_transition_started = true
	AudioManager.stop_music()
	_battle_hud.show_battle_state("矛盾击破 · 静音过渡")
	_oracle_transition_timer.start(0.5)


# 静音过渡结束才把本场普通历史与复读统计交给 13 系统的真实入口。
func _on_oracle_silence_finished() -> void:
	if _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		return
	var current_level: LevelProfile = _run_state.get_current_level_profile()
	if current_level == null:
		return
	_final_oracle_session = FinalOracleSession.new()
	if not _final_oracle_session.open_after_breakthrough(
		current_level.level_id,
		_get_oracle_history_with_sentence_text(current_level),
		_repeat_queue.get_generation_stats(),
		_oracle_confirmation_state
	):
		push_error("Sandbox: 终结神谕入口拒绝本场击破结果。")
		return
	_contradiction_stage_active = false
	_attack_charge_input.set_combat_active(false)
	_repeat_queue.clear_contradiction_queue()
	_battle_hud.show_battle_state("终结神谕已开放")
	final_oracle_opened.emit(_final_oracle_session)


# 给展示快照补上静态关卡原句文本，不把展示字段写回 HitResolution 历史。
func _get_oracle_history_with_sentence_text(current_level: LevelProfile) -> Array[Dictionary]:
	var normal_hit_history: Array[Dictionary] = _hit_resolution.get_normal_hit_history()
	var sentence_text_by_id: Dictionary = {}
	if current_level != null:
		for speech: LevelSpeech in current_level.normal_speech_pool:
			if speech != null and not speech.original_sentence_id.is_empty():
				sentence_text_by_id[speech.original_sentence_id] = speech.text

	for history_entry: Dictionary in normal_hit_history:
		var sentence_id: String = str(history_entry.get("original_sentence_id", ""))
		history_entry["original_sentence_text"] = str(sentence_text_by_id.get(sentence_id, sentence_id))
	return normal_hit_history


# 成功分支等神谕最终候选确认后，才把本场普通历史并入当前周目。
func _on_oracle_confirmation_committed(run_data: SaveData, level_id: String, _candidate: Dictionary) -> void:
	if run_data != SaveManager.data or _final_oracle_session == null or not _final_oracle_session.is_open():
		return
	if level_id != _final_oracle_session.get_level_id():
		return
	if _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		return
	if not _hit_resolution.commit_normal_hit_history(run_data):
		push_error("Sandbox: 神谕确认后提交普通命中历史失败。")
		return
	run_data.tendency_state.commit_attempt_tendency()


# 正式满蓄释放时立即按冻结的矛盾原句判定；飞行计时只保留演出。
func _on_contradiction_shot_created(snapshot: AttackTargetSnapshot) -> void:
	if not _contradiction_stage_active or _contradiction_break == null:
		return
	if not _contradiction_break.register_launched_shot():
		_attack_charge_input.set_combat_active(false)
		return
	var hit_ids: Array[String] = []
	for fact: Dictionary in snapshot.get_contradiction_facts():
		var sentence_id: String = str(fact.get("original_sentence_id", ""))
		if sentence_id.is_empty():
			continue
		hit_ids.append(sentence_id)
		# 真 / 假矛盾都按释放时冻结的原句事实创建复读计划。
		var plan: RepeatPlan = RepeatPlan.create_contradiction_hit_plan(
			StringName(sentence_id),
			str(fact.get("original_sentence_text", "")),
			_combat_stage.get_current_tier(),
			battle_config.contradiction_repeat_count,
			battle_config.contradiction_repeat_lifetime_seconds
		)
		plan.apply_display_template(battle_config.repeat_display_template)
		_repeat_queue.enqueue_plan(plan)
		_barrage_area.end_barrage(int(fact.get("target_instance_id", -1)))
	_contradiction_break.resolve_shot_hit_ids(hit_ids)


# 已锁定结果立即停止攻击和矛盾生成；后续分支只读取这一份结果。
func _on_contradiction_outcome_locked(outcome: int) -> void:
	_attack_charge_input.lock_new_attacks()
	_barrage_area.clear_barrages()
	if outcome == ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		_battle_hud.show_battle_state("矛盾击破成功 · 等待复读展示")
	else:
		_open_rest_after_unbroken()


# 未击破已是本场最终结果，直接把无神谕奖励的 PK 胜利快照交给休息入口。
func _open_rest_after_unbroken() -> void:
	if _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.NOT_BROKEN:
		return
	var current_level: LevelProfile = _run_state.get_current_level_profile()
	if current_level == null:
		return
	_rest_session = RestSession.new()
	if not _rest_session.open_result({
		"level_id": current_level.level_id,
		"result_kind": "pk_win_unbroken",
		"pk_won": true,
		"contradiction_broken": false,
		"new_scripture_entries": [],
		"new_loser_cards": [],
		"new_assimilation": [],
	}):
		push_error("Sandbox: 休息入口拒绝本场未击破结果。")
		return
	if not _hit_resolution.commit_normal_hit_history(SaveManager.data):
		push_error("Sandbox: 未击破进入休息时提交普通命中历史失败。")
		return
	SaveManager.data.tendency_state.commit_attempt_tendency()
	_contradiction_stage_active = false
	_repeat_queue.clear_contradiction_queue()
	_attack_charge_input.set_combat_active(false)
	_battle_hud.show_battle_state("PK 胜利 · 未击破矛盾 · 休息时刻")
	rest_opened.emit(_rest_session)


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
			battle_config.repeat_lifetime_seconds
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
	if _normal_combat_active and player_pk >= battle_config.maximum_player_pk:
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
	SaveManager.data.tendency_state.rollback_attempt_tendency()
	_battle_hud.show_failure()


# 普通 PK 满后读取本关矛盾内容，并以 Paradox 专属数值启动生成。
func _complete_normal_combat() -> void:
	if not _normal_combat_active or _hit_resolution.get_player_pk() < battle_config.maximum_player_pk:
		return
	_stop_normal_combat()
	_contradiction_stage_active = true
	_contradiction_break = ContradictionBreakSystem.new()
	add_child(_contradiction_break)
	_contradiction_break.outcome_locked.connect(_on_contradiction_outcome_locked)
	var current_level: LevelProfile = _run_state.get_current_level_profile()
	if not _contradiction_break.load_level_content(current_level):
		push_error("Sandbox: 当前关卡没有可用的矛盾内容。")
		return
	if not _barrage_area.start_contradiction_generation(
		current_level,
		_contradiction_break.get_true_contradictions(),
		_contradiction_break.get_false_contradictions(),
		CONTRADICTION_WINDOW_CONFIG
	):
		push_error("Sandbox: 无法启动真假矛盾生成。")
		return
	if not _contradiction_break.start_window(CONTRADICTION_WINDOW_CONFIG):
		_barrage_area.stop_contradiction_generation()
		push_error("Sandbox: 无法启动矛盾限时窗口。")
		return
	_attack_charge_input.set_contradiction_mode(true)
	_attack_charge_input.set_combat_active(true)
	_battle_hud.show_battle_state("矛盾阶段：寻找真正的矛盾")


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
	if SaveManager.data != null:
		SaveManager.data.tendency_state.rollback_attempt_tendency()
