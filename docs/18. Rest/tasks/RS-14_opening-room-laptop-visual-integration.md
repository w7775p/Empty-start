# RS-14 · 休息室开播电脑图接入与临时面板替换

状态：P1，待开发；Owner：领取 `ui/rest/rest_opening_room.*` 的休息室 UI Agent。**本卡只做图片替换及必要的按钮布局调整。**

## 开始前先阅读以下文档
- `AGENTS.md`、`project.godot`、`known_traps.md`、`docs/Original/任务卡模板.md`。
- `ui/rest/rest_opening_room.gd` / `.tscn`、`ui/rest/rest_room_environment.tscn`。
- `docs/Shared/PresentationAssets/PA-21_资产接入状态_2026-10-19.md`（电脑图路径）。

## 已经实现的功能
- 休息室已有正式房间背景、桌面和倾向光照，页面显示主播名、粉丝团名、下一关提示。
- `StartLiveButton` 连接 `start_live()`，已有进入游戏、暂停、重复点击锁定和跳转失败恢复逻辑。**原交互继续保留。**
- 现有中央 `PanelContainer` 比较临时，`assets/environment/player_room/laptop_start_stream.png`（764×512）已经在仓库，开播页尚未使用。

## 本次任务
1. 在正式 `ui/rest/rest_opening_room.tscn` 展示 `laptop_start_stream.png`，保持原始宽高比，位置与原有房间背景/桌面自然协调；移除或弱化遮挡房间的中央通用大面板。
2. 将**原有**“开始直播”按钮视觉摆放在电脑图对应的位置或旁边，让玩家一眼知道哪里点击。复用 `StartLiveButton`、`start_live()` 和现有点击反馈；保留主播名、粉丝团名、下一关及失败提示，文字能看清。
3. **不做新电脑热区系统、开播动画、交互状态机或关卡/存档逻辑修改。** 仅在为保留既有节点引用和布局所必需时改 `rest_opening_room.gd`。

## 本任务所属分支和文件归属
- 最新 `main` HEAD 创建独立分支，PR 指向 `main`；D 盘独立工作树和缓存。
- **唯一可改运行文件：** `ui/rest/rest_opening_room.tscn`、确有必要时 `ui/rest/rest_opening_room.gd`。禁止改共享 `ui/rest/rest_room_environment.*`，避免身份过渡和结算画面被电脑图污染；禁止改 `SaveManager`、`SceneRouter`、`ui/rest/rest_result_view.*`、`scenes/sandbox/sandbox.gd`。
- 如被其他任务认领，等文件释放；不得修改别人的工作树。

## Godot 开发环境
Godot 4.7.2、GDScript、Windows PC；1920×1080 逻辑画布。工程操作 Godot-MCP-Native；API 查阅 godot_mcp。

## 最小执行流程
1. 核对电脑 PNG、现有房间 UI 和开始按钮节点，直接接入并替换布局；独立子任务按需各自 commit。
2. 运行**正式休息室场景**，留 **1 张 1920×1080 实际游戏截图**，确认电脑与文字清楚、点击原按钮能开播。仅当出现 720p 布局问题时补 1280×720 截图；无需重新执行完整新周目、继续游戏、全部关卡或存档回归。
3. 同一代码 PR 写短日志 `docs/18. Rest/休息系统_RS-14_YYYY-MM-DD_log.md`，附截图、commit、实际使用的图片路径和修改结果。没图保持 Draft，人工验收后合并。

## 执行要求
完整遵守仓库 `docs/Original/任务卡模板.md` 的 14 项通用要求；不扩展休息室其他功能，不新建测试框架。

## 验收标准与最终汇报
- `laptop_start_stream.png` 在正式房间实际显示，中央临时大面板不再抢占主要画面；姓名/关卡提示可读。
- 原有 `StartLiveButton` 鼠标点击可正常进入游戏，原暂停与进度逻辑未受改动，结算和身份页不出现新电脑。
- PR 附至少 1 张 Godot 真实截图（分辨率、commit SHA），列明资源引用节点、实际修改文件及任何遮挡遗留；未经人工确认不自动合并。
