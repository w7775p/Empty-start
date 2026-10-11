extends SceneTree

const DIR: String = "res://assets/ui/combat/impact_marks/"
const NAMES: Array[String] = [
	"impact_01_razor", "impact_02_ink", "impact_03_krak", "impact_04_manga"
]


# 从可编辑透明 SVG 生成正式独立透明 PNG，每份 512×512，可按需重新生成。
func _initialize() -> void:
	call_deferred("_export")


func _export() -> void:
	for asset_name: String in NAMES:
		var xml: String = FileAccess.get_file_as_string(DIR + asset_name + ".svg")
		if xml.is_empty():
			push_error("PA06_ASSET_SOURCE_MISSING: " + asset_name)
			quit(1)
			return
		var image: Image = Image.new()
		var error: Error = image.load_svg_from_string(xml, 2.0)
		if error != OK:
			push_error("PA06_ASSET_SVG_RENDER_FAILED: " + asset_name + " err=" + str(error))
			quit(1)
			return
		if image.get_size() != Vector2i(512, 512) or not image.detect_alpha():
			push_error("PA06_ASSET_BAD_DIMENSIONS_OR_ALPHA: " + asset_name)
			quit(1)
			return
		var output: String = DIR + asset_name + ".png"
		error = image.save_png(ProjectSettings.globalize_path(output))
		if error != OK:
			push_error("PA06_ASSET_PNG_SAVE_FAILED: " + asset_name)
			quit(1)
			return
		print("PA06_ASSET_OK: %s %s corner_alpha=%s" % [
			output, image.get_size(), image.get_pixel(0, 0).a
		])
	quit(0)
