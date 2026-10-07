extends SceneTree

const ASSIMILATION_DATA = preload("res://core/assimilation/assimilation_data.gd")


func _initialize() -> void:
	if not _test_first_true_defeat_registers():
		quit(1)
		return
	if not _test_defeat_ids_are_deduplicated():
		quit(1)
		return
	print("PASS AS-02: 2 cases")
	quit(0)


# 只有击破和正式确认都成立时才登记首次真正击败。
func _test_first_true_defeat_registers() -> bool:
	var data = ASSIMILATION_DATA.new()
	if data.register_defeated_streamer(&"level_001", &"streamer_a", false, true):
		push_error("AS-02 未击破不能登记真正击败")
		return false
	if data.register_defeated_streamer(&"level_001", &"streamer_a", true, false):
		push_error("AS-02 神谕尚未确认不能登记真正击败")
		return false
	if not data.register_defeated_streamer(&"level_001", &"streamer_a", true, true):
		push_error("AS-02 首次真正击败没有登记")
		return false
	if data.defeated_streamer_ids != [&"streamer_a"] or data.defeated_level_ids != [&"level_001"]:
		push_error("AS-02 稳定主播和关卡 ID 登记错误")
		return false
	return true


# 主播重复和同关卡重复提交均保持第一次登记，包含重复数据读取场景。
func _test_defeat_ids_are_deduplicated() -> bool:
	var data = ASSIMILATION_DATA.new()
	data.register_defeated_streamer(&"level_001", &"streamer_a", true, true)
	if (
		data.register_defeated_streamer(&"level_001", &"streamer_a", true, true)
		or data.register_defeated_streamer(&"level_002", &"streamer_a", true, true)
		or data.register_defeated_streamer(&"level_001", &"streamer_b", true, true)
	):
		push_error("AS-02 重复主播或同关卡重复结果被再次登记")
		return false
	if data.defeated_streamer_ids.size() != 1 or data.defeated_level_ids.size() != 1:
		push_error("AS-02 重复登记改变了已提交集合")
		return false
	return true
