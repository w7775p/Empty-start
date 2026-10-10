extends Node

const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")

var _sandbox: Control
var _area: BarrageArea
var _attack: AttackChargeInput
var _aim: AimReticle
var _failures: Array[String] = []
var _check_count: int = 0
var _snapshots: Array[AttackTargetSnapshot] = []
var _submissions: Array[Dictionary] = []
var _flow_shot_events: Array[Dictionary] = []
var _flow_tier_events: Array[Dictionary] = []
var _last_attempt_failure: Dictionary = {}
var _last_attempt_restart: Dictionary = {}
var _attempt_failed_events: int = 0
var _attempt_restarted_events: int = 0
var _pk_maximum_events: int = 0
var _normal_completed_events: int = 0
var _contradiction_entered_events: int = 0
var _player_portrait_shot_motion_events: int = 0
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
	var battle_hud: Control = _sandbox.get_node("%BattleHud") as Control
	var player_portrait_motion: StreamerPortraitMotion = battle_hud.get("player_portrait_motion") as StreamerPortraitMotion
	var opponent_portrait_motion: StreamerPortraitMotion = battle_hud.get("opponent_portrait_motion") as StreamerPortraitMotion
	player_portrait_motion.shot_motion_started.connect(_on_player_portrait_shot_motion_started)
	var initial_level: LevelProfile = _flow().get_current_level_profile()
	_check(initial_level != null and is_equal_approx(opponent_portrait_motion.idle_period,
		_expected_portrait_idle_period(initial_level.streamer_id)), "尝试启动按当前主播 ID 配置对手立绘待机")
	_attack.shot_snapshot_created.connect(_on_snapshot)
	_attack.shot_hit_resolution_submitted.connect(_on_submission)
	_flow().shot_resolved.connect(_on_flow_shot_resolved)
	_flow().tier_changed.connect(_on_flow_tier_changed)
	_flow().attempt_failed.connect(_on_flow_attempt_failed)
	_flow().attempt_restarted.connect(_on_flow_attempt_restarted)
	_flow().pk_maximum_reached.connect(_on_flow_pk_maximum_reached)
	_flow().normal_combat_completed.connect(_on_flow_normal_combat_completed)
	_flow().contradiction_entered.connect(_on_flow_contradiction_entered)
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
	_check(_area.size.x > 0.0 and _area.size.y > 0.0 and _area.is_visible_in_tree(), "中央弹幕区域可见且有尺寸")
	var opening_views: Array[BarrageView] = _views(false)
	_check(opening_views.size() == _level().base_batch_count, "开局真实普通批次生成")
	_check(SaveManager.data.live_session.comment_count == opening_views.size(), "普通生成成功数同步评论")
	var first_view: BarrageView = opening_views[0]
	var opening_x: float = first_view.position.x
	var opening_pk: float = _hit().get_player_pk()
	await _wait(1.50)
	_check(is_instance_valid(first_view) and first_view.position.x < opening_x, "普通弹幕持续移动")
	_check(_views(false).size() > opening_views.size(), "普通弹幕持续生成")
	_check(is_equal_approx(_hit().get_player_pk(), opening_pk), "T0 等待对手连线时 PK 保持稳定")
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
	_check(_player_portrait_shot_motion_events == 1, "正式释放快照驱动玩家立绘射击动作")
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
	_check(_flow_shot_events.size() == 1 and int(_flow_shot_events.back().get("current_tier", -1)) == 1
		and _flow_shot_events.back().get("repeat_stats") == queue.get_generation_stats(), "单发事件发布升档后的 Tier 与同一复读统计")
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
	_check(_hit().get_normal_hit_history() == history_before, "复读命中不写普通历史")
	_check(_flow_shot_events.size() == submissions_before + 1 and bool(_flow_shot_events.back().get("is_repeat_hit", false)), "复读命中事件保留零收益事实")


# 将 PK 边界通过唯一所有者推进，核实倍率影响新实例且保留既有快照。
func _verify_tier_and_new_barrage_parameters() -> void:
	_sandbox.restart_current_attempt()
	_area.clear_barrages()
	_opponent().stop_pullback()
	var old_view: BarrageView = _spawn_test_normal()
	var old_expiry: int = old_view.runtime_record.expires_at_msec
	var tier_event_count_before: int = _flow_tier_events.size()
	_hit().apply_player_pk_delta(0.22)
	_check(_stage().get_current_tier() == 3, "PK 更新同步跨档到 Tier 3")
	_check(_flow_tier_events.size() == tier_event_count_before + 1 and int(_flow_tier_events.back().get("tier", -1)) == 3,
		"Tier 公开事件只发布稳定后的当前档位")
	_check((_sandbox.get_node("%Tier") as Label).text.contains("3"), "中央顶部同步显示当前 Tier")
	var tier: CombatStageTierConfig = TIER_CATALOG.get_tier_config(3)
	var before_spawn_msec: int = Time.get_ticks_msec()
	var new_view: BarrageView = _spawn_test_normal()
	_check(absi(new_view.runtime_record.expires_at_msec - before_spawn_msec - roundi(_area.base_lifetime_seconds * tier.lifetime_multiplier * 1000.0)) <= 20, "新弹幕使用 Tier 寿命倍率")
	# 比较同一段实际帧中的移动距离，验证升档只改变新实例，避免读取私有速度缓存。
	var old_x: float = old_view.position.x
	var new_x: float = new_view.position.x
	await _wait(0.12)
	var old_distance: float = old_x - old_view.position.x
	var new_distance: float = new_x - new_view.position.x
	_check(old_distance > 0.0 and absf(new_distance / old_distance - tier.movement_speed_multiplier
		/ TIER_CATALOG.get_tier_config(0).movement_speed_multiplier) < 0.02, "升档后新旧弹幕实际移动保持各自倍率")
	_check(old_view.runtime_record.expires_at_msec == old_expiry, "既有弹幕保留生成时寿命")
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
	_check(int(_flow_tier_events.back().get("tier", -1)) == 2, "降档结果沿用同一 Tier 公开事件")


