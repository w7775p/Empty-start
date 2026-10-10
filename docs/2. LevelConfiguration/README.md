# 2. LevelConfiguration 关卡配置系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。已实现的基础卡用于接口复查；新的视觉、静止弹幕、对话与阶段打磨以最新单卡和此表为准。

## 2026-10-09 现行实现核对与任务状态

**数值来源：** `LevelProfile.normal_barrage_screen_cap` 目前是整关基础容量；普通战斗 T0～T5 的各档前景容量统一由 `CombatStageTierConfig` 承接（CS-24），LC-11 归档为口径索引。关卡本身继续提供原句池、倾向权重和可用特性；LC-12 负责本关同屏特殊实例上限配置。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [LC-11](tasks/LC-11_tier-foreground-count-config.md) | 前景同屏容量配置入口归档到 CS-24 | 归档 |
| [LC-12](tasks/LC-12_special-trait-instance-cap.md) | 本关特殊实例同屏上限 | 待开发 |

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


## 系统目标

关卡配置系统负责回答三类问题：

1. **这一场是谁、有什么内容**：主播形象、主题、粉丝牌、词库、倾向比例、特殊玩法、真假矛盾。
2. **这一场基础怎么生成**：给弹幕生成系统提供基础数量、频率、速度和同屏上限；具体数值继续来自策划数值配置。
3. **这一场之后去哪**：当前关重开、当前关完成、下一关、全部普通关结束后的终局入口。

它是“关卡资料和关卡顺序”的来源，不负责真正生成弹幕、结算 PK、判定矛盾或播放终局。

## 当前仓库状态

- `LevelProfile`、`LevelCatalog`、`LevelRunState` 已实现，`data/level_configuration/` 提供可编辑的示例关卡。
- INT-01 Sandbox 持有当前 `LevelRunState`，普通战斗失败后原地重开同一关，关卡序号保持不变。
- RS-09 将 Rest 继续请求接到 `LevelRunState.complete_level(level_id)`；返回 `ADVANCED` 后 Sandbox 读取新的 LevelProfile 并在原场景重建该关尝试，保留 SaveData 已提交成果。最后普通关到神降临仍待 RS-10；第二关正式内容尚未补齐。
- 【吞并系统】【对手 PK 条系统】【休息时刻系统】【神降临系统】尚未实现时，与它们有关的任务卡只保留为后续联调任务，不提前制造临时跨系统接口。
- 身份系统任务卡已经拆分，但本系统不依赖身份系统才能先做静态关卡数据和关卡顺序。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| LC-01 | 定义关卡基础资料 | 无 |
| LC-02 | 定义本关词库与倾向比例 | 无 |
| LC-03 | 定义本关特殊玩法与真假矛盾内容 | 无 |
| LC-04 | 定义本关基础生成参数 | 无 |
| LC-05 | 当前普通关卡选择与读取 | 2 个关键单元测试 |
| LC-06 | 同一关只完成一次并推进 | 3 个关键单元测试 |
| LC-07 | 接入吞并后的继承内容 | 无新增自动化测试 |
| LC-08 | 接通当前关重开 | 无新增自动化测试 |
| LC-09 | 接通休息时刻后的下一关 / 终局入口 | 无新增自动化测试 |
| LC-10 | 正式导表与后续新增需求联调（未完成，暂缓） | 待策划确认后再定 |

## 测试预算

本系统只给“关卡推进状态”写单元测试，因为这里一旦出错会直接造成跳关、重复结算或进不了终局。

只测试：

- 默认读取第一关；
- 切换当前关后读取正确关卡；
- 一关第一次完成会推进；
- 同一关重复提交不会再次推进；
- 最后一关完成后会得到“普通关卡全部结束”的状态。

下面这些不逐项写单元测试：

- Resource 每个字段；
- 词库内容；
- 倾向比例具体数值；
- 美术资源引用；
- 真假矛盾文本；
- 生成参数字段；
- 与吞并、重开、休息、神降临的场景联调。

这些内容继续按任务卡做最小 Resource 加载、Godot 解析和实际流程验证。

## 依赖顺序

LC-01～LC-06 可以在其他战斗系统尚未完成时独立开发。

LC-07 等【14. 吞并系统】有真实输出后再做。

LC-08 等【7. 对手 PK 条系统】以及本场需要重置的战斗系统有真实重开流程后再做。

