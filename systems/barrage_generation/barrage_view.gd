## 单条弹幕的运行与外观。保留 Label 根节点及原有攻击/阶段接口。
class_name BarrageView
extends Label

const REPEAT_Z_INDEX: int = 0
const FOREGROUND_Z_INDEX: int = 1
const OCCLUSION_Z_INDEX: int = RenderingServer.CANVAS_ITEM_Z_MAX
enum ForegroundMotionMode { STRAIGHT, CURVED, SPEED_CHANGE, WANDERING }
const LOCAL_TEXT_ANIMATION_KINDS: Array[StringName] = [&"shake", &"pulse", &"wave", &"tornado"]

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
var _foreground_motion_mode: ForegroundMotionMode = ForegroundMotionMode.STRAIGHT
var _move_speed_pixels_per_second: float = 0.0
var _move_direction: Vector2 = Vector2.LEFT
var _wandering_motion_active: bool = false
var _wandering_direction: Vector2 = Vector2.LEFT
var _wandering_direction_change_interval_seconds: float = 0.0
var _wandering_direction_change_elapsed_seconds: float = 0.0
var _stationary_position: bool = false
var _contradiction_ease_out_curve: Curve
var _contradiction_ease_out_duration_seconds: float = 0.0
var _contradiction_ease_out_elapsed_seconds: float = 0.0
var _contradiction_ease_out_active: bool = false
var _requested_curve_amplitude_pixels: float = 0.0
var _speed_change_cycle_seconds: float = 0.0
var _speed_change_elapsed_seconds: float = 0.0
var _foreground_layer_change_interval_seconds: float = 0.0
var _foreground_layer_change_elapsed_seconds: float = 0.0
var _motion_curve: Curve2D
var _motion_curve_origin: Vector2 = Vector2.ZERO
var _motion_curve_offset: float = 0.0
var _active_area: Control
var _pause_started_msec: int = -1
var _presentation_tween: Tween
var _presentation_base_scale: Vector2 = Vector2.ONE
var _presentation_pulse_multiplier: float = 1.0
var _animated_size_enabled: bool = false
var _animated_size_min_scale: float = 1.0
var _animated_size_max_scale: float = 1.0
var _animated_size_cycle_seconds: float = 0.0
var _animated_size_phase: float = 0.0
var _animated_size_multiplier: float = 1.0
var _presentation_trait_ids: Array[StringName] = []
var _visual_bbcode: String = ""


# 进入树后让 Label 内部最小尺寸缓存完成，再按文字真实收缩宽度。
func _ready() -> void:
	if runtime_record != null:
		_fit_visual_to_sentence(runtime_record.text)
		_apply_special_text_layout()


# 记录终局冻结的特性 ID；复读保留灰色，普通前景继续使用对应倾向色。
func apply_terminal_trait_presentation(trait_ids: Array[StringName], trait_colors: Dictionary) -> void:
	_presentation_trait_ids = trait_ids.duplicate()
	if runtime_record != null and runtime_record.is_repeat:
		return
	for trait_id: StringName in _presentation_trait_ids:
		if trait_colors.get(trait_id) is Color:
			_set_visual_font_color(trait_colors[trait_id])
			break


# 返回冻结的表现 ID 副本。
func get_presentation_trait_ids() -> Array[StringName]:
	return _presentation_trait_ids.duplicate()


# 组合短时表现脉冲与 BG-27 缓和缩放；实际命中矩形沿用 Control 当前变换。
func pulse_presentation(scale_multiplier: float, return_seconds: float) -> bool:
	if not is_inside_tree() or is_queued_for_deletion() or get_tree().paused:
		return false
	if not is_finite(scale_multiplier) or scale_multiplier <= 1.0 or not is_finite(return_seconds) or return_seconds <= 0.0:
		return false
	if _presentation_tween != null and _presentation_tween.is_valid():
		_presentation_tween.kill()
	else:
		_presentation_base_scale = scale / maxf(_animated_size_multiplier, 0.0001)
	_presentation_pulse_multiplier = scale_multiplier
	_apply_presentation_scale()
	_presentation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_presentation_tween.tween_property(self, "_presentation_pulse_multiplier", 1.0, return_seconds)
	_presentation_tween.finished.connect(_on_presentation_tween_finished)
	return true


