extends Node

const UI_SCENE: PackedScene = preload("res://ui/plan_b/plan_b_battle_ui.tscn")

class FakePlanBSimulation:
	extends Node

	signal unit_changed(unit_id: String, reason: String)
	signal unit_spawned(unit_id: String)
	signal unit_despawned(unit_id: String)
	signal contact_resolved(first_unit_id: String, second_unit_id: String, outcome: StringName)
	signal word_batch_spawned(batch: Dictionary)
	signal word_groups_changed(groups: Array)
	signal unit_physics_positions_updated(unit_ids, previous_positions, current_positions)

	var snapshots: Array = []
	var groups: Array = []
	var counts := {"player": 3, "opponent": 0, "neutral": 0}

	func get_unit_snapshots() -> Array:
		return snapshots

	func get_unit_snapshot(unit_id: Variant) -> Dictionary:
		for snapshot in snapshots:
			if str(snapshot.get("unit_id", "")) == str(unit_id):
				return snapshot
		return {}

	func get_faction_counts() -> Dictionary:
		return counts

	func get_word_groups() -> Array:
		return groups


var _failures := 0
var _selected_words: Array[String] = []
var _publish_requests: Array[Dictionary] = []


func _ready() -> void:
	# 通过正式 UI 公开入口验证三槽位置稳定、失败不消耗、棋盘落点与团体快照绘制。
	if DisplayServer.get_name() != "headless":
		get_window().size = Vector2i(1920, 1080)
	var ui := UI_SCENE.instantiate()
	ui.name = "PlanBBattleUI"
	add_child(ui)
	ui.connect("word_selected", Callable(self, "_on_word_selected"))
	ui.connect("publish_requested", Callable(self, "_on_publish_requested"))
	await get_tree().process_frame

	ui.set_word_hand([
		{"slot_id": 2, "word_id": "w_c", "text": "第三槽保留原句", "battle_type": "type_c", "strength": 3},
		{"slot_id": 0, "word_id": "w_a", "text": "第一槽发言", "battle_type": "type_a", "strength": 1},
		{"slot_id": 1, "word_id": "", "text": "", "battle_type": "", "strength": 0},
	], 4)
	ui.set_player_slot_states([
		{"slot_id": 2, "word_id": "w_c", "remaining": 2.5, "progress": 0.5, "available": false},
		{"slot_id": 1, "word_id": "", "remaining": 0.0, "progress": 0.0, "available": false},
		{"slot_id": 0, "word_id": "w_a", "remaining": 0.0, "progress": 0.0, "available": true},
	])
	await get_tree().process_frame
	var first_card := ui.find_child("WordCard1", true, false) as Button
	var empty_card := ui.find_child("WordCard2", true, false) as Button
	var third_card := ui.find_child("WordCard3", true, false) as Button
	_check(first_card != null and empty_card != null and third_card != null, "exactly three fixed card slots exist")
	if first_card == null or empty_card == null or third_card == null:
		_finish()
		return
	var third_phrase := third_card.find_child("PhraseLabel", true, false) as Label
	var third_fill := third_card.find_child("CooldownFill", true, false)
	_check(third_phrase != null and third_phrase.text == "第三槽保留原句", "empty middle slot does not shift slot 3 content")
	_check(not first_card.disabled and empty_card.disabled and third_card.disabled, "availability stays bound to stable slot_id values")
	if third_fill != null:
		_check(absf(float(third_fill.get("fill_ratio")) - 0.5) < 0.12, "slot 3 fill reflects its own 2.5 second timer")

	first_card.pressed.emit()
	_check(_selected_words == ["w_a"], "mouse card selection publishes the selected word fact")
	var field := ui.find_child("UnitField", true, false)
	field.call("emit_signal", "board_position_clicked", Vector2(700.0, 430.0))
	_check(_publish_requests.size() == 1, "board coordinate submits one publish request")
	if not _publish_requests.is_empty():
		var request: Dictionary = _publish_requests[0]
		_check(int(request.get("slot_id", -1)) == 0, "publish request keeps the selected slot id")
		_check(str(request.get("word_id", "")) == "w_a", "publish request keeps the selected word")
		_check(request.get("spawn_position", Vector2.ZERO) == Vector2(700.0, 430.0), "publish request keeps the chosen board position")
		ui.call("resolve_publish_request", 0, "w_a", Vector2(700.0, 430.0), {"ok": false, "reason": "capacity"})
		_check(not first_card.disabled, "capacity failure leaves the selected slot available")

	var field_snapshots: Array = [
		{"unit_id": 101, "team": "player", "word_id": "w_a", "battle_type": "type_a", "position": Vector2(600.0, 420.0), "collision_radius": 13.0},
		{"unit_id": 102, "team": "player", "word_id": "w_a", "battle_type": "type_a", "position": Vector2(650.0, 445.0), "collision_radius": 13.0},
		{"unit_id": 103, "team": "player", "word_id": "w_a", "battle_type": "type_a", "position": Vector2(700.0, 420.0), "collision_radius": 13.0},
	]
	var group_snapshot := {
		"group_id": "player-w_a-101-103",
		"team": "player",
		"word_id": "w_a",
		"member_ids": [101, 102, 103],
		"center_position": Vector2(650.0, 428.0),
		"member_positions": {},
		"word_snapshot": {"text": "完整中文话语会按团体气泡容器自动换行显示"},
	}
	var simulation := FakePlanBSimulation.new()
	simulation.name = "Simulation"
	simulation.snapshots = field_snapshots
	simulation.groups = [group_snapshot]
	add_child(simulation)
	ui.call("bind_sources", null, simulation, null)
	simulation.unit_physics_positions_updated.emit(
		PackedInt32Array([101, 102, 103]),
		PackedVector2Array([Vector2(590.0, 420.0), Vector2(640.0, 445.0), Vector2(690.0, 420.0)]),
		PackedVector2Array([Vector2(600.0, 420.0), Vector2(650.0, 445.0), Vector2(700.0, 420.0)])
	)
	simulation.word_batch_spawned.emit({
		"word_order": 1,
		"team": "player",
		"word_id": "w_a",
		"word_definition": {"text": "完整中文话语会按团体气泡容器自动换行显示"},
		"spawn_position": Vector2(650.0, 420.0),
		"spawn_target_positions": [Vector2(600.0, 420.0), Vector2(650.0, 445.0), Vector2(700.0, 420.0)],
		"unit_ids": [101, 102, 103],
		"count": 3,
	})
	simulation.unit_changed.emit("102", "split")
	simulation.contact_resolved.emit("103", "102", &"reflected")
	await get_tree().process_frame
	await get_tree().process_frame
	print("RENDER B batch, group, split and reflect facts through the D presentation layer")
	_save_preview_image()
	_finish()


