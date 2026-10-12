# 按真实 PK / Tier 状态选择底板，并独立呈现短促切图动画。
class_name PkBarSkin
extends TextureRect

const BASE_SKIN_KEY: int = 0
const TIER_1_SKIN_KEY: int = 1
const TIER_2_SKIN_KEY: int = 2
const TIER_3_SKIN_KEY: int = 3
const TIER_4_SKIN_KEY: int = 4
const TIER_5_SKIN_KEY: int = 5
const PARADOX_SKIN_KEY: int = 6
const NEGATIVE_04_SKIN_KEY: int = -4
const NEGATIVE_03_SKIN_KEY: int = -3
const NEGATIVE_02_SKIN_KEY: int = -2
const NEGATIVE_01_SKIN_KEY: int = -1

const NEGATIVE_04_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_neg_04.png")
const NEGATIVE_03_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_neg_03.png")
const NEGATIVE_02_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_neg_02.png")
const NEGATIVE_01_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_neg_01.png")
const TIER_1_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_pos_01.png")
const TIER_2_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_pos_02.png")
const TIER_3_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_pos_03.png")
const TIER_4_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_pos_04.png")
const TIER_5_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_pos_05.png")
const PARADOX_TEXTURE: Texture2D = preload("res://assets/ui/combat/pk_bar/pk_bar_pos_06.png")

@export_range(0.0, 1.0, 0.01) var negative_10_percent_end: float = 0.10
@export_range(0.0, 1.0, 0.01) var negative_20_percent_end: float = 0.20
@export_range(0.0, 1.0, 0.01) var negative_30_percent_end: float = 0.30
@export_range(0.0, 1.0, 0.01) var negative_40_percent_end: float = 0.40
@export_range(0.08, 0.7, 0.01) var transition_duration_seconds: float = 0.28
@export_range(0.1, 0.9, 0.01) var texture_swap_progress: float = 0.34
@export_range(1, 4, 1) var flash_pulse_count: int = 2
@export_range(1.0, 2.5, 0.05) var flash_brightness: float = 1.7
@export var flash_hue_tint: Color = Color(0.72, 0.90, 1.25, 1.0)
@export_range(0.15, 0.8, 0.05) var flash_opacity: float = 0.45

var _track: ProgressBar
var _default_background: StyleBox
var _default_fill: StyleBox
var _skin_fill: StyleBoxFlat
var _empty_background: StyleBoxEmpty
var _transition_tween: Tween
var _selected_skin_key: int = BASE_SKIN_KEY


# 作为进度条子层绘制底板；实际填充继续由父 ProgressBar 绘制。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	show_behind_parent = true
	_track = get_parent() as ProgressBar
	if _track == null:
		push_error("PkBarSkin 必须作为 ProgressBar 子节点使用。")
		return
	_default_background = _track.get_theme_stylebox(&"background")
	_default_fill = _track.get_theme_stylebox(&"fill")
	_skin_fill = _default_fill.duplicate() as StyleBoxFlat
	if _skin_fill == null:
		_skin_fill = StyleBoxFlat.new()
		_skin_fill.bg_color = Color(0.15, 0.87, 0.82, 1.0)
	# Keep the real percentage fill, but allow the stage skin colors to be seen beneath it.
	var tint: Color = _skin_fill.bg_color
	tint.a = 0.25
	_skin_fill.bg_color = tint
	_empty_background = StyleBoxEmpty.new()
	_apply_skin_immediately(BASE_SKIN_KEY)


# 读取唯一 PK 和阶段事实；相同底板连续刷新时不会重播闪烁。
func set_display_state(player_pk: float, current_tier: int, paradox_active: bool) -> void:
	var next_skin_key: int = _resolve_skin_key(player_pk, current_tier, paradox_active)
	if next_skin_key == _selected_skin_key:
		return
	_selected_skin_key = next_skin_key
	_cancel_transition()
	if _track == null:
		_apply_skin_immediately(next_skin_key)
		return
	_play_skin_transition(next_skin_key)


# 重开时立即同步目标底板，取消上一场尚未完成的闪烁。
func reset_for_attempt(player_pk: float, current_tier: int, paradox_active: bool) -> void:
	_cancel_transition()
	_selected_skin_key = _resolve_skin_key(player_pk, current_tier, paradox_active)
	_apply_skin_immediately(_selected_skin_key)


