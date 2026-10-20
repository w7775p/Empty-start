class_name OpponentTierPortrait
extends Control

const TierFx = preload("res://systems/presentation/opponent_tier_fx.gd")
const FrogSlicedPortraitScript = preload("res://systems/presentation/frog_sliced_portrait.gd")

signal flip_finished(tier: int)
signal frog_cockroach_dance_finished

@export var flip_seconds: float = 0.32
@export_range(0.02, 0.5) var narrow_scale: float = 0.08
@export var rebound_scale: float = 1.07
@export var kiwi_flip_seconds: float = 0.42
@export var kiwi_burst_scale: float = 1.09
@export var kiwi_shake_pixels: float = 7.0
@export_range(0.7, 1.0, 0.01) var alien_tier_scale: float = 0.90
# Y=1 对齐可见脚底到直播框的安全下沿；是否裁切由 fit_current_texture() 负责。
# 旧版 0.94 在 432px 框中人为留下约 26px 悬空间隙。
@export var visible_anchor_ratio: Vector2 = Vector2(0.5, 1.0)
@export_range(0.0, 24.0, 1.0) var visible_edge_guard_px: float = 5.0
# 列巴坐姿参考：增大 T1/T2 的 fox_idle.png，让头部略低、身体铺满直播镜头。
# 两档使用同一贴图，采用同一构图，避免换档瞬间跳动。
@export_range(1.0, 1.5, 0.01) var fox_idle_zoom: float = 1.08
@export_range(0.0, 0.25, 0.01) var fox_idle_top_ratio: float = 0.10

var current_tier: int = 0
var fx: OpponentTierFx
var _portrait: TextureRect
var _idle: Texture2D
var _tier_01: Texture2D
var _tier_02: Texture2D
var _tier_03: Texture2D
var _flip_tween: Tween
var _shudder_tween: Tween
var _impact_tween: Tween
var _pending_texture: Texture2D
var _character_id: String = ""
var _impact_backdrop: Control
var _display_scale: float = 1.0
var _pending_display_scale: float = 1.0
var _visible_bounds: Dictionary = {}
var _maximum_visible_size: Vector2 = Vector2.ONE
var _result_textures: Array[Texture2D] = []
var _result_defeat_texture: Texture2D
var _frog_sliced_portrait: Control


# 保留 PA-14 的 Idle 层级给射击/切图使用；循环呼吸动画已停用。
func attach_portrait(portrait: TextureRect) -> void:
	var slot: Control = portrait.get_parent() as Control
	var index: int = portrait.get_index()
	name = "OpponentTierPortrait"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 坐姿放大后由直播槽本身裁切；避免肢体溢出到下方评论区域。
	clip_contents = true
	slot.add_child(self)
	slot.move_child(self, index)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait = portrait
	portrait.reparent(self, false)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait.pivot_offset = portrait.size * 0.5
	_impact_backdrop = Control.new()
	_impact_backdrop.name = "TierImpactBackdrop"
	_impact_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_impact_backdrop)
	move_child(_impact_backdrop, 0)
	_impact_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx = TierFx.new()
	fx.name = "TierFx"
	add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.bind_backdrop(_impact_backdrop)
	resized.connect(_refresh_pivot)
	_refresh_pivot()


# 纹理由关卡/集成方显式提供；缺图时保留 idle 占位，不猜测文件名。
func configure_textures(idle: Texture2D, tier_01: Texture2D, tier_02: Texture2D, tier_03: Texture2D) -> void:
	_idle = idle
	_tier_01 = tier_01
	_tier_02 = tier_02
	_tier_03 = tier_03
	_rebuild_visible_bounds()
	_configure_frog_sliced_portrait()
	reset_for_tier(current_tier)


# 待机、阶段、过渡和击败共用同一尺寸基准，切图不随透明画布重新居中。
func configure_result_bounds(transition: Texture2D, defeat: Texture2D) -> void:
	_result_defeat_texture = defeat
	_result_textures.clear()
	for texture: Texture2D in [transition, defeat]:
		if texture != null:
			_result_textures.append(texture)
	_rebuild_visible_bounds()
	_configure_frog_sliced_portrait()
	fit_current_texture()


