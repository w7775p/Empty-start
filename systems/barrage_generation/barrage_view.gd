## 单条弹幕的运行与外观。保留 Label 根节点及原有攻击/阶段接口。
class_name BarrageView
extends Label

@export_group("文字玻璃统一样式")
@export_range(14, 42, 1) var visual_font_size: int = 24
@export_range(5, 26, 1) var horizontal_padding: int = 19
@export_range(4, 24, 1) var vertical_padding: int = 12
@export_range(150, 860, 10) var max_glass_width: float = 550.0
@export_range(1, 7, 1) var foreground_outline_size: int = 2
@export var foreground_font_color: Color = Color("#fffdf2")
@export var repeat_font_color: Color = Color("#b8bfcb")
@export var outline_color: Color = Color("#162131")
@export var text_shadow_color: Color = Color(0.03, 0.07, 0.13, 0.50)
@export_range(0, 5, 1) var text_shadow_offset: int = 2

var runtime_record: BarrageRuntimeRecord
var _move_speed_pixels_per_second: float = 0.0
var _active_area: Control
var _pause_started_msec: int = -1
var _presentation_tween: Tween
var _presentation_base_scale: Vector2
var _presentation_trait_ids: Array[StringName] = []
var _visual_bbcode: String = ""


# 进入树后让 Label 内部最小尺寸缓存完成，再按文字真实收缩宽度。
func _ready() -> void:
	if runtime_record != null:
		_fit_visual_to_sentence(runtime_record.text)


# 终局原有特性表现入口，仍按冻结的颜色优先级覆盖文字而不改变弹幕事实。
func apply_terminal_trait_presentation(trait_ids: Array[StringName], trait_colors: Dictionary) -> void:
	_presentation_trait_ids = trait_ids.duplicate()
	for trait_id: StringName in _presentation_trait_ids:
		if trait_colors.get(trait_id) is Color:
			_set_visual_font_color(trait_colors[trait_id])
			break


# 返回冻结的表现 ID 副本。
func get_presentation_trait_ids() -> Array[StringName]:
	return _presentation_trait_ids.duplicate()


# 缩放视觉本体，不更改实际话语、移动参数、弹幕判定与绝对寿命。
func pulse_presentation(scale_multiplier: float, return_seconds: float) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or get_tree().paused:
		return false
	if not is_finite(scale_multiplier) or scale_multiplier <= 1.0 or not is_finite(return_seconds) or return_seconds <= 0.0:
		return false
	if _presentation_tween != null and _presentation_tween.is_valid():
		_presentation_tween.kill()
	else:
		_presentation_base_scale = scale
	scale = _presentation_base_scale * scale_multiplier
	_presentation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_presentation_tween.tween_property(self, "scale", _presentation_base_scale, return_seconds)
	return true


# 在添加到区域之前即可配置尺寸和材质，保证生成排布读取的是实际显示范围。
func setup(barrage_record: BarrageRuntimeRecord, move_speed_pixels_per_second: float, active_area: Control) -> void:
	runtime_record = barrage_record
	text = barrage_record.text
	_move_speed_pixels_per_second = move_speed_pixels_per_second
	_active_area = active_area
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 层级只在弹幕区域内部比较：复读最低，前景留给后续特性更高层级。
	z_index = 0 if barrage_record.is_repeat else 1
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_visual_bbcode = ""
	_set_visual_material()
	_fit_visual_to_sentence(barrage_record.text)


# 独立视觉富文本接口。由 BG-28 的正式局部样式数据接入时调用，复读保留纯文本。
func set_visual_bbcode(bbcode: String) -> bool:
	if runtime_record == null or runtime_record.is_repeat:
		return false
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich == null:
		return false
	_visual_bbcode = bbcode
	rich.visible = not bbcode.is_empty()
	text = "" if rich.visible else runtime_record.text
	if rich.visible:
		rich.text = bbcode
	_fit_visual_to_sentence(runtime_record.text)
	return true


# 外部可读取原句显示事实，不受富文本标签切换影响。
func get_visual_plain_text() -> String:
	return runtime_record.text if runtime_record != null else text


# 演示和集成验收读取材质参数，不承担玩法计算。
func get_glass_surface() -> BarrageGlassSurface:
	return get_node_or_null("GlassSurface") as BarrageGlassSurface


