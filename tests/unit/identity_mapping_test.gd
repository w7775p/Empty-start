extends SceneTree

# 一次核对正式源正文、12 个稳定 ID 与 4/4/4 映射。
func _init() -> void:
	quit(0 if _verify_source() else 1)


# 缺来源或字段漂移时明确返回失败，避免 assert 中断后没有退出码。
func _verify_source() -> bool:
	var source := FileAccess.open("res://data/source_tables/01_身份配置.csv", FileAccess.READ)
	if source == null:
		push_error("FAIL ID-08: 正式身份 CSV 缺失")
		return false
	var header := source.get_csv_line()
	for field: String in ["identity_id", "display_name", "description", "tendency"]:
		if not header.has(field):
			push_error("FAIL ID-08: CSV 缺少字段 " + field)
			return false
	var ids: Array[StringName] = []
	var counts := {"orthodox": 0, "heretical": 0, "absurd": 0}
	while not source.eof_reached():
		var row := source.get_csv_line()
		if row.size() != header.size():
			continue
		var identity_id := StringName(row[header.find("identity_id")])
		var option := IdentityOptions.find_option(identity_id)
		if option == null or not IdentityOptions.CARDS.has(option) or ids.has(identity_id):
			push_error("FAIL ID-08: 身份缺失或重复 " + String(identity_id))
			return false
		ids.append(identity_id)
		if option.display_name != row[header.find("display_name")] or option.description != row[header.find("description")]:
			push_error("FAIL ID-08: 身份正文漂移 " + String(identity_id))
			return false
		var tendency := row[header.find("tendency")]
		if tendency == "heresy":
			tendency = "heretical"
		if not counts.has(tendency) or option.tendency_id != tendency:
			push_error("FAIL ID-08: 倾向映射错误 " + String(identity_id))
			return false
		counts[tendency] += 1
	if ids.size() != 12 or IdentityOptions.CARDS.size() != 12 or counts != {"orthodox": 4, "heretical": 4, "absurd": 4}:
		push_error("FAIL ID-08: 正式身份数量或倾向分布错误")
		return false
	print("PASS ID-08: 12 exact CSV identities; orthodox/heretical/absurd = 4/4/4")
	return true