# 为单条普通移动话语配置平滑缩放；复读、矛盾、静止实例不会启用。
func configure_animated_size(min_scale: float, max_scale: float, cycle_seconds: float) -> bool:
	if runtime_record == null or runtime_record.is_repeat or runtime_record.is_contradiction or _stationary_position:
		return false
	if not is_finite(min_scale) or not is_finite(max_scale) or not is_finite(cycle_seconds):
		return false
	if min_scale <= 0.0 or min_scale >= 1.0 or max_scale <= 1.0 or max_scale <= min_scale or cycle_seconds <= 0.0:
		return false

	_animated_size_min_scale = min_scale
	_animated_size_max_scale = max_scale
	_animated_size_cycle_seconds = cycle_seconds
	_animated_size_phase = randf()
	_animated_size_enabled = true
	_presentation_base_scale = scale
	pivot_offset = size * 0.5
	_animated_size_multiplier = _get_animated_size_multiplier()
	_apply_presentation_scale()
	return true


# 为单条矛盾设置减速演出；释放快照仍读取该视图当下的可见矩形。
func configure_contradiction_ease_out(duration_seconds: float, speed_curve: Curve) -> bool:
	if (runtime_record == null or not runtime_record.is_contradiction or speed_curve == null
			or speed_curve.get_point_count() < 2 or not is_finite(duration_seconds)
			or duration_seconds <= 0.0 or speed_curve.sample(0.0) <= 0.0
			or speed_curve.sample(1.0) > 0.001):
		return false
	_contradiction_ease_out_curve = speed_curve
	_contradiction_ease_out_duration_seconds = duration_seconds
	_contradiction_ease_out_elapsed_seconds = 0.0
	_contradiction_ease_out_active = true
	return true


# 在进入场景树前配置单条视图；复读初始透明度恢复可见，移动参数由入口传入。
func setup(
	barrage_record: BarrageRuntimeRecord,
	move_speed_pixels_per_second: float,
	active_area: Control,
	stationary_position: bool = false,
	curve_amplitude_pixels: float = 0.0,
	speed_change_cycle_seconds: float = 0.0,
	move_direction: Vector2 = Vector2.LEFT,
	foreground_layer_change_interval_seconds: float = 0.0,
	foreground_motion_mode: ForegroundMotionMode = ForegroundMotionMode.STRAIGHT
) -> void:
	runtime_record = barrage_record
	_foreground_motion_mode = foreground_motion_mode
	text = barrage_record.text
	_stationary_position = stationary_position
	_move_speed_pixels_per_second = 0.0 if stationary_position else move_speed_pixels_per_second
	_move_direction = move_direction.normalized() if move_direction.length_squared() > 0.0001 else Vector2.LEFT
	_wandering_motion_active = false
	_wandering_direction = Vector2.LEFT
	_wandering_direction_change_interval_seconds = 0.0
	_wandering_direction_change_elapsed_seconds = 0.0
	_requested_curve_amplitude_pixels = maxf(curve_amplitude_pixels, 0.0) if is_finite(curve_amplitude_pixels) else 0.0
	_speed_change_cycle_seconds = maxf(speed_change_cycle_seconds, 0.0) if is_finite(speed_change_cycle_seconds) else 0.0
	_speed_change_elapsed_seconds = 0.0
	_foreground_layer_change_interval_seconds = (
		maxf(foreground_layer_change_interval_seconds, 0.0)
		if is_finite(foreground_layer_change_interval_seconds) else 0.0
	)
	_foreground_layer_change_elapsed_seconds = 0.0
	_active_area = active_area
	_presentation_base_scale = scale
	if barrage_record.is_repeat:
		var initial_modulate: Color = modulate
		initial_modulate.a = 1.0
		modulate = initial_modulate
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 真复读固定在底层；遮挡固定在最前，其余前景从普通层级带随机抽取。
	var has_occlusion: bool = (
		barrage_record.trait_set != null and barrage_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION)
	)
	if has_occlusion:
		z_index = OCCLUSION_Z_INDEX
	elif barrage_record.is_repeat:
		z_index = REPEAT_Z_INDEX
	else:
		z_index = randi_range(FOREGROUND_Z_INDEX, OCCLUSION_Z_INDEX - 1)
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_visual_bbcode = ""
	_set_visual_material()
	_fit_visual_to_sentence(barrage_record.text)
	# PA-05 只读取现有实例 TraitSet，选择外观不改变战斗结算或命中对象。
	var special: BarrageSpecialSurface = get_glass_surface() as BarrageSpecialSurface
	if special != null and barrage_record.trait_set != null and not barrage_record.is_repeat:
		# 复制品装饰文字与前景话语使用同一描边参数。
		special.configure_traits(
			barrage_record.trait_set.get_trait_ids(), barrage_record.text, get_theme_font("font"),
			foreground_outline_size, outline_color
		)
	_apply_special_text_layout()


