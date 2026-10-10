# PA-17 真矛盾击破：对手三种专属击败演出与未击破离线

> 状态：需求已确认，待实施
> 类型：程序美术 / PresentationAssets
> 依赖：CB-07 `outcome_locked`、CB-09/CB-10 现有结果分流；PA-12 Paradox 结果提示；PA-15 阶段立绘映射

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md` 与最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/12. ContradictionBreak/README.md`、`docs/13. FinalOracle/README.md`（若有）
- `docs/Shared/PresentationAssets/tasks/PA-12_paradox-comic-transition-visual.md`
- `docs/Shared/PresentationAssets/tasks/PA-15_opponent-tier-portrait-flip-and-sweat.md`

## 已经实现的功能
- `ContradictionOracleFlow` 接收 `ContradictionBreakSystem.outcome_locked` 并公开 `outcome_resolved(outcome)`、`oracle_opened(session)`、`rest_ready(result)`；Sandbox 保持场景路由职责。
- `scenes/sandbox/sandbox_battle_hud.gd` 已有 `OpponentPortraitArt`、`set_opponent_portrait_connected()`；PA-14 的 `opponent_portrait_motion` 为动效容器。
- 外星人融化图、狐狸花瓣雨图、Kiwi 击败图及位置在本卡已有资源清单中；PA-12、PA-15 的过场和阶段贴图要求须按其实际开发状态接入。

## INT-10 / S3 接口交接（2026-10-11）
PA-17 继续由 PresentationAssets 持有角色演出；成功/未击破事实读取 `Sandbox.get_contradiction_oracle_flow().outcome_resolved`。演出完成后由 Sandbox 协调后续 FO 或 `rest_ready` 展示时序；当前尚无 PA 完成回调，需随动画实现定义并接入，不能假设现有 Flow 会等待视觉结束。

## 本次任务

### 最新策划配置来源（2026-10-10）
- 对手表现资源从 `02_主播关卡.portrait_set_id` 定位 `23_对手立绘配置`；使用其中 `defeat_asset_path`、可选 `defeat_transition_asset_path` 和 `defeat_effect_id` 选择本场演出。
- 已登记 `alien_melt`（外星人融化）、`kiwi_wobble`（Kiwi整图乱舞）、`fox_petal_rain`（狐狸花瓣雨）三种对手演出标识；具体美术与时序沿用本卡下述已确认需求。
- 第四关青蛙 `frog` 的专属素材和演出方案留待后续策划交付，再补到相同配置入口。


### 画面结果对应关系
- **进入 Paradox 时**，对手仍展示 T5 使用的 `{opponent}_tier_03.png`。
- **真实命中真矛盾并得到正式 BREAKTHROUGH 结果后**，才执行以下专属击败动画，动画结束时切至 `{opponent}_defeat.png`。
- **未击破（只中假句、落空、超时）时**，继续展示 T5 的 `tier_03`，播放短促离线演出；无需使用 defeat 图片。两种 Paradox 结果最终都遵照 PA-19 回房间结算，但成功方仍先走既有 FinalOracle 正式确认与奖励流程。

### 角色专属击败动画
#### 1. 外星人（alien）：融化
- 资源：`assets/characters/opponents/alien/alien_tier_03.png`、`alien_defeat_transition.png`、`alien_defeat.png`。
- 从 T5 立绘开始向下松弛、局部波动；短暂展示现有**融化过渡帧**，同时做边缘波形 / 向下拉伸、整体压扁坍塌；自然过渡到已经提交的倒地 / 融化完成图 `alien_defeat.png`。
- 使用现有 Tween / Shader 完成动态伸缩和软体扭曲，过渡时长、局部强度、画面震颤可调。