# 暂停真实 SceneTree，逐段验证蓄力、飞行、硬直与场上移动/回拉同时冻结。
func _verify_pause_in_each_attack_phase() -> void:
	_sandbox.restart_current_attempt()
	_area.clear_barrages()
	_sandbox.call("debug_set_player_pk", 0.6)
	await get_tree().process_frame
	_check(_stage().get_current_tier() == 1, "进入 T1 后启用对手回拉")
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
	await _wait(0.22)
	_check(_attack.get_attack_phase() == AttackChargeInput.AttackPhase.RECOVERY and not _attack.can_start_charging(), "暂停冻结硬直")
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
	_check(_attempt_tendency_total() > 0, "失败前存在本场倾向")
	var save_before: SaveData = SaveManager.data
	var level_before: LevelProfile = _flow().get_current_level_profile()
	var failures_before: int = _attempt_failed_events
	var restarts_before: int = _attempt_restarted_events
	_sandbox.call("debug_set_player_pk", 0.0)
	_opponent().resume_pullback()
	await _wait(0.12)
	_check(_opponent().has_attempt_failed() and not _flow().is_normal_combat_active(), "PK 归零进入真实失败状态")
	_check(_sandbox.get_node("%FailureOverlay").visible, "失败遮罩可见")
	_check(_attempt_tendency_total() == 0, "失败回滚本场倾向")
	_check(_attempt_failed_events == failures_before + 1
		and _last_attempt_failure.get("level") == level_before
		and int(_last_attempt_failure.get("loss_streak_count", 0)) == 1
		and _last_attempt_failure.get("hit_resolution") == _hit(), "失败事件只通知一次并交付结果")
	_check(_views(false).is_empty() and _views(true).is_empty() and not _attack.can_start_charging(), "失败停止生成与攻击并清场")
	(_sandbox.get_node("%RestartButton") as Button).pressed.emit()
	_check(_attempt_restarted_events == restarts_before + 1
		and _last_attempt_restart.get("level") == level_before
		and _last_attempt_restart.get("hit_resolution") == _hit()
		and _last_attempt_restart.get("combat_stage") == _stage()
		and _last_attempt_restart.get("repeat_queue") == _queue(), "重开事件交付新尝试状态")
	_check(is_equal_approx(_hit().get_player_pk(), 0.5) and _stage().get_current_tier() == 0, "重开恢复初始 PK 和 Tier 0")
	_check(_attack.can_start_charging() and _attempt_tendency_total() == 0, "重开恢复 READY 并重置本场暂存")
	_check(SaveManager.data == save_before and _flow().get_current_level_profile() == level_before, "重开保留同一周目及当前关对象")
	_check(SaveManager.data.tendency_state.orthodox_total == 11 and SaveManager.data.assimilation_data.defeated_streamer_ids.has(&"test_previous_streamer"), "重开保留已提交周目成果")
	_check(SaveManager.data.live_session.fan_count == 77 and SaveManager.data.live_session.viewer_count == 0 and SaveManager.data.live_session.like_count == 0 and SaveManager.data.live_session.comment_count == _views(false).size(), "重开直播表现归零后只计新开局实际评论")
	_check(_opponent().get_loss_streak_count() == 1 and not _opponent().has_attempt_failed(), "重开保留连败次数并清除本场失败标记")
	_sandbox.call("debug_set_player_pk", 0.6)
	var pk_before: float = _hit().get_player_pk()
	await _wait(0.06)
	_check(_hit().get_player_pk() < pk_before, "重开后进入 T1 恢复真实回拉")
	_area.clear_barrages()
	_opponent().stop_pullback()
	_hit().apply_player_pk_delta(0.9995 - _hit().get_player_pk())
	target = _spawn_test_normal()
	var tendency_before: int = _attempt_tendency_total()
	var pk_maximum_before: int = _pk_maximum_events
	var normal_complete_before: int = _normal_completed_events
	var contradiction_entered_before: int = _contradiction_entered_events
	await _fire_at(target)
	_check(is_equal_approx(_hit().get_player_pk(), 1.0) and not _flow().is_normal_combat_active(), "真实普通命中使 PK 满值并停止普通战斗")
	_check(_pk_maximum_events == pk_maximum_before + 1 and _normal_completed_events == normal_complete_before + 1
		and _contradiction_entered_events == contradiction_entered_before + 1, "PK 满值、普通结束和进入矛盾各通知一次")
	_check(bool(_sandbox.get_contradiction_oracle_flow().is_contradiction_active()), "满值只进入一次矛盾阶段")
	var contradiction_ids: Array[String] = []
	for view: BarrageView in _views(false):
		if view.runtime_record.is_contradiction:
			contradiction_ids.append(view.runtime_record.original_sentence_id)
	_check(contradiction_ids.has(_level().true_contradictions[0].original_sentence_id) and contradiction_ids.has(_level().false_contradictions[0].original_sentence_id), "当前关真假矛盾进入真实弹幕区域")
	_check(_attempt_tendency_total() == tendency_before + 1 and not _hit().get_normal_hit_history().is_empty(), "满值这一发仍保留倾向与普通命中历史")
	_check(_attack.can_start_charging(), "满值后开放矛盾攻击")


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
	return _flow().get_hit_resolution()


