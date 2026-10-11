# Sandbox 布局 INT-06 任务日志（2026-10-11）

## 目标与分支

本次继续 `INT-06`，工作分支为 `codex/lane-a-int06-1011`，起始 HEAD 为 `07a4ea1`（与开工时 `origin/main` 相同）。开工时已有未提交代码、图标、测试和证据；在这些改动上继续完成验收与交接，没有重置或覆盖原工作区内容。

## 实现内容

- `scenes/sandbox/sandbox.tscn`：中央 `BarrageArea` 和 `OracleCandidateDisplay` 从高度 760 调整为局部矩形 `(0,72,1024,1008)`；删除 `ChargeFeedback` 栏及其进度条、文字；新增左下角纵排 `OperationHintOverlay`，含鼠标左键与 ESC 图标，图标各为 48×48、间隔 12px，左/下边距 24px。
- `assets/ui/input_mouse_left.svg`、`assets/ui/input_escape.svg`：新增两枚按键图标；ESC 图标内保留 `ESC` 字样。
- `scenes/sandbox/sandbox_battle_hud.gd`：移除已删除 ChargeFeedback 控件的引用；`refresh_attack(progress, phase)` 继续保存归 CombatAttack 所有的最新进度和阶段，`reset_for_attempt()` 复位两项状态。
- `data/stage_layout/stage_layout_profile.gd`、`stage_layout_profile.tres`：把旧的 PK / ChargeFeedback 区域字段替换为 `top_battle_status_area_size`；资源矩形同步为 `(448,72,1024,1008)` 与顶部 `1024×72`。
- `tests/integration/int_01_playable_battle_sandbox_test.gd`：将旧 ChargeProgress 控件断言改为读取公开 HUD 状态；同步当前测试所用 Tier 速度上限和 T0 状态预期。
- `tests/integration/int_06_full_height_battle_smoke.gd/.tscn`：增加真实 Sandbox GUI smoke，检查场景矩形、普通弹幕底边命中、神谕底边选择、图标输入穿透、Escape 暂停/恢复和缩放锚点。注入输入前等待现有 `can_start_charging()` 恢复 READY，避免测试依赖上一发计时余量。

未改普通战斗、矛盾、神谕或 Rest 的业务规则；`refresh_attack` 仍为原显示入口。

## 验证与证据

- 使用本机 Godot `4.7.2.stable.steam.ed1daf0bf` GUI 运行本仓库的 `int_06_full_height_battle_smoke.tscn`：
  - 请求 `1920×1080`：PASS。桌面窗口客户端实际为 `1920×1055`，逻辑视口为 `1965×1080`，最终变换约 `0.977×`；全屏切换验证获得实际 `1920×1080`。
  - `1280×720`：PASS；全屏切换至 `1920×1080` 后恢复 `1280×720`：PASS。
  - `960×540`：PASS；显式等待 READY 后一次复测及三次重复运行均 PASS。
  - 真实输入事件命中全高弹幕场底边普通目标，并选择底边神谕候选；ESC 暂停后再次按下可恢复；图标浮层不拦截准心与攻击。
- 复用 `int01_regression_rerun_engine.log`：`INT-01 PASS: 88 checks`，对应 stderr 文件为 0 字节。`cs18_regression_engine.log` 记录 13 项 PASS。
- 运行截图保存在 `evidence/INT-06_2026-10-11/`。已目视检查 1920 窗口、1280 与 960 下的底边目标和 ICON 画面。
- 初始文件导入记录包含缺失音效资源和 CSV locale 警告，均未涉及本卡修改；最新 INT-06 GUI smoke 日志未记录相关错误或警告。
- 960×540 首次重跑出现一次神谕底边选择断言失败，之后未能稳定复现。Smoke 的 `_fire_at()` 原先使用固定等待时间；增加 `can_start_charging()` 状态等待后，4 次 960×540 运行均 PASS。现有证据记录了首轮失败与修正后的通过日志，没有确认到运行时代码问题。
- `Godot-MCP-Native` 当前连接项目为 `D:/Godot/Empty-start`、活动场景为 `Boot`，因此没有用该连接检查本仓库 Scene Tree；改用本机 Godot GUI CLI 实际运行目标 smoke 场景。独立的编辑器 Scene 预览尚未核验。

## 当前能力与未验收项

中央顶部以下全高可生成弹幕；准心能命中靠近屏幕底边的普通目标并选择神谕候选。图标随 PC 窗口缩放固定在中央区左下角，鼠标输入可穿透浮层，攻击状态仍可供后续正式美术反馈读取。

编辑器中的 Sandbox Scene 预览、实体鼠标/键盘手动验收、Android 设备验收仍为 `UNVERIFIED`。正式蓄力反馈美术仍由后续任务接入。

## 文档与下一步

- 已更新 `docs/Integration/README.md` 的 INT-06 状态，并从待接入表中移出。
- 已更新本任务卡的状态与当前完成摘要。
- `known_traps.md` 未更新：一次 smoke 失败只在测试时序层出现，修正后重复运行通过，未确认出可复现的运行时陷阱。
- 后续接手从本日志、INT-06 任务卡与 `scenes/sandbox/sandbox.tscn` 开始；使用连接到本工作树的 Godot 编辑器核对 Scene 预览，并完成实体输入验收后更新剩余验收状态。
