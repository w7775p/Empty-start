class_name ContradictionOracleFlow
extends Node

signal entered(system: ContradictionBreakSystem)
signal outcome_resolved(outcome: int)
signal oracle_opened(session: FinalOracleSession)
signal rest_ready(result: RestSession)
signal state_text_changed(text: String)
signal commit_failed(reason: String)

var _run_data: SaveData
var _current_level: LevelProfile
var _catalog: LevelCatalog
var _hit_resolution: HitResolution
# 仅引用本次首次确认的历史拥有者；复用旧确认的新尝试没有提交资格。
var _confirmation_hit_resolution: HitResolution
var _combat_stage: CombatStage
var _barrage_area: BarrageArea
var _opponent_pk_bar: OpponentPKBar
var _attack_charge_input: AttackChargeInput
var _repeat_queue: RepeatDelayQueue
var _oracle_candidate_display: FinalOracleCandidateDisplay
var _audio_manager: Node
var battle_config: SandboxBattleConfig
var loser_card_catalog: LoserCardCatalog
var _contradiction_break: ContradictionBreakSystem
var _final_oracle_session: FinalOracleSession
var _oracle_selection_timer: FinalOracleSelectionTimer
var _oracle_confirmation_state: FinalOracleConfirmationState
var _rest_session: RestSession
var _oracle_transition_timer: Timer
var _oracle_transition_started: bool = false
var _contradiction_stage_active: bool = false
var _contradiction_outcome_handled: bool = false
var _stopped: bool = true
var _commit_error: String = ""
var _rest_handoff_pending: bool = false


# 查询流程当前持有的唯一业务对象；Rest 后仍可核对首次神谕结果。
func get_contradiction_system() -> ContradictionBreakSystem:
	return _contradiction_break


func get_oracle_session() -> FinalOracleSession:
	return _final_oracle_session


func get_selection_timer() -> FinalOracleSelectionTimer:
	return _oracle_selection_timer


func get_confirmation_state() -> FinalOracleConfirmationState:
	return _oracle_confirmation_state


func get_result() -> RestSession:
	return _rest_session


func is_contradiction_active() -> bool:
	return not _stopped and _contradiction_stage_active


func get_commit_error() -> String:
	return _commit_error


# 显式停止尝试，取消旧 Timer、输入订阅及帧尾交接，保留周目确认事实。
func stop() -> void:
	_stopped = true
	_rest_handoff_pending = false
	_contradiction_stage_active = false
	_oracle_selection_timer = null
	_final_oracle_session = null
	_confirmation_hit_resolution = null
	_rest_session = null
	if is_instance_valid(_attack_charge_input):
		if _attack_charge_input.shot_snapshot_created.is_connected(_on_contradiction_shot_created):
			_attack_charge_input.shot_snapshot_created.disconnect(_on_contradiction_shot_created)
		if _attack_charge_input.selection_target_hit.is_connected(_on_oracle_selection_target_hit):
			_attack_charge_input.selection_target_hit.disconnect(_on_oracle_selection_target_hit)
		_attack_charge_input.clear_selection_targets()
		_attack_charge_input.set_combat_active(false)
		_attack_charge_input.set_contradiction_mode(false)
	if _repeat_queue != null:
		_repeat_queue.clear_contradiction_queue()
	if is_instance_valid(_oracle_candidate_display):
		_oracle_candidate_display.clear_display()
	if is_instance_valid(_barrage_area):
		_barrage_area.stop_contradiction_generation()
	if is_instance_valid(_contradiction_break):
		_contradiction_break.set_contradiction_break_enabled(false)
		remove_child(_contradiction_break)
		_contradiction_break.queue_free()
		_contradiction_break = null
	if is_instance_valid(_oracle_transition_timer):
		_oracle_transition_timer.stop()
		remove_child(_oracle_transition_timer)
		_oracle_transition_timer.queue_free()
		_oracle_transition_timer = null


# 离树仅作最终清理；正常重开、换关和终局入口均显式 stop。
func _exit_tree() -> void:
	stop()


