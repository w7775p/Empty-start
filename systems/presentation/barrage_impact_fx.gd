class_name BarrageImpactFx
extends Control

const BARRAGE_SCENE: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")

@export_group("碎裂 / 曲线")
@export_range(0.08, 0.6, 0.01) var break_seconds: float = 0.28
@export_range(5.0, 52.0, 1.0) var shard_push: float = 27.0
@export_range(0.0, 0.25, 0.01) var curve_depth: float = 0.11
@export_range(0.0, 0.4, 0.01) var shard_rotation: float = 0.09
@export var fracture_color: Color = Color("#F8F5E9")

@export_group("漫画强调符号")
@export var accent_texture: Texture2D
@export var accent_symbol: String = "∑"
@export_range(22, 108, 1) var accent_size: int = 60
@export var accent_offset: Vector2 = Vector2(4, -50)
@export var accent_color: Color = Color("#FFF0C7")

@export_group("材质命中")
@export_range(0.08, 0.55, 0.01) var rebound_seconds: float = 0.35
@export_range(0.08, 0.55, 0.01) var hard_seconds: float = 0.19
@export_range(0.1, 0.9, 0.05) var compressed_y: float = 0.58
@export_range(1.0, 1.5, 0.01) var stretched_y: float = 1.23

var _effect_mode: StringName
var _render_size: Vector2


# 独立镜像只进入演出容器；场上真实 BarrageView 按原战斗系统的时机移除。
func play_fracture(target: BarrageView, kind: StringName = &"normal") -> void:
	if target == null or not is_instance_valid(target) or target.runtime_record == null:
		queue_free()
		return
	_effect_mode = kind
	_render_size = target.size
	size = target.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_capture_then_break(target.runtime_record)


# 原始弹幕删掉后，借助 SubViewport 一帧镜像得到完整彩色玻璃与正文的像素。
func _capture_then_break(record: BarrageRuntimeRecord) -> void:
	var snapshot: SubViewport = SubViewport.new()
	snapshot.name = "HitSourceTexture"
	snapshot.size = Vector2i(maxi(1, ceili(_render_size.x)), maxi(1, ceili(_render_size.y)))
	snapshot.disable_3d = true
	snapshot.transparent_bg = true
	snapshot.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(snapshot)
	var area: Control = Control.new()
	area.size = _render_size
	snapshot.add_child(area)
	var copy: BarrageView = BARRAGE_SCENE.instantiate() as BarrageView
	copy.setup(record, 0.0, area)
	area.add_child(copy)
	copy.position = Vector2.ZERO
	await RenderingServer.frame_post_draw
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var image: Image = snapshot.get_texture().get_image()
	if image.is_empty():
		queue_free()
		return
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	remove_child(snapshot)
	snapshot.queue_free()
	_start_break(texture)


# 两块各自用曲线多边形 UV 裁切相同画面，分离后各自消隐。
func _start_break(texture: Texture2D) -> void:
	var top: Polygon2D = _make_shard(texture, true)
	var bottom: Polygon2D = _make_shard(texture, false)
	add_child(top)
	add_child(bottom)
	var split_curve := Line2D.new()
	split_curve.width = 2.8
	split_curve.default_color = fracture_color
	for i in range(19):
		var x: float = _render_size.x * float(i) / 18.0
		split_curve.add_point(Vector2(x, _curve_y(x)))
	add_child(split_curve)
	_show_accent()
	var tween: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	tween.set_parallel(true)
	tween.tween_property(top, "position", Vector2(-shard_push, -shard_push * 0.70), break_seconds).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(bottom, "position", Vector2(shard_push, shard_push * 0.66), break_seconds).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(top, "rotation", -shard_rotation, break_seconds)
	tween.tween_property(bottom, "rotation", shard_rotation, break_seconds)
	tween.tween_property(top, "modulate:a", 0.0, break_seconds).set_delay(break_seconds * 0.20)
	tween.tween_property(bottom, "modulate:a", 0.0, break_seconds).set_delay(break_seconds * 0.20)
	tween.tween_property(split_curve, "modulate:a", 0.0, break_seconds * 0.60)
	tween.chain().tween_callback(queue_free)