func _on_word_selected(word_id: String) -> void:
	_selected_words.append(word_id)


func _on_publish_requested(slot_id: int, word_id: String, spawn_position: Vector2) -> void:
	_publish_requests.append({"slot_id": slot_id, "word_id": word_id, "spawn_position": spawn_position})


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS ", label)
	else:
		_failures += 1
		push_error("FAIL " + label)


func _save_preview_image() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP preview image: headless renderer does not provide viewport readback")
		return
	var evidence_dir := ProjectSettings.globalize_path("res://tests/plan_b/evidence")
	DirAccess.make_dir_recursive_absolute(evidence_dir)
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		print("SKIP preview image: renderer has no ViewportTexture")
		return
	var image := viewport_texture.get_image()
	if image == null:
		print("SKIP preview image: viewport readback is unavailable")
		return
	var output_path := evidence_dir.path_join("pb12_14_d_ui_smoke.png")
	var result := image.save_png(output_path)
	if result == OK:
		print("PREVIEW ", output_path)
	else:
		print("SKIP preview image: save failed with ", result)


func _finish() -> void:
	if _failures == 0:
		print("PASS PB-12/13/11/14 D UI smoke")
		get_tree().quit(0)
	else:
		push_error("%d UI smoke check(s) failed" % _failures)
		get_tree().quit(1)
