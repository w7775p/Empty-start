# SD-08 根据关卡剧情配置载入事件气泡对白

**状态：新需求已确认 · 待开发**
**类型：数据配置与主播对白**
**关联：SD-01、SD-03～SD-07、LC-10、02_主播关卡、20_主播气泡对白**

## 开始前先阅读以下文档
- `AGENTS.md`、`project.godot`、当前21系统README和SD-01完成日志
- `data/streamer_bubble_dialogue/bubble_dialogue_config.gd`、`bubble_dialogue_entry.gd`
- `data/level_configuration/level_profile.gd` 及当前关卡读取入口
- Google Sheets `02_主播关卡`、`20_主播气泡对白` 的当前表头及正式策划记录

## 已经实现的功能
- SD-01已经提供 `BubbleDialogueEntry`、`BubbleDialogueConfig`、`find_by_sentence()`、`find_by_event()` 与玩家命中复述入口。
- 02表已确定四关的 `story_config_id`：`story_level_001`～`story_level_004`。
- 20表已有发言方、主播ID、事件类型/触发键、原句ID、对白正文、优先级、时长、定时节点和启用状态；已增加 `story_config_id`、`line_order`，新增 `trigger_type=random_idle` 与 `random_weight` 支持双方独立随机闲聊（消费方为SD-07）。
- SD-03任务卡负责请求队列与关键剧情逐句完整播放；SD-05、SD-06、SD-07任务卡分别负责命中原句、战斗状态和定时/随机闲聊的消费，实现状态按最新main和完成日志核对。

## 本次任务

### 触发条件
当前关有有效 story_config_id，20表存在与本场 streamer_id 匹配且 enabled 的剧情对白时；空表则读取合法空配置。

### 预期行为
本卡交付02与20表的 story_config_id、streamer_id 双重校验、trigger_type/trigger_key/source_word_id/trigger_time_s及line_order有序映射、SD-01 BubbleDialogueConfig和本场查询接口。SD-03接收有序配置后执行剧情逐句播放及完成通知；SD-05/06/07分别接收命中、状态与定时的静态事件映射。

1. 读取当前 `LevelProfile` 对应的02.`story_config_id` 与02.`streamer_id`，筛选20表中 `story_config_id` 匹配、`enabled` 为真的本场对白；同时核对20.`streamer_id` 的本场对手归属，保证当前关只读取本场剧情。`streamer_id` 始终是关卡对手ID，玩家侧台词通过 `speaker_side=player` 表达，不以该字段改写为 `player`。
2. 将20.`speaker_side`、`text`、`source_word_id`、`priority`、`display_duration_s` 对应到已有 `BubbleDialogueEntry`；将 `trigger_type + trigger_key` 映射为稳定的SD-01 `event_id`，同时为SD-07提供 `trigger_time_s`。
3. 同一剧情配置、同一触发事件下，按正整数 line_order 升序提供连续对白查询结果和稳定排序列表，供SD-03顺序播放；队列完成通知由SD-03按其任务卡提供给CS-23。
4. 提供事件映射表及查询接口：hit_word关联source_word_id，供SD-05匹配实际命中；connect、tier_up、tier_down、win、lose供SD-06根据战斗状态查询；timed及trigger_time_s供SD-07的可暂停计时消费；random_idle及可选random_weight（留空按1）作为当前关双方随机闲聊候选供SD-07使用。
5. 当前关开播、重开、进入下一关时按新的 `story_config_id` 读取本场对白；与现有 `LevelProfile`、Sandbox和SD-01资源接口协调，使用同一静态配置供SD-03～07消费。

### 验收条件
- 四关读取对应剧情配置ID；有条目的关卡按本场ID和主播筛选，未填写正式对白的关卡可进入正常战斗。
- connect 的同事件多句配置按line_order升序读取，并可交给SD-03；SD-03的实际显示及向CS-23发送队列完成通知由其任务卡进行后续验收。
- hit_word、升降Tier、胜负与timed的event_id和相关配置可被各自的SD-05/06/07消费者按稳定键检索；实际触发与优先级显示按对应任务卡联调验收。
- 重开与切关重新选择剧情配置；不同关卡的同名事件读取各自台词。
- 随机闲聊按story_config_id、streamer_id、speaker_side分别筛出player/opponent两侧候选及正权重；由SD-07按权重实际随机触发。
- Godot 4.7.2完成导表、Resource加载、按主播查询与切关配置隔离的实际验收；后续剧情逐句表现及真实事件联动按SD-03～07独立验收。

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
- **正式内容**：四关剧情配置ID已预留，具体20表台词未填完时可正常进入战斗；验证数据导表、同事件 line_order 顺序读取、切关/重开配置隔离，记录后续 SD-03～07 待验收范围。
- **完成日志**：双主播气泡对话系统_SD-08_YYYY-MM-DD_log.md，记录每项表字段映射、事件键和实际运行资源验收。
提交SD-08日期日志，记录表字段映射、事件ID映射、顺序对白和本场切换的实际验收结果。
