class_name CombatStageTierConfig
extends Resource

@export var upgrade_threshold: float = 0.0
@export var downgrade_threshold: float = 0.0
@export var generation_count_multiplier: float = 1.0
@export var generation_frequency_multiplier: float = 1.0
@export var movement_speed_multiplier: float = 1.0
@export var lifetime_multiplier: float = 1.0
@export var neutral_weight_multiplier: float = 1.0
@export var opponent_pullback_multiplier: float = 1.0
@export var repeat_count_per_hit: int = 0
# 0 表示本档前景名额尚未由策划填写。
@export var foreground_slot_count: int = 0
@export var opponent_portrait_state_id: StringName = &""
