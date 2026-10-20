## 本周目当前普通关卡运行状态；状态实例范围内按关卡 ID 去重。
class_name LevelRunState
extends RefCounted

enum CompletionResult {
	INVALID_LEVEL,
	ALREADY_COMPLETED,
	LEVEL_NOT_CURRENT,
	ADVANCED,
	ALL_NORMAL_LEVELS_COMPLETED,
}

var _catalog: LevelCatalog
var _current_level: LevelProfile
var _completed_level_ids: Dictionary = {}
var _all_normal_levels_completed: bool = false

func _init(catalog: LevelCatalog) -> void:
	_catalog = catalog
	_current_level = _find_first_level()

## 返回当前选中的普通关卡配置；空目录时返回 null，最终完成后保留最后一关。
func get_current_level_profile() -> LevelProfile:
	return _current_level

## 按 LevelProfile.level_order 切换当前关卡，非法序号不会改变当前选择。
func set_current_level_order(level_order: int) -> bool:
	if _all_normal_levels_completed:
		return false
	var selected_level: LevelProfile = _find_level_by_order(level_order)
	if selected_level == null:
		return false
	_current_level = selected_level
	return true

## 从房间恢复进度；终局标记只接受目录内所有稳定关卡均已完成的存档。
func restore_progress(
		next_level_order: int,
		completed_ids: Array[String],
		campaign_completed: bool = false
	) -> bool:
	if _catalog == null or _all_normal_levels_completed:
		return false

	var restored_ids: Dictionary = {}
	for level_id: String in completed_ids:
		var profile: LevelProfile = _find_level_by_id(level_id)
		if profile == null or restored_ids.has(level_id):
			return false
		restored_ids[level_id] = true

	if campaign_completed:
		var final_profile: LevelProfile
		for profile: LevelProfile in _catalog.profiles:
			if profile == null:
				continue
			if final_profile == null or profile.level_order > final_profile.level_order:
				final_profile = profile
			if not restored_ids.has(profile.level_id):
				return false
		if final_profile == null or next_level_order != final_profile.level_order:
			return false
		_current_level = final_profile
		_completed_level_ids = restored_ids
		_all_normal_levels_completed = true
		return true

	var selected_level: LevelProfile = _find_level_by_order(next_level_order)
	if selected_level == null:
		return false
	for level_id: String in restored_ids:
		var prior_profile: LevelProfile = _find_level_by_id(level_id)
		if prior_profile == null or prior_profile.level_order >= selected_level.level_order:
			return false
	# 所有前序关卡都应已完成，禁止缺少记录时直接跳入后关。
	for profile: LevelProfile in _catalog.profiles:
		if profile != null and profile.level_order < selected_level.level_order and not restored_ids.has(profile.level_id):
			return false
	_current_level = selected_level
	_completed_level_ids = restored_ids
	return true

## 以当前周目状态实例 + 稳定关卡 ID 标记完成，重复提交不会再次推进。
func complete_level(level_id: String) -> CompletionResult:
	if level_id.is_empty() or _find_level_by_id(level_id) == null:
		return CompletionResult.INVALID_LEVEL
	if _completed_level_ids.has(level_id):
		return CompletionResult.ALREADY_COMPLETED
	if _current_level == null or _current_level.level_id != level_id:
		return CompletionResult.LEVEL_NOT_CURRENT

	_completed_level_ids[level_id] = true
	var next_level: LevelProfile = _find_next_level(_current_level.level_order)
	if next_level == null:
		_all_normal_levels_completed = true
		return CompletionResult.ALL_NORMAL_LEVELS_COMPLETED
	_current_level = next_level
	return CompletionResult.ADVANCED

## 供流程读取普通关卡是否全部完成；本类不负责切换到终局场景。
func is_all_normal_levels_completed() -> bool:
	return _all_normal_levels_completed

## 查找序号最小的关卡，作为新一局的第一关。
func _find_first_level() -> LevelProfile:
	if _catalog == null:
		return null
	var first_level: LevelProfile
	for profile in _catalog.profiles:
		if profile == null:
			continue
		if first_level == null or profile.level_order < first_level.level_order:
			first_level = profile
	return first_level

func _find_level_by_order(level_order: int) -> LevelProfile:
	if _catalog == null:
		return null
	for profile in _catalog.profiles:
		if profile != null and profile.level_order == level_order:
			return profile
	return null

func _find_level_by_id(level_id: String) -> LevelProfile:
	if _catalog == null:
		return null
	for profile in _catalog.profiles:
		if profile != null and profile.level_id == level_id:
			return profile
	return null

## 取比当前序号更大的最小关卡，允许序号之间留有空位。
func _find_next_level(current_order: int) -> LevelProfile:
	if _catalog == null:
		return null
	var next_level: LevelProfile
	for profile in _catalog.profiles:
		if profile == null or profile.level_order <= current_order:
			continue
		if next_level == null or profile.level_order < next_level.level_order:
			next_level = profile
	return next_level
