@tool
extends Control

enum DisplaySide { PLAYER_LEFT, OPPONENT_RIGHT }

const STAT_ICON_PATHS_BY_SIDE: Dictionary = {
	"player": {
		"viewer_count": "res://assets/ui/live/stats/player_viewers.png",
		"like_count": "res://assets/ui/live/stats/player_likes.png",
		"comment_count": "res://assets/ui/live/stats/player_comments.png",
		"fan_count": "res://assets/ui/live/stats/player_followers.png",
	},
	"opponent": {
		"viewer_count": "res://assets/ui/live/stats/opponent_viewers.png",
		"like_count": "res://assets/ui/live/stats/opponent_likes.png",
		"comment_count": "res://assets/ui/live/stats/opponent_comments.png",
		"fan_count": "res://assets/ui/live/stats/opponent_followers.png",
	},
}

# 展示方向只控制图标顺序和对齐。
@export var display_side: DisplaySide = DisplaySide.PLAYER_LEFT:
	set(value):
		display_side = value
		if is_node_ready():
			_refresh_stat_icon_side()
		_refresh_values()

# 默认订阅玩家当前周目；其他数据来源由组合方关闭此项并显式注入。
@export var auto_bind_player_session: bool = true

# 正式PNG优先显示；资源缺失时使用对应Emoji安全回退，数值仍复用原刷新入口。
@export_group("指标图标")
@export var viewer_icon: String = "👤":
	set(value):
		viewer_icon = value
		_refresh_values()
@export var like_icon: String = "👍":
	set(value):
		like_icon = value
		_refresh_values()
@export var comment_icon: String = "🔊":
	set(value):
		comment_icon = value
		_refresh_values()
@export var fan_icon: String = "👥":
	set(value):
		fan_icon = value
		_refresh_values()

@onready var _viewer_metric: RichTextLabel = %ViewerMetric
@onready var _like_metric: RichTextLabel = %LikeMetric
@onready var _comment_metric: RichTextLabel = %CommentMetric
@onready var _fan_metric: RichTextLabel = %FanMetric
@onready var _metrics: VBoxContainer = $Metrics

var _metric_rows: Dictionary = {}
var _metric_icon_rects: Dictionary = {}

var _live_session: LiveSessionData = null
# 仅缓存最近展示输入，避免图标或方向变化时从 k 文本反推并丢失整数。
var _display_values: Array[int] = [0, 0, 0, 0]
var _comment_rows: Array[Dictionary] = []
var _comment_params: Dictionary = {}
var _comment_scroll: ScrollContainer
var _comment_list: VBoxContainer
var _comment_timer: float = 0.0
var _comment_scroll_speed: float = 24.0
var _comment_scroll_remainder: float = 0.0
var _comment_row_cap: int = 5
var _comment_fan_badge: Texture2D
var _comment_fan_nameplate: Texture2D
var _comment_nameplate_text_color: Color = Color("#33421f")
const FAN_NAMEPLATE_VISIBLE_REGION := Rect2(10.0, 20.0, 316.0, 101.0)
var _unknown_metrics: Dictionary = {}


# A 提交未配置事实的指标 ID；这里只显示未知，不生成对手业务数值。
func set_unknown_metrics(metric_ids: Array) -> void:
	_unknown_metrics.clear()
	for metric_id: Variant in metric_ids:
		var key: String = str(metric_id)
		if key in ["viewer_count", "like_count", "comment_count", "fan_count"]:
			_unknown_metrics[key] = true
	_refresh_values()


# 交接/诊断只读当前显示值，未知字段保持 null，避免把占位零值报告成真实人数。
func get_display_snapshot() -> Dictionary:
	var result: Dictionary = {"has_live_session": _live_session != null}
	var keys: Array[String] = ["viewer_count", "like_count", "comment_count", "fan_count"]
	for index: int in keys.size():
		result[keys[index]] = null if _unknown_metrics.has(keys[index]) else _display_values[index]
	return result


