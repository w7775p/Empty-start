## 负责普通战斗的批次计时、倍率应用与单条弹幕实例化。
class_name BarrageArea
extends Control

## 普通话语与复读均在视图进入场景树并完成定位后通知成功生成。
signal barrage_generated(view: BarrageView)

@export var barrage_view_scene: PackedScene
## 临时全局基础寿命，正式数值表接入前可在 Inspector 调整。
@export var base_lifetime_seconds: float = 10.0
## 临时复读同屏上限，正式数值表接入前可在 Inspector 调整。
@export var repeat_barrage_screen_cap: int = 24
## 普通移动前景的最高速度；默认沿用现有关卡基础速度，避免 Tier 倍率让短句快速掠过。
@export var maximum_foreground_move_speed_pixels_per_second: float = 100.0
@export_group("BG-21 普通前景曲线运动")
## 开启后，仅新生成的普通移动前景使用平滑曲线；静止请求、复读与矛盾保持原行为。
@export var curved_foreground_motion_enabled: bool = false
## 普通前景曲线的最大垂直弧高，实际值会按当前战斗区可用空间收窄。
@export_range(0.0, 180.0, 4.0) var curved_foreground_motion_amplitude_pixels: float = 72.0
@onready var _spawn_timer: Timer = $SpawnTimer

var _speech_selector: NormalSpeechSelector = NormalSpeechSelector.new()
var _current_level_profile: LevelProfile
var _normal_generation_enabled: bool = false
var _contradiction_generation_enabled: bool = false
var _contradiction_lines: Array[LevelContradiction] = []
var _contradiction_initial_set_spawned: bool = false
var _contradiction_config: ContradictionWindowConfig
var _count_multiplier: float = 1.0
var _frequency_multiplier: float = 1.0
var _movement_speed_multiplier: float = 1.0
var _lifetime_multiplier: float = 1.0
var _neutral_weight_multiplier: float = 1.0
var _foreground_slot_count: int = 0
## 普通话语与陷阱共用的容量账本。
var _normal_capacity_ledger: BarrageCapacityLedger = BarrageCapacityLedger.new()
var _repeat_capacity_ledger: BarrageCapacityLedger = BarrageCapacityLedger.new()
var _next_spawn_row: int = 0
var _terminal_presentation_only: bool = false
var _terminal_trait_ids: Array[StringName] = []
var _terminal_trait_colors: Dictionary = {}

## 终局只保存表现 ID 和显式配色；不装配普通特性，不改动已在场实例。
func enter_terminal_presentation(trait_ids: Array[StringName] = [], trait_colors: Dictionary = {}) -> void:
	_terminal_presentation_only = true
	var supported := BarrageTraitSet.new()
	for trait_id: StringName in trait_ids:
		supported.add_trait(trait_id)
	_terminal_trait_ids = supported.get_trait_ids()
	_terminal_trait_colors = trait_colors.duplicate()

## 雷尚无独立生成器；陷阱调用方必须在创建前查询同一终局边界。
func allows_trap_generation() -> bool:
	return not _terminal_presentation_only

## 连接批次 Timer；区域直接使用父场景保存的 Rect，本组件负责生成和裁剪。
func _ready() -> void:
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)

## 打开普通生成并立即生成第一批，之后按当前关卡间隔与频率倍率循环。
func start_normal_generation(level_profile: LevelProfile) -> bool:
	if level_profile == null or level_profile.base_spawn_interval_seconds <= 0.0:
		return false
	if _normal_generation_enabled:
		if _current_level_profile == level_profile:
			return true
		stop_normal_generation()
	_current_level_profile = level_profile
	_normal_generation_enabled = true
	if _frequency_multiplier > 0.0:
		_spawn_normal_batch()
	_restart_spawn_timer()
	return true

