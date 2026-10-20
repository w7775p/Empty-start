extends Control

# 将青蛙全组在 1920×1080 设计画布中上移 15 个逻辑像素。
const FROG_ASSEMBLY_RISE_PX: float = 15.0

signal dance_finished

const IDLE_LAYERS: Array[Dictionary] = [
	{"role": "body", "texture": preload("res://assets/characters/opponents/frog/slices/idle/01_body.png"), "offset": Vector2(23.0, 0.0)},
	{"role": "bubbles", "texture": preload("res://assets/characters/opponents/frog/slices/idle/02_bubbles.png"), "offset": Vector2(0.0, 102.0)},
	{"role": "chain", "texture": preload("res://assets/characters/opponents/frog/slices/idle/03_chain.png"), "offset": Vector2(155.0, 308.0)},
	{"role": "side", "texture": preload("res://assets/characters/opponents/frog/slices/idle/04_side_detail.png"), "offset": Vector2(39.0, 189.0)},
	{"role": "apron", "texture": preload("res://assets/characters/opponents/frog/slices/idle/05_apron.png"), "offset": Vector2(169.0, 497.0)},
]
const TIER_01_LAYERS: Array[Dictionary] = [
	{"role": "body", "texture": preload("res://assets/characters/opponents/frog/slices/tier_01/01_body.png"), "offset": Vector2.ZERO},
	{"role": "chain", "texture": preload("res://assets/characters/opponents/frog/slices/tier_01/02_chain.png"), "offset": Vector2(174.0, 104.0)},
	{"role": "cockroach", "texture": preload("res://assets/characters/opponents/frog/slices/tier_01/03_cockroach.png"), "offset": Vector2(322.0, 37.0)},
]
const TIER_02_LAYERS: Array[Dictionary] = [
	{"role": "motion_lines", "texture": preload("res://assets/characters/opponents/frog/slices/tier_02/04_motion_lines.png"), "offset": Vector2.ZERO},
	{"role": "body", "texture": preload("res://assets/characters/opponents/frog/slices/tier_02/01_body.png"), "offset": Vector2(0.0, 100.0)},
	# 分件缺原始画布原点，按Tier1/3链层和Tier2完整图定位到同一胸前区域。
	{"role": "chain", "texture": preload("res://assets/characters/opponents/frog/slices/tier_02/02_chain.png"), "offset": Vector2(177.0, 203.0)},
	{"role": "cockroach", "texture": preload("res://assets/characters/opponents/frog/slices/tier_02/03_cockroach.png"), "offset": Vector2(323.0, 155.0)},
]
const TIER_03_LAYERS: Array[Dictionary] = [
	{"role": "body", "texture": preload("res://assets/characters/opponents/frog/slices/tier_03/01_body.png"), "offset": Vector2(0.0, 146.0)},
	{"role": "chain", "texture": preload("res://assets/characters/opponents/frog/slices/tier_03/02_chain.png"), "offset": Vector2(174.0, 249.0)},
	{"role": "spirit_fx", "texture": preload("res://assets/characters/opponents/frog/slices/tier_03/04_spirit_fx.png"), "offset": Vector2(164.0, 0.0)},
	{"role": "cockroach", "texture": preload("res://assets/characters/opponents/frog/slices/tier_03/03_cockroach.png"), "offset": Vector2(322.0, 183.0)},
]
const DEFEAT_LAYERS: Array[Dictionary] = [
	{"role": "head", "texture": preload("res://assets/characters/opponents/frog/slices/defeat/01_head.png"), "offset": Vector2.ZERO},
	{"role": "shadow", "texture": preload("res://assets/characters/opponents/frog/slices/defeat/02_cockroach_shadow.png"), "offset": Vector2(238.0, 458.0)},
	{"role": "cockroach", "texture": preload("res://assets/characters/opponents/frog/slices/defeat/03_cockroach.png"), "offset": Vector2(196.0, 130.0)},
]