# 编辑器只预览展示方向；运行时按独立绑定配置读取当前周目。
func _ready() -> void:
	_setup_metric_rows()
	_create_comment_feed()
	if Engine.is_editor_hint():
		_refresh_values()
		return
	if auto_bind_player_session:
		bind_live_session(SaveManager.data.live_session if SaveManager.data != null else null)
	else:
		_refresh_values()


## 将四项原有数值标签放入左右镜像行，图标层与数值更新保持分离。
func _setup_metric_rows() -> void:
	var metric_specs: Array[Dictionary] = [
		{"metric_id": "viewer_count", "metric": _viewer_metric},
		{"metric_id": "like_count", "metric": _like_metric},
		{"metric_id": "comment_count", "metric": _comment_metric},
		{"metric_id": "fan_count", "metric": _fan_metric},
	]
	for spec: Dictionary in metric_specs:
		var metric_id: String = str(spec.get("metric_id", ""))
		var metric := spec.get("metric") as RichTextLabel
		if metric == null or metric.get_parent() != _metrics:
			continue
		var original_index: int = metric.get_index()
		_metrics.remove_child(metric)
		var row := HBoxContainer.new()
		row.name = "%sRow" % metric.name
		row.custom_minimum_size.y = metric.custom_minimum_size.y
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		var icon_rect := TextureRect.new()
		icon_rect.name = "%sIcon" % metric_id
		icon_rect.custom_minimum_size = Vector2(28.0, 28.0)
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		metric.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		metric.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(icon_rect)
		row.add_child(metric)
		_metrics.add_child(row)
		_metrics.move_child(row, original_index)
		_metric_rows[metric_id] = row
		_metric_icon_rects[metric_id] = icon_rect
	_refresh_stat_icon_side()


## 依据主播侧加载同名正式PNG；缺图时隐藏TextureRect并保留原Emoji回退。
func _refresh_stat_icon_side() -> void:
	var side_key: String = "opponent" if display_side == DisplaySide.OPPONENT_RIGHT else "player"
	var side_paths: Dictionary = STAT_ICON_PATHS_BY_SIDE.get(side_key, {})
	for metric_id_value: Variant in _metric_icon_rects.keys():
		var metric_id: String = str(metric_id_value)
		var icon_rect := _metric_icon_rects[metric_id] as TextureRect
		var path: String = str(side_paths.get(metric_id, ""))
		var texture: Texture2D = load(path) as Texture2D if not path.is_empty() else null
		icon_rect.texture = texture
		icon_rect.visible = texture != null
		var row := _metric_rows.get(metric_id) as HBoxContainer
		var metric: RichTextLabel = _metric_label_for_id(metric_id)
		if row == null or metric == null:
			continue
		row.alignment = BoxContainer.ALIGNMENT_END if side_key == "opponent" else BoxContainer.ALIGNMENT_BEGIN
		if side_key == "opponent":
			row.move_child(metric, 0)
			row.move_child(icon_rect, 1)
		else:
			row.move_child(icon_rect, 0)
			row.move_child(metric, 1)


func _metric_label_for_id(metric_id: String) -> RichTextLabel:
	match metric_id:
		"viewer_count":
			return _viewer_metric
		"like_count":
			return _like_metric
		"comment_count":
			return _comment_metric
		"fan_count":
			return _fan_metric
		_:
			return null


## 只展示正式评论，不修改直播统计中的真实 comment_count。
func configure_formal_comments(rows: Array[Dictionary], parameters: Dictionary) -> void:
	_comment_rows = rows.duplicate(true)
	_comment_params = parameters.duplicate()
	_comment_row_cap = maxi(1, int(_comment_params.get("comment_visible_row_cap", 5)))
	_comment_scroll_speed = maxf(0.0, float(_comment_params.get("comment_scroll_speed_px_s", 24.0)))
	_comment_scroll_remainder = 0.0
	if _comment_scroll != null:
		_comment_list.add_theme_constant_override("separation", int(_comment_params.get("comment_row_spacing_px", 8)))
		_comment_scroll.custom_minimum_size.y = maxf(0.0, float(_comment_row_cap) * float(_comment_params.get("comment_font_size_px", 20)) * 1.6)
		_comment_timer = _next_comment_interval()
		_clear_comment_rows()
	var pause_with_game: bool = bool(_comment_params.get("comment_pause_with_game", true))
	process_mode = Node.PROCESS_MODE_PAUSABLE if pause_with_game else Node.PROCESS_MODE_ALWAYS


