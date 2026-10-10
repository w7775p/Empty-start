extends Node

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const CONTRADICTION_CONFIG: ContradictionWindowConfig = preload("res://systems/contradiction_break/contradiction_window_config.tres")

var _sandbox: Control
var _area: BarrageArea
var _attack: AttackChargeInput
var _aim: AimReticle
var _failures: Array[String] = []
var _check_count: int = 0
var _snapshots: Array[AttackTargetSnapshot] = []
var _submissions: Array[Dictionary] = []
var _mouse_position: Vector2 = Vector2.ZERO


# 使用真实 Sandbox 与 Autoload 运行，输入通过 Godot 事件管线进入正式攻击组件。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.new_game()
	SaveManager.data.streamer_name = "INT-01 测试主播"
	SaveManager.data.live_session.fan_count = 77
	SaveManager.data.tendency_state.orthodox_total = 11
	SaveManager.data.assimilation_data.defeated_streamer_ids.append(&"test_previous_streamer")
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	# 测试父节点在暂停中继续验收，正式 Sandbox 保持顶层场景的可暂停语义。
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_sandbox)
	await get_tree().process_frame
	await get_tree().process_frame
	_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_attack = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_aim = _sandbox.get_node("%AimReticle") as AimReticle
	_attack.shot_snapshot_created.connect(_on_snapshot)
	_attack.shot_hit_resolution_submitted.connect(_on_submission)
	await _verify_layout_and_generation()
	await _verify_real_attack_and_repeat()
	await _verify_tier_and_new_barrage_parameters()
	await _verify_pause_in_each_attack_phase()
	await _verify_failure_restart_and_full_pk()
	await _verify_three_candidate_overlap_selection()
	await _verify_oracle_timeout_pause_and_auto_pick()
	get_tree().paused = false
	_sandbox.queue_free()
	await get_tree().process_frame
	if _failures.is_empty():
		print("INT-01 PASS: %d checks, real Sandbox/InputEvent lifecycle" % _check_count)
		get_tree().quit(0)
	else:
		for failure: String in _failures:
			printerr("INT-01 FAIL: " + failure)
		print("INT-01 RESULT: %d/%d checks failed" % [_failures.size(), _check_count])
		get_tree().quit(1)


# 初始生成、移动、评论与舞台结构均读取正式场景事实。
func _verify_layout_and_generation() -> void:
	_check(not _sandbox.has_node("CenterContainer"), "中央旧技术 Panel 已移出")
	_check(_sandbox.has_node("BattleHud/PlayerStreamerArea") and _sandbox.has_node("BattleHud/BattleArea") and _sandbox.has_node("BattleHud/OpponentStreamerArea"), "左中右直播区域存在")
	_check(_area.size.x > 0.0 and _area.size.y > 0.0 and _area.is_visible_in_tree(), "中央弹幕区域可见且有尺寸")
	var opening_views: Array[BarrageView] = _views(false)
	_check(opening_views.size() == _level().base_batch_count, "开局真实普通批次生成")
	_check(SaveManager.data.live_session.comment_count == opening_views.size(), "普通生成成功数同步评论")
	var first_view: BarrageView = opening_views[0]
	var opening_x: float = first_view.position.x
	var opening_pk: float = _hit().get_player_pk()
	await _wait(1.08)
	_check(is_instance_valid(first_view) and first_view.position.x < opening_x, "普通弹幕持续移动")
	_check(_views(false).size() > opening_views.size(), "普通弹幕持续生成")
	_check(_hit().get_player_pk() < opening_pk, "真实回拉按帧降低 PK")
	_check(_live_comment_label().get_parsed_text() == "🔊" + str(SaveManager.data.live_session.comment_count), "Comment HUD 自动刷新")
	var pause_menu: Node = _sandbox.get_node("%PauseMenu")
	pause_menu.pause_game()
	await get_tree().process_frame
	var timer: Timer = _area.get_node("SpawnTimer") as Timer
	var timer_left: float = timer.time_left
	var count_before_pause: int = _views(false).size()
	await _wait(0.22)
	_check(is_equal_approx(timer.time_left, timer_left) and _views(false).size() == count_before_pause, "暂停冻结普通生成 Timer")
	pause_menu.resume_game()