# 用对应文字类型配置默认填充、阴影、描边与 RichTextLabel 可选覆盖层。
func _set_visual_material() -> void:
	var repeat: bool = runtime_record != null and runtime_record.is_repeat
	var surface: BarrageGlassSurface = get_glass_surface()
	if surface != null and runtime_record != null:
		surface.configure(runtime_record.tendency_id, roundi(runtime_record.strength), repeat)
	_set_visual_font_color(repeat_font_color if repeat else foreground_font_color)
	add_theme_color_override("font_outline_color", Color.TRANSPARENT if repeat else outline_color)
	var strong: bool = not repeat and runtime_record != null and roundi(runtime_record.strength) >= 3
	add_theme_constant_override("outline_size", 0 if repeat else foreground_outline_size + (1 if strong else 0))
	# S3 只加重文字笔画，不改变字号和已确定的气泡尺寸规则。
	if strong:
		var thick_font := FontVariation.new()
		thick_font.base_font = get_theme_font("font")
		thick_font.variation_embolden = 0.34
		add_theme_font_override("font", thick_font)
	add_theme_color_override("font_shadow_color", Color.TRANSPARENT if repeat else text_shadow_color)
	add_theme_constant_override("shadow_offset_x", 0 if repeat else text_shadow_offset)
	add_theme_constant_override("shadow_offset_y", 0 if repeat else text_shadow_offset)
	add_theme_font_size_override("font_size", visual_font_size if not repeat else visual_font_size - 3)
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich != null:
		rich.bbcode_enabled = true
		rich.scroll_active = false
		rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rich.visible = false
		rich.add_theme_color_override("default_color", repeat_font_color if repeat else foreground_font_color)
		rich.add_theme_color_override("font_outline_color", Color.TRANSPARENT if repeat else outline_color)
		rich.add_theme_constant_override("outline_size", 0 if repeat else foreground_outline_size + (1 if strong else 0))
		rich.add_theme_color_override("font_shadow_color", Color.TRANSPARENT if repeat else text_shadow_color)
		rich.add_theme_constant_override("shadow_offset_x", 0 if repeat else text_shadow_offset)
		rich.add_theme_constant_override("shadow_offset_y", 0 if repeat else text_shadow_offset)
		rich.add_theme_font_size_override("normal_font_size", visual_font_size if not repeat else visual_font_size - 3)
		rich.add_theme_font_size_override("bold_font_size", visual_font_size + 2)
		rich.add_theme_font_override("normal_font", get_theme_font("font"))


# 外部文字配色覆盖同步到已有富文本层。
func _set_visual_font_color(color: Color) -> void:
	add_theme_color_override("font_color", color)
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich != null:
		rich.add_theme_color_override("default_color", color)


# 通过当前 Theme 字体真实测量，短文本自动缩窄，长文本折行后提高命中矩形高度。
func _fit_visual_to_sentence(sentence: String) -> void:
	var font: Font = get_theme_font("font")
	var font_size: int = visual_font_size
	if runtime_record != null and runtime_record.is_repeat:
		font_size = maxi(14, visual_font_size - 3)
	var font_width: float = font.get_string_size(sentence, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var content_width: float = clampf(font_width + 4.0, 100.0, max_glass_width - float(horizontal_padding) * 2.0)
	var multi_size: Vector2 = font.get_multiline_string_size(sentence, HORIZONTAL_ALIGNMENT_LEFT, content_width, font_size)
	var new_size: Vector2 = Vector2(content_width + horizontal_padding * 2.0, maxf(48.0, multi_size.y + vertical_padding * 2.0))
	custom_minimum_size = new_size
	reset_size()
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich != null:
		rich.position = Vector2(horizontal_padding, vertical_padding * 0.5)
		rich.size = Vector2(new_size.x - horizontal_padding * 2.0, new_size.y - vertical_padding)
		rich.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# 暂停时记录起点；恢复后继续沿用原有的毫秒级到期补偿。
func _update_pause_compensation(is_tree_paused: bool, current_time_msec: int) -> bool:
	if is_tree_paused:
		if _pause_started_msec < 0:
			_pause_started_msec = current_time_msec
		return true
	if _pause_started_msec >= 0:
		runtime_record.expires_at_msec += current_time_msec - _pause_started_msec
		_pause_started_msec = -1
	return false


# 移动与自然结束继续只由区域和运行记录负责，外观不另建计时状态。
func _process(delta: float) -> void:
	if runtime_record == null:
		return
	var current_time_msec: int = Time.get_ticks_msec()
	if _update_pause_compensation(get_tree().paused, current_time_msec):
		return
	if current_time_msec >= runtime_record.expires_at_msec:
		queue_free()
		return
	position.x -= _move_speed_pixels_per_second * delta
	if not is_instance_valid(_active_area):
		queue_free()
		return
	var active_rect: Rect2 = Rect2(Vector2.ZERO, _active_area.size)
	if not active_rect.intersects(Rect2(position, size)):
		queue_free()
