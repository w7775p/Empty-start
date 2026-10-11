extends Node

const TIMED_DIALOGUE_EVENT_ID: StringName = &"timed"

var _battle_attempt_flow: BattleAttemptFlow
var _bubble_dialogue_config: BubbleDialogueConfig
var _enqueue_dialogue_bubble: Callable
var _is_configured: bool = false
var _attempt_active: bool = false
var _elapsed_seconds: float = 0.0
var _next_entry_index: int = 0
var _scheduled_entries: Array[Dictionary] = []
var _due_entries: Array[BubbleDialogueEntry] = []


# 时钟随普通尝试开始与重开重置；PAUSABLE 让 SceneTree 暂停冻结累计时间。
func configure(
	battle_attempt_flow: BattleAttemptFlow,
	bubble_dialogue_config: BubbleDialogueConfig,
	enqueue_dialogue_bubble: Callable
) -> bool:
	if _is_configured or not is_inside_tree():
		return false
	if battle_attempt_flow == null or bubble_dialogue_config == null:
		return false
	if not enqueue_dialogue_bubble.is_valid():
		return false

	_battle_attempt_flow = battle_attempt_flow
	_bubble_dialogue_config = bubble_dialogue_config
	_enqueue_dialogue_bubble = enqueue_dialogue_bubble
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_battle_attempt_flow.attempt_started.connect(_on_attempt_started)
	_battle_attempt_flow.normal_combat_completed.connect(_on_normal_combat_completed)
	_battle_attempt_flow.attempt_failed.connect(_on_attempt_failed)
	_is_configured = true
	return true


# 本场重开也会发 attempt_started；重新读当前配置并清空旧计时与待提交条目。
func _on_attempt_started(
	_level: LevelProfile,
	_hit_resolution: HitResolution,
	_combat_stage: CombatStage,
	_repeat_queue: RepeatDelayQueue
) -> void:
	_attempt_active = true
	_elapsed_seconds = 0.0
	_next_entry_index = 0
	_due_entries.clear()
	_scheduled_entries.clear()
	var timed_entries: Array[BubbleDialogueEntry] = _bubble_dialogue_config.find_by_event(
		TIMED_DIALOGUE_EVENT_ID, BubbleDialogueEntry.SpeakerSide.OPPONENT
	)
	for config_order: int in range(timed_entries.size()):
		var source_entry: BubbleDialogueEntry = timed_entries[config_order]
		if source_entry == null or source_entry.text.strip_edges().is_empty():
			continue
		if source_entry.trigger_time_seconds < 0.0:
			push_warning("SD-07: 定时对白触发时间不能小于 0 秒。")
			continue
		var timed_entry: BubbleDialogueEntry = source_entry.duplicate(true) as BubbleDialogueEntry
		timed_entry.priority = BubbleDialogueEntry.Priority.TIMED_IDLE
		_scheduled_entries.append({
			"trigger_time_seconds": source_entry.trigger_time_seconds,
			"config_order": config_order,
			"entry": timed_entry,
		})
	_scheduled_entries.sort_custom(_scheduled_entry_precedes)


# 按触发秒数排序；相同时间沿用配置数组顺序，和 SD-08 的 line_order 映射一致。
func _scheduled_entry_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_time: float = float(left["trigger_time_seconds"])
	var right_time: float = float(right["trigger_time_seconds"])
	if left_time != right_time:
		return left_time < right_time
	return int(left["config_order"]) < int(right["config_order"])


# 普通尝试中累计秒数；T0 离线期间先缓存到点条目，待对手连线后再交给 HUD。
func _process(delta: float) -> void:
	if not _attempt_active:
		return
	_elapsed_seconds += delta
	while _next_entry_index < _scheduled_entries.size():
		var scheduled_entry: Dictionary = _scheduled_entries[_next_entry_index]
		if float(scheduled_entry["trigger_time_seconds"]) > _elapsed_seconds:
			break
		_due_entries.append(scheduled_entry["entry"] as BubbleDialogueEntry)
		_next_entry_index += 1
	_flush_due_entries()


# T0 时 HUD 会拒绝对手侧请求；保留尚未提交的到期句子并在下一次连线后继续提交。
func _flush_due_entries() -> void:
	if _due_entries.is_empty() or _battle_attempt_flow.get_current_tier() <= CombatStage.INITIAL_TIER:
		return
	while not _due_entries.is_empty():
		var entry: BubbleDialogueEntry = _due_entries[0]
		if not bool(_enqueue_dialogue_bubble.call(entry)):
			return
		_due_entries.pop_front()


# 普通胜负结束计时，避免本场定时对白延续到 Paradox 或失败界面。
func _on_normal_combat_completed(
	_level: LevelProfile, _hit_resolution: HitResolution, _repeat_stats: RepeatGenerationStats
) -> void:
	_stop_attempt_clock()


func _on_attempt_failed(
	_level: LevelProfile,
	_loss_streak_count: int,
	_hit_resolution: HitResolution,
	_repeat_stats: RepeatGenerationStats
) -> void:
	_stop_attempt_clock()


func _stop_attempt_clock() -> void:
	_attempt_active = false
	_due_entries.clear()


# Sandbox 销毁时解除信号连接，避免旧尝试在后续场景中继续触发。
func _exit_tree() -> void:
	if not is_instance_valid(_battle_attempt_flow):
		return
	if _battle_attempt_flow.attempt_started.is_connected(_on_attempt_started):
		_battle_attempt_flow.attempt_started.disconnect(_on_attempt_started)
	if _battle_attempt_flow.normal_combat_completed.is_connected(_on_normal_combat_completed):
		_battle_attempt_flow.normal_combat_completed.disconnect(_on_normal_combat_completed)
	if _battle_attempt_flow.attempt_failed.is_connected(_on_attempt_failed):
		_battle_attempt_flow.attempt_failed.disconnect(_on_attempt_failed)