## 矛盾阶段一次性显示协调方提供的固定候选集，并沿用 Paradox 速度与寿命配置。
func start_contradiction_generation(
	level_profile: LevelProfile,
	true_lines: Array[LevelContradiction],
	false_lines: Array[LevelContradiction],
	config: ContradictionWindowConfig
) -> bool:
	if level_profile == null or config == null:
		return false
	if config.duration_seconds <= 0.0 or config.movement_speed_multiplier <= 0.0:
		return false
	if true_lines.size() != ContradictionWindowConfig.PARADOX_TRUE_CANDIDATE_COUNT or false_lines.size() != ContradictionWindowConfig.PARADOX_FALSE_CANDIDATE_COUNT:
		return false
	var lines: Array[LevelContradiction] = []
	for line: LevelContradiction in true_lines + false_lines:
		if line == null or line.original_sentence_id.is_empty() or line.text.is_empty():
			return false
		lines.append(line)
	stop_normal_generation()
	stop_contradiction_generation()
	_current_level_profile = level_profile
	_contradiction_lines = lines
	_contradiction_config = config
	_contradiction_generation_enabled = true
	if not _spawn_contradiction_batch():
		stop_contradiction_generation()
		return false
	return true


## 离开矛盾阶段时关闭矛盾生成入口；已生成实例由场景协调方决定何时清理。
func stop_contradiction_generation() -> void:
	_contradiction_generation_enabled = false
	_contradiction_lines.clear()
	_contradiction_initial_set_spawned = false
	_contradiction_config = null
	_spawn_timer.stop()

## 更新倍率只影响后续批次和新弹幕；已有实例保留创建时的移动速度。
func set_generation_multipliers(generation_count_multiplier: float, generation_frequency_multiplier: float, movement_speed_multiplier: float) -> void:
	_count_multiplier = generation_count_multiplier
	_frequency_multiplier = generation_frequency_multiplier
	_movement_speed_multiplier = movement_speed_multiplier
	_restart_spawn_timer()

## 唯一普通前景速度入口：读取关卡基础速度与当前 Tier 倍率后应用可调上限。
func get_foreground_move_speed_pixels_per_second(level_profile: LevelProfile) -> float:
	if level_profile == null:
		return 0.0
	var base_speed: float = maxf(level_profile.base_move_speed_pixels_per_second, 0.0)
	var tier_multiplier: float = maxf(_movement_speed_multiplier, 0.0)
	var speed_ceiling: float = maxf(maximum_foreground_move_speed_pixels_per_second, 0.0)
	return minf(base_speed * tier_multiplier, speed_ceiling)

## 保存当前寿命倍率；它只参与之后新建弹幕的截止时间计算。
func set_lifetime_multiplier(lifetime_multiplier: float) -> void:
	_lifetime_multiplier = lifetime_multiplier

## 当前 Tier 的 Neutral 权重只影响之后新生成的普通话语。
func set_neutral_weight_multiplier(multiplier: float) -> void:
	_neutral_weight_multiplier = maxf(multiplier, 0.0)

## 接收 CombatStage 发布的当前 Tier 名额；配额变化后重算因容量暂停的批次 Timer。
func set_foreground_slot_count(slot_count: int) -> void:
	_foreground_slot_count = slot_count
	_restart_spawn_timer()

## 为后续前景容量逻辑提供当前 Tier 名额；0 表示 T0 数值尚未确定。
func get_foreground_slot_count() -> int:
	return _foreground_slot_count

## T0 使用关卡普通容量 fallback；矛盾实例走候选集自身的独立容量。
func _get_foreground_capacity_limit(level_profile: LevelProfile) -> int:
	if level_profile == null:
		return 0
	if _contradiction_generation_enabled or _foreground_slot_count == 0:
		return level_profile.normal_barrage_screen_cap
	return _foreground_slot_count

## 申请普通弹幕共享容量；未设置当前关卡或容量满时返回 false。
func try_register_normal_capacity_occupant(occupant: Object) -> bool:
	# 普通话语由内部入口登记；终局拒绝外部陷阱共享占位请求。
	if _terminal_presentation_only or _current_level_profile == null:
		return false
	return _try_register_normal_capacity_occupant(occupant, _get_foreground_capacity_limit(_current_level_profile))

