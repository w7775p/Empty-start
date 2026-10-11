extends SceneTree

const FX_SCRIPT: Script = preload("res://systems/presentation/combat_hit_feedback.gd")


# 只验证低噪声显示规则，不替代 Godot 实机画面与策划美术验收。
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fx: Control = FX_SCRIPT.new() as Control
	root.add_child(fx)
	fx.preview(0, 0)
	var value_label: Label = fx.get("_number") as Label
	if not _expect(value_label != null and value_label.visible and value_label.text == "+2", "normal shot shows net value at the reticle"):
		return
	if not _expect(_tags(fx).is_empty(), "normal shot has no duplicate HIT tag"):
		return
	var small_size: int = value_label.get_theme_font_size("font_size")
	var small_shadow: int = value_label.get_theme_constant("shadow_outline_size")
	fx.preview(0, 1)
	if not _expect(value_label.text == "+8" and value_label.get_theme_font_size("font_size") > small_size
		and value_label.get_theme_constant("shadow_outline_size") > small_shadow, "larger magnitude grows font and shadow"):
		return
	fx.preview(0, 2)
	if not _expect(_tags(fx).size() == 1 and (_tags(fx)[0] as Label).text == "BLOCK", "special hit keeps only its result keyword"):
		return
	fx.preview(0, 4)
	if not _expect(_tags(fx).size() == 2 and (_tags(fx)[0] as Label).text == "BLOCK"
		and (_tags(fx)[1] as Label).text == "REFLECT" and value_label.text == "-24", "multi-target effects show one net value and two exception keywords"):
		return
	fx.preview(0, 5)
	if not _expect(not value_label.visible and _tags(fx).size() == 1 and (_tags(fx)[0] as Label).text == "MISS", "miss shows MISS without redundant zero"):
		return
	for child in fx.get_children():
		if child is TextureRect:
			push_error("PA09_SMOKE_FAIL: normal hit must not create player comic TextureRect")
			quit(1)
			return
	print("PA09_FEEDBACK_SMOKE_PASS: six focused visual rules")
	quit(0)


func _tags(fx: Control) -> Array:
	return fx.get("_labels") as Array


func _expect(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
		return true
	push_error("PA09_SMOKE_FAIL: " + description)
	quit(1)
	return false