# 停战只操作注入的现有组件，页面及顶层路由继续交给 Sandbox。
func _stop_battle() -> void:
	_attack_charge_input.set_combat_active(false)
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	_opponent_pk_bar.stop_pullback()
	_repeat_queue.clear_normal_queue()


# 提交状态由 HitResolution 持有；重试奖励时已提交历史不能再次累计。
func _commit_history_and_tendency() -> bool:
	if not _hit_resolution.has_committed_normal_hit_history() and not _hit_resolution.commit_normal_hit_history(_run_data):
		return _fail_commit("普通命中历史提交失败")
	_run_data.tendency_state.commit_attempt_tendency()
	return true


# 写入失败停止后续奖励与 Rest；已有合法成果保留，修复配置后显式重试。
func _fail_commit(reason: String) -> bool:
	_commit_error = reason
	commit_failed.emit(reason)
	push_error("ContradictionOracleFlow: " + reason)
	return false


# 只对真实确认提交奖励；按数据所有者返回值和保存事实区分拒绝、去重与成功。
func commit_confirmed_rewards() -> bool:
	if _stopped or not is_inside_tree() or _rest_handoff_pending or _rest_session != null or _final_oracle_session == null:
		return false
	if _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		return false
	var candidate: Dictionary = _final_oracle_session.get_confirmed_selection()
	if candidate.is_empty() or _final_oracle_session.get_level_id() != _current_level.level_id:
		return false
	var level_id := StringName(_current_level.level_id)
	var streamer_id := StringName(_current_level.streamer_id)
	var entry: ScriptureEntry = _run_data.scripture_data.get_entry_for_level(level_id)
	if entry == null:
		if not _run_data.scripture_data.write_confirmed_oracle(_current_level, candidate):
			return _fail_commit("已确认神谕未写入圣典")
		entry = _run_data.scripture_data.get_entry_for_level(level_id)
	if entry == null or entry.original_line_id != StringName(str(candidate.get("original_sentence_id", ""))):
		return _fail_commit("圣典保存结果与首次确认不匹配")
	if _confirmation_hit_resolution == _hit_resolution:
		if not _commit_history_and_tendency():
			return false
	else:
		# 重放旧神谕只补齐原奖励，新尝试的普通暂存由原拥有者撤回。
		_hit_resolution.discard_uncommitted_normal_hit_history()
		_run_data.tendency_state.rollback_attempt_tendency()
	# 正式卡目录缺资料沿用无卡规则；有资料时拒绝写入必须有已有卡片作为去重依据。
	var cards: LoserCardData = _run_data.loser_card_data
	var card_added: bool = cards.grant_on_true_defeat(level_id, streamer_id, true, true, loser_card_catalog)
	if loser_card_catalog != null and loser_card_catalog.find_profile(streamer_id) != null:
		if not card_added and not cards.acquired_streamer_ids.has(streamer_id):
			return _fail_commit("败者卡提交失败")
	var assimilation: AssimilationData = _run_data.assimilation_data
	var defeat_added: bool = assimilation.register_defeated_streamer(level_id, streamer_id, true, true)
	if not defeat_added and not assimilation.defeated_streamer_ids.has(streamer_id):
		return _fail_commit("真正击败登记失败")
	# 同来源重试补齐尚未成功的继承写入；跨关同主播去重继续沿用原归属。
	if assimilation.defeated_level_ids.has(level_id):
		var pool: WordPoolInheritanceConfig = _current_level.normal_pool_inheritance
		if pool != null and pool.can_inherit and not pool.is_contradiction_pool:
			var pool_added: bool = assimilation.register_inherited_word_pool(level_id, pool.pool_id,
				pool.appearance_weight, pool.can_inherit, pool.is_contradiction_pool)
			if not pool_added and not assimilation.get_current_content_snapshot()["inherited_word_weights"].has(pool.pool_id):
				return _fail_commit("普通词库继承提交失败")
		for trait_id: StringName in _current_level.inheritable_trait_ids:
			var trait_added: bool = assimilation.register_inherited_trait(level_id, trait_id, true)
			if not trait_added and not assimilation.get_current_content_snapshot()["inherited_trait_ids"].has(trait_id):
				return _fail_commit("特性继承提交失败")
	_commit_error = ""
	_rest_handoff_pending = true
	if _confirmation_hit_resolution == _hit_resolution:
		_run_data.live_session.start_short_boost(LiveSessionData.BoostEvent.ORACLE_CONFIRMATION,
			battle_config.oracle_boost_viewer_gain, battle_config.oracle_boost_like_gain,
			battle_config.oracle_boost_duration_seconds)
	# 同步确认与攻击回调先结束，帧尾再清候选并交付同一 Rest 对象。
	_open_rest_after_oracle.call_deferred(_run_data, _final_oracle_session)
	return true


