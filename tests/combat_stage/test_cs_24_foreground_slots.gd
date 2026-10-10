extends SceneTree

const TIER_CATALOG_PATH := "res://data/combat_stage/tier_catalog.tres"
const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")


# 用正式 Tier Resource 和真实 BarrageArea 节点验证数据独立性及档位发布。
func _initialize() -> void:
	# 延迟到 SceneTree 进入处理阶段后再创建区域，确保它的 SpawnTimer 已完成 @onready。
	call_deferred("_run_test")


func _run_test() -> void:
	var catalog: CombatStageTierCatalog = load(TIER_CATALOG_PATH) as CombatStageTierCatalog
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if catalog == null or area == null:
		push_error("FAIL CS-24: Tier Catalog 或 BarrageArea 加载失败")
		quit(1)
		return

	root.add_child(area)
	var stage := CombatStage.new(catalog)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	var failures: Array[String] = []
	var expected_counts: Array[int] = [0, 10, 13, 16, 19, 22]
	for tier: int in range(expected_counts.size()):
		var config: CombatStageTierConfig = catalog.get_tier_config(tier)
		if config == null or config.foreground_slot_count != expected_counts[tier]:
			failures.append("Tier %d expected slot count %d" % [tier, expected_counts[tier]])
	if area.get_foreground_slot_count() != 0:
		failures.append("T0 initial slot count must remain unconfigured")

	var tier_thresholds: Array[float] = [0.56, 0.64, 0.71, 0.79, 0.9]
	for index: int in range(tier_thresholds.size()):
		stage.update_tier_for_pk(tier_thresholds[index])
		var expected_tier: int = index + 1
		if stage.get_current_tier() != expected_tier:
			failures.append("expected CombatStage Tier %d" % expected_tier)
		if area.get_foreground_slot_count() != expected_counts[expected_tier]:
			failures.append("BarrageArea did not receive Tier %d slot count" % expected_tier)

	stage.update_tier_for_pk(0.52)
	if stage.get_current_tier() != 0 or area.get_foreground_slot_count() != 0:
		failures.append("return to T0 must publish its unconfigured slot count")

	var tier2_config: CombatStageTierConfig = catalog.get_tier_config(2)
	tier2_config.foreground_slot_count = 37
	if catalog.get_tier_config(1).foreground_slot_count != 10 or catalog.get_tier_config(3).foreground_slot_count != 16:
		failures.append("editing T2 must not change neighboring Tier resources")
	stage.update_tier_for_pk(0.64)
	if area.get_foreground_slot_count() != 37:
		failures.append("BarrageArea must expose the independently edited T2 count")
	tier2_config.foreground_slot_count = 13

	root.remove_child(area)
	area.free()
	if failures.is_empty():
		print("PASS CS-24: Tier 0-5 slot data, independent edits, and BarrageArea publication")
	else:
		push_error("FAIL CS-24: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)
