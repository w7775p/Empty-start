extends SceneTree

const REPEAT_PLAN = preload("res://core/repeat/repeat_plan.gd")
const DELAY_QUEUE = preload("res://core/repeat/repeat_delay_queue.gd")


func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	await process_frame
	if not _test_queue_retains_requests_with_capacity():
		quit(1)
		return
	if not _test_queue_discards_overflow():
		quit(1)
		return
	print("通过：普通复读队列容量保留与溢出丢弃两项单元测试")
	quit()


# 入队后更改源 Resource，已排队请求仍保留命中时的原句、数量、Tier 和寿命。
func _test_queue_retains_requests_with_capacity() -> bool:
	var queue: RepeatDelayQueue = DELAY_QUEUE.new(4)
	var plan: RepeatPlan = _make_normal_plan(3)
	if queue.enqueue_plan(plan) != 3:
		push_error("有剩余容量时普通复读计划没有完整入队")
		return false
	plan.original_line_id = &"changed"
	plan.planned_repeat_count = 99
	plan.generation_tier = 5
	plan.lifetime_seconds = 99.0
	var requests: Array[RepeatPlan] = queue.advance(RepeatDelayQueue.DELAY_CONFIG.maximum_delay_seconds + 0.1)
	if requests.size() != 3 or not queue.advance(100.0).is_empty():
		push_error("到期请求数量错误或重复派发")
		return false
	for request: RepeatPlan in requests:
		if request.original_line_id != &"line_capacity_fixture" or request.planned_repeat_count != 1 or request.generation_tier != 2 or not is_equal_approx(request.lifetime_seconds, 4.0):
			push_error("源计划变更污染了已入队的复读快照")
			return false
	return true


# 剩余容量不足时只保留容量允许的请求，并丢弃超出部分。
func _test_queue_discards_overflow() -> bool:
	var queue: RepeatDelayQueue = DELAY_QUEUE.new(3)
	var first_plan: RepeatPlan = _make_normal_plan(2)
	var overflow_plan: RepeatPlan = _make_normal_plan(2)
	if queue.enqueue_plan(first_plan) != 2:
		push_error("首个普通复读计划没有占用预期容量")
		return false
	if queue.enqueue_plan(overflow_plan) != 1 or queue.advance(RepeatDelayQueue.DELAY_CONFIG.maximum_delay_seconds + 0.1).size() != 3:
		push_error("普通复读队列没有丢弃超出容量的部分")
		return false
	return true


# 使用正式计划入口，测试夹具仅提供确定的命中数值。
func _make_normal_plan(repeat_count: int) -> RepeatPlan:
	return REPEAT_PLAN.create_normal_hit_plan(&"line_capacity_fixture", "容量测试原句", 2, repeat_count, 4.0)
