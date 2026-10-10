extends SceneTree

const AREA_SCENE = preload("res://systems/barrage_generation/barrage_area.tscn")

func _init() -> void:
	call_deferred("_run")

# 通过实际区域改变倍率；旧实例截止时间应固定，新实例读取当前倍率。
func _run() -> void:
	var profile := LevelProfile.new()
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 0.0
	profile.normal_barrage_screen_cap = 2
	var speech := LevelSpeech.new()
	speech.original_sentence_id = "test_lifetime_line"
	speech.text = "寿命快照"
	var area: BarrageArea = AREA_SCENE.instantiate()
	root.add_child(area)
	area.start_normal_generation(profile)
	area.base_lifetime_seconds = 10.0
	var old_view: BarrageView = area.spawn_normal_barrage(profile, speech)
	if old_view == null:
		push_error("FAIL BG lifetime: first instance failed to spawn")
		area.free()
		quit(1)
		return
	var old_deadline: int = old_view.runtime_record.expires_at_msec
	area.set_lifetime_multiplier(1.5)
	var started: int = Time.get_ticks_msec()
	var new_view: BarrageView = area.spawn_normal_barrage(profile, speech)
	var ended: int = Time.get_ticks_msec()
	var passed: bool = old_view.runtime_record.expires_at_msec == old_deadline and new_view != null
	if new_view != null:
		var deadline: int = new_view.runtime_record.expires_at_msec
		passed = passed and deadline >= started + 15000 and deadline <= ended + 15000
	if passed:
		print("PASS BG lifetime: multiplier change preserves old deadline and applies to new instance")
	else:
		push_error("FAIL BG lifetime: old deadline changed or new lifetime differs from 15 seconds")
	area.clear_barrages()
	area.queue_free()
	await process_frame
	quit(0 if passed else 1)