## 供验收与演示读取该视图实际选中的普通前景运动类型。
func get_foreground_motion_mode() -> ForegroundMotionMode:
	return _foreground_motion_mode


# 进入独立 BG-23 游荡状态，不改写 BG-20 使用的直线方向。
func configure_wandering_motion(direction_change_interval_seconds: float) -> bool:
	if (runtime_record == null or runtime_record.is_repeat or runtime_record.is_contradiction
			or _stationary_position or not is_instance_valid(_active_area)
			or _move_speed_pixels_per_second <= 0.0 or not is_finite(direction_change_interval_seconds)
			or direction_change_interval_seconds <= 0.0):
		return false

	# BG-18 从边缘出生后先留在区域内，再朝区域中心游荡。
	var max_position: Vector2 = Vector2(
		maxf(_active_area.size.x - size.x, 0.0), maxf(_active_area.size.y - size.y, 0.0)
	)
	position.x = clampf(position.x, 0.0, max_position.x)
	position.y = clampf(position.y, 0.0, max_position.y)
	var center_offset: Vector2 = _active_area.size * 0.5 - (position + size * 0.5)
	if center_offset.length_squared() <= 0.0001:
		center_offset = Vector2.RIGHT.rotated(randf_range(0.0, TAU))

	_wandering_motion_active = true
	_foreground_motion_mode = ForegroundMotionMode.WANDERING
	_wandering_direction = center_offset.normalized()
	_wandering_direction_change_interval_seconds = direction_change_interval_seconds
	_wandering_direction_change_elapsed_seconds = 0.0
	return true


# 普通前景应用局部 BBCode；显示正文必须和运行记录原文一致，复读始终保留纯文本。
func set_visual_bbcode(bbcode: String) -> bool:
	if runtime_record == null or runtime_record.is_repeat or _uses_fake_repeat_appearance() or get_special_material() == &"retaliation_copy":
		return false
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich == null:
		return false
	if bbcode.is_empty():
		_visual_bbcode = ""
		rich.text = ""
		rich.hide()
		text = runtime_record.text
		_fit_visual_to_sentence(runtime_record.text)
		return true
	rich.text = bbcode
	if rich.get_parsed_text() != runtime_record.text:
		# 配置正文不匹配时恢复原文，避免表现覆盖战斗记录事实。
		rich.text = ""
		rich.hide()
		text = runtime_record.text
		_visual_bbcode = ""
		_fit_visual_to_sentence(runtime_record.text)
		push_warning("BarrageView: BBCode 正文与运行记录原文不一致，已回退纯文本。")
		return false
	_visual_bbcode = bbcode
	rich.show()
	text = ""
	_fit_visual_to_sentence(runtime_record.text)
	_fit_visual_to_rich_text(rich)
	return true


