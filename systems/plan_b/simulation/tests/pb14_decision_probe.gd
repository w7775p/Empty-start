extends "res://systems/plan_b/simulation/plan_b_unit_simulation.gd"

var steering_call_count: int = 0
var steering_calls_by_id: Dictionary = {}
var neighbor_grid_rebuild_count: int = 0
var word_group_refresh_count: int = 0
var neutral_decisions_with_neighbors: int = 0
var faction_decisions_with_neighbors: int = 0


## 仅供 PB-14 smoke 统计决策频率；生产模拟器仍调用同一基类实现。
func _get_steering(unit: PlanBUnit, nearby_units: Array[PlanBUnit]) -> Dictionary:
	steering_call_count += 1
	steering_calls_by_id[unit.unit_id] = int(steering_calls_by_id.get(unit.unit_id, 0)) + 1
	if unit.team == &"neutral" and not nearby_units.is_empty():
		neutral_decisions_with_neighbors += 1
	elif unit.team != &"neutral" and not nearby_units.is_empty():
		faction_decisions_with_neighbors += 1
	return super._get_steering(unit, nearby_units)


## 记录测试场景中全量空间网格重建次数，不进入正式单位状态。
func _rebuild_neighbor_grid(units: Array[PlanBUnit]) -> void:
	neighbor_grid_rebuild_count += 1
	super._rebuild_neighbor_grid(units)


## 记录团体连通重建次数，用于确认事件能够合并到固定拓扑周期。
func _refresh_word_groups() -> void:
	word_group_refresh_count += 1
	super._refresh_word_groups()
