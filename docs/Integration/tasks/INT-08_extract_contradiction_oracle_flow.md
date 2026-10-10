# INT-08 提取矛盾击破、终结神谕与战后结算流程

**状态：待开发 · Sandbox 架构重构第 2 张卡**  
**Owner：Lane A / Sandbox 集成**  
**前置：INT-07 合并并通过整局回归**  
**后续：INT-09 → INT-10**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`
- `docs/Original/任务卡模板.md`
- `docs/Integration/README.md`、`docs/Integration/tasks/INT-04_test_only_full_run.md`、`docs/Integration/INT-04_2026-10-09_log.md`
- `docs/12. ContradictionBreak/README.md`、`docs/13. FinalOracle/README.md`、`docs/18. Rest/README.md`
- `docs/14. Assimilation/README.md`、`docs/15. Scripture/README.md`、`docs/16. LoserCard/README.md`
- `docs/Integration/tasks/INT-07_extract_divine_descent_flow.md` 及其最新完成日志
- `scenes/sandbox/sandbox.gd`、`systems/combat_attack/attack_charge_input.gd`、`tests/integration/int_01_playable_battle_sandbox_test.gd`

## 已经实现的功能
- PK 满值后 `Sandbox` 启动 `ContradictionBreakSystem` 的正式限时阶段；矛盾命中使用释放时冻结的真实目标事实。
- 真、假矛盾都创建有限复读；矛盾复读队列和场上可见实例结束后分别进入神谕或 Rest。
- `FinalOracleSession`、`FinalOracleSelectionTimer`、`FinalOracleConfirmationState` 和 `FinalOracleCandidateDisplay` 已支持候选显示、手动命中、超时选择及确认。
- 正式确认通过现有数据所有者提交普通历史、倾向、圣典、败者卡与吞并；未击破胜利进入对应 Rest 结果。

## 本次任务
将矛盾击破、终结神谕及战后成果提交提取为独立的 `ContradictionOracleFlow`，向 `Sandbox` 输出已就绪的 Rest 结果。

1. 核对 `Sandbox` 中矛盾攻击处理、结果锁定、矛盾复读展示等待、静音过渡、神谕候选选择及成果提交的完整调用顺序。
2. 建立 `ContradictionOracleFlow`，统一持有本阶段 `ContradictionBreakSystem`、`FinalOracleSession`、`FinalOracleSelectionTimer`、过渡 Timer 与相关流程状态。
3. 通过公开启动接口接收本关 `LevelProfile`、真实攻击组件、弹幕区域、复读队列与统计、普通命中历史、周目数据以及已有候选显示组件。
4. 对接原有矛盾射击快照、结果通知、真/假分支和等待条件，并提供可供表现系统订阅的阶段事实通知。
5. 复用现有 `FinalOracleConfirmationState` 与 `ScriptureData` 的确认接线，梳理一次确认到各数据所有者的写入条件与顺序；在实际提交入口核验成功条件、返回值及去重结果。
6. 为真击破确认与未击破胜利分别准备对应 `RestSession`，以 `rest_ready` 等明确结果通知交给 `Sandbox` 展示 `RestResultView`。
7. 在 `Sandbox` 保留 Rest 页面显示、继续下一关和末关进入神降临的顶层路由；将本阶段具体倒计时和候选状态读取转接到流程公开接口。
8. 同步调整 INT-01、INT-04 的矛盾/神谕断言及调试读取，覆盖阶段接口和真实结果对象。

## 验收条件
1. PK 满值后真实进入矛盾阶段，释放时只消耗一次正式发射机会，十秒窗口与已存在的真假判定规则正确运行。
2. 真击破等待矛盾复读离场后进入候选神谕，人工命中和超时选择均能完成一次确认，并生成正确的 Rest 结果。
3. 未击破的命中与超时路线按既有展示完成条件进入 Rest；普通历史与倾向在当前合法时点正式提交。
4. 同关重复结果通知、重复神谕确认、失败重开与下一关切换均得到原有去重、回滚及成果保留结果。
5. 本场神谕、圣典、败者卡和吞并成果的写入结果与整局测试一致；增加一个覆盖确认中途写入失败边界的定向回归。
6. INT-01 相关场景测试与 INT-04 两条路线通过，现有 Rest 历史查看与继续按钮可用。

## Godot 开发环境
- Godot 版本：4.7.2
- 脚本语言：GDScript
- 项目根目录：仓库根目录
- 目标平台：Windows / Android；本卡在 Windows 上完成真实运行验收
- Godot 工程操作 MCP：Godot-MCP-Native
- Godot 官方文档 MCP：godot_mcp

## 本卡专项执行要求
1. 从合并 INT-07 的最新 `main` 创建独立 branch，核对现有信号绑定、同步回调、`call_deferred()` 与实际运行顺序。
2. 以原有业务对象作为唯一事实来源，通过明确公开接口完成模块组合和结果交接。
3. 逐一验证真击破、未击破、神谕超时、重复确认及重开路径，记录真实 Godot 运行结果。
4. 更新 `docs/Integration/README.md` 的阶段与成果交接说明，新增 `docs/Integration/Sandbox重构_INT-08_YYYY-MM-DD_log.md`。
5. 完成本卡后提交独立 PR，附对应 Godot 运行与回归证据。

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
汇报矛盾/神谕流程组件、Rest 结果交接接口、奖励提交与去重的实测情况、INT-01/INT-04 回归结果，以及 INT-09 需要复用的阶段启动入口。

提交与本卡功能对应的变更及 Godot 实际运行结果，维护本系统 README 和本卡完成日志。
- **改动文件**：逐个说明文件、Scene、Resource 与公开接口的修改。
- **场景 / 节点变化**：列出相关 Scene 和 Node 的增删调整。
- **当前能做什么**：给出本卡完成后的可验证能力。
- **还不能做什么**：写清未覆盖、未验证及需人工确认的部分。
- **验证结果**：记录 Godot MCP、CLI、真实运行及必要的人工/截图验收结果。
- **下一步建议**：只提出由本卡实际状态支持的工作。
- **任务交接**：更新对应系统 README，按 `系统名_任务卡_YYYY-MM-DD_log.md` 写入并提交日期日志，包含主要变更、验证结果、遗留项、接手入口与文档更新情况。