## 在普通原句的短片段上随机应用一种低强度 RichTextLabel 原生动画。
func apply_random_local_text_animation(probability: float) -> bool:
	if (not is_inside_tree() or runtime_record == null or runtime_record.is_repeat
			or runtime_record.is_contradiction or not is_finite(probability)):
		return false
	if runtime_record.trait_set != null and not runtime_record.trait_set.get_trait_ids().is_empty():
		# 特性有独立表现语义，局部文字动画不覆盖它们。
		return false
	if randf() >= clampf(probability, 0.0, 1.0):
		return false
	var source_bbcode: String = _visual_bbcode if not _visual_bbcode.is_empty() else runtime_record.text
	var selected_text: String = ""
	var source_index: int = -1
	for _attempt: int in range(8):
		var selected_range: Vector2i = _choose_local_text_animation_range(runtime_record.text)
		if selected_range.x < 0:
			return false
		selected_text = runtime_record.text.substr(selected_range.x, selected_range.y)
		source_index = _find_plain_segment_in_bbcode(source_bbcode, selected_text)
		if source_index >= 0:
			break
	if source_index < 0:
		# 无法安全定位既有富文本正文时保留原样式，不猜测要插入的位置。
		return false

	var animation_kind: StringName = LOCAL_TEXT_ANIMATION_KINDS[randi_range(0, LOCAL_TEXT_ANIMATION_KINDS.size() - 1)]
	var open_tag: String
	match animation_kind:
		&"shake":
			open_tag = "[shake rate=8.0 level=1 connected=1]"
		&"pulse":
			open_tag = "[pulse freq=0.5 color=#fffdf2e6 ease=-2.0]"
		&"wave":
			open_tag = "[wave amp=2.0 freq=1.6 connected=1]"
		&"tornado":
			open_tag = "[tornado radius=1.0 freq=0.8 connected=1]"
		_:
			return false
	var end_tag: String = "[/%s]" % String(animation_kind)
	var animated_bbcode: String = (
		source_bbcode.substr(0, source_index) + open_tag + selected_text + end_tag
		+ source_bbcode.substr(source_index + selected_text.length())
	)
	if not set_visual_bbcode(animated_bbcode):
		return false
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich != null:
		# 弹幕节点为补偿寿命设为 ALWAYS；文字动画本身仍随游戏暂停。
		rich.process_mode = Node.PROCESS_MODE_PAUSABLE
	return true


## 读取已生效的局部动画 ID，供本机演示显示，不参与命中或结算。
func get_local_text_animation_kind() -> StringName:
	for animation_kind: StringName in LOCAL_TEXT_ANIMATION_KINDS:
		if _visual_bbcode.contains("[" + String(animation_kind) + " "):
			return animation_kind
	return &""


## 从当前原文抽取一个至四个可见字符，避开 BBCode 界符和空白。
func _choose_local_text_animation_range(sentence: String) -> Vector2i:
	if sentence.is_empty():
		return Vector2i(-1, 0)
	var candidates: Array[Vector2i] = []
	for start_index: int in range(sentence.length()):
		var max_length: int = mini(4, sentence.length() - start_index)
		for segment_length: int in range(1, max_length + 1):
			var fragment: String = sentence.substr(start_index, segment_length)
			if (fragment.strip_edges().is_empty() or fragment.contains("[") or fragment.contains("]")
					or fragment.contains("\n") or fragment.contains("\r") or fragment.contains("\t")):
				continue
			candidates.append(Vector2i(start_index, segment_length))
	if candidates.is_empty():
		return Vector2i(-1, 0)
	return candidates[randi_range(0, candidates.size() - 1)]


## 在 BBCode 标签外定位可见片段，避免把动画标记插入标签参数。
func _find_plain_segment_in_bbcode(source_bbcode: String, selected_text: String) -> int:
	var inside_tag: bool = false
	var index: int = 0
	while index < source_bbcode.length():
		if source_bbcode.substr(index, 2) == "[[":
			index += 2
			continue
		var character: String = source_bbcode.substr(index, 1)
		if character == "[":
			inside_tag = true
			index += 1
			continue
		if character == "]":
			inside_tag = false
			index += 1
			continue
		if (not inside_tag and index + selected_text.length() <= source_bbcode.length()
				and source_bbcode.substr(index, selected_text.length()) == selected_text):
			return index
		index += 1
	return -1


# 外部可读取原句显示事实，不受富文本标签切换影响。
func get_visual_plain_text() -> String:
	return runtime_record.text if runtime_record != null else text


# 单个实例的材质选择，可供 PA-06 命中演出读取，无需重算 TraitSet。
func get_special_material() -> StringName:
	var special: BarrageSpecialSurface = get_glass_surface() as BarrageSpecialSurface
	return special.get_main_material() if special != null else &"glass"


