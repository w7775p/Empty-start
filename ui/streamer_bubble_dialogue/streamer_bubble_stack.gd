class_name StreamerBubbleStack
extends Control

const BubbleScene: PackedScene = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_view.tscn")

@export_enum("Left", "Right") var tail_direction: int = StreamerBubbleView.TailDirection.LEFT
@export_range(0.0, 1.0, 0.01) var tail_position: float = 0.68
@export_range(120.0, 448.0, 1.0) var max_bubble_width: float = 352.0
@export_range(120.0, 320.0, 1.0) var min_bubble_width: float = 142.0
@export_range(12.0, 64.0, 1.0) var tail_length: float = 24.0
@export_range(12.0, 64.0, 1.0) var tail_base_width: float = 30.0
@export var text_margin: Vector2 = Vector2(18.0, 12.0)
@export var fill_color: Color = Color("#fff6dd")
@export var text_color: Color = Color("#26242b")
@export var outline_color: Color = Color("#27242c")
@export_range(1.0, 8.0, 0.5) var outline_width: float = 3.0
@export_range(0.01, 0.8, 0.01) var popup_duration_seconds: float = 0.16
@export_range(0.0, 120.0, 1.0) var float_distance_px: float = 38.0
@export_range(0.01, 1.0, 0.01) var fade_duration_seconds: float = 0.28
@export_range(0.0, 48.0, 1.0) var vertical_gap: float = 8.0
@export_range(0.0, 48.0, 1.0) var edge_margin: float = 12.0

var _active_bubbles: Array[StreamerBubbleView] = []


# 立绘尺寸由场景锚点提供；浮层忽略鼠标并裁切超出本立绘区域的内容。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout_active_bubbles)


# 保持到达顺序：先来的对白在上方，新对白从下方加入并允许并排叠显。
func show_bubble(entry: BubbleDialogueEntry) -> StreamerBubbleView:
	if entry == null or entry.text.strip_edges().is_empty():
		return null
	var bubble: StreamerBubbleView = BubbleScene.instantiate() as StreamerBubbleView
	if bubble == null:
		push_error("StreamerBubbleStack: 无法实例化主播对白气泡。")
		return null
	_configure_bubble(bubble)
	add_child(bubble)
	bubble.configure(entry.text, entry.display_duration_seconds)
	bubble.expired.connect(_on_bubble_expired)
	_active_bubbles.append(bubble)
	_layout_active_bubbles()
	bubble.start_lifecycle()
	return bubble


# 新一局或对手离线时由拥有 HUD 的组合方显式清空本侧显示。
func clear_bubbles() -> void:
	for bubble: StreamerBubbleView in _active_bubbles:
		if is_instance_valid(bubble):
			bubble.cancel_lifecycle()
			bubble.hide()
			bubble.queue_free()
	_active_bubbles.clear()


# 将可调美术参数复制到单条气泡，玩家和对手浮层可各自配置。
func _configure_bubble(bubble: StreamerBubbleView) -> void:
	bubble.tail_direction = tail_direction
	bubble.tail_position = tail_position
	bubble.max_bubble_width = max_bubble_width
	bubble.min_bubble_width = min_bubble_width
	bubble.tail_length = tail_length
	bubble.tail_base_width = tail_base_width
	bubble.text_margin = text_margin
	bubble.fill_color = fill_color
	bubble.text_color = text_color
	bubble.outline_color = outline_color
	bubble.outline_width = outline_width
	bubble.popup_duration_seconds = popup_duration_seconds
	bubble.float_distance_px = float_distance_px
	bubble.fade_duration_seconds = fade_duration_seconds


# 同侧旧泡在上、新泡在下；左右对齐与尾巴方向共同指向该侧主播。
func _layout_active_bubbles() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var next_bottom: float = size.y - edge_margin
	for index in range(_active_bubbles.size() - 1, -1, -1):
		var bubble: StreamerBubbleView = _active_bubbles[index]
		if not is_instance_valid(bubble):
			continue
		var bubble_x: float = edge_margin
		if tail_direction == StreamerBubbleView.TailDirection.LEFT:
			bubble_x = size.x - edge_margin - bubble.size.x
		var bubble_y: float = maxf(edge_margin, next_bottom - bubble.size.y)
		bubble.set_stack_position(
			Vector2(bubble_x, bubble_y), index < _active_bubbles.size() - 1
		)
		next_bottom = bubble_y - vertical_gap


# 到期节点退出顺序表后重排仍存活的气泡。
func _on_bubble_expired(bubble: StreamerBubbleView) -> void:
	_active_bubbles.erase(bubble)
	bubble.queue_free()
	_layout_active_bubbles()
