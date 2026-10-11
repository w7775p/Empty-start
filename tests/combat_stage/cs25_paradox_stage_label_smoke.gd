extends Control

const TIER_FIVE_PROBE_PK: float = 0.95
const MAXIMUM_PLAYER_PK: float = 1.0
const SCREENSHOT_DIRECTORY: String = "res://docs/8. CombatStage/evidence/cs25_2026-10-11"

var _checks: int = 0
var _failures: int = 0


# 本冒烟场景实例化正式 Sandbox，使用公开调试入口驱动普通 PK 与矛盾阶段。
func _ready() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var sandbox: Control = $Sandbox
	if not sandbox.has_method("get_battle_attempt_flow"):
		_check(false, "正式 Sandbox 脚本加载并完成初始化")
		_finish()
		return
	var tier_label: Label = sandbox.get_node("BattleHud/BattleArea/TopBattleStatus/Tier")
	var player_share: ProgressBar = sandbox.get_node("BattleHud/BattleArea/TopBattleStatus/PKBar/PlayerShare")
	var failure_overlay: Control = sandbox.get_node("FailureOverlay")
	var attempt_flow: BattleAttemptFlow = sandbox.call("get_battle_attempt_flow")
	var oracle_flow: ContradictionOracleFlow = sandbox.call("get_contradiction_oracle_flow")
	if DisplayServer.get_name() == "headless":
		print("INFO CS-25: headless 运行执行 HUD 与流程断言，截图留给 GUI 验收")
	_check(attempt_flow.get_combat_stage().get_current_tier() == 0 and tier_label.text == "Tier 0", "新尝试显示 T0")

	sandbox.call("debug_set_player_pk", TIER_FIVE_PROBE_PK)
	attempt_flow.get_opponent_pk_bar().stop_pullback()
	_check(attempt_flow.get_combat_stage().get_current_tier() == 5, "合成 PK 值经正式流程进入 T5")
	_check(tier_label.text == "Tier 5", "普通 T5 显示 Tier 5")
	_check(is_equal_approx(player_share.value, TIER_FIVE_PROBE_PK), "普通 T5 PK 比例保持原值")
	await _capture("cs25_t5_normal")

	sandbox.call("debug_set_player_pk", MAXIMUM_PLAYER_PK)
	if not await _wait_for_contradiction(oracle_flow):
		_check(false, "满 PK 后 ContradictionOracleFlow 进入真实矛盾阶段")
		_finish()
		return
	await get_tree().process_frame
	var contradiction_system: ContradictionBreakSystem = oracle_flow.get_contradiction_system()
	_check(oracle_flow.is_contradiction_active(), "真实矛盾击破流程处于 active")
	_check(attempt_flow.get_combat_stage().get_current_tier() == 5, "Paradox 显示期间运行 Tier 保持 T5")
	_check(tier_label.text == "T6 / Paradox", "真实矛盾阶段 HUD 显示 T6 / Paradox")
	_check(is_equal_approx(player_share.value, MAXIMUM_PLAYER_PK), "T6 显示不改变普通 PK 比例")
	_check(contradiction_system.get_fixed_paradox_candidates().size() == 6, "当前关卡矛盾流程提供六个 Paradox 候选")
	await _capture("cs25_t6_real_paradox")

	_check(contradiction_system.register_launched_shot(), "真实矛盾系统接受一发机会")
	_check(contradiction_system.resolve_shot_hit_ids([]), "合成落空按现有矛盾规则锁定未击破结果")
	await get_tree().process_frame
	var rest_session: RestSession = oracle_flow.get_result()
	_check(rest_session != null and rest_session.is_open(), "未击破结果进入真实 RestSession")
	_check(not oracle_flow.is_contradiction_active() and tier_label.text == "Tier 5", "Rest 阶段恢复当前普通 T5 标签")

	sandbox.call("restart_current_attempt")
	await get_tree().process_frame
	attempt_flow = sandbox.call("get_battle_attempt_flow")
	_check(attempt_flow.get_combat_stage().get_current_tier() == 0 and tier_label.text == "Tier 0", "Rest 后重开恢复新尝试 T0")

	sandbox.call("debug_set_player_pk", 0.0)
	await get_tree().process_frame
	_check(failure_overlay.visible and tier_label.text == "Tier 0", "普通战斗失败保留当前普通档位标签")
	sandbox.call("restart_current_attempt")
	await get_tree().process_frame
	_check(not failure_overlay.visible and tier_label.text == "Tier 0", "失败重试清除旧 Paradox 显示并恢复 T0")

	sandbox.call("debug_set_player_pk", TIER_FIVE_PROBE_PK)
	attempt_flow.get_opponent_pk_bar().stop_pullback()
	sandbox.call("debug_set_player_pk", MAXIMUM_PLAYER_PK)
	if not await _wait_for_contradiction(oracle_flow):
		_check(false, "第二次尝试再次进入真实矛盾阶段")
		_finish()
		return
	await get_tree().process_frame
	_check(oracle_flow.is_contradiction_active() and tier_label.text == "T6 / Paradox", "第二次尝试重新显示 T6 / Paradox")
	sandbox.call("restart_current_attempt")
	await get_tree().process_frame
	attempt_flow = sandbox.call("get_battle_attempt_flow")
	_check(not oracle_flow.is_contradiction_active() and attempt_flow.get_combat_stage().get_current_tier() == 0, "第二次尝试重开结束 Paradox 并重置普通 Tier")
	_check(tier_label.text == "Tier 0", "第二次尝试重开后 HUD 恢复 T0")
	_finish()


func _wait_for_contradiction(oracle_flow: ContradictionOracleFlow) -> bool:
	for _frame_index: int in range(120):
		if oracle_flow.is_contradiction_active():
			return true
		await get_tree().process_frame
	return false


# GUI 运行时保存实际 Sandbox Viewport；headless 只验证运行状态和 HUD 文本。
func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var evidence_directory: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(evidence_directory) != OK:
		_check(false, "创建 CS-25 截图目录")
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = evidence_directory.path_join(filename + ".png")
	_check(image.save_png(output_path) == OK, "保存 Godot Viewport 截图 %s (%s)" % [filename, image.get_size()])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS CS-25: " + message)
	else:
		_failures += 1
		push_error("FAIL CS-25: " + message)


func _finish() -> void:
	print("CS-25 RESULT checks=%d failures=%d display=%s viewport=%s" % [
		_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size
	])
	get_tree().quit(0 if _failures == 0 else 1)