var _reference_rect: TextureRect
var _motion_root: Control
var _fit_callback: Callable
var _internal_reference_change: bool = false
var _references: Dictionary = {}
var _original_self_modulate: Color = Color.WHITE
var _active_pose: StringName = &""
var _active_texture: Texture2D
var _active_tier: int = 0
var _enabled: bool = false
var _fit_scale: float = 1.0
var _layers: Array[TextureRect] = []
var _layer_by_role: Dictionary = {}
var _layer_specs: Dictionary = {}
var _base_by_role: Dictionary = {}
var _struggle_tween: Tween
var _dance_tween: Tween
var _dance_return_texture: Texture2D
var _dance_return_tier: int = 0
var _struggle_strength: float = 0.0


# 隐藏整图但沿用其尺寸、PA-23锚点和PA-14外层变换；分件按原画布偏移组装。
func bind_reference_rect(reference_rect: TextureRect, fit_callback: Callable) -> void:
	_reference_rect = reference_rect
	_fit_callback = fit_callback
	_original_self_modulate = reference_rect.self_modulate
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# 缩放仍读取完整Tier资源，分件只提供绘制层和运动。
func configure_references(
	idle: Texture2D,
	tier_01: Texture2D,
	tier_02: Texture2D,
	tier_03: Texture2D,
	defeat: Texture2D
) -> void:
	_references = {
		"idle": idle,
		"tier_01": tier_01,
		"tier_02": tier_02,
		"tier_03": tier_03,
		"defeat": defeat,
	}
	if _enabled and _reference_rect != null:
		sync_reference(_reference_rect.texture, _active_tier)


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	visible = enabled
	if not enabled:
		_cancel_dance(true)
		_stop_struggle()
		_clear_layers()
		_active_pose = &""
		_active_texture = null
		if _reference_rect != null:
			_reference_rect.self_modulate = _original_self_modulate
		return
	if _reference_rect != null:
		sync_reference(_reference_rect.texture, _active_tier)

# 按完整立绘资源选择分件组；未知资源仍显示原整图作为安全回退。
func sync_reference(texture: Texture2D, tier: int) -> bool:
	if _reference_rect == null or texture == null:
		return false
	if _reference_rect.size.x > 0.0:
		_fit_scale = _reference_rect.size.x / float(texture.get_size().x)
	if _internal_reference_change:
		return true
	if not _enabled:
		return false
	if _dance_tween != null:
		_cancel_dance(false)
	var pose: StringName = _pose_for_reference(texture)
	if pose == &"" or _layers_for_pose(pose).is_empty():
		_stop_struggle()
		_clear_layers()
		_active_pose = &""
		_active_texture = null
		_reference_rect.self_modulate = _original_self_modulate
		return false
	if texture != _active_texture or pose != _active_pose:
		_build_pose(pose, texture, tier)
	else:
		_active_tier = tier
		_refresh_layout()
		_update_struggle_strength(tier)
	return true

