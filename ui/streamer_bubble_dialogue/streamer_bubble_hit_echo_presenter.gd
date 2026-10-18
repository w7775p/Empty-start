class_name StreamerBubbleHitEchoPresenter
extends Node

enum EchoPolicy { LEGACY_EVERY_HIT, SPECIAL_THROTTLED, STORY_WITH_IDLE }
# 人工选择前保留正式旧策略；A/B 只通过公开接口注入预览。
var echo_policy: EchoPolicy = EchoPolicy.LEGACY_EVERY_HIT
var minimum_interval_seconds: float = 0.0
var _cooldown_remaining: float = 0.0

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
	battle_attempt_flow.attempt_started.connect(_on_attempt_started)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_is_configured = true
	return true


# 预览 A/B 使用同一正式消费者，批准后由组合方传入策略及间隔。
func configure_policy(policy: EchoPolicy, interval_seconds: float) -> void:
	echo_policy = policy
	minimum_interval_seconds = maxf(0.0, interval_seconds)
	_cooldown_remaining = 0.0


# 暂停冻结限频时钟，不使用现实时间跨过游戏暂停。
func _process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)


# 每次尝试独立，旧尝试的限频不会延续到重开。
func _on_attempt_started(_level: LevelProfile, _hit: HitResolution, _stage: CombatStage, _queue: RepeatDelayQueue) -> void:
	_cooldown_remaining = 0.0


## Plan B 的成功发表替代普通射击命中，仍复用同一对白配置和限频规则。
func on_plan_b_player_publication(definition: Dictionary) -> void:
	if not _is_configured or _cooldown_remaining > 0.0:
		return
	var sentence_id: String = str(
		definition.get("original_sentence_id", definition.get("source_id", definition.get("word_id", "")))
	)
	var sentence_text: String = str(definition.get("text", ""))
	if sentence_id.is_empty() or sentence_text.is_empty():
		return
	if echo_policy == EchoPolicy.STORY_WITH_IDLE:
		var configured: Array[BubbleDialogueEntry] = _bubble_dialogue_config.find_by_event(
			&"actual_hit", BubbleDialogueEntry.SpeakerSide.PLAYER, sentence_id
		)
		if (
			not configured.is_empty()
			and bool(_enqueue_dialogue_bubble.call(configured[0].duplicate(true)))
		):
			_cooldown_remaining = minimum_interval_seconds
		return
	var traits: Variant = definition.get("traits", [])
	var has_special_trait: bool = traits is Array and not (traits as Array).is_empty()
	if echo_policy == EchoPolicy.SPECIAL_THROTTLED and not has_special_trait:
		return
	var entry: BubbleDialogueEntry = _bubble_dialogue_config.create_hit_echo(
		sentence_id, sentence_text, true, has_special_trait
	)
	if entry != null and bool(_enqueue_dialogue_bubble.call(entry)):
		_cooldown_remaining = minimum_interval_seconds


# 按最终逐目标列表原序提交气泡；列表不含遮挡整发落空，负收益仍保留其中。
func _on_shot_resolved(
	_snapshot: AttackTargetSnapshot,
	submission: Dictionary,
	_current_tier: int,
	_repeat_stats: RepeatGenerationStats
) -> void:
	if not _is_configured or _cooldown_remaining > 0.0:
		return
	var hit_result: Dictionary = submission.get("hit_resolution_result", {})
	var target_results: Array = hit_result.get("target_results", [])
	for target_result: Dictionary in target_results:
		if bool(target_result.get("is_repeat", false)):
			continue
		var id: String = str(target_result.get("original_sentence_id", ""))
		if echo_policy == EchoPolicy.STORY_WITH_IDLE:
			# B 只消费已经配置的特定命中台词；普通命中不自动复述，保留闲聊空档。
			var configured: Array[BubbleDialogueEntry] = _bubble_dialogue_config.find_by_event(&"actual_hit", BubbleDialogueEntry.SpeakerSide.PLAYER, id)
			if not configured.is_empty() and bool(_enqueue_dialogue_bubble.call(configured[0].duplicate(true))):
				_cooldown_remaining = minimum_interval_seconds
				return
			continue
		if echo_policy == EchoPolicy.SPECIAL_THROTTLED:
			var parsed_trait: BarrageTraitResult = target_result.get("trait_result") as BarrageTraitResult
			var special: bool = parsed_trait != null and parsed_trait.kind != BarrageTraitResult.Kind.NORMAL
			var target: BarrageView = target_result.get("target") as BarrageView
			if is_instance_valid(target) and target.runtime_record != null:
				special = special or not target.runtime_record.trait_set.get_trait_ids().is_empty()
			if not special:
				continue
		var entry: BubbleDialogueEntry = _bubble_dialogue_config.create_hit_echo(
			str(target_result.get("original_sentence_id", "")),
			str(target_result.get("original_sentence_text", "")),
			true,
			false
		)
		if entry != null and bool(_enqueue_dialogue_bubble.call(entry)):
			_cooldown_remaining = minimum_interval_seconds
			if echo_policy != EchoPolicy.LEGACY_EVERY_HIT:
				return
