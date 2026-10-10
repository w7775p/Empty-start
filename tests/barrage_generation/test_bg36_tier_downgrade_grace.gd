extends SceneTree

const BARRAGE_AREA_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_area.tscn")
const TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const TEST_SPAWN_GAP_SECONDS: float = 0.08
const TEST_TIMEOUT_FRAMES: int = 240

var _observed_spawn_timeouts: int = 0


func _initialize() -> void:
	call_deferred("_run_test")


## 用真实 Tier、BarrageView 与 SpawnTimer 验证降档后的自然回落和延迟补位。
func _run_test() -> void:
	var area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	if area == null or TIER_CATALOG == null:
		push_error("FAIL BG-36: BarrageArea 或 Tier Catalog 加载失败")
		quit(1)
		return

	root.add_child(area)
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(1024.0, 2000.0)

	var stage := CombatStage.new(TIER_CATALOG)
	stage.bind_barrage_area(area)
	stage.begin_combat()
	var tier_3_reached: bool = stage.update_tier_for_pk(0.75) \
		and stage.get_current_tier() == 3 \
		and area.get_foreground_slot_count() == 16
	if not tier_3_reached:
		push_error("FAIL BG-36: CombatStage did not publish T3=16")
		quit(1)
		return

	var profile := LevelProfile.new()
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 0.6
	profile.base_move_speed_pixels_per_second = 30.0
	profile.normal_barrage_screen_cap = 24
	profile.orthodox_ratio = 1.0
	var speech := LevelSpeech.new()
	speech.original_sentence_id = "bg36_downgrade_grace"
	speech.text = "降档保留既有前景话语"
	speech.tendency_id = "orthodox"
	speech.appearance_weight = 1.0
	profile.normal_speech_pool.append(speech)

	# 前四条使用较短的生成寿命，后十二条使用长寿命，便于观察自然回落到 12。
	area.base_lifetime_seconds = 4.0
	var initial_views: Array[BarrageView] = []
	for index: int in range(16):
		if index == 4:
			area.base_lifetime_seconds = 100.0
		var view: BarrageView = area.spawn_normal_barrage(profile, speech)
		if view == null:
			push_error("FAIL BG-36: real foreground view %d could not spawn" % (index + 1))
			area.queue_free()
			quit(1)
			return
		initial_views.append(view)
		if index < 15:
			await create_timer(TEST_SPAWN_GAP_SECONDS).timeout

	var initial_view_ids: Array[int] = []
	var initial_expiry_by_id: Dictionary = {}
	for view: BarrageView in initial_views:
		var instance_id: int = view.get_instance_id()
		initial_view_ids.append(instance_id)
		initial_expiry_by_id[instance_id] = view.runtime_record.expires_at_msec
	initial_view_ids.sort()

	# 开启普通生成时场上已满 16；首次补位尝试应被容量账本阻止并停表。
	profile.base_batch_count = 4
	var generation_started: bool = area.start_normal_generation(profile)
	var spawn_timer: Timer = area.get_node_or_null("SpawnTimer") as Timer
	if spawn_timer != null:
		spawn_timer.timeout.connect(_on_spawn_timer_timeout_observed)
	var full_t3_count: bool = _get_foreground_views(area).size() == 16
	var full_t3_timer_stopped: bool = spawn_timer != null and spawn_timer.is_stopped()
	var tier_2_reached: bool = stage.update_tier_for_pk(0.64) \
		and stage.get_current_tier() == 2 \
		and area.get_foreground_slot_count() == 13
	var retained_after_downgrade: bool = _has_exact_view_ids(area, initial_view_ids)
	var timer_stays_stopped_over_cap: bool = spawn_timer != null and spawn_timer.is_stopped()
	var deadlines_unchanged: bool = _initial_deadlines_unchanged(initial_views, initial_expiry_by_id)
	var overflow_blocked: bool = area.spawn_normal_barrage(profile, speech) == null \
		and _get_foreground_views(area).size() == 16
	var watched_view: BarrageView = initial_views[4]
	var watched_start_x: float = watched_view.position.x
	await create_timer(0.12).timeout
	var movement_continues: bool = is_instance_valid(watched_view) and watched_view.position.x < watched_start_x
	var still_over_capacity: bool = _get_foreground_views(area).size() == 16
	var timer_still_stopped: bool = spawn_timer != null and spawn_timer.is_stopped()
	var deadlines_still_unchanged: bool = _initial_deadlines_unchanged(initial_views, initial_expiry_by_id)

	# 等四条短寿命视图真实到期离树；占用仍为 13 时 Timer 必须停着，降到 12 才恢复。
	var naturally_reached_twelve: bool = false
	var observed_thirteen_timer_stopped: bool = false
	for _frame: int in range(TEST_TIMEOUT_FRAMES):
		var declining_count: int = _get_foreground_views(area).size()
		if declining_count == 13:
			observed_thirteen_timer_stopped = spawn_timer != null and spawn_timer.is_stopped()
		if declining_count == 12:
			naturally_reached_twelve = true
			break
		if declining_count < 12:
			break
		await process_frame
	var twelve_actual_views: Array[BarrageView] = _get_foreground_views(area)
	var timer_resumed_below_cap: bool = naturally_reached_twelve \
		and spawn_timer != null \
		and not spawn_timer.is_stopped() \
		and spawn_timer.time_left > 0.0
	var only_long_lived_views_remain: bool = _contains_all_long_lived_views(twelve_actual_views, initial_views)
	var tier_2_interval: float = profile.base_spawn_interval_seconds \
		/ TIER_CATALOG.get_tier_config(2).generation_frequency_multiplier
	var timer_uses_tier_2_interval: bool = spawn_timer != null \
		and is_equal_approx(spawn_timer.wait_time, tier_2_interval)

	if timer_resumed_below_cap:
		await create_timer(minf(tier_2_interval * 0.2, 0.1)).timeout
	var no_immediate_refill: bool = _get_foreground_views(area).size() == 12 \
		and spawn_timer != null \
		and not spawn_timer.is_stopped()
	var refill_completed: bool = await _wait_for_foreground_count(area, 13, true)
	var refilled_views: Array[BarrageView] = _get_foreground_views(area)
	var new_view_added: bool = _contains_new_view_id(refilled_views, initial_view_ids)
	var timer_timeout_observed: bool = _observed_spawn_timeouts > 0
	var timer_stops_at_tier_2_cap: bool = spawn_timer != null and spawn_timer.is_stopped()
	var retained_long_lifetimes: bool = _initial_deadlines_unchanged(initial_views.slice(4), initial_expiry_by_id)

	var failures: Array[String] = []
	if not generation_started or not full_t3_count or not full_t3_timer_stopped:
		failures.append("T3 setup: started=%s count16=%s timer_stopped=%s" % [generation_started, full_t3_count, full_t3_timer_stopped])
	if not tier_2_reached or not retained_after_downgrade or not timer_stays_stopped_over_cap:
		failures.append("downgrade: tier2=%s retained16=%s timer_stopped=%s" % [tier_2_reached, retained_after_downgrade, timer_stays_stopped_over_cap])
	if not overflow_blocked or not still_over_capacity or not timer_still_stopped:
		failures.append("over-capacity hold: overflow_blocked=%s count16=%s timer_stopped=%s" % [overflow_blocked, still_over_capacity, timer_still_stopped])
	if not deadlines_unchanged or not deadlines_still_unchanged or not movement_continues:
		failures.append("existing views: deadlines_before=%s deadlines_after=%s movement=%s" % [deadlines_unchanged, deadlines_still_unchanged, movement_continues])
	if not naturally_reached_twelve or not observed_thirteen_timer_stopped or not timer_resumed_below_cap or not only_long_lived_views_remain:
		failures.append("natural decline: count=%d timer_stopped_at_13=%s resumed_at_12=%s long_views_remain=%s" % [twelve_actual_views.size(), observed_thirteen_timer_stopped, timer_resumed_below_cap, only_long_lived_views_remain])
	if not timer_uses_tier_2_interval or not no_immediate_refill:
		failures.append("timed refill gate: interval=%s no_immediate_refill=%s" % [timer_uses_tier_2_interval, no_immediate_refill])
	if not refill_completed or refilled_views.size() != 13 or not new_view_added or not timer_timeout_observed or not timer_stops_at_tier_2_cap or not retained_long_lifetimes:
		failures.append("T2 refill: completed=%s count=%d new_view=%s timer_timeout=%s timer_stopped=%s old_deadlines=%s timeouts=%d timer_left=%.3f wait=%.3f" % [refill_completed, refilled_views.size(), new_view_added, timer_timeout_observed, timer_stops_at_tier_2_cap, retained_long_lifetimes, _observed_spawn_timeouts, spawn_timer.time_left if spawn_timer != null else -1.0, spawn_timer.wait_time if spawn_timer != null else -1.0])

	area.clear_barrages()
	area.queue_free()
	await process_frame
	if failures.is_empty():
		print("PASS BG-36: T3=16 retained on downgrade; natural 16→12 decline resumes timed T2 refill to 13")
	else:
		push_error("FAIL BG-36: %s" % "; ".join(failures))
	quit(0 if failures.is_empty() else 1)