LC-09 等【18. 休息时刻系统】和【19. 神降临系统】存在真实入口后再做。

这样可以避免现在为了“以后要接”先造一批最后会被推翻的接口。

## 已实现的数据类型

LC-01 使用 `data/level_configuration/level_profile.gd` 定义 `LevelProfile` Resource，并提供 `data/level_configuration/level_001.tres` 作为可编辑示例。

基础资料包含稳定关卡 ID、关卡顺序、主播稳定 ID、主播显示名、主播立绘、头像、直播背景、直播主题、粉丝牌稳定 ID 和粉丝牌纹理。主播立绘、头像、直播背景分别由 `streamer_portrait`、`streamer_avatar`、`streamer_live_background` 引用；均为 `Texture2D`。对应主播素材未交付时可以暂留空值，资源到位后直接替换。粉丝牌也可先用稳定 ID 标识。

LevelProfile 保存静态关卡资料、普通话语池、倾向比例、特殊玩法标识、真假矛盾、前文线索和基础生成参数；当前周目进度由 LevelRunState 单独保存。

### LC-02 词库与倾向比例

`LevelProfile` 保存 `normal_speech_pool` 和普通话语类别比例；词库条目使用 `LevelSpeech` Resource，保存稳定 `original_sentence_id`、话语文本、可编辑的 `tendency_id`、`strength` 强度和 `appearance_weight` 相对权重。未填写强度的旧内容默认强度 1。

普通话语比例字段为 `orthodox_ratio`、`heretical_ratio`、`absurd_ratio`、`neutral_ratio`，类型均为浮点数；`neutral_ratio` 默认 0，旧关卡保持原生成结果。本数据类型只保存比例，不负责抽取、归一化或玩家倾向累计；具体内容与比例由策划填写。

前三项稳定 ID 沿用身份选项系统 ID-01 的字符串值：`orthodox`、`heretical`、`absurd`。普通话语额外允许 `neutral`，只表示内容类别，不作为开局身份或玩家三项倾向。`LevelSpeech.tendency_id` 保持字符串字段，不在关卡配置系统另建枚举。

### LC-03 特殊玩法与矛盾内容

`LevelProfile.special_trait_ids` 保存本关使用的特性稳定 ID 字符串，具体 ID 由现有 `BarrageTraitSet` 定义；本关启用列表和继承白名单分别配置。

真、假矛盾分别保存在 `true_contradictions` 与 `false_contradictions` 中；每项为 `LevelContradiction` Resource，含稳定 `original_sentence_id` 与文本。`contradiction_context_clues` 保存本关前文线索文本。矛盾真假判定和命中流程仍由矛盾击破系统负责。

### FO-11 继承配置前置

`LevelProfile.normal_pool_inheritance` 引用 `WordPoolInheritanceConfig`，只保存该关 `normal_speech_pool` 的继承元数据：稳定 `pool_id`、整池 `appearance_weight`、`can_inherit` 和 `is_contradiction_pool`。普通句子列表继续只有一个内容来源，真 / 假矛盾仍用各自独立字段；LevelSpeech 的单句权重不替代整池继承权重。

`LevelProfile.inheritable_trait_ids` 为独立 `Array[StringName]` 白名单，供真正击败结果读取。旧关卡默认配置 null / 空列表，不会自动获得词库或特性奖励。

`tests/fixtures/fo11/test_level_catalog.tres` 可以直接交给 `LevelRunState` 和其他已有关卡读取接口：首关含 TEST_ONLY 继承配置，第二关复用已有生产关卡。生产目录没有引用该 fixture；正式交付将配置填写到生产 LevelProfile 的同一字段。实际奖励、混词和兼容装配接线留对应后续卡。

### LC-04 基础生成参数

`LevelProfile` 提供 `base_batch_count`、`base_spawn_interval_seconds`、`base_move_speed_pixels_per_second` 与 `normal_barrage_screen_cap`。间隔字段单位为秒；普通话语与普通战斗陷阱共用同屏上限，复读上限由弹幕生成系统单独处理。

`LevelSpeech.appearance_weight` 保存同一倾向话语间的相对出现权重，`1.0` 表示默认等权值。三项比例用于倾向类别选择，两者分别配置。

示例值 `3` 条 / 批、`1.0` 秒间隔、`100` 像素 / 秒、同屏 `24` 条与权重 `1.0` 都是临时试玩默认值，等待策划实测调整。本类型不执行生成，也不包含 Tier 倍率和弹幕寿命。

