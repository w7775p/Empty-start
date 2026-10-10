# PA-18 PK 归零：仓鼠球跌落、我方直播断流、失败界面

> 状态：需求已确认，待实施
> 类型：程序美术 / PresentationAssets
> 依赖：OP-05 归零失败通知、现有 `Sandbox._on_attempt_failed()`、PA-13 仓鼠球、PA-11 CRT 材质

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md` 与最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/7. OpponentPKBar/README.md`、`docs/Shared/PresentationAssets/tasks/PA-13_pk-hamster-ball-indicator-animation.md`
- `docs/Shared/PresentationAssets/tasks/PA-11_stage-transition-visuals.md`

## 已经实现的功能
- 本卡原文所列的战斗 HUD、主播立绘、正式资产与阶段信号作为复用基础；以开工时真实资源/场景和最新日志核验。

## 本次任务

### 触发与表演
- 当真实玩家 PK 归零，现有 OP-05 / Sandbox 正式发出本场失败事实后，在失败界面出现前播放**一次**战败动画。
- 动画顺序：
  1. 玩家 PK 进度归零，PA-13 仓鼠球停在 PK 条左端，出现短促的失衡 / 惊跳。
  2. 仓鼠球从 PK 条**翻滚跌出轨道**，沿向下的弧线旋转坠落，快速缩小或移出画面。
  3. **左侧我方主播直播画面**播放信号抖动 → CRT 水平线收缩 → 黑屏 / 断流，终止主播显示。
  4. 右侧对手直播画面仍保持可见和正常直播形象，形成双方状态反差。
  5. 玩家当前已存在的**失败 UI / 重开按钮**在视觉动画结束后显示，并正常响应重开。

### 美术实现
- PA-13 的同一只仓鼠球为跌落对象，实际跟随 PK 的滚动状态转换成一次抛物线与角速度动画；可用 Tween、Node2D 控制位置、缩放、旋转。
- 我方断流复用 PA-11 的 CRT 扫描 / 收线参数与 Shader，方向与接入开机相反；断流范围为左侧 448×432 主播视频区域，其他区域继续受原战斗 HUD 控制。
- 可调掉落方向、初速度感、旋转次数、掉落耗时、CRT 关机耗时及失败 UI 出场延迟。
- 与当前 `show_failure()` 和既有失败 / 重开逻辑对接，只延后**失败 UI 的可见展示**到演出结束；任何一场 PK 归零只播放一次，取消 / 重开可复位球体和直播画面。

### 验收条件
- PK 真正达到 0 并进入失败结果时，能够完整看到仓鼠球跌落、左侧断流、右侧保持直播、最后出现原失败界面。
- 普通降档（仍 >0）依旧使用 PA-11/PA-13 箭头与惊跳，不会播放 PK0 整段战败动画。
- 重开后仓鼠球回归当前 PK 轨道、笑脸正常；左右视频重新按现有阶段状态展示。
- 1920×1080 / Windows / Android 真机场景和 Output / Debugger 验收通过。

## 本卡专项交付说明
新增 `docs/Shared/PresentationAssets/表现资产_PA-18_YYYY-MM-DD_log.md`，记录场景过渡、角色 / PK 可见状态、重开复位和实测。

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
