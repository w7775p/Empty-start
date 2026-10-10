extends Control

const PREVIEW_FOLDER: String = "res://docs/Shared/PresentationAssets/previews"

@onready var _reticle: AimReticle = $AimReticle

var _charge_amount: float = 0.0
var _auto_charge: bool = false
var _space_held: bool = false
var _is_paused: bool = false
var _capture_mode: bool = false
var _slider: HSlider
var _status: Label
var _fire_finished_count: int = 0


# 在正式直播 PNG 和 Kiwi 立绘前测试真实准星组件，全部按钮只驱动表现接口。
func _ready() -> void:
	_build_demo_ui()
	_reticle.restore_mouse_aim(Vector2(960, 485))
	_reticle.animation_finished.connect(_on_effect_finished)
	if OS.get_cmdline_user_args().has("--capture-pa08"):
		_capture_mode = true
		call_deferred("_run_capture_sequence")


# 模拟 CombatAttack 的蓄力事实；独立演示不生成实际的命中与 PK 结果。
func _process(delta: float) -> void:
	if _is_paused or _capture_mode:
		return
	if _auto_charge or _space_held:
		_charge_amount = minf(1.0, _charge_amount + delta / 1.6)
		_slider.set_value_no_signal(_charge_amount)
	if not _reticle.is_shot_feedback_playing():
		_reticle.set_charge_visual_state(_charge_amount, _auto_charge or _space_held, _charge_amount >= 0.999)
	_update_status()


# 常用键支持快捷展示；空格松开时模拟一次成功 / 未蓄满取消。
func _input(event: InputEvent) -> void:
	if _capture_mode or not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	if key.echo:
		return
	if key.keycode == KEY_SPACE:
		if key.pressed:
			_begin_charge()
			_space_held = true
			_auto_charge = false
		else:
			_space_held = false
			if _charge_amount >= 0.999:
				_fire()
			else:
				_reset()
		get_viewport().set_input_as_handled()
	elif key.pressed and key.keycode == KEY_ENTER:
		_fire()
		get_viewport().set_input_as_handled()
	elif key.pressed and key.keycode == KEY_R:
		_reset()
		get_viewport().set_input_as_handled()
	elif key.pressed and key.keycode == KEY_P:
		_toggle_pause()
		get_viewport().set_input_as_handled()


# 布置有正式场景材质的演示 HUD、蓄力滑杆和真实可点击调试按钮。
func _build_demo_ui() -> void:
	_add_label("PA-08  /  RING RETICLE", Vector2(66, 54), 50, Color("#f1f6ff"))
	_add_label("Godot procedural art  /  visual component preview", Vector2(69, 127), 24, Color("#a4c5cf"))
	_add_label("Actual portrait & livestream textures  •  1920 × 1080", Vector2(1320, 85), 20, Color("#cde5ee"))
	var panel := PanelContainer.new()
	panel.position = Vector2(65, 757)
	panel.custom_minimum_size = Vector2(895, 252)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.055, 0.073, 0.92)
	style.border_color = Color(0.38, 0.87, 0.87, 0.65)
	style.set_border_width_all(2)
	style.set_corner_radius_all(17)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 11)
	panel.add_child(column)
	var top := Label.new()
	top.text = "AIM CONTROL   /   SPACE : HOLD   ENTER : FIRE   R : RESET   P : PAUSE"
	top.add_theme_font_size_override("font_size", 20)
	top.add_theme_color_override("font_color", Color("#d5eefa"))
	column.add_child(top)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 22)
	_status.add_theme_color_override("font_color", Color("#65f9d6"))
	column.add_child(_status)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.custom_minimum_size = Vector2(760, 28)
	_slider.value_changed.connect(_on_slider_changed)
	column.add_child(_slider)
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 13)
	column.add_child(button_row)
	_add_button(button_row, "AUTO CHARGE", _begin_charge)
	_add_button(button_row, "FIRE", _fire)
	_add_button(button_row, "RESET", _reset)
	_add_button(button_row, "PAUSE", _toggle_pause)
	_update_status()