# 透明字形依靠 Godot Label 的描边字形层，复制板内部小字由同一个 GlassSurface 绘制。
# 真假复读共用一套排版与颜色；假复读的 TraitSet/前景判定仍独立。
func _uses_fake_repeat_appearance() -> bool:
	if runtime_record == null or runtime_record.trait_set == null or runtime_record.is_repeat:
		return false
	var traits: BarrageTraitSet = runtime_record.trait_set
	return traits.has_trait(BarrageTraitSet.FAKE_CARD) \
		and not traits.has_trait(BarrageTraitSet.REFLECT) \
		and not traits.has_trait(BarrageTraitSet.OCCLUSION)


func _apply_special_text_layout() -> void:
	if runtime_record == null or runtime_record.trait_set == null or runtime_record.is_repeat:
		return
	if runtime_record.trait_set.has_trait(BarrageTraitSet.UNSELECTABLE):
		# 文字内芯保持接近透明，扩大笔画轮廓的可辨认面积并增加暗色投影。
		add_theme_font_size_override("font_size", visual_font_size + 4)
		add_theme_color_override("font_color", Color(0.96, 0.985, 1.0, 0.08))
		add_theme_color_override("font_outline_color", Color("#F5F9FF"))
		add_theme_constant_override("outline_size", 3)
		add_theme_color_override("font_shadow_color", Color(0.0, 0.04, 0.09, 0.96))
		add_theme_constant_override("shadow_offset_x", 1)
		add_theme_constant_override("shadow_offset_y", 1)
		_fit_visual_to_sentence(runtime_record.text)
	if get_special_material() == &"reflect":
		# 软胶有实体厚度，特性弹幕的显示/命中区域同步增高，文字仍保持居中稳定。
		custom_minimum_size = Vector2(maxf(size.x, 188.0), maxf(size.y, 78.0))
		reset_size()
	if get_special_material() == &"retaliation_copy":
		# 一个整体 Panel 对应同一条 BarrageView，扩大的 rect 继续由现有攻击命中几何使用。
		custom_minimum_size = Vector2(maxf(size.x, 460.0), 144.0)
		reset_size()
		text = ""
		var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
		if rich != null:
			rich.visible = false


# 演示和集成验收读取材质参数，不承担玩法计算。
func get_glass_surface() -> BarrageGlassSurface:
	return get_node_or_null("GlassSurface") as BarrageGlassSurface