# 对手和场景协调方可调用此公开入口；每次只播放一次独立短舞。
func play_cockroach_dance() -> bool:
	if not _enabled or _dance_tween != null or _active_pose == &"defeat":
		return false
	var defeat_texture: Texture2D = _references.get("defeat") as Texture2D
	if defeat_texture == null or _active_texture == null or _reference_rect == null:
		return false
	_dance_return_texture = _reference_rect.texture
	_dance_return_tier = _active_tier
	_stop_struggle()
	# 临时切到正式败北画布，让蟑螂、影子和身体沿用完整图的相对位置与PA-23锚点。
	_internal_reference_change = true
	_reference_rect.texture = defeat_texture
	_fit_callback.call()
	_internal_reference_change = false
	if not _build_pose(&"defeat", defeat_texture, _dance_return_tier):
		_restore_after_dance()
		return false
	var cockroach: TextureRect = _layer_by_role.get("cockroach") as TextureRect
	var shadow: TextureRect = _layer_by_role.get("shadow") as TextureRect
	if cockroach == null or shadow == null or _motion_root == null:
		_restore_after_dance()
		return false
	var roach_base: Dictionary = _base_by_role.get("cockroach", {})
	var shadow_base: Dictionary = _base_by_role.get("shadow", {})
	var roach_position: Vector2 = roach_base.get("position", cockroach.position)
	var roach_rotation: float = roach_base.get("rotation", cockroach.rotation)
	var roach_scale: Vector2 = roach_base.get("scale", cockroach.scale)
	var shadow_scale: Vector2 = shadow_base.get("scale", shadow.scale)
	var shadow_modulate: Color = shadow_base.get("modulate", shadow.modulate)
	var hop_height: float = 34.0 * _fit_scale
	var side_step: float = 8.0 * _fit_scale

	_dance_tween = create_tween().set_trans(Tween.TRANS_CUBIC)
	for beat: int in range(3):
		var direction: float = -1.0 if beat % 2 == 0 else 1.0
		_dance_tween.tween_property(
			cockroach, "position", roach_position + Vector2(direction * side_step, -hop_height), 0.18
		).set_ease(Tween.EASE_OUT)
		_dance_tween.parallel().tween_property(
			cockroach, "rotation", roach_rotation + deg_to_rad(14.0 * direction), 0.18
		)
		_dance_tween.parallel().tween_property(cockroach, "scale", roach_scale * Vector2(1.06, 0.94), 0.18)
		_dance_tween.parallel().tween_property(shadow, "scale", shadow_scale * Vector2(0.72, 0.48), 0.18)
		_dance_tween.parallel().tween_property(shadow, "modulate", Color(1.0, 1.0, 1.0, 0.26), 0.18)
		_dance_tween.parallel().tween_property(_motion_root, "rotation", deg_to_rad(1.0 * direction), 0.18)
		_dance_tween.tween_interval(0.04)
		_dance_tween.tween_property(
			cockroach, "position", roach_position + Vector2(-direction * side_step * 0.35, 0.0), 0.13
		).set_ease(Tween.EASE_IN)
		_dance_tween.parallel().tween_property(
			cockroach, "rotation", roach_rotation - deg_to_rad(8.0 * direction), 0.13
		)
		_dance_tween.parallel().tween_property(cockroach, "scale", roach_scale * Vector2(0.96, 1.04), 0.13)
		_dance_tween.parallel().tween_property(shadow, "scale", shadow_scale * Vector2(0.96, 0.70), 0.13)
		_dance_tween.parallel().tween_property(shadow, "modulate", Color(1.0, 1.0, 1.0, 0.40), 0.13)
		_dance_tween.parallel().tween_property(_motion_root, "rotation", deg_to_rad(-0.6 * direction), 0.13)
		_dance_tween.tween_property(cockroach, "position", roach_position, 0.10)
		_dance_tween.parallel().tween_property(cockroach, "rotation", roach_rotation, 0.10)
		_dance_tween.parallel().tween_property(cockroach, "scale", roach_scale, 0.10)
		_dance_tween.parallel().tween_property(shadow, "scale", shadow_scale, 0.10)
		_dance_tween.parallel().tween_property(shadow, "modulate", shadow_modulate, 0.10)
		_dance_tween.parallel().tween_property(_motion_root, "rotation", 0.0, 0.10)
	_dance_tween.tween_callback(_finish_dance)
	return true

# 每次尺寸变化重新按完整画布比例定位切件，底层锚点仍由整图槽持有。
func _refresh_layout() -> void:
	if _reference_rect == null or _active_texture == null or _motion_root == null or _reference_rect.size.x <= 0.0:
		return
	_fit_scale = _reference_rect.size.x / float(_active_texture.get_size().x)
	_motion_root.position = Vector2(0.0, -FROG_ASSEMBLY_RISE_PX)
	_motion_root.size = _reference_rect.size
	_motion_root.pivot_offset = _reference_rect.pivot_offset
	_motion_root.rotation = 0.0
	_motion_root.scale = Vector2.ONE
	for layer: TextureRect in _layers:
		var spec: Dictionary = _layer_specs.get(layer.get_instance_id(), {})
		var texture: Texture2D = spec.get("texture") as Texture2D
		if texture == null:
			continue
		var offset: Vector2 = spec.get("offset", Vector2.ZERO)
		layer.position = offset * _fit_scale
		layer.size = Vector2(texture.get_size()) * _fit_scale
		layer.pivot_offset = _pivot_for(texture, _fit_scale, str(spec.get("role", "")))
		_store_base_transform(layer, str(spec.get("role", "")))

# 清理所有局部变换，避免切换Tier或离开场景后残留挣扎/舞蹈姿态。
func reset_visual_state() -> void:
	_cancel_dance(true)
	_stop_struggle()
	_restore_layer_transforms()


func _exit_tree() -> void:
	_cancel_dance(false)
	_stop_struggle()


