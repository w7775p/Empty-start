# RS-15 · 移除休息房间三倾向 HUD / 装饰标识

状态：P1，待开发；Owner：休息室环境 Agent。**本卡只删除房间里用于展示三倾向的 UI，不改三倾向数据。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `ui/rest/rest_room_environment.gd` / `.tscn`；`ui/rest/rest_opening_room.gd`、`ui/rest/rest_result_view.tscn`（后两者只读）。

## 已经实现的功能
- `RestRoomEnvironment` 共用 `RoomBackdrop`、`RoomTint`、`RoomForegroundDesk`，并在 `apply_tendency()` 按正统/异端/荒谬设置 `LeftVotive`、`RightVotive`、`RoomSigil` 及房间色调。
- 三倾向状态由其他系统保存；开播页和结算页均复用房间环境场景。

## 本次任务
1. **移除可见三倾向 HUD/符号层**：删除或永久关闭 `LeftVotive`、`RightVotive`、`RoomSigil`，并清理对应脚本引用，避免正统/异端/荒谬在房间里出现光柱、符号或倾向指示。
2. 保留房间的真实背景、前景桌面、正常的轻微环境着色。`apply_tendency(tendency_id)` 可继续作为兼容入口，但不能重新弹出倾向 HUD；若现有调色过重影响原画，只把多余遮罩恢复为中性，不扩成三套新场景。
3. **不删除三倾向系统**：不改 `TendencyState`、结果/圣典/结局映射、存档、关卡和三个属性的实际数值；不改另一任务正在做的 RS-14 电脑开播布局。

## 本任务所属分支和文件归属
- 唯一可写运行文件：`ui/rest/rest_room_environment.gd`、`.tscn`。不改 `rest_opening_room.*`、`rest_result_view.*` 或其他 Agent 文件。
- 最新 `main` 分支，独立 D 盘工作树，功能 PR 指向 `main`；先认领 Owner，禁止覆盖正在修改的共享环境。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080；Godot-MCP-Native、godot_mcp。

## 最小执行流程
移除对应节点与引用 → Godot 加载休息室 → 一张真实截图 + 一次 `apply_tendency()` 调用确认不显示 HUD → commit + 短 log + PR。遵循原任务卡模板 14 项，**无需复测三倾向数值和结局系统**。

## 验收标准与最终汇报
- 房间中无三倾向专用符号/光柱/HUD；房间和桌面仍正常，开播按钮和结算页照常可用；脚本无失效 NodePath。
- PR 列出删除节点、截图分辨率和 SHA；视觉未确认保留 Draft。
