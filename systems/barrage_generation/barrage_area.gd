## 负责普通战斗的批次计时、倍率应用与单条弹幕实例化。
class_name BarrageArea
extends Control

enum NormalSpawnEdge { TOP, BOTTOM, LEFT, RIGHT }

## 普通话语与复读均在视图进入场景树并完成定位后通知成功生成。
signal barrage_generated(view: BarrageView)

@export var barrage_view_scene: PackedScene
## 临时全局基础寿命，正式数值表接入前可在 Inspector 调整。
@export var base_lifetime_seconds: float = 10.0
## 临时复读同屏上限，正式数值表接入前可在 Inspector 调整。
@export var repeat_barrage_screen_cap: int = 24
## 普通移动前景的最高速度；默认沿用现有关卡基础速度，避免 Tier 倍率让短句快速掠过。
@export var maximum_foreground_move_speed_pixels_per_second: float = 100.0
@export_group("BG-20 普通前景随机直线方向")
## 围绕出生边内向法线随机偏转的最大角度；保留向内主分量，避免初始运动朝区域外。
@export_range(0.0, 45.0, 1.0) var random_straight_direction_spread_degrees: float = 30.0
@export_group("BG-19 普通前景内部随机出生")
## 每条普通话语从战斗区内部出生的比例；剩余比例使用 BG-18 四边出生。
@export_range(0.0, 1.0, 0.05) var interior_foreground_spawn_ratio: float = 0.0
@export_group("BG-21 普通前景曲线运动")
## 开启后，仅新生成的普通移动前景使用平滑曲线；静止请求、复读与矛盾保持原行为。
@export var curved_foreground_motion_enabled: bool = false
## 普通前景曲线的最大垂直弧高，实际值会按当前战斗区可用空间收窄。
@export_range(0.0, 180.0, 4.0) var curved_foreground_motion_amplitude_pixels: float = 72.0
@export_group("BG-22 普通前景平缓加减速")
## 开启后，仅新生成的普通移动前景按周期加速和减速；默认关闭以保留匀速行为。
@export var speed_change_foreground_motion_enabled: bool = false
## 一次从低速加速到上限再减速回低速的总时长，周期只影响新生成的普通前景。
@export_range(2.0, 16.0, 0.5) var speed_change_foreground_motion_cycle_seconds: float = 6.0
@export_group("BG-23 普通前景低速游荡")
## 开启后，新生成的普通移动前景单独进入游荡状态，不改写 BG-20 的直线方向状态。
@export var normal_foreground_wandering_enabled: bool = false
## 游荡速度仍基于关卡速度与 Tier，再乘以该低速倍率并受 BG-40 上限约束。
@export_range(0.10, 1.0, 0.05) var normal_foreground_wandering_speed_multiplier: float = 0.35
## 游荡视图随机转向的间隔；该值为可调试玩起点。
@export_range(0.5, 10.0, 0.5) var normal_foreground_wandering_direction_change_interval_seconds: float = 2.0
@export_group("BG-26 普通前景运动中换层")
## 每条普通移动前景随机换到另一层级的间隔；0 表示关闭，默认值是可调试玩起点。
@export_range(0.0, 10.0, 0.25) var normal_foreground_layer_change_interval_seconds: float = 2.0
@export_group("BG-27 普通前景缓和缩放")
## 普通移动前景缩小到的最小倍率，视图默认中心锚定。
@export_range(0.90, 0.99, 0.01) var normal_foreground_min_scale: float = 0.96
## 普通移动前景放大到的最大倍率。
@export_range(1.01, 1.10, 0.01) var normal_foreground_max_scale: float = 1.04
## 完成一次放大与缩小往返的时长。
@export_range(3.0, 12.0, 0.5) var normal_foreground_scale_cycle_seconds: float = 6.0
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
## 带特性普通话语另占一个实例名额；同一视图无论有几项特性都只登记一次。
var _special_capacity_ledger: BarrageCapacityLedger = BarrageCapacityLedger.new()
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
	if (not is_finite(config.duration_seconds) or config.duration_seconds <= 0.0
			or not is_finite(config.movement_speed_multiplier) or config.movement_speed_multiplier <= 0.0
			or not is_finite(config.ease_out_motion_duration_seconds)
			or config.ease_out_motion_duration_seconds <= 0.0
			or config.ease_out_motion_duration_seconds >= config.duration_seconds
			or config.ease_out_motion_speed_curve == null
			or config.ease_out_motion_speed_curve.get_point_count() < 2
			or config.ease_out_motion_speed_curve.sample(0.0) <= 0.0
			or config.ease_out_motion_speed_curve.sample(1.0) > 0.001):
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


## 未配置每关特殊上限时，暂沿用普通前景容量作为兼容回退。
func _get_special_foreground_capacity_limit(level_profile: LevelProfile, foreground_capacity_limit: int) -> int:
	if level_profile == null or level_profile.special_instance_screen_cap < 0:
		return foreground_capacity_limit
	return level_profile.special_instance_screen_cap