# 测量原 Texture 可见 alpha 边界，不修改 PNG，也不依赖原文件存在于导出包。
func _rebuild_visible_bounds() -> void:
	_visible_bounds.clear()
	_maximum_visible_size = Vector2.ONE
	var textures: Array[Texture2D] = [_idle, _tier_01, _tier_02, _tier_03]
	textures.append_array(_result_textures)
	for texture: Texture2D in textures:
		if texture == null:
			continue
		var bounds := Rect2(Vector2.ZERO, texture.get_size())
		var pixels: Image = texture.get_image()
		if pixels != null:
			if pixels.is_compressed():
				pixels.decompress()
			var used: Rect2i = pixels.get_used_rect()
			if used.has_area():
				bounds = Rect2(used)
		_visible_bounds[texture] = bounds
		_maximum_visible_size = _maximum_visible_size.max(bounds.size)


# 维持单张原图等比适配。可见脚底落到安全下沿，较高姿态向上移动。
# 考虑缩放动画的实际 scale.y，修正原来按未缩放边界定位造成的悬空。
func fit_current_texture() -> void:
	if _portrait == null or _portrait.texture == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var texture: Texture2D = _portrait.texture
	var bounds: Rect2 = _visible_bounds.get(texture, Rect2(Vector2.ZERO, texture.get_size()))
	var guard: float = minf(visible_edge_guard_px, minf(size.x, size.y) * 0.1)
	var available: Vector2 = (size - Vector2.ONE * guard * 2.0).max(Vector2.ONE)
	# 每张原图按自己的完整画布比例适配镜头，恢复 PA-14 的 TextureRect 尺寸逻辑。
	# _maximum_visible_size 只作图像测量参考，不再缩小较短/较窄的阶段姿态。
	var raw_size: Vector2 = texture.get_size().max(Vector2.ONE)
	var fit_scale: float = minf(available.x / raw_size.x, available.y / raw_size.y)
	var fox_seated: bool = _character_id == "fox" and texture == _idle and current_tier in [1, 2]
	if fox_seated:
		fit_scale *= fox_idle_zoom
	var ground_ratio: Vector2 = visible_anchor_ratio.clamp(Vector2.ZERO, Vector2.ONE)
	var display_height: float = bounds.size.y * fit_scale * absf(_portrait.scale.y)
	var visible_top: float = clampf(
		size.y * ground_ratio.y - guard - display_height,
		guard,
		maxf(guard, size.y - guard - display_height)
	)
	# 列巴坐姿：完整显示头部，窗口下沿裁掉坐姿多余部分。
	if fox_seated:
		visible_top = size.y * fox_idle_top_ratio
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.size = texture.get_size() * fit_scale
	# 翻牌仍绕可见身体中心旋转；位置补偿 pivot 与 scale 对脚底的影响。
	_portrait.pivot_offset = (bounds.position + bounds.size * 0.5) * fit_scale
	_portrait.position = Vector2(
		size.x * ground_ratio.x - _portrait.pivot_offset.x,
		visible_top - _portrait.pivot_offset.y
			- (bounds.position.y * fit_scale - _portrait.pivot_offset.y) * _portrait.scale.y
	)
	if _frog_sliced_portrait != null and _character_id == "frog":
		_frog_sliced_portrait.call("sync_reference", texture, current_tier)

# 三名对手共用白色冲击条；Kiwi 的翻图节奏仍单独处理。
func configure_character(character_id: String) -> void:
	_character_id = character_id
	_configure_frog_sliced_portrait()
	fx.configure_character(character_id)
	_display_scale = _scale_for_texture(_portrait.texture)
	_portrait.scale = Vector2.ONE * _display_scale
	fit_current_texture()