## 粉丝徽章与横标由所属主播面板注入；显示实例仍由评论行负责。
func configure_comment_branding(fan_badge: Texture2D, fan_nameplate: Texture2D, text_color: Color) -> void:
	if (_comment_fan_badge == fan_badge and _comment_fan_nameplate == fan_nameplate
			and _comment_nameplate_text_color == text_color):
		return
	_comment_fan_badge = fan_badge
	_comment_fan_nameplate = fan_nameplate
	_comment_nameplate_text_color = text_color
	if _comment_list != null:
		_clear_comment_rows()


func _process(delta: float) -> void:
	if _comment_rows.is_empty() or _comment_list == null:
		return
	_comment_timer -= delta
	if _comment_timer <= 0.0:
		_add_next_comment()
		_comment_timer = _next_comment_interval()
	if _comment_scroll != null:
		_comment_scroll_remainder += _comment_scroll_speed * delta
		var scroll_step := int(floor(_comment_scroll_remainder))
		if scroll_step > 0:
			_comment_scroll_remainder -= float(scroll_step)
			_comment_scroll.scroll_vertical = mini(
				int(_comment_scroll.get_v_scroll_bar().max_value),
				_comment_scroll.scroll_vertical + scroll_step
			)


func _create_comment_feed() -> void:
	_comment_scroll = ScrollContainer.new()
	_comment_scroll.name = "FormalCommentScroll"
	_comment_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_comment_scroll.custom_minimum_size = Vector2(0.0, 160.0)
	_comment_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_comment_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_metrics.add_child(_comment_scroll)
	_comment_list = VBoxContainer.new()
	_comment_list.name = "CommentRows"
	_comment_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comment_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_comment_scroll.add_child(_comment_list)


func _add_next_comment() -> void:
	if _comment_rows.is_empty():
		return
	var row: Dictionary = _pick_weighted_comment()
	var viewer: Dictionary = row.get("viewer", {})
	var display_name := str(viewer.get("display_name", viewer.get("viewer_id", "")))
	if display_name.is_empty():
		display_name = str(viewer.get("viewer_id", "路人"))
	var comment_text := str(row.get("text", ""))
	var is_fan := str(viewer.get("audience_type", "")) == "fan"
	var badge_probability := clampf(float(_comment_params.get("comment_fan_probability", 0.45)), 0.0, 1.0)
	var show_fan_nameplate := (
		is_fan and _comment_fan_badge != null and _comment_fan_nameplate != null
		and randf() <= badge_probability
	)
	if show_fan_nameplate:
		_comment_list.add_child(_create_fan_nameplate_row(display_name, comment_text))
	else:
		_comment_list.add_child(_create_plain_comment_row(display_name, comment_text))
	while _comment_list.get_child_count() > _comment_row_cap:
		var oldest: Node = _comment_list.get_child(0)
		_comment_list.remove_child(oldest)
		oldest.queue_free()


