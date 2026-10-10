# INT-10 精简 Sandbox 根场景与联调测试接口

**状态：待开发 · Sandbox 架构重构第 4 张卡**  
**Owner：Lane A / Sandbox 集成**  
**前置：INT-09 合并并通过整局回归**  
**后续：战斗打磨、主播气泡对话、程序美术与 UI 接线任务**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`
- `docs/Original/任务卡模板.md`
- `docs/Integration/README.md`、`docs/Integration/INT-04_2026-10-09_log.md`
- `docs/开发计划_2026-10-09_任务卡依赖整合.md`
- `docs/Integration/tasks/INT-07_extract_divine_descent_flow.md`、`INT-08_extract_contradiction_oracle_flow.md`、`INT-09_extract_battle_attempt_flow.md` 及最新日志
- `scenes/sandbox/sandbox.gd`、`scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`
- `tests/integration/int_01_playable_battle_sandbox_test.gd`、`tests/integration/int_04_full_run.gd`、`ui/debug/debug_panel.gd`

## 已经实现的功能
- INT-07、INT-08、INT-09 将分别提供神降临、矛盾神谕和普通战斗的独立流程接口。
- `SandboxBattleHud` 已提供主播、PK/Tier、攻击状态与失败页面的显示方法。
- `RestResultView` 已提供战后展示、历史查看和继续请求；`SceneRouter` 已提供正式顶层入口。
- DebugPanel 使用 Sandbox 的 `get_debug_snapshot()`、`debug_*()` 和 `restart_current_attempt()`。
- INT-01 与 INT-04 已有可复用的真实 Godot 场景及 TEST_ONLY 集成测试。

## 本次任务
将 `Sandbox` 整理为顶层场景组合与流程交接入口，并把现有集成测试调整到稳定的业务公开接口。

1. 核对三组已提取流程的实际方法、signal、场景生命周期和数据所有权，绘制当前运行流程交接关系并更新 Integration 文档。
2. 在 `Sandbox` 集中完成现有组件创建与绑定、关卡运行入口、普通战斗 → 矛盾/神谕 → Rest → 下一关/神降临 → Ending 的顶层切换。
3. 让各流程分别管理自身阶段状态，由 `Sandbox` 根据公开结果确定当前顶层阶段及可用输入。
4. 将 RestResultView、BattleHud、LiveDataHud、PauseMenu、DebugPanel 的真实事件接入对应流程接口，保留现有界面与操作行为。
5. 为 DebugPanel 保留 `get_debug_snapshot()`、`debug_*()` 和 `restart_current_attempt()` 入口，以转发方式读取和操作真实状态所有者。
6. 更新 INT-01、INT-04 和相关测试对 `_hit_resolution`、`_repeat_queue`、`_contradiction_break`、`_final_oracle_session`、`_divine_descent_spread` 等内部字段的读取，统一经对应流程公开方法获得状态。
7. 保持 `sandbox.tscn` 当前对外节点路径与 TEST_ONLY 场景继承入口可用；核对 `BattleHud`、`BarrageArea`、`AttackChargeInput`、`AimReticle`、`OracleCandidateDisplay` 的节点引用及信号连接。
8. 按现有 `AGENTS.md` 协作方式明确后续修改归属：BG/RP 处理生成与复读，CS/流程模块处理阶段事实，SD 处理气泡，PA/UI 处理演出和展示，Sandbox 处理总场景接线。
9. 更新现行任务依赖文档中与 Sandbox 接线有关的 Owner 和前置关系，使 CS-14、CS-22、SD-06、PA-17～19、INT-06 等卡片能够对接实际公开接口。

## 验收条件
1. `Sandbox` 作为顶层场景启动后可以连接三个流程，普通战斗、矛盾/神谕、Rest、神降临和 Ending 的真实切换顺序正确。
2. DebugPanel 的当前关、PK、Tier、重开、生成与倾向调试操作可用，读取到的数值与实际系统一致。
3. INT-01 真正战斗场景验收、INT-04 两条整局路线以及 Rest/Ending 相关回归测试通过；重复确认、重复 Continue、重开、暂停和存档读回结果正确。
4. TEST_ONLY 派生场景、现有 `%` 唯一节点引用、窗口缩放下的输入及 HUD 显示保持可用。
5. 现有 `Sandbox` 跨系统协调函数归口到三个流程；战斗系统及表现组件拥有明确的修改入口与交接文档。
6. 正式 Windows Godot 4.7.2 场景启动与图形模式整局联调完成，提供原始测试输出、关键画面和对应提交记录。

## Godot 开发环境
- Godot 版本：4.7.2
- 脚本语言：GDScript
- 项目根目录：仓库根目录
- 目标平台：Windows / Android；本卡在 Windows 上完成真实运行验收
- Godot 工程操作 MCP：Godot-MCP-Native
- Godot 官方文档 MCP：godot_mcp

## 本卡专项执行要求
1. 从合并 INT-09 的最新 `main` 创建独立 branch，按当前工程确认根场景与三个流程的真实接口。
2. 基于原有 Node、Scene、Resource 和信号连接整理总场景，使跨系统流程及运行数据的来源清晰可追踪。
3. 对修改的脚本执行相关解析检查，对真实场景与 UI 执行 Windows Godot 运行验证，使用已有 INT-01/INT-04 测试证明回归。
4. 更新 `docs/Integration/README.md`、`docs/System_Collaboration.md` 及现行任务依赖文档，新增 `docs/Integration/Sandbox重构_INT-10_YYYY-MM-DD_log.md`。
5. 完成本卡后提交独立 PR，提供模块负责人、公开接口、回归结果和新需求派工入口。

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
汇报最终 Sandbox 根场景职责、三个流程的接口和所有权、调试与自动化测试更新、Godot 真实联调结果，以及后续打磨任务各自的程序修改位置。

提交与本卡功能对应的变更及 Godot 实际运行结果，维护本系统 README 和本卡完成日志。
- **改动文件**：逐个说明文件、Scene、Resource 与公开接口的修改。
- **场景 / 节点变化**：列出相关 Scene 和 Node 的增删调整。
- **当前能做什么**：给出本卡完成后的可验证能力。
- **还不能做什么**：写清未覆盖、未验证及需人工确认的部分。
- **验证结果**：记录 Godot MCP、CLI、真实运行及必要的人工/截图验收结果。
- **下一步建议**：只提出由本卡实际状态支持的工作。
- **任务交接**：更新对应系统 README，按 `系统名_任务卡_YYYY-MM-DD_log.md` 写入并提交日期日志，包含主要变更、验证结果、遗留项、接手入口与文档更新情况。
