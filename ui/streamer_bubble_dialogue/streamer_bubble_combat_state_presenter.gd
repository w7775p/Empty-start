extends Node

signal event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int)

const EVENT_COMBAT_CONNECTED: StringName = &"combat_connected"
const EVENT_TIER_UP: StringName = &"combat_tier_up"
const EVENT_TIER_DOWN: StringName = &"combat_tier_down"
const EVENT_TIER1_TAUNT: StringName = &"combat_tier1_taunt"
const EVENT_COMBAT_WIN: StringName = &"combat_win"
const EVENT_COMBAT_LOSE: StringName = &"combat_lose"
const EVENT_PARADOX_BREAKTHROUGH: StringName = &"paradox_breakthrough"
const EVENT_PARADOX_NOT_BROKEN: StringName = &"paradox_not_broken"

var _battle_attempt_flow: BattleAttemptFlow
var _contradiction_oracle_flow: ContradictionOracleFlow
var _bubble_dialogue_config: BubbleDialogueConfig
var _enqueue_dialogue_sequence: Callable
var _hud: Node
var _is_configured: bool = false
var _attempt_active: bool = false
var _last_tier: int = CombatStage.INITIAL_TIER
var _has_contradiction_outcome: bool = false
var _sequence_counter: int = 0
var _event_by_sequence: Dictionary = {}


# 只订阅已发生的公开战斗事实；对白内容和显示仍由配置与 HUD 队列拥有。
func configure(
	battle_attempt_flow: BattleAttemptFlow,
	contradiction_oracle_flow: ContradictionOracleFlow,
	bubble_dialogue_config: BubbleDialogueConfig,
	enqueue_dialogue_sequence: Callable,
	hud: Node
) -> bool:
	if _is_configured or not is_inside_tree():
		return false
	if battle_attempt_flow == null or contradiction_oracle_flow == null or bubble_dialogue_config == null:
		return false
	if not enqueue_dialogue_sequence.is_valid() or not is_instance_valid(hud):
		return false
	if not hud.has_signal("dialogue_sequence_completed"):
		return false

	_battle_attempt_flow = battle_attempt_flow
	_contradiction_oracle_flow = contradiction_oracle_flow
	_bubble_dialogue_config = bubble_dialogue_config
	_enqueue_dialogue_sequence = enqueue_dialogue_sequence
	_hud = hud
	_battle_attempt_flow.attempt_started.connect(_on_attempt_started)
	_battle_attempt_flow.tier_changed.connect(_on_tier_changed)
	_battle_attempt_flow.normal_combat_completed.connect(_on_normal_combat_completed)
	_battle_attempt_flow.attempt_failed.connect(_on_attempt_failed)
	_contradiction_oracle_flow.outcome_resolved.connect(_on_contradiction_outcome_resolved)
	_hud.connect("dialogue_sequence_completed", Callable(self, "_on_hud_sequence_completed"))
	_is_configured = true
	return true


# 开始和原地重开都只发出一次 attempt_started；从此刻重新跟踪本场 Tier 边沿。
func _on_attempt_started(
	_level: LevelProfile,
	_hit_resolution: HitResolution,
	combat_stage: CombatStage,
	_repeat_queue: RepeatDelayQueue
) -> void:
	_attempt_active = true
	_last_tier = combat_stage.get_current_tier() if combat_stage != null else CombatStage.INITIAL_TIER
	_has_contradiction_outcome = false
	_event_by_sequence.clear()


# Tier 信号只携带最终档位；与尝试启动时记录的档位比较即可识别真实升降档。
func _on_tier_changed(current_tier: int, _player_pk: float) -> void:
	if not _attempt_active or current_tier == _last_tier:
		return
	var previous_tier: int = _last_tier
	_last_tier = current_tier
	if previous_tier == CombatStage.INITIAL_TIER and current_tier > CombatStage.INITIAL_TIER:
		# T0 到正档表示对手完成连线；跨档时同时保留普通升档事实。
		_submit_event(EVENT_COMBAT_CONNECTED)
		if current_tier > CombatStage.INITIAL_TIER + 1:
			_submit_event(EVENT_TIER_UP)
	elif current_tier > previous_tier:
		_submit_event(EVENT_TIER_UP)
	elif current_tier == CombatStage.INITIAL_TIER:
		# T0 表示对手离线；HUD 已清理对手侧队列，这里丢弃对应完成映射。
		_forget_sequences_for_side(BubbleDialogueEntry.SpeakerSide.OPPONENT)
	elif current_tier == 1 and previous_tier > 1:
		# 降到 T1 使用独立语义 ID，供 CS-27 精确配置嘲讽内容。
		_submit_event(EVENT_TIER1_TAUNT)
	else:
		_submit_event(EVENT_TIER_DOWN)


# 普通 PK 满是本场胜利事实；后续 Paradox 结果使用独立事件 ID，避免重复胜负对白。
func _on_normal_combat_completed(
	_level: LevelProfile, _hit_resolution: HitResolution, _repeat_stats: RepeatGenerationStats
) -> void:
	if not _attempt_active:
		return
	_attempt_active = false
	_submit_event(EVENT_COMBAT_WIN)