## 申请普通弹幕共享容量；未设置当前关卡或容量满时返回 false。
func try_register_normal_capacity_occupant(occupant: Object) -> bool:
	# 普通话语由内部入口登记；终局拒绝外部陷阱共享占位请求。
	if _terminal_presentation_only or _current_level_profile == null:
		return false
	return _try_register_normal_capacity_occupant(occupant, _get_foreground_capacity_limit(_current_level_profile))

## 普通视图离树时同时释放前景名额和可能占用的特殊名额。
func release_normal_capacity_occupant(occupant: Object) -> bool:
	var normal_released: bool = _normal_capacity_ledger.release(occupant)
	var special_released: bool = _special_capacity_ledger.release(occupant)
	if not normal_released and not special_released:
		return false
	# 只有满容量曾暂停计时时才恢复；正在运行的周期保留剩余时间，命中不会推迟下一批。
	if normal_released and _spawn_timer.is_stopped():
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


## 遮挡特性自动随机静止定位；其他普通话语仍可单次请求随机静止落点。
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
	var has_selected_traits: bool = not barrage_record.trait_set.get_trait_ids().is_empty()
	var special_capacity_limit: int = _get_special_foreground_capacity_limit(level_profile, capacity_limit)
	if has_selected_traits and not _special_capacity_ledger.has_capacity(special_capacity_limit):
		# 特殊名额用尽只拒绝当前带特性请求，不暂停未满的普通前景生成。
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
	# 遮挡是实例特性，直接决定静止落点；合并其他兼容特性时继续保持静止。
	var should_use_random_static_placement: bool = (
		random_static_placement or barrage_record.trait_set.has_trait(BarrageTraitSet.OCCLUSION)
	)
	var should_use_wandering_motion: bool = (
		normal_foreground_wandering_enabled
		and not _terminal_presentation_only and not should_use_random_static_placement
	)
	# 单次抽取普通移动话语的内部出生模式；静止请求绕过比例选择。
	var should_use_random_interior_placement: bool = (
		not should_use_random_static_placement
		and randf() < clampf(interior_foreground_spawn_ratio, 0.0, 1.0)
	)
	var random_spawn_edge: int = -1
	var inward_move_direction: Vector2 = Vector2.LEFT
	var uses_existing_motion_variant: bool = (
		curved_foreground_motion_enabled or speed_change_foreground_motion_enabled
	)
	if not should_use_random_static_placement:
		if should_use_random_interior_placement:
			# 内部没有出生边法线时，以现有左向直线为基线复用 BG-20 偏转设置。
			if not should_use_wandering_motion and not uses_existing_motion_variant:
				inward_move_direction = _get_random_straight_direction(Vector2.LEFT)
		else:
			# 方向仅用于本次边缘出生；运动速度和生命周期仍走现有普通前景路径。
			random_spawn_edge = randi_range(NormalSpawnEdge.TOP, NormalSpawnEdge.RIGHT)
			# BG-20 只改变当前直线模式；曲线与加减速继续沿用原出生法线。
			inward_move_direction = (
				_get_inward_direction_for_edge(random_spawn_edge)
				if uses_existing_motion_variant
				else _get_random_inward_direction_for_edge(random_spawn_edge)
			)
	# BG-42 静止实例保持零速度；移动前景沿用限速、曲线和周期加减速配置。
	var base_move_speed: float = (
		0.0 if should_use_random_static_placement else get_foreground_move_speed_pixels_per_second(level_profile)
	)
	var effective_move_speed: float = (
		base_move_speed * clampf(normal_foreground_wandering_speed_multiplier, 0.10, 1.0)
		if should_use_wandering_motion else base_move_speed
	)
	var curve_amplitude: float = (
		curved_foreground_motion_amplitude_pixels
		if curved_foreground_motion_enabled and not should_use_random_static_placement and not should_use_wandering_motion
		else 0.0
	)
	var speed_change_cycle: float = (
		speed_change_foreground_motion_cycle_seconds
		if speed_change_foreground_motion_enabled and not should_use_random_static_placement
		else 0.0
	)
	var layer_change_interval: float = (
		normal_foreground_layer_change_interval_seconds
		if not should_use_random_static_placement
		else 0.0
	)
	view.setup(
		barrage_record, effective_move_speed, self, should_use_random_static_placement,
		curve_amplitude, speed_change_cycle, inward_move_direction, layer_change_interval
	)
	if not _terminal_presentation_only and not should_use_random_static_placement:
		# 只让普通移动前景缓和缩放；静止、复读、矛盾和终局实例沿用各自外观。
		view.configure_animated_size(
			normal_foreground_min_scale,
			normal_foreground_max_scale,
			normal_foreground_scale_cycle_seconds
		)
	if _terminal_presentation_only:
		view.apply_terminal_trait_presentation(_terminal_trait_ids, _terminal_trait_colors)
	if not _try_register_normal_capacity_occupant(view, capacity_limit):
		view.free()
		return null
	if has_selected_traits and not _try_register_special_capacity_occupant(view, special_capacity_limit):
		# 特殊登记失败时同步归还刚申请的普通前景名额。
		release_normal_capacity_occupant(view)
		view.free()
		return null
	add_child(view)
	if not speech.local_style_bbcode.is_empty():
		view.set_visual_bbcode(speech.local_style_bbcode)
	var placement_succeeded: bool = false
	if should_use_random_static_placement:
		placement_succeeded = _place_barrage_for_spawn_request(view, true)
	elif should_use_random_interior_placement:
		placement_succeeded = _place_random_interior_barrage(view)
	else:
		placement_succeeded = _place_random_edge_barrage(view, random_spawn_edge)
	if not placement_succeeded:
		# 场上没有可见空位时归还刚申请的容量，普通 Timer 后续继续尝试。
		end_barrage(view.get_instance_id())
		return null
	if should_use_wandering_motion:
		view.configure_wandering_motion(normal_foreground_wandering_direction_change_interval_seconds)
	barrage_generated.emit(view)
	return view


