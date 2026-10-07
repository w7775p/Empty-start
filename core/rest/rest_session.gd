class_name RestSession
extends RefCounted

signal opened(result_snapshot: Dictionary)

var _result_snapshot: Dictionary = {}
var _open: bool = false


# 休息入口只冻结本场已经确定的结果；重复打开不替换第一次收到的事实。
func open_result(result_snapshot: Dictionary) -> bool:
	if _open or String(result_snapshot.get("level_id", "")).is_empty():
		return false
	var result_kind: String = String(result_snapshot.get("result_kind", ""))
	if result_kind != "pk_win_unbroken" and result_kind != "breakthrough_oracle_complete":
		return false
	_result_snapshot = result_snapshot.duplicate(true)
	_open = true
	opened.emit(get_result_snapshot())
	return true


func is_open() -> bool:
	return _open


func get_result_snapshot() -> Dictionary:
	return _result_snapshot.duplicate(true)
