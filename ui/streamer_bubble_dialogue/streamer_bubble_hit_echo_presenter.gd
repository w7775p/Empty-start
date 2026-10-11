class_name StreamerBubbleHitEchoPresenter
extends Node

var _bubble_dialogue_config: BubbleDialogueConfig
var _enqueue_dialogue_bubble: Callable
var _is_configured: bool = false


# 订阅最终整发结果，并保存生成玩家气泡所需的最小依赖。
func configure(
	battle_attempt_flow: BattleAttemptFlow,
	bubble_dialogue_config: BubbleDialogueConfig,
	enqueue_dialogue_bubble: Callable
) -> bool:
	if _is_configured or not is_inside_tree() or battle_attempt_flow == null or bubble_dialogue_config == null:
		return false
	_bubble_dialogue_config = bubble_dialogue_config
	_enqueue_dialogue_bubble = enqueue_dialogue_bubble
	battle_attempt_flow.shot_resolved.connect(_on_shot_resolved)
	_is_configured = true
	return true


# 按最终逐目标列表原序提交气泡；列表不含遮挡整发落空，负收益仍保留其中。
func _on_shot_resolved(
	_snapshot: AttackTargetSnapshot,
	submission: Dictionary,
	_current_tier: int,
	_repeat_stats: RepeatGenerationStats
) -> void:
	if not _is_configured:
		return
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var target_results: Array = hit_result.get("target_results", [])
	for target_result: Dictionary in target_results:
		if bool(target_result.get("is_repeat", false)):
			continue
		var entry: BubbleDialogueEntry = _bubble_dialogue_config.create_hit_echo(
			str(target_result.get("original_sentence_id", "")),
			str(target_result.get("original_sentence_text", "")),
			true,
			false
		)
		if entry != null:
			_enqueue_dialogue_bubble.call(entry)