## 释放占位对象；普通弹幕节点离树时会自动调用此入口。
func release_normal_capacity_occupant(occupant: Object) -> bool:
	if not _normal_capacity_ledger.release(occupant):
		return false
	# 只有满容量曾暂停计时时才恢复；正在运行的周期保留剩余时间，命中不会推迟下一批。
	if _spawn_timer.is_stopped():
		_restart_spawn_timer()
	return true

## 以当前关卡的容量限制登记普通弹幕或陷阱占位者。
func _try_register_normal_capacity_occupant(occupant: Object, capacity_limit: int) -> bool:
	if occupant == null:
		return false
	if _normal_capacity_ledger.has_occupant(occupant):
		return true
	if not _normal_capacity_ledger.try_register(occupant, capacity_limit):
		_pause_normal_generation_timer()
		return false
	if occupant is Node:
		var occupant_node: Node = occupant as Node
		occupant_node.tree_exited.connect(_on_normal_capacity_occupant_tree_exited.bind(occupant), CONNECT_ONE_SHOT)
	if not _normal_capacity_ledger.has_capacity(capacity_limit):
		_pause_normal_generation_timer()
	return true

## 节点实例离开场景树时自动归还共享容量。
func _on_normal_capacity_occupant_tree_exited(occupant: Object) -> void:
	release_normal_capacity_occupant(occupant)

## 容量达到上限时保留生成开启状态，只暂停批次 Timer。
func _pause_normal_generation_timer() -> void:
	if _normal_generation_enabled or _contradiction_generation_enabled:
		_spawn_timer.stop()

## 关闭普通生成；已在场弹幕继续按自己的运行参数移动。
func stop_normal_generation() -> void:
	_normal_generation_enabled = false
	if not _contradiction_generation_enabled:
		_spawn_timer.stop()

func resume_normal_generation() -> bool:
	# 矛盾阶段由专属生成器接管；普通调试恢复只作用于普通战斗。
	if _contradiction_generation_enabled:
		return false
	if _current_level_profile == null or _current_level_profile.base_spawn_interval_seconds <= 0.0:
		return false
	_normal_generation_enabled = true
	_restart_spawn_timer()
	return true


func is_normal_generation_enabled() -> bool:
	return _normal_generation_enabled


func clear_current_barrages() -> int:
	# 调试清屏保留当前生成开关；阶段结束仍使用 clear_barrages。
	return _clear_barrage_views()


func spawn_normal_batch_now() -> int:
	# Paradox 阶段由专属生成器接管，不从调试入口插入普通话语。
	if _contradiction_generation_enabled:
		return 0
	return _spawn_normal_batch(true)


# 只读取区域内实际可见的弹幕记录；纯 UI、隐藏及待移除视图不参与终局占比。
func get_visible_barrage_records() -> Array[BarrageRuntimeRecord]:
	var records: Array[BarrageRuntimeRecord] = []
	var area_rect := Rect2(Vector2.ZERO, size)
	for child in get_children():
		if not child is BarrageView or child.is_queued_for_deletion():
			continue
		var view := child as BarrageView
		if view.runtime_record == null or not view.is_visible_in_tree():
			continue
		if area_rect.intersects(Rect2(view.position, view.size)):
			records.append(view.runtime_record)
	return records


func get_current_barrage_counts() -> Dictionary:
	# 从当前真实 BarrageView 汇总，不保存第二份计数。
	var normal_count: int = 0
	var repeat_count: int = 0
	var contradiction_count: int = 0
	for child in get_children():
		if not child is BarrageView or child.is_queued_for_deletion():
			continue
		var view: BarrageView = child as BarrageView
		if view.runtime_record == null:
			continue
		if view.runtime_record.is_repeat:
			repeat_count += 1
		elif view.runtime_record.is_contradiction:
			contradiction_count += 1
		else:
			normal_count += 1
	return {"normal": normal_count, "repeat": repeat_count, "contradiction": contradiction_count}


