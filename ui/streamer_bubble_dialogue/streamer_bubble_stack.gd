class_name StreamerBubbleStack
extends Control

const BubbleScene: PackedScene = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_view.tscn")

@export_enum("Left", "Right") var tail_direction: int = StreamerBubbleView.TailDirection.LEFT
@export_range(0.0, 1.0, 0.01) var tail_position: float = 0.68
@export_range(120.0, 448.0, 1.0) var max_bubble_width: float = 310.0
@export_range(120.0, 320.0, 1.0) var min_bubble_width: float = 134.0
@export_range(12.0, 64.0, 1.0) var tail_length: float = 22.0
@export_range(12.0, 64.0, 1.0) var tail_base_width: float = 26.0
@export var text_margin: Vector2 = Vector2(25.0, 16.0)
@export var fill_color: Color = Color("#FFF8EA")
@export var text_color: Color = Color("#292734")
@export var outline_color: Color = Color("#252331")
@export_range(1.0, 8.0, 0.5) var outline_width: float = 3.0
@export_range(0.01, 0.8, 0.01) var popup_duration_seconds: float = 0.14
@export_range(0.0, 120.0, 1.0) var float_distance_px: float = 18.0
@export_range(0.01, 1.0, 0.01) var fade_duration_seconds: float = 0.24
@export_range(0.0, 48.0, 1.0) var vertical_gap: float = 7.0
@export_range(0.0, 48.0, 1.0) var edge_margin: float = 12.0

var _active_bubbles: Array[StreamerBubbleView] = []


# Stays confined to the portrait; bubbles themselves do not intercept attacks or mouse input.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(_layout_active_bubbles)


func show_bubble(entry: BubbleDialogueEntry) -> StreamerBubbleView:
	if entry == null or entry.text.strip_edges().is_empty():
		return null
	var bubble: StreamerBubbleView = BubbleScene.instantiate() as StreamerBubbleView
	if bubble == null:
		push_error("StreamerBubbleStack: failed to instantiate bubble")
		return null
	_configure_bubble(bubble)
	add_child(bubble)
	bubble.configure(entry.text, entry.display_duration_seconds)
	bubble.expired.connect(_on_bubble_expired)
	_active_bubbles.append(bubble)
	_layout_active_bubbles()
	bubble.start_lifecycle()
	return bubble


func clear_bubbles() -> void:
	for bubble: StreamerBubbleView in _active_bubbles:
		if is_instance_valid(bubble):
			bubble.cancel_lifecycle()
			bubble.hide()
			bubble.queue_free()
	_active_bubbles.clear()


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


# All lines retain their full content. Old lines become compact history; newest keeps the pointing tail.
# Lay out from bottom to top, aligning to the outer edges of the portrait instead of the character face.
func _layout_active_bubbles() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var count: int = _active_bubbles.size()
	for index in range(count):
		var bubble: StreamerBubbleView = _active_bubbles[index]
		if is_instance_valid(bubble):
			bubble.set_history_depth(count - 1 - index)
	var bottom: float = size.y - edge_margin
	for index in range(count - 1, -1, -1):
		var bubble: StreamerBubbleView = _active_bubbles[index]
		if not is_instance_valid(bubble):
			continue
		var x: float = edge_margin
		if tail_direction == StreamerBubbleView.TailDirection.LEFT:
			x = size.x - edge_margin - bubble.size.x
		var y: float = maxf(edge_margin, bottom - bubble.size.y)
		bubble.set_stack_position(Vector2(x, y), index < count - 1)
		bottom = y - vertical_gap


func _on_bubble_expired(bubble: StreamerBubbleView) -> void:
	_active_bubbles.erase(bubble)
	bubble.queue_free()
	_layout_active_bubbles()
