## TEST_ONLY CSV 与关卡 / 词库的字段及引用比对；成功仅证明测试数据转换。
extends SceneTree

const CATALOG_PATH := "res://data/test_only/generated/level_configuration/test_only_level_catalog.tres"
const CSV_FIRST := "res://data/test_only/source_tables/03_普通词库.csv"


func _initialize() -> void:
    # 测试资源的真实 ID 必须统一带 test_，防止误认作正式内容。
    var catalog: LevelCatalog = load(CATALOG_PATH) as LevelCatalog
    if catalog == null or catalog.profiles.size() != 2:
        _fail("TEST_ONLY 关卡目录读取失败")
        return
    var record_count: int = 0
    var expected: Dictionary = {"test_level_01": 8, "test_level_02": 4}
    var all_ids: Dictionary = {}
    var pool_by_id: Dictionary = {}
    for profile: LevelProfile in catalog.profiles:
        if profile == null or not expected.has(profile.level_id):
            _fail("出现非 TEST_ONLY 关卡")
            return
        if not profile.streamer_id.begins_with("test_"):
            _fail("主播 ID 缺少 test_")
            return
        if profile.normal_speech_pool_source == null:
            _fail("关卡未链接生成式词库")
            return
        var speeches: Array[LevelSpeech] = profile.get_normal_speech_pool()
        if speeches.size() != expected[profile.level_id]:
            _fail("词库条数或关卡引用错误：" + profile.level_id)
            return
        if profile.true_contradictions.size() != 1 or profile.false_contradictions.size() != 1:
            _fail("真假矛盾配对错误：" + profile.level_id)
            return
        for speech: LevelSpeech in speeches:
            if speech == null or not speech.original_sentence_id.begins_with("test_"):
                _fail("发现非测试原句 ID")
                return
            if all_ids.has(speech.original_sentence_id):
                _fail("发现重复原句 ID")
                return
            all_ids[speech.original_sentence_id] = speech
            pool_by_id[speech.original_sentence_id] = profile.normal_speech_pool_source.pool_id
            record_count += 1
    var file: FileAccess = FileAccess.open(CSV_FIRST, FileAccess.READ)
    if file == null:
        _fail("TEST_ONLY 词库 CSV 缺失")
        return
    var header: PackedStringArray = file.get_csv_line()
    if header != PackedStringArray(["word_id", "text", "tendency", "strength", "pool_id", "weight", "source_streamer_id", "enabled", "notes"]):
        _fail("TEST_ONLY CSV 字段漂移")
        return
    var csv_count: int = 0
    var csv_ids: Dictionary = {}
    while not file.eof_reached():
        var cols: PackedStringArray = file.get_csv_line()
        if cols.size() > 1 and cols[0].begins_with("test_"):
            if cols.size() != header.size():
                _fail("CSV 行缺少字段：" + cols[0])
                return
            if cols[7] != "true":
                continue
            csv_count += 1
            if not all_ids.has(cols[0]) or csv_ids.has(cols[0]):
                _fail("CSV 与 Resource 不一致：" + cols[0])
                return
            csv_ids[cols[0]] = true
            var speech: LevelSpeech = all_ids[cols[0]]
            var tendency: String = "heretical" if cols[2] == "heresy" else cols[2]
            if speech.text != cols[1] or speech.tendency_id != tendency or speech.strength != int(cols[3]) or not is_equal_approx(speech.appearance_weight, float(cols[5])) or pool_by_id[cols[0]] != cols[4]:
                _fail("CSV 字段或跨池引用漂移：" + cols[0])
                return
    if csv_count != record_count:
        _fail("CSV 与 Resource 记录数不一致")
        return
    print("PASS TEST_ONLY 2 LevelProfiles, 2 speech pools, ", record_count,
          " speech records with CSV fields/pool links; formal content UNVERIFIED.")
    quit(0)


func _fail(message: String) -> void:
    push_error("FAIL TEST_ONLY integration: " + message)
    quit(1)
