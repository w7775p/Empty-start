extends SceneTree

var _completed_count: int = 0


# 单独启动场景验证公开接口、几何判定、进度平滑、暂停、重播和完成信号。
func _initialize() -> void:
	call_deferred("_run_checks")


func _run_checks() -> void:
	var packed: PackedScene = load("res://systems/combat_attack/aim_reticle.tscn")
	if not _expect(packed != null, "can load AimReticle scene"):
		return
	var reticle: AimReticle = packed.instantiate() as AimReticle
	root.add_child(reticle)
	await process_frame
	reticle.animation_finished.connect(_on_animation_finished)

	reticle.move_touch_aim(Vector2(420.0, 300.0), 64.0)
	var expected: Vector2 = reticle.get_canvas_transform().affine_inverse() * Vector2(420.0, 300.0)
	if not _expect(reticle.get_aim_center_global_position().distance_to(expected) < 0.05, "touch center matches aim center"):
		return
	if not _expect(is_equal_approx(reticle.reticle_diameter, 64.0), "mobile diameter changes visual and hit geometry"):
		return
	if not _expect(reticle.intersects_target_area(Rect2(expected - Vector2(8.0, 8.0), Vector2(16.0, 16.0))), "center target intersects"):
		return
	if not _expect(not reticle.intersects_target_area(Rect2(expected + Vector2(130.0, 130.0), Vector2(20.0, 20.0))), "distant target misses"):
		return

	reticle.set_charge_visual_state(0.50, true, false)
	await create_timer(0.24).timeout
	if not _expect(absf(reticle.get_display_charge_progress() - 0.50) < 0.06, "charging follows injected state"):
		return

	reticle.set_charge_visual_state(0.86, true, false)
	reticle.set_visual_paused(true)
	var saved: float = reticle.get_display_charge_progress()
	await create_timer(0.20).timeout
	if not _expect(absf(reticle.get_display_charge_progress() - saved) < 0.0001, "pause holds rendering progress"):
		return
	reticle.set_visual_paused(false)
	await create_timer(0.22).timeout
	if not _expect(absf(reticle.get_display_charge_progress() - 0.86) < 0.05, "resume continues progress"):
		return

	reticle.set_charge_visual_state(1.0, true, true)
	await create_timer(0.20).timeout
	if not _expect(reticle.get_display_charge_progress() > 0.96, "full charge ring reaches complete state"):
		return

	reticle.play_shot_feedback()
	if not _expect(reticle.is_shot_feedback_playing(), "shot begins visible effect"):
		return
	await create_timer(0.24).timeout
	if not _expect(_completed_count == 1 and not reticle.is_shot_feedback_playing(), "shot emits completion once"):
		return

	reticle.play_shot_feedback()
	await create_timer(0.24).timeout
	if not _expect(_completed_count == 2, "shot replays and finishes again"):
		return

	reticle.play_shot_feedback()
	reticle.reset_visual_state()
	await create_timer(0.22).timeout
	if not _expect(_completed_count == 2 and reticle.get_display_charge_progress() == 0.0, "reset cancels effect and clears progress"):
		return

	reticle.play_shot_feedback()
	reticle.set_visual_paused(true)
	await create_timer(0.24).timeout
	if not _expect(_completed_count == 2 and reticle.is_shot_feedback_playing(), "paused shot retains its time"):
		return
	reticle.set_visual_paused(false)
	await create_timer(0.24).timeout
	if not _expect(_completed_count == 3 and not reticle.is_shot_feedback_playing(), "paused shot resumes with one finish"):
		return

	print("PA08_RUNTIME_TEST_PASS: 15 checks, 3 completion signals")
	reticle.queue_free()
	quit()


# 只观察来自准星视觉组件的动画完成事实。
func _on_animation_finished() -> void:
	_completed_count += 1


# 任何失败都以非零退出码报告给自动化脚本。
func _expect(condition: bool, description: String) -> bool:
	if condition:
		print("PASS: " + description)
		return true
	push_error("PA08_TEST_FAIL: " + description)
	quit(1)
	return false