## 粉丝牌宽度跟随昵称的实际字体宽度；圆徽章和右侧尖角始终保持原形。
## 横牌只承担身份展示，长 ID 占用受限宽度，正文优先保留可读空间。
func _create_fan_nameplate_row(display_name: String, comment_text: String) -> Control:
	var preferred_size: int = maxi(16, int(_comment_params.get("comment_font_size_px", 20)))
	var plate_height: float = 46.0
	var nickname_font_size: int = 17
	var font: Font = get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var name_width: float = font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, nickname_font_size).x
	var row_width: float = _comment_list.size.x
	if row_width <= 0.0:
		row_width = maxf(size.x - 32.0, 240.0)
	# 牌宽仍根据昵称实际宽度变化；文字排在圆徽章后的矩形色条中。
	# 圆徽章属于装饰，计算昵称水平居中时不包含它。
	var text_inset: float = 47.0
	var plate_width: float = clampf(
		ceilf(name_width + text_inset * 2.0),
		112.0,
		maxf(112.0, minf(208.0, row_width - 184.0))
	)
	var plate_size := Vector2(plate_width, plate_height)
	var row := HBoxContainer.new()
	row.name = "FanNameplateCommentRow"
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)

	var identity := Control.new()
	identity.name = "FanIdentity"
	identity.custom_minimum_size = plate_size
	identity.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	identity.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	identity.clip_contents = true
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(identity)

	# NinePatchRect 只横向拉伸原牌中央的纯色部分，左侧圆圈与右侧箭头无变形。
	# 原图有效范围 316×101。将九宫格整体等比缩放至 46px 高，保持圆圈宽高比。
	var plate := NinePatchRect.new()
	plate.name = "Nameplate"
	var atlas := AtlasTexture.new()
	atlas.atlas = _comment_fan_nameplate
	atlas.region = FAN_NAMEPLATE_VISIBLE_REGION
	plate.texture = atlas
	plate.patch_margin_left = 102
	plate.patch_margin_right = 36
	plate.patch_margin_top = 0
	plate.patch_margin_bottom = 0
	plate.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	var art_scale: float = plate_height / FAN_NAMEPLATE_VISIBLE_REGION.size.y
	plate.position = Vector2.ZERO
	plate.size = Vector2(plate_width / art_scale, FAN_NAMEPLATE_VISIBLE_REGION.size.y)
	plate.scale = Vector2.ONE * art_scale
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(plate)

	var badge := TextureRect.new()
	badge.name = "FanBadge"
	badge.size = Vector2(31.0, 31.0)
	badge.position = Vector2(24.0, 23.5) - badge.size * 0.5
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	badge.texture = _comment_fan_badge
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(badge)

	var nickname := Label.new()
	nickname.name = "FanNickname"
	nickname.text = display_name
	# 中文昵称水平居中于圆形徽章右侧的矩形色条（含右侧尖角前的留白）。
	nickname.add_theme_font_size_override("font_size", nickname_font_size)
	nickname.add_theme_color_override("font_color", _comment_nameplate_text_color)
	nickname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nickname.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nickname.clip_text = true
	nickname.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(nickname)
	# 左徽章有效边缘约 x=49；右尖角起点约 x=plate_width-17。
	# Label 入树后再指定宽度，确保文字区域居中于这段矩形条。
	var name_strip_left: float = 51.0
	var name_strip_right: float = 17.0
	nickname.position = Vector2(name_strip_left, 4.0)
	nickname.size = Vector2(maxf(1.0, plate_width - name_strip_left - name_strip_right), plate_height - 8.0)

	var message := RichTextLabel.new()
	message.name = "CommentText"
	message.text = "：" + comment_text
	message.bbcode_enabled = false
	message.fit_content = true
	message.scroll_active = false
	message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message.custom_minimum_size = Vector2(0.0, maxf(plate_height, float(preferred_size) * 1.5))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("normal_font_size", preferred_size)
	message.add_theme_color_override("default_color", Color("#e7edf5"))
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(message)
	return row


## 路人或缺少粉丝素材时保留纯文字评论，正文自然换行。
func _create_plain_comment_row(display_name: String, comment_text: String) -> RichTextLabel:
	var safe_name := display_name.replace("[", "[lb]")
	var safe_text := comment_text.replace("[", "[lb]")
	var label := RichTextLabel.new()
	label.name = "PlainCommentRow"
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font_size: int = maxi(16, int(_comment_params.get("comment_font_size_px", 20)))
	label.custom_minimum_size = Vector2(0.0, maxf(46.0, float(font_size) * 1.5))
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.text = "[color=#b8c0ce]%s[/color]：%s" % [safe_name, safe_text]
	return label