# 用对应文字类型配置默认填充、阴影、描边与 RichTextLabel 可选覆盖层。
func _set_visual_material() -> void:
	var repeat: bool = runtime_record != null and (runtime_record.is_repeat or _uses_fake_repeat_appearance())
	# 假牌可以借用复读调色；只有真实复读实例关闭前景描边。
	var is_repeat: bool = runtime_record != null and runtime_record.is_repeat
	var surface: BarrageGlassSurface = get_glass_surface()
	if surface != null and runtime_record != null:
		surface.configure(runtime_record.tendency_id, 1 if repeat else roundi(runtime_record.strength), repeat)
	_set_visual_font_color(repeat_font_color if repeat else foreground_font_color)
	add_theme_color_override("font_outline_color", Color.TRANSPARENT if is_repeat else outline_color)
	var strong: bool = not repeat and runtime_record != null and roundi(runtime_record.strength) >= 3
	add_theme_constant_override("outline_size", 0 if is_repeat else foreground_outline_size + (1 if strong else 0))
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
		rich.add_theme_color_override("font_outline_color", Color.TRANSPARENT if is_repeat else outline_color)
		rich.add_theme_constant_override("outline_size", 0 if is_repeat else foreground_outline_size + (1 if strong else 0))
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
	if runtime_record != null and (runtime_record.is_repeat or _uses_fake_repeat_appearance()):
		font_size = maxi(14, visual_font_size - 3)
	elif runtime_record != null and runtime_record.trait_set != null and runtime_record.trait_set.has_trait(BarrageTraitSet.UNSELECTABLE):
		font_size = visual_font_size + 4
	var font_width: float = font.get_string_size(sentence, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var content_width: float = clampf(font_width + 4.0, 100.0, max_glass_width - float(horizontal_padding) * 2.0)
	var multi_size: Vector2 = font.get_multiline_string_size(sentence, HORIZONTAL_ALIGNMENT_LEFT, content_width, font_size)
	var new_size: Vector2 = Vector2(content_width + horizontal_padding * 2.0, maxf(48.0, multi_size.y + vertical_padding * 2.0))
	custom_minimum_size = new_size
	reset_size()
	if _animated_size_enabled:
		pivot_offset = new_size * 0.5
	var rich: RichTextLabel = get_node_or_null("RichBody") as RichTextLabel
	if rich != null:
		rich.position = Vector2(horizontal_padding, vertical_padding * 0.5)
		rich.size = Vector2(new_size.x - horizontal_padding * 2.0, new_size.y - vertical_padding)
		rich.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


# 按局部字体 / 字号的实际排版高度扩展弹幕框，避免富文本被裁切。
func _fit_visual_to_rich_text(rich: RichTextLabel) -> void:
	var required_height: float = float(rich.get_content_height()) + vertical_padding
	if required_height <= size.y:
		return
	custom_minimum_size.y = required_height
	reset_size()
	rich.size = Vector2(size.x - horizontal_padding * 2.0, size.y - vertical_padding)


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


# 复读透明度按剩余寿命连续计算；暂停时由到期补偿保持当前比例。
func _update_repeat_fade(current_time_msec: int) -> void:
	if not runtime_record.is_repeat or runtime_record.lifetime_duration_msec <= 0:
		return
	var remaining_msec: int = maxi(runtime_record.expires_at_msec - current_time_msec, 0)
	var alpha_ratio: float = clampf(
		float(remaining_msec) / float(runtime_record.lifetime_duration_msec), 0.0, 1.0
	)
	var current_modulate: Color = modulate
	current_modulate.a = alpha_ratio
	modulate = current_modulate


# 普通移动前景按独立间隔换到不同的前景 Z，遮挡与复读沿用固定层级。
func _update_moving_foreground_layer(delta: float) -> void:
	if runtime_record.is_repeat or runtime_record.is_contradiction or _stationary_position:
		return
	if _move_speed_pixels_per_second <= 0.0:
		return
	if _foreground_layer_change_interval_seconds <= 0.0:
		return
	if runtime_record.trait_set != null and runtime_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION):
		return

	_foreground_layer_change_elapsed_seconds += maxf(delta, 0.0)
	if _foreground_layer_change_elapsed_seconds < _foreground_layer_change_interval_seconds:
		return
	_foreground_layer_change_elapsed_seconds = fposmod(
		_foreground_layer_change_elapsed_seconds, _foreground_layer_change_interval_seconds
	)
	# 从剩余普通层级中抽样，保证本次更新真的改变覆盖顺序。
	var next_layer_index: int = randi_range(FOREGROUND_Z_INDEX, OCCLUSION_Z_INDEX - 2)
	if next_layer_index >= z_index:
		next_layer_index += 1
	z_index = next_layer_index

# 移动、复读淡出与自然结束沿用运行记录寿命；区域继续负责空间与实例释放。
func _process(delta: float) -> void:
	if runtime_record == null:
		return
	var current_time_msec: int = Time.get_ticks_msec()
	if _update_pause_compensation(get_tree().paused, current_time_msec):
		return
	_update_repeat_fade(current_time_msec)
	if current_time_msec >= runtime_record.expires_at_msec:
		queue_free()
		return
	if _animated_size_enabled:
		_animated_size_phase = fposmod(
			_animated_size_phase + maxf(delta, 0.0) / _animated_size_cycle_seconds, 1.0
		)
		_animated_size_multiplier = _get_animated_size_multiplier()
	_apply_presentation_scale()
	_update_moving_foreground_layer(delta)
	if runtime_record.is_contradiction:
		_advance_contradiction_ease_out(delta)
		if not is_instance_valid(_active_area):
			queue_free()
			return
		if not Rect2(Vector2.ZERO, _active_area.size).intersects(Rect2(position, size)):
			queue_free()
		return
	if _stationary_position:
		# 窗口缩放后继续完整留在当前区域；空间不足时销毁并沿用离树释放容量。
		if not _constrain_stationary_position_to_area():
			queue_free()
		return
	if _wandering_motion_active:
		_process_wandering_motion(delta)
		return
	var current_move_speed: float = _get_current_move_speed(delta)
	if _requested_curve_amplitude_pixels > 0.0 and _ensure_curved_motion():
		_move_along_curve(delta, current_move_speed)
	else:
		position += _move_direction * current_move_speed * delta
	if not is_instance_valid(_active_area):
		queue_free()
		return
	var active_rect: Rect2 = Rect2(Vector2.ZERO, _active_area.size)
	if not active_rect.intersects(Rect2(position, size)):
		queue_free()


