extends SceneTree

const CARD_DATA = preload("res://core/loser_card/loser_card_data.gd")
const CARD_CATALOG = preload("res://core/loser_card/loser_card_catalog.gd")
const CARD_PROFILE = preload("res://core/loser_card/loser_card_profile.gd")
const SAVE_MANAGER = preload("res://core/autoload/save_manager.gd")


func _initialize() -> void:
	if not _test_true_defeat_grants_matching_card():
		quit(1)
		return
	if not _test_incomplete_defeat_does_not_grant():
		quit(1)
		return
	if not _test_streamer_is_granted_once_per_run():
		quit(1)
		return
	if not _test_new_game_starts_with_empty_cards():
		quit(1)
		return
	print("PASS LoserCard: 4 cases (true defeat, incomplete preserves history, dedup, new run)")
	quit(0)


# 满足两项事实后，按稳定主播 ID 获得资料库中对应卡片。
func _test_true_defeat_grants_matching_card() -> bool:
	var data = CARD_DATA.new()
	var catalog = _make_catalog()
	if not data.grant_on_true_defeat(&"level_001", &"streamer_a", true, true, catalog):
		push_error("LCARD-02 真正击败没有发卡")
		return false
	if data.get_new_card_for_level(&"level_001", catalog).get("streamer_id") != &"streamer_a":
		push_error("LCARD-02 获卡身份不匹配")
		return false
	if data.get_new_card_for_level(&"level_001", catalog).get("profile") == null:
		push_error("LCARD-02 获得的主播 ID 没有对应卡片资料")
		return false
	return true


# 击破或确认缺一及资料缺失均不发卡，保留之前已获卡片。
func _test_incomplete_defeat_does_not_grant() -> bool:
	var data = CARD_DATA.new()
	var catalog = _make_catalog()
	data.grant_on_true_defeat(&"previous_level", &"streamer_a", true, true, catalog)
	var next_profile = CARD_PROFILE.new()
	next_profile.streamer_id = &"streamer_b"
	catalog.profiles.append(next_profile)
	if (
		data.grant_on_true_defeat(&"level_001", &"streamer_b", false, true, catalog)
		or data.grant_on_true_defeat(&"level_001", &"streamer_b", true, false, catalog)
		or data.grant_on_true_defeat(&"level_001", &"missing_streamer", true, true, catalog)
	):
		push_error("LCARD-02 非真正击败或资料缺失仍然发卡")
		return false
	if data.get_acquired_cards(catalog).size() != 1 or not data.get_new_card_for_level(&"level_001", catalog).is_empty():
		push_error("LCARD-02 未击破或未确认改变了历史卡片或新增卡片")
		return false
	return true


# 同主播重复确认或来自另一关，当前周目仍只保留一张卡。
func _test_streamer_is_granted_once_per_run() -> bool:
	var data = CARD_DATA.new()
	var catalog = _make_catalog()
	if not data.grant_on_true_defeat(&"level_001", &"streamer_a", true, true, catalog):
		push_error("LCARD-03 首次发卡失败")
		return false
	if (
		data.grant_on_true_defeat(&"level_001", &"streamer_a", true, true, catalog)
		or data.grant_on_true_defeat(&"level_002", &"streamer_a", true, true, catalog)
	):
		push_error("LCARD-03 同周目重复主播再次获得卡片")
		return false
	if data.get_acquired_cards(catalog).size() != 1 or not data.get_new_card_for_level(&"level_002", catalog).is_empty():
		push_error("LCARD-03 重复发卡改变了已获集合")
		return false
	return true


# 复用真实新周目入口，新周目查询为空，历史卡片仍归旧周目。
func _test_new_game_starts_with_empty_cards() -> bool:
	var manager = SAVE_MANAGER.new()
	var catalog = _make_catalog()
	manager.new_game()
	var previous_run = manager.data
	var previous_cards = previous_run.loser_card_data
	previous_cards.grant_on_true_defeat(&"level_001", &"streamer_a", true, true, catalog)
	manager.new_game()
	var passed: bool = (
		manager.data.loser_card_data.get_acquired_cards(catalog).is_empty()
		and manager.data.loser_card_data.get_new_card_for_level(&"level_001", catalog).is_empty()
		and previous_cards.get_acquired_cards(catalog).size() == 1
	)
	manager.free()
	if not passed:
		push_error("LCARD-06 新周目混入旧卡片或旧周目历史丢失")
		return false
	return true


# 仅为测试构造临时资料，正式空 Catalog 保持由内容方填写。
func _make_catalog():
	var profile = CARD_PROFILE.new()
	profile.streamer_id = &"streamer_a"
	var catalog = CARD_CATALOG.new()
	catalog.profiles.append(profile)
	return catalog