# 注入本场已有组件；同一周目复用确认状态，重开只重建矛盾和神谕会话。
func start(run_data: SaveData, catalog: LevelCatalog, current_level: LevelProfile,
		hit_resolution: HitResolution, combat_stage: CombatStage, area: BarrageArea,
		opponent_pk_bar: OpponentPKBar, attack_input: AttackChargeInput,
		repeat_queue: RepeatDelayQueue, candidate_display: FinalOracleCandidateDisplay,
		config: SandboxBattleConfig, card_catalog: LoserCardCatalog,
		window_config: ContradictionWindowConfig, audio_manager: Node) -> bool:
	if not is_inside_tree() or not _stopped or run_data == null or catalog == null or current_level == null:
		return false
	if hit_resolution == null or combat_stage == null or repeat_queue == null or config == null or window_config == null:
		return false
	if not is_instance_valid(area) or not is_instance_valid(attack_input) or not is_instance_valid(candidate_display) or not is_instance_valid(opponent_pk_bar) or not is_instance_valid(audio_manager):
		return false
	if _run_data != run_data or _catalog != catalog:
		_run_data = run_data
		_catalog = catalog
		_oracle_confirmation_state = FinalOracleConfirmationState.new(run_data)
		# Scripture 先同步写入，流程再读取保存结果，不能将确认广播当作写入成功。
		run_data.scripture_data.bind_confirmation_state(_oracle_confirmation_state, catalog)
		_oracle_confirmation_state.confirmation_committed.connect(_on_oracle_confirmation_committed)
	_current_level = current_level
	_hit_resolution = hit_resolution
	_combat_stage = combat_stage
	_barrage_area = area
	_opponent_pk_bar = opponent_pk_bar
	_attack_charge_input = attack_input
	_repeat_queue = repeat_queue
	_oracle_candidate_display = candidate_display
	_audio_manager = audio_manager
	battle_config = config
	loser_card_catalog = card_catalog
	_stopped = false
	_rest_handoff_pending = false
	_rest_session = null
	_final_oracle_session = null
	_oracle_transition_started = false
	_contradiction_outcome_handled = false
	_commit_error = ""
	_contradiction_break = ContradictionBreakSystem.new()
	add_child(_contradiction_break)
	_contradiction_break.outcome_locked.connect(_on_contradiction_outcome_locked)
	_oracle_transition_timer = Timer.new()
	_oracle_transition_timer.one_shot = true
	_oracle_transition_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_oracle_transition_timer.timeout.connect(_on_oracle_silence_finished)
	add_child(_oracle_transition_timer)
	_attack_charge_input.shot_snapshot_created.connect(_on_contradiction_shot_created)
	_attack_charge_input.selection_target_hit.connect(_on_oracle_selection_target_hit)
	var contradiction_stage_ready: bool = _contradiction_break.load_level_content(current_level)
	if contradiction_stage_ready:
		# 候选数量和真假构成由 12 系统决定；弹幕区只负责显示本场固定集合。
		var paradox_candidates: Array[LevelContradiction] = _contradiction_break.get_fixed_paradox_candidates()
		if paradox_candidates.size() != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT:
			contradiction_stage_ready = false
		else:
			var true_lines: Array[LevelContradiction] = [paradox_candidates[0]]
			var false_lines: Array[LevelContradiction] = []
			for index: int in range(1, paradox_candidates.size()):
				false_lines.append(paradox_candidates[index])
			contradiction_stage_ready = area.start_contradiction_generation(current_level, true_lines, false_lines, window_config)
	if not contradiction_stage_ready or not _contradiction_break.start_window(window_config):
		stop()
		return false
	_contradiction_stage_active = true
	attack_input.set_contradiction_mode(true)
	attack_input.set_combat_active(true)
	state_text_changed.emit("矛盾阶段：寻找真正的矛盾")
	entered.emit(_contradiction_break)
	return true


