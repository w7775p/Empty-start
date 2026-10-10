class_name ComicPanelPlaybackControl
extends Node

signal panel_display_requested(panel_number: int)
signal playback_completed

@export_range(1, 99, 1) var panel_count: int = 1
@export_range(0.05, 30.0, 0.05) var panel_interval_seconds: float = 1.0

var current_panel_number: int:
	get:
		return _current_panel_number

var _timer: Timer
var _current_panel_number: int = 0
var _active_interval_seconds: float = 0.0
var _has_started: bool = false
var _is_paused: bool = false
var _has_completed: bool = false

# 控制器只发出格数请求；分镜资源与实际绘制由外部表现组件接收信号负责。
func _ready() -> void:
	_timer = Timer.new()
	_timer.name = "PanelIntervalTimer"
	_timer.one_shot = true
	_timer.timeout.connect(_on_interval_timeout)
	add_child(_timer)

# 首次启动时立即请求第一格，其后每格使用相同可配置间隔。
func start_playback() -> bool:
	if _timer == null or _has_started or panel_count < 1 or panel_interval_seconds <= 0.0:
		return false
	_has_started = true
	_active_interval_seconds = panel_interval_seconds
	_current_panel_number = 1
	panel_display_requested.emit(_current_panel_number)
	_start_interval_if_needed()
	return true

# 外部点击入口：普通格立即推进；末格点击才确认这段漫画结束。
func advance_on_click() -> void:
	if not _has_started or _is_paused or _has_completed:
		return
	if _current_panel_number >= panel_count:
		_complete_playback()
		return
	_timer.stop()
	_request_next_panel()

# 暂停 Timer 本身以保留当前剩余时间，暂停期间点击也不会改变分镜状态。
func pause_playback() -> void:
	if not _has_started or _is_paused or _has_completed:
		return
	_is_paused = true
	_timer.paused = true

# 取消 Timer 暂停即可从原剩余时间继续；末格仍等待一次明确点击。
func resume_playback() -> void:
	if not _has_started or not _is_paused or _has_completed:
		return
	_is_paused = false
	_timer.paused = false

# 计时到期只请求普通下一格；到达末格后停止计时并保留当前画面。
func _on_interval_timeout() -> void:
	if _is_paused or _has_completed or _current_panel_number >= panel_count:
		return
	_request_next_panel()

# 每次推进只发当前 1-based 格数，外部表现按同一编号选择对应资源。
func _request_next_panel() -> void:
	_current_panel_number += 1
	panel_display_requested.emit(_current_panel_number)
	_start_interval_if_needed()

# 最后一格没有后续计时；非末格才启动下一段展示间隔。
func _start_interval_if_needed() -> void:
	if _current_panel_number >= panel_count:
		_timer.stop()
		return
	_timer.wait_time = _active_interval_seconds
	_timer.start()

# 结束事件由末格确认点击触发，并由状态位保证只发一次。
func _complete_playback() -> void:
	if _has_completed:
		return
	_has_completed = true
	_timer.stop()
	playback_completed.emit()