# 低于 40% 时按四个十百分点区间覆盖阶段图；Paradox 使用第 6 张正向图。
func _resolve_skin_key(player_pk: float, current_tier: int, paradox_active: bool) -> int:
	var share: float = clampf(player_pk, 0.0, 1.0)
	if share < negative_10_percent_end:
		return NEGATIVE_04_SKIN_KEY
	if share < negative_20_percent_end:
		return NEGATIVE_03_SKIN_KEY
	if share < negative_30_percent_end:
		return NEGATIVE_02_SKIN_KEY
	if share < negative_40_percent_end:
		return NEGATIVE_01_SKIN_KEY
	if paradox_active:
		return PARADOX_SKIN_KEY
	return clampi(current_tier, BASE_SKIN_KEY, TIER_5_SKIN_KEY)


# 每个负向区间和普通阶段都从现有 PNG 直接取图；T0 留用原底板。
func _texture_for_skin_key(skin_key: int) -> Texture2D:
	match skin_key:
		NEGATIVE_04_SKIN_KEY:
			return NEGATIVE_04_TEXTURE
		NEGATIVE_03_SKIN_KEY:
			return NEGATIVE_03_TEXTURE
		NEGATIVE_02_SKIN_KEY:
			return NEGATIVE_02_TEXTURE
		NEGATIVE_01_SKIN_KEY:
			return NEGATIVE_01_TEXTURE
		TIER_1_SKIN_KEY:
			return TIER_1_TEXTURE
		TIER_2_SKIN_KEY:
			return TIER_2_TEXTURE
		TIER_3_SKIN_KEY:
			return TIER_3_TEXTURE
		TIER_4_SKIN_KEY:
			return TIER_4_TEXTURE
		TIER_5_SKIN_KEY:
			return TIER_5_TEXTURE
		PARADOX_SKIN_KEY:
			return PARADOX_TEXTURE
	return null


# 底板变化播放短促闪烁、偏色和可调时点换图。
func _play_skin_transition(next_skin_key: int) -> void:
	var duration: float = maxf(transition_duration_seconds, 0.08)
	var pulse_count: int = maxi(flash_pulse_count, 1)
	var swap_progress: float = clampf(texture_swap_progress, 0.05, 0.95)
	var pulse_step: float = duration * swap_progress / float(pulse_count * 2)
	var dimmed_tint: Color = Color(
		flash_hue_tint.r,
		flash_hue_tint.g,
		flash_hue_tint.b,
		clampf(flash_opacity, 0.0, 1.0)
	)
	var bright_flash: Color = Color(flash_brightness, flash_brightness, flash_brightness, 1.0)
	_transition_tween = create_tween()
	_transition_tween.set_parallel(false)
	_transition_tween.set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	for _pulse: int in range(pulse_count):
		_transition_tween.tween_property(self, "modulate", bright_flash, pulse_step)
		_transition_tween.tween_property(self, "modulate", dimmed_tint, pulse_step)
	_transition_tween.tween_callback(_apply_skin.bind(next_skin_key))
	var restore_duration: float = duration * (1.0 - swap_progress)
	_transition_tween.tween_property(self, "modulate", bright_flash, restore_duration * 0.18)
	_transition_tween.tween_property(self, "modulate", Color.WHITE, restore_duration * 0.82)
	_transition_tween.tween_callback(_finish_transition.bind(_transition_tween))
# 替换底板贴图时只清空 ProgressBar 背景 StyleBox，实际填充比例仍由原 Range 绘制。
func _apply_skin(skin_key: int) -> void:
	texture = _texture_for_skin_key(skin_key)
	visible = texture != null
	if _track == null:
		return
	if visible:
		_track.add_theme_stylebox_override(&"background", _empty_background)
		_track.add_theme_stylebox_override(&"fill", _skin_fill)
	else:
		if _default_background != null:
			_track.add_theme_stylebox_override(&"background", _default_background)
		if _default_fill != null:
			_track.add_theme_stylebox_override(&"fill", _default_fill)


# 首帧和重开直接落到确定的当前贴图，不保留过场色或残留 Tween。
func _apply_skin_immediately(skin_key: int) -> void:
	modulate = Color.WHITE
	_apply_skin(skin_key)


# 只取消底板局部 Tween；其他进度条子层不受本动画影响。
func _cancel_transition() -> void:
	if _transition_tween != null:
		_transition_tween.kill()
		_transition_tween = null
	modulate = Color.WHITE


# 当前切换结束后重置调色，让后续底板从标准颜色开始。
func _finish_transition(active_tween: Tween) -> void:
	if active_tween != _transition_tween:
		return
	_transition_tween = null
	modulate = Color.WHITE
