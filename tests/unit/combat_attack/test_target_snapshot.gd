extends SceneTree

const AREA_SCENE = preload("res://systems/barrage_generation/barrage_area.tscn")
const VIEW_SCENE = preload("res://systems/barrage_generation/barrage_view.tscn")

func _init() -> void:
	call_deferred("_run")

# TEST_ONLY 真实视图：同发去重、释放后加入无效、移动保留、到期排除、矛盾原文冻结。
func _run() -> void:
	var area: BarrageArea = AREA_SCENE.instantiate()
	area.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.add_child(area)
	area.size = Vector2(1024, 800)
	var first: BarrageView = VIEW_SCENE.instantiate()
	var second: BarrageView = VIEW_SCENE.instantiate()
	var late: BarrageView = VIEW_SCENE.instantiate()
	# 直接装配视图避免随机落点和批次；生命周期复核使用产品公开接口。
	for view: BarrageView in [first, second, late]:
		var runtime_record := BarrageRuntimeRecord.new()
		runtime_record.text = "测试目标"
		runtime_record.original_sentence_id = "test_snapshot_%d" % view.get_instance_id()
		runtime_record.original_sentence_text = runtime_record.text
		runtime_record.capture_lifetime_at_spawn(Time.get_ticks_msec(), 60.0, 1.0)
		view.setup(runtime_record, 0.0, area)
		area.add_child(view)
		view.position = Vector2(100, 100)
	second.runtime_record.is_contradiction = true
	var second_id: String = second.runtime_record.original_sentence_id
	var candidates: Array[Node] = [first, first, second]
	var snapshot := AttackTargetSnapshot.capture_at_release(candidates, Vector2(100, 100))
	candidates.append(late)
	second.runtime_record.original_sentence_text = "释放后改变的文本"
	var ids: Array[int] = snapshot.get_target_instance_ids()
	var frozen: bool = ids.size() == 2 and ids.has(first.get_instance_id()) and ids.has(second.get_instance_id()) and not ids.has(late.get_instance_id())
	first.position = Vector2(300, 300)
	var present: Array[Node] = snapshot.resolve_present_targets(area)
	var moved_valid: bool = present.size() == 2 and present.has(first) and present.has(second)
	# 已到期但尚未被下一帧移除的目标，不能获得到达收益。
	first.runtime_record.expires_at_msec = Time.get_ticks_msec() - 1
	present = snapshot.resolve_present_targets(area)
	var expired_excluded: bool = present.size() == 1 and present[0] == second
	area.end_barrage(second.get_instance_id())
	var removed_excluded: bool = snapshot.resolve_present_targets(area).is_empty()
	var facts: Array[Dictionary] = snapshot.get_contradiction_facts()
	var contradiction_frozen: bool = facts.size() == 1 and facts[0].get("original_sentence_id") == second_id and facts[0].get("original_sentence_text") == "测试目标"
	var passed: bool = frozen and moved_valid and expired_excluded and removed_excluded and contradiction_frozen
	if passed:
		print("PASS CA snapshot: multi-target release freezes IDs/facts; movement survives; expiry/removal exclude")
	else:
		push_error("FAIL CA snapshot: frozen=%s moved=%s expired=%s removed=%s contradiction=%s" % [frozen, moved_valid, expired_excluded, removed_excluded, contradiction_frozen])
	area.clear_barrages()
	area.queue_free()
	await process_frame
	quit(0 if passed else 1)