# 游荡实例按间隔转向，并在区域边缘反射，原寿命仍由通用流程处理。
func _process_wandering_motion(delta: float) -> void:
	if not is_instance_valid(_active_area):
		queue_free()
		return

	_wandering_direction_change_elapsed_seconds += maxf(delta, 0.0)
	if _wandering_direction_change_elapsed_seconds >= _wandering_direction_change_interval_seconds:
		_wandering_direction_change_elapsed_seconds = fposmod(
			_wandering_direction_change_elapsed_seconds, _wandering_direction_change_interval_seconds
		)
		var turn_sign: float = -1.0 if randi_range(0, 1) == 0 else 1.0
		var turn_angle: float = deg_to_rad(randf_range(55.0, 125.0))
		_wandering_direction = _wandering_direction.rotated(turn_sign * turn_angle).normalized()

	var move_distance: float = _get_current_move_speed(delta) * maxf(delta, 0.0)
	var next_position: Vector2 = position + _wandering_direction * move_distance
	var max_x: float = maxf(_active_area.size.x - size.x, 0.0)
	var max_y: float = maxf(_active_area.size.y - size.y, 0.0)
	if next_position.x < 0.0 or next_position.x > max_x:
		_wandering_direction.x *= -1.0
		next_position.x = clampf(next_position.x, 0.0, max_x)
	if next_position.y < 0.0 or next_position.y > max_y:
		_wandering_direction.y *= -1.0
		next_position.y = clampf(next_position.y, 0.0, max_y)
	position = next_position


# 按归一化速度曲线移动到截止时刻，之后留在本次生成的最终位置。
func _advance_contradiction_ease_out(delta: float) -> void:
	if not _contradiction_ease_out_active or _contradiction_ease_out_curve == null:
		return
	var remaining_seconds: float = _contradiction_ease_out_duration_seconds - _contradiction_ease_out_elapsed_seconds
	var step_seconds: float = minf(maxf(delta, 0.0), remaining_seconds)
	if step_seconds <= 0.0:
		_contradiction_ease_out_active = false
		return
	var sample_progress: float = clampf(
		(_contradiction_ease_out_elapsed_seconds + step_seconds * 0.5)
		/ _contradiction_ease_out_duration_seconds,
		0.0,
		1.0
	)
	var speed_multiplier: float = clampf(_contradiction_ease_out_curve.sample(sample_progress), 0.0, 1.0)
	var move_distance: float = maxf(_move_speed_pixels_per_second, 0.0) * speed_multiplier * step_seconds
	position.x = maxf(position.x - move_distance, 0.0)
	_contradiction_ease_out_elapsed_seconds += step_seconds
	if _contradiction_ease_out_elapsed_seconds >= _contradiction_ease_out_duration_seconds:
		_contradiction_ease_out_active = false


# 用余弦曲线在最小与最大倍率间平滑往返，周期首尾速度为零。
func _get_animated_size_multiplier() -> float:
	var blend: float = 0.5 - 0.5 * cos(_animated_size_phase * TAU)
	return lerpf(_animated_size_min_scale, _animated_size_max_scale, blend)


# 把呼吸缩放与短时命中表现合成为单一 Control scale。
func _apply_presentation_scale() -> void:
	var target_scale: Vector2 = _presentation_base_scale * _animated_size_multiplier * _presentation_pulse_multiplier
	if not scale.is_equal_approx(target_scale):
		scale = target_scale


# Tween 完成后立即应用回落到当前呼吸倍率的尺寸。
func _on_presentation_tween_finished() -> void:
	_presentation_pulse_multiplier = 1.0
	_apply_presentation_scale()


