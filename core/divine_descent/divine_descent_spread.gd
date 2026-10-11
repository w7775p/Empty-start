class_name DivineDescentSpread
extends Node

signal repeat_generated(original_sentence_id: StringName, view: BarrageView, current_weight: int)
signal sentence_locked(candidate: Dictionary)
signal convergence_started(candidate: Dictionary)
signal locked_sentence_emphasized(original_sentence_id: StringName, affected_view_count: int)
signal completed(session: DivineDescentSession)

var _candidates: Array[Dictionary] = []
var _barrage_area: BarrageArea
var _random_generator: RandomNumberGenerator
var _timer: Timer
var _repeat_lifetime_seconds: float = 0.0
var _display_template: String = ""
var _generation_blocked: bool = false
var _combat_mode: DivineDescentCombatMode
var _locked_candidate: Dictionary = {}
var _converging: bool = false
var _session: DivineDescentSession
var _full_screen_emphasis: DivineDescentEmphasis
var _completed: bool = false


# 原生 Timer 独立于玩家输入推进；全局暂停沿用 SceneTree 的暂停模式。
func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = false
	_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_timer.timeout.connect(_on_generation_timeout)
	add_child(_timer)
	set_process(false)


# 从冻结来源初始化一个扩散工作池；频率、寿命和模板由组合方读取真实配置后注入。
func start(
		session: DivineDescentSession, barrage_area: BarrageArea, speech_catalog: LevelCatalog,
		interval_seconds: float, repeat_lifetime_seconds: float, display_template: String,
		random_generator: RandomNumberGenerator = null, trait_colors: Dictionary = {}
) -> bool:
	if _timer == null or not _candidates.is_empty() or session == null or not session.is_entered():
		return false
	if not is_instance_valid(barrage_area) or not barrage_area.is_inside_tree():
		return false
	if interval_seconds <= 0.0 or repeat_lifetime_seconds <= 0.0:
		return false
	var frozen: Dictionary = session.get_entry_snapshot()
	var history_candidates: Array[Dictionary] = frozen["history_candidates"]
	var scripture_entries: Array[Dictionary] = frozen["scripture_entries"]
	var base_candidates: Array[Dictionary] = DivineDescentCandidateFilter.calculate_base_weights(history_candidates)
	var candidates: Array[Dictionary] = DivineDescentCandidateFilter.apply_scripture_bonus(base_candidates, scripture_entries)
	if candidates.is_empty() or not _resolve_original_texts(candidates, speech_catalog):
		return false
	_candidates = candidates
	_session = session
	_barrage_area = barrage_area
	# 仅消费进入时冻结的已获特性；候选、权重和锁句算法不读取表现配置。
	var inherited_trait_ids: Array[StringName] = frozen["assimilation_content"]["inherited_trait_ids"]
	_barrage_area.enter_terminal_presentation(inherited_trait_ids, trait_colors)
	_repeat_lifetime_seconds = repeat_lifetime_seconds
	_display_template = display_template
	_random_generator = random_generator if random_generator != null else RandomNumberGenerator.new()
	if random_generator == null:
		_random_generator.randomize()
	_timer.start(interval_seconds)
	_try_lock_after_new_word_decay()
	return true


# 绑定 DD-05 的真实衰减事实；晚绑定已归零的模式时立即读取当前扩散池。
func bind_new_word_decay(combat_mode: DivineDescentCombatMode) -> bool:
	if combat_mode == null:
		return false
	if _combat_mode != null:
		return _combat_mode == combat_mode
	_combat_mode = combat_mode
	_combat_mode.new_word_rate_changed.connect(_on_new_word_rate_changed)
	_try_lock_after_new_word_decay()
	return true


# 锁句后返回首次独立快照，调用方不能修改已经确定的锁句结果。
func get_locked_candidate() -> Dictionary:
	return _locked_candidate.duplicate(true)


# 锁句状态从已保存结果读取，未归零或空候选时仍为 false。
func is_sentence_locked() -> bool:
	return not _locked_candidate.is_empty()


