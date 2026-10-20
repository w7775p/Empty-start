extends Control

const LIBRARY_SCENE := preload("res://tools/dialogue_studio/content_library_editor.tscn")
const TUTORIAL_SCENE := preload("res://tools/tutorial_editor/tutorial_editor.tscn")
const COMIC_SCENE := preload("res://tools/comic_copy_editor/comic_copy_editor.tscn")

func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 5)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "全游戏对话与气泡工作台"
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var help := Label.new()
	help.text = "各文案来源独立保存；改触发键前请核对程序接线"
	help.add_theme_color_override("font_color", Color("#c4b18a"))
	header.add_child(help)

	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var library := LIBRARY_SCENE.instantiate()
	tabs.add_child(library)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "游戏文案库")

	var tutorial := TUTORIAL_SCENE.instantiate()
	tabs.add_child(tutorial)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "新手教学")

	var comic := COMIC_SCENE.instantiate()
	tabs.add_child(comic)
	tabs.set_tab_title(tabs.get_tab_count() - 1, "开头 / 结尾漫画")