### LC-05 当前普通关卡选择

#### AS-06 已提交吞并输入

`LevelCatalog.get_inherited_content_snapshot(current_run_data.assimilation_data)` 从 14 公开总量快照取已获得池 ID、整池权重和特性。池按现有 `normal_pool_inheritance` 解析，词句调用 `get_normal_speech_pool()`，兼容导表 LevelSpeechPool 和内嵌词库。导表的 pool_id 与继承元数据 ID 须保持一致，整池权重使用保存的提交值。

返回 `inherited_word_pools` 与 `inherited_trait_ids`；每个池带 `pool_id / appearance_weight / speeches`。静态目录缺项、禁止继承、矛盾标记或 ID 不匹配时该池不产生词句结果；没有成果时保持空数组。同池只返回一次，词句和成果列表均隔离于源数据。调用方提供完整关卡目录，查询不扫描目录文件、不建立新池注册表，也不修改当前关普通池。

Godot 4.7.2 smoke 已验证同一周目第一关真实 FO-11 提交后，通过现有 LevelRunState 完成并选择第二关，读取导表测试池、原权重、全部词句与特性。本卡只交付数据可消费能力，Sandbox 调用接线由 A 负责，实际混池 / 特性触发留后续联调。

#### 当前选择接口

`LevelCatalog.profiles` 保存普通关卡集合；每个 `LevelProfile.level_order` 使用唯一递增序号表示流程位置。`LevelRunState` 新建时选择序号最小的关卡，通过 `set_current_level_order()` 切换，并由 `get_current_level_profile()` 返回当前配置。

示例目录 `data/level_configuration/level_catalog.tres` 列出 `level_001.tres` 与 `level_002.tres`。本阶段只读取当前关卡，不推进、不结算，也不接入 UI。

### LC-06 同一关只完成一次并推进

`LevelRunState.complete_level(level_id)` 只接受当前关的首次完成：存在更大的 `level_order` 时返回 `ADVANCED` 并推进；重复提交返回 `ALREADY_COMPLETED`；最后一关返回 `ALL_NORMAL_LEVELS_COMPLETED`，`is_all_normal_levels_completed()` 同时报告结束状态。空白或未知 ID 返回 `INVALID_LEVEL`，已知但非当前关返回 `LEVEL_NOT_CURRENT`。

完成记录保存在单个 `LevelRunState` 实例中，以当前周目状态实例 + `level_id` 识别本次提交。去重状态不写入 SaveData；本类不调用休息时刻、终局或奖励系统。


## 2026-10-08 导表 TEST_ONLY 数据接入

策划源中，只有身份配置和系统案已明确的战斗规则可作为确定配置。其他关卡、台词、矛盾与资产等数据尚未定稿，联调使用 data/test_only/ 中的独立测试样例。

LevelProfile 新增可选 normal_speech_pool_source: LevelSpeechPool，使用 get_normal_speech_pool() 读取。存在词库 Resource 时读取其中的 LevelSpeech 列表，否则继续使用内嵌 normal_speech_pool；运行时保持静态 Resource 只读。

测试场景为 tests/fixtures/data_export/test_only_sandbox.tscn，注入测试关卡目录；正常主场景默认继续使用原关卡目录。导表方法、已实现映射、策划确认后的替换方式详见 tools/README.md。

## 2026-10-08 阶段记录：LC-10 正式导表待办（未完成）

当前导表工具已完成 Excel/XLSX → CSV 数据校验及 TEST_ONLY 02/03/04/05 → Godot 关卡 Resource 的联调路径。正式关卡与矛盾表尚无有效记录，生成数值仍待填写；正式运行关卡仍用占位配置。正式数据绑定和跨系统联调尚未完成。**此为旧阶段的暂停记录；现行字段、拆卡和开工条件以下方 2026-10-10 新需求和最新版 LC-10/LC-13 为准。**详见 `tasks/LC-10_pending-data-import-and-integration.md`。

## 2026-10-09 新确认规则与单功能任务卡

前景数量按 Tier 配置：T1=10、T2=13、T3=16，T4/T5 沿递增三条的规划为 19/22，T0 后续由策划填写。各档特性实例同屏上限独立可配，示例值为 1；一条话语同时拥有多项兼容特性仍按一条实例计数。

