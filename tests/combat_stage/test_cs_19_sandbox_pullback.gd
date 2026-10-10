extends Node

const TIER_ONE_PROBE_PK: float = 0.60


# 用现有 Sandbox 场景及其公开调试/读取接口核对真实 Tier 回拉行为。
func _ready() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var sandbox: Node = get_node_or_null("Sandbox")
	if sandbox == null:
		push_error("FAIL CS-19 Sandbox: 未加载正式 Sandbox 子场景")
		get_tree().quit(1)
		return
	if not sandbox.has_method("get_battle_attempt_flow") or not sandbox.has_method("debug_set_player_pk"):
		push_error("FAIL CS-19 Sandbox: Sandbox 公开验收接口不可用")
		get_tree().quit(1)
		return

	var attempt_flow: Node = sandbox.call("get_battle_attempt_flow")
	if attempt_flow == null:
		push_error("FAIL CS-19 Sandbox: 普通战斗流程未启动")
		get_tree().quit(1)
		return
	var hit_resolution: Object = attempt_flow.call("get_hit_resolution")
	var combat_stage: Object = attempt_flow.call("get_combat_stage")
	if hit_resolution == null or combat_stage == null:
		push_error("FAIL CS-19 Sandbox: 本场 PK 或 CombatStage 未初始化")
		get_tree().quit(1)
		return

	if int(combat_stage.call("get_current_tier")) != 0:
		push_error("FAIL CS-19 Sandbox: 开局应处于 T0")
		get_tree().quit(1)
		return
	var t0_player_pk: float = float(hit_resolution.call("get_player_pk"))
	await get_tree().create_timer(0.75).timeout
	if not is_equal_approx(float(hit_resolution.call("get_player_pk")), t0_player_pk):
		push_error("FAIL CS-19 Sandbox: T0 等待期间玩家 PK 发生变化")
		get_tree().quit(1)
		return

	sandbox.call("debug_set_player_pk", TIER_ONE_PROBE_PK)
	if int(combat_stage.call("get_current_tier")) != 1:
		push_error("FAIL CS-19 Sandbox: 0.60 PK 应通过现有公开流程进入 T1")
		get_tree().quit(1)
		return
	var t1_player_pk: float = float(hit_resolution.call("get_player_pk"))
	await get_tree().create_timer(1.0).timeout
	var t1_player_pk_after_wait: float = float(hit_resolution.call("get_player_pk"))
	if t1_player_pk_after_wait >= t1_player_pk:
		push_error("FAIL CS-19 Sandbox: T1 保留的 1.3 倍率应沿现有 PK 所有者产生回拉")
		get_tree().quit(1)
		return
	if int(combat_stage.call("get_current_tier")) != 1:
		push_error("FAIL CS-19 Sandbox: T1 探针期间不应意外降档")
		get_tree().quit(1)
		return

	print("PASS CS-19 Sandbox: T0 PK stable; T1 pullback changes the existing HitResolution PK")
	get_tree().quit(0)
