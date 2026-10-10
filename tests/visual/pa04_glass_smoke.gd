extends SceneTree

var _checks: int = 0
const PACKED: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")


# 从真实 PackedScene 验证尺寸、倾向、富文本和移动边界等既有能力。
func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	var area := Control.new()
	area.size = Vector2(1800.0, 1100.0)
	root.add_child(area)
	var normal := _spawn(area, "神说：你必须被看见", "orthodox", 1, false)
	await process_frame
	print("PA04_DEBUG_SIZE=" + str(normal.size) + "; minimum=" + str(normal.get_combined_minimum_size()))
	if not _expect(normal.size.x < 440.0 and normal.size.x >= 150.0, "glass fits short sentence"):
		return
	var glass := normal.get_glass_surface()
	if not _expect(glass != null and glass.get_base_tint() == glass.orthodox_color, "orthodox palette follows runtime tendency"):
		return
	if not _expect(normal.get_visual_plain_text() == normal.runtime_record.text, "plain sentence keeps identity"):
		return
	if not _expect(normal.get_theme_constant("outline_size") > 0, "foreground text has outline"):
		return
	if not _expect(normal.get_theme_color("font_shadow_color").a > 0.0, "foreground text has tiny emboss shadow"):
		return
	var heresy := _spawn(area, "神意要被改写", "heretical", 2, false)
	var absurd := _spawn(area, "神是土豆", "absurd", 3, false)
	var neutral := _spawn(area, "谢谢支持", "neutral", 1, false)
	if not _expect(heresy.get_glass_surface().get_base_tint() == heresy.get_glass_surface().heretical_color, "heretical palette"):
		return
	if not _expect(absurd.get_glass_surface().get_base_tint() == absurd.get_glass_surface().absurd_color, "absurd palette"):
		return
	if not _expect(neutral.get_glass_surface().get_base_tint() == neutral.get_glass_surface().neutral_color, "neutral palette"):
		return
	if not _expect(absurd.get_glass_surface().get_base_tint() != normal.get_glass_surface().get_base_tint(), "palette remains distinct"):
		return
	var stronger := _spawn(area, "神说：你必须被看见", "orthodox", 3, false)
	if not _expect(stronger.get_glass_surface().max_border_width > 1.0, "three-level border configuration"):
		return
	var repeat := _spawn(area, "神说：你必须被看见", "orthodox", 1, true)
	if not _expect(repeat.get_theme_constant("outline_size") == 0, "repeat outline is zero"):
		return
	if not _expect(not repeat.set_visual_bbcode("[b]重复[/b]"), "repeat stays plain text"):
		return
	if not _expect(repeat.z_index < normal.z_index, "repeat is below foreground within area"):
		return
	if not _expect(normal.set_visual_bbcode("[color=#ffee88]神说[/color]：你必须被看见"), "foreground rich text opt-in"):
		return
	if not _expect(normal.get_visual_plain_text() == "神说：你必须被看见" and normal.runtime_record.original_sentence_id == "smoke_orthodox", "rich text preserves ID and plain content"):
		return
	if not _expect(normal.get_node("RichBody").visible, "rich text overlay visible"):
		return
	if not _expect(normal.set_visual_bbcode(""), "rich text can be reset"):
		return
	if not _expect(normal.text == normal.runtime_record.text, "rich text reset restores label"):
		return
	if not _expect(normal.pulse_presentation(1.1, 0.12), "pulse remains usable"):
		return
	await create_timer(0.20).timeout
	if not _expect(normal.scale.distance_to(Vector2.ONE) < 0.01, "pulse completes to original scale"):
		return
	var mover := _spawn(area, "移动测试", "neutral", 1, false, 100.0)
	mover.position = Vector2(900.0, 300.0)
	await create_timer(0.20).timeout
	if not _expect(mover.position.x < 895.0, "original moving lifecycle remains active"):
		return
	print("PA04_SMOKE_PASS; checks=%d" % _checks)
	quit()


# 每次都创建独立真实运行记录，并注入真实区域。
func _spawn(area: Control, message: String, tendency: String, strength: int, repeat: bool, speed: float = 0.0) -> BarrageView:
	var r := BarrageRuntimeRecord.new()
	r.text = message
	r.original_sentence_text = message
	r.original_sentence_id = "smoke_" + tendency
	r.tendency_id = tendency
	r.strength = float(strength)
	r.is_repeat = repeat
	r.expires_at_msec = Time.get_ticks_msec() + 60000
	var view := PACKED.instantiate() as BarrageView
	view.setup(r, speed, area)
	area.add_child(view)
	view.position = Vector2(500, 300)
	return view


# 所有断言以非零退出码呈现，避免将加载成功误判为视觉功能完成。
func _expect(condition: bool, description: String) -> bool:
	if not condition:
		push_error("PA04_SMOKE_FAIL: " + description)
		quit(1)
		return false
	_checks += 1
	print("PASS: " + description)
	return true