func _pick_weighted_comment() -> Dictionary:
	var total_weight := 0.0
	for row: Dictionary in _comment_rows:
		total_weight += float(row.get("weight", 1.0))
	var target := randf() * total_weight
	for row: Dictionary in _comment_rows:
		target -= float(row.get("weight", 1.0))
		if target <= 0.0:
			return row
	return _comment_rows.back()


func _next_comment_interval() -> float:
	var low := maxf(0.1, float(_comment_params.get("comment_spawn_interval_min_s", 2.5)))
	var high := maxf(low, float(_comment_params.get("comment_spawn_interval_max_s", 4.5)))
	return randf_range(low, high)


func _clear_comment_rows() -> void:
	for child: Node in _comment_list.get_children():
		_comment_list.remove_child(child)
		child.queue_free()


# 场景初始化或替换数据源时显式重连，HUD 只订阅当前 Resource。
func bind_live_session(session: LiveSessionData) -> void:
	if _live_session != null and _live_session.changed.is_connected(_refresh_values):
		_live_session.changed.disconnect(_refresh_values)
	_live_session = session
	if _live_session != null:
		_live_session.changed.connect(_refresh_values)
		_refresh_values()
	elif is_node_ready():
		# 显式解绑仍清空显示，保持原绑定入口的约定。
		set_values(0, 0, 0, 0)


# 保留调用方的原始展示输入；业务状态仍由数据源持有。
func set_values(viewer_count: int, like_count: int, comment_count: int, fan_count: int) -> void:
	# 绑定后由唯一 Resource 优先，旧零占位调用不能覆盖当前事实。
	if _live_session != null:
		viewer_count = _live_session.viewer_count
		like_count = _live_session.like_count
		comment_count = _live_session.comment_count
		fan_count = _live_session.fan_count
	_display_values = [viewer_count, like_count, comment_count, fan_count]
	if not is_node_ready():
		return
	_render_metric(_viewer_metric, viewer_icon, viewer_count, "viewer_count")
	_render_metric(_like_metric, like_icon, like_count, "like_count")
	_render_metric(_comment_metric, comment_icon, comment_count, "comment_count")
	_render_metric(_fan_metric, fan_icon, fan_count, "fan_count")


# 绑定时读取数据源；未绑定时按最近的原始展示输入重新排版。
func _refresh_values() -> void:
	if not is_node_ready():
		return
	if _live_session == null:
		set_values(_display_values[0], _display_values[1], _display_values[2], _display_values[3])
		return
	set_values(_live_session.viewer_count, _live_session.like_count,
		_live_session.comment_count, _live_session.fan_count)


# 四项标签独立渲染，后续单项变色或 Tween 可在此接入。
func _render_metric(metric: RichTextLabel, icon: String, value: int, metric_id: String = "") -> void:
	# 千以下沿用整数；从 1000 起按千显示一位小数，只转换可见文字。
	var number_text: String = "%.1fk" % (value / 1000.0) if value >= 1000 else str(value)
	var icon_rect := _metric_icon_rects.get(metric_id) as TextureRect
	var has_stat_texture: bool = icon_rect != null and icon_rect.texture != null
	if _unknown_metrics.has(metric_id):
		number_text = "—"
		metric.tooltip_text = "暂无该项数据"
	else:
		metric.tooltip_text = ""
	metric.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT if display_side == DisplaySide.OPPONENT_RIGHT
		else HORIZONTAL_ALIGNMENT_LEFT
	)
	if has_stat_texture:
		metric.text = number_text
	elif display_side == DisplaySide.OPPONENT_RIGHT:
		metric.text = number_text + icon
	else:
		metric.text = icon + number_text