## 结算协调方按实例 ID 结束本区域目标；立即离树归还容量，重复请求保持无副作用。
func end_barrage(target_instance_id: int) -> bool:
	var target: Object = instance_from_id(target_instance_id)
	if not is_instance_valid(target) or not target is BarrageView:
		return false
	var barrage_view: BarrageView = target as BarrageView
	if barrage_view.get_parent() != self or barrage_view.is_queued_for_deletion():
		return false
	remove_child(barrage_view)
	barrage_view.queue_free()
	return true

## 重开或阶段结束时停止普通生成并清理当前视图，避免旧实例占用新一局容量。
func clear_barrages() -> void:
	stop_normal_generation()
	stop_contradiction_generation()
	_clear_barrage_views()


# 移除当前所有弹幕视图并释放容量；调用方决定是否停止生成器。
func _clear_barrage_views() -> int:
	var cleared_count: int = 0
	for child in get_children():
		if child is BarrageView:
			if child.is_queued_for_deletion():
				remove_child(child)
				child.queue_free()
			else:
				end_barrage(child.get_instance_id())
			cleared_count += 1
	_next_spawn_row = 0
	return cleared_count


# 从当前周目读取可用特性；每次查询返回副本，换关和重开无需另存继承缓存。
func get_available_trait_ids(level_profile: LevelProfile) -> Array[StringName]:
	# 通过已登记 Autoload 节点读取，单文件 CLI 检查也能解析；未入树时仅提供本关特性。
	var save_manager: Node = get_node_or_null("/root/SaveManager") if is_inside_tree() else null
	var run_data: SaveData = save_manager.get("data") as SaveData if save_manager != null else null
	return BarrageTraitSet.get_available_for_level(
		level_profile, run_data.assimilation_data if run_data != null else null
	)


## 显式选择普通话语特性并可单次请求随机静止落点；新参数默认保留既有行为。
func spawn_normal_barrage(
	level_profile: LevelProfile,
	speech: LevelSpeech,
	selected_trait_ids: Array[StringName] = [],
	random_static_placement: bool = false
) -> BarrageView:
	if level_profile == null or speech == null:
		push_error("BarrageArea: 生成普通弹幕需要关卡配置和话语定义。")
		return null
	if barrage_view_scene == null:
		push_error("BarrageArea: 未配置弹幕表现 Scene。")
		return null

	var capacity_limit: int = _get_foreground_capacity_limit(level_profile)
	if not _normal_capacity_ledger.has_capacity(capacity_limit):
		_pause_normal_generation_timer()
		return null

	var barrage_record: BarrageRuntimeRecord = BarrageRuntimeRecord.new()
	# 当前入口创建普通原句，陷阱和复读继续使用各自生成入口及类型信息。
	# 终局忽略普通特性选择，只保留独立表现配置，避免反弹、分裂或不可选触发规则。
	if not _terminal_presentation_only and not barrage_record.trait_set.add_available_traits(selected_trait_ids, get_available_trait_ids(level_profile)):
		return null
	barrage_record.text = speech.text
	barrage_record.original_sentence_text = speech.text
	barrage_record.source_id = level_profile.streamer_id
	barrage_record.tendency_id = speech.tendency_id
	barrage_record.strength = float(speech.strength)
	barrage_record.original_sentence_id = speech.original_sentence_id
	barrage_record.capture_lifetime_at_spawn(Time.get_ticks_msec(), base_lifetime_seconds, _lifetime_multiplier)

	var view: BarrageView = barrage_view_scene.instantiate() as BarrageView
	if view == null:
		push_error("BarrageArea: 弹幕表现 Scene 根节点需要 BarrageView。")
		return null
	# BG-42 静止请求直接保持零速度；普通移动实例统一经限速入口，并可显式启用曲线。
	var effective_move_speed: float = 0.0 if random_static_placement else get_foreground_move_speed_pixels_per_second(level_profile)
	var curve_amplitude: float = (
		curved_foreground_motion_amplitude_pixels
		if curved_foreground_motion_enabled and not random_static_placement
		else 0.0
	)
	view.setup(barrage_record, effective_move_speed, self, random_static_placement, curve_amplitude)
	if _terminal_presentation_only:
		view.apply_terminal_trait_presentation(_terminal_trait_ids, _terminal_trait_colors)
	if not _try_register_normal_capacity_occupant(view, capacity_limit):
		view.free()
		return null
	add_child(view)
	if not _place_barrage_for_spawn_request(view, random_static_placement):
		# 场上没有可见空位时归还刚申请的容量，普通 Timer 后续继续尝试。
		end_barrage(view.get_instance_id())
		return null
	barrage_generated.emit(view)
	return view


