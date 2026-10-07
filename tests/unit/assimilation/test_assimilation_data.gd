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
	if not _test_first_inherited_trait_registers():
		quit(1)
		return
	if not _test_inherited_trait_is_deduplicated_across_sources():
		quit(1)
		return
	if not _test_clear_only_never_creates_defeat_rewards():
		quit(1)
		return
	print("PASS Assimilation: 7 cases (AS-02..AS-05)")
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


# 首次继承必须来自已真正击败的关卡及允许继承的特性清单。
func _test_first_inherited_trait_registers() -> bool:
	var data = ASSIMILATION_DATA.new()
	if data.register_inherited_trait(&"level_001", &"split", true):
		push_error("AS-04 未真正击败不能继承特性")
		return false
	data.register_defeated_streamer(&"level_001", &"streamer_a", true, true)
	if data.register_inherited_trait(&"level_001", &"reflect", false):
		push_error("AS-04 禁止继承的特性被登记")
		return false
	if not data.register_inherited_trait(&"level_001", &"split", true):
		push_error("AS-04 首次合格特性没有登记")
		return false
	if data.inherited_trait_ids != [&"split"]:
		push_error("AS-04 稳定特性 ID 保存错误")
		return false
	return true


# 同一特性来自不同真正击败主播时仍只保留一次。
func _test_inherited_trait_is_deduplicated_across_sources() -> bool:
	var data = ASSIMILATION_DATA.new()
	data.register_defeated_streamer(&"level_001", &"streamer_a", true, true)
	data.register_defeated_streamer(&"level_002", &"streamer_b", true, true)
	data.register_inherited_trait(&"level_001", &"split", true)
	if data.register_inherited_trait(&"level_002", &"split", true):
		push_error("AS-04 不同来源重复登记了同一特性")
		return false
	if data.inherited_trait_ids != [&"split"]:
		push_error("AS-04 特性去重集合发生变化")
		return false
	return true


# 未击破 PK 胜利只新增通关，保留既有成果；正式确认击败则同时记录两类结果。
func _test_clear_only_never_creates_defeat_rewards() -> bool:
	var data = ASSIMILATION_DATA.new()
	data.register_defeated_streamer(&"previous_level", &"previous_streamer", true, true)
	data.register_inherited_word_pool(&"previous_level", &"previous_pool", 2.0, true, false)
	data.register_inherited_trait(&"previous_level", &"split", true)
	var changes: Dictionary = data.register_level_result(&"level_001", &"streamer_a", true, false, false)
	if not changes["completed_added"] or changes["defeated_added"]:
		push_error("AS-05 未击破结果应只新增通关")
		return false
	if not data.completed_streamer_ids.has(&"streamer_a") or data.defeated_streamer_ids.has(&"streamer_a"):
		push_error("AS-05 通关与真正击败没有区分")
		return false
	if (
		data.register_inherited_word_pool(&"level_001", &"new_pool", 3.0, true, false)
		or data.register_inherited_trait(&"level_001", &"reflect", true)
		or data.inherited_word_weights != {&"previous_pool": 2.0}
		or data.inherited_trait_ids != [&"split"]
	):
		push_error("AS-05 仅通关产生了击败奖励或改变既有成果")
		return false
	var duplicate: Dictionary = data.register_level_result(&"level_001", &"streamer_a", true, false, false)
	if duplicate["completed_added"] or duplicate["defeated_added"]:
		push_error("AS-05 相同通关重复新增了结果")
		return false
	var defeated: Dictionary = data.register_level_result(&"level_002", &"streamer_b", true, true, true)
	if (
		not defeated["completed_added"] or not defeated["defeated_added"]
		or not data.completed_streamer_ids.has(&"streamer_b")
		or not data.defeated_streamer_ids.has(&"streamer_b")
	):
		push_error("AS-05 真正击败应同时登记通关与击败")
		return false
	return true