## 返回场景树中仍有效且已经进入队列的前景 BarrageView。
func _get_foreground_views(area: BarrageArea) -> Array[BarrageView]:
	var views: Array[BarrageView] = []
	for child: Node in area.get_children():
		if child is BarrageView and not child.is_queued_for_deletion():
			var view: BarrageView = child as BarrageView
			if view.runtime_record != null and not view.runtime_record.is_repeat:
				views.append(view)
	return views


## 对比实际视图实例 ID，确认降档期间没有替换或清理旧弹幕。
func _has_exact_view_ids(area: BarrageArea, expected_ids: Array[int]) -> bool:
	var actual_ids: Array[int] = []
	for view: BarrageView in _get_foreground_views(area):
		actual_ids.append(view.get_instance_id())
	actual_ids.sort()
	return actual_ids == expected_ids


## 用 SceneTree 帧等待真实寿命到期及批次 Timer，不读取虚拟容量计数。
func _wait_for_foreground_count(area: BarrageArea, expected_count: int, allow_count_below: bool = false) -> bool:
	for _frame: int in range(TEST_TIMEOUT_FRAMES):
		var current_count: int = _get_foreground_views(area).size()
		if current_count == expected_count:
			return true
		if current_count < expected_count and not allow_count_below:
			return false
		await process_frame
	return false