| 任务卡 | 唯一功能 | 状态 |
| --- | --- | --- |
| [LC-11](tasks/LC-11_tier-foreground-count-config.md) | 按 Tier 配置前景话语数量 | 待实施 |
| [LC-12](tasks/LC-12_special-trait-instance-cap.md) | 特殊特性话语的同屏实例上限配置 | 待实施 |

本轮任务卡逐项说明触发条件、应发生的行为与验收结果；派工时依赖最新卡片和系统当前代码。

## 2026-10-10 四关策划表与新接口（未开始正式导表）

当前策划 Google Sheets：`02_主播关卡` 已确定 `level_001/alien`、`level_002/kiwi`、`level_003/frog`、`level_004/fox`，四关均为正式PK，首关负责新手教学。战斗数值保留现有可调入口，待策划函数建模。

- **02表现行16列：**`level_id, level_order, streamer_id, streamer_name, portrait_set_id, tutorial_config_id, story_config_id, live_theme, fan_group_name, background_asset_id, word_pool_id, contradiction_set_id, enabled, notes, fan_badge_asset_id, 新需求对接状态`。原 `avatar_asset_id`、`special_play_id`、`loser_card_id` 已从策划表移除；败者卡用 `streamer_id`、反击池用 `streamer_id + tier`。
- **03_普通词库：**用于中央可击中的普通战斗弹幕，按 `pool_id` 构造 `LevelSpeechPool`，由02.`word_pool_id` 关联；正式源池归属与 `source_streamer_id` 映射按 LC-10 未决事项处理，保持与19直播评论和20事件对白分离。
- **23_对手立绘配置：**通过 `portrait_set_id` 关联 `streamer_id`，包含 idle、tier_01～03、defeat、可选过渡图和击败效果ID。已有 `alien`、`kiwi`、`fox` 记录，`frog` 的美术与演出之后补齐。由 PA-15/17 消费。
- **24_新手教学配置：**通过 `tutorial_config_id` 关联首关，提供步骤ID、顺序、触发事件、提示文本、完成事件与启用标记。当前三步为未启用草案；新增 [LC-13](tasks/LC-13_first-level-tutorial-steps.md) 负责读取真实输入事实并按事件推进。
- **05_关卡生成：**新增可选 `special_instance_screen_cap`，留空沿用06.`special_foreground_instance_cap`。对战前景总容量仍归08 Tier配置（CS-24）。
- **20/21/19表：**02.`story_config_id` 关联20表同名剧情配置ID，按本场主播校验归属；20的 `trigger_type/trigger_key`、指定原句、时间节点驱动SD-05～07，新增 `line_order` 保证同事件多句剧情对白按顺序显示（SD-08/SD-03）。反击候选按 `streamer_id + tier`（CS-28），直播评论按 `side_scope + 可选streamer_id`（LD-12）。
- 05与11的首关ID已统一为 `level_001`；现有正式 `.tres` 与导表器还需 [LC-10](tasks/LC-10_pending-data-import-and-integration.md) 对接四关及新表字段。

现有 Godot `LevelProfile` 类型和两关示例资源持续作为程序实现基础，正式资源随LC-10导表集成。

## 2026-10-10 新版主播粉丝团名称

策划总表的 `02_主播关卡.fan_group_name` 用于该关对手直播间**主播名右侧**的 `❤粉丝团名❤` 文字，原字段名 `fan_badge_text` 已弃用。PA-20 将把此名称接入 `LevelProfile` 和正式 BattleHud，玩家侧仍直接读取 `SaveData.fan_group_name`。对手 `fan_badge_id / fan_badge_texture` 与玩家共享资源 `player_fan_badge` 继续用于 LD-15 直播评论内粉丝身份标记。参见 `docs/Shared/PresentationAssets/tasks/PA-20_header-fan-group-name.md`。

## 2026-10-10 LC-14 普通导表来源隔离

`tools/export_game_data.py` 在普通导表和 `--test-only` 模式共用 `00_填写说明!A1` 的 TEST_ONLY 来源标记。普通模式发现该标记时，在解析和写盘前返回退出码 2，并保留现有正式 CSV；已标记工作簿继续由 `--test-only` 写入测试目录。`--output-root <目录>` 可将导出产物写入隔离根目录，默认仍为当前项目根目录。此修复只处理导表来源隔离；LC-10 正式关卡数据联调仍按对应任务卡暂停状态执行。
