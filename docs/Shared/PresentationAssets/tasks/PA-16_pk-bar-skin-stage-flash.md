# PA-16 PK 条阶段贴图：短闪调色后换底板

> 状态：需求已确认，待实施
> 类型：程序美术 / PresentationAssets
> 依赖：现有 PK HUD / `refresh_pk()`、CombatStage 最终阶段通知；PA-13 仓鼠球指示器

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md`、最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/Shared/PresentationAssets/tasks/PA-13_pk-hamster-ball-indicator-animation.md`

## 当前素材
- `res://assets/ui/combat/pk_bar/pk_bar_pos_01.png`～`pk_bar_pos_06.png` 分别对应 T1～T5、Paradox。
- T0 对应的 0 号图片已向美术提出补交，收到后接入 `pk_bar_pos_00.png`；接入前保持可替换的现有底板。
- 玩家 PK 落在 0～10%、10～20%、20～30%、30～40% 时，分别使用 `pk_bar_neg_04.png`、`neg_03.png`、`neg_02.png`、`neg_01.png` 作为额外的玩家失势表现；具体边界统一处理，例如 [0,10)、[10,20)、[20,30)、[30,40)，40% 不属于负向覆盖。
- **显示优先级已确定**：玩家 PK **低于 40%** 时优先显示负向变体，覆盖对应普通 Tier 底板；玩家 PK **大于或等于 40%** 时显示当前正式阶段图。普通 Tier 的真实状态继续由 CombatStage 提供，负向图只改变 PK 条外观。

## 已经实现的功能
- 本卡原文所列的战斗 HUD、主播立绘、正式资产与阶段信号作为复用基础；以开工时真实资源/场景和最新日志核验。

## 本次任务
- **每次阶段底图发生变化**，先在 PK 条上播放短促明暗闪烁、颜色偏移 / 色相变化，再将原图替换为目标阶段底图，最后迅速恢复正常明度与配色。
- 闪烁、换图只作用于 PK 条背景层；上方 PA-13 的仓鼠球继续根据真实玩家 PK 位置移动、滚动或蹦跳，显示位置和表情独立于底板。
- 当玩家 PK 穿过 10%、20%、30%、40% 的负向区间边界时，按新的对应图切换；避免正常持续回拉每帧都重开闪烁，按**实际显示底板变化**触发一次短动画。
- 保持 `refresh_pk()` 的唯一数值驱动、原 PK 进度条实际占比以及对手 PK 百分比计算。选择显示底板时先判断玩家 PK 是否低于 40%，再在非负向范围使用当前 Tier；**从负向恢复到 40% 时重新显露此时的最新 Tier 贴图**。Tween / CanvasItem.modulate / 轻量 Shader 调参：闪烁次数、强度、色相偏移、换图点、动画时间、透明度。

### 验收条件
- T1～T5、Paradox 根据实际阶段显示对应 1～6 图；T0 兼容正式 0 号图未来补交。
- 玩家处于 [0%,40%) 时，按 -4、-3、-2、-1 四档看到实际对应负向贴图；PK 恢复到 40% 及以上立即回归当前 Tier 图。负向覆盖期间即便 Tier 变化，也能在恢复后显示最新正确的 Tier 图。
- 每次切换有明显但短促的“闪烁 → 调色 → 换图 → 稳定”反馈；PA-13 仓鼠球仍清楚可见且随 PK 实时滚动。
- Windows / Android 运行画面中，两侧主播、顶部 PK 和战斗场能正常显示。

## 本卡专项交付说明
新增 `docs/Shared/PresentationAssets/表现资产_PA-16_YYYY-MM-DD_log.md`，记录贴图映射、切换参数、效果和实测。

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