# 暂停由 SceneTree 统一控制；矛盾复读及神谕计时只由本流程推进。
func advance(delta: float) -> void:
	if _stopped or not is_inside_tree() or get_tree().paused or _rest_session != null:
		return
	if _contradiction_stage_active:
		_repeat_queue.advance_and_dispatch(delta, _barrage_area)
	if _oracle_selection_timer != null:
		_oracle_selection_timer.advance(delta, false)
	if not _contradiction_stage_active:
		return
	if not _contradiction_break.is_result_locked():
		state_text_changed.emit("击破矛盾：%.1f 秒 · 剩余 %d 发" % [_contradiction_break.get_remaining_seconds(), _contradiction_break.get_remaining_shots()])
	elif _contradiction_break.get_outcome() == ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		_try_start_oracle_transition()
	elif _commit_error.is_empty():
		_open_rest_after_unbroken()


# 成功分支必须等本发矛盾复读全部生成并离场，才开始一次静音过渡。
func _try_start_oracle_transition() -> void:
	if _oracle_transition_started or _repeat_queue.get_pending_contradiction_count() > 0:
		return
	if _barrage_area.has_visible_contradiction_repeats():
		return
	_oracle_transition_started = true
	_audio_manager.stop_music()
	state_text_changed.emit("矛盾击破 · 静音过渡")
	_oracle_transition_timer.start(0.5)


# 静音过渡结束才把本场普通历史与复读统计交给 13 系统的真实入口。
func _on_oracle_silence_finished() -> void:
	if _stopped or _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		return
	var current_level: LevelProfile = _current_level
	if current_level == null:
		return
	_final_oracle_session = FinalOracleSession.new()
	if not _final_oracle_session.open_after_breakthrough(
		current_level.level_id,
		_get_oracle_history_with_sentence_text(current_level),
		_repeat_queue.get_generation_stats(),
		_oracle_confirmation_state
	):
		push_error("ContradictionOracleFlow: 终结神谕入口拒绝本场击破结果。")
		return
	_contradiction_stage_active = false
	_repeat_queue.clear_contradiction_queue()
	_barrage_area.stop_normal_generation()
	_barrage_area.stop_contradiction_generation()
	_barrage_area.clear_barrages()
	_opponent_pk_bar.stop_pullback()
	var confirmed_candidate: Dictionary = _final_oracle_session.get_confirmed_selection()
	if not confirmed_candidate.is_empty():
		_attack_charge_input.clear_selection_targets()
		_attack_charge_input.set_combat_active(false)
		_oracle_candidate_display.show_confirmed_candidate(confirmed_candidate)
		state_text_changed.emit("终结神谕已确认")
		oracle_opened.emit(_final_oracle_session)
		commit_confirmed_rewards()
		return
	var candidates: Array[Dictionary] = _final_oracle_session.get_display_candidates()
	var target_controls: Array[Control] = _oracle_candidate_display.show_candidates(candidates)
	if target_controls.size() != candidates.size():
		push_error("ContradictionOracleFlow: 神谕候选正文未能显示到主游戏区。")
		return
	if not _attack_charge_input.set_selection_targets(target_controls):
		_oracle_candidate_display.clear_display()
		push_error("ContradictionOracleFlow: 神谕候选没有可攻击的目标控件。")
		return
	_attack_charge_input.set_contradiction_mode(false)
	_attack_charge_input.set_combat_active(true)
	_oracle_selection_timer = FinalOracleSelectionTimer.new()
	_oracle_selection_timer.remaining_time_changed.connect(_on_oracle_selection_time_changed)
	_oracle_selection_timer.expired.connect(_on_oracle_selection_expired)
	state_text_changed.emit("神谕选择 · 10.0 秒")
	_oracle_selection_timer.start()
	oracle_opened.emit(_final_oracle_session)


