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
	if not _test_pk_only_preserves_existing_cards():
		quit(1)
		return
	if not _test_new_game_starts_with_empty_cards():
		quit(1)
		return
	print("PASS LoserCard: 5 cases (LCARD-02..LCARD-06)")
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


# 使用未击破休息结果的公开字段，PK 胜利只保留历史卡片。
func _test_pk_only_preserves_existing_cards() -> bool:
	var data = CARD_DATA.new()
	var catalog = _make_catalog()
	var next_profile = CARD_PROFILE.new()
	next_profile.streamer_id = &"streamer_b"
	catalog.profiles.append(next_profile)
	data.grant_on_true_defeat(&"previous_level", &"streamer_a", true, true, catalog)
	var pk_only_result: Dictionary = {
		"level_id": "level_001", "result_kind": "pk_win_unbroken",
		"pk_won": true, "contradiction_broken": false,
	}
	if data.grant_on_true_defeat(
		StringName(pk_only_result["level_id"]), &"streamer_b",
		pk_only_result["contradiction_broken"], false, catalog
	):
		push_error("LCARD-04 未击破 PK 胜利新增了败者卡")
		return false
	if data.acquired_streamer_ids != [&"streamer_a"] or data.rewarded_level_ids != [&"previous_level"]:
		push_error("LCARD-04 未击破分支改变了既有卡片")
		return false
	return true


# 复用真实新周目入口创建独立 SaveData；获卡与提交 ID 清空，静态资料继续存在。
func _test_new_game_starts_with_empty_cards() -> bool:
	var manager = SAVE_MANAGER.new()
	var catalog = _make_catalog()
	var static_profile = catalog.find_profile(&"streamer_a")
	manager.new_game()
	var previous_run = manager.data
	var previous_cards = previous_run.loser_card_data
	previous_cards.grant_on_true_defeat(&"level_001", &"streamer_a", true, true, catalog)
	manager.new_game()
	var passed: bool = (
		manager.data != previous_run
		and manager.data.loser_card_data != previous_cards
		and manager.data.loser_card_data.acquired_streamer_ids.is_empty()
		and manager.data.loser_card_data.rewarded_level_ids.is_empty()
		and previous_cards.acquired_streamer_ids == [&"streamer_a"]
		and catalog.find_profile(&"streamer_a") == static_profile
	)
	manager.free()
	if not passed:
		push_error("LCARD-06 新周目混入旧卡片或改写了静态资料")
		return false
	return true


# 仅为测试构造临时资料，正式空 Catalog 保持由内容方填写。
func _make_catalog():
	var profile = CARD_PROFILE.new()
	profile.streamer_id = &"streamer_a"
	var catalog = CARD_CATALOG.new()
	catalog.profiles.append(profile)
	return catalog
