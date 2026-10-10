# LC-10 关卡正式导表与四关资源联调

**状态：规格已确认 · 正式策划数据及依赖待完善后实施**
**类型：关卡配置与集成**
**关联：LC-12 / LC-13 / PA-15 / PA-17 / LD-12 / SD-08 / CS-28**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`
- `docs/2. LevelConfiguration/README.md`、`tools/README.md`
- `data/level_configuration/level_profile.gd`、`level_catalog.gd`、`level_run_state.gd`
- `tools/export_game_data.py`、`scenes/sandbox/sandbox.gd`
- 本任务关联的现行任务卡、完成日志，以及 Google Sheets 策划填表需求总表

## 已经实现的功能
- LC-01～LC-09 的 `LevelProfile`、`LevelCatalog`、`LevelRunState` 和实际关卡推进接口已完成。
- 导表器已有 XLSX 校验、分表 CSV 及 TEST_ONLY 02/03/04/05 → `LevelProfile` / `LevelCatalog` 路径。
- Sandbox 已读取当前关卡的主播名、立绘、直播背景、粉丝牌、词库和矛盾内容。
- Google Sheets 的02表已确定四关顺序：`level_001 / alien`、`level_002 / kiwi`、`level_003 / frog`、`level_004 / fox`。正式运行目录当前仍为两关示例。
- 02表现行16列包含 `portrait_set_id`、`tutorial_config_id`、`story_config_id` 与 `fan_group_name`（旧 `fan_badge_text` 已弃用）；23_对手立绘配置、24_新手教学配置已建立；20_主播气泡对白新增 `story_config_id`、`line_order`；19_直播评论词库新增可选 `streamer_id`。
- 05_关卡生成与11_矛盾参数中的现有首关记录统一为 `level_001`。

## 本次任务

### 触发条件
正式四关核心配置有可验证的有效记录并经负责人确认开始关卡数据导入时。

### 预期行为
本卡交付导表器、关卡静态字段、正式 LevelProfile / LevelCatalog 资源与稳定 ID 关联的最小集成。对应消费入口：PA-15/17 负责立绘动画，LC-13 负责教学步骤，LD-12/16 负责评论生成，SD-08/SD-03～07 负责剧情对白事件与队列，CS-28 负责反击抽取。本卡向这些消费方提供可验证的静态字段和关卡数据接口。

1. **正式导表：**按最新 Google Sheets 源字段更新 `tools/export_game_data.py` 的02表结构及必要的新表入口，使02/03/04/05/11/23/24及相关消费者能使用同一套稳定 ID。02按现行16列导出，包含 `portrait_set_id`、`tutorial_config_id`、`story_config_id` 与 `fan_group_name`；20表按SD-08导出 `story_config_id`、`line_order`、`trigger_type=random_idle` 与 `random_weight`，19表按LD-12导出可选 `streamer_id`。
2. **四关正式资源和战斗词库：**从02表生成或更新正式的四份 `LevelProfile` 及 `LevelCatalog.profiles`，保持 `level_order` 与 `level_id` 一一对应。关联03按 `pool_id` 分组的 `LevelSpeechPool`、02.`word_pool_id`、04真假矛盾、05生成参数、11矛盾参数和已有吞并/奖励入口；验证03启用词句、强度1～3、权重及旧类别 `heresy` 到 `heretical` 的映射。
3. **阶段立绘组：**02.`portrait_set_id` 关联23.`portrait_set_id`，把已交付的 idle、tier_01～03、defeat 和可选过渡图加载为该对手的正式纹理配置，供 PA-15/17 按战斗事实读取。保留当前 `LevelProfile.streamer_portrait` 的待机兼容入口。
4. **首关教学：**02.`tutorial_config_id` 关联24表，向 LC-13 提供步骤配置与当前关卡身份。仅第一关已关联 `tutorial_level_001`；启用状态和事件ID由教学需求确认后填写。
5. **剧情、评论和反击数据关联：**将02.story_config_id关联20表对应剧情组，并校验20.streamer_id、trigger_type、trigger_key、source_word_id、trigger_time_s、line_order 的导表值和本场归属；为SD-08、SD-03～07及SD-07提供双侧事件与随机闲聊数据，为CS-28提供21表的 streamer_id + tier + weight 字段，为LD-12提供19表的 side_scope 和可选 streamer_id。
6. **资源与容量数据：**background_asset_id 和 fan_badge_asset_id 映射现有纹理入口；05.special_instance_screen_cap 提供本关可选覆盖值，未填写时提供06.special_foreground_instance_cap的默认来源，供LC-12/BG-35消费；实际数值由策划后续建模。
7. **最小关卡流转验收：**验收主场景首关进入、战败重开、Rest 继续、第四关完成后终局入口，切关后提供新的 LevelProfile 与关联资源 ID，表现层数据消费由对应独立任务卡验证。

### 最新字段及03词库来源核对（2026-10-10）
- Google Sheets `02_主播关卡` 的现行16列中，`fan_group_name` 取代旧 `fan_badge_text`：主播信息区显示“主播名    ❤粉丝团名❤”；`fan_badge_asset_id` 只用于LD-15对手直播评论的粉丝牌图片。正式导表和HUD接线需要与 PA-20 / LD-15 的已确认规则一致。
- `03_普通词库` 的既定用途是中央**可击中的普通战斗弹幕**。导表按 `pool_id` 聚合为 `LevelSpeechPool`，02.`word_pool_id` 选择关卡使用的池；BG-02从当前关池中先按正统/异端/荒谬/neutral权重选类，再按同类单句`weight`抽词。它不属于19滚动直播评论或20剧情气泡，真/假矛盾仍由04单独提供。
- 策划已明确：03的普通话语全部是**主角可以在PK时选择说出的话**，不是对手的自有发言。当前344条的 `source_streamer_id=player` 符合内容归属；`pool_streamer_a` 是历史池ID，四关是否复用同一池与正式命名待策划确认。已有普通弹幕运行记录 `BarrageRuntimeRecord.source_id` 取当前对手 `LevelProfile.streamer_id`，正式联调时要明确该字段表示对战场次还是话语发言方，以实际需求维持一致标记。
- 正式导表验收包含：03启用词句映射、`heresy`旧类别转换为`heretical`、强度1～3、单句权重、合法ID关联与更换关卡后的词库刷新；具体PK收益和生成数量由现有战斗/Tier规则决定，词库只提供内容数据。

### 验收条件
- 02表四个稳定关卡ID进入正式目录，正式Sandbox从 `alien` 开始并按 `kiwi → frog → fox` 依次推进。
- 已配置的三位对手可以按23表定位正确图片；`frog` 资源尚未交付时使用既有占位和默认动画入口。
- 02、03、04、05、11、19、20、21、23、24的引用按真实已填写数据解析；20表的剧情配置、事件键和逐句顺序与本场ID对应；缺少待填文字/资源时报告对应表行与字段。
- 05和06的特殊实例容量字段及默认来源可验证，运行时同屏覆盖由LC-12/BG-35依据本卡导出字段验收；当前未定数值继续由策划填写。
- Godot 4.7.2正式资源加载、基础战斗及完整关卡推进验证通过；相关回归使用仓库已有最小测试入口。

### 2026-10-10 双侧随机闲聊输入说明
- 03仅存主角普通可击中候选发言；其真实命中由SD-04复述到主角侧，文本直接取命中的原句。
- 20独立管理双方随机闲聊及事件对白：`speaker_side=player / opponent`、`trigger_type=random_idle`、相对`random_weight`（空按1）；按本关`story_config_id`与对手`streamer_id`过滤。SD-08提供静态候选，SD-07负责双方随机计时和加权选取，SD-03继续统一管理优先级与显示队列。

## Godot 开发环境
- Godot 版本：4.7.2（开工核对 `project.godot`）
- 脚本语言：GDScript
- 项目根目录：仓库根目录（`project.godot` 所在目录）
- 目标平台：Windows / Android（基准分辨率 1920×1080，16:9）
- Godot 工程操作 MCP：`Godot-MCP-Native`
- Godot 官方文档 MCP：`godot_mcp`

## 执行要求
### 1. 先检查当前项目状态
- 确认当前 branch、未提交修改、已有实现；核对 `project.godot` 的版本、Autoload、插件、Input Map、渲染器。
- 检查相关 `.tscn`、`.gd`、`.tres`、`.res`、节点职责、信号与资源依赖；以真实工程和最新已合并代码为准。

### 2. 严格控制任务范围
- 本张卡只完成“本次任务”所定义的功能和验收；发现关联问题在日志中说明，按任务依赖单独处理。

### 3. 保持最小必要复杂度
- 依赖方向清晰、代码高内聚；拆分场景或脚本以独立变化、生命周期、状态、流程或复用等实际需求为依据。

### 4. 组合优于继承
- 根据现有结构，优先采用子节点、子场景、Resource、signal、公开方法组合行为；仅在明确的 is-a 关系中使用业务继承。

### 5. 保持场景边界
- 父场景协调生命周期与组合，子模块维护自身状态；跨系统通过公开接口、稳定 ID、signal 或数据对象协作。

### 6. 区分场景、逻辑和数据
- Node/Scene 承载场景行为，Resource 承载静态配置，普通脚本对象承载纯逻辑；新增 Autoload 需有真实跨场景生命周期需求。

### 7. 新增实现前按顺序检查
- 依次检查仓库已有实现、Godot 原生 API、已安装 addon/plugin 和语言标准能力；需要新实现时采用满足本卡的最小方案。

### 8. Godot API 不允许猜
- 对 Node、属性、方法、signal、枚举和版本行为存疑时，使用 `godot_mcp` 查询对应 Godot 官方文档并核实后实现。

### 9. 使用 Godot-MCP-Native 检查真实工程
- 涉及场景树、节点、Inspector、连接、运行状态与画面时优先使用 `Godot-MCP-Native` 实际检查；MCP 不可用时记录原因和可替代的 CLI / 人工验证。

### 10. 自动化与额外保障机制
- 优先复用既有测试入口；仅针对稳定可复现的规则补充必要自动化。视觉、动画、交互与手感以真实运行及人工验收为依据。
- hash、baseline、gate、contract 或额外框架必须有明确且可复现的失败依据。

### 11. 避免脆弱的 Godot 依赖
- 检查跨模块内部 NodePath、固定父级层级、节点名业务身份、跨场景 Node 引用和多余 Singleton 耦合；使用稳定公开接口协作。

### 12. 修改现有场景时尊重现有结构
- 修改前核对场景实例、继承、owner、Resource 内嵌/外部关系及信号连接来源，保留有效 UID、节点路径和现有引用。

### 13. 验证实际 Godot 行为
- 完成后检查脚本解析、Scene/Resource 加载、相关场景运行、Output/Debugger，以及本卡“验收条件”。
- 涉及 UI、动画、运动、输入或其他视觉表现时实际运行并保存必要截图；Headless 结果按其覆盖范围说明。

### 14. 完成前检查
- 复查范围、复用、复杂度、Scene/Resource 引用与信号方向、死代码和测试投入；确认本卡实际通过后提交。
- 每张开发任务使用独立 branch，按 `AGENTS.md` 提交对应系统的完成日志；合并前同步最新目标分支重新验证。

## 最终汇报
- **开工条件**：02/03/04/05/11 核心关卡记录与稳定ID齐备；03旧 `pool_streamer_a` 的344条词句尚需策划决定共用池或按对手拆池，再填写正式02.word_pool_id。frog 的独立美术和专属演出未交付时保留现有占位并列明欠交付；24表三步当前禁用，trigger_event/completion_event 的稳定ID尚待确认；19/20 正式文字未齐时作为可选空配置。
- **交付范围**：验证四关正式资源加载和既有切关/重开/Rest/终局入口；其他系统的直播评论、剧情事件执行、技能抽取和角色演出由独立任务卡验收。
- **完成日志**：提交关卡配置系统_LC-10_YYYY-MM-DD_log.md，说明有效字段、缺项、最小实测和下一位接手入口。
记录正式CSV和Resource关联结果、Windows/Android已实测范围、未填写字段及对应完成日志。
