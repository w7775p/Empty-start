# RS-15 · 移除房间三倾向 HUD，保留环境装饰

状态：P1，待开发；Owner：休息室环境 Agent。**只隐藏/移除独立的倾向指示 HUD，不拆除房间美术和氛围。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `ui/rest/rest_room_environment.gd` / `.tscn`；`ui/rest/rest_opening_room.gd`、`ui/rest/rest_result_view.tscn`（后两者只读）。

## 已经实现的功能
- `RestRoomEnvironment` 共用 `RoomBackdrop`、`RoomTint`、`RoomForegroundDesk`，并在 `apply_tendency()` 按正统/异端/荒谬设置 `LeftVotive`、`RightVotive`、`RoomSigil` 和着色；**当前场景源码没有独立的三项数值条 HUD**。其中 `LeftVotive`/`RightVotive` 是装饰光柱，不能擅自等同于数值 HUD。
- 三倾向状态由其他系统保存；开播页和结算页均复用房间环境场景。

## 本次任务
1. 先查看**正式房间实际画面**，定位用户所说的三倾向 HUD（数字、倾向文字、条形指示，或独立悬浮符号）。只对确认是 HUD 的控件做隐藏/移除；若该 HUD 实际上就是 `RoomSigil` 悬浮符号，仅隐藏或删除 `RoomSigil` 并同步清理相应引用。**不要把 `LeftVotive` / `RightVotive` 房间装饰光柱当 HUD 全删。**
2. 完整保留背景、桌面、现有 `RoomTint` 及按倾向改变的房间氛围和 `apply_tendency(tendency_id)` 调用入口。**不改色调或光照规则**。若正式场景里没有独立 HUD，记录“当前版本不存在待删三项数值 HUD”；不要为了完成卡片而删除非 HUD 装饰或改动其他 Owner 的页面。
3. **不删除三倾向系统**：不改 `TendencyState`、结果/圣典/结局映射、存档、关卡和三个属性的实际数值；不改另一任务正在做的 RS-14 电脑开播布局。

## 本任务所属分支和文件归属
- 唯一可写运行文件：`ui/rest/rest_room_environment.gd`、`.tscn`。不改 `rest_opening_room.*`、`rest_result_view.*` 或其他 Agent 文件。
- 最新 `main` 分支，独立 D 盘工作树，功能 PR 指向 `main`；先认领 Owner，禁止覆盖正在修改的共享环境。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080；Godot-MCP-Native、godot_mcp。

## 最小执行流程
确认实际 HUD 节点 → 仅隐藏/移除对应显示与失效引用 → Godot 运行房间留一张真实截图（无目标 HUD 则说明并结束，不造修改）→ commit + 短 log + PR。遵循原任务卡模板 14 项，**无需复测三倾向数值和结局系统**。

## 验收标准与最终汇报
- 目标三倾向 HUD 不再显示；房间底图、桌面和原有光柱/环境着色不被误删，开播按钮和结算页照常可用；脚本无失效 NodePath。
- PR 列出实际识别的 HUD 节点、截图分辨率和 SHA；如果正式版无独立 HUD，仅提交“未发现待删 UI”的审查说明，**不要创建无效代码 PR**。