# 根据完整贴图引用选择对应拆件姿态。
func _pose_for_reference(texture: Texture2D) -> StringName:
	if texture == null:
		return &""
	if texture == _references.get("idle"):
		return &"idle"
	if texture == _references.get("tier_01"):
		return &"tier_01"
	if texture == _references.get("tier_02"):
		return &"tier_02"
	if texture == _references.get("tier_03"):
		return &"tier_03"
	if texture == _references.get("defeat"):
		return &"defeat"
	return &""


# 创建当前姿态所有分件，绘制顺序遵循文件编号对应的原图层顺序。
func _build_pose(pose: StringName, texture: Texture2D, tier: int) -> bool:
	_stop_struggle()
	_clear_layers()
	_active_pose = pose
	_active_texture = texture
	_active_tier = tier
	_motion_root = Control.new()
	_motion_root.name = "FrogBodyMotionRoot"
	_motion_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_motion_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	add_child(_motion_root)
	for spec: Dictionary in _layers_for_pose(pose):
		var layer_texture: Texture2D = spec.get("texture") as Texture2D
		if layer_texture == null:
			continue
		var layer := TextureRect.new()
		layer.name = "FrogSlice_%s" % str(spec.get("role", "Layer"))
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_SCALE
		layer.texture = layer_texture
		_motion_root.add_child(layer)
		_layers.append(layer)
		_layer_by_role[str(spec.get("role", ""))] = layer
		_layer_specs[layer.get_instance_id()] = spec
	_refresh_layout()
	_reference_rect.self_modulate = Color(_original_self_modulate.r, _original_self_modulate.g, _original_self_modulate.b, 0.0)
	_update_struggle_strength(tier)
	return not _layers.is_empty()

func _layers_for_pose(pose: StringName) -> Array[Dictionary]:
	match pose:
		&"idle":
			return IDLE_LAYERS
		&"tier_01":
			return TIER_01_LAYERS
		&"tier_02":
			return TIER_02_LAYERS
		&"tier_03":
			return TIER_03_LAYERS
		&"defeat":
			return DEFEAT_LAYERS
		_:
			return []


# 阶段压力只改变分件的局部动作，强度随正式Tier升高，不覆盖战斗状态。
func _update_struggle_strength(tier: int) -> void:
	var target: float = _strength_for_tier(tier)
	if _active_pose == &"defeat":
		target = 0.0
	if is_equal_approx(target, _struggle_strength):
		if target <= 0.0 and _struggle_tween == null:
			return
		if target > 0.0 and _struggle_tween != null:
			return
	_stop_struggle()
	_struggle_strength = target
	if target <= 0.0:
		return
	_struggle_tween = create_tween().set_loops()
	var period: float = lerpf(0.68, 0.48, target)
	_struggle_tween.tween_method(_apply_struggle, 0.0, TAU, period)


func _strength_for_tier(tier: int) -> float:
	match tier:
		3:
			return 0.34
		4:
			return 0.62
		5:
			return 0.88
		6:
			return 1.0
		_:
			return 0.0


# 身体在脚底枢轴上轻压、摆动，链条和蟑螂保留少量惯性延迟。
func _apply_struggle(phase: float) -> void:
	if _motion_root == null:
		return
	var wave: float = sin(phase)
	var compress: float = absf(cos(phase * 2.0)) * _struggle_strength
	_motion_root.position = Vector2(wave * 6.0 * _struggle_strength * _fit_scale, -FROG_ASSEMBLY_RISE_PX)
	_motion_root.rotation = deg_to_rad(2.8 * _struggle_strength) * wave
	_motion_root.scale = Vector2(1.0 + compress * 0.018, 1.0 - compress * 0.035)
	var chain: TextureRect = _layer_by_role.get("chain") as TextureRect
	if chain != null:
		var chain_base: Dictionary = _base_by_role.get("chain", {})
		var base_position: Vector2 = chain_base.get("position", chain.position)
		var base_scale: Vector2 = chain_base.get("scale", Vector2.ONE)
		var base_rotation: float = chain_base.get("rotation", chain.rotation)
		# 链条继承身体整体变换，局部轻微滞后避免悬浮；父级压缩只应用一次。
		var chain_lag: float = sin(phase + 0.35)
		chain.position = base_position + Vector2(
			-chain_lag * 1.8 * _struggle_strength * _fit_scale,
			compress * 0.75 * _fit_scale
		)
		chain.scale = base_scale
		chain.rotation = base_rotation + deg_to_rad(2.4 * _struggle_strength) * sin(phase + 0.55)
	var cockroach: TextureRect = _layer_by_role.get("cockroach") as TextureRect
	if cockroach != null:
		var cockroach_base: Dictionary = _base_by_role.get("cockroach", {})
		cockroach.position = cockroach_base.get("position", cockroach.position) + Vector2(wave * 3.0 * _struggle_strength * _fit_scale, 0.0)

