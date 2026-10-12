class_name CombatStageTierConfig
extends Resource

@export var upgrade_threshold: float = 0.0
@export var downgrade_threshold: float = 0.0
@export var generation_count_multiplier: float = 1.0
@export var generation_frequency_multiplier: float = 1.0
@export var movement_speed_multiplier: float = 1.0
@export var lifetime_multiplier: float = 1.0
@export var neutral_weight_multiplier: float = 1.0
@export_group("普通前景运动权重")
## 直线相对权重；其他模式保持 0 作为正式策划配置前的安全默认。
@export_range(0.0, 100.0, 0.1) var straight_motion_weight: float = 1.0
## 曲线相对权重。
@export_range(0.0, 100.0, 0.1) var curved_motion_weight: float = 0.0
## 周期加减速相对权重。
@export_range(0.0, 100.0, 0.1) var speed_change_motion_weight: float = 0.0
## 低速游荡相对权重。
@export_range(0.0, 100.0, 0.1) var wandering_motion_weight: float = 0.0
@export var opponent_pullback_multiplier: float = 1.0
@export var repeat_count_per_hit: int = 0
# 0 表示本档前景名额尚未由策划填写。
@export var foreground_slot_count: int = 0
@export var opponent_portrait_state_id: StringName = &""
