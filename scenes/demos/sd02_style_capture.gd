extends SceneTree

const PREVIEW: PackedScene = preload("res://scenes/demos/sd02_style_compare_demo.tscn")
const OUTPUT: String = "res://docs/21. StreamerBubbleDialogue/evidence/SD-02_2026-10-10-v3/"


func _initialize() -> void:
	call_deferred("_capture")


# Actual GPU render in an offscreen Godot SubViewport; export both full-HD and 720p.
func _capture() -> void:
	var path: String = ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(path) != OK:
		push_error("SD02_STYLE_CAPTURE_DIR")
		quit(1)
		return
	var vp := SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(1920, 1080)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var sample: Control = PREVIEW.instantiate() as Control
	vp.add_child(sample)
	for i in range(3):
		sample.set_scenario(i)
		await process_frame
		await RenderingServer.frame_post_draw
		var filename: String = ["sd02_three_styles_short_1920.jpg", "sd02_three_styles_medium_1920.jpg", "sd02_three_styles_long_1920.jpg"][i]
		if not _save(vp, filename, Vector2i(1920, 1080)):
			quit(1)
			return
	vp.size = Vector2i(1280, 720)
	sample.scale = Vector2.ONE * (2.0 / 3.0)
	for mode in [0, 2]:
		sample.set_scenario(mode)
		await process_frame
		await RenderingServer.frame_post_draw
		var name: String = "sd02_three_styles_short_1280.jpg" if mode == 0 else "sd02_three_styles_long_1280.jpg"
		if not _save(vp, name, Vector2i(1280, 720)):
			quit(1)
			return
	print("SD02_STYLE_CAPTURE_PASS: 5 images / 3 designs / 3 scenarios")
	quit(0)


func _save(vp: SubViewport, name: String, expected: Vector2i) -> bool:
	var image: Image = vp.get_texture().get_image()
	var error: Error = image.save_jpg(ProjectSettings.globalize_path(OUTPUT + name), 0.93)
	print("SD02_STYLE_IMAGE %s error=%d size=%s" % [name, error, image.get_size()])
	return error == OK and image.get_size() == expected
