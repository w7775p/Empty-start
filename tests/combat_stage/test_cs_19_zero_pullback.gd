extends SceneTree

const TIER_CATALOG_PATH := "res://data/combat_stage/tier_catalog.tres"


# 直接核对正式 Tier Resource，避免测试夹具替代实际配置。
func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var catalog: Resource = load(TIER_CATALOG_PATH)
	var failures: Array[String] = []
	if catalog == null:
		push_error("FAIL CS-19: 正式 Tier Catalog 加载失败")
		quit(1)
		return

	var tier_zero: Resource = catalog.call("get_tier_config", 0)
	var tier_one: Resource = catalog.call("get_tier_config", 1)
	if tier_zero == null or not is_equal_approx(float(tier_zero.get("opponent_pullback_multiplier")), 0.0):
		failures.append("正式 T0 opponent_pullback_multiplier 必须为 0")
	if tier_one == null or not is_equal_approx(float(tier_one.get("opponent_pullback_multiplier")), 1.3):
		failures.append("正式 T1 opponent_pullback_multiplier 必须保留 1.3")

	if failures.is_empty():
		print("PASS CS-19: official Tier Catalog T0=0 and T1=1.3")
	else:
		push_error("FAIL CS-19: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)