# 固定阶段贴图的共同锚点，再沿用原翻面与汗滴动作。
func show_tier(tier: int) -> void:
	var target_tier: int = clampi(tier, 0, 6)
	var target: Texture2D = _texture_for_tier(target_tier)
	var target_display_scale: float = _scale_for_texture(target)
	if target_tier == current_tier and _flip_tween == null:
		return
	current_tier = target_tier
	fx.set_sweat(target_tier == 2)
	fx.clear_impact()
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null
	if _shudder_tween != null:
		_shudder_tween.kill()
		_shudder_tween = null
	if _impact_tween != null:
		_impact_tween.kill()
		_impact_tween = null
	position = Vector2.ZERO
	_display_scale = _scale_for_texture(_portrait.texture)
	_portrait.scale = Vector2.ONE * _display_scale
	if _portrait.texture == target or _portrait.texture == null or target == null:
		_portrait.texture = target
		_display_scale = target_display_scale
		_portrait.scale = Vector2.ONE * _display_scale
		fit_current_texture()
		if target_tier == 1 or target_tier == 2:
			_play_shudder()
		return
	_pending_texture = target
	_pending_display_scale = target_display_scale
	if _character_id == "kiwi":
		_play_kiwi_flip()
		return
	var half: float = maxf(flip_seconds, 0.08) * 0.5
	_flip_tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	_flip_tween.tween_method(_set_horizontal_scale, 1.0, narrow_scale, half).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(_swap_at_edge)
	_flip_tween.tween_method(_set_horizontal_scale, narrow_scale, rebound_scale, half * 0.72).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_method(_set_horizontal_scale, rebound_scale, 1.0, half * 0.28).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(_finish_flip)


# Paradox 沿用 T5，重开/断线取消残留动画。
func reset_for_tier(tier: int = 0) -> void:
	if _flip_tween != null:
		_flip_tween.kill()
		_flip_tween = null
	if _shudder_tween != null:
		_shudder_tween.kill()
		_shudder_tween = null
	if _impact_tween != null:
		_impact_tween.kill()
		_impact_tween = null
	position = Vector2.ZERO
	current_tier = clampi(tier, 0, 6)
	_pending_texture = null
	_portrait.texture = _texture_for_tier(current_tier)
	_display_scale = _scale_for_texture(_portrait.texture)
	_pending_display_scale = _display_scale
	_portrait.scale = Vector2.ONE * _display_scale
	fit_current_texture()
	fx.reset_fx()
	fx.set_sweat(current_tier == 2)


func _texture_for_tier(tier: int) -> Texture2D:
	match tier:
		3:
			return _tier_01 if _tier_01 != null else _idle
		4:
			return _tier_02 if _tier_02 != null else _idle
		5, 6:
			return _tier_03 if _tier_03 != null else _idle
		_:
			return _idle


func _set_horizontal_scale(value: float) -> void:
	_portrait.scale = Vector2(value, 1.0) * _display_scale


# Kiwi 在翻面后快速放大、定格、回弹；时长与幅度单独调参。
func _play_kiwi_flip() -> void:
	var compress: float = maxf(kiwi_flip_seconds, 0.32) * 0.29
	_flip_tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	_flip_tween.tween_method(_set_horizontal_scale, 1.0, narrow_scale, compress).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(_swap_at_edge)
	_flip_tween.tween_method(_set_kiwi_scale, narrow_scale, kiwi_burst_scale, 0.105).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_interval(0.06)
	_flip_tween.tween_method(_set_kiwi_scale, kiwi_burst_scale, 0.98, 0.085).set_ease(Tween.EASE_IN_OUT)
	_flip_tween.tween_method(_set_kiwi_scale, 0.98, 1.0, 0.05).set_ease(Tween.EASE_OUT)
	_flip_tween.tween_callback(_finish_flip)


# Kiwi 回弹也保留角色原有缩放，避免换图时绕另一套基点变形。
func _set_kiwi_scale(value: float) -> void:
	_portrait.scale = Vector2(value, lerpf(1.0, value, 0.78)) * _display_scale