# 普通命中从按住、释放、飞行到真实结算，再验证延迟复读与零收益。
func _verify_real_attack_and_repeat() -> void:
	_sandbox.restart_current_attempt()
	_area.clear_barrages()
	_opponent().stop_pullback()
	var target: BarrageView = _spawn_test_normal()
	_aim_at(target)
	_check(_aim.get_aim_center_global_position().distance_to(_mouse_position) < 1.0, "真实鼠标事件移动准心")
	_mouse_button(true)
	await _wait(0.07)
	_check(_attack.get_charge_progress() > 0.0 and _attack.get_charge_progress() < 1.0, "左键按住实际推进蓄力")
	_check((_sandbox.get_node("%ChargeProgress") as ProgressBar).value > 0.0, "真实蓄力显示进度")
	_mouse_button(false)
	await get_tree().process_frame
	_check(_attack.get_charge_progress() == 0.0 and _snapshots.is_empty(), "未满释放取消且未生成攻击")
	var target_id: int = target.get_instance_id()
	var original_id: String = target.runtime_record.original_sentence_id
	# 这一发真实收益跨过升档阈值，复读必须读取命中完成后的 Tier 1。
	_hit().apply_player_pk_delta(0.5595 - _hit().get_player_pk())
	var pk_before: float = _hit().get_player_pk()
	var tendency_before: int = _attempt_tendency_total()
	await _fire_at(target)
	_check(_submissions.size() == 1 and _snapshots.size() == 1, "满蓄产生唯一一发并实际提交")
	if _snapshots.is_empty() or _submissions.is_empty():
		return
	_check(_snapshots[0].get_target_instance_ids().has(target_id), "快照包含准心罩住的真实普通弹幕")
	_check(not is_instance_valid(target) or not target.is_inside_tree(), "正常结算结束对应弹幕")
	_check(is_equal_approx(_hit().get_player_pk(), pk_before + 0.0012), "普通强度 1 命中真实增加 PK")
	_check(absf((_sandbox.get_node("%PlayerShare") as ProgressBar).value - _hit().get_player_pk()) < 0.001, "可见 PK Bar 读取真实 PK")
	_check(_attempt_tendency_total() == tendency_before + 1, "普通命中仅增加本场倾向")
	_check(SaveManager.data.tendency_state.orthodox_total == 11, "此前已提交倾向保持")
	var queue: RepeatDelayQueue = _queue()
	_check(_stage().get_current_tier() == 1, "普通命中收益实际触发 Tier 上升")
	_check(queue._pending_items.size() == _stage().get_current_repeat_count_per_hit(), "普通命中计划使用结算后 Tier 数量")
	for item: Dictionary in queue._pending_items:
		var plan: RepeatPlan = item["plan"] as RepeatPlan
		_check(plan.generation_tier == _stage().get_current_tier() and plan.original_line_id == StringName(original_id), "复读计划保留原句和最终 Tier")
		_check(float(item["remaining_seconds"]) >= 0.0 and plan.wait_offsets_seconds[0] >= 0.5 and plan.wait_offsets_seconds[0] <= 3.0, "复读等待位于 0.5～3 秒配置")
	var comment_before: int = SaveManager.data.live_session.comment_count
	await _wait(3.12)
	var repeats: Array[BarrageView] = _views(true)
	_check(repeats.size() == _stage().get_current_repeat_count_per_hit(), "延迟结束后复读实际出现在场上")
	_check(queue.get_generation_stats().get_normal_count(StringName(original_id)) == repeats.size(), "复读统计只记录实际生成")
	_check(SaveManager.data.live_session.comment_count == comment_before + repeats.size(), "复读生成同步评论计数")
	if repeats.is_empty():
		return
	var repeat_target: BarrageView = repeats[0]
	var repeat_target_id: int = repeat_target.get_instance_id()
	# 保留一个真实复读实例，隔离同发目标以核实复读零收益。
	for view: BarrageView in repeats:
		if view != repeat_target:
			_area.end_barrage(view.get_instance_id())
	pk_before = _hit().get_player_pk()
	tendency_before = _attempt_tendency_total()
	var history_before: Array[Dictionary] = _hit().get_normal_hit_history()
	var submissions_before: int = _submissions.size()
	await _fire_at(repeat_target)
	_check(_submissions.size() == submissions_before + 1, "复读可从真实输入链命中")
	_check(_snapshots.back().get_target_instance_ids().has(repeat_target_id), "复读真实实例进入释放快照")
	var settled_targets: Array = _submissions.back().get("hit_resolution_result", {}).get("target_results", [])
	_check(settled_targets.size() == 1 and bool(settled_targets[0].get("is_repeat", false)) and bool(settled_targets[0].get("is_valid_hit", false)), "复读到达被结算为有效复读命中")
	_check(not is_instance_valid(repeat_target) or not repeat_target.is_inside_tree(), "命中的复读实例真实结束")
	_check(is_equal_approx(_hit().get_player_pk(), pk_before) and _attempt_tendency_total() == tendency_before, "复读命中 PK 与倾向均为零收益")
	_check(_hit().get_normal_hit_history() == history_before and _queue()._pending_items.is_empty(), "复读命中不写普通历史或递归入队")


