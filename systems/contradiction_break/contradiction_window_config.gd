class_name ContradictionWindowConfig
extends Resource

## Paradox 窗口与移动配置；固定候选规模由下方常量定义，不沿用进入前的狂热档位。
const PARADOX_TRUE_CANDIDATE_COUNT: int = 1
const PARADOX_FALSE_CANDIDATE_COUNT: int = 5
const PARADOX_CANDIDATE_COUNT: int = PARADOX_TRUE_CANDIDATE_COUNT + PARADOX_FALSE_CANDIDATE_COUNT

@export var duration_seconds: float = 10.0
@export var max_shots: int = 1
@export var generation_count_multiplier: float = 2.0
@export var generation_frequency_multiplier: float = 3.0
@export var movement_speed_multiplier: float = 2.5