# 位移用独立 Tween，反复改档时统一取消并归零。
func _play_kiwi_shake() -> void:
	var amount: float = kiwi_shake_pixels
	_impact_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_impact_tween.tween_property(self, "position", Vector2(amount, -amount * 0.35), 0.025)
	_impact_tween.tween_property(self, "position", Vector2(-amount * 0.6, amount * 0.3), 0.028)
	_impact_tween.tween_property(self, "position", Vector2(amount * 0.28, -amount * 0.1), 0.032)
	_impact_tween.tween_property(self, "position", Vector2.ZERO, 0.055)


func _play_shudder() -> void:
	if _shudder_tween != null:
		_shudder_tween.kill()
	position = Vector2.ZERO
	_shudder_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_shudder_tween.tween_property(self, "position", Vector2(5.0, -2.0), 0.045)
	_shudder_tween.tween_property(self, "position", Vector2(-3.0, 1.0), 0.055)
	_shudder_tween.tween_property(self, "position", Vector2.ZERO, 0.07)


# 窄边换图后重新排版，当前 Tween 继续拥有缩放动画。
func _swap_at_edge() -> void:
	_portrait.texture = _pending_texture
	fit_current_texture()
	_display_scale = _pending_display_scale
	fx.play_impact()
	if _character_id == "kiwi":
		_play_kiwi_shake()


func _finish_flip() -> void:
	_flip_tween = null
	_pending_texture = null
	_portrait.scale = Vector2.ONE * _display_scale
	flip_finished.emit(current_tier)


# 父框变化时重算同一可见锚点，不按新 PNG 画布另选中心。
func _refresh_pivot() -> void:
	fit_current_texture()


# ALIEN 的阶段图比 idle 横向扩张更明显，只缩小阶段图显示，不改原始 PNG 或卡片尺寸。
func _scale_for_texture(texture: Texture2D) -> float:
	if _character_id == "alien" and texture != null and texture != _idle:
		if texture == _tier_01 or texture == _tier_02 or texture == _tier_03:
			return alien_tier_scale
	return 1.0

# 青蛙分件只在真实 frog 资源组启用；整图继续作为PA-23锚点与回退来源。
func _configure_frog_sliced_portrait() -> void:
	if _portrait == null:
		return
	if _character_id != "frog" or not _is_frog_portrait_texture(_idle):
		if _frog_sliced_portrait != null:
			_frog_sliced_portrait.call("set_enabled", false)
		return
	if _frog_sliced_portrait == null:
		_frog_sliced_portrait = FrogSlicedPortraitScript.new() as Control
		_frog_sliced_portrait.name = "FrogSlicedPortrait"
		_portrait.add_child(_frog_sliced_portrait)
		_frog_sliced_portrait.call("bind_reference_rect", _portrait, Callable(self, "fit_current_texture"))
		_frog_sliced_portrait.connect(
			"dance_finished", Callable(self, "_on_frog_cockroach_dance_finished")
		)
	_frog_sliced_portrait.call(
		"configure_references", _idle, _tier_01, _tier_02, _tier_03, _result_defeat_texture
	)
	_frog_sliced_portrait.call("set_enabled", true)
	_frog_sliced_portrait.call("sync_reference", _portrait.texture, current_tier)


# 只用稳定资源路径识别已装配的Frog组，防止切换角色间隙误绘制分件。
func _is_frog_portrait_texture(texture: Texture2D) -> bool:
	return texture != null and texture.resource_path.contains("/characters/opponents/frog/")


# 供场景协调方绑定既有表现时机；不创建战斗技能或运行时战斗状态。
func play_frog_cockroach_dance() -> bool:
	if _character_id != "frog" or _frog_sliced_portrait == null:
		return false
	return bool(_frog_sliced_portrait.call("play_cockroach_dance"))


func _on_frog_cockroach_dance_finished() -> void:
	frog_cockroach_dance_finished.emit()
