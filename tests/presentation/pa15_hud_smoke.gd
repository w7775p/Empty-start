extends Control

const IDLE = preload("res://assets/characters/opponents/alien/alien_idle.png")
const TIER_01 = preload("res://assets/characters/opponents/alien/alien_tier_01.png")
const TIER_02 = preload("res://assets/characters/opponents/alien/alien_tier_02.png")
const TIER_03 = preload("res://assets/characters/opponents/alien/alien_tier_03.png")

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	call_deferred("_run")


# 使用正式 Sandbox HUD 验证公开接线、T0 隐藏、Paradox 保留 T5 与重开清理。
func _run() -> void:
	var hud: Control = get_node("BattleHud")
	var portrait: TextureRect = hud.get_node("%OpponentPortraitArt")
	hud.configure_streamer_assets(null, null, null, IDLE, null, null)
	hud.configure_opponent_tier_textures(IDLE, TIER_01, TIER_02, TIER_03)
	_check(not hud.opponent_tier_portrait.visible, "T0 opponent hidden")
	for tier: int in [1, 2, 3, 4, 5, 6, 4, 2, 1]:
		hud.refresh_pk(0.5, tier)
		await get_tree().create_timer(0.44).timeout
		var expected: Texture2D = IDLE
		match tier:
			3:
				expected = TIER_01
			4:
				expected = TIER_02
			5, 6:
				expected = TIER_03
		_check(portrait.texture == expected, "HUD T%d texture" % tier)
		_check(hud.opponent_tier_portrait.visible, "HUD T%d visible" % tier)
	hud.refresh_pk(0.5, 3)
	hud.refresh_pk(0.5, 5)
	await get_tree().create_timer(0.44).timeout
	_check(portrait.texture == TIER_03, "rapid stage uses final T5 texture")
	hud.reset_for_attempt()
	_check(not hud.opponent_tier_portrait.visible and portrait.scale.is_equal_approx(Vector2.ONE), "reset hides and restores portrait")
	print("PA15 HUD RESULT checks=%d failures=%d" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("PASS: " + message)
	else:
		_failures += 1
		push_error("FAIL: " + message)
