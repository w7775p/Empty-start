# PA-26 · 仓鼠主播立绘按现有战斗事件切换五种表情

状态：P1，待开发；Owner：主播立绘表现 Agent。**只增加玩家仓鼠换图反馈，不改变战斗逻辑。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `ui/plan_b/plan_b_streamer_panel.gd`、`ui/plan_b/plan_b_battle_ui.gd`、`systems/presentation/streamer_portrait_motion.gd`、PA-23 / PA-23-FIX 的立绘锚点说明。

## 已经实现的功能
- 玩家主播面板现在以 `assets/characters/player/hamster_idle.png` 为默认立绘，通过 `_portrait_art` TextureRect 呈现，并复用已经实现的呼吸与射击表现。
- 资源中还有 `hamster_smile.png`、`hamster_happy.png`、`hamster_angry.png`、`hamster_evil.png`，目前没有正式切换入口。
- `PlanBBattleUI` 已有成功发表回调 `resolve_publish_request(...)`、`_on_tier_changed(...)`、`set_paradox_stage_active(...)`、`reset_for_attempt(...)` 和射击事件 `_on_player_shot(...)`。

## 本次任务
1. 让**玩家侧** `PlanBStreamerPanel` 预加载五张仓鼠表情，并暴露一个极小的 `show_player_expression(kind, seconds)` / 重置接口；只替换 `_portrait_art.texture`，保持现有立绘位置、尺寸和锚点不变，**不改对手面板**。
2. 使用已有事实事件做简单表情映射（无额外配置系统）：
   - **idle**：开局、重开和短暂反馈结束后的默认状态；
   - **smile**：玩家成功发表话语时短暂切换；
   - **happy**：玩家 Tier 升档时短暂切换；
   - **angry**：Tier 降档时短暂切换；
   - **evil**：首次进入矛盾击破阶段时短暂切换，再回 idle。
3. 优先调用现有方法而非另建战斗监听器。表情短反馈可采用约 0.6–1.0 秒的单一轻量 Timer/Tween，新的事件**覆盖前一个表情**，不排队、不每帧换图；离开场景或重开时恢复 idle，射击动画正常运作。
4. 保持原先的呼吸/射击/CRT/遮挡和资源尺寸逻辑，不增加移动、粒子、滤镜、战斗数值或状态计算。如果一个预期事件在当前正式版不会发出，只在日志标明未触发，不改模拟系统去造事件。

## 本任务所属分支和文件归属
- 唯一 Owner 可写 `ui/plan_b/plan_b_streamer_panel.gd` 与 `ui/plan_b/plan_b_battle_ui.gd`（仅现有事件的触发调用）；不改 `systems/presentation/streamer_portrait_motion.gd`，除非现有节点逻辑证明完全无法兼容且得到总控批准。
- `plan_b_battle_ui.gd` 与 **INT-24** 可能争用：等该文件 Owner 释放后再进行事件接线，不覆盖对方分支；可以先在单独分支完成单侧面板方法。
- `live_data_hud.gd`（INT-22）、PB-25 教学气泡、PA-22 青蛙分件、模拟器、剧情与漫画都是禁改范围。
- 从最新 `main` 创建独立 D 盘工作树，PR 目标 `main`。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080 逻辑画布；Godot-MCP-Native、godot_mcp。

## 最小执行流程
接五张现有 PNG → 增加极小换图方法 → 在现有四个事件入口调用 → Godot 正式主播面板验证实际切换（截**一张多状态对照图**或一段短录屏即可）→ commit、短 log、功能 PR。遵循原任务卡模板 14 项，不新增大规模测试。

## 验收标准与最终汇报
- 仓鼠不再永远 idle；成功发言、Tier 升降、进入矛盾阶段分别出现对应非 idle 图，短暂展示后正常恢复。
- 五张图同一立绘基点，无突变大小、切出画面或挡住主播 UI；立绘运动与原射击表现不中断，重开无残留 Timer/Tween。
- 提交事件 → 贴图映射表、截图/短录屏、SHA、真实可触发事件与限制；无实机证据保留 Draft。
