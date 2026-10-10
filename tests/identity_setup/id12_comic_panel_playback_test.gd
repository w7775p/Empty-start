extends Node

const TEST_ONLY_PANEL_COUNT: int = 3
const TEST_ONLY_PANEL_CONTENT = [
	"TEST_ONLY_PANEL_1",
	"TEST_ONLY_PANEL_2",
	"TEST_ONLY_PANEL_3",
]
const TEST_INTERVAL_SECONDS: float = 0.8

var _playback: ComicPanelPlaybackControl
var _reference_timer: Timer
var _requested_panels: Array[int] = []
var _presented_test_content: Array[String] = []
var _completion_count: int = 0
var _failures := PackedStringArray()
var _measure_resumed_advance: bool = false
var _resumed_advance_elapsed_seconds: float = -1.0

# 运行真实 Timer 与 signal，记录输出并让 Godot 进程以实际验收结果退出。
func _ready() -> void:
	await _run_playback_test()

func _run_playback_test() -> void:
	_playback = ComicPanelPlaybackControl.new()
	_playback.panel_count = TEST_ONLY_PANEL_COUNT
	_playback.panel_interval_seconds = TEST_INTERVAL_SECONDS
	_playback.panel_display_requested.connect(_on_panel_display_requested)
	_playback.playback_completed.connect(_on_playback_completed)
	add_child(_playback)

	_check(_playback.start_playback(), "first start accepted")
	_check(_requested_panels == [1], "first panel requested immediately")
	_check(_playback.current_panel_number == 1, "current panel starts at one")
	_check(not _playback.start_playback(), "duplicate start rejected")
	_check(_requested_panels == [1], "duplicate start does not re-request a panel")

	# 独立参考 Timer 与播放 Timer 使用相同引擎时钟，避免 headless 墙钟速度影响边界判断。
	_reference_timer = Timer.new()
	_reference_timer.name = "TestOnlyReferenceTimer"
	_reference_timer.one_shot = true
	_reference_timer.wait_time = TEST_INTERVAL_SECONDS * 10.0
	add_child(_reference_timer)
	_reference_timer.start()
	await _wait_seconds(0.18)
	var elapsed_before_pause := _reference_timer.wait_time - _reference_timer.time_left
	_playback.pause_playback()
	_playback.advance_on_click()
	_check(_playback.current_panel_number == 1, "paused click cannot advance")
	await _wait_seconds(TEST_INTERVAL_SECONDS + 0.15)
	_check(_requested_panels == [1], "paused timer does not emit during the pause")

	_reference_timer.stop()
	_reference_timer.wait_time = TEST_INTERVAL_SECONDS * 10.0
	_reference_timer.start()
	_measure_resumed_advance = true
	_playback.resume_playback()
	var expected_remaining_seconds := TEST_INTERVAL_SECONDS - elapsed_before_pause
	_check(expected_remaining_seconds > 0.35, "pause began before the timer boundary")
	var before_boundary_seconds := maxf(expected_remaining_seconds - 0.16, 0.05)
	await _wait_seconds(before_boundary_seconds)
	_check(_requested_panels == [1], "resumed timer does not advance before its remaining time")
	await _wait_seconds(0.24)
	_check(_requested_panels == [1, 2], "resumed timer automatically requests the next panel")
	_check(_playback.current_panel_number == 2, "auto request exposes the current panel")
	_check(
		_resumed_advance_elapsed_seconds >= 0.0 and absf(_resumed_advance_elapsed_seconds - expected_remaining_seconds) < 0.16,
		"resume uses the saved remaining interval instead of a fresh full interval"
	)
	_measure_resumed_advance = false
	_check(_presented_test_content == ["TEST_ONLY_PANEL_1", "TEST_ONLY_PANEL_2"], "external presenter maps requested panel numbers to replaceable TEST_ONLY content")

	_playback.advance_on_click()
	_check(_requested_panels == [1, 2, 3], "click immediately requests the next panel")
	_check(_playback.current_panel_number == TEST_ONLY_PANEL_COUNT, "click reaches the configured final panel")
	_check(_presented_test_content[-1] == "TEST_ONLY_PANEL_3", "external presenter receives the final TEST_ONLY content")
	await _wait_seconds(TEST_INTERVAL_SECONDS + 0.15)
	_check(_requested_panels == [1, 2, 3], "final panel remains displayed without an automatic next request")
	_check(_completion_count == 0, "final panel does not complete until another click")

	_playback.advance_on_click()
	_check(_completion_count == 1, "click on the final panel emits completion")
	_playback.advance_on_click()
	_playback.advance_on_click()
	_check(_completion_count == 1, "completion is emitted only once")
	_check(_playback.current_panel_number == TEST_ONLY_PANEL_COUNT, "completion keeps the final panel number")

	if _failures.is_empty():
		print("ID12_RUNTIME_PASS panels=1,2,3 elapsed_before_pause_ms=%d resumed_to_next_ms=%d completion_count=%d" % [int(elapsed_before_pause * 1000.0), int(_resumed_advance_elapsed_seconds * 1000.0), _completion_count])
		get_tree().quit(0)
	else:
		push_error("ID12_RUNTIME_FAIL failures=%s" % "; ".join(_failures))
		get_tree().quit(1)

# 订阅逐格请求，按显式 TEST_ONLY 编号模拟可替换的外部分镜内容接收端。
func _on_panel_display_requested(panel_number: int) -> void:
	_requested_panels.append(panel_number)
	if panel_number < 1 or panel_number > TEST_ONLY_PANEL_CONTENT.size():
		_failures.append("panel request index is outside TEST_ONLY content")
		return
	_presented_test_content.append(TEST_ONLY_PANEL_CONTENT[panel_number - 1])
	if panel_number == 2 and _measure_resumed_advance:
		_resumed_advance_elapsed_seconds = _reference_timer.wait_time - _reference_timer.time_left

func _on_playback_completed() -> void:
	_completion_count += 1

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error("ID12_CHECK_FAILED %s" % description)

func _wait_seconds(duration: float) -> void:
	await get_tree().create_timer(duration).timeout
