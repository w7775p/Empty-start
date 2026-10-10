@tool
extends Control

enum DisplaySide { PLAYER_LEFT, OPPONENT_RIGHT }

# 展示方向只控制图标顺序和对齐。
@export var display_side: DisplaySide = DisplaySide.PLAYER_LEFT:
	set(value):
		display_side = value
		_refresh_values()

# 默认订阅玩家当前周目；其他数据来源由组合方关闭此项并显式注入。
@export var auto_bind_player_session: bool = true

# 正式 ICON 可替换为 BBCode [img]，继续沿用相同的数值刷新入口。
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

var _live_session: LiveSessionData = null
# 仅缓存最近展示输入，避免图标或方向变化时从 k 文本反推并丢失整数。
var _display_values: Array[int] = [0, 0, 0, 0]


# 编辑器只预览展示方向；运行时按独立绑定配置读取当前周目。
func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_values()
		return
	if auto_bind_player_session:
		bind_live_session(SaveManager.data.live_session if SaveManager.data != null else null)
	else:
		_refresh_values()


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
	_display_values = [viewer_count, like_count, comment_count, fan_count]
	if not is_node_ready():
		return
	_render_metric(_viewer_metric, viewer_icon, viewer_count)
	_render_metric(_like_metric, like_icon, like_count)
	_render_metric(_comment_metric, comment_icon, comment_count)
	_render_metric(_fan_metric, fan_icon, fan_count)


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
func _render_metric(metric: RichTextLabel, icon: String, value: int) -> void:
	# 千以下沿用整数；从 1000 起按千显示一位小数，只转换可见文字。
	var number_text: String = "%.1fk" % (value / 1000.0) if value >= 1000 else str(value)
	if display_side == DisplaySide.OPPONENT_RIGHT:
		metric.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		metric.text = number_text + icon
	else:
		metric.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		metric.text = icon + number_text
