extends SceneTree

const AREA_SCENE = preload("res://systems/barrage_generation/barrage_area.tscn")
const TIER_CATALOG = preload("res://data/combat_stage/tier_catalog.tres")

var _notification_count: int = 0


# 本卡仅一个关键用例；内容和静止视图均为 TEST_ONLY 内存夹具。
func _init() -> void:
	call_deferred("_run_test")


# 用真实锁句与区域接口验证空场、89% 到 90% 和首次收束。
func _run_test() -> void:
	var area: BarrageArea = AREA_SCENE.instantiate() as BarrageArea
	root.add_child(area)
	area.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	area.size = Vector2(600, 400)
	var spread := DivineDescentSpread.new()
	root.add_child(spread)
	spread.convergence_started.connect(_on_convergence_started)
	var run_data := SaveData.new()
	run_data.tendency_state = TendencyState.new()
	run_data.committed_normal_hit_history = [{
		"original_sentence_id": "TEST_ONLY_dd13_locked",
		"original_sentence_text": "TEST_ONLY locked",
		"tendency": "orthodox", "hit_count": 1, "first_committed_hit_order": 1,
	}]
	var session := DivineDescentSession.new()
	var mode := DivineDescentCombatMode.new()
	var decay := DivineDescentDecayConfig.new()
	decay.new_word_decay_duration_seconds = 1.0
	var passed: bool = session.enter(run_data)
	passed = mode.enter_terminal_mode(TIER_CATALOG) and passed
	passed = mode.start_new_word_decay(decay) and passed
	passed = spread.bind_new_word_decay(mode) and passed
	passed = spread.start(session, area, null, 60.0, 60.0, "") and passed
	var views: Array[BarrageView] = []
	for index: int in range(100):
		views.append(_add_test_view(area, index, index < 89))
	# 即使所有可见句均匹配，未锁句也保持扩散。
	views[89].runtime_record.original_sentence_id = "TEST_ONLY_dd13_locked"
	for index: int in range(90, 100):
		views[index].hide()
	await process_frame
	await process_frame
	passed = not spread.is_converging() and _notification_count == 0 and passed
	area.hide()
	mode.advance_new_word_decay(1.0)
	await process_frame
	await process_frame
	passed = spread.is_sentence_locked() and spread.get_locked_visible_ratio() == 0.0 and passed
	passed = not spread.is_converging() and _notification_count == 0 and passed
	area.show()
	views[89].runtime_record.original_sentence_id = "TEST_ONLY_dd13_other"
	for view: BarrageView in views:
		view.show()
	await process_frame
	await process_frame
	passed = spread.get_locked_visible_ratio() == 0.89 and not spread.is_converging() and passed
	views[89].runtime_record.original_sentence_id = "TEST_ONLY_dd13_locked"
	await process_frame
	await process_frame
	passed = spread.get_locked_visible_ratio() == 0.9 and spread.is_converging() and passed
	passed = _notification_count == 1 and not spread.is_running() and passed
	await process_frame
	await process_frame
	passed = _notification_count == 1 and passed
	area.free()
	spread.free()
	if passed:
		print("PASS DD-13 90% threshold: unlocked/empty/89% stay; 90% converges once, Timer stopped (1/1)")
	else:
		push_error("FAIL DD-13 90% convergence threshold")
	quit(0 if passed else 1)


# 只记录首次收束通知，重复帧继续核对通知次数。
func _on_convergence_started(_candidate: Dictionary) -> void:
	_notification_count += 1


# 静止弹幕显式标记 TEST_ONLY，正式资源和身份内容保持原值。
func _add_test_view(area: BarrageArea, index: int, locked: bool) -> BarrageView:
	var view := BarrageView.new()
	view.name = "TEST_ONLY_dd13_view_%d" % index
	view.runtime_record = BarrageRuntimeRecord.new()
	view.runtime_record.original_sentence_id = "TEST_ONLY_dd13_locked" if locked else "TEST_ONLY_dd13_other"
	view.text = "TEST_ONLY %d" % index
	view.position = Vector2((index % 5) * 115 + 5, (index / 5) * 18 + 5)
	area.add_child(view)
	view.set_process(false)
	return view
