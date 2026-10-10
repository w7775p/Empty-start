extends SceneTree

const VIEW_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const PRESENTER_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_presenter.gd")


# 测试对外事实：按最终 trait 选择反馈、整发遮挡、退场镜像以及子体原属性。
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Control.new()
	stage.size = Vector2(1920, 1080)
	root.add_child(stage)
	var barrage_area := Control.new()
	barrage_area.size = stage.size
	stage.add_child(barrage_area)
	var presenter: BarrageImpactPresenter = PRESENTER_SCRIPT.new() as BarrageImpactPresenter
	stage.add_child(presenter)
	presenter.size = stage.size

	var attack: AttackChargeInput = AttackChargeInput.new()
	presenter.bind_attack(attack)
	var normal: BarrageView = _spawn(barrage_area, "普通被击碎", [], Vector2(200, 220))
	var blocker: BarrageView = _spawn(barrage_area, "铁板保持完整", [&"occlusion"], Vector2(450, 220))
	var facts: Array[Dictionary] = [
		{"target": normal, "trait_result": normal.runtime_record.trait_set.get_hit_result()},
		{"target": blocker, "trait_result": blocker.runtime_record.trait_set.get_hit_result()}
	]
	attack.shot_arrival_resolved.emit(null, facts)
	if not _expect(presenter.get_active_effect_count() == 1
		and blocker.is_inside_tree() and not blocker.is_queued_for_deletion(),
		"occlusion absorbs whole shot, actual records remain"):
		return

	var jelly: BarrageView = _spawn(barrage_area, "果冻", [&"reflect"], Vector2(500, 490))
	var bounce: BarrageImpactFx = presenter.play_target_result(jelly, jelly.runtime_record.trait_set.get_hit_result())
	jelly.queue_free()
	await process_frame
	if not _expect(is_instance_valid(bounce) and bounce.get_effect_mode() == &"reflect"
		and bounce.get_child_count() == 1, "reflection outlives original view and compresses one duplicate"):
		return

	var broken: BarrageView = _spawn(barrage_area, "完整玻璃", [], Vector2(700, 260))
	var fracture: BarrageImpactFx = presenter.play_target_result(broken, broken.runtime_record.trait_set.get_hit_result())
	broken.queue_free()
	await process_frame
	if not _expect(is_instance_valid(fracture) and fracture.get_effect_mode() == &"normal",
		"normal fracture owns a temporary independent effect"):
		return

	var child_a: BarrageView = _spawn(barrage_area, "真实前句", [], Vector2(650, 690))
	var child_b: BarrageView = _spawn(barrage_area, "真实后句", [], Vector2(820, 690))
	var children: Array[BarrageView] = [child_a, child_b]
	presenter.play_spawned_split_children(children)
	await create_timer(0.23).timeout
	if not _expect(child_a.get_special_material() == &"glass" and child_b.get_special_material() == &"glass"
		and child_a.runtime_record.original_sentence_text == "真实前句"
		and child_b.runtime_record.original_sentence_text == "真实后句"
		and child_a.scale.distance_to(Vector2.ONE) < 0.04
		and child_b.scale.distance_to(Vector2.ONE) < 0.04, "real child instances retain their text and glass appearance"):
		return

	presenter.reset_effects()
	if not _expect(presenter.get_active_effect_count() == 0
		and is_instance_valid(blocker) and not blocker.is_queued_for_deletion(),
		"reset clears effects without touching live barrage targets"):
		return

	presenter.bind_attack(null)
	attack.free()
	print("PA06_SMOKE_PASS: 5 observable behavior scenarios")
	quit(0)


func _spawn(area: Control, text_line: String, trait_ids: Array[StringName], place: Vector2) -> BarrageView:
	var record := BarrageRuntimeRecord.new()
	record.text = text_line
	record.original_sentence_text = text_line
	record.original_sentence_id = "pa06_test_" + text_line
	record.tendency_id = "orthodox"
	record.strength = 2.0
	record.expires_at_msec = Time.get_ticks_msec() + 100000
	for trait_id: StringName in trait_ids:
		record.trait_set.add_trait(trait_id)
	var view: BarrageView = VIEW_SCENE.instantiate() as BarrageView
	view.setup(record, 0.0, area)
	area.add_child(view)
	view.position = place
	return view


func _expect(ok: bool, title: String) -> bool:
	if not ok:
		push_error("PA06_SMOKE_FAIL: " + title)
		quit(1)
		return false
	print("PASS: " + title)
	return true