# 将 PK 边界通过唯一所有者推进，核实倍率影响新实例且保留既有快照。
func _verify_tier_and_new_barrage_parameters() -> void:
	_sandbox.restart_current_attempt()
	_area.clear_barrages()
	_opponent().stop_pullback()
	var old_view: BarrageView = _spawn_test_normal()
	var old_speed: float = old_view._move_speed_pixels_per_second
	var old_expiry: int = old_view.runtime_record.expires_at_msec
	_hit().apply_player_pk_delta(0.22)
	_check(_stage().get_current_tier() == 3, "PK 更新同步跨档到 Tier 3")
	_check((_sandbox.get_node("%Tier") as Label).text.contains("3"), "中央顶部同步显示当前 Tier")
	var tier: CombatStageTierConfig = TIER_CATALOG.get_tier_config(3)
	_check(is_equal_approx(_opponent()._pullback_multiplier, tier.opponent_pullback_multiplier), "Tier 同步真实回拉倍率")
	var before_spawn_msec: int = Time.get_ticks_msec()
	var new_view: BarrageView = _spawn_test_normal()
	_check(is_equal_approx(new_view._move_speed_pixels_per_second, _level().base_move_speed_pixels_per_second * tier.movement_speed_multiplier), "新弹幕使用 Tier 移动倍率")
	_check(absi(new_view.runtime_record.expires_at_msec - before_spawn_msec - roundi(_area.base_lifetime_seconds * tier.lifetime_multiplier * 1000.0)) <= 20, "新弹幕使用 Tier 寿命倍率")
	_check(is_equal_approx(old_view._move_speed_pixels_per_second, old_speed) and old_view.runtime_record.expires_at_msec == old_expiry, "既有弹幕保留生成时速度与寿命")
	_area.clear_barrages()
	_area.start_normal_generation(_level())
	_check(_views(false).size() == roundi(_level().base_batch_count * tier.generation_count_multiplier), "Tier 真实影响批次数量")
	_check(is_equal_approx((_area.get_node("SpawnTimer") as Timer).wait_time, _level().base_spawn_interval_seconds / tier.generation_frequency_multiplier), "Tier 真实影响后续生成间隔")
	var count_before: int = _views(false).size()
	await _wait(_level().base_spawn_interval_seconds / tier.generation_frequency_multiplier + 0.1)
	_check(_views(false).size() > count_before, "新频率下后续批次实际生成")
	_area.stop_normal_generation()
	_hit().apply_player_pk_delta(0.68 - _hit().get_player_pk() + 0.0001)
	_opponent().resume_pullback()
	await _wait(0.18)
	_check(_stage().get_current_tier() == 2, "真实回拉跨降档阈值后 Tier 下降")


# 暂停真实 SceneTree，逐段验证蓄力、飞行、硬直与场上移动/回拉同时冻结。
func _verify_pause_in_each_attack_phase() -> void:
	_sandbox.restart_current_attempt()
	_area.clear_barrages()
	var target: BarrageView = _spawn_test_normal()
	_aim_at(target)
	_mouse_button(true)
	await _wait(0.06)
	var pause_menu: Node = _sandbox.get_node("%PauseMenu")
	pause_menu.pause_game()
	await get_tree().process_frame
	var charge_before: float = _attack.get_charge_progress()
	var position_before: Vector2 = target.position
	var expiry_before: int = target.runtime_record.expires_at_msec
	var pk_before: float = _hit().get_player_pk()
	await _wait(0.22)
	_check(is_equal_approx(_attack.get_charge_progress(), charge_before), "暂停冻结蓄力")
	_check(target.position == position_before and is_equal_approx(_hit().get_player_pk(), pk_before), "暂停冻结弹幕移动和回拉")
	pause_menu.resume_game()
	await _wait(0.23)
	_check(_attack.is_fully_charged() and _hit().get_player_pk() < pk_before, "恢复继续蓄力与回拉")
	_check(target.runtime_record.expires_at_msec - expiry_before >= 180, "恢复补偿弹幕暂停寿命")
	_aim_at(target)
	var submissions_before: int = _submissions.size()
	_mouse_button(false)
	pause_menu.pause_game()
	await _wait(0.22)
	_check(_attack.get_attack_phase() == AttackChargeInput.AttackPhase.PROJECTILE_FLIGHT and _submissions.size() == submissions_before, "暂停冻结飞行且没有到达结算")
	pause_menu.resume_game()
	await _wait_until_phase(AttackChargeInput.AttackPhase.RECOVERY)
	_check(_submissions.size() == submissions_before + 1, "恢复后飞行完成真实结算")
	pause_menu.pause_game()
	var repeat_wait_before: float = float(_queue()._pending_items[0]["remaining_seconds"]) if not _queue()._pending_items.is_empty() else -1.0
	await _wait(0.22)
	_check(_attack.get_attack_phase() == AttackChargeInput.AttackPhase.RECOVERY and not _attack.can_start_charging(), "暂停冻结硬直")
	_check(repeat_wait_before >= 0.0 and is_equal_approx(float(_queue()._pending_items[0]["remaining_seconds"]), repeat_wait_before), "暂停冻结普通复读等待")
	pause_menu.resume_game()
	await _wait(0.2)
	_check(_attack.can_start_charging(), "恢复后硬直完成并重新可攻击")


