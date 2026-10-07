class_name RepeatPlan
extends Resource

const ORIGINAL_LINE_PLACEHOLDER: String = "{原句}"

enum RepeatType { NORMAL, CONTRADICTION }

@export var original_line_id: StringName = &""
@export var original_line_text: String = ""
@export var display_text: String = ""
@export var repeat_type: RepeatType = RepeatType.NORMAL
@export var planned_repeat_count: int = 0
@export var generation_tier: int = 0
@export var lifetime_seconds: float = 0.0

# 每个复读条目的等待偏移；延迟队列负责按配置生成并读取这些时间。
@export var wait_offsets_seconds: PackedFloat32Array = PackedFloat32Array()


# 把本次命中的原句、结算档位和已解析配置值复制进普通复读计划。
static func create_normal_hit_plan(
		original_line_id: StringName,
		original_line_text: String,
		settled_tier: int,
		configured_repeat_count: int,
		configured_lifetime_seconds: float
	) -> RepeatPlan:
	var plan := RepeatPlan.new()
	plan.original_line_id = original_line_id
	plan.original_line_text = original_line_text
	plan.repeat_type = RepeatType.NORMAL
	plan.planned_repeat_count = configured_repeat_count
	plan.generation_tier = settled_tier
	plan.lifetime_seconds = configured_lifetime_seconds
	return plan


# 矛盾复读固定命中时的原句和独立数量 / 寿命配置，不与普通候选统计混用。
static func create_contradiction_hit_plan(
		original_line_id: StringName,
		original_line_text: String,
		settled_tier: int,
		configured_repeat_count: int,
		configured_lifetime_seconds: float
	) -> RepeatPlan:
	var plan := RepeatPlan.new()
	plan.original_line_id = original_line_id
	plan.original_line_text = original_line_text
	plan.repeat_type = RepeatType.CONTRADICTION
	plan.planned_repeat_count = configured_repeat_count
	plan.generation_tier = settled_tier
	plan.lifetime_seconds = configured_lifetime_seconds
	return plan


# 将原句填入策划模板并保存显示文本，计划始终保留原句 ID。
func apply_display_template(template: String) -> String:
	if not template.contains(ORIGINAL_LINE_PLACEHOLDER):
		push_warning("RepeatPlan: display template has no {原句} placeholder; using original line text.")
		display_text = original_line_text
		return display_text

	display_text = template.replace(ORIGINAL_LINE_PLACEHOLDER, original_line_text)
	return display_text
