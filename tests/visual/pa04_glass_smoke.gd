extends SceneTree

const VIEW_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")


# PA-04 只做最小运行冒烟；颜色与 S1/S2/S3 视觉递进通过真实渲染图验收。
func _initialize() -> void:
	call_deferred("_smoke")


func _smoke() -> void:
	var area := Control.new()
	area.size = Vector2(1800, 1100)
	root.add_child(area)

	# 最容易破坏生成排布的变更：短句缩小底板、长句增加高度。
	var normal: BarrageView = _spawn(area, "神说：你必须被看见", false)
	var long_line: BarrageView = _spawn(area, "神说：你必须被看见；".repeat(16), false)
	await process_frame
	if not _expect(
		normal.size.x < 440.0 and long_line.size.x <= long_line.max_glass_width + 1.0
		and long_line.size.y > normal.size.y,
		"glass fits short and wrapped text"
	):
		return

	# 局部 BBCode 切换期间，必须保留战斗使用的原文与稳定 ID。
	var rich: bool = normal.set_visual_bbcode("[color=#ffe16b]神说[/color]：你必须被看见")
	var kept: bool = normal.runtime_record.original_sentence_id == "pa04_smoke" 		and normal.get_visual_plain_text() == "神说：你必须被看见"
	var restored: bool = normal.set_visual_bbcode("") and normal.text == normal.runtime_record.text
	if not _expect(rich and kept and restored, "rich text preserves the combat sentence"):
		return

	# 普通复读继续在前景下层，并保持无描边纯文本。
	var repeat: BarrageView = _spawn(area, "神说：你必须被看见", true)
	if not _expect(
		repeat.z_index < normal.z_index and repeat.get_theme_constant("outline_size") == 0
		and not repeat.set_visual_bbcode("[b]神说[/b]")
		and repeat.text == repeat.runtime_record.text,
		"repeat remains a lower plain-text layer"
	):
		return

	# 原有弹幕缩放表现与移动仍可由既有公开接口使用。
	normal.position = Vector2(800, 300)
	normal.pulse_presentation(1.12, 0.12)
	await create_timer(0.22).timeout
	if not _expect(normal.position.x < 790 and normal.scale.distance_to(Vector2.ONE) < 0.02, "movement and replay recover"):
		return

	print("PA04_SMOKE_PASS: 4 behavior scenarios")
	quit(0)


# 实例化同一份正式弹幕 Scene 与 RuntimeRecord，零复制玩法状态。
func _spawn(area: Control, message: String, is_repeat: bool) -> BarrageView:
	var record := BarrageRuntimeRecord.new()
	record.text = message
	record.original_sentence_text = message
	record.original_sentence_id = "pa04_smoke"
	record.tendency_id = "orthodox"
	record.strength = 2.0
	record.is_repeat = is_repeat
	record.expires_at_msec = Time.get_ticks_msec() + 60000
	var view: BarrageView = VIEW_SCENE.instantiate() as BarrageView
	view.setup(record, 100.0 if not is_repeat else 0.0, area)
	area.add_child(view)
	view.position = Vector2(500, 300)
	return view


# 只有可观测行为通过才输出 PASS，异常退出会让 CI 识别失败。
func _expect(valid: bool, description: String) -> bool:
	if not valid:
		push_error("PA04_SMOKE_FAIL: " + description)
		quit(1)
		return false
	print("PASS: " + description)
	return true