## 单条矛盾沿用区域定位；完整候选集成功后才统一发布生成通知。
func spawn_contradiction_barrage(level_profile: LevelProfile, line: LevelContradiction) -> BarrageView:
	if level_profile == null or line == null or barrage_view_scene == null or _contradiction_config == null or not _contradiction_generation_enabled or _contradiction_initial_set_spawned:
		return null
	# Paradox 容量只按当前矛盾视图和固定候选数计算，不占用普通前景容量账本。
	if int(get_current_barrage_counts().get("contradiction", 0)) >= _contradiction_lines.size():
		return null
	var barrage_record := BarrageRuntimeRecord.new()
	# 真 / 假矛盾使用新记录自带的独立空 TraitSet；不复制普通特性，真假由 12 按原句 ID 判断。
	barrage_record.text = line.text
	barrage_record.original_sentence_text = line.text
	barrage_record.original_sentence_id = line.original_sentence_id
	barrage_record.source_id = level_profile.streamer_id
	barrage_record.is_contradiction = true
	barrage_record.capture_lifetime_at_spawn(Time.get_ticks_msec(), _contradiction_config.duration_seconds, 1.0)
	var view := barrage_view_scene.instantiate() as BarrageView
	if view == null:
		return null
	view.setup(barrage_record, level_profile.base_move_speed_pixels_per_second * _contradiction_config.movement_speed_multiplier, self)
	add_child(view)
	if not _place_new_barrage(view):
		end_barrage(view.get_instance_id())
		return null
	return view

## 把 RepeatPlan 的单条请求显示为场上复读；调用方可单次要求随机静止落点。
func spawn_repeat_barrage(plan: RepeatPlan, random_static_placement: bool = false) -> BarrageView:
	if plan == null or _current_level_profile == null:
		return null
	if barrage_view_scene == null:
		push_error("BarrageArea: 未配置弹幕表现 Scene。")
		return null
	var original_line_id: String = str(plan.original_line_id)
	if original_line_id.is_empty() or plan.lifetime_seconds <= 0.0:
		push_error("BarrageArea: 复读请求需要稳定原句 ID 和正寿命。")
		return null
	if not _repeat_capacity_ledger.has_capacity(repeat_barrage_screen_cap):
		return null

	var repeat_record: BarrageRuntimeRecord = BarrageRuntimeRecord.new()
	repeat_record.text = plan.display_text if not plan.display_text.is_empty() else plan.original_line_text
	repeat_record.original_sentence_text = plan.original_line_text
	repeat_record.is_repeat = true
	repeat_record.is_contradiction_repeat = plan.repeat_type == RepeatPlan.RepeatType.CONTRADICTION
	repeat_record.source_id = _current_level_profile.streamer_id
	repeat_record.original_sentence_id = original_line_id
	repeat_record.tendency_id = plan.tendency_id
	repeat_record.strength = 1.0
	repeat_record.capture_lifetime_at_spawn(Time.get_ticks_msec(), plan.lifetime_seconds, 1.0)

	var view: BarrageView = barrage_view_scene.instantiate() as BarrageView
	if view == null:
		push_error("BarrageArea: 弹幕表现 Scene 根节点需要 BarrageView。")
		return null
	var effective_move_speed: float = _current_level_profile.base_move_speed_pixels_per_second * _movement_speed_multiplier
	view.setup(repeat_record, effective_move_speed, self, random_static_placement)
	if _terminal_presentation_only:
		view.apply_terminal_trait_presentation(_terminal_trait_ids, _terminal_trait_colors)
	if not _try_register_repeat_capacity_occupant(view):
		view.free()
		return null
	add_child(view)
	if not _place_barrage_for_spawn_request(view, random_static_placement):
		# 到期请求继续留在 Repeat 队列，成功定位前不发送实际生成事实。
		end_barrage(view.get_instance_id())
		return null
	barrage_generated.emit(view)
	return view


