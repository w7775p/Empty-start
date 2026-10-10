extends SceneTree

const BARRAGE_AREA_SCENE := preload("res://systems/barrage_generation/barrage_area.tscn")
const TIER_CATALOG := preload("res://data/combat_stage/tier_catalog.tres")


func _initialize() -> void:
	call_deferred("_run_test")


## 用真实 BarrageArea、CombatStage 和 Tier 配置验证 T2 满槽后按计时补位。
func _run_test() -> void:
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	var tier_catalog: CombatStageTierCatalog = TIER_CATALOG as CombatStageTierCatalog
	if area == null or tier_catalog == null:
		push_error("FAIL BG-34: BarrageArea 或 Tier Catalog 加载失败")
		quit(1)
		return

	root.add_child(area)
	# 给实际弹幕视图留足纵向位置，单独验证 Timer 与容量，不覆盖 Sandbox 布局。
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(1024.0, 1200.0)

	var stage := CombatStage.new(tier_catalog)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	var tier_2_config: CombatStageTierConfig = tier_catalog.get_tier_config(2)
	var tier_2_reached: bool = stage.update_tier_for_pk(0.64)
	var tier_2_published: bool = tier_2_reached and stage.get_current_tier() == 2 \
		and area.get_foreground_slot_count() == 13

	var profile := LevelProfile.new()
	profile.base_batch_count = 4
	profile.base_spawn_interval_seconds = 1.0
	profile.base_move_speed_pixels_per_second = 0.0
	profile.normal_barrage_screen_cap = 24
	profile.orthodox_ratio = 1.0
	var speech := LevelSpeech.new()
	speech.original_sentence_id = "bg34_t2_refill"
	speech.text = "T2定时补位"
	speech.tendency_id = "orthodox"
	speech.appearance_weight = 1.0
	profile.normal_speech_pool.append(speech)

	var failures: Array[String] = []
	if not tier_2_published:
		failures.append("T2 publishes its configured 13 foreground slots")

	var generation_started: bool = area.start_normal_generation(profile)
	var effective_interval: float = profile.base_spawn_interval_seconds \
		/ tier_2_config.generation_frequency_multiplier
	# 初始批次立即生成，此后只允许现有 SpawnTimer 按倍率间隔补足容量。
	await create_timer(effective_interval * 3.0).timeout
	var initial_count: int = int(area.get_current_barrage_counts()["normal"])
	var filled_to_thirteen: bool = initial_count == 13
	var at_capacity_blocks_extra: bool = area.spawn_normal_barrage(profile, speech) == null \
		and int(area.get_current_barrage_counts()["normal"]) == 13
	if not generation_started or not filled_to_thirteen or not at_capacity_blocks_extra:
		failures.append("initial count=%d, started=%s, size=%s, interval=%.3f" % [
			initial_count, generation_started, area.size, effective_interval
		])

	var foreground_views: Array[BarrageView] = []
	for child in area.get_children():
		if child is BarrageView and not child.is_queued_for_deletion():
			foreground_views.append(child as BarrageView)
	if foreground_views.size() != 13:
		failures.append("the full T2 cap is represented by 13 real foreground views")

	var removed_four: bool = foreground_views.size() >= 13
	if removed_four:
		for index: int in range(4):
			if not area.end_barrage(foreground_views[index].get_instance_id()):
				removed_four = false
	var count_after_removal: int = int(area.get_current_barrage_counts()["normal"])
	var nine_after_removal: bool = count_after_removal == 9
	var no_immediate_refill: bool = false
	if removed_four:
		# 小于一个当前 Timer 周期时仍应保持 9 条，避免移除动作同步补位。
		await create_timer(effective_interval * 0.2).timeout
		no_immediate_refill = area.get_current_barrage_counts()["normal"] == 9
		await create_timer(effective_interval * 1.25).timeout
	var refilled_count: int = int(area.get_current_barrage_counts()["normal"])
	var refilled_to_thirteen: bool = refilled_count == 13
	var refill_stops_at_capacity: bool = area.spawn_normal_barrage(profile, speech) == null \
		and int(area.get_current_barrage_counts()["normal"]) == 13
	if not removed_four or not nine_after_removal or not no_immediate_refill \
		or not refilled_to_thirteen or not refill_stops_at_capacity:
		failures.append("removed=%s count_after_remove=%d before_timer=%s after_timer=%d" % [
			removed_four, count_after_removal,
			no_immediate_refill, refilled_count
		])

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS BG-34: T2=13 timed refill after four foreground removals")
	else:
		push_error("FAIL BG-34: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)
