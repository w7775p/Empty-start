extends SceneTree

const REQUIRED_PLAN_B_CSVS: Array[String] = [
	"res://data/plan_b/battle_type_matchups.csv",
	"res://data/plan_b/opponent_config.csv",
	"res://data/plan_b/retaliation_skill_map.csv",
	"res://data/plan_b/strength_success_rates.csv",
	"res://data/plan_b/word_pool.csv",
]
const EXPECTED_PC_SETTINGS: Dictionary = {
	"display/window/size/viewport_width": 1920,
	"display/window/size/viewport_height": 1080,
	"display/window/size/mode": 0,
	"display/window/size/window_width_override": 1280,
	"display/window/size/window_height_override": 720,
	"display/window/size/initial_position_type": 1,
	"display/window/size/resizable": true,
	"display/window/stretch/aspect": "keep",
}


func _initialize() -> void:
	call_deferred("_verify_packed_csvs")


# 从包外挂载的正式 PCK 打开每张 Plan B 原表，证明导出时保留了原始 CSV。
func _verify_packed_csvs() -> void:
	var failures: Array[String] = []
	for setting_path: String in EXPECTED_PC_SETTINGS:
		var actual_value: Variant = ProjectSettings.get_setting(setting_path, null)
		if actual_value != EXPECTED_PC_SETTINGS[setting_path]:
			failures.append("project setting %s was %s" % [setting_path, actual_value])
	for csv_path: String in REQUIRED_PLAN_B_CSVS:
		if not FileAccess.file_exists(csv_path):
			failures.append("missing %s" % csv_path)
			continue
		var csv_file: FileAccess = FileAccess.open(csv_path, FileAccess.READ)
		if csv_file == null:
			failures.append("cannot open %s: %s" % [csv_path, error_string(FileAccess.get_open_error())])
			continue
		var header: String = csv_file.get_line().strip_edges()
		var first_record: String = csv_file.get_line().strip_edges()
		csv_file.close()
		if header.is_empty() or first_record.is_empty():
			failures.append("empty header or data row in %s" % csv_path)

	if failures.is_empty():
		print("PASS PB-10 packed PC display settings: 1920x1080 logical, 1280x720 windowed, keep aspect")
		print("PASS PB-10 packed Plan B CSV: %d original files opened" % REQUIRED_PLAN_B_CSVS.size())
		quit(0)
		return
	for failure: String in failures:
		push_error("PB-10 packed CSV check failed: " + failure)
	quit(1)
