# PA-26 · 仓鼠主播立绘按现有战斗事件切换五种表情

状态：P1，待开发；Owner：主播立绘表现 Agent。**只增加玩家仓鼠换图反馈，不改变战斗逻辑。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `ui/plan_b/plan_b_streamer_panel.gd`、`ui/plan_b/plan_b_battle_ui.gd`、`systems/presentation/streamer_portrait_motion.gd`、PA-23 / PA-23-FIX 的立绘锚点说明。

## 已经实现的功能
- 玩家主播面板现在以 `assets/characters/player/hamster_idle.png` 为默认立绘，通过 `_portrait_art` TextureRect 呈现，并复用已经实现的呼吸与射击表现。
- 资源中还有 `hamster_smile.png`、`hamster_happy.png`、`hamster_angry.png`、`hamster_evil.png`，目前没有正式切换入口。
- `PlanBBattleUI` 已有成功发表回调 `resolve_publish_request(...)`、阶段切换 `set_paradox_stage_active(...)`、`reset_for_attempt(...)`、`_on_battle_ended(...)` 及射击事件 `_on_player_shot(...)`。现有 `Tier` 主要服务战斗阶段/对手表现，**不应直接把升档解释为仓鼠开心、降档解释为仓鼠生气**。

## 本次任务
1. 让**玩家侧** `PlanBStreamerPanel` 预加载五张仓鼠表情，并暴露一个极小的 `show_player_expression(kind, seconds)` / 重置接口；只替换 `_portrait_art.texture`，保持现有立绘位置、尺寸和锚点不变，**不改对手面板**。
2. 只选**实际存在且情绪含义明确**的事件进行最小映射：
   - **idle**：默认、重开和反馈结束；
   - **smile**：成功发表话语时短暂显示（连续发表不能持续闪烁）；
   - **evil**：进入矛盾击破阶段时短暂显示；
   - **happy / angry**：仅在已有胜利 / 失败表现流程**确实留有可见时机**时分别显示；如被结算界面立即遮挡，先保留资源入口，不为了表情另造结果事件。
   以上是本轮轻量触发建议，**不把 Tier 升降固定解释成正负情绪**；若现有事件不足，先交付可见的两种非 idle 状态，不扩系统。
3. 优先复用现有事件和主角面板方法，仅用最简单的一次性计时恢复 idle；新反馈可覆盖旧反馈，不排队、不逐帧切图。成功发表若过于频繁，跳过后续短反馈，不制造眼花闪烁；原呼吸、射击和场景重开继续正常。
4. 保持原先的呼吸/射击/CRT/遮挡和资源尺寸逻辑，不增加移动、粒子、滤镜、战斗数值或状态计算。如果一个预期事件在当前正式版不会发出，只在日志标明未触发，不改模拟系统去造事件。

## 本任务所属分支和文件归属
- 唯一 Owner 可写 `ui/plan_b/plan_b_streamer_panel.gd` 与 `ui/plan_b/plan_b_battle_ui.gd`（仅现有事件的触发调用）；不改 `systems/presentation/streamer_portrait_motion.gd`，除非现有节点逻辑证明完全无法兼容且得到总控批准。
- **真实并发冲突：** 当前未合并的 PR #324（PB-25 教学）与 #333（PB-28 气泡/棋子平衡）都修改 `ui/plan_b/plan_b_battle_ui.gd`；INT-24 后续也可能使用该文件。待这些变更合流或文件 Owner 释放后，从当时最新 main 接入少量触发调用，**不要反复从旧分支 rebase / cherry-pick 或抢改相同文件**。单侧面板换图方法若独占，可先做。
- `live_data_hud.gd`（INT-22）、PB-25 教学气泡、PA-22 青蛙分件、模拟器、剧情与漫画都是禁改范围。
- 从最新 `main` 创建独立 D 盘工作树，PR 目标 `main`。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080 逻辑画布；Godot-MCP-Native、godot_mcp。

## 最小执行流程
接五张现有 PNG → 增加极小换图方法 → 在现有四个事件入口调用 → Godot 正式主播面板验证实际切换（截**一张多状态对照图**或一段短录屏即可）→ commit、短 log、功能 PR。遵循原任务卡模板 14 项，不新增大规模测试。

## 验收标准与最终汇报
- 仓鼠在现有可见的成功发言 / 矛盾阶段能展示至少两种非 idle 表情，结束后恢复 idle；happy / angry 有真实可见结果入口就接，没有则如实说明，不把 Tier 升降错误映射成情绪。
- 五张图同一立绘基点，无突变大小、切出画面或挡住主播 UI；立绘运动与原射击表现不中断，重开无残留 Timer/Tween。
- 提交实际绑定的事件 → 表情贴图映射、至少一张状态对照截图或短录屏、SHA、未接入表情的原因；无实机证据保留 Draft。
