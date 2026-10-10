extends SceneTree

const AREA_SCENE = preload("res://systems/barrage_generation/barrage_area.tscn")

func _init() -> void:
	call_deferred("_run")

# TEST_ONLY 陷阱只模拟外部占位；用真实普通生成和离树释放验证共享容量。
func _run() -> void:
	var profile := LevelProfile.new()
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 0.05
	profile.base_move_speed_pixels_per_second = 0.0
	profile.normal_barrage_screen_cap = 1
	profile.orthodox_ratio = 1.0
	var speech := LevelSpeech.new()
	speech.original_sentence_id = "test_capacity_line"
	speech.text = "容量恢复"
	speech.tendency_id = "orthodox"
	profile.normal_speech_pool.append(speech)
	var area: BarrageArea = AREA_SCENE.instantiate()
	root.add_child(area)
	area.start_normal_generation(profile)
	var trap := Node.new()
	area.add_child(trap)
	var registered: bool = area.try_register_normal_capacity_occupant(trap)
	var rejected: bool = area.spawn_normal_barrage(profile, speech) == null
	profile.base_batch_count = 1
	await create_timer(0.12).timeout
	var blocked: bool = area.get_current_barrage_counts()["normal"] == 0
	area.remove_child(trap)
	trap.free()
	# 给真实批次 Timer 留出有限时间；出现普通实例即证明恢复生成。
	for _frame in range(60):
		if area.get_current_barrage_counts()["normal"] == 1:
			break
		await process_frame
	var resumed: bool = area.get_current_barrage_counts()["normal"] == 1
	area.clear_barrages()
	var respawned: bool = area.spawn_normal_barrage(profile, speech) != null
	var passed: bool = registered and rejected and blocked and resumed and respawned
	if passed:
		print("PASS BG capacity: trap blocks normal; tree exit resumes Timer; clear releases slot")
	else:
		push_error("FAIL BG capacity: registered=%s rejected=%s blocked=%s resumed=%s respawned=%s" % [registered, rejected, blocked, resumed, respawned])
	area.clear_barrages()
	area.queue_free()
	await process_frame
	quit(0 if passed else 1)
