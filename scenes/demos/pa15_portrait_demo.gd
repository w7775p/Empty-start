extends Control

const TierPortrait = preload("res://systems/presentation/opponent_tier_portrait.gd")
const PortraitMotion = preload("res://systems/presentation/streamer_portrait_motion.gd")

const PORTRAITS := [
	["alien", preload("res://assets/characters/opponents/alien/alien_idle.png"), preload("res://assets/characters/opponents/alien/alien_tier_01.png"), preload("res://assets/characters/opponents/alien/alien_tier_02.png"), preload("res://assets/characters/opponents/alien/alien_tier_03.png")],
	["kiwi", preload("res://assets/characters/opponents/kiwi/kiwi_idle.png"), preload("res://assets/characters/opponents/kiwi/kiwi_tier_01.png"), preload("res://assets/characters/opponents/kiwi/kiwi_tier_02.png"), preload("res://assets/characters/opponents/kiwi/kiwi_tier_03.png")],
	["fox", preload("res://assets/characters/opponents/fox/fox_idle.png"), preload("res://assets/characters/opponents/fox/fox_tier_01.png"), preload("res://assets/characters/opponents/fox/fox_tier_02.png"), preload("res://assets/characters/opponents/fox/fox_tier_03.png")]
]

var _views: Array[OpponentTierPortrait] = []
var _portraits: Array[TextureRect] = []
var _status: Label
var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	var background := ColorRect.new()
	background.color = Color("151b2c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	for index: int in PORTRAITS.size():
		_create_card(index)
	_status = Label.new()
	_status.position = Vector2(80, 70)
	_status.add_theme_font_size_override("font_size", 28)
	add_child(_status)
	if "--kiwi-sample" in OS.get_cmdline_user_args():
		call_deferred("_loop_kiwi_sample")
	elif "--keep-open" in OS.get_cmdline_user_args():
		call_deferred("_loop_preview")
	else:
		call_deferred("_run")


func _create_card(index: int) -> void:
	var entry: Array = PORTRAITS[index]
	var frame := ColorRect.new()
	frame.color = Color("292c42")
	frame.position = Vector2(80 + index * 600, 170)
	frame.size = Vector2(448, 470)
	add_child(frame)
	# 演示卡片把标题与立绘分槽，速度线按立绘槽尺寸排布。
	var portrait_slot := Control.new()
	portrait_slot.position = Vector2(0, 38)
	portrait_slot.size = frame.size - portrait_slot.position
	frame.add_child(portrait_slot)
	var portrait := TextureRect.new()
	portrait.size = portrait_slot.size
	portrait.texture = entry[1]
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_slot.add_child(portrait)
	var motion := PortraitMotion.new()
	motion.configure_character(entry[0])
	motion.attach_portrait(portrait)
	var view := TierPortrait.new()
	view.attach_portrait(portrait)
	view.configure_textures(entry[1], entry[2], entry[3], entry[4])
	view.configure_character(entry[0])
	_views.append(view)
	_portraits.append(portrait)
	var title := Label.new()
	title.text = entry[0].to_upper()
	title.position = Vector2(15, 4)
	title.add_theme_font_size_override("font_size", 26)
	frame.add_child(title)


# 三个正式角色同时逐档升降，核对映射、汗滴、快速改档和 Paradox 维持 T5 图。
func _run() -> void:
	for tier: int in [1, 2, 3, 4, 5, 6, 5, 4, 3, 2, 1]:
		_status.text = "PA-15 · Tier %d" % tier
		for view: OpponentTierPortrait in _views:
			view.show_tier(tier)
		if tier == 3:
			await get_tree().create_timer(0.19).timeout
			await _capture("tier_3_flip")
			await get_tree().create_timer(0.36).timeout
		else:
			await get_tree().create_timer(0.55).timeout
		for index: int in _views.size():
			var expected: Texture2D = PORTRAITS[index][clampi(tier - 1, 2, 4)] if tier >= 3 else PORTRAITS[index][1]
			_check(_portraits[index].texture == expected, "%s T%d texture" % [PORTRAITS[index][0], tier])
			_check(_views[index].fx.sweat_alpha > 0.9 if tier == 2 else _views[index].fx.sweat_alpha < 0.1, "%s T%d sweat" % [PORTRAITS[index][0], tier])
		_check(_views[1].position.is_equal_approx(Vector2.ZERO), "kiwi T%d position restored" % tier)
		_check(_portraits[1].scale.is_equal_approx(Vector2.ONE), "kiwi T%d scale restored" % tier)
		if tier >= 3:
			for index: int in _views.size():
				_check(not _views[index].fx.is_processing(), "%s T%d impact cleared" % [PORTRAITS[index][0], tier])
		await _capture("tier_%d" % tier)
		if tier == 2:
			await get_tree().create_timer(0.68).timeout
			await _capture("tier_2_late")
	for view: OpponentTierPortrait in _views:
		view.show_tier(3)
		view.show_tier(5)
	await get_tree().create_timer(0.55).timeout
	for index: int in _views.size():
		_check(_portraits[index].texture == PORTRAITS[index][4], "%s rapid T3 to T5" % PORTRAITS[index][0])
	_check(_views[1].position.is_equal_approx(Vector2.ZERO), "kiwi rapid stage position restored")
	_check(_portraits[1].scale.is_equal_approx(Vector2.ONE), "kiwi rapid stage scale restored")
	for index: int in _views.size():
		_check(not _views[index].fx.is_processing(), "%s rapid impact cleared" % PORTRAITS[index][0])
	print("PA15 RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


# 在 Godot 窗口中持续展示各档位，方便直接观察汗滴滑落和翻面。
func _loop_preview() -> void:
	while is_inside_tree():
		for tier: int in [1, 2, 3, 4, 5, 6, 5, 4, 3, 2]:
			_status.text = "PA-15 · Tier %d · 循环演示" % tier
			for view: OpponentTierPortrait in _views:
				view.show_tier(tier)
			await get_tree().create_timer(1.5 if tier == 2 else 0.8).timeout


# 样板只循环 Kiwi 的翻图段，另外两位保持原样作为画面对照。
func _loop_kiwi_sample() -> void:
	for index: int in _views.size():
		_views[index].show_tier(2 if index == 1 else 3)
	await get_tree().create_timer(0.6).timeout
	var captured: bool = false
	while is_inside_tree():
		for tier: int in [3, 4, 5, 4, 3]:
			_status.text = "PA-15 · KIWI 冲击效果样板 · T%d" % tier
			_views[1].show_tier(tier)
			if tier == 3 and not captured and "--capture" in OS.get_cmdline_user_args():
				await get_tree().create_timer(0.19).timeout
				await _capture("kiwi_burst")
				await get_tree().create_timer(0.16).timeout
				await _capture("kiwi_rebound")
				await get_tree().create_timer(0.25).timeout
				await _capture("kiwi_cleared")
				await get_tree().create_timer(0.25).timeout
				captured = true
			else:
				await get_tree().create_timer(0.85).timeout
		_views[1].show_tier(2)
		await get_tree().create_timer(0.9).timeout


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute("res://.godot/pa15-evidence")
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/pa15-evidence/%s.png" % label) == OK, "capture " + label)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
