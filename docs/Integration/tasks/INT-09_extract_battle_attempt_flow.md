# INT-09 提取普通战斗与单次尝试流程

**状态：待开发 · Sandbox 架构重构第 3 张卡**  
**Owner：Lane A / Sandbox 集成**  
**前置：INT-08 合并并通过整局回归**  
**后续：INT-10**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`
- `docs/Original/任务卡模板.md`
- `docs/Integration/README.md`、`docs/Integration/tasks/INT-04_test_only_full_run.md`
- `docs/6. HitResolution/README.md`、`docs/7. OpponentPKBar/README.md`、`docs/8. CombatStage/README.md`、`docs/10. Repeat/README.md`
- `docs/3. BarrageGeneration/README.md`、`docs/5. CombatAttack/README.md`、`docs/9. LiveDataPresentation/README.md`
- `docs/Integration/tasks/INT-08_extract_contradiction_oracle_flow.md` 及其最新完成日志
- `scenes/sandbox/sandbox.gd`、`scenes/sandbox/sandbox_battle_hud.gd`、`tests/integration/int_01_playable_battle_sandbox_test.gd`

## 已经实现的功能
- `Sandbox.restart_current_attempt()` 负责当前关卡失败与继续后的尝试重建，使用 `HitResolution`、`CombatStage`、`OpponentPKBar` 和 `RepeatDelayQueue`。
- `AttackChargeInput` 提交每发目标结果；`HitResolution` 计算 PK 和命中结果；Tier 状态由 `CombatStage` 更新。
- `Sandbox` 根据整发结果记录倾向、创建普通复读、更新 HUD；PK 满值时提交复读历史和粉丝、结束普通战斗，交接矛盾阶段。
- 失败时会处理本场暂存回滚和重开；已提交周目成果由原有 `SaveData` 保存。

## 本次任务
将普通战斗 T0～T5 的单次尝试生命周期提取为 `BattleAttemptFlow`，把普通命中、Tier、复读与失败交接从 `Sandbox` 迁入该组件。

1. 核对 `restart_current_attempt()`、`_process()` 中的普通战斗部分、`_on_shot_hit_resolution_submitted()`、`_on_final_player_pk_updated()`、`_complete_normal_combat()`、`_on_attempt_failed()` 和 `_stop_normal_combat()` 的现行执行顺序。
2. 建立 `BattleAttemptFlow`，负责当前关卡尝试的创建、启动、推进、结束与重建；使用现有 `HitResolution`、`CombatStage`、`OpponentPKBar`、`RepeatDelayQueue` 作为实际状态所有者。
3. 接入现有 `BarrageArea`、`AttackChargeInput`、`AimReticle`、关卡配置和周目数据，按现有规则启动普通弹幕生成、设置攻击时长和对手回拉。
4. 让整发命中完成入口统一协调有效目标移除、倾向暂存、复读计划生成及 PK/Tier 完成结果；对外通知本发结算完成的事实，并提供最新 Tier 与本发结算数据。
5. 显式保证当前整发 PK 更新、Tier 更新、本发复读计划登记及阶段切换的顺序，为 CS-18/CS-14 的升档清屏接线提供稳定的完成时点。
6. 提供正常结束、PK 满值、战败及尝试重开结果通知；把阶段所需的同一份 `HitResolution` 和复读统计交给已完成的 `ContradictionOracleFlow`。
7. 将直播观众、点赞及评论等表现数据沿用原有 `LiveSessionData` 入口，并通过可订阅事件向 `SandboxBattleHud` 交付展示结果。
8. 维护失败回滚、同关重试、正式粉丝与复读历史提交、下一关初始化的现有时序和同一周目状态。
9. 调整相关 INT-01、INT-04 测试对普通战斗状态的读取，使用单次尝试流程的稳定公开接口。

## 验收条件
1. 新周目开播及 Rest 下一关继续都能初始化正确的 `LevelProfile`、PK、Tier 0、普通弹幕与攻击状态。
2. 单发、多目标、复读零收益、遮挡、PK 增减与 Tier 变化按原真实结算链运行，完整一发的最终事实能够被后续升档演出读取。
3. PK 满值只推进一次矛盾阶段，冻结和清理顺序保持现有 CS-11/CS-12 的运行结果。
4. PK 归零失败后展示失败 UI，重开后恢复本关战斗，已提交粉丝、经文、卡片和吞并成果继续存在。
5. 暂停、蓄力、攻击到达、复读等待和时间推进在真实 Godot 场景中通过；INT-01、INT-04 两条路线完整通过。
6. 后续 CS-14～16、CS-18～29 的接线可以订阅普通战斗公开事实，并调用本组件提供的阶段操作入口。

## Godot 开发环境
- Godot 版本：4.7.2
- 脚本语言：GDScript
- 项目根目录：仓库根目录
- 目标平台：Windows / Android；本卡在 Windows 上完成真实运行验收
- Godot 工程操作 MCP：Godot-MCP-Native
- Godot 官方文档 MCP：godot_mcp

## 本卡专项执行要求
1. 从合并 INT-08 的最新 `main` 建立独立 branch，核对当前战斗组件构造、信号绑定与启动时序。
2. 使用同一份单次尝试数据和周目状态，通过公开方法及已发生事实的 signal 对接其余阶段。
3. 对上行/下行 Tier、PK 满值、PK 归零、重复事件及重开做定向验证；再执行 INT-01 和 INT-04 回归。
4. 更新 `docs/Integration/README.md` 的普通战斗职责和跨阶段交接，新增 `docs/Integration/Sandbox重构_INT-09_YYYY-MM-DD_log.md`。
5. 完成本卡后提交独立 PR，并附 Windows Godot 真实运行证据。

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
汇报普通战斗流程组件、整发完成时点、对矛盾阶段的交接接口、失败与重开的实测结果，以及 INT-10 可以直接连接的接口。

提交与本卡功能对应的变更及 Godot 实际运行结果，维护本系统 README 和本卡完成日志。
- **改动文件**：逐个说明文件、Scene、Resource 与公开接口的修改。
- **场景 / 节点变化**：列出相关 Scene 和 Node 的增删调整。
- **当前能做什么**：给出本卡完成后的可验证能力。
- **还不能做什么**：写清未覆盖、未验证及需人工确认的部分。
- **验证结果**：记录 Godot MCP、CLI、真实运行及必要的人工/截图验收结果。
- **下一步建议**：只提出由本卡实际状态支持的工作。
- **任务交接**：更新对应系统 README，按 `系统名_任务卡_YYYY-MM-DD_log.md` 写入并提交日期日志，包含主要变更、验证结果、遗留项、接手入口与文档更新情况。
