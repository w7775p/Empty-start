## 仅测试场景装配 HUD 和真实攻击组件；不启动存档或完整战斗流程。
extends Control

var _hud: Control
var _attack: AttackChargeInput
var _starts: int = 0
var _finishes: int = 0
var _shots: int = 0
var _checks: int = 0
var _failures: int = 0


# 测试场景继承正式 Scene，仅替换组合脚本，保留真实节点和布局。
func _ready() -> void:
	# Windows 工作区会压缩带边框窗口；测试固定无边框客户区以验证设计分辨率。
	if DisplayServer.get_name() != "headless":
		get_window().mode = Window.MODE_WINDOWED
		get_window().borderless = true
		get_window().min_size = Vector2i(1920, 1080)
		get_window().size = Vector2i(1920, 1080)
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit(2))
	_hud = get_node("BattleHud")
	_attack = AttackChargeInput.new()
	add_child(_attack)
	_attack.configure_attack_timing(preload("res://tests/fixtures/combat_attack/ca07_short_attack_timing.tres"))
	_attack.set_contradiction_mode(true)
	_attack.shot_snapshot_created.connect(func(_snapshot): _shots += 1)
	_hud.player_portrait_motion.shot_motion_started.connect(func(): _starts += 1)
	_hud.player_portrait_motion.shot_motion_finished.connect(func(): _finishes += 1)
	_hud.bind_portrait_attack(_attack)
	_hud.bind_portrait_attack(_attack)
	call_deferred("_run")


# 验证可见变换、T0、换图、真实未满蓄与满蓄发射，以及取消恢复。
func _run() -> void:
	var player: TextureRect = _hud.get_node("%PlayerPortraitArt")
	var opponent: TextureRect = _hud.get_node("%OpponentPortraitArt")
	var hamster: Texture2D = preload("res://assets/characters/player/hamster_idle.png")
	var alien: Texture2D = preload("res://assets/characters/opponents/alien/alien_idle.png")
	_hud.configure_streamer_assets(hamster, null, null, alien, null, null)
	_check(not opponent.is_visible_in_tree(), "T0 hides opponent with configured PNG")
	_hud.refresh_pk(0.5, 1)
	_check(player.is_visible_in_tree() and opponent.is_visible_in_tree(), "both PNG visible at T1")
	await _wait(0.1)
	var player_before: Transform2D = player.get_global_transform()
	var opponent_before: Transform2D = opponent.get_global_transform()
	await _capture("idle_a")
	await _wait(0.45)
	_check(not player.get_global_transform().is_equal_approx(player_before), "player whole PNG moves")
	_check(not opponent.get_global_transform().is_equal_approx(opponent_before), "opponent whole PNG moves")
	var breath_scale: float = player.get_global_transform().y.length() / _hud.get_global_transform().y.length()
	_check(breath_scale > 0.97 and breath_scale < 1.03, "breath stays within 3 percent of HUD scale")
	_check(not is_equal_approx(player.get_global_transform().y.length(), opponent.get_global_transform().y.length()), "distinct idle phases")
	await _capture("idle_b")
	get_tree().paused = true
	var paused_transform: Transform2D = player.get_global_transform()
	await get_tree().create_timer(0.15, true).timeout
	_check(player.get_global_transform().is_equal_approx(paused_transform), "pause freezes portrait tween")
	get_tree().paused = false
	_mouse(true)
	_mouse(false)
	await _wait(0.08)
	_check(_shots == 0 and _starts == 0, "undercharge emits no shot or motion")
	_mouse(true)
	await _wait(0.28)
	_mouse(false)
	await _wait(0.06)
	_check(_shots == 1 and _starts == 1, "one full-charge snapshot starts one motion after duplicate bind")
	_check(_hud.player_portrait_motion.position.length() > 0.1, "shot moves portrait during its event tween")
	await _capture("shot")
	await _wait(0.55)
	_check(_finishes == 1 and _hud.player_portrait_motion.position.is_zero_approx(), "shot finishes once at origin")
	_check(_hud.player_portrait_motion.scale.is_equal_approx(Vector2.ONE), "shot scale restores")
	for character_id: String in ["kiwi", "fox", "alien"]:
		_hud.configure_portrait_character(character_id)
		_hud.configure_streamer_assets(hamster, null, null, load("res://assets/characters/opponents/%s/%s_idle.png" % [character_id, character_id]), null, null)
		await _wait(0.1)
		_check(opponent.is_visible_in_tree(), character_id + " preset keeps existing portrait container")
	var same_motion: Control = _hud.opponent_portrait_motion
	_hud.configure_streamer_assets(hamster, null, null, preload("res://assets/characters/opponents/alien/alien_tier_01.png"), null, null)
	_check(_hud.opponent_portrait_motion == same_motion, "tier PNG replacement keeps motion container")
	_hud.player_portrait_motion.set_idle_strength(0.0, 0.02)
	await _wait(0.06)
	var idle_muted: Transform2D = player.get_global_transform()
	await _wait(0.08)
	_check(player.get_global_transform().is_equal_approx(idle_muted), "event can mute idle smoothly")
	_hud.player_portrait_motion.set_idle_strength(1.0, 0.02)
	var slot: Control = _hud.player_portrait_motion.get_parent()
	slot.rotation = 0.01
	_mouse(true)
	await _wait(0.28)
	_mouse(false)
	await _wait(0.5)
	_check(_shots == 2 and _starts == 2 and _finishes == 2, "second real shot completes once")
	_check(is_equal_approx(slot.rotation, 0.01), "outer event transform survives idle and shot")
	_hud.player_portrait_motion.play_shot()
	await _wait(0.03)
	_hud.player_portrait_motion.play_shot()
	await _wait(0.5)
	_check(_finishes == 3, "interrupted tween finishes only its replacement")
	_hud.player_portrait_motion.play_shot()
	await _wait(0.03)
	_hud.reset_for_attempt()
	await _wait(0.5)
	_check(_finishes == 3 and _hud.player_portrait_motion.position.is_zero_approx(), "reset cancels pending shot")
	_check(not opponent.is_visible_in_tree(), "reset returns opponent to T0")
	_hud.bind_portrait_attack(null)
	_mouse(true)
	await _wait(0.28)
	var starts_before: int = _starts
	_mouse(false)
	await _wait(0.5)
	_check(_starts == starts_before, "unbound attack stops visual callbacks")
	print("PA14 RESULT checks=%d failures=%d display=%s viewport=%s" % [_checks, _failures, DisplayServer.get_name(), get_viewport_rect().size])
	get_tree().quit(0 if _failures == 0 else 1)


# 真实输入分发驱动攻击组件，蓄力由实际帧推进。
func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(900, 500)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


# 仅 GUI 保存真实视口截图到本工作区忽略目录。
func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://.godot/pa14-evidence/%s.png" % label)


# 使用实际计时等待原生 Tween 和攻击 Timer。
func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# 同时输出断言与退出码，避免空运行误报通过。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
