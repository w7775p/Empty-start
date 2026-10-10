class_name HitResolution
extends RefCounted

signal final_player_pk_updated(final_player_pk: float)

enum ShotAnomaly {
	NONE,
	BOUNCE,
	OBSTRUCTION,
	MISS,
}

const _NORMAL_WORD_REWARDS_BY_STRENGTH: Dictionary = {
	1: {"pk_delta": 0.0012, "tendency_delta": 1},
	2: {"pk_delta": 0.002, "tendency_delta": 5},
	3: {"pk_delta": 0.005, "tendency_delta": 10},
}

var _player_pk: float = 0.0
var _minimum_player_pk: float = 0.0
var _maximum_player_pk: float = 1.0
var _normal_hit_history: Array[Dictionary] = []
var _normal_hit_order: int = 0
var _normal_history_committed: bool = false
var _normal_pk_resolution_enabled: bool = true


func _init(initial_pk: float, minimum_pk: float, maximum_pk: float) -> void:
	# 创建本场唯一 PK 状态，并将配置初始值限制在配置范围内。
	initialize_player_pk(initial_pk, minimum_pk, maximum_pk)


func initialize_player_pk(initial_pk: float, minimum_pk: float, maximum_pk: float) -> void:
	# 开始或重开时替换范围与初始值，玩家 PK 始终由本对象持有。
	_minimum_player_pk = minimum_pk
	_maximum_player_pk = maximum_pk
	_player_pk = _clamp_player_pk(initial_pk)


func apply_player_pk_delta(delta: float) -> float:
	# 命中、惩罚或回拉都通过这里修改唯一 PK；clamp 后发送一次最终值事实。
	if not _normal_pk_resolution_enabled:
		return _player_pk
	_player_pk = _clamp_player_pk(_player_pk + delta)
	final_player_pk_updated.emit(_player_pk)
	return _player_pk


# 矛盾和终局阶段关闭普通结算，保留 PK 快照并停止 Tier 驱动信号。
func set_normal_pk_resolution_enabled(enabled: bool) -> void:
	_normal_pk_resolution_enabled = enabled


func allows_normal_pk_resolution() -> bool:
	return _normal_pk_resolution_enabled


func get_player_pk() -> float:
	# 只读提供玩家 PK；对手显示值由读取方按需从总量中计算。
	return _player_pk


func set_player_pk_for_debug(player_pk: float) -> float:
	# 调试改值仍通过正式 PK 更新入口发信号，让 Tier 和 HUD 使用真实联动链。
	return apply_player_pk_delta(_clamp_player_pk(player_pk) - _player_pk)


func record_normal_word_hit(original_sentence_id: Variant, tendency: Variant) -> void:
	# 每次有效普通命中递增顺序；同一原句只保留一条记录并更新次数和最近顺序。
	_normal_hit_order += 1
	for history_record: Dictionary in _normal_hit_history:
		if history_record["original_sentence_id"] == original_sentence_id:
			history_record["hit_count"] = int(history_record["hit_count"]) + 1
			history_record["last_hit_order"] = _normal_hit_order
			return

	_normal_hit_history.append(
		{
			"original_sentence_id": original_sentence_id,
			"tendency": tendency,
			"hit_count": 1,
			"first_hit_order": _normal_hit_order,
			"last_hit_order": _normal_hit_order,
		}
	)


func get_normal_hit_history() -> Array[Dictionary]:
	# 给神谕等读取方返回本场快照，避免外部修改命中结算系统拥有的历史。
	var history_copy: Array[Dictionary] = []
	for history_record: Dictionary in _normal_hit_history:
		history_copy.append(history_record.duplicate(true))
	return history_copy


# 流程重试后续奖励前读取本场提交事实，避免再次累计普通历史。
func has_committed_normal_hit_history() -> bool:
	return _normal_history_committed


# PK 胜利后只合入本场普通命中一次；旧原句沿用首次正式提交顺序。
func commit_normal_hit_history(run_data: SaveData) -> bool:
	if run_data == null or _normal_history_committed:
		return false
	for attempt_entry: Dictionary in _normal_hit_history:
		var sentence_id: Variant = attempt_entry.get("original_sentence_id")
		var committed_entry: Dictionary = {}
		for previous_entry: Dictionary in run_data.committed_normal_hit_history:
			if previous_entry.get("original_sentence_id") == sentence_id:
				committed_entry = previous_entry
				break
		if committed_entry.is_empty():
			run_data.committed_normal_hit_history.append({
				"original_sentence_id": sentence_id,
				"tendency": attempt_entry.get("tendency"),
				"hit_count": int(attempt_entry.get("hit_count", 0)),
				"first_committed_hit_order": run_data.next_normal_hit_commit_order,
			})
			run_data.next_normal_hit_commit_order += 1
		else:
			committed_entry["hit_count"] = int(committed_entry.get("hit_count", 0)) + int(attempt_entry.get("hit_count", 0))
	_normal_history_committed = true
	return true