## 对照记录生成时保存的绝对寿命截止值，确认降档没有改写旧实例寿命。
func _initial_deadlines_unchanged(views: Array, expiry_by_id: Dictionary) -> bool:
	for entry: Variant in views:
		var view: BarrageView = entry as BarrageView
		if view == null or not is_instance_valid(view):
			continue
		var instance_id: int = view.get_instance_id()
		if expiry_by_id.has(instance_id) and view.runtime_record.expires_at_msec != int(expiry_by_id[instance_id]):
			return false
	return true


## 回落至 12 时仅保留初始长寿命实例，四条短寿命视图必须已自然离树。
func _contains_all_long_lived_views(actual_views: Array[BarrageView], initial_views: Array[BarrageView]) -> bool:
	if actual_views.size() != 12:
		return false
	for index: int in range(4, initial_views.size()):
		if not actual_views.has(initial_views[index]):
			return false
	return true


## 补位后确认新增的是实际 BarrageView 实例，旧实例 ID 均保持原值。
func _contains_new_view_id(actual_views: Array[BarrageView], initial_ids: Array[int]) -> bool:
	var new_count: int = 0
	for view: BarrageView in actual_views:
		if not initial_ids.has(view.get_instance_id()):
			new_count += 1
	return new_count == 1


## 观察场景中实际 SpawnTimer 的 timeout 信号，不依赖容量计数推断计时。
func _on_spawn_timer_timeout_observed() -> void:
	_observed_spawn_timeouts += 1