# 组合方将终局玩家操作路由到这里；只重播锁句表现，倍率和时长由已批准配置或测试夹具注入。
func emphasize_locked_sentence(scale_multiplier: float, return_seconds: float) -> bool:
	if not is_inside_tree() or get_tree().paused or not is_sentence_locked() or _completed:
		return false
	if not is_finite(scale_multiplier) or scale_multiplier <= 1.0 or not is_finite(return_seconds) or return_seconds <= 0.0:
		return false
	if not is_instance_valid(_barrage_area) or not _barrage_area.is_inside_tree():
		return false
	var sentence_id := StringName(str(_locked_candidate["original_sentence_id"]))
	var affected: int = 0
	var visible_records: Array[BarrageRuntimeRecord] = _barrage_area.get_visible_barrage_records()
	for child in _barrage_area.get_children():
		if not child is BarrageView:
			continue
		var view := child as BarrageView
		if view.runtime_record == null or not visible_records.has(view.runtime_record):
			continue
		if StringName(view.runtime_record.original_sentence_id) == sentence_id:
			if view.pulse_presentation(scale_multiplier, return_seconds):
				affected += 1
	# 音频只请求既有锁句事件；空场仍可强化声音，不补造视图、权重或存档事实。
	var audio_manager: Node = get_node_or_null("/root/AudioManager")
	if audio_manager != null:
		audio_manager.play_event(&"divine_descent_lock")
	locked_sentence_emphasized.emit(sentence_id, affected)
	return true


# 即时读取当前区域；空可见集合返回零，占比不缓存。
func get_locked_visible_ratio() -> float:
	if not is_sentence_locked() or not is_instance_valid(_barrage_area) or not _barrage_area.is_inside_tree():
		return 0.0
	return DivineDescentCandidateFilter.calculate_visible_ratio(
		_barrage_area.get_visible_barrage_records(), str(_locked_candidate["original_sentence_id"])
	)


# 读取首次收束状态，后续弹幕退出不会撤销已进入的阶段。
func is_converging() -> bool:
	return _converging


# 收束后由组合方启动一次全屏演出；时长显式注入，不猜测正式节奏。
func begin_full_screen_emphasis(fade_seconds: float, hold_seconds: float) -> bool:
	if not is_inside_tree() or get_tree().paused or not _converging or _full_screen_emphasis != null:
		return false
	if not is_finite(fade_seconds) or fade_seconds <= 0.0 or not is_finite(hold_seconds) or hold_seconds <= 0.0:
		return false
	_full_screen_emphasis = DivineDescentEmphasis.new()
	add_child(_full_screen_emphasis)
	_full_screen_emphasis.finished.connect(_on_full_screen_emphasis_finished)
	_full_screen_emphasis.play(str(_locked_candidate["original_sentence_text"]), fade_seconds, hold_seconds)
	return true


# 完成事实只来自真实 Tween 结束；发送进入时的同一 Session，Ending 无需重读存档。
func _on_full_screen_emphasis_finished() -> void:
	if _completed:
		return
	_completed = true
	completed.emit(_session)


# 演出被销毁或中断时不会形成完成事实。
func is_completed() -> bool:
	return _completed


# 锁句后按实际可见占比检查；空场为零，达到 90% 只进入一次。
func _process(_delta: float) -> void:
	if _converging or not is_running() or not is_sentence_locked():
		return
	if get_locked_visible_ratio() < 0.9:
		return
	_converging = true
	stop()
	convergence_started.emit(get_locked_candidate())


# 只在真实归零时响应；后续重复通知不能覆盖首次结果。
func _on_new_word_rate_changed(_rate_multiplier: float, _progress: float) -> void:
	_try_lock_after_new_word_decay()


