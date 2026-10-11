extends Control

const DEFAULT_T0_STATUS: String = "等待对手连线……"
const CONNECTED_STATUS: String = "对手已连线"
const SCREENSHOT_DIRECTORY: String = "res://docs/8. CombatStage/evidence/cs20_2026-10-11"

var _checks: int = 0
var _failures: int = 0


# 使用正式 Sandbox 和 PK 调试入口验证 T0/T1 状态切换与提示保护。
func _ready() -> void:
	call_deferred("_run_smoke")


func _run_smoke() -> void:
	var sandbox: Control = $Sandbox
	var hud: Control = sandbox.get_node("BattleHud")
	var state_label: Label = sandbox.get_node("BattleHud/BattleArea/TopBattleStatus/BattleStateFeedback")
	var attempt_flow: BattleAttemptFlow = sandbox.call("get_battle_attempt_flow")
	if attempt_flow == null:
		_check(false, "正式 Sandbox 已启动 BattleAttemptFlow")
		_finish()
		return
	await get_tree().process_frame

	_check(attempt_flow.get_combat_stage().get_current_tier() == 0, "新战斗从 T0 开始")
	_check(hud.get("t0_matching_status_text") == DEFAULT_T0_STATUS, "T0 等待文案可配置且默认值明确")
	_check(state_label.text == DEFAULT_T0_STATUS, "新战斗显示对手连线等待文案")
	await _capture("cs20_t0_waiting")

	sandbox.call("debug_set_player_pk", 0.60)
	_check(attempt_flow.get_combat_stage().get_current_tier() == 1, "PK 通过正式流程进入 T1")
	_check(state_label.text == CONNECTED_STATUS, "进入 T1 后显示对手已连线状态")
	await _capture("cs20_t1_connected")

	hud.call("show_battle_state", "关键战斗警告：注意命中窗口")
	sandbox.call("debug_set_player_pk", 0.50)
	_check(attempt_flow.get_combat_stage().get_current_tier() == 0, "PK 下降通过正式流程返回 T0")
	_check(state_label.text == "关键战斗警告：注意命中窗口", "Tier 刷新保留正在显示的战斗警告")

	hud.set("t0_matching_status_text", "正在搜索 PK 对手……")
	sandbox.call("restart_current_attempt")
	await get_tree().process_frame
	attempt_flow = sandbox.call("get_battle_attempt_flow")
	_check(attempt_flow.get_combat_stage().get_current_tier() == 0, "重开后 CombatStage 重置为 T0")
	_check(state_label.text == "正在搜索 PK 对手……", "重开读取配置的 T0 等待文案")

	hud.call("show_battle_state", "关键战斗警告：请立即处理")
	sandbox.call("debug_set_player_pk", 0.60)
	_check(attempt_flow.get_combat_stage().get_current_tier() == 1, "重开后可再次进入 T1")
	_check(state_label.text == "关键战斗警告：请立即处理", "进入 T1 时保留实时战斗警告")
	_finish()


# GUI 运行时保存正式 Sandbox 视口；headless 仅检查实际状态和文案。
func _capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var evidence_directory: String = ProjectSettings.globalize_path(SCREENSHOT_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(evidence_directory) != OK:
		_check(false, "创建 CS-20 GUI 证据目录")
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var output_path: String = evidence_directory.path_join(filename + ".png")
	_check(image.save_png(output_path) == OK, "保存 Godot 视口截图 %s (%s)" % [filename, image.get_size()])


func _check(condition: bool, message: String) -> void:
	# 每条验收结果单独输出，失败时返回非零进程码。
	_checks += 1
	if condition:
		print("PASS CS-20: " + message)
	else:
		_failures += 1
		push_error("FAIL CS-20: " + message)


func _finish() -> void:
	# 汇总本次聚焦验收并让 Godot 进程返回对应退出码。
	print("CS-20 RESULT checks=%d failures=%d display=%s viewport=%s" % [
		_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size
	])
	get_tree().quit(0 if _failures == 0 else 1)