# 失败与满值均由生产流程处理，重开通过 UI 信号恢复同一关且保留周目成果。
func _verify_failure_restart_and_full_pk() -> void:
	_sandbox.restart_current_attempt()
	_area.clear_barrages()
	_opponent().stop_pullback()
	var target: BarrageView = _spawn_test_normal()
	await _fire_at(target)
	_check(_attempt_tendency_total() > 0 and not _queue()._pending_items.is_empty(), "失败前存在本场倾向与待复读")
	var save_before: SaveData = SaveManager.data
	var run_before: LevelRunState = _sandbox.get("_run_state") as LevelRunState
	_hit().apply_player_pk_delta(0.00002 - _hit().get_player_pk())
	_opponent().resume_pullback()
	await _wait(0.12)
	_check(_opponent().has_attempt_failed() and not bool(_sandbox.get("_normal_combat_active")), "PK 归零进入真实失败状态")
	_check(_sandbox.get_node("%FailureOverlay").visible, "失败遮罩可见")
	_check(_attempt_tendency_total() == 0 and _queue()._pending_items.is_empty(), "失败回滚倾向并清空待复读")
	_check(_views(false).is_empty() and _views(true).is_empty() and not _attack.can_start_charging(), "失败停止生成与攻击并清场")
	(_sandbox.get_node("%RestartButton") as Button).pressed.emit()
	_check(is_equal_approx(_hit().get_player_pk(), 0.5) and _stage().get_current_tier() == 0, "重开恢复初始 PK 和 Tier 0")
	_check(_attack.can_start_charging() and _queue()._pending_items.is_empty() and _attempt_tendency_total() == 0, "重开恢复 READY 并重置本场暂存")
	_check(SaveManager.data == save_before and (_sandbox.get("_run_state") as LevelRunState) == run_before, "重开保留同一周目及当前关对象")
	_check(SaveManager.data.tendency_state.orthodox_total == 11 and SaveManager.data.assimilation_data.defeated_streamer_ids.has(&"test_previous_streamer"), "重开保留已提交周目成果")
	_check(SaveManager.data.live_session.fan_count == 77 and SaveManager.data.live_session.viewer_count == 0 and SaveManager.data.live_session.like_count == 0 and SaveManager.data.live_session.comment_count == _views(false).size(), "重开直播表现归零后只计新开局实际评论")
	_check(_opponent().get_loss_streak_count() == 1 and not _opponent().has_attempt_failed(), "重开保留连败次数并清除本场失败标记")
	var pk_before: float = _hit().get_player_pk()
	await _wait(0.06)
	_check(_hit().get_player_pk() < pk_before, "重开后真实回拉恢复")
	_area.clear_barrages()
	_opponent().stop_pullback()
	_hit().apply_player_pk_delta(0.9995 - _hit().get_player_pk())
	target = _spawn_test_normal()
	var tendency_before: int = _attempt_tendency_total()
	await _fire_at(target)
	_check(is_equal_approx(_hit().get_player_pk(), 1.0) and not bool(_sandbox.get("_normal_combat_active")), "真实普通命中使 PK 满值并停止普通战斗")
	_check(bool(_sandbox.get_contradiction_oracle_flow().is_contradiction_active()), "满值只进入一次矛盾阶段")
	var contradiction_ids: Array[String] = []
	for view: BarrageView in _views(false):
		if view.runtime_record.is_contradiction:
			contradiction_ids.append(view.runtime_record.original_sentence_id)
	_check(contradiction_ids.has(_level().true_contradictions[0].original_sentence_id) and contradiction_ids.has(_level().false_contradictions[0].original_sentence_id), "当前关真假矛盾进入真实弹幕区域")
	var first_contradiction: BarrageView = null
	for view: BarrageView in _views(false):
		if view.runtime_record.is_contradiction:
			first_contradiction = view
			break
	if first_contradiction != null:
		_check(is_equal_approx(float(first_contradiction.get("_move_speed_pixels_per_second")), _level().base_move_speed_pixels_per_second * CONTRADICTION_CONFIG.movement_speed_multiplier), "矛盾弹幕使用 Paradox 速度倍率")
		_check(absf(float(first_contradiction.runtime_record.expires_at_msec - Time.get_ticks_msec()) / 1000.0 - CONTRADICTION_CONFIG.duration_seconds) < 0.5, "矛盾弹幕寿命使用 10 秒窗口")
	_check(is_equal_approx(float(_area.call("_get_effective_spawn_interval")), _level().base_spawn_interval_seconds / CONTRADICTION_CONFIG.generation_frequency_multiplier), "矛盾批次使用 Paradox 频率倍率")
	_check(_attempt_tendency_total() == tendency_before + 1 and not _hit().get_normal_hit_history().is_empty(), "满值这一发仍保留倾向与普通命中历史")
	_check(_attack.can_start_charging() and _attack.get_attack_phase() == AttackChargeInput.AttackPhase.READY and _queue()._pending_items.is_empty(), "满值清理旧攻击并开放矛盾阶段蓄力")
	var comment_before: int = SaveManager.data.live_session.comment_count
	await _wait(1.12)
	var normal_view_count: int = 0
	for view: BarrageView in _views(false):
		if not view.runtime_record.is_contradiction:
			normal_view_count += 1
	_check(is_equal_approx(_hit().get_player_pk(), 1.0) and SaveManager.data.live_session.comment_count >= comment_before and normal_view_count == 0, "满值保持且只生成矛盾内容")
	var break_system := _sandbox.get_contradiction_oracle_flow().get_contradiction_system() as ContradictionBreakSystem
	var repeat_config := _sandbox.get("battle_config") as SandboxBattleConfig
	_check(break_system != null and break_system.get_remaining_seconds() > 0.0 and break_system.get_remaining_shots() == 1, "矛盾限时窗口和一次发射机会已启动")
	var contradiction_target: BarrageView = null
	for view: BarrageView in _views(false):
		if view.runtime_record.is_contradiction and view.runtime_record.original_sentence_id == _level().true_contradictions[0].original_sentence_id:
			contradiction_target = view
			break
	_check(contradiction_target != null, "矛盾阶段存在可瞄准真矛盾")
	if contradiction_target != null:
		var history_before: int = _hit().get_normal_hit_history().size()
		await _fire_at(contradiction_target)
		_check(break_system.get_remaining_shots() == 0 and is_equal_approx(_hit().get_player_pk(), 1.0) and _hit().get_normal_hit_history().size() == history_before, "矛盾真实发射扣机会且不提交普通 PK 或历史")
		_check(break_system.get_outcome() == ContradictionBreakSystem.Outcome.BREAKTHROUGH, "释放瞬间命中真矛盾即刻击破")
		_check(not _attack.can_start_charging() and _views(false).is_empty(), "判定固定后关闭攻击并清理矛盾弹幕")
		_check(_queue().get_pending_contradiction_count() >= repeat_config.contradiction_repeat_count, "真矛盾命中创建独立矛盾复读计划")
		await _wait(0.7)
		_check(_area.has_visible_contradiction_repeats() and _queue().get_generation_stats().get_contradiction_count(StringName(_level().true_contradictions[0].original_sentence_id)) > 0, "矛盾复读真实展示并独立计数")
		# 已验证复读实际出现；缩短测试等待，模拟本场剩余展示全部结束。
		_queue().clear_contradiction_queue()
		_area.clear_barrages()
		await _wait(0.65)
		var oracle_session := _sandbox.get_contradiction_oracle_flow().get_oracle_session() as FinalOracleSession
		var candidate_display := _sandbox.get_node("%OracleCandidateDisplay") as FinalOracleCandidateDisplay
		_check(not bool(_sandbox.get_contradiction_oracle_flow().is_contradiction_active()) and oracle_session.is_open(), "击破成功和静音过渡后开放神谕")
		_check(candidate_display.visible and candidate_display.get_child_count() == 1, "一条真实普通命中候选显示在中央主游戏区")
		_check(not _area.is_normal_generation_enabled() and _views(false).is_empty() and _views(true).is_empty(), "神谕阶段停止普通生成并清除战斗弹幕")
		if candidate_display.get_child_count() == 1:
			var candidate_target := candidate_display.get_child(0) as Control
			var candidate_id: String = candidate_display.get_candidate_id_for_target(candidate_target)
			var history_before_oracle_shot: Array[Dictionary] = _hit().get_normal_hit_history()
			var pk_before_oracle_shot: float = _hit().get_player_pk()
			await _wait(0.2)
			_check(is_equal_approx(_hit().get_player_pk(), pk_before_oracle_shot), "神谕倒计时期间对手 PK 回拉停止")
			var tendency_total_before_oracle_shot: int = _get_total_tendency_points()
			var normal_generation_stats: RepeatGenerationStats = _queue().get_generation_stats()
			var repeat_count_before_oracle_shot: int = normal_generation_stats.get_normal_count(StringName(candidate_id))
			var submissions_before_oracle_shot: int = _submissions.size()
			await _fire_at(candidate_target)
			var confirmation_state := _sandbox.get_contradiction_oracle_flow().get_confirmation_state() as FinalOracleConfirmationState
			var selected_candidate: Dictionary = confirmation_state.get_confirmed_selection(oracle_session.get_level_id())
			_check(not candidate_id.is_empty() and str(selected_candidate.get("original_sentence_id", "")) == candidate_id, "普通攻击命中唯一候选并完成正式神谕确认")
			_check(is_equal_approx(_hit().get_player_pk(), pk_before_oracle_shot), "神谕选择攻击不改变玩家 PK")
			_check(_hit().get_normal_hit_history() == history_before_oracle_shot, "神谕选择攻击不追加普通命中历史")
			_check(_get_total_tendency_points() == tendency_total_before_oracle_shot, "神谕选择攻击不产生倾向收益")
			_check(normal_generation_stats.get_normal_count(StringName(candidate_id)) == repeat_count_before_oracle_shot and _submissions.size() == submissions_before_oracle_shot, "神谕选择攻击不生成复读或 HitResolution 提交")
			_check(_sandbox.get_contradiction_oracle_flow().get_selection_timer() == null and not _attack.can_start_charging(), "确认后停止倒计时并锁住后续攻击")
			_check(_sandbox.get_contradiction_oracle_flow().get_result() == _sandbox.get("_rest_session")
				and _sandbox.get_contradiction_oracle_flow().get_result().get_result_snapshot()["result_kind"] == "breakthrough_oracle_complete",
				"正式确认交付同一成功 Rest 对象")
			_check(not candidate_display.visible and SaveManager.data.scripture_data.get_entry_for_level(StringName(oracle_session.get_level_id())) != null,
				"Rest 收起候选并读取真实已保存经文")

	# 假矛盾等待使用 INT-04 已有的 TEST_ONLY 短复读数值；正式 120 条仍在真击破计划检查中覆盖。
	var short_repeat_config: SandboxBattleConfig = (_sandbox.battle_config as SandboxBattleConfig).duplicate(true)
	short_repeat_config.contradiction_repeat_count = 3
	short_repeat_config.contradiction_repeat_lifetime_seconds = 0.3
	_sandbox.battle_config = short_repeat_config
	_sandbox.restart_current_attempt()
	_hit().apply_player_pk_delta(1.0 - _hit().get_player_pk())
	await _wait(0.05)
	var false_target: BarrageView = null
	for view: BarrageView in _views(false):
		if view.runtime_record.is_contradiction and view.runtime_record.original_sentence_id == _level().false_contradictions[0].original_sentence_id and false_target == null:
			false_target = view
		else:
			_area.end_barrage(view.get_instance_id())
	_check(false_target != null, "重开后存在可瞄准假矛盾")
	if false_target != null:
		false_target.position = Vector2(_area.size.x * 0.65, _area.size.y * 0.38)
		await _fire_at(false_target)
		var failed_break := _sandbox.get_contradiction_oracle_flow().get_contradiction_system() as ContradictionBreakSystem
		_check(failed_break.get_outcome() == ContradictionBreakSystem.Outcome.NOT_BROKEN and not _attack.can_start_charging(), "假矛盾用尽机会后保持 PK 胜利但未击破")
		_check(_sandbox.get_contradiction_oracle_flow().is_contradiction_active() and _sandbox.get_contradiction_oracle_flow().get_result() == null, "假矛盾命中等待真实有限复读")
		# 按真实队列及离场事实等待，固定秒数无法覆盖容量与延迟生成。
		var rest_deadline: int = Time.get_ticks_msec() + 15000
		while _sandbox.get_contradiction_oracle_flow().get_result() == null and Time.get_ticks_msec() < rest_deadline:
			await get_tree().process_frame
		_check(not bool(_sandbox.get_contradiction_oracle_flow().is_contradiction_active()) and (_sandbox.get("_rest_session") as RestSession).is_open(), "未击破交给休息入口后结束矛盾阶段")
		_check(_queue().get_pending_contradiction_count() == 0 and not _area.has_visible_contradiction_repeats(), "休息阶段不再推进矛盾复读")