# 给展示快照补上静态关卡原句文本，不把展示字段写回 HitResolution 历史。
func _get_oracle_history_with_sentence_text(current_level: LevelProfile) -> Array[Dictionary]:
	var normal_hit_history: Array[Dictionary] = _hit_resolution.get_normal_hit_history()
	var sentence_text_by_id: Dictionary = {}
	if current_level != null:
		for speech: LevelSpeech in current_level.get_normal_speech_pool():
			if speech != null and not speech.original_sentence_id.is_empty():
				sentence_text_by_id[speech.original_sentence_id] = speech.text

	for history_entry: Dictionary in normal_hit_history:
		var sentence_id: String = str(history_entry.get("original_sentence_id", ""))
		var sentence_text: String = str(sentence_text_by_id.get(sentence_id, ""))
		if sentence_text.is_empty():
			push_error("ContradictionOracleFlow: 无法从当前关卡解析神谕原句正文：%s" % sentence_id)
		history_entry["original_sentence_text"] = sentence_text
	return normal_hit_history


# 准心命中候选控件后按稳定原句 ID 读取 Session 冻结候选。
func _on_oracle_selection_target_hit(target: Control) -> void:
	if _final_oracle_session == null or not _final_oracle_session.is_open():
		return
	var sentence_id: String = _oracle_candidate_display.get_candidate_id_for_target(target)
	if sentence_id.is_empty():
		return
	for candidate: Dictionary in _final_oracle_session.get_display_candidates():
		if str(candidate.get("original_sentence_id", "")) == sentence_id:
			confirm_candidate(candidate)
			return


# 自动选择只改变请求来源；手动攻击和超时都复用 Session 的同一确认方法。
func _on_oracle_selection_expired() -> void:
	if _final_oracle_session == null or not _final_oracle_session.is_open():
		return
	var candidate: Dictionary = _final_oracle_session.select_timeout_candidate()
	if candidate.is_empty():
		push_error("ContradictionOracleFlow: 神谕倒计时结束，但没有可自动确认的候选。")
		return
	confirm_candidate(candidate)


# 首次确认后停表、锁住攻击，并保留已确认的原句正文供玩家查看。
func confirm_candidate(candidate: Dictionary) -> bool:
	if _stopped or _final_oracle_session == null or not _final_oracle_session.confirm_display_candidate(candidate):
		return false
	_oracle_selection_timer = null
	_attack_charge_input.clear_selection_targets()
	_attack_charge_input.lock_new_attacks()
	_attack_charge_input.set_combat_active(false)
	_oracle_candidate_display.show_confirmed_candidate(candidate)
	state_text_changed.emit("终结神谕已确认")
	return true


# 计时器剩余时间显示在现有战斗状态栏，中央候选仍只呈现原句正文。
func _on_oracle_selection_time_changed(seconds_remaining: float) -> void:
	state_text_changed.emit("神谕选择 · %.1f 秒" % seconds_remaining)


# 成功分支正式确认后提交本场历史，并把真正击败事实交给 14 / 16 各自保存。
func _on_oracle_confirmation_committed(run_data: SaveData, level_id: String, _candidate: Dictionary) -> void:
	if run_data != _run_data or _final_oracle_session == null or not _final_oracle_session.is_open():
		return
	if level_id != _final_oracle_session.get_level_id():
		return
	if _stopped or _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		return
	var current_level: LevelProfile = _current_level
	if current_level == null or current_level.level_id != level_id:
		return
	# 同次失败重试继续使用原拥有者；同关重开只读旧确认，不会再次收到此事件。
	_confirmation_hit_resolution = _hit_resolution
	commit_confirmed_rewards()