## 成功击破后的过渡等待实际可见矛盾复读离场，不把排队项当作已展示。
func has_visible_contradiction_repeats() -> bool:
	for child in get_children():
		if child is BarrageView and not child.is_queued_for_deletion():
			var view := child as BarrageView
			if view.runtime_record != null and view.runtime_record.is_contradiction_repeat:
				return true
	return false

## 只对调用方显式请求的实例使用随机静止定位，其他实例继续沿用轮换行。
func _place_barrage_for_spawn_request(view: BarrageView, random_static_placement: bool) -> bool:
	if random_static_placement:
		return _place_random_static_barrage(view)
	return _place_new_barrage(view)


## 按实际视图尺寸和当前区域尺寸均匀抽取完整位于区域内的静止落点。
func _place_random_static_barrage(view: BarrageView) -> bool:
	var max_x: float = size.x - view.size.x
	var max_y: float = size.y - view.size.y
	if max_x < 0.0 or max_y < 0.0:
		return false
	view.position = Vector2(randf_range(0.0, max_x), randf_range(0.0, max_y))
	return true


## 从轮换行寻找当前真实空位；上一轮横移目标仍占着入口时跳到其他行。
func _place_new_barrage(view: BarrageView) -> bool:
	var start_x: float = maxf(size.x - view.size.x, 0.0)
	var top_margin: float = minf(48.0, maxf(size.y - view.size.y, 0.0))
	var row_step: float = view.size.y + 16.0
	var available_height: float = maxf(size.y - view.size.y - top_margin - 16.0, 0.0)
	var row_count: int = maxi(floori(available_height / row_step) + 1, 1)
	for row_offset: int in range(row_count):
		var row_index: int = (_next_spawn_row + row_offset) % row_count
		var candidate_position: Vector2 = Vector2(start_x, top_margin + float(row_index) * row_step)
		var candidate_rect: Rect2 = Rect2(candidate_position, view.size).grow(8.0)
		var overlaps_existing: bool = false
		for child in get_children():
			if child == view or not child is BarrageView or child.is_queued_for_deletion():
				continue
			var existing_view: BarrageView = child as BarrageView
			var existing_rect: Rect2 = Rect2(existing_view.position, existing_view.size).grow(8.0)
			if candidate_rect.intersects(existing_rect):
				overlaps_existing = true
				break
		if overlaps_existing:
			continue
		view.position = candidate_position
		_next_spawn_row = (row_index + 1) % row_count
		return true
	return false

## 复读屏幕容量独立登记，视图离树时自动释放。
func _try_register_repeat_capacity_occupant(occupant: Object) -> bool:
	if occupant == null:
		return false
	if _repeat_capacity_ledger.has_occupant(occupant):
		return true
	if not _repeat_capacity_ledger.try_register(occupant, repeat_barrage_screen_cap):
		return false
	if occupant is Node:
		var occupant_node: Node = occupant as Node
		occupant_node.tree_exited.connect(_on_repeat_capacity_occupant_tree_exited.bind(occupant), CONNECT_ONE_SHOT)
	return true