# 用真实 Sandbox/AttackChargeInput 验证三句显示、同发多目标最近中心裁决。
func _verify_three_candidate_overlap_selection() -> void:
	await _replace_sandbox()
	var session: FinalOracleSession = await _open_oracle_with_hit_history(3)
	var display := _sandbox.get_node("%OracleCandidateDisplay") as FinalOracleCandidateDisplay
	var labels: Array[Control] = []
	for child: Node in display.get_children():
		if child is Control:
			labels.append(child as Control)
	_check(session.is_open() and display.visible and labels.size() == 3, "三个普通命中候选固定显示在中央主游戏区")
	if labels.size() != 3:
		return
	var first_target: Control = labels[0]
	var second_target: Control = labels[1]
	var first_candidate_id: String = display.get_candidate_id_for_target(first_target)
	var first_rect: Rect2 = first_target.get_global_rect()
	var second_rect: Rect2 = second_target.get_global_rect()
	var overlap_midpoint: float = (first_rect.end.y + second_rect.position.y) * 0.5
	var aim_point: Vector2 = Vector2(first_rect.get_center().x, overlap_midpoint - 4.0)
	var first_instance_id: int = first_target.get_instance_id()
	var second_instance_id: int = second_target.get_instance_id()
	var submissions_before: int = _submissions.size()
	var snapshots_before: int = _snapshots.size()
	var pk_before: float = _hit().get_player_pk()
	_aim_at_point(aim_point)
	_mouse_button(true)
	await _wait(0.24)
	_aim_at_point(aim_point)
	_mouse_button(false)
	await _wait(0.29)
	if _snapshots.size() <= snapshots_before:
		_check(false, "选择攻击产生释放快照")
		return
	var oracle_shot: AttackTargetSnapshot = _snapshots.back()
	var target_ids: Array[int] = oracle_shot.get_target_instance_ids()
	print("INT01 overlap first=", first_rect, " second=", second_rect,
		" release_aim=", oracle_shot.get_aim_center_global_position(), " targets=", target_ids)
	_check(target_ids.has(first_instance_id) and target_ids.has(second_instance_id), "同一发快照覆盖相邻两条神谕候选")
	var confirmation_state := _sandbox.get_contradiction_oracle_flow().get_confirmation_state() as FinalOracleConfirmationState
	var selected_candidate: Dictionary = confirmation_state.get_confirmed_selection(session.get_level_id())
	_check(str(selected_candidate.get("original_sentence_id", "")) == first_candidate_id, "同发命中多句时只确认准心中心最近的一句")
	_check(_submissions.size() == submissions_before and is_equal_approx(_hit().get_player_pk(), pk_before), "多目标神谕攻击不进入 HitResolution 或改变 PK")