## 普通前景沿平滑周期从零速加到 BG-40 上限，再平滑减速；周期两端保持连续。
func _get_current_move_speed(delta: float) -> float:
	if _speed_change_cycle_seconds <= 0.0:
		return _move_speed_pixels_per_second
	_speed_change_elapsed_seconds = fposmod(
		_speed_change_elapsed_seconds + maxf(delta, 0.0), _speed_change_cycle_seconds
	)
	var cycle_phase: float = _speed_change_elapsed_seconds / _speed_change_cycle_seconds
	var speed_progress: float = 1.0 - absf(cycle_phase * 2.0 - 1.0)
	# Smoothstep 让加速、减速的起点、峰值和周期接缝都没有速度突变。
	var eased_progress: float = speed_progress * speed_progress * (3.0 - 2.0 * speed_progress)
	return _move_speed_pixels_per_second * eased_progress


## 按生成方向构造单弧路径，幅度受区域各边界约束。
func _ensure_curved_motion() -> bool:
	if _motion_curve != null:
		return true
	if not is_instance_valid(_active_area) or _move_speed_pixels_per_second <= 0.0:
		return false
	var area_size: Vector2 = _active_area.size
	var travel_distance: float = area_size.x * absf(_move_direction.x) + area_size.y * absf(_move_direction.y)
	var curve_normal: Vector2 = Vector2(_move_direction.y, -_move_direction.x)
	var available_positive: float = _get_available_motion_space(curve_normal, area_size)
	var available_negative: float = _get_available_motion_space(-curve_normal, area_size)
	var available_height: float = 0.0
	if available_positive > 0.0 and available_negative > 0.0:
		if randi_range(0, 1) == 0:
			curve_normal = -curve_normal
			available_height = available_negative
		else:
			available_height = available_positive
	elif available_positive > 0.0:
		available_height = available_positive
	elif available_negative > 0.0:
		curve_normal = -curve_normal
		available_height = available_negative
	else:
		return false
	var curve_height: float = minf(_requested_curve_amplitude_pixels, available_height)
	if curve_height < 4.0 or travel_distance <= 0.0:
		return false
	var tangent_offset: Vector2 = _move_direction * travel_distance / 3.0
	var control_offset: Vector2 = curve_normal * curve_height * 4.0 / 3.0
	_motion_curve = Curve2D.new()
	_motion_curve.bake_interval = 2.0
	_motion_curve.add_point(Vector2.ZERO, Vector2.ZERO, tangent_offset + control_offset)
	_motion_curve.add_point(
		_move_direction * travel_distance, -tangent_offset + control_offset, Vector2.ZERO
	)
	_motion_curve_origin = position
	_motion_curve_offset = 0.0
	return _motion_curve.get_baked_length() > 0.0


## 返回当前完整视图沿给定方向可在区域内移动的最大距离。
func _get_available_motion_space(direction: Vector2, area_size: Vector2) -> float:
	var available_distance: float = INF
	if direction.x > 0.0:
		available_distance = minf(available_distance, (area_size.x - size.x - position.x) / direction.x)
	elif direction.x < 0.0:
		available_distance = minf(available_distance, position.x / -direction.x)
	if direction.y > 0.0:
		available_distance = minf(available_distance, (area_size.y - size.y - position.y) / direction.y)
	elif direction.y < 0.0:
		available_distance = minf(available_distance, position.y / -direction.y)
	return maxf(available_distance, 0.0)


## 沿细分弧长按当帧速度线性采样，避免加减速与曲线叠加后超过 BG-40 上限。
func _move_along_curve(delta: float, current_move_speed: float) -> void:
	var curve_length: float = _motion_curve.get_baked_length()
	_motion_curve_offset = minf(_motion_curve_offset + current_move_speed * delta, curve_length)
	position = _motion_curve_origin + _motion_curve.sample_baked(_motion_curve_offset, false)


## 将静止视图限制在区域内；缩小到容不下完整视图时交给现有生命周期移除。
func _constrain_stationary_position_to_area() -> bool:
	if not is_instance_valid(_active_area):
		return false
	var active_size: Vector2 = _active_area.size
	if size.x > active_size.x or size.y > active_size.y:
		return false
	position.x = clampf(position.x, 0.0, active_size.x - size.x)
	position.y = clampf(position.y, 0.0, active_size.y - size.y)
	return true