func _finish_dance() -> void:
	_dance_tween = null
	_restore_after_dance()
	dance_finished.emit()


# Dance用的败北切件姿态含有匹配的蟑螂影子和蟑螂图层；结束后回到原Tier。
func _restore_after_dance() -> void:
	var return_texture: Texture2D = _dance_return_texture
	var return_tier: int = _dance_return_tier
	_dance_return_texture = null
	if return_texture == null or _reference_rect == null:
		return
	_internal_reference_change = true
	_reference_rect.texture = return_texture
	_fit_callback.call()
	_internal_reference_change = false
	_build_pose(_pose_for_reference(return_texture), return_texture, return_tier)

func _cancel_dance(restore: bool) -> void:
	if _dance_tween == null:
		return
	_dance_tween.kill()
	_dance_tween = null
	_restore_layer_transforms()
	if restore:
		_restore_after_dance()
	else:
		_dance_return_texture = null


func _stop_struggle() -> void:
	if _struggle_tween != null:
		_struggle_tween.kill()
		_struggle_tween = null
	_restore_layer_transforms()


func _restore_layer_transforms() -> void:
	if _motion_root != null:
		_motion_root.position = Vector2(0.0, -FROG_ASSEMBLY_RISE_PX)
		_motion_root.rotation = 0.0
		_motion_root.scale = Vector2.ONE
	for layer: TextureRect in _layers:
		if not is_instance_valid(layer):
			continue
		var role: String = str(_layer_specs.get(layer.get_instance_id(), {}).get("role", ""))
		var base: Dictionary = _base_by_role.get(role, {})
		if base.is_empty():
			continue
		layer.position = base.get("position", layer.position)
		layer.scale = base.get("scale", Vector2.ONE)
		layer.rotation = base.get("rotation", 0.0)
		layer.modulate = base.get("modulate", Color.WHITE)
	_struggle_strength = 0.0

func _clear_layers() -> void:
	for layer: TextureRect in _layers:
		if is_instance_valid(layer):
			if layer.get_parent() != null:
				layer.get_parent().remove_child(layer)
			layer.queue_free()
	_layers.clear()
	_layer_by_role.clear()
	_layer_specs.clear()
	_base_by_role.clear()
	if _motion_root != null:
		if _motion_root.get_parent() != null:
			_motion_root.get_parent().remove_child(_motion_root)
		_motion_root.queue_free()
		_motion_root = null

func _store_base_transform(layer: TextureRect, role: String) -> void:
	_base_by_role[role] = {
		"position": layer.position,
		"scale": layer.scale,
		"rotation": layer.rotation,
		"modulate": layer.modulate,
	}


func _refresh_layer_base(layer: TextureRect, role: String) -> void:
	_store_base_transform(layer, role)


func _pivot_for(texture: Texture2D, fit_scale: float, role: String) -> Vector2:
	var image: Image = texture.get_image()
	if image == null:
		return Vector2(texture.get_size()) * fit_scale * 0.5
	if image.is_compressed():
		image.decompress()
	var used: Rect2i = image.get_used_rect()
	if not used.has_area():
		return Vector2(texture.get_size()) * fit_scale * 0.5
	if role == "chain":
		return (Vector2(used.position) + Vector2(used.size.x * 0.5, used.size.y * 0.14)) * fit_scale
	if role in ["body", "head", "cockroach"]:
		return (Vector2(used.position) + Vector2(used.size.x * 0.5, used.size.y)) * fit_scale
	return (Vector2(used.position) + Vector2(used.size) * 0.5) * fit_scale