func _curve_y(x: float) -> float:
	var t: float = x / maxf(1.0, _render_size.x)
	if _effect_mode == &"split":
		# 母体已存在左上→右下的预裂玻璃纹；碎裂沿同一走向延伸到全板。
		return lerpf(9.0, _render_size.y - 8.0, t) + sin(t * PI * 3.0) * 3.3
	return _render_size.y * (0.50 + sin(t * PI * 2.05 - 0.70) * curve_depth)


func _make_shard(texture: Texture2D, upper: bool) -> Polygon2D:
	var poly := Polygon2D.new()
	var perimeter: PackedVector2Array = PackedVector2Array()
	if upper:
		perimeter.append(Vector2.ZERO)
		perimeter.append(Vector2(_render_size.x, 0))
		for i in range(19, -1, -1):
			var x: float = _render_size.x * float(i) / 19.0
			perimeter.append(Vector2(x, _curve_y(x)))
	else:
		for i in range(20):
			var x: float = _render_size.x * float(i) / 19.0
			perimeter.append(Vector2(x, _curve_y(x)))
		perimeter.append(Vector2(_render_size.x, _render_size.y))
		perimeter.append(Vector2(0, _render_size.y))
	poly.polygon = perimeter
	poly.uv = perimeter.duplicate()
	poly.texture = texture
	poly.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return poly


# 漫画强调符号可直接被美术的透明 PNG 替代。
func _show_accent() -> void:
	var accent: Control
	if accent_texture != null:
		var icon := TextureRect.new()
		icon.texture = accent_texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2.ONE * float(accent_size)
		icon.size = Vector2.ONE * float(accent_size)
		accent = icon
	else:
		var label := Label.new()
		label.text = accent_symbol
		label.add_theme_font_size_override("font_size", accent_size)
		label.add_theme_color_override("font_color", accent_color)
		label.add_theme_color_override("font_outline_color", Color("#171D32"))
		label.add_theme_constant_override("outline_size", 5)
		accent = label
	add_child(accent)
	accent.position = Vector2(_render_size.x, 0) + accent_offset
	accent.z_index = 3
	var pop: Tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	accent.scale = Vector2(0.60, 0.60)
	pop.tween_property(accent, "scale", Vector2.ONE * 1.2, 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(accent, "modulate:a", 0.0, break_seconds * 0.65)


# 打到铁板：一瞬间局部撞击线，真实铁质弹幕仍保持在原场上。
func play_hard_hit(target: BarrageView) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	_effect_mode = &"occlusion"
	size = target.size
	process_mode = Node.PROCESS_MODE_PAUSABLE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.pulse_presentation(1.08, hard_seconds)
	var flash := ColorRect.new()
	flash.color = Color("#E8F4FF", 0.45)
	flash.size = Vector2(13, size.y * 0.75)
	flash.position = Vector2(size.x * 0.52, size.y * 0.12)
	flash.rotation = -0.22
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var t := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	t.tween_property(flash, "modulate:a", 0.0, hard_seconds)
	t.tween_callback(queue_free)


# 反弹弹幕在临时镜像中压缩→拉伸→回正，场上原实体可按既有结算移除。
func play_rebound(target: BarrageView) -> void:
	if target == null or not is_instance_valid(target) or target.runtime_record == null:
		queue_free()
		return
	_effect_mode = &"reflect"
	size = target.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var copy: BarrageView = BARRAGE_SCENE.instantiate() as BarrageView
	copy.setup(target.runtime_record, 0.0, self)
	add_child(copy)
	copy.position = Vector2.ZERO
	copy.pivot_offset = copy.size * 0.5
	var motion := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	motion.tween_property(copy, "scale", Vector2(1.22, compressed_y), rebound_seconds * 0.28).set_trans(Tween.TRANS_CUBIC)
	motion.tween_property(copy, "scale", Vector2(0.90, stretched_y), rebound_seconds * 0.38).set_trans(Tween.TRANS_BACK)
	motion.tween_property(copy, "scale", Vector2.ONE, rebound_seconds * 0.34).set_trans(Tween.TRANS_SINE)
	motion.tween_callback(queue_free)


# 每发退出时取消短命镜像；暂停时 Tween 由 SceneTree 原生管理。
func get_effect_mode() -> StringName:
	return _effect_mode
