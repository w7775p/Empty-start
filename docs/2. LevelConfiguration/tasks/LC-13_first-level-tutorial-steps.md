# LC-13 首关新手教学按步骤配置播放

**状态：新需求 · 待开发**
**类型：关卡配置 / 教学流程**
**关联：LC-10、现有 CombatAttack、AimReticle、Sandbox、24_新手教学配置**

## 开始前阅读
- `AGENTS.md`、`project.godot`、`known_traps.md`
- `docs/2. LevelConfiguration/README.md`、`data/level_configuration/level_profile.gd`
- 现有 Sandbox、`AttackChargeInput`、`AimReticle` 的实际输入/命中接口
- Google Sheets `02_主播关卡`、`24_新手教学配置` 最新字段

## 已实现的基础
- 第一关正式ID为 `level_001`，对手为 `alien`，保留完整的直播PK和Tier流程。
- 游戏已有瞄准、蓄力、发射和实际命中事件，Sandbox HUD 已有战斗提示显示区域。
- 02表的第一关 `tutorial_config_id=tutorial_level_001`；24表有瞄准、蓄力、发射三个待启用步骤草案。

## 本次任务
进入具有有效 `tutorial_config_id` 的关卡时，读取24表中启用的教学条目，按 `step_order` 依次响应真实 `trigger_event`，显示 `hint_text`，并在对应 `completion_event` 确认后推进到下一步骤。使用现有瞄准与攻击事件作为触发与完成事实，并在正式绑定时确立稳定事件ID。

提供本周目教学步骤完成记录，让战斗重开、关卡切换和已有教学完成状态与显示保持一致。提示与实际战斗共用同一个HUD和输入来源；PC及Android均从现有输入抽象取得操作事实。

## 验收
- 02表仅首关带有教学配置关联，按24表启用的步骤播放并依次完成。
- 瞄准、蓄力和实际发射触发分别来自真实输入；按顺序推进，重开时已完成步骤的处理符合当前周目记录。
- 其余三关使用正常PK流程；修改24表文本/顺序/启用状态后重新导表可以生效。
- Windows与Android相关输入和HUD提示经Godot实景验证。

## 完成记录
提交LC-13日期日志，记录事件ID映射、配置来源与实际教学操作验收结果。
