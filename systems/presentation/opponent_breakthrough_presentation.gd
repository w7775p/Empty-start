## 对手真击破与未击破后的直播间表现；所有目标与素材由场景协调方注入。
class_name OpponentBreakthroughPresentation
extends Control

signal defeat_animation_finished(character_id: StringName)
signal unbroken_offline_finished

enum PresentationMode { IDLE, ALIEN_MELT, FOX_PETALS, KIWI_WOBBLE, OFFLINE, OFFLINE_DONE }

const WARP_SHADER: Shader = preload("res://systems/presentation/opponent_portrait_deform.gdshader")

@export_group("外星人融化")
@export_range(0.05, 1.0, 0.05) var alien_relax_seconds: float = 0.28
@export_range(0.1, 1.5, 0.05) var alien_melt_seconds: float = 0.72
@export_range(0.1, 1.0, 0.05) var alien_collapse_seconds: float = 0.34
@export_range(0.0, 80.0, 1.0) var alien_drop_pixels: float = 34.0
@export_range(0.0, 1.0, 0.01) var alien_warp_strength: float = 0.78

@export_group("狐狸花瓣雨")
@export_range(12, 72, 1) var fox_petal_count: int = 42
@export_range(16.0, 64.0, 1.0) var fox_petal_size_min: float = 22.0
@export_range(16.0, 80.0, 1.0) var fox_petal_size_max: float = 40.0
@export_range(0.5, 2.5, 0.05) var fox_fall_seconds_min: float = 1.05
@export_range(0.5, 3.0, 0.05) var fox_fall_seconds_max: float = 1.85
@export_range(0.0, 1.5, 0.05) var fox_spawn_stagger_seconds: float = 0.62
@export_range(0.1, 1.5, 0.05) var fox_defeat_reveal_seconds: float = 0.78
@export_range(0.0, 180.0, 1.0) var fox_drift_pixels: float = 86.0

@export_group("Kiwi 整图乱舞")
@export_range(3, 10, 1) var kiwi_wobble_cycles: int = 7
@export_range(1.0, 20.0, 0.5) var kiwi_rotation_degrees: float = 9.0
@export_range(1.0, 36.0, 1.0) var kiwi_shake_pixels: float = 18.0
@export_range(0.08, 0.5, 0.01) var kiwi_cycle_seconds: float = 0.23
@export_range(0.1, 1.0, 0.05) var kiwi_wobble_strength: float = 0.86
@export_range(0.0, 80.0, 1.0) var kiwi_speed_line_length: float = 40.0

@export_group("未击破后离线")
@export var unbroken_result_text: String = "未击破"
@export var offline_text: String = "主播已离线"
@export_range(0.1, 1.5, 0.05) var unbroken_hold_seconds: float = 0.42
@export_range(0.2, 1.5, 0.05) var offline_transition_seconds: float = 0.76
@export_range(0.3, 1.0, 0.01) var offline_dark_alpha: float = 0.88
@export_range(0.0, 0.35, 0.01) var offline_flicker_strength: float = 0.14

var _portrait: TextureRect
var _motion_layer: StreamerPortraitMotion
var _tier_three_texture: Texture2D
var _defeat_transition_texture: Texture2D
var _defeat_texture: Texture2D
var _petal_textures: Array[Texture2D] = []
var _saved_portrait_material: Material
var _warp_material: ShaderMaterial
var _active_tween: Tween
var _petals: Array[TextureRect] = []
var _petal_remaining: int = 0
var _sequence_id: int = 0
var _elapsed: float = 0.0
var _melt_amount: float = 0.0
var _wobble_amount: float = 0.0
var _offline_amount: float = 0.0
var _fox_defeat_revealed: bool = false
var _offline_label_changed: bool = false
var _mode: PresentationMode = PresentationMode.IDLE

var _motion_origin_position: Vector2 = Vector2.ZERO
var _motion_origin_scale: Vector2 = Vector2.ONE
var _motion_origin_rotation: float = 0.0

@onready var _status_label: Label = $StatusLabel


## 接收现有 HUD 立绘和动效层，保持动画目标由调用方所有。
func bind_targets(portrait: TextureRect, motion_layer: StreamerPortraitMotion) -> bool:
	if portrait == null or motion_layer == null:
		return false
	_portrait = portrait
	_motion_layer = motion_layer
	_saved_portrait_material = _portrait.material
	_motion_origin_position = _motion_layer.position
	_motion_origin_scale = _motion_layer.scale
	_motion_origin_rotation = _motion_layer.rotation
	_warp_material = ShaderMaterial.new()
	_warp_material.shader = WARP_SHADER
	clip_contents = true
	return true


