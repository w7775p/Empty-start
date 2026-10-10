# LC-10 关卡正式导表与四关资源联调

**状态：需求已补齐 · 待正式数据完善后实施**
**类型：关卡配置与集成**
**关联：LC-12 / LC-13 / PA-15 / PA-17 / LD-12 / SD-08 / CS-28**

## 开始前阅读
- `AGENTS.md`、`known_traps.md`、`project.godot`
- `docs/2. LevelConfiguration/README.md`、`tools/README.md`
- `data/level_configuration/level_profile.gd`、`level_catalog.gd`、`level_run_state.gd`
- `tools/export_game_data.py`、`scenes/sandbox/sandbox.gd`
- 本任务关联的现行任务卡、完成日志，以及 Google Sheets 策划填表需求总表

## 已有基础
- LC-01～LC-09 的 `LevelProfile`、`LevelCatalog`、`LevelRunState` 和实际关卡推进接口已完成。
- 导表器已有 XLSX 校验、分表 CSV 及 TEST_ONLY 02/03/04/05 → `LevelProfile` / `LevelCatalog` 路径。
- Sandbox 已读取当前关卡的主播名、立绘、直播背景、粉丝牌、词库和矛盾内容。
- Google Sheets 的02表已确定四关顺序：`level_001 / alien`、`level_002 / kiwi`、`level_003 / frog`、`level_004 / fox`。正式运行目录当前仍为两关示例。
- 02表精简为15列；23_对手立绘配置、24_新手教学配置已建立；19_直播评论词库新增可选 `streamer_id`。
- 05_关卡生成与11_矛盾参数中的现有首关记录统一为 `level_001`。

## 本次任务
1. **正式导表：**按最新 Google Sheets 源字段更新 `tools/export_game_data.py` 的02表结构及必要的新表入口，使02/03/04/05/11/23/24及相关消费者能使用同一套稳定 ID。02按现行15列导出，包含 `portrait_set_id` 和 `tutorial_config_id`；19表按 LD-12 增加可选 `streamer_id`。
2. **四关正式资源：**从02表生成或更新正式的四份 `LevelProfile` 及 `LevelCatalog.profiles`，保持 `level_order` 与 `level_id` 一一对应。关联03词库、04真假矛盾、05生成参数、11矛盾参数和已有吞并/奖励入口。
3. **阶段立绘组：**02.`portrait_set_id` 关联23.`portrait_set_id`，把已交付的 idle、tier_01～03、defeat 和可选过渡图加载为该对手的正式纹理配置，供 PA-15/17 按战斗事实读取。保留当前 `LevelProfile.streamer_portrait` 的待机兼容入口。
4. **首关教学：**02.`tutorial_config_id` 关联24表，向 LC-13 提供步骤配置与当前关卡身份。仅第一关已关联 `tutorial_level_001`；启用状态和事件ID由教学需求确认后填写。
5. **既有跨表引用：**20表通过当前 `streamer_id` 选择主播气泡对白（SD-08），21表以 `streamer_id + tier` 取得本场反击候选（CS-28），19表通过 `side_scope + 可选streamer_id` 选择直播评论（LD-12）。
6. **资源与容量：**`background_asset_id` 和 `fan_badge_asset_id` 映射现有对应纹理入口；05.`special_instance_screen_cap` 作为本关可选覆盖，空值沿用06.`special_foreground_instance_cap` 的全局数值，数值由策划后续建模确定。
7. **完整流程：**验收主场景首关进入、战败重开、Rest 继续、第四关完成后终局入口，主播切换时同步刷新背景、立绘组、粉丝牌、词库、评论、对白和反击候选。

## 验收
- 02表四个稳定关卡ID进入正式目录，正式Sandbox从 `alien` 开始并按 `kiwi → frog → fox` 依次推进。
- 已配置的三位对手可以按23表定位正确图片；`frog` 资源尚未交付时使用既有占位和默认动画入口。
- 02、03、04、05、11、19、20、21、23、24的引用按真实已填写数据解析；缺少待填文字/资源时报告对应表行与字段。
- 05和06的特殊实例容量覆盖规则可用，当前未定数值仍由策划填写。
- Godot 4.7.2正式资源加载、基础战斗及完整关卡推进验证通过；相关回归使用仓库已有最小测试入口。

## 完成记录
记录正式CSV和Resource关联结果、Windows/Android已实测范围、未填写字段及对应完成日志。