# PK 归零只在本次活动尝试触发一次失败对白；重开会由新的 attempt_started 复位。
func _on_attempt_failed(
	_level: LevelProfile,
	_loss_streak_count: int,
	_hit_resolution: HitResolution,
	_repeat_stats: RepeatGenerationStats
) -> void:
	if not _attempt_active:
		return
	_attempt_active = false
	_submit_event(EVENT_COMBAT_LOSE)


# Paradox 的最终结果也由配置驱动，但与普通 PK 胜负分开，避免同一流程重复播报。
func _on_contradiction_outcome_resolved(outcome: int) -> void:
	if _has_contradiction_outcome:
		return
	_has_contradiction_outcome = true
	match outcome:
		ContradictionBreakSystem.Outcome.BREAKTHROUGH:
			_submit_event(EVENT_PARADOX_BREAKTHROUGH)
		ContradictionBreakSystem.Outcome.NOT_BROKEN:
			_submit_event(EVENT_PARADOX_NOT_BROKEN)


# 按事件 ID 查询当前配置，复制条目后统一设为 PLOT，静态 Resource 保持只读。
func _submit_event(event_id: StringName) -> void:
	var configured_entries: Array[BubbleDialogueEntry] = _bubble_dialogue_config.find_by_event(event_id)
	var plot_entries: Array[BubbleDialogueEntry] = []
	var sequence_side: int = -1
	for configured_entry: BubbleDialogueEntry in configured_entries:
		if configured_entry == null or configured_entry.text.strip_edges().is_empty():
			continue
		if sequence_side < 0:
			sequence_side = configured_entry.side
		elif configured_entry.side != sequence_side:
			push_error("SD-06: 同一事件的剧情序列必须属于同一发言侧：%s" % String(event_id))
			return
		var plot_entry: BubbleDialogueEntry = configured_entry.duplicate(true) as BubbleDialogueEntry
		plot_entry.priority = BubbleDialogueEntry.Priority.PLOT
		plot_entries.append(plot_entry)

	if plot_entries.is_empty():
		# 空配置等价于零句序列完成，避免 CS-23 因暂缺台词而永久等待。
		event_sequence_completed.emit(event_id, &"", -1)
		return

	_sequence_counter += 1
	var requested_sequence_id := StringName("sd06_%s_%d" % [String(event_id), _sequence_counter])
	var accepted_sequence_id: StringName = StringName(
		_enqueue_dialogue_sequence.call(plot_entries, requested_sequence_id)
	)
	if String(accepted_sequence_id).is_empty():
		push_error("SD-06: SD-03 拒绝剧情序列：%s" % String(event_id))
		return
	_event_by_sequence[accepted_sequence_id] = {
		"event_id": event_id,
		"side": sequence_side,
	}


# HUD 只在最后一句气泡实际到期后转发；同一 ID 完成一次后立即移除映射。
func _on_hud_sequence_completed(sequence_id: StringName, side: int) -> void:
	if not _event_by_sequence.has(sequence_id):
		return
	var event_record: Dictionary = _event_by_sequence[sequence_id]
	_event_by_sequence.erase(sequence_id)
	if int(event_record.get("side", -1)) != side:
		return
	event_sequence_completed.emit(event_record["event_id"], sequence_id, side)


# 对手离线会取消队列内的序列；清掉其映射，防止后续同 ID 的回调误认成完成。
func _forget_sequences_for_side(side: int) -> void:
	for sequence_id: StringName in _event_by_sequence.keys():
		var event_record: Dictionary = _event_by_sequence[sequence_id]
		if int(event_record.get("side", -1)) == side:
			_event_by_sequence.erase(sequence_id)


# 沙盒退出时解除全部信号连接，允许场景重建后只保留新消费者。
func _exit_tree() -> void:
	if is_instance_valid(_battle_attempt_flow):
		if _battle_attempt_flow.attempt_started.is_connected(_on_attempt_started):
			_battle_attempt_flow.attempt_started.disconnect(_on_attempt_started)
		if _battle_attempt_flow.tier_changed.is_connected(_on_tier_changed):
			_battle_attempt_flow.tier_changed.disconnect(_on_tier_changed)
		if _battle_attempt_flow.normal_combat_completed.is_connected(_on_normal_combat_completed):
			_battle_attempt_flow.normal_combat_completed.disconnect(_on_normal_combat_completed)
		if _battle_attempt_flow.attempt_failed.is_connected(_on_attempt_failed):
			_battle_attempt_flow.attempt_failed.disconnect(_on_attempt_failed)
	if is_instance_valid(_contradiction_oracle_flow):
		if _contradiction_oracle_flow.outcome_resolved.is_connected(_on_contradiction_outcome_resolved):
			_contradiction_oracle_flow.outcome_resolved.disconnect(_on_contradiction_outcome_resolved)
	if is_instance_valid(_hud) and _hud.is_connected(
		"dialogue_sequence_completed", Callable(self, "_on_hud_sequence_completed")
	):
		_hud.disconnect("dialogue_sequence_completed", Callable(self, "_on_hud_sequence_completed"))
