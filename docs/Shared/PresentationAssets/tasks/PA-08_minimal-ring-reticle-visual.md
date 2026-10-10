# PA-08 极简准星程序美术：小空心圆与环形蓄力进度

> 状态：独立视觉组件与演示已交付（PR #111）；2026-10-10 按策划表修订 PC 视觉 96×96 / 命中 144×144，待 Sandbox 正式集成验收
> 类型：P0 / PresentationAssets
> 依赖：现有 AimReticle 与 CombatAttack 的蓄力状态

## 开始前阅读
- `AGENTS.md`、`project.godot`、仓库已知问题记录
- `docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`
- `docs/5. CombatAttack/README.md`
- `systems/combat_attack/aim_reticle.gd`、`systems/combat_attack/aim_reticle.tscn`
- `systems/combat_attack/attack_charge_input.gd`
- 当前攻击系统与战斗 HUD 相关最新 log

## 现有基础
- `AimReticle` 已通过 `_draw()` 绘制准星，支持鼠标及触屏位置与瞄准直径调整。
- `AttackChargeInput` 已有蓄力进度、释放、飞行与恢复阶段。

## 本次任务

### 1. 基础外观
- 将准星绘制成**极简的小空心圆**，中心明确、线条轻巧。
- 在准星外侧绘制一圈**细的环形蓄力进度**，与中心空心圆形成清楚的内外层次。
- 用简洁、高对比、可调整的线条颜色与亮度，在密集弹幕背景下保持可辨识性。

### 2. 四种视觉状态
- **待机**：小空心圆清晰稳定，外侧环形进度显示基础状态。
- **移动**：准星跟随已有瞄准位置，搭配轻微且短促的移动反馈。
- **蓄力**：外围细圆弧随现有蓄力进度逐步填充，填充过程平滑、清楚。
- **发射**：释放时小空心圆与外环出现短促的高亮或收放反馈，随后恢复待机外观。
- **满蓄强调**：蓄力达到完成状态时，外环闭合并进行明确但克制的视觉强调。

### 3. 程序美术接入
- 优先复用 `AimReticle` 的 `_draw()`，以现有蓄力进度与攻击阶段驱动视觉状态。
- 将中心环直径、外环直径、线宽、颜色、透明度、蓄满高亮及动画时长设为可调整的视觉参数。
- 保持准星绘制中心与现有实际瞄准判定中心一致，PC / Android 显示均能继承现有缩放适配。
- 在当前主战斗场景中展示新准星的待机、移动、蓄力和发射反馈。

## 验收
- 准星视觉呈现为**小空心圆 + 外围细进度环**，整体风格极简。
- 待机、移动、蓄力、满蓄及发射反馈均可在实际游戏中观察。
- 进度环的填充视觉与现有蓄力进度同步，发射时反馈短促明确。
- 准星中心与已有命中判定坐标保持一致，PC / Android 下保持视觉比例和可读性。
- Godot 实际画面与 Output / Debugger 验证通过。

## 环境与完成记录
- Godot 4.7.2 / GDScript / Windows / Android
- Godot-MCP-Native；godot_mcp
- 完成后新增 `docs/Shared/PresentationAssets/表现资产_PA-08_2026-10-09_log.md`，记录节点、绘制与配置方式、状态反馈、视觉接线和实际运行验收。