## 复读视图离树时归还独立屏幕容量。
func _on_repeat_capacity_occupant_tree_exited(occupant: Object) -> void:
	_repeat_capacity_ledger.release(occupant)

## 按四舍五入后的批次数量倍率生成当前批次。
func _spawn_normal_batch(allow_when_stopped: bool = false) -> int:
	if (not _normal_generation_enabled and not allow_when_stopped) or _current_level_profile == null or _frequency_multiplier <= 0.0:
		return 0
	if not _has_normal_capacity_for(_current_level_profile):
		_pause_normal_generation_timer()
		return 0
	var batch_count: int = roundi(float(_current_level_profile.base_batch_count) * _count_multiplier)
	if batch_count <= 0:
		return 0
	var generated_count: int = 0
	for _index in range(batch_count):
		var speech: LevelSpeech = _speech_selector.select_next_normal_speech(_current_level_profile, _neutral_weight_multiplier)
		if speech == null:
			return generated_count
		var barrage_view: BarrageView = spawn_normal_barrage(_current_level_profile, speech)
		if barrage_view == null:
			return generated_count
		generated_count += 1
	return generated_count


## 一次性生成完整候选集；放置失败时撤销本次新增实例，避免留下不完整阶段。
func _spawn_contradiction_batch() -> bool:
	if _contradiction_initial_set_spawned:
		_spawn_timer.stop()
		return false
	if not _contradiction_generation_enabled or _current_level_profile == null or _contradiction_config == null or _contradiction_lines.size() != ContradictionWindowConfig.PARADOX_CANDIDATE_COUNT:
		return false
	var spawned_views: Array[BarrageView] = []
	for line: LevelContradiction in _contradiction_lines:
		var view: BarrageView = spawn_contradiction_barrage(_current_level_profile, line)
		if view == null:
			for spawned_view: BarrageView in spawned_views:
				end_barrage(spawned_view.get_instance_id())
			return false
		spawned_views.append(view)
	_contradiction_initial_set_spawned = true
	for spawned_view: BarrageView in spawned_views:
		barrage_generated.emit(spawned_view)
	return true

## 按当前 Tier 名额或 T0 关卡 fallback 判断普通弹幕容量。
func _has_normal_capacity_for(level_profile: LevelProfile) -> bool:
	return level_profile != null and _normal_capacity_ledger.has_capacity(_get_foreground_capacity_limit(level_profile))

## 根据当前频率倍率更新时间间隔；零频率时保留已开启状态并暂停 Timer。
func _restart_spawn_timer() -> void:
	if not is_inside_tree() or (not _normal_generation_enabled and not _contradiction_generation_enabled) or _current_level_profile == null or _active_frequency_multiplier() <= 0.0 or not _has_normal_capacity_for(_current_level_profile):
		_spawn_timer.stop()
		return
	_spawn_timer.wait_time = _get_effective_spawn_interval()
	_spawn_timer.start()

func _get_effective_spawn_interval() -> float:
	return _current_level_profile.base_spawn_interval_seconds / _active_frequency_multiplier()

## 普通战斗使用当前档位频率；Paradox 没有后续批次 Timer。
func _active_frequency_multiplier() -> float:
	if _contradiction_generation_enabled and _contradiction_config != null:
		return _contradiction_config.generation_frequency_multiplier
	return _frequency_multiplier

## Timer 每到间隔触发一批，关闭状态下保持静默。
func _on_spawn_timer_timeout() -> void:
	if (not _normal_generation_enabled and not _contradiction_generation_enabled) or _current_level_profile == null or _active_frequency_multiplier() <= 0.0:
		return
	if not _has_normal_capacity_for(_current_level_profile):
		_pause_normal_generation_timer()
		return
	if _contradiction_generation_enabled:
		_spawn_contradiction_batch()
	else:
		_spawn_normal_batch()
