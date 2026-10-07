extends SceneTree

const ASSIMILATION_DATA = preload("res://core/assimilation/assimilation_data.gd")


func _initialize() -> void:
	if not _test_first_true_defeat_registers():
		quit(1)
		return
	if not _test_defeat_ids_are_deduplicated():
		quit(1)
		return
	if not _test_first_inherited_pool_registers():
		quit(1)
		return
	if not _test_inherited_pool_id_is_deduplicated():
		quit(1)
		return
	print("PASS Assimilation: 4 cases (AS-02..AS-03)")
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


# 权重与稳定 pool_id 一起登记，未击败或矛盾专属词库均排除。
func _test_first_inherited_pool_registers() -> bool:
	var data = ASSIMILATION_DATA.new()
	if data.register_inherited_word_pool(&"level_001", &"pool_a", 2.5, true, false):
		push_error("AS-03 未真正击败不能继承词库")
		return false
	data.register_defeated_streamer(&"level_001", &"streamer_a", true, true)
	if (
		data.register_inherited_word_pool(&"level_001", &"true_contradictions", 2.5, true, true)
		or data.register_inherited_word_pool(&"level_001", &"false_contradictions", 2.5, true, true)
		or data.register_inherited_word_pool(&"level_001", &"not_inheritable", 2.5, false, false)
	):
		push_error("AS-03 矛盾专属或禁止继承的词库被登记")
		return false
	if not data.register_inherited_word_pool(&"level_001", &"pool_a", 2.5, true, false):
		push_error("AS-03 合格词库没有登记")
		return false
	if data.inherited_word_weights.size() != 1 or data.inherited_word_weights.get(&"pool_a") != 2.5:
		push_error("AS-03 pool_id 或出现权重保存错误")
		return false
	return true


# 重复 pool_id 不叠加权重、不替换首次权重。
func _test_inherited_pool_id_is_deduplicated() -> bool:
	var data = ASSIMILATION_DATA.new()
	data.register_defeated_streamer(&"level_001", &"streamer_a", true, true)
	data.register_inherited_word_pool(&"level_001", &"pool_a", 2.5, true, false)
	if data.register_inherited_word_pool(&"level_001", &"pool_a", 99.0, true, false):
		push_error("AS-03 相同稳定 pool_id 被重复登记")
		return false
	if data.inherited_word_weights.size() != 1 or data.inherited_word_weights.get(&"pool_a") != 2.5:
		push_error("AS-03 重复登记改变了首次词库权重")
		return false
	return true
