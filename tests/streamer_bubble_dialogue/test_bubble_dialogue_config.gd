extends SceneTree

const Entry = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_entry.gd")
const Config = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.gd")
var _failures: int = 0


# TEST_ONLY 条目只在测试进程内创建，正式空词库保持无虚构台词。
func _initialize() -> void:
	var config = load("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
	_check(config != null and config.entries.is_empty(), "正式词库加载为空")
	_test_lookup_and_editable_resource()
	_test_actual_hit_defaults(config)
	print("SD-01 RESULT: %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)


# 验证同句双方、多事件、精确筛选与未知 ID，并通过真实资源读写确认可编辑配置。
func _test_lookup_and_editable_resource() -> void:
	var config := Config.new()
	var player := Entry.new()
	player.original_sentence_id = "test_sentence"
	player.event_id = &"test_reply"
	player.text = "TEST_ONLY player"
	var opponent := Entry.new()
	opponent.side = Entry.SpeakerSide.OPPONENT
	opponent.original_sentence_id = player.original_sentence_id
	opponent.event_id = player.event_id
	opponent.text = "TEST_ONLY opponent"
	opponent.priority = Entry.Priority.PLOT
	opponent.display_duration_seconds = 4.5
	var idle := Entry.new()
	idle.side = Entry.SpeakerSide.OPPONENT
	idle.event_id = &"test_idle"
	idle.text = "TEST_ONLY idle"
	idle.priority = Entry.Priority.TIMED_IDLE
	var other := Entry.new()
	other.original_sentence_id = "test_other_sentence"
	other.event_id = player.event_id
	other.text = "TEST_ONLY other"
	config.entries.assign([player, opponent, idle, other, null])
	_check(config.find_by_sentence("test_sentence") == [player, opponent], "原句读取双方并保序")
	_check(config.find_by_sentence("test_sentence", Entry.SpeakerSide.OPPONENT) == [opponent], "原句限定对手")
	_check(config.find_by_event(&"test_reply") == [player, opponent, other], "事件读取多条")
	_check(config.find_by_event(&"test_reply", Entry.SpeakerSide.PLAYER) == [player, other], "事件限定玩家")
	_check(config.find_by_event(&"test_reply", Config.ANY_SIDE, "test_sentence") == [player, opponent], "事件限定原句")
	_check(config.find_by_event(&"test_idle") == [idle], "无原句事件可读取")
	_check(config.find_by_sentence("").is_empty() and config.find_by_sentence("test_missing").is_empty(), "空及未知原句无匹配")
	_check(config.find_by_event(&"").is_empty() and config.find_by_event(&"test_missing").is_empty(), "空及未知事件无匹配")
	_check(config.find_by_event(&"test_reply", 99).is_empty(), "未知侧无匹配")
	_check(Entry.Priority.PLOT > Entry.Priority.HIT and Entry.Priority.HIT > Entry.Priority.TIMED_IDLE, "剧情大于命中大于闲聊")
	var resource_path := "res://.godot/sd01/test_roundtrip.tres"
	DirAccess.make_dir_recursive_absolute("res://.godot/sd01")
	_check(ResourceSaver.save(config, resource_path) == OK, "保存可编辑 Resource")
	var restored = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(restored != null, "重新读取 Resource")
	if restored != null:
		var replies = restored.find_by_event(&"test_reply", Entry.SpeakerSide.OPPONENT, "test_sentence")
		_check(replies.size() == 1 and replies[0].text == opponent.text and replies[0].priority == Entry.Priority.PLOT and is_equal_approx(replies[0].display_duration_seconds, 4.5), "侧、文本、优先级、时长往返保持")
	DirAccess.remove_absolute(resource_path)


# 验证调用方提供的有效命中与复读事实；每次仅返回新数据，不积累命中记录。
func _test_actual_hit_defaults(config: Resource) -> void:
	config.hit_display_duration_seconds = 2.5
	var echo = config.create_hit_echo("test_hit", "TEST_ONLY exact original", true, false)
	_check(echo != null and echo.side == Entry.SpeakerSide.PLAYER and echo.priority == Entry.Priority.HIT, "非复读命中默认玩家")
	_check(echo.original_sentence_id == "test_hit" and echo.text == "TEST_ONLY exact original" and echo.event_id == Config.ACTUAL_HIT_EVENT and is_equal_approx(echo.display_duration_seconds, 2.5), "保留原句及当前可调时长")
	_check(config.create_hit_echo("test_hit", echo.text, false, false) == null, "落空无复述")
	_check(config.create_hit_echo("test_hit", echo.text, true, true) == null, "普通复读无复述")
	_check(config.create_hit_echo("test_hit", " \n ", true, false) == null, "空白文本无气泡数据")
	var next_echo = config.create_hit_echo("test_hit", echo.text, true, false)
	_check(next_echo != echo and config.entries.is_empty(), "连续请求独立且无命中历史")


# 所有失败均计数并设置非零进程退出码，同时输出可核对的用例结果。
func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
