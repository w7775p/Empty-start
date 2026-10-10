class_name ContradictionBreakSystem
extends Node

enum Outcome { PENDING, BREAKTHROUGH, NOT_BROKEN }

signal outcome_locked(outcome: int)

## 当前关卡的静态矛盾内容只由 LevelProfile 提供，不改写原始 Resource。
var _true_contradictions: Array[LevelContradiction] = []
var _false_contradictions: Array[LevelContradiction] = []
var _context_clues: Array[String] = []
var _window_timer: Timer
var _remaining_shots: int = 0
var _pending_shots: int = 0
var _window_active: bool = false
var _outcome: Outcome = Outcome.PENDING
var _contradiction_break_enabled: bool = true


func _ready() -> void:
	_window_timer = Timer.new()
	_window_timer.one_shot = true
	# Godot 的暂停模式会在全局暂停时保存 Timer 剩余时间。
	_window_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_window_timer.timeout.connect(_on_window_timeout)
	add_child(_window_timer)


# 在进入矛盾阶段时接收当前关卡；复制列表以固定本场读取到的内容。
func load_level_content(level_profile: LevelProfile) -> bool:
	if level_profile == null:
		return false
	_true_contradictions = level_profile.true_contradictions.duplicate()
	_false_contradictions = level_profile.false_contradictions.duplicate()
	_context_clues = level_profile.contradiction_context_clues.duplicate()
	return true


func get_true_contradictions() -> Array[LevelContradiction]:
	return _true_contradictions.duplicate()


func get_false_contradictions() -> Array[LevelContradiction]:
	return _false_contradictions.duplicate()


## 返回顺序固定为唯一真句在首、五个假句随后，供阶段协调方按真假分组。
func get_fixed_paradox_candidates() -> Array[LevelContradiction]:
	var candidates: Array[LevelContradiction] = []
	var valid_true_lines: Array[LevelContradiction] = _get_valid_contradictions(_true_contradictions)
	var valid_false_lines: Array[LevelContradiction] = _get_valid_contradictions(_false_contradictions)
	if valid_true_lines.is_empty() or valid_false_lines.is_empty():
		return candidates

	# 按关卡顺序取唯一真句；假句数量不足时复用已有原句，不编造正式文本或 ID。
	for index: int in range(ContradictionWindowConfig.PARADOX_TRUE_CANDIDATE_COUNT):
		candidates.append(valid_true_lines[index])
	for index: int in range(ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT):
		candidates.append(valid_false_lines[index % valid_false_lines.size()])
	return candidates


# 只把有稳定 ID 和可见文本的关卡条目交给矛盾阶段。
func _get_valid_contradictions(lines: Array[LevelContradiction]) -> Array[LevelContradiction]:
	var valid_lines: Array[LevelContradiction] = []
	for line: LevelContradiction in lines:
		if line != null and not line.original_sentence_id.is_empty() and not line.text.is_empty():
			valid_lines.append(line)
	return valid_lines


func get_context_clues() -> Array[String]:
	return _context_clues.duplicate()


# 由阶段协调者传入数值表配置；本系统只持有本场运行计时与机会。
func start_window(config: ContradictionWindowConfig) -> bool:
	if config == null or config.duration_seconds <= 0.0 or config.max_shots <= 0:
		return false
	if not _contradiction_break_enabled:
		return false
	if _window_timer == null or _window_active or is_result_locked():
		return false
	_remaining_shots = config.max_shots
	_pending_shots = 0
	_window_active = true
	_outcome = Outcome.PENDING
	_window_timer.start(config.duration_seconds)
	return true


# 终局模式关闭矛盾流程；已经存在的窗口也立即停止，避免继续消耗发射机会。
func set_contradiction_break_enabled(enabled: bool) -> void:
	_contradiction_break_enabled = enabled
	if not enabled:
		_window_active = false
		_pending_shots = 0
		_remaining_shots = 0
		if _window_timer != null:
			_window_timer.stop()


func allows_contradiction_break() -> bool:
	return _contradiction_break_enabled


func get_remaining_seconds() -> float:
	if not _window_active:
		return 0.0
	return _window_timer.time_left


func get_remaining_shots() -> int:
	return _remaining_shots


func get_outcome() -> Outcome:
	return _outcome


func is_result_locked() -> bool:
	return _outcome != Outcome.PENDING


func can_launch_shot() -> bool:
	return _window_active and not is_result_locked() and _remaining_shots > 0


# 只接收 AttackChargeInput 真正满蓄发射后产生的快照事实；取消蓄力不调用此入口。
func register_launched_shot() -> bool:
	if not can_launch_shot():
		return false
	_remaining_shots -= 1
	_pending_shots += 1
	return true


# 一发到达后只按稳定原句 ID 判定；矛盾命中不提交普通 PK 或倾向收益。
func resolve_shot_hit_ids(hit_sentence_ids: Array[String]) -> bool:
	if not _window_active or _pending_shots <= 0:
		return false
	_pending_shots -= 1
	for contradiction in _true_contradictions:
		if contradiction != null and hit_sentence_ids.has(contradiction.original_sentence_id):
			_lock_outcome(Outcome.BREAKTHROUGH)
			return true
	if _remaining_shots == 0 and _pending_shots == 0:
		_finish_without_breakthrough()
	return true


# 到期优先形成未击破结果；已结束的成功判定不再被倒计时覆盖。
func _on_window_timeout() -> void:
	if _window_active and _outcome == Outcome.PENDING:
		_finish_without_breakthrough()


func _finish_without_breakthrough() -> void:
	_lock_outcome(Outcome.NOT_BROKEN)


# 第一份结果是本场唯一事实；锁定后关闭计时与攻击入口。
func _lock_outcome(value: Outcome) -> void:
	if is_result_locked():
		return
	_outcome = value
	_window_active = false
	_window_timer.stop()
	outcome_locked.emit(value)
