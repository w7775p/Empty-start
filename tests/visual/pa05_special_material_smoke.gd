extends SceneTree

const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")


# 只保护特性表现的外部行为与单实例事实；材质好不好看按真实 GPU 截图验收。
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var area := Control.new()
	area.size = Vector2(1920, 1080)
	root.add_child(area)

	# 多特性只选择一个主底板，优先级与实际结果接口一致。
	var combo: BarrageView = _spawn(area, "反弹遮挡组合", [&"occlusion", &"reflect"])
	var metal: BarrageView = _spawn(area, "遮挡话语", [&"occlusion"])
	var split: BarrageView = _spawn(area, "预裂话语", [&"split"])
	if not _check(combo.get_special_material() == &"reflect"
		and metal.get_special_material() == &"occlusion"
		and split.get_special_material() == &"split", "material precedence"):
		return

	# 空心文字应当是现有不可选话语；单独叠加不会改变玻璃底板。
	var outline: BarrageView = _spawn(area, "不能打中我", [&"unselectable"])
	if not _check(outline.get_special_material() == &"glass"
		and not outline.runtime_record.trait_set.is_selectable()
		and outline.get_theme_color("font_color").a < 0.01
		and outline.get_theme_constant("outline_size") > 0, "outline text on original glass"):
		return

	# 一条水军实例含多处小字，只有 BarrageView 这一份 Rect 和运行 ID。
	var copy: BarrageView = _spawn(area, "正在看着你", [&"retaliation_copy"])
	if not _check(copy.get_special_material() == &"retaliation_copy"
		and copy.size.x >= 460 and copy.size.y >= 144
		and copy.text == "" and copy.get_visual_plain_text() == "正在看着你"
		and copy.get_child_count() == 2
		and copy.runtime_record.trait_set.get_hit_result().kind == BarrageTraitResult.Kind.RETALIATION_COPY, "retaliation is one hit target"):
		return

	# 假复读是有描边前景；分裂后的子句及真正复读保持 PA-04 外观。
	var fake: BarrageView = _spawn(area, "快来关注", [&"fake_card"])
	var child: BarrageView = _spawn(area, "子话语", [])
	var repeat: BarrageView = _spawn(area, "灰色复读", [], true)
	if not _check(fake.get_special_material() == &"fake_card"
		and fake.z_index > repeat.z_index and fake.get_theme_constant("outline_size") > 0
		and child.get_special_material() == &"glass"
		and repeat.get_special_material() == &"glass"
		and repeat.get_theme_constant("outline_size") == 0, "fake, child and genuine repeat"):
		return

	print("PA05_SMOKE_PASS: 4 external behavior scenarios")
	quit(0)


# 真正生成 BarrageRuntimeRecord 和一份正式 BarrageView。
func _spawn(area: Control, line: String, traits: Array[StringName], repeat: bool = false) -> BarrageView:
	var record := BarrageRuntimeRecord.new()
	record.text = line
	record.original_sentence_text = line
	record.original_sentence_id = "pa05_" + line
	record.tendency_id = "orthodox"
	record.strength = 2.0
	record.is_repeat = repeat
	record.expires_at_msec = Time.get_ticks_msec() + 60000
	for id in traits:
		record.trait_set.add_trait(id)
	var view: BarrageView = VIEW.instantiate() as BarrageView
	view.setup(record, 0.0, area)
	area.add_child(view)
	view.position = Vector2(850, 510)
	return view


func _check(ok: bool, label: String) -> bool:
	if not ok:
		push_error("PA05_SMOKE_FAIL: " + label)
		quit(1)
		return false
	print("PASS: " + label)
	return true