# 统一生成字体信息，便于实际画面验收布局。
func _add_label(content: String, where: Vector2, point_size: int, tint: Color) -> void:
	var label := Label.new()
	label.text = content
	label.position = where
	label.add_theme_font_size_override("font_size", point_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


# 构建按钮并立即接入实际动作。
func _add_button(parent: HBoxContainer, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(185, 56)
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(action)
	parent.add_child(button)


# 演示的充能可以反复从零启动。
func _begin_charge() -> void:
	_is_paused = false
	_reticle.set_visual_paused(false)
	_reticle.reset_visual_state()
	_charge_amount = 0.0
	_auto_charge = true
	_slider.set_value_no_signal(0.0)


# 手动拉滑杆展示不同进度，包括闭合的满蓄环。
func _on_slider_changed(value: float) -> void:
	_auto_charge = false
	_space_held = false
	_charge_amount = clampf(value, 0.0, 1.0)
	_reticle.set_charge_visual_state(_charge_amount, _charge_amount > 0.0, _charge_amount >= 0.999)


# 发射只驱动视觉：正式集成由 shot_snapshot_created 信号触发。
func _fire() -> void:
	_auto_charge = false
	_space_held = false
	_charge_amount = 0.0
	_slider.set_value_no_signal(0.0)
	_reticle.play_shot_feedback()
	_update_status()


# 任何视觉状态都可回到待机，并保持准心定位。
func _reset() -> void:
	_auto_charge = false
	_space_held = false
	_charge_amount = 0.0
	_slider.set_value_no_signal(0.0)
	_reticle.reset_visual_state()
	_update_status()


# 暂停保留进度；恢复后进度和短时动画继续。
func _toggle_pause() -> void:
	_is_paused = not _is_paused
	_reticle.set_visual_paused(_is_paused)
	_update_status()


# 展示当前可见状态；不是实际战斗数值。
func _update_status() -> void:
	if _status == null:
		return
	var mode := "PAUSED" if _is_paused else ("FIRING" if _reticle.is_shot_feedback_playing() else ("FULL" if _charge_amount >= 0.999 else ("CHARGING" if _charge_amount > 0.0 else "IDLE")))
	_status.text = "VISUAL STATE : %s     CHARGE : %3d%%    FINISHED : %d" % [mode, roundi(_charge_amount * 100.0), _fire_finished_count]


# 完成通知由组件自己发出，演示只记录次数用于重播核对。
func _on_effect_finished() -> void:
	_fire_finished_count += 1
	_update_status()


# 截图入口只在额外命令行传入 --capture-pa08 时运行，截图来自真实图形视口。
func _run_capture_sequence() -> void:
	var directory := ProjectSettings.globalize_path(PREVIEW_FOLDER)
	var err := DirAccess.make_dir_recursive_absolute(directory)
	if err != OK:
		push_error("PA08_CAPTURE_DIRECTORY_ERROR=%d" % err)
		get_tree().quit(1)
		return
	_reticle.set_visual_paused(false)
	_reticle.reset_visual_state()
	_reticle.restore_mouse_aim(Vector2(995, 496))
	await get_tree().create_timer(0.30).timeout
	_status.text = "VISUAL STATE : IDLE     CHARGE : 0%"
	await RenderingServer.frame_post_draw
	_save_capture("idle")
	_reticle.set_charge_visual_state(0.58, true, false)
	_slider.set_value_no_signal(0.58)
	await get_tree().create_timer(0.24).timeout
	_status.text = "VISUAL STATE : CHARGING     CHARGE : 58%"
	await RenderingServer.frame_post_draw
	_save_capture("charging")
	_reticle.set_charge_visual_state(1.0, true, true)
	_slider.set_value_no_signal(1.0)
	await get_tree().create_timer(0.20).timeout
	_status.text = "VISUAL STATE : FULL     CHARGE : 100%"
	await RenderingServer.frame_post_draw
	_save_capture("full")
	_reticle.play_shot_feedback()
	_slider.set_value_no_signal(0.0)
	await get_tree().create_timer(0.045).timeout
	_status.text = "VISUAL STATE : FIRE     SHOT FLASH"
	await RenderingServer.frame_post_draw
	_save_capture("firing")
	await get_tree().create_timer(0.25).timeout
	if _fire_finished_count != 1:
		push_error("PA08_CAPTURE_SIGNAL_ERROR: count=%d" % _fire_finished_count)
		get_tree().quit(2)
		return
	print("PA08_CAPTURE_DONE; finish_signals=%d" % _fire_finished_count)
	get_tree().quit()


# 图形视口画面直接落盘，像素结果由实际 GPU 渲染产生。
func _save_capture(stage: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var png_path: String = ProjectSettings.globalize_path(PREVIEW_FOLDER.path_join("pa08_" + stage + ".png"))
	var result: Error = image.save_png(png_path)
	print("PA08_CAPTURE_%s=%d; size=%s" % [stage.to_upper(), result, image.get_size()])
	if result != OK:
		push_error("PA08_CAPTURE_WRITE_FAILED: " + png_path)
