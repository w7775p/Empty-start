class_name StreamerBubbleSpecificSentenceReplyPresenter
extends Node

var _bubble_dialogue_config: BubbleDialogueConfig
var _enqueue_dialogue_bubble: Callable
var _is_configured: bool = false


# 订阅最终整发结算，并保存配置查询和 SD-03 队列入口。
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


# 仅从最终实际命中目标按稳定 ID 查对手对白；遮挡整发 MISS 不含目标事实。
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
	# 同发多目标或分裂子体使用同一句时，只请求一次完整回复。
	var replied_ids: Dictionary = {}
	for target_result: Dictionary in target_results:
		var original_sentence_id: String = str(target_result.get("original_sentence_id", ""))
		if original_sentence_id.is_empty() or replied_ids.has(original_sentence_id):
			continue
		replied_ids[original_sentence_id] = true
		_enqueue_sentence_replies(original_sentence_id)


## Plan B 玩家成功发表后按原句 ID复用旧的对手特定回复配置。
func on_plan_b_player_publication(definition: Dictionary) -> void:
	if not _is_configured:
		return
	var sentence_id: String = str(
		definition.get("original_sentence_id", definition.get("source_id", definition.get("word_id", "")))
	)
	if not sentence_id.is_empty():
		_enqueue_sentence_replies(sentence_id)


func _enqueue_sentence_replies(sentence_id: String) -> void:
	var configured_replies: Array[BubbleDialogueEntry] = _bubble_dialogue_config.find_by_sentence(
		sentence_id, BubbleDialogueEntry.SpeakerSide.OPPONENT
	)
	for configured_reply: BubbleDialogueEntry in configured_replies:
		if configured_reply.text.strip_edges().is_empty():
			continue
		# 静态配置保持只读；特定原句回复作为剧情对白副本进入 SD-03。
		var reply_request: BubbleDialogueEntry = configured_reply.duplicate(true) as BubbleDialogueEntry
		reply_request.priority = BubbleDialogueEntry.Priority.PLOT
		_enqueue_dialogue_bubble.call(reply_request)