# 失败重开只撤销本场暂存；以前关卡已提交历史仍由 SaveData 持有。
func discard_uncommitted_normal_hit_history() -> void:
	if _normal_history_committed:
		return
	_normal_hit_history.clear()
	_normal_hit_order = 0


func calculate_normal_word_reward(strength: int, tendency_id: String = "") -> Dictionary:
	# PK 收益由内容强度决定；neutral 是有效普通话语，但不给三项倾向增量。
	if not _NORMAL_WORD_REWARDS_BY_STRENGTH.has(strength):
		push_error("Normal word strength must be 1, 2, or 3; received %d." % strength)
		return {}
	var reward: Dictionary = _NORMAL_WORD_REWARDS_BY_STRENGTH[strength].duplicate()
	if tendency_id == "neutral":
		reward["tendency_delta"] = 0
	return reward


func calculate_repeat_hit_result() -> Dictionary:
	# 复读是有效命中，但不产生 PK 或倾向收益，避免被整发结算误判为落空。
	return {"is_valid_hit": true, "pk_delta": 0.0, "tendency_delta": 0}


func select_shot_anomaly(has_bounce: bool, has_obstruction: bool, is_miss: bool) -> ShotAnomaly:
	# 每发只选一个异常；布尔输入把同一反弹目标的重复报告折叠为一次。
	if has_bounce:
		return ShotAnomaly.BOUNCE
	if has_obstruction:
		return ShotAnomaly.OBSTRUCTION
	if is_miss:
		return ShotAnomaly.MISS
	return ShotAnomaly.NONE


func is_shot_fully_missed(target_validity: Array[bool]) -> bool:
	# 只要本发存在一个有效目标，其他失效目标就不能把整发变成落空。
	for target_is_valid: bool in target_validity:
		if target_is_valid:
			return false
	return true


func resolve_shot_results(
	target_results: Array[Dictionary], shot_anomaly: ShotAnomaly = ShotAnomaly.NONE
) -> Dictionary:
	# 保留逐目标结算数据，只把 PK 增量求和后统一更新一次并应用范围限制。
	# 回拉已使 PK 到达下限时整发作废，避免提交命中收益或倾向结果。
	if not _normal_pk_resolution_enabled:
		# 阶段关闭后丢弃晚到的普通目标收益，避免下游继续累计倾向或生成普通复读。
		return {
			"cancelled_by_zero_pk": false,
			"terminal_mode": true,
			"total_pk_delta": 0.0,
			"final_player_pk": _player_pk,
			"target_results": [],
		}
	if _player_pk <= _minimum_player_pk:
		return {
			"cancelled_by_zero_pk": true,
			"total_pk_delta": 0.0,
			"final_player_pk": _player_pk,
			"target_results": [],
		}

	# 特性已由 4 解析；6 按正式战斗数值表换算为内部 0–1 PK，并清掉特殊结果的普通收益。
	var resolved_targets: Array[Dictionary] = target_results.duplicate(true)
	var total_pk_delta: float = 0.0
	for target_result: Dictionary in resolved_targets:
		var trait_result := target_result.get("trait_result") as BarrageTraitResult
		if trait_result != null and not trait_result.receives_normal_reward:
			target_result["is_valid_hit"] = false
			target_result["tendency_delta"] = 0
			match trait_result.kind:
				BarrageTraitResult.Kind.FAKE_CARD:
					target_result["pk_delta"] = -0.005
				BarrageTraitResult.Kind.RETALIATION_COPY:
					target_result["pk_delta"] = -0.007
				_:
					target_result["pk_delta"] = 0.0
		total_pk_delta += float(target_result.get("pk_delta", 0.0))
	# 反弹 / 遮挡 / 落空每发只扣一次；最终反弹结果不会再叠加该目标的反击惩罚。
	if shot_anomaly != ShotAnomaly.NONE:
		total_pk_delta -= 0.01

	var final_player_pk: float = apply_player_pk_delta(total_pk_delta)
	return {
		"cancelled_by_zero_pk": false,
		"total_pk_delta": total_pk_delta,
		"final_player_pk": final_player_pk,
		"target_results": resolved_targets,
	}


func _clamp_player_pk(value: float) -> float:
	return clampf(value, _minimum_player_pk, _maximum_player_pk)