# 只把同场已确认事实交给休息入口；奖励已提交，展示只调用已有公开读取链。
func _open_rest_after_oracle(run_data: SaveData, session: FinalOracleSession) -> void:
	# 重开、换关或换周目后，旧帧尾请求不再影响当前尝试。
	if _stopped or not is_inside_tree() or run_data != _run_data or session == null or session != _final_oracle_session:
		return
	if _rest_session != null and _rest_session.is_open():
		return
	if _stopped or _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		return
	var current_level: LevelProfile = _current_level
	if current_level == null or session.get_level_id() != current_level.level_id or session.get_confirmed_selection().is_empty():
		return
	_rest_session = RestSession.new()
	if not _rest_session.open_result({
		"level_id": current_level.level_id,
		"result_kind": "breakthrough_oracle_complete",
		"pk_won": true,
		"contradiction_broken": true,
	}):
		push_error("ContradictionOracleFlow: 休息入口拒绝本场已确认神谕结果。")
		return
	_stop_battle()
	_contradiction_stage_active = false
	_repeat_queue.clear_contradiction_queue()
	_oracle_transition_timer.stop()
	_oracle_selection_timer = null
	_attack_charge_input.clear_selection_targets()
	_attack_charge_input.lock_new_attacks()
	_oracle_candidate_display.clear_display()
	state_text_changed.emit("休息时刻")
	rest_ready.emit(_rest_session)


# 正式满蓄释放时立即按冻结的矛盾原句判定；飞行计时只保留演出。
func _on_contradiction_shot_created(snapshot: AttackTargetSnapshot) -> void:
	if _stopped or not _contradiction_stage_active or _contradiction_break == null:
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
	# 同场结果只启动一次展示；重复通知不能清掉已生成复读或重新提交休息。
	if not _contradiction_stage_active or _contradiction_outcome_handled:
		return
	if _contradiction_break == null or outcome != _contradiction_break.get_outcome():
		return
	_contradiction_outcome_handled = true
	_attack_charge_input.lock_new_attacks()
	_barrage_area.clear_barrages()
	outcome_resolved.emit(outcome)
	if outcome == ContradictionBreakSystem.Outcome.BREAKTHROUGH:
		# 只消费成功结果；未击破分支继续沿用既有休息流程。
		_run_data.live_session.start_short_boost(
			LiveSessionData.BoostEvent.CONTRADICTION_BREAK,
			battle_config.break_boost_viewer_gain, battle_config.break_boost_like_gain,
			battle_config.break_boost_duration_seconds
		)
		state_text_changed.emit("矛盾击破成功 · 等待复读展示")
	else:
		state_text_changed.emit("未击破矛盾 · 等待复读展示")
		_open_rest_after_unbroken()


# 未击破结果立即固定；本发有限复读全部生成并离场后，将无神谕奖励的 PK 胜利交给休息。
func _open_rest_after_unbroken() -> void:
	if _contradiction_break == null or _contradiction_break.get_outcome() != ContradictionBreakSystem.Outcome.NOT_BROKEN:
		return
	if not _contradiction_stage_active or (_rest_session != null and _rest_session.is_open()):
		return
	# 沿用成功分支的展示结束条件；输入与生成已停止，空命中和超时无需等待。
	if _repeat_queue.get_pending_contradiction_count() > 0 or _barrage_area.has_visible_contradiction_repeats():
		return
	var current_level: LevelProfile = _current_level
	if current_level == null:
		return
	if not _commit_history_and_tendency():
		return
	_rest_session = RestSession.new()
	if not _rest_session.open_result({
		"level_id": current_level.level_id,
		"result_kind": "pk_win_unbroken",
		"pk_won": true,
		"contradiction_broken": false,
		"new_scripture_entries": [], "new_loser_cards": [], "new_assimilation": [],
	}):
		_rest_session = null
		_fail_commit("未击破 Rest 结果接收失败")
		return
	_contradiction_stage_active = false
	_repeat_queue.clear_contradiction_queue()
	_attack_charge_input.set_combat_active(false)
	state_text_changed.emit("PK 胜利 · 未击破矛盾 · 休息时刻")
	rest_ready.emit(_rest_session)