## 注入 T5、击败和花瓣资源；演示与正式资源映射均由调用方负责。
func configure_visuals(
	tier_three: Texture2D,
	defeat_transition: Texture2D,
	defeat: Texture2D,
	petal_textures: Array[Texture2D] = []
) -> bool:
	if tier_three == null or defeat == null:
		return false
	_tier_three_texture = tier_three
	_defeat_transition_texture = defeat_transition
	_defeat_texture = defeat
	_petal_textures = petal_textures.duplicate()
	reset_to_tier_three()
	return true


## 播放指定主播的真击破演出，结束时将失败图留在当前立绘槽。
func play_defeat(character_id: StringName) -> bool:
	if _portrait == null or _motion_layer == null or _tier_three_texture == null or _defeat_texture == null:
		return false
	if character_id == &"fox" and _petal_textures.is_empty():
		return false
	reset_to_tier_three()
	_sequence_id += 1
	_elapsed = 0.0
	_mode = _get_mode_for_character(character_id)
	if _mode == PresentationMode.IDLE:
		return false
	visible = true
	_portrait.material = _warp_material
	_motion_layer.set_idle_strength(0.0, 0.14)
	match _mode:
		PresentationMode.ALIEN_MELT:
			_play_alien_melt(character_id, _sequence_id)
		PresentationMode.FOX_PETALS:
			_start_fox_petals(character_id, _sequence_id)
		PresentationMode.KIWI_WOBBLE:
			_play_kiwi_wobble(character_id, _sequence_id)
	return true


## 保留同一张 T5 纹理，先显示未击破，再收暗右侧直播区。
func play_unbroken_offline() -> bool:
	if _portrait == null or _tier_three_texture == null:
		return false
	reset_to_tier_three()
	_sequence_id += 1
	_elapsed = 0.0
	_offline_amount = 0.0
	_offline_label_changed = false
	_mode = PresentationMode.OFFLINE
	visible = true
	_portrait.material = _saved_portrait_material
	_motion_layer.set_idle_strength(0.0, 0.12)
	_status_label.text = unbroken_result_text
	_status_label.visible = true
	_status_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_status_label, "modulate:a", 1.0, 0.14)
	_active_tween.tween_interval(unbroken_hold_seconds)
	_active_tween.tween_callback(_show_offline_text)
	_active_tween.tween_property(self, "_offline_amount", 0.32, offline_transition_seconds * 0.46)
	_active_tween.tween_property(self, "_offline_amount", offline_dark_alpha, offline_transition_seconds * 0.34)
	_active_tween.tween_property(self, "_offline_amount", offline_dark_alpha * 0.92, offline_transition_seconds * 0.2)
	_active_tween.tween_interval(0.16)
	_active_tween.tween_callback(_finish_unbroken_offline.bind(_sequence_id))
	return true


## 重置组件并恢复当前主播的 T5 立绘，供演示重播或新尝试使用。
func reset_to_tier_three() -> void:
	_sequence_id += 1
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = null
	_clear_petals()
	_mode = PresentationMode.IDLE
	_elapsed = 0.0
	_melt_amount = 0.0
	_wobble_amount = 0.0
	_offline_amount = 0.0
	_fox_defeat_revealed = false
	_offline_label_changed = false
	visible = false
	if _portrait != null:
		_portrait.texture = _tier_three_texture
		_portrait.material = _saved_portrait_material
	if _motion_layer != null:
		_motion_layer.position = _motion_origin_position
		_motion_layer.scale = _motion_origin_scale
		_motion_layer.rotation = _motion_origin_rotation
		_motion_layer.set_idle_strength(1.0, 0.16)
	if is_node_ready():
		_status_label.visible = false
		_status_label.modulate = Color.WHITE
	queue_redraw()


# 初始化覆盖层的输入、裁切与状态文案布局。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	clip_contents = true
	visible = false
	resized.connect(_layout_status_label)
	call_deferred("_layout_status_label")