# 暂停冻结 10 秒计时；恢复后超时按现有候选池正式排序自动确认。
func _verify_oracle_timeout_pause_and_auto_pick() -> void:
	await _replace_sandbox()
	var session: FinalOracleSession = await _open_oracle_with_hit_history(3)
	var timer := _sandbox.get_contradiction_oracle_flow().get_selection_timer() as FinalOracleSelectionTimer
	var pause_menu: Node = _sandbox.get_node("%PauseMenu")
	var expected_candidate: Dictionary = session.select_timeout_candidate()
	var submissions_before: int = _submissions.size()
	var time_before_pause: float = timer.get_remaining_seconds()
	var status_before_pause: String = (_sandbox.get_node("%BattleStateFeedback") as Label).text
	pause_menu.pause_game()
	await _wait(0.25)
	_check(is_equal_approx(timer.get_remaining_seconds(), time_before_pause), "全局暂停期间神谕倒计时冻结")
	_check((_sandbox.get_node("%BattleStateFeedback") as Label).text == status_before_pause, "暂停时战斗状态栏保留剩余时间")
	pause_menu.resume_game()
	await _wait(10.2)
	var confirmation_state := _sandbox.get_contradiction_oracle_flow().get_confirmation_state() as FinalOracleConfirmationState
	var selected_candidate: Dictionary = confirmation_state.get_confirmed_selection(session.get_level_id())
	_check(str(selected_candidate.get("original_sentence_id", "")) == str(expected_candidate.get("original_sentence_id", "")), "10 秒到期后按 FO-08 顺序自动确认正确原句")
	_check(_sandbox.get_contradiction_oracle_flow().get_selection_timer() == null and not _attack.can_start_charging(), "自动确认后停表并关闭攻击选择")
	_check(_hit().get_player_pk() >= 1.0 and _submissions.size() == submissions_before, "超时神谕确认不提交普通命中 PK")


