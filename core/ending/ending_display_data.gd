class_name EndingDisplayData
extends RefCounted

const MAIN_ART_CONFIG = preload("res://data/ending/ending_main_art_config.gd")
const RELIGION_NAME_CONFIG = preload("res://data/ending/ending_religion_name_config.gd")
const JUDGEMENT_TEXT_CONFIG = preload("res://data/ending/ending_judgement_text_config.gd")
const SCRIPTURE_DISPLAY = preload("res://core/ending/ending_scripture_display_data.gd")
const IDENTITY_CLASSIFIER = preload("res://core/ending/ending_identity_result_classifier.gd")


# 组合已有查询结果与配置；圣典全空或配置留空时仍返回完整显示数据。
func build(
		tendency_state: TendencyState,
		scripture_data: ScriptureData,
		level_catalog: LevelCatalog,
		main_art_config: MAIN_ART_CONFIG,
		religion_name_config: RELIGION_NAME_CONFIG,
		judgement_text_config: JUDGEMENT_TEXT_CONFIG
	) -> Dictionary:
	return build_from_frozen_tendency({
		"primary_tendency_id": tendency_state.get_primary_tendency_id(),
		"secondary_tendency_id": tendency_state.get_secondary_tendency_id(),
		"is_primary_tied": tendency_state.is_primary_tied(),
		"has_no_effective_behavior": tendency_state.has_no_effective_behavior(),
		"opening_identity_tendency_id": tendency_state.opening_identity_tendency_id,
	}, scripture_data, level_catalog, main_art_config, religion_name_config, judgement_text_config)


# 接收 Session getter 的倾向副本，只读首次事实；不重建可变 TendencyState 或重算裁决。
func build_from_frozen_tendency(
		tendency_result: Dictionary,
		scripture_data: ScriptureData,
		level_catalog: LevelCatalog,
		main_art_config: MAIN_ART_CONFIG,
		religion_name_config: RELIGION_NAME_CONFIG,
		judgement_text_config: JUDGEMENT_TEXT_CONFIG
	) -> Dictionary:
	if tendency_result.is_empty():
		return {}
	var primary_tendency_id: String = str(tendency_result.get("primary_tendency_id", ""))
	var secondary_tendency_id: String = str(tendency_result.get("secondary_tendency_id", ""))
	var result_class: StringName = IDENTITY_CLASSIFIER.new().classify_frozen_result(tendency_result)
	var scripture_rows: Array[Dictionary] = SCRIPTURE_DISPLAY.new().build_from_scripture(
		scripture_data, level_catalog
	)
	# 正式圣典是否为空由 Scripture 公开列表确定，缺章行继续沿用 EN-04。
	var scripture_is_empty: bool = scripture_data.get_ordered_entries().is_empty()
	return {
		"primary_tendency_id": primary_tendency_id,
		"secondary_tendency_id": secondary_tendency_id,
		"is_primary_tied": bool(tendency_result.get("is_primary_tied", false)),
		"has_no_effective_behavior": bool(tendency_result.get("has_no_effective_behavior", false)),
		"opening_identity_tendency_id": str(tendency_result.get("opening_identity_tendency_id", "")),
		"main_art": main_art_config.get_main_art_for_tendency(primary_tendency_id),
		"religion_name": religion_name_config.get_religion_name(primary_tendency_id, secondary_tendency_id),
		"religion_description": religion_name_config.get_religion_description(primary_tendency_id, secondary_tendency_id),
		"identity_result_class": result_class,
		"judgement_text": judgement_text_config.get_judgement_text(result_class),
		"scripture": {
			"rows": scripture_rows,
			"is_empty": scripture_is_empty,
			"status": SCRIPTURE_DISPLAY.STATUS_NOT_FORMED_ORACLE if scripture_is_empty else SCRIPTURE_DISPLAY.STATUS_CONFIRMED_ORACLE,
		},
	}
