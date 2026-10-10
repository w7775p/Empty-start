# LC-13 首关新手教学按步骤配置播放

**状态：规格确认，24表三步当前未启用；trigger_event/completion_event稳定ID和启用状态待策划确认后开发**
**类型：关卡配置 / 教学流程**
**关联：LC-10、现有 CombatAttack、AimReticle、Sandbox、24_新手教学配置**

## 开始前先阅读以下文档
- `AGENTS.md`、`project.godot`、`known_traps.md`
- `docs/2. LevelConfiguration/README.md`、`data/level_configuration/level_profile.gd`
- 现有 Sandbox、`AttackChargeInput`、`AimReticle` 的实际输入/命中接口
- Google Sheets `02_主播关卡`、`24_新手教学配置` 最新字段

## 已经实现的功能
- 第一关正式ID为 `level_001`，对手为 `alien`，保留完整的直播PK和Tier流程。
- 游戏已有瞄准、蓄力、发射和实际命中事件，Sandbox HUD 已有战斗提示显示区域。
- 02表的第一关 `tutorial_config_id=tutorial_level_001`；24表有瞄准、蓄力、发射三个待启用步骤草案。

## 本次任务

### 触发条件
当前关有已确认并在24表启用的教学步骤，且本场 LevelProfile 提供有效 tutorial_config_id 时。

### 预期行为
24 表的瞄准、蓄力和发射三步目前全部 disabled；trigger_event 与 completion_event 的稳定ID及其对应真实输入/攻击事件须先由策划和程序现有接口共同确认，然后才实施步骤处理。按照既有瞄准/蓄力/发射的事实推进并复用 Sandbox HUD 与周目存储入口，配置为禁用或未填写时首关正常进行战斗。

进入具有有效 `tutorial_config_id` 的关卡时，读取24表中启用的教学条目，按 `step_order` 依次响应真实 `trigger_event`，显示 `hint_text`，并在对应 `completion_event` 确认后推进到下一步骤。使用现有瞄准与攻击事件作为触发与完成事实，并在正式绑定时确立稳定事件ID。

提供本周目教学步骤完成记录，让战斗重开、关卡切换和已有教学完成状态与显示保持一致。提示与实际战斗共用同一个HUD和输入来源；PC及Android均从现有输入抽象取得操作事实。

### 验收条件
- 02表仅首关带有教学配置关联，按24表启用的步骤播放并依次完成。
- 瞄准、蓄力和实际发射触发分别来自真实输入；按顺序推进，重开时已完成步骤的处理符合当前周目记录。
- 其余三关使用正常PK流程；修改24表文本/顺序/启用状态后重新导表可以生效。
- Windows与Android相关输入和HUD提示经Godot实景验证。

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
- **数据开工前置**：24表三步启用值、trigger_event、completion_event 与稳定事件ID对应表须由策划明确；Agent 依据实际输入接口实现，不自行创造事件协议。
- **验收边界**：真实瞄准/蓄力/发射、暂停和重开的步骤状态由现有系统提供；正式 Windows/Android 结果按实测报告。完成日志：关卡配置系统_LC-13_YYYY-MM-DD_log.md。
提交LC-13日期日志，记录事件ID映射、配置来源与实际教学操作验收结果。