func _process(delta: float) -> void:
	if _mode == PresentationMode.IDLE or _mode == PresentationMode.OFFLINE_DONE:
		return
	_elapsed += delta
	if _mode == PresentationMode.FOX_PETALS and not _fox_defeat_revealed and _elapsed >= fox_defeat_reveal_seconds:
		_fox_defeat_revealed = true
		_portrait.texture = _defeat_texture
	if _mode == PresentationMode.OFFLINE and not _offline_label_changed and _elapsed >= unbroken_hold_seconds + 0.14:
		_show_offline_text()
	if _warp_material != null:
		_warp_material.set_shader_parameter("melt_amount", _melt_amount)
		_warp_material.set_shader_parameter("wobble_amount", _wobble_amount)
	queue_redraw()


# 按当前演出状态绘制融化拖滴、速度线或信号噪点。
func _draw() -> void:
	match _mode:
		PresentationMode.ALIEN_MELT:
			_draw_melt_drips()
		PresentationMode.KIWI_WOBBLE:
			_draw_kiwi_speed_lines()
		PresentationMode.OFFLINE, PresentationMode.OFFLINE_DONE:
			_draw_offline_signal()


## 外星人先松弛、播放融化过渡帧，再压扁落到现有击败图。
func _play_alien_melt(character_id: StringName, sequence_id: int) -> void:
	_melt_amount = 0.0
	_active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_property(
		_motion_layer, "position:y", _motion_origin_position.y + alien_drop_pixels * 0.22, alien_relax_seconds
	)
	_active_tween.parallel().tween_property(_motion_layer, "rotation", _motion_origin_rotation + deg_to_rad(3.0), alien_relax_seconds)
	_active_tween.parallel().tween_property(self, "_melt_amount", 0.22, alien_relax_seconds)
	_active_tween.tween_callback(_show_alien_transition)
	_active_tween.tween_property(self, "_melt_amount", alien_warp_strength, alien_melt_seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_active_tween.parallel().tween_property(
		_motion_layer, "scale", _motion_origin_scale * Vector2(1.06, 1.22), alien_melt_seconds
	)
	_active_tween.tween_property(
		_motion_layer, "position:y", _motion_origin_position.y + alien_drop_pixels, alien_collapse_seconds
	)
	_active_tween.parallel().tween_property(
		_motion_layer, "scale", _motion_origin_scale * Vector2(1.12, 0.42), alien_collapse_seconds
	)
	_active_tween.parallel().tween_property(self, "_melt_amount", 1.0, alien_collapse_seconds)
	_active_tween.tween_callback(_finish_defeat.bind(character_id, sequence_id))


## 四种现有玫瑰贴图从顶部与两侧散落，遮挡时切到狐狸击败图。
func _start_fox_petals(character_id: StringName, sequence_id: int) -> void:
	_fox_defeat_revealed = false
	_petal_remaining = fox_petal_count
	for index: int in range(fox_petal_count):
		var petal: TextureRect = TextureRect.new()
		petal.name = "RosePetal_%02d" % index
		petal.texture = _petal_textures[index % _petal_textures.size()]
		petal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		petal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var progress: float = float(index) / float(maxi(fox_petal_count - 1, 1))
		var dimension: float = lerpf(fox_petal_size_min, fox_petal_size_max, fposmod(float(index) * 0.618, 1.0))
		petal.size = Vector2.ONE * dimension
		petal.pivot_offset = petal.size * 0.5
		var start_x: float = fposmod(float(index) * 83.0, maxf(size.x, 1.0)) - dimension * 0.5
		var start_y: float = -dimension - fposmod(float(index) * 29.0, 80.0)
		petal.position = Vector2(start_x, start_y)
		petal.rotation = deg_to_rad(float(index * 37 % 360))
		petal.modulate = Color(1.0, 1.0, 1.0, 0.0)
		petal.mouse_filter = Control.MOUSE_FILTER_IGNORE
		petal.z_index = 12
		$PetalLayer.add_child(petal)
		_petals.append(petal)
		var delay: float = progress * fox_spawn_stagger_seconds
		var fall_seconds: float = lerpf(fox_fall_seconds_min, fox_fall_seconds_max, fposmod(float(index) * 0.381, 1.0))
		var drift_sign: float = -1.0 if index % 2 == 0 else 1.0
		var end_x: float = clampf(start_x + drift_sign * fox_drift_pixels, -dimension, size.x)
		var fall_tween: Tween = petal.create_tween()
		fall_tween.tween_interval(delay)
		fall_tween.tween_property(petal, "modulate:a", 0.94, 0.12)
		fall_tween.tween_property(
			petal, "position", Vector2(end_x, size.y + dimension), fall_seconds
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		fall_tween.parallel().tween_property(
			petal, "rotation", petal.rotation + deg_to_rad(160.0 + float(index % 7) * 34.0), fall_seconds
		)
		fall_tween.tween_property(petal, "modulate:a", 0.0, 0.18)
		fall_tween.tween_callback(_on_petal_finished.bind(petal, character_id, sequence_id))


## Kiwi 整图多轮加速摇摆，用扭曲与速度线增强翅膀和腿的交错感。
func _play_kiwi_wobble(character_id: StringName, sequence_id: int) -> void:
	_wobble_amount = 0.0
	_active_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for cycle: int in range(kiwi_wobble_cycles):
		var side: float = -1.0 if cycle % 2 == 0 else 1.0
		var speed_progress: float = float(cycle) / float(maxi(kiwi_wobble_cycles - 1, 1))
		var swing_seconds: float = lerpf(kiwi_cycle_seconds, kiwi_cycle_seconds * 0.48, speed_progress)
		var swing_angle: float = deg_to_rad(kiwi_rotation_degrees * side)
		_active_tween.tween_property(
			_motion_layer, "rotation", _motion_origin_rotation + swing_angle, swing_seconds * 0.5
		)
		_active_tween.parallel().tween_property(
			_motion_layer, "position:x", _motion_origin_position.x + side * kiwi_shake_pixels, swing_seconds * 0.5
		)
		_active_tween.parallel().tween_property(
			_motion_layer, "scale", _motion_origin_scale * Vector2(1.05, 0.96), swing_seconds * 0.5
		)
		_active_tween.parallel().tween_property(self, "_wobble_amount", kiwi_wobble_strength, swing_seconds * 0.5)
		_active_tween.tween_property(
			_motion_layer, "rotation", _motion_origin_rotation - swing_angle * 0.62, swing_seconds * 0.5
		)
		_active_tween.parallel().tween_property(
			_motion_layer, "position:x", _motion_origin_position.x - side * kiwi_shake_pixels * 0.55, swing_seconds * 0.5
		)
		_active_tween.parallel().tween_property(
			_motion_layer, "scale", _motion_origin_scale * Vector2(0.96, 1.06), swing_seconds * 0.5
		)
	_active_tween.tween_property(_motion_layer, "position", _motion_origin_position, 0.16)
	_active_tween.parallel().tween_property(_motion_layer, "rotation", _motion_origin_rotation, 0.16)
	_active_tween.parallel().tween_property(_motion_layer, "scale", _motion_origin_scale, 0.16)
	_active_tween.parallel().tween_property(self, "_wobble_amount", 0.0, 0.16)
	_active_tween.tween_callback(_finish_defeat.bind(character_id, sequence_id))


## 短暂停留“未击破”后抖动、扫描线闪烁并压暗右侧直播区。
func _draw_offline_signal() -> void:
	var dark: Color = Color("#070A12")
	dark.a = _offline_amount
	draw_rect(Rect2(Vector2.ZERO, size), dark)
	if _offline_amount < 0.2:
		return
	var band_color: Color = Color("#D6E0E5")
	band_color.a = offline_flicker_strength * (1.0 - _offline_amount * 0.45)
	for index: int in range(7):
		var y: float = fposmod(_elapsed * (176.0 + float(index) * 11.0) + float(index) * 59.0, maxf(size.y, 1.0))
		var width_ratio: float = 0.18 + fposmod(float(index) * 0.37, 0.74)
		draw_rect(Rect2(Vector2(0.0, y), Vector2(size.x * width_ratio, 2.0)), band_color)


## 过渡图出现后用程序色滴做短拖尾，随后交给已交付的击败图。
func _draw_melt_drips() -> void:
	if _melt_amount < 0.1:
		return
	for index: int in range(7):
		var x: float = size.x * (0.13 + float(index) * 0.12)
		var phase: float = fposmod(_elapsed * (0.72 + float(index % 3) * 0.09) + float(index) * 0.17, 1.0)
		var y: float = size.y * (0.56 + phase * 0.34 * _melt_amount)
		var half_width: float = 2.0 + _melt_amount * (2.0 + float(index % 3))
		var drop_length: float = 7.0 + _melt_amount * (12.0 + float(index % 4) * 4.0)
		var drop := PackedVector2Array([
			Vector2(x - half_width, y), Vector2(x + half_width, y), Vector2(x, y + drop_length)
		])
		var drop_color: Color = Color("#8D9E4E")
		drop_color.a = _melt_amount * 0.72
		draw_colored_polygon(drop, drop_color)


## Kiwi 摆动期间在直播画面两侧追加短速度线。
func _draw_kiwi_speed_lines() -> void:
	var line_color: Color = Color("#FFF0D6")
	line_color.a = 0.22 + _wobble_amount * 0.45
	for index: int in range(5):
		var y: float = size.y * (0.17 + float(index) * 0.14)
		var offset: float = fposmod(_elapsed * (96.0 + float(index) * 27.0), 48.0)
		draw_line(Vector2(10.0 + offset, y), Vector2(18.0 + offset + kiwi_speed_line_length, y - 14.0), line_color, 3.0, true)
		draw_line(Vector2(size.x - 10.0 - offset, y + 22.0), Vector2(size.x - 18.0 - offset - kiwi_speed_line_length, y + 8.0), line_color, 3.0, true)


## 切换到融化过渡图，明确展示现有美术帧。
func _show_alien_transition() -> void:
	if _defeat_transition_texture != null:
		_portrait.texture = _defeat_transition_texture


## 显示花瓣密集时切入狐狸击败图。
func _show_fox_defeat() -> void:
	_portrait.texture = _defeat_texture
	_fox_defeat_revealed = true


## 花瓣全部离场后恢复目标变换并发出完成通知。
func _on_petal_finished(petal: TextureRect, character_id: StringName, sequence_id: int) -> void:
	if sequence_id != _sequence_id:
		return
	if is_instance_valid(petal):
		_petals.erase(petal)
		petal.queue_free()
	_petal_remaining = maxi(_petal_remaining - 1, 0)
	if _petal_remaining == 0:
		_finish_defeat(character_id, sequence_id)


## 仅在当前播放序号仍有效时提交 defeat 图与结束事实。
func _finish_defeat(character_id: StringName, sequence_id: int) -> void:
	if sequence_id != _sequence_id:
		return
	_active_tween = null
	_clear_petals()
	_portrait.texture = _defeat_texture
	_portrait.material = _saved_portrait_material
	_restore_motion_transform()
	_mode = PresentationMode.IDLE
	visible = false
	_warp_material.set_shader_parameter("melt_amount", 0.0)
	_warp_material.set_shader_parameter("wobble_amount", 0.0)
	_motion_layer.set_idle_strength(0.0, 0.15)
	defeat_animation_finished.emit(character_id)


## 等离线遮罩到位后留下局部离线画面并通知场景协调方。
func _finish_unbroken_offline(sequence_id: int) -> void:
	if sequence_id != _sequence_id:
		return
	_mode = PresentationMode.OFFLINE_DONE
	_offline_amount = offline_dark_alpha
	_show_offline_text()
	queue_redraw()
	unbroken_offline_finished.emit()


## 结果提示结束后更换为离线文案。
func _show_offline_text() -> void:
	_offline_label_changed = true
	_status_label.text = offline_text


## 还原传入的立绘与变换，不改变关卡或矛盾结果。
func _restore_motion_transform() -> void:
	if _motion_layer == null:
		return
	_motion_layer.position = _motion_origin_position
	_motion_layer.scale = _motion_origin_scale
	_motion_layer.rotation = _motion_origin_rotation


## 删除本次演出生成的花瓣节点。
func _clear_petals() -> void:
	for petal: TextureRect in _petals:
		if is_instance_valid(petal):
			petal.queue_free()
	_petals.clear()
	_petal_remaining = 0


## 依据稳定角色 ID 选择已支持的专属表现。
func _get_mode_for_character(character_id: StringName) -> PresentationMode:
	match character_id:
		&"alien":
			return PresentationMode.ALIEN_MELT
		&"fox":
			return PresentationMode.FOX_PETALS
		&"kiwi":
			return PresentationMode.KIWI_WOBBLE
	return PresentationMode.IDLE


## 更新右侧立绘区中的状态文案锚点。
func _layout_status_label() -> void:
	if not is_node_ready():
		return
	_status_label.position = Vector2(16.0, size.y * 0.5 - 30.0)
	_status_label.size = Vector2(maxf(size.x - 32.0, 0.0), 60.0)
