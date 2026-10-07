extends SceneTree

const CARD_DATA = preload("res://core/loser_card/loser_card_data.gd")
const CARD_CATALOG = preload("res://core/loser_card/loser_card_catalog.gd")
const CARD_PROFILE = preload("res://core/loser_card/loser_card_profile.gd")


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
	print("PASS LoserCard: 3 cases (LCARD-02..LCARD-03)")
	quit(0)


# 满足两项事实后，按稳定主播 ID 获得资料库中对应卡片。
func _test_true_defeat_grants_matching_card() -> bool:
	var data = CARD_DATA.new()
	var catalog = _make_catalog()
	if not data.grant_on_true_defeat(&"level_001", &"streamer_a", true, true, catalog):
		push_error("LCARD-02 真正击败没有发卡")
		return false
	if data.acquired_streamer_ids != [&"streamer_a"] or data.rewarded_level_ids != [&"level_001"]:
		push_error("LCARD-02 获卡身份不匹配")
		return false
	if catalog.find_profile(data.acquired_streamer_ids[0]) == null:
		push_error("LCARD-02 获得的主播 ID 没有对应卡片资料")
		return false
	return true


# 击破或正式确认缺一时不发卡，资料缺失时不合成卡片。
func _test_incomplete_defeat_does_not_grant() -> bool:
	var data = CARD_DATA.new()
	var catalog = _make_catalog()
	if (
		data.grant_on_true_defeat(&"level_001", &"streamer_a", false, true, catalog)
		or data.grant_on_true_defeat(&"level_001", &"streamer_a", true, false, catalog)
		or data.grant_on_true_defeat(&"level_001", &"streamer_a", false, false, catalog)
		or data.grant_on_true_defeat(&"level_001", &"missing_streamer", true, true, catalog)
	):
		push_error("LCARD-02 非真正击败或资料缺失仍然发卡")
		return false
	if not data.acquired_streamer_ids.is_empty() or not data.rewarded_level_ids.is_empty():
		push_error("LCARD-02 不满足条件仍改变获卡集合")
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
	if data.acquired_streamer_ids != [&"streamer_a"] or data.rewarded_level_ids != [&"level_001"]:
		push_error("LCARD-03 重复发卡改变了已获集合")
		return false
	return true


# 仅为测试构造临时资料，正式空 Catalog 保持由内容方填写。
func _make_catalog():
	var profile = CARD_PROFILE.new()
	profile.streamer_id = &"streamer_a"
	var catalog = CARD_CATALOG.new()
	catalog.profiles.append(profile)
	return catalog
