# INT-24 · 战斗界面现有美术底图接线

状态：P1，待开发；Owner：领取 `ui/plan_b/plan_b_battle_ui.gd` 的界面整合 Agent。**本卡只做现有资源的接线和遮挡调整。**

## 开始前先阅读以下文档
- `AGENTS.md`、`project.godot`、`known_traps.md`、`docs/Original/任务卡模板.md`。
- `docs/Integration/INT-21_2026-10-20_log.md`、`docs/Shared/PresentationAssets/Art_Intake_Rename_2026-10-20.md`。
- `ui/plan_b/plan_b_battle_ui.gd` / `.tscn`（重点：`_build_view()` 与中央 PK/矛盾区域）。

## 已经实现的功能
- 正式 Plan B 三列布局、棋盘、PK 皮肤、三张话语卡、左右主播区及其交互均已存在。
- 已入库待接的图片：
  - `assets/ui/live/livestream_layout_background.png`（1920×1080，直播/棋盘总底图）。
  - `assets/ui/combat/paradox_bar_background.png`（532×144，矛盾条美术）。
- INT-22 **正在开发**八张直播统计图标，本卡无需处理。

## 本次任务
1. 在正式 `PlanBBattleUI` 接入 `livestream_layout_background.png`，替换现有纯色底层或相应背景层。使用 Godot 原生纹理显示，按照现有 1920×1080 画布适配；让图片可见，并确保主播房间、棋盘、PK、文字、三卡及气泡保持原有层级和可读性。
2. 核查 `paradox_bar_background.png` 对应的**已有**矛盾条或阶段显示位置。如已有匹配的背景节点/容器，直接更换美术并保留原数值与状态表现；如没有合适位置，**只在完成日志里写明“暂无对应正式容器”并跳过此项**，无需新增计量系统、设计新条或等待策划决定。本卡主要完成第 1 项。
3. 仅调整为显示两张图片所必需的尺寸、缩放、遮罩、层级或背景透明度。保留三列尺寸 448 / 1024 / 448、棋盘操作坐标、PK/Tier、发表和冷却行为。

**明确排除：** INT-22 直播统计、评论/粉丝牌、角色立绘、教程、矛盾机制、PK 算法、输入重构、全局 UI 美化、重新制作贴图。

## 本任务所属分支和文件归属
- 从开发时最新 `main` HEAD 建独立分支，PR 指向 `main`；工作树、Godot 缓存、截图、日志均在 D 盘。
- **唯一可改运行文件：** `ui/plan_b/plan_b_battle_ui.gd`；如现有场景确实需要，附带修改 `.tscn`。禁止修改 `ui/live_data/live_data_hud.gd`（INT-22 正在开发）、`ui/plan_b/plan_b_streamer_panel.gd`、`scenes/sandbox/sandbox.gd` 以及其他 Agent 已占用的文件。
- 若当前仍有 Agent 修改本卡运行文件，等待 Owner 释放后再接线；不得并发覆盖。

## Godot 开发环境
Godot 4.7.2、GDScript、Windows PC；1920×1080 逻辑画布。工程操作 Godot-MCP-Native；API 查阅 godot_mcp。

## 最小执行流程
1. 从最新 main 核对两张 PNG 和已有可见层，一次性完成最小资源接线；独立子任务按需各自 commit。
2. 运行**正式** `scenes/sandbox/sandbox_plan_b.tscn`，留 **1 张 1920×1080 实际游戏截图**，检查背景真正可见、控件未遮挡，鼠标点卡/棋盘仍正常。若发现 720p 适配异常，再补 1280×720 截图；不要求模拟多关与完整矛盾流程。
3. 同一代码 PR 写短日志 `docs/Integration/INT-24_YYYY-MM-DD_log.md`，列出两张图分别“已接入/无对应容器”、修改文件、commit 和截图。截图缺失时保持 Draft；由策划视觉验收后合并。

## 执行要求
完整遵守仓库 `docs/Original/任务卡模板.md` 的 14 项通用要求；本卡无额外测试框架、专项架构重构或跨系统回归。

## 验收标准与最终汇报
- 直播总底图在**正式游戏画面**实际显示，按原图比例呈现，不遮住主播、三卡、棋盘或文字；原有点击行为正常。
- 矛盾条底图若有对应旧容器即完成替换，若无则明确记录并放行本卡，不虚构新功能。
- PR 附最少 1 张真实 Godot 截图（标注分辨率、commit SHA），短述素材映射、改动位置与遗留问题；未经人工确认不自动合并。
