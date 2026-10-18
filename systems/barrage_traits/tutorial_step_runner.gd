class_name TutorialStepRunner
extends RefCounted

signal hint_requested(step_id: String, hint_text: String)
signal step_completed(step_id: String)
signal tutorial_completed(config_id: String)

const TABLE_PATH := "res://data/source_tables/24_新手教学配置.csv"
var _config_id: String = ""
var _steps: Array[Dictionary] = []
var _completed: Array[String] = []
var _active_index: int = -1
var _active_triggered: bool = false
var _finished: bool = false


## 重新进入和失败重开均由周目拥有者传入已完成 ID；运行器只持有读取副本。
func begin(config_id: String, completed_step_ids: Array[String] = []) -> bool:
	_config_id = config_id
	_steps.clear()
	_completed = completed_step_ids.duplicate()
	_active_index = -1
	_active_triggered = false
	_finished = false
	for row: Dictionary in _read_rows():
		if row.get("tutorial_config_id", "") == config_id and row.get("enabled", "").to_lower() == "true":
			_steps.append(row)
	_steps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("step_order", "0")) < int(b.get("step_order", "0")))
	for index: int in _steps.size():
		if not _completed.has(str(_steps[index].get("step_id", ""))):
			_active_index = index
			# 已完成上一阶段即已发生下一阶段触发事实，恢复时重新发布当前提示。
			if index > 0 and str(_steps[index - 1].get("completion_event", "")) == str(_steps[index].get("trigger_event", "")):
				_show_active_hint()
			return true
	if not _steps.is_empty():
		_finish()
	return false


## 只消费当前步骤的事实；先更新状态再发信号，重复或重入事件不会重复完成。
func notify_event(event_id: String) -> bool:
	if _finished or _active_index < 0 or _active_index >= _steps.size():
		return false
	var step: Dictionary = _steps[_active_index]
	if _active_triggered and event_id == str(step.get("completion_event", "")):
		var completed_id: String = str(step.get("step_id", ""))
		if not _completed.has(completed_id):
			_completed.append(completed_id)
		_active_index += 1
		_active_triggered = false
		step_completed.emit(completed_id)
		if _active_index >= _steps.size():
			_finish()
		elif event_id == str(_steps[_active_index].get("trigger_event", "")):
			_show_active_hint()
		return true
	if not _active_triggered and event_id == str(step.get("trigger_event", "")):
		_show_active_hint()
		return true
	return false


## INT-16 每帧传现有对象；目标几何与满蓄读取真实公开接口，暂停时冻结观察。
func observe_combat_frame(
	area: BarrageArea,
	aim: AimReticle,
	attack: AttackChargeInput,
	contradiction_targets: bool = false
) -> void:
	if _finished or area == null or aim == null or attack == null or not area.is_inside_tree() or area.get_tree().paused:
		return
	var has_target: bool = false
	var overlaps: bool = false
	for child: Node in area.get_children():
		if not child is BarrageView or child.is_queued_for_deletion():
			continue
		var view := child as BarrageView
		# 隐藏的目标没有可见瞄准事实，不能启动或完成教学。
		if not view.is_visible_in_tree():
			continue
		var facts: BarrageRuntimeRecord = view.runtime_record
		if (facts == null or facts.is_repeat or facts.is_contradiction != contradiction_targets
				or facts.expires_at_msec <= Time.get_ticks_msec()):
			continue
		if (not contradiction_targets
				and (not facts.trait_set.is_selectable()
					or not facts.trait_set.get_hit_result().receives_normal_reward)):
			continue
		var visible_rect: Rect2 = area.get_global_rect().intersection(view.get_global_rect())
		if visible_rect.size.x <= 0.0 or visible_rect.size.y <= 0.0:
			continue
		has_target = true
		if aim.intersects_target_area(visible_rect):
			overlaps = true
	if has_target:
		notify_event("tutorial_target_available")
	if overlaps:
		notify_event("tutorial_aim_acquired")
	if attack.is_fully_charged():
		notify_event("tutorial_charge_full")


## 连接 BattleAttemptFlow.shot_resolved，只让已结算的有效普通非复读命中完成 fire。
func on_shot_resolved(_snapshot: AttackTargetSnapshot, submission: Dictionary, _tier: int, _stats: RepeatGenerationStats) -> void:
	var result: Dictionary = submission.get("hit_resolution_result", {})
	if bool(result.get("cancelled_by_zero_pk", false)) or bool(result.get("terminal_mode", false)):
		return
	for target: Dictionary in result.get("target_results", []):
		var trait_result := target.get("trait_result") as BarrageTraitResult
		if bool(target.get("is_valid_hit", false)) and not bool(target.get("is_repeat", false)) and trait_result != null and trait_result.receives_normal_reward:
			notify_event("tutorial_normal_hit")
			return


## D 可在 UI 重新绑定后读取同一提示，避免重新驱动步骤。
func get_current_hint() -> Dictionary:
	if _finished or not _active_triggered or _active_index < 0 or _active_index >= _steps.size():
		return {}
	return {"step_id": get_active_step_id(), "hint_text": str(_steps[_active_index].get("hint_text", ""))}


## 交给周目拥有者保存；外部修改返回值不会回写步骤。
func get_completed_step_ids() -> Array[String]:
	return _completed.duplicate()


## 当前未完成步骤 ID，全部结束后为空。
func get_active_step_id() -> String:
	if _finished or _active_index < 0 or _active_index >= _steps.size():
		return ""
	return str(_steps[_active_index].get("step_id", ""))


## 当前阶段激活后发布已有配置提示。
func _show_active_hint() -> void:
	_active_triggered = true
	var step: Dictionary = _steps[_active_index]
	hint_requested.emit(str(step.get("step_id", "")), str(step.get("hint_text", "")))


## 完成事实在本次 begin 中只发布一次。
func _finish() -> void:
	if _finished:
		return
	_finished = true
	_active_index = -1
	tutorial_completed.emit(_config_id)


## 直接读取正式 24 表，不复制策划步骤和提示文案。
func _read_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file == null:
		push_error("TutorialStepRunner: 无法读取正式教学表。")
		return rows
	var headers: PackedStringArray = file.get_csv_line()
	while not file.eof_reached():
		var values: PackedStringArray = file.get_csv_line()
		if values.size() != headers.size():
			continue
		var row: Dictionary = {}
		for index: int in headers.size():
			row[headers[index]] = values[index]
		rows.append(row)
	return rows
