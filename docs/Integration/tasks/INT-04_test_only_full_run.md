# INT-04 使用 TEST_ONLY 配置完成整局主流程联调

**状态：已实施指定基线 Windows TEST_ONLY 联调 · 2026-10-09 · [完成日志](../INT-04_2026-10-09_log.md)；旧日志标明当时最新 main 兼容复验存在未解决项**

## 开始前先阅读以下文档
- AGENTS.md、known_traps.md、project.godot
- docs/Original/任务卡模板.md
- docs/Integration/README.md 与相关完成日志
- 当前相关 Scene、Resource、代码与前置任务卡

## 授权与目的
项目负责人 2026-10-08 决策：正式策划内容、配图、文案、数值若尚未交付，统一用已标明来源的 `TEST_ONLY` 注入进行程序联调，不阻塞基础系统闭环。今天优先完成基础系统；次日集中整合联调和表现打磨。本卡在关键上游代码合并后执行。

**Owner**：Lane A / Sandbox 集成。B 持有 Rest UI，C 持有 DivineDescent 核心，D 持有 Ending，E 持有继承特性；由各 Owner 修复其模块，A 最小化接线，不在 A 内重写其它系统。

## 已经实现的功能
- `data/test_only/generated/level_configuration/test_only_level_catalog.tres`：两个 TEST_ONLY 主播关卡及普通词库/矛盾配置。
- `tests/fixtures/data_export/test_only_sandbox.tscn`：通过覆写 `level_catalog` 启动真实 Sandbox，而非修改生产关卡目录。
- `tests/data_export/test_test_only_live_smoke.gd`：已覆盖首关真实生成、蓄力命中、PK 满值、矛盾未击破、Rest Continue 到第二关。
- `tests/fixtures/fo11/`：真实击破后败者卡及吞并奖励的 TEST_ONLY 资料。
- 正式 `data/ending/*.tres` 与 `data/loser_card/loser_card_catalog.tres` 若仍为空，测试环境可以显式提供 TEST_ONLY Resource / 内存配置，不将虚构数据回填为正式策划内容。

## 本次任务
1. 基于**最新 main** 阅读本卡、`AGENTS.md`、`known_traps.md` 和系统日志。确认 ID-08、RS-11、CS-11、DD-10～17、EN-09、BT-13 等真正已合并和所暴露的接口；若未合并，列明阻塞并等待对应 Owner，不抢写。
2. 从身份选择与 SaveData 确认开始，实际运行**两次普通关**：正常弹幕生成、蓄力攻击、命中、Tier 与 PK、矛盾分支、神谕选择、真正击败奖励、Rest 展示、继续与下一主播。身份 12 卡的已批准真实文字来自 CSV，不以 TEST_ONLY 擅自替换。
3. 验证未击破通关、真正击破成功、失败重开、重复确认/重复打开、历史经文和败者卡、吞并词库/特性、粉丝数与倾向只取已提交值；无正式数据时显式注入稳定的 TEST_ONLY ID、材质/颜色和文案。
4. 两个普通关全部完成后进入 DivineDescent，真实验证冻结快照、新话衰减、扩散、锁句、90% 收束和 DD-17 触发，随后收到 **EndingSession** 的固定事实、显示 EndingPage；验证没有圣典/卡片/吞并的全空路线也可结束。
5. PC Windows Godot 4.7.2 真正运行 `SceneTree` smoke，至少覆盖主成功路线和一次未击破路线（可以用 TEST_ONLY 注入而不人工点击每一条弹幕）；有 UI 的路径补实际 D3D12 窗口验证，记录判定点、退出码、Output 错误和真实数据的来源。Android 触控 / 分辨率 / 打包交后续 CA-12 与平台验收，不把 PC 结果冒充 Android 已过。
6. 发现一个跨系统问题先定位真实 Owner：A 只修 Sandbox / 路由边界；其它问题形成最小复现与明确文件/接口交接。没有问题不额外新建 Manager、索引/哈希门禁或重复实现已有测试。
7. 更新 `docs/Integration/README.md`（存在时）和 `INT-04_YYYY-MM-DD_log.md`；写清正式缺口与 TEST_ONLY 代替项、尚未覆盖内容、PC/Android 验收边界。依当前协作规则独立 PR。

### 验收条件
- 至少一条真实的身份 → 普通关 1 → Rest → 普通关 2 → DivineDescent → Ending 主流程完成，期间未复制一套 PK、终局倾向或奖励事实。
- 未击破、真正击破、重开及重复输入不错误登记奖励、倾向、收藏、关卡或终局快照。
- 缺正式结局图、判词、教名、败者卡、第二关配表不阻塞 TEST_ONLY 的程序逻辑验收；所有临时内容明确可识别、可替换，不污染正式 `.tres`。
- 提供真实 Godot 4.7.2 运行证据和对应日志；正式美术/平衡/Android 继续明确为待验收。

## 开始条件
**这是一张次日整合卡，不是当前五条 Lane 的追加并行任务。** 只有相关 P0 上游合并后再派给空闲 A，不打断正在执行的 CS-11，也不抢改各 Lane 未提交文件。

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