# 每个运行场景使用新的周目对象，候选事实仍由真实 HitResolution 生成。
func _replace_sandbox() -> void:
	get_tree().paused = false
	if _sandbox != null:
		remove_child(_sandbox)
		_sandbox.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	SaveManager.new_game()
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_sandbox)
	await get_tree().process_frame
	await get_tree().process_frame
	_area = _sandbox.get_node("%BarrageArea") as BarrageArea
	_attack = _sandbox.get_node("%AttackChargeInput") as AttackChargeInput
	_aim = _sandbox.get_node("%AimReticle") as AimReticle
	_attack.shot_snapshot_created.connect(_on_snapshot)
	_attack.shot_hit_resolution_submitted.connect(_on_submission)


# 通过真实击破结果和静音过渡开放 FinalOracle，历史由 HitResolution 保存。
func _open_oracle_with_hit_history(candidate_count: int) -> FinalOracleSession:
	var level: LevelProfile = _level()
	var history_count: int = mini(candidate_count, level.normal_speech_pool.size())
	for index in range(history_count):
		var speech: LevelSpeech = level.normal_speech_pool[index]
		_hit().record_normal_word_hit(speech.original_sentence_id, speech.tendency_id)
	_sandbox.call("debug_set_player_pk", 1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var break_system := _sandbox.get_contradiction_oracle_flow().get_contradiction_system() as ContradictionBreakSystem
	if break_system == null:
		_check(false, "普通 PK 满值后进入矛盾阶段")
		return null
	break_system.register_launched_shot()
	var hit_ids: Array[String] = [break_system.get_true_contradictions()[0].original_sentence_id]
	break_system.resolve_shot_hit_ids(hit_ids)
	await _wait(0.7)
	var session := _sandbox.get_contradiction_oracle_flow().get_oracle_session() as FinalOracleSession
	_check(session != null and session.is_open(), "矛盾击破成功和静音过渡后开放 FinalOracle")
	return session


# 仅使用正式公开生成入口；将真实实例放在独立位置便于瞄准。
func _spawn_test_normal() -> BarrageView:
	var view: BarrageView = _area.spawn_normal_barrage(_level(), _level().normal_speech_pool[0])
	view.position = Vector2(_area.size.x * 0.65, _area.size.y * 0.38)
	return view


# 发射前重新瞄准移动中的真实目标，整个攻击经 MouseButton 输入事件推进。
func _fire_at(target: Control) -> void:
	_aim_at(target)
	_mouse_button(true)
	await _wait(0.24)
	_check(_attack.is_fully_charged(), "正式配置蓄力达到 100%")
	_aim_at(target)
	var was_contradiction_stage: bool = bool(_sandbox.get_contradiction_oracle_flow().is_contradiction_active())
	_mouse_button(false)
	if was_contradiction_stage:
		_check((_sandbox.get_contradiction_oracle_flow().get_contradiction_system() as ContradictionBreakSystem).is_result_locked(), "矛盾在释放同帧判定，不等待飞行到达")
	await _wait(0.29)


func _aim_at(target: Control) -> void:
	_aim_at_point(target.get_global_rect().get_center())


func _aim_at_point(canvas_position: Vector2) -> void:
	_mouse_position = canvas_position
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	# parse_input_event 接收窗口坐标，headless 窗口仍会按 final_transform 转回逻辑视口。
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim.get_canvas_transform() * _mouse_position)
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse_button(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	var window_position: Vector2 = get_viewport().get_final_transform() * (_aim.get_canvas_transform() * _mouse_position)
	event.position = window_position
	event.global_position = window_position
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 验收等待继续处理暂停中的测试节点，业务 Timer 仍遵循 SceneTree 暂停。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


# 统计已提交与本场暂存之和，确认时提交转移不能被误判为新增倾向。
func _get_total_tendency_points() -> int:
	var tendency_state: TendencyState = SaveManager.data.tendency_state
	return (
		tendency_state.orthodox_total
		+ tendency_state.heretical_total
		+ tendency_state.absurd_total
		+ tendency_state.attempt_orthodox_total
		+ tendency_state.attempt_heretical_total
		+ tendency_state.attempt_absurd_total
	)


func _wait_until_phase(phase: AttackChargeInput.AttackPhase) -> void:
	var deadline: int = Time.get_ticks_msec() + 1000
	while _attack.get_attack_phase() != phase and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _views(is_repeat: bool) -> Array[BarrageView]:
	var result: Array[BarrageView] = []
	for child: Node in _area.get_children():
		if child is BarrageView and not child.is_queued_for_deletion() and (child as BarrageView).runtime_record.is_repeat == is_repeat:
			result.append(child as BarrageView)
	return result


func _hit() -> HitResolution:
	return _sandbox.get("_hit_resolution") as HitResolution


func _stage() -> CombatStage:
	return _sandbox.get("_combat_stage") as CombatStage


func _opponent() -> OpponentPKBar:
	return _sandbox.get("_opponent_pk_bar") as OpponentPKBar


func _queue() -> RepeatDelayQueue:
	return _sandbox.get("_repeat_queue") as RepeatDelayQueue


func _level() -> LevelProfile:
	return (_sandbox.get("_run_state") as LevelRunState).get_current_level_profile()


func _attempt_tendency_total() -> int:
	var tendency: TendencyState = SaveManager.data.tendency_state
	return tendency.attempt_orthodox_total + tendency.attempt_heretical_total + tendency.attempt_absurd_total


func _live_comment_label() -> RichTextLabel:
	return _sandbox.get_node("%LiveDataHud").find_child("CommentMetric", true, false) as RichTextLabel


func _on_snapshot(snapshot: AttackTargetSnapshot) -> void:
	_snapshots.append(snapshot)


func _on_submission(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_submissions.append(submission)


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("INT-01 OK: " + description)
	else:
		_failures.append(description)
