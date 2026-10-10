extends SceneTree

const BARRAGE_AREA_SCENE = preload("res://systems/barrage_generation/barrage_area.tscn")

func _init() -> void:
	call_deferred("_run_component_test")

## 普通槽位满时仍生成复读，并保留 RepeatPlan 的原句 ID 和寿命。
func _run_component_test() -> void:
	var profile: LevelProfile = LevelProfile.new()
	profile.base_batch_count = 0
	profile.base_spawn_interval_seconds = 60.0
	profile.base_move_speed_pixels_per_second = 0.0
	profile.normal_barrage_screen_cap = 2

	var barrage_area: BarrageArea = BARRAGE_AREA_SCENE.instantiate() as BarrageArea
	root.add_child(barrage_area)
	barrage_area.start_normal_generation(profile)
	# Tier 前景名额比关卡 fallback 小；复读仍走独立容量账本。
	barrage_area.set_foreground_slot_count(1)

	var normal_speech: LevelSpeech = LevelSpeech.new()
	normal_speech.original_sentence_id = "bg10_normal_sentence"
	normal_speech.text = "普通话语"
	normal_speech.tendency_id = "orthodox"
	var normal_view: BarrageView = barrage_area.spawn_normal_barrage(profile, normal_speech)

	barrage_area.repeat_barrage_screen_cap = 1
	var plan: RepeatPlan = RepeatPlan.new()
	plan.original_line_id = &"bg10_repeat_sentence"
	plan.original_line_text = "重复原句"
	plan.display_text = "复读：重复原句"
	plan.planned_repeat_count = 1
	plan.lifetime_seconds = 3.0
	var spawn_started_msec: int = Time.get_ticks_msec()
	var repeat_view: BarrageView = barrage_area.spawn_repeat_barrage(plan)
	var deadline_preserved: bool = false
	var original_line_preserved: bool = false
	var display_text_preserved: bool = false
	if repeat_view != null:
		var remaining_lifetime_msec: int = repeat_view.runtime_record.expires_at_msec - Time.get_ticks_msec()
		deadline_preserved = remaining_lifetime_msec > 0 and remaining_lifetime_msec <= 3000 and repeat_view.runtime_record.expires_at_msec >= spawn_started_msec + 3000
		original_line_preserved = repeat_view.runtime_record.original_sentence_id == "bg10_repeat_sentence"
		display_text_preserved = repeat_view.text == "复读：重复原句"
	var extra_normal_speech: LevelSpeech = LevelSpeech.new()
	extra_normal_speech.original_sentence_id = "bg10_extra_normal"
	extra_normal_speech.text = "额外普通话语"
	var extra_normal_rejected: bool = barrage_area.spawn_normal_barrage(profile, extra_normal_speech) == null
	# 释放普通实例后复读仍满；释放复读后可再次生成，两组真实容量互不串扰。
	var normal_reopened: bool = false
	var repeat_stays_full: bool = false
	var repeat_reopened: bool = false
	if normal_view != null and repeat_view != null:
		barrage_area.end_barrage(normal_view.get_instance_id())
		normal_reopened = barrage_area.spawn_normal_barrage(profile, extra_normal_speech) != null
		repeat_stays_full = barrage_area.spawn_repeat_barrage(plan) == null
		barrage_area.end_barrage(repeat_view.get_instance_id())
		repeat_reopened = barrage_area.spawn_repeat_barrage(plan) != null
	var passed: bool = normal_view != null and repeat_view != null and deadline_preserved and original_line_preserved and display_text_preserved and extra_normal_rejected and normal_reopened and repeat_stays_full and repeat_reopened
	if passed:
		print("PASS: 普通容量满时复读仍生成并保留原句与寿命。")
	else:
		push_error("FAIL: 复读计划或容量隔离失败; normal_reopened=%s repeat_stays_full=%s repeat_reopened=%s" % [normal_reopened, repeat_stays_full, repeat_reopened])
	barrage_area.clear_barrages()
	barrage_area.queue_free()
	await process_frame
	quit(0 if passed else 1)
