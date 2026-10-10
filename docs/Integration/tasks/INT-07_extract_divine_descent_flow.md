# INT-07 提取神降临与结局转场流程

**状态：已完成 · PR #110 已合并 · 2026-10-10 · [完成日志](../Sandbox重构_INT-07_2026-10-10_log.md)**
**Owner：Lane A / Sandbox 集成**  
**前置：INT-04 Windows TEST_ONLY 整局联调通过**  
**后续：INT-08 → INT-09 → INT-10**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`
- `docs/Original/任务卡模板.md`
- `docs/Integration/README.md`、`docs/Integration/tasks/INT-04_test_only_full_run.md`、`docs/Integration/INT-04_2026-10-09_log.md`
- `docs/19. DivineDescent/README.md`、`docs/20. Ending/README.md`
- `docs/开发计划_2026-10-09_任务卡依赖整合.md`
- `scenes/sandbox/sandbox.gd`、`scenes/sandbox/sandbox.tscn`、`core/autoload/scene_router.gd`、`core/divine_descent/`、`tests/integration/int_04_full_run.gd`

## 已经实现的功能
- `Sandbox` 在最后一关 Rest Continue 后创建 `DivineDescentSession`，启用 `DivineDescentCombatMode`，按冻结历史进入扩散或空历史结局路线。
- `DivineDescentSpread` 已提供自动扩散、新话衰减、锁句、90% 收束、输入强化和全屏强调完成事件。
- `EndingSession.receive_final_state()`、`SceneRouter.goto_ending()` 已接通结局页面。
- INT-04 已有 Windows Godot 4.7.2 的两条 TEST_ONLY 完整路线及存档读回证据。

## 本次任务
将神降临阶段的生命周期和内部流程提取为独立的 `DivineDescentFlow`，由 `Sandbox` 组合使用。

1. 以最新 `main` 核对 `Sandbox` 的 `_enter_divine_descent()`、`_on_divine_convergence()`、`_finish_divine_descent()`、神降临输入分发、逐帧衰减和离树清理的现行行为及调用关系。
2. 建立一个与现有 Godot 场景结构匹配的神降临流程组件，统一持有当次 `DivineDescentSession`、`DivineDescentCombatMode`、`DivineDescentSpread` 的生命周期。
3. 通过公开入口接收当前关卡目录、现有战斗组件和已确定的终局配置；复用原有终局冻结、普通战斗关闭、扩散、收束及输入强化规则。
4. 对外提供明确的开始、逐帧推进、终局输入处理、停止和结果读取接口；以完成信号交付已接收冻结事实的 `EndingSession`。
5. 在 `Sandbox` 保留最后一关的顶层切换请求，调用流程组件的启动入口，并负责最终存盘和 `SceneRouter.goto_ending()`。
6. 同步更新引用神降临内部状态的测试调用，使测试通过稳定的流程接口读取同一 `Session` 和扩散状态。
7. 保留两条终局路线的完成顺序：空普通历史直接准备 Ending；存在有效历史时完成扩散、锁句、90% 收束和全屏强调后进入 Ending。

## 验收条件
1. `Sandbox` 可以启动独立神降临流程并收到一次完成通知，原冻结 `DivineDescentSession` 贯穿至 `EndingSession`。
2. 普通历史路线通过真实扩散、衰减、锁句、收束和全屏强调；空历史路线完成零收藏结局。
3. 神降临输入强化维持现有表现，终局期间的 PK、Tier、倾向、奖励与冻结快照保持 INT-04 已验收的结果。
4. 顶层场景切换后，神降临计时、生成和输入组件完成生命周期清理。
5. `INT-04` 两条路线、场景真实启动、存盘读回和现有神降临定向测试通过；记录 Godot 真实进程退出码、关键结果及相关 Output。

## 本卡完成结果（2026-10-10）
- [PR #110](https://github.com/w7775p/Empty-start/pull/110) 已合并，`core/divine_descent/divine_descent_flow.gd` 承载神降临流程、扩散与 Ending 接收；`Sandbox` 保留路由与持久化协调。
- [完成日志](../Sandbox重构_INT-07_2026-10-10_log.md) 列出了正式接口与 INT-08 接线入口。

## Godot 开发环境
- Godot 版本：4.7.2
- 脚本语言：GDScript
- 项目根目录：仓库根目录
- 目标平台：Windows / Android；本卡在 Windows 上完成真实运行验收
- Godot 工程操作 MCP：Godot-MCP-Native
- Godot 官方文档 MCP：godot_mcp

## 本卡专项执行要求
1. 使用独立 branch，从最新 `main` 开始，先确认受影响脚本、节点、Resource、信号与当前测试入口。
2. 通过 Godot 原生 Node / signal / 公开方法组合现有组件，保持每份运行事实的原有状态所有者。
3. 修改 `.tscn` 时核对节点 owner、引用与生命周期；修改脚本后运行相关解析、场景和整局回归。
4. 更新 `docs/Integration/README.md` 中的流程归属和交接接口；新增 `docs/Integration/Sandbox重构_INT-07_YYYY-MM-DD_log.md`。
5. 完成本卡后提交独立 PR，并交付对应实际验证记录。

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
汇报流程组件及根场景分别改动的文件、公开接口、神降临两条路线的实测结果、存盘及顶层转场结果，以及 INT-08 可直接使用的交接入口。

提交与本卡功能对应的变更及 Godot 实际运行结果，维护本系统 README 和本卡完成日志。
- **改动文件**：逐个说明文件、Scene、Resource 与公开接口的修改。
- **场景 / 节点变化**：列出相关 Scene 和 Node 的增删调整。
- **当前能做什么**：给出本卡完成后的可验证能力。
- **还不能做什么**：写清未覆盖、未验证及需人工确认的部分。
- **验证结果**：记录 Godot MCP、CLI、真实运行及必要的人工/截图验收结果。
- **下一步建议**：只提出由本卡实际状态支持的工作。
- **任务交接**：更新对应系统 README，按 `系统名_任务卡_YYYY-MM-DD_log.md` 写入并提交日期日志，包含主要变更、验证结果、遗留项、接手入口与文档更新情况。
