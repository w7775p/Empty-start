extends SceneTree

const RETICLE_SCENE: PackedScene = preload("res://systems/combat_attack/aim_reticle.tscn")

var _finished: int = 0


# 只验收外部调用会破坏玩法的边界；具体色彩与动效交给实际 Godot 画面检查。
func _initialize() -> void:
	call_deferred("_smoke")


func _smoke() -> void:
	var reticle: AimReticle = RETICLE_SCENE.instantiate() as AimReticle
	root.add_child(reticle)
	await process_frame
	reticle.animation_finished.connect(func() -> void: _finished += 1)

	# 移动端准星中心与命中判定保持一致。
	reticle.move_touch_aim(Vector2(420, 300), 64.0)
	var center: Vector2 = reticle.get_canvas_transform().affine_inverse() * Vector2(420, 300)
	if not _expect(
		reticle.get_aim_center_global_position().distance_to(center) < 0.1
		and reticle.intersects_target_area(Rect2(center - Vector2(8, 8), Vector2(16, 16)))
		and not reticle.intersects_target_area(Rect2(center + Vector2(140, 140), Vector2(16, 16))),
		"touch aim still hits the correct target"
	):
		return

	# 外部蓄力事实可以推动进度环，复位可重新开始下一次蓄力。
	reticle.set_charge_visual_state(0.6, true, false)
	await create_timer(0.25).timeout
	var progressed: bool = reticle.get_display_charge_progress() > 0.5
	reticle.reset_visual_state()
	if not _expect(progressed and reticle.get_display_charge_progress() == 0.0, "charge input and reset"):
		return

	# 演出暂停时不能提前发出完成通知；恢复后只能发送一次。
	reticle.play_shot_feedback()
	reticle.set_visual_paused(true)
	await create_timer(0.23).timeout
	var held: bool = _finished == 0 and reticle.is_shot_feedback_playing()
	reticle.set_visual_paused(false)
	await create_timer(0.23).timeout
	if not _expect(held and _finished == 1 and not reticle.is_shot_feedback_playing(), "shot pause and completion signal"):
		return

	# 同一视觉实例可以重播，重置正在播放的短闪也不会误报完成。
	reticle.play_shot_feedback()
	await create_timer(0.23).timeout
	var replayed: bool = _finished == 2
	reticle.play_shot_feedback()
	reticle.reset_visual_state()
	await create_timer(0.23).timeout
	if not _expect(replayed and _finished == 2 and not reticle.is_shot_feedback_playing(), "replay and cancellation"):
		return

	print("PA08_SMOKE_PASS: 4 behavior scenarios")
	reticle.queue_free()
	quit(0)


# 以运行结果判定成功，退出码不能替代明确的预期输出。
func _expect(valid: bool, description: String) -> bool:
	if not valid:
		push_error("PA08_SMOKE_FAIL: " + description)
		quit(1)
		return false
	print("PASS: " + description)
	return true