## 特殊账本按弹幕视图身份登记，多个兼容特性仍共用一个名额。
func _try_register_special_capacity_occupant(occupant: Object, capacity_limit: int) -> bool:
	return _special_capacity_ledger.try_register(occupant, capacity_limit)


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
	if not view.configure_contradiction_ease_out(
		_contradiction_config.ease_out_motion_duration_seconds,
		_contradiction_config.ease_out_motion_speed_curve
	):
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
func _place_barrage_for_spawn_request(
		view: BarrageView, random_static_placement: bool, allow_overlap: bool = false
) -> bool:
	if random_static_placement:
		return _place_random_static_barrage(view)
	return _place_new_barrage(view, allow_overlap)


## 按实际视图尺寸和当前区域尺寸均匀抽取完整位于区域内的静止落点。
func _place_random_static_barrage(view: BarrageView) -> bool:
	return _place_random_position_inside_area(view)


## 普通移动话语从当前战斗区域内部均匀抽取出生点。
func _place_random_interior_barrage(view: BarrageView) -> bool:
	return _place_random_position_inside_area(view)


## 静止与内部移动落点共用完整视图边界。
func _place_random_position_inside_area(view: BarrageView) -> bool:
	var max_x: float = size.x - view.size.x
	var max_y: float = size.y - view.size.y
	if max_x < 0.0 or max_y < 0.0:
		return false
	view.position = Vector2(randf_range(0.0, max_x), randf_range(0.0, max_y))
	return true


## 从完整视图仍位于区域内的四条边抽取位置，并让新话语朝区域内部移动。
func _place_random_edge_barrage(view: BarrageView, edge: int) -> bool:
	var max_x: float = size.x - view.size.x
	var max_y: float = size.y - view.size.y
	if max_x < 0.0 or max_y < 0.0:
		return false
	match edge:
		NormalSpawnEdge.TOP:
			view.position = Vector2(randf_range(0.0, max_x), 0.0)
		NormalSpawnEdge.BOTTOM:
			view.position = Vector2(randf_range(0.0, max_x), max_y)
		NormalSpawnEdge.LEFT:
			view.position = Vector2(0.0, randf_range(0.0, max_y))
		NormalSpawnEdge.RIGHT:
			view.position = Vector2(max_x, randf_range(0.0, max_y))
		_:
			return false
	return true


## 为选中的边返回指向战斗区域内部的移动方向。
func _get_inward_direction_for_edge(edge: int) -> Vector2:
	match edge:
		NormalSpawnEdge.TOP:
			return Vector2.DOWN
		NormalSpawnEdge.BOTTOM:
			return Vector2.UP
		NormalSpawnEdge.LEFT:
			return Vector2.RIGHT
		NormalSpawnEdge.RIGHT:
			return Vector2.LEFT
	return Vector2.LEFT


# 在出生边的内向法线周围随机偏转；最大偏角限制在 45 度内以维持明确向内运动。
func _get_random_inward_direction_for_edge(edge: int) -> Vector2:
	return _get_random_straight_direction(_get_inward_direction_for_edge(edge))


## 在给定移动方向周围复用 BG-20 的 Inspector 偏转范围。
func _get_random_straight_direction(base_direction: Vector2) -> Vector2:
	var safe_spread_degrees: float = clampf(random_straight_direction_spread_degrees, 0.0, 45.0)
	var random_offset_radians: float = deg_to_rad(randf_range(-safe_spread_degrees, safe_spread_degrees))
	return base_direction.rotated(random_offset_radians).normalized()


## 普通移动前景保留轮换落点但允许重叠；其余调用维持原空位扫描。
func _place_new_barrage(view: BarrageView, allow_overlap: bool = false) -> bool:
	var start_x: float = maxf(size.x - view.size.x, 0.0)
	var top_margin: float = minf(48.0, maxf(size.y - view.size.y, 0.0))
	var row_step: float = view.size.y + 16.0
	var available_height: float = maxf(size.y - view.size.y - top_margin - 16.0, 0.0)
	var row_count: int = maxi(floori(available_height / row_step) + 1, 1)
	for row_offset: int in range(row_count):
		var row_index: int = (_next_spawn_row + row_offset) % row_count
		var candidate_position: Vector2 = Vector2(start_x, top_margin + float(row_index) * row_step)
		if not allow_overlap:
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