func _stage() -> CombatStage:
	return _flow().get_combat_stage()


func _opponent() -> OpponentPKBar:
	return _flow().get_opponent_pk_bar()


func _queue() -> RepeatDelayQueue:
	return _flow().get_repeat_queue()


func _level() -> LevelProfile:
	return _flow().get_current_level_profile()


func _flow() -> BattleAttemptFlow:
	return _sandbox.get_battle_attempt_flow()


func _attempt_tendency_total() -> int:
	var tendency: TendencyState = SaveManager.data.tendency_state
	return tendency.attempt_orthodox_total + tendency.attempt_heretical_total + tendency.attempt_absurd_total


func _live_comment_label() -> RichTextLabel:
	return _sandbox.get_node("%LiveDataHud").find_child("CommentMetric", true, false) as RichTextLabel


func _on_snapshot(snapshot: AttackTargetSnapshot) -> void:
	_snapshots.append(snapshot)


func _on_player_portrait_shot_motion_started() -> void:
	_player_portrait_shot_motion_events += 1


func _expected_portrait_idle_period(character_id: String) -> float:
	# 示例 streamer_id 暂未与正式角色 ID 对齐；按动效配置的公开预设映射计算预期周期。
	match character_id:
		"alien":
			return 3.8
		"kiwi":
			return 2.9
		"fox":
			return 4.1
		_:
			return 3.4


func _on_submission(_snapshot: AttackTargetSnapshot, submission: Dictionary) -> void:
	_submissions.append(submission)


func _on_flow_shot_resolved(snapshot: AttackTargetSnapshot, submission: Dictionary, current_tier: int, repeat_stats: RepeatGenerationStats) -> void:
	var result: Dictionary = submission.get("hit_resolution_result", {})
	var repeat_hit: bool = false
	for target_result: Dictionary in result.get("target_results", []):
		if bool(target_result.get("is_repeat", false)) and bool(target_result.get("is_valid_hit", false)):
			repeat_hit = true
	_flow_shot_events.append({
		"snapshot": snapshot,
		"submission": submission,
		"current_tier": current_tier,
		"repeat_stats": repeat_stats,
		"is_repeat_hit": repeat_hit,
	})


func _on_flow_tier_changed(current_tier: int, player_pk: float) -> void:
	_flow_tier_events.append({"tier": current_tier, "player_pk": player_pk})


func _on_flow_attempt_failed(level: LevelProfile, loss_streak_count: int, hit: HitResolution, stats: RepeatGenerationStats) -> void:
	_attempt_failed_events += 1
	_last_attempt_failure = {"level": level, "loss_streak_count": loss_streak_count, "hit_resolution": hit, "repeat_stats": stats}


func _on_flow_attempt_restarted(level: LevelProfile, hit: HitResolution, stage: CombatStage, queue: RepeatDelayQueue) -> void:
	_attempt_restarted_events += 1
	_last_attempt_restart = {"level": level, "hit_resolution": hit, "combat_stage": stage, "repeat_queue": queue}


func _on_flow_pk_maximum_reached(_level: LevelProfile, _hit: HitResolution, _stats: RepeatGenerationStats) -> void:
	_pk_maximum_events += 1


func _on_flow_normal_combat_completed(_level: LevelProfile, _hit: HitResolution, _stats: RepeatGenerationStats) -> void:
	_normal_completed_events += 1


func _on_flow_contradiction_entered(_level: LevelProfile, _hit: HitResolution, _stats: RepeatGenerationStats) -> void:
	_contradiction_entered_events += 1


func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("INT-01 OK: " + description)
	else:
		_failures.append(description)
