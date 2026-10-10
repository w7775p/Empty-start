class_name CombatStage
extends RefCounted

signal opponent_tier_state_changed(pullback_multiplier: float, tier5_desperation_active: bool)
signal barrage_generation_multipliers_changed(count_multiplier: float, frequency_multiplier: float, movement_speed_multiplier: float)
signal barrage_lifetime_multiplier_changed(lifetime_multiplier: float)
signal barrage_foreground_slot_count_changed(foreground_slot_count: int)
signal neutral_weight_multiplier_changed(multiplier: float)
signal tier_state_changed(current_tier: int)
signal audio_event_requested(event_id: StringName)

const INITIAL_TIER: int = 0

enum StageResult { NORMAL_COMBAT, ENTER_CONTRADICTION }

var _tier_catalog: CombatStageTierCatalog
var _current_tier: int = INITIAL_TIER
var _tier_changes_enabled: bool = true


func _init(tier_catalog: CombatStageTierCatalog) -> void:
	# 注入本系统静态 Tier 配置；运行时当前档位继续由 CombatStage 自己持有。
	_tier_catalog = tier_catalog


func begin_combat() -> void:
	# 新一场或当前关重开时统一从 Tier 0 开始。
	_tier_changes_enabled = true
	_current_tier = INITIAL_TIER
	_publish_current_tier_state()


func get_current_tier() -> int:
	return _current_tier


# 最终 PK 达到配置满值时交出矛盾阶段结果，内容与成败仍由 12 系统处理。
func get_stage_result(final_player_pk: float, maximum_player_pk: float) -> StageResult:
	if final_player_pk >= maximum_player_pk:
		return StageResult.ENTER_CONTRADICTION
	return StageResult.NORMAL_COMBAT


# 终局把当前表现固定到指定 Tier，并关闭后续普通升降档入口。
func enter_terminal_tier(tier: int) -> bool:
	if _tier_catalog == null or _tier_catalog.get_tier_config(tier) == null:
		return false
	_tier_changes_enabled = false
	_current_tier = tier
	_publish_current_tier_state()
	return true


func allows_tier_changes() -> bool:
	return _tier_changes_enabled


func get_current_repeat_count_per_hit() -> int:
	# 给复读计划创建方读取当前 Tier 的每次命中复读数量。
	var current_config: CombatStageTierConfig = _tier_catalog.get_tier_config(_current_tier)
	return current_config.repeat_count_per_hit


func bind_hit_resolution(hit_resolution: HitResolution) -> void:
	# 监听命中结算的最终 PK 事实；整发攻击和每次回拉共用同一入口。
	hit_resolution.final_player_pk_updated.connect(_on_final_player_pk_updated)


func bind_opponent_pk_bar(opponent_pk_bar: OpponentPKBar) -> void:
	# Tier 配置只通过信号通知对手系统；同一对象重复绑定时不重复连接。
	var callback: Callable = Callable(opponent_pk_bar, "apply_tier_state")
	if not opponent_tier_state_changed.is_connected(callback):
		opponent_tier_state_changed.connect(callback)
	_publish_opponent_tier_state()


func bind_barrage_area(barrage_area: BarrageArea) -> void:
	# 复用弹幕生成系统现有的倍率入口，并在绑定时补发当前 Tier 配置。
	var generation_callback: Callable = Callable(barrage_area, "set_generation_multipliers")
	if not barrage_generation_multipliers_changed.is_connected(generation_callback):
		barrage_generation_multipliers_changed.connect(generation_callback)
	var lifetime_callback: Callable = Callable(barrage_area, "set_lifetime_multiplier")
	if not barrage_lifetime_multiplier_changed.is_connected(lifetime_callback):
		barrage_lifetime_multiplier_changed.connect(lifetime_callback)
	var neutral_callback: Callable = Callable(barrage_area, "set_neutral_weight_multiplier")
	if not neutral_weight_multiplier_changed.is_connected(neutral_callback):
		neutral_weight_multiplier_changed.connect(neutral_callback)
	var foreground_slot_callback: Callable = Callable(barrage_area, "set_foreground_slot_count")
	if not barrage_foreground_slot_count_changed.is_connected(foreground_slot_callback):
		barrage_foreground_slot_count_changed.connect(foreground_slot_callback)
	_publish_barrage_state()


func bind_audio_manager(audio_manager: Node) -> void:
	# 音效由共享 AudioManager 播放；重复绑定同一管理器不重复连接。
	var callback: Callable = Callable(audio_manager, "play_event")
	if not audio_event_requested.is_connected(callback):
		audio_event_requested.connect(callback)


func _on_final_player_pk_updated(final_player_pk: float) -> void:
	update_tier_for_pk(final_player_pk)


func try_tier_up(final_player_pk: float) -> bool:
	# 达到当前档位配置的升档阈值时最多升一档，Tier 5 留给矛盾阶段处理。
	if not _tier_changes_enabled or _current_tier >= 5:
		return false

	var current_config: CombatStageTierConfig = _tier_catalog.get_tier_config(_current_tier)
	if final_player_pk < current_config.upgrade_threshold:
		return false

	_current_tier += 1
	return true


func try_tier_down(final_player_pk: float) -> bool:
	# 只有 PK 严格低于当前档位的降档阈值时才下降一档。
	if not _tier_changes_enabled or _current_tier <= INITIAL_TIER:
		return false

	var current_config: CombatStageTierConfig = _tier_catalog.get_tier_config(_current_tier)
	if final_player_pk >= current_config.downgrade_threshold:
		return false

	_current_tier -= 1
	return true


func update_tier_for_pk(final_player_pk: float) -> bool:
	# 重复调用已实现的单档规则，直到该 PK 不再跨越升档或降档阈值。
	if not _tier_changes_enabled:
		return false
	var previous_tier: int = _current_tier
	var tier_changed: bool = false
	while try_tier_up(final_player_pk):
		tier_changed = true
	while try_tier_down(final_player_pk):
		tier_changed = true
	if tier_changed:
		_publish_current_tier_state()
		if _current_tier > previous_tier:
			# 多档上升仍只播放一次本次 Tier 升档事件。
			audio_event_requested.emit(&"tier_up")
	return tier_changed


func _publish_current_tier_state() -> void:
	# 先确定唯一当前 Tier，再把同一配置分别交给各系统。
	_publish_opponent_tier_state()
	_publish_barrage_state()
	tier_state_changed.emit(_current_tier)


func _publish_opponent_tier_state() -> void:
	# Tier 稳定后再广播最终倍率与 Tier 5 状态，不发送跨档中间值。
	var current_config: CombatStageTierConfig = _tier_catalog.get_tier_config(_current_tier)
	opponent_tier_state_changed.emit(
		current_config.opponent_pullback_multiplier,
		_current_tier == 5
	)


func _publish_barrage_state() -> void:
	# BarrageArea 接收当前档位配置；具体容量规则仍由弹幕生成任务消费名额。
	var current_config: CombatStageTierConfig = _tier_catalog.get_tier_config(_current_tier)
	barrage_generation_multipliers_changed.emit(
		current_config.generation_count_multiplier,
		current_config.generation_frequency_multiplier,
		current_config.movement_speed_multiplier
	)
	barrage_lifetime_multiplier_changed.emit(current_config.lifetime_multiplier)
	# Neutral 只按当前档位影响下一次普通话语抽取，不改写关卡基础权重。
	neutral_weight_multiplier_changed.emit(current_config.neutral_weight_multiplier)
	barrage_foreground_slot_count_changed.emit(current_config.foreground_slot_count)