# 完成标记使用近似比较，所以还需严格检查新话率为零，避免极小正值提前锁句。
func _try_lock_after_new_word_decay() -> void:
	if _combat_mode == null or is_sentence_locked() or _candidates.is_empty():
		return
	if not _combat_mode.is_new_word_decay_complete() or _combat_mode.get_new_word_rate_multiplier() != 0.0:
		return
	_locked_candidate = DivineDescentCandidateFilter.select_highest_weight_candidate(get_current_candidates())
	if is_sentence_locked():
		# 没有积压队列；收窄后续抽取池即取消其他句的生成，保留 Timer 和在场视图。
		_candidates.clear()
		_candidates.append(_locked_candidate.duplicate(true))
		set_process(true)
		sentence_locked.emit(get_locked_candidate())


# 每次重新读取当前权重抽一句；生成失败保持权重，下一次 Timer 到期再尝试。
func generate_next_repeat() -> BarrageView:
	if not is_running() or get_tree().paused:
		return null
	if not is_instance_valid(_barrage_area) or not _barrage_area.is_inside_tree():
		stop()
		return null
	var weights := PackedFloat32Array()
	for candidate: Dictionary in _candidates:
		weights.append(float(candidate["weight"]))
	var index: int = _random_generator.rand_weighted(weights)
	var selected: Dictionary = _candidates[index]
	var plan: RepeatPlan = RepeatPlan.create_normal_hit_plan(
		StringName(str(selected["original_sentence_id"])), str(selected["original_sentence_text"]),
		DivineDescentCombatMode.TERMINAL_TIER, 1, _repeat_lifetime_seconds, str(selected["tendency"])
	)
	if not _display_template.is_empty():
		plan.apply_display_template(_display_template)
	# 神降临重播冻结历史原句，保持复读静止随机落点与原有容量 / 寿命规则。
	var view: BarrageView = _barrage_area.spawn_repeat_barrage(plan, true)
	_generation_blocked = view == null
	if view == null:
		return null
	# 只有真实生成成功才更新本原句，冻结历史、基础权重和其他候选均保持原值。
	selected["weight"] = int(selected["weight"]) + 1
	repeat_generated.emit(plan.original_line_id, view, int(selected["weight"]))
	return view


# 停止生成和收束检查并保留工作池；收束时沿用同一停止入口。
func stop() -> void:
	if _timer != null:
		_timer.stop()
	set_process(false)


# 当前动态权重唯一归本扩散组件；读取副本不能回写工作池。
func get_current_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate: Dictionary in _candidates:
		result.append(candidate.duplicate(true))
	return result


# 计时状态由 Timer 拥有，不另存一份运行开关。
func is_running() -> bool:
	return _timer != null and not _timer.is_stopped()


# 空生成结果可能来自满容量、无位置或未准备好的区域，统一等待下一轮尝试。
func is_generation_blocked() -> bool:
	return _generation_blocked


# 唯一自动触发来源是计时；不订阅攻击、复读命中或弹幕移除事件。
func _on_generation_timeout() -> void:
	generate_next_repeat()


# 命中存档通常只有 ID；从真实静态词库补正文并复制到工作池，不伪造或丢弃候选。
func _resolve_original_texts(candidates: Array[Dictionary], speech_catalog: LevelCatalog) -> bool:
	var texts_by_id: Dictionary = {}
	if speech_catalog != null:
		for profile: LevelProfile in speech_catalog.profiles:
			if profile == null:
				continue
			for speech: LevelSpeech in profile.get_normal_speech_pool():
				if speech != null and not texts_by_id.has(speech.original_sentence_id):
					texts_by_id[speech.original_sentence_id] = speech.text
	for candidate: Dictionary in candidates:
		if not str(candidate.get("original_sentence_text", "")).is_empty():
			continue
		var sentence_id: String = str(candidate["original_sentence_id"])
		var text: String = str(texts_by_id.get(sentence_id, ""))
		if text.is_empty():
			push_warning("DivineDescentSpread: 缺少历史原句正文：%s" % sentence_id)
			return false
		candidate["original_sentence_text"] = text
	return true
