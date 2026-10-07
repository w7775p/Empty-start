## 集中保存普通战斗 Sandbox 的临时运行参数，正式数值表到位后替换资源来源。
class_name SandboxBattleConfig
extends Resource

@export var attack_timing: AttackTimingConfig
@export var initial_player_pk: float = 0.5
@export var minimum_player_pk: float = 0.0
@export var maximum_player_pk: float = 1.0
@export var base_pullback_speed: float = 0.001
@export var normal_lifetime_seconds: float = 10.0
@export var repeat_lifetime_seconds: float = 6.0
## 原始系统案写明每条矛盾命中产生 120 条复读；寿命暂用 Sandbox 运行配置。
@export var contradiction_repeat_count: int = 120
@export var contradiction_repeat_lifetime_seconds: float = 6.0
@export var maximum_pending_repeat_count: int = 96
@export var repeat_screen_cap: int = 24
@export var repeat_display_template: String = "复读 · {原句}"