#### 2. 狐狸（fox）：花瓣雨
- 资源：`assets/characters/opponents/fox/fox_tier_03.png`、`fox_defeat.png` 与 `fox/effects/fox_rose_01～04.png`。
- 用**现有四张玫瑰 / 花瓣贴图**组合粒子流：上方和两侧先有少量花瓣飘入，继而一阵密集花瓣雨从上落下，粒子具有旋转、飘动、速度差、透明度变化。
- 花瓣形成短暂视觉遮挡时，右侧直播画面下的狐狸立绘切成 `fox_defeat.png`；花瓣逐渐散开，露出击败图。
- 采用 Godot 2D 粒子 / Node2D+Tween，数量、速度、大小与持续时间集中可调；保持 16:9 主画面可读。

#### 3. Kiwi：先用原 PNG 整图模拟乱舞（方案 A）
- 资源：`assets/characters/opponents/kiwi/kiwi_tier_03.png`、`kiwi_defeat.png`。
- 先使用**整张立绘**做左右剧烈摇晃、连续角度摆动与局部弹性扭曲（上半身 / 两侧翅膀区域摇摆、下半身节奏交错伸缩），让人视觉上感到翅膀和双腿同时乱甩；中途可辅以速度线。
- 摇摆动作频率逐渐加速再骤停，切入 `kiwi_defeat.png` 并回弹到稳定状态。
- 第一版用现有整图、Tween / Shader / 遮罩实现；**试玩后如果肢体动作不够明确，再由策划决定是否让美术只切 Kiwi 的必要肢体层**，美术切层目前为候选而非先决交付。

#### 4. Paradox 未击破：维持 T5 图后离线
- 在 `UNBROKEN` 结果出现后，保持现有 `tier_03`（T5）立绘，先显示 PA-12 的未击破漫画结果反馈，再让对手直播画面短暂信号波动、变暗 / 收拢至无信号状态，表现对手离线。
- 可复用 PA-11 的 CRT 视觉材料及现有右侧直播层；离线提示只属于对手画面局部。

### 接口与交接
- 使用现有 `ContradictionBreakSystem.outcome_locked` 与 Sandbox 结果分支读取胜负，播放对应视觉并向场景协调方发送**击败 / 离线演出完成**通知。
- 真击破后原有 CB-09 等复读展示、FO-13 终结神谕、FO 选择确认与奖励继续正常执行；本卡负责角色图和显示完成通知，PA-19 负责之后的直播结束转场。
- 未击破后接 CB-10 的休息时刻展示转场；两条路径结果状态以现有系统为准。

### 验收条件
- 进入 Paradox 时三名对手保持 T5 图；只有命中真矛盾才触发各自击败表演和 `defeat` 图。
- 外星人确实经过现有融化过渡帧；狐狸的四种花瓣组成飘落雨；Kiwi 用完整图变形做出明显乱舞动作。
- 只击中假矛盾、落空或超时始终不显示 `defeat`，保留 T5 图直至离线。
- 两条结果对应原有 CB / FO / Rest 流程；真实 Godot Windows / Android 演示通过。

## 本卡专项交付说明
新增 `docs/Shared/PresentationAssets/表现资产_PA-17_YYYY-MM-DD_log.md`，记录每名对手效果与是否需要后续 Kiwi 切图的验收判断。

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
提交与本卡功能对应的变更及 Godot 实际运行结果，维护本系统 README 和本卡完成日志。
- **改动文件**：逐个说明文件、Scene、Resource 与公开接口的修改。
- **场景 / 节点变化**：列出相关 Scene 和 Node 的增删调整。
- **当前能做什么**：给出本卡完成后的可验证能力。
- **还不能做什么**：写清未覆盖、未验证及需人工确认的部分。
- **验证结果**：记录 Godot MCP、CLI、真实运行及必要的人工/截图验收结果。
- **下一步建议**：只提出由本卡实际状态支持的工作。
- **任务交接**：更新对应系统 README，按 `系统名_任务卡_YYYY-MM-DD_log.md` 写入并提交日期日志，包含主要变更、验证结果、遗留项、接手入口与文档更新情况。
