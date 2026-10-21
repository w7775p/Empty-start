class_name EndingReligionNameConfig
extends Resource

## 三种纯倾向的教名；正式文本由策划填写。
@export var orthodox_name: String = ""
@export var heretical_name: String = ""
@export var absurd_name: String = ""

## 六种主导 → 次要混合组合的教名；正式文本由策划填写。
@export var orthodox_heretical_name: String = ""
@export var orthodox_absurd_name: String = ""
@export var heretical_orthodox_name: String = ""
@export var heretical_absurd_name: String = ""
@export var absurd_orthodox_name: String = ""
@export var absurd_heretical_name: String = ""

## 九种主次倾向组合的结局描述；对应第16表 religion_name 的 notes 列。
@export var orthodox_description: String = ""
@export var orthodox_heretical_description: String = ""
@export var orthodox_absurd_description: String = ""
@export var heretical_orthodox_description: String = ""
@export var heretical_description: String = ""
@export var heretical_absurd_description: String = ""
@export var absurd_orthodox_description: String = ""
@export var absurd_heretical_description: String = ""
@export var absurd_description: String = ""

const _TENDENCY_IDS: Array[String] = ["orthodox", "heretical", "absurd"]


# 从主导和次要倾向的稳定 ID 读取策划配置教名，保留组合顺序。
func get_religion_name(primary_tendency_id: String, secondary_tendency_id: String) -> String:
	match _build_combination_key(primary_tendency_id, secondary_tendency_id):
		"orthodox/orthodox":
			return orthodox_name
		"heretical/heretical":
			return heretical_name
		"absurd/absurd":
			return absurd_name
		"orthodox/heretical":
			return orthodox_heretical_name
		"orthodox/absurd":
			return orthodox_absurd_name
		"heretical/orthodox":
			return heretical_orthodox_name
		"heretical/absurd":
			return heretical_absurd_name
		"absurd/orthodox":
			return absurd_orthodox_name
		"absurd/heretical":
			return absurd_heretical_name
		_:
			return ""


# 使用与教名相同的主次倾向映射，保证标题与结局描述来自同一组合。
func get_religion_description(primary_tendency_id: String, secondary_tendency_id: String) -> String:
	match _build_combination_key(primary_tendency_id, secondary_tendency_id):
		"orthodox/orthodox":
			return orthodox_description
		"orthodox/heretical":
			return orthodox_heretical_description
		"orthodox/absurd":
			return orthodox_absurd_description
		"heretical/orthodox":
			return heretical_orthodox_description
		"heretical/heretical":
			return heretical_description
		"heretical/absurd":
			return heretical_absurd_description
		"absurd/orthodox":
			return absurd_orthodox_description
		"absurd/heretical":
			return absurd_heretical_description
		"absurd/absurd":
			return absurd_description
		_:
			return ""


# 供配置检查和后续结局数据阶段确认九个组合都有策划文本。
func has_complete_mapping() -> bool:
	for primary_tendency_id: String in _TENDENCY_IDS:
		for secondary_tendency_id: String in _TENDENCY_IDS:
			if get_religion_name(primary_tendency_id, secondary_tendency_id).is_empty():
				return false
	return true


func _build_combination_key(primary_tendency_id: String, secondary_tendency_id: String) -> String:
	if not _TENDENCY_IDS.has(primary_tendency_id) or not _TENDENCY_IDS.has(secondary_tendency_id):
		return ""
	return "%s/%s" % [primary_tendency_id, secondary_tendency_id]
