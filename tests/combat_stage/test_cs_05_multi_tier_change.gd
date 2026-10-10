extends SceneTree

# 同一条玩家 PK 路径覆盖阈值滞回和跨档；通过真实最终 PK 信号驱动阶段。
func _initialize() -> void:
	var catalog: CombatStageTierCatalog = load("res://data/combat_stage/tier_catalog.tres")
	var stage := CombatStage.new(catalog)
	var resolution := HitResolution.new(0.5, 0.0, 1.0)
	stage.bind_hit_resolution(resolution)
	stage.begin_combat()
	var failures: Array[String] = []
	resolution.set_player_pk_for_debug(0.559)
	if stage.get_current_tier() != 0:
		failures.append("below 56% must remain T0")
	resolution.set_player_pk_for_debug(0.56)
	if stage.get_current_tier() != 1:
		failures.append("56% must enter T1")
	resolution.set_player_pk_for_debug(0.53)
	if stage.get_current_tier() != 1:
		failures.append("53% must retain T1")
	resolution.set_player_pk_for_debug(0.529)
	if stage.get_current_tier() != 0:
		failures.append("below 53% must return T0")
	resolution.set_player_pk_for_debug(0.8)
	if stage.get_current_tier() != 4:
		failures.append("80% must cross to T4")
	resolution.set_player_pk_for_debug(0.95)
	if stage.get_current_tier() != 5:
		failures.append("95% must enter T5")
	resolution.set_player_pk_for_debug(0.52)
	if stage.get_current_tier() != 0:
		failures.append("52% must cross back to T0")
	if failures.is_empty():
		print("PASS CS-03/04/05: inclusive upgrade, strict downgrade and multi-tier PK changes")
	else:
		push_error("FAIL CS tier path: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)
