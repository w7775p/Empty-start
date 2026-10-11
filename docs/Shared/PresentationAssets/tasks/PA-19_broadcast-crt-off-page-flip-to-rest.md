# PA-19 直播结束：CRT 关机、向上翻页、回主角房间弹出结算

> 状态：需求已确认，待实施
> 类型：程序美术 / PresentationAssets
> 依赖：CB-10 未击破休息入口、FO 正式确认后的休息入口、现有 RS RestResultView 与 RestRoomEnvironment；PA-11 CRT 表现

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md` 与最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/12. ContradictionBreak/README.md`、`docs/13. FinalOracle/README.md`、`docs/18. Rest/README.md`
- `ui/rest/rest_room_environment.tscn`、`ui/rest/rest_result_view.tscn`
- `docs/Shared/PresentationAssets/tasks/PA-11_stage-transition-visuals.md`、`PA-17_opponent-breakthrough-defeat-performances.md`

## 两条合法入口
- **Paradox 未击破**：由现有 CB-10 结果进入战后休息；先播对应的 PA-12 未击破提示和 PA-17 对手离线，再执行本卡画面退出 / 回房间。
- **Paradox 真击破**：先播 PA-17 专属击败演出，然后继续原本的**终结神谕（FinalOracle）候选选择 / 确认和正式奖励提交**，在 FO 通过现有入口进入战后 Rest 时才执行本卡画面退出 / 回房间。
- 两条路径都进入**同一个已有的战后休息结算界面**，用真实 `RestSession` 结果、成果和既有继续逻辑显示。本卡向现有展示方提供视觉播放完成信号。

## 已经实现的功能
- `ContradictionOracleFlow.rest_ready(result)` 是神谕确认 / 未击破的统一 Rest 结果入口；Sandbox 的 `_on_rest_ready()` 将同一 `RestSession` 交给 `RestResultView.show_result()`。
- `ui/rest/rest_result_view.gd/.tscn` 提供 `RestResultView.show_result()`、`finish_result_performance()`、`continue_requested`；`ui/rest/rest_room_environment.gd/.tscn` 提供 `apply_tendency()` 和正式房间背景 `assets/environment/rooms/player_room_01.png`。
- `scenes/sandbox/sandbox_battle_hud.gd/.tscn` 提供左右视频区域；PA-11/12/17 的 CRT、Paradox、失败演出按任务实际进度衔接，本卡新增整屏翻页和回房间的表现序列。

## INT-10 / S3 接口交接（2026-10-11）
PA-19 保持 PresentationAssets 的转场所有权，Sandbox 继续控制阶段。由 `rest_ready` 收到的视觉完成通知协调何时调用 `RestResultView.show_result()`；当前根场景收到结果后会立即显示，PA-19 需在实现时定义并接入明确的完成回调。继续按钮仍经 `RestResultView.continue_requested` → `Sandbox._on_rest_continue_requested()` → `RestSession.continue_to_next_level()`。

## 本次任务
### 1. 直播画面 CRT 关机
- 在任一路径确认准备进入 Rest 画面时，左右主播直播画面依次或基本同步播放 **轻微扫描失真 → 画面骤暗 → 收缩为横向亮线 → 亮线灭掉黑屏**，让玩家清楚感觉一场直播正式结束。
- 优先复用 PA-11 的 CRT 开机 Shader / Tween，反向动画；右侧画面若此前已在未击破分支离线，保持其离线黑屏，只关闭仍开启的视频区域。
- 全程短促；扫描强度、闪亮时间、关机时长可集中配置。

### 2. 整屏向上翻页，揭开仓鼠房间
- CRT 结束后，采用**战斗画面作为一整页向上翻开的漫画分页**：战斗 UI 作为上层在向上翻 / 上滑中缩短或带轻微透视，底部露出已有 **主角房间背景** `res://assets/environment/rooms/player_room_01.png`。
- 可以使用 Shader / 遮罩 / Tween / 截取当帧画面，重点表现“从直播这一页翻回现实的房间”；沿用 1920×1080 的 UI 比例。翻页遮罩应覆盖战斗 HUD 以自然收场，房间露出后战斗 UI 不再覆盖它。
- 主角房间由现有 `RestRoomEnvironment` 负责，继续显示原有倾向色调和环境状态。

### 3. 房间到结算
- 翻页结束时，玩家先清楚看到房间画面，然后**从房间上方弹出 / 放大并回弹**现有战后结算 UI，使用原 `RestResultView.show_result()`、`finish_result_performance()` 等已有展示契约。
- 提供 `CRT 完成 → 翻页完成 → 允许打开结算 / 结算演出完成` 的明确顺序，避免重复启动、提前出现结果 UI 和与 Rest 的显示锁冲突。
- 不同结果由真实 `RestSession` 区分，视觉转场共用一套，结算文本、奖励、历史圣典 / 败者卡仍来自既有入口。

### 验收条件
- 真击破：正确经历 PA-17 击败演出、现有 FinalOracle 确认提交，再播放 CRT 关机 → 向上翻页 → 主角房间 → 结算 UI。
- 未击破：保留 T5 立绘离线后，同样 CRT 关机 → 向上翻页 → 主角房间 → 结算 UI；无成功击破图和奖励。
- 战败 PK0 由 PA-18 自己的失败界面负责，不混入本卡的战后房间结算。
- 两种 Rest 入口复用相同页面，首次播放、返回 / 重进 / 本关继续均不会重复演出或重复提交结果。
- 1920×1080 的 Windows / Android 场景动画流畅，结算按钮可正常使用，Output / Debugger 无新增错误。

## 本卡专项交付说明
新增 `docs/Shared/PresentationAssets/表现资产_PA-19_YYYY-MM-DD_log.md`，记录 CRT / 翻页动画、Rest 界面控制顺序、两种结算入口和实际画面验证。

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
