# PA-15 对手阶段立绘：T2 漫画汗滴与卡牌翻转切图

> 状态：程序美术组件与 HUD 接口已实现；正式 23 表接线和 Android 实景验收待完成
> 类型：程序美术 / PresentationAssets
> 依赖：CombatStage `tier_state_changed`、现有对手立绘入口、PA-11 升降档演出

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md`、最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/Shared/PresentationAssets/tasks/PA-11_stage-transition-visuals.md`
- `docs/8. CombatStage/README.md`、现有 `CombatStageTierConfig` / `CombatStageTierCatalog`

## 正式运行 Tier → 对手立绘映射
| 运行阶段 | 显示 |
| --- | --- |
| T0 | 无对手立绘，使用等待连线状态 |
| T1 | `{opponent}_idle.png` |
| T2 | **仍为 `{opponent}_idle.png`，额外叠加漫画汗滴** |
| T3 | `{opponent}_tier_01.png` |
| T4 | `{opponent}_tier_02.png` |
| T5 | `{opponent}_tier_03.png` |
| T6 / Paradox | **保留 T5 的 `tier_03` 立绘**，结果明确之后按 PA-17 演出；仅真矛盾成功时才能使用 `defeat` |

`{opponent}` 按当前关的外星人 `alien`、Kiwi `kiwi`、狐狸 `fox` 等稳定角色类型选择。美术文件名里的 `tier_01` 是变化版本 1，并非战斗 T1。

## 已经实现的功能
- `scenes/sandbox/sandbox_battle_hud.gd` 已有 `OpponentPortraitArt`、`configure_streamer_assets()`、`set_opponent_portrait_connected()` 与 `refresh_pk(player_pk,current_tier)`；`CombatStage.tier_state_changed` 是正式阶段事件。
- PA-14（PR #109 已合并）的 `systems/presentation/streamer_portrait_motion.gd` 与 `opponent_portrait_motion` 提供可复用整图动画容器。
- 正式对手 PNG 位于 `assets/characters/opponents/{alien,kiwi,fox}/`；T2 汗滴与跨阶段翻面属于本卡待实施能力，并与 PA-11、#115 的阶段数据接线衔接。

## 本次任务

### 最新策划配置来源（2026-10-10）
- `02_主播关卡.portrait_set_id` 关联 `23_对手立绘配置.portrait_set_id`；23表每组记录所属 `streamer_id`、idle、tier_01～03、defeat、可选击败过渡图与 `defeat_effect_id`。
- 当前已登记 `portrait_alien`、`portrait_kiwi`、`portrait_fox` 三组正式素材路径；第四关 `frog` 的阶段图片与专属演出由策划、美术后续补充。
- 按23表的阶段图实际加载纹理并在 T1/T2/T3/T4/T5/T6 映射中使用；从现有 `LevelProfile.streamer_portrait`、`OpponentPortraitArt`、PA-14动效层复用入口。
- 阶段图标识是图片变化版本，不作为额外战斗Tier；当前关角色类型来源为02.`streamer_id`。

### 1. T2 漫画流汗
- 当对手进入 T2，在待机立绘头部附近绘制**一到两滴醒目的漫画水滴状汗珠**，使用程序绘制带高光 / 描边的水滴、多帧透明度和少量下滑，表现对手开始紧张。
- 汗滴跟随立绘位置与缩放变化；可以周期性缓慢出现、下滑、淡出，频率可调。
- 升档至 T3 后，贴图切为 `tier_01`，汗滴随之淡出；降回 T2 后恢复 idle + 汗滴；回 T1 不再显示汗滴。

### 2. 有图像变化时的立绘卡牌翻转
- 对当前旧立绘做**快速横向压扁 / 仿卡牌绕 Y 轴翻转 → 最窄点更换 Texture → 横向展开并轻微过冲回弹**。
- 换图完成瞬间配合 **PA-06 / PA-09 已确定风格的漫画受击冲击线 / 尖锐图形**短促弹出，再消隐；可从已有手绘视觉参数取色，保证与角色动效协调。
- T2→T3、T3→T4、T4→T5 及反方向跨越不同贴图时有明显翻转；T1↔T2 保持同一张 idle，只用汗滴出现 / 消失及小幅受击震颤，而非无意义重复翻同图。
- 跨多个 Tier 时根据最终实际阶段只显示一次对应落点画面，保持与 PA-11 箭头、PA-13 仓鼠球响应同步。

### 3. 与阶段事件同步
- 源数据读取当前对手外观与 `CombatStage` 的真实阶段，刷新现有 `OpponentPortraitArt` 的 Texture。
- T0→T1 由 PA-11 先播中央箭头和 CRT 接入，再显示 idle；普通升降档保留 PA-11 既有画面与清屏时序。
- 使用现有立绘容器与 Tween、AnimationPlayer、轻量 Shader；调参入口包含翻转时长、最窄比例、回弹、漫画冲击强度、汗滴位置 / 频率。

### 验收条件
- 在 T0～T5 逐档升降时，T2 为 idle+漫画汗滴、T3 为变化图 01、T4 为 02、T5 为 03；T1↔T2 不更换底图。
- 不同底图切换有清楚的卡片翻面动效与漫画冲击；临界档位快速变化能够正确显示最终素材。
- 正式 Paradox 开始时仍显示 T5 图，击破胜负由 PA-17 接手；支持当前角色资源缺失时的现有占位。
- Windows / Android 实景验证无丢图 / 错位。

## 本卡专项交付说明
新增 `docs/Shared/PresentationAssets/表现资产_PA-15_YYYY-MM-DD_log.md`，注明阶段图片、绘制汗滴、翻转参数及实测。

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
