# PB-25-FIX · 费米教学文案改用仓鼠主播现有气泡

状态：P0、已实现；PR #324 保持 Draft，等待用户视觉验收；Owner：B，沿用 PB-25 / PR #324 的同一 Agent。

## 开始前先阅读以下文档
AGENTS.md、known_traps.md、docs/Original/任务卡模板.md、PB-25 原任务卡、PR #324、ui/streamer_bubble_dialogue/ 和 scenes/sandbox/sandbox_battle_hud.gd。

## 已经实现的功能
PB-25 四阶段教学事件、三卡高亮、type_c/S1 感染、费米 type_b 反击与重开接续已完成；当前存在独立 TutorialHintView 面板。既有主播话语可通过 SandboxBattleHud.show_dialogue_bubble(entry: BubbleDialogueEntry) 或 enqueue_dialogue_bubble 提交至玩家侧 StreamerBubbleStack，现有 ui/plan_b/plan_b_streamer_panel.gd 亦有 show_bubble。

## 本次任务
1. 将 PB-25 教学所有显示给玩家的引导文本从中央独立 TutorialHintView/Panel 改由 **玩家（左侧仓鼠主播煲煲）的现有话语气泡**呈现；沿用原 BubbleDialogueEntry、StreamerBubbleView/Stack 的字体、颜色、尺寸、动画、尾巴及左主播锚点。不要另外制作教学浮层/Panel。
2. 接通 TutorialStepRunner.hint_requested 到现有左主播气泡接口；四阶段对应原 24_新手教学配置.csv 正式文本，保持事件驱动且顺序正确，不用调试浮字代替正式剧情。
3. 对超长文本作可读的气泡内折行/分句呈现；同一阶段只能稳定展示一组提示，避免与既有随机复读/主播台词叠出大量重复气泡。关键操作提示要给玩家足够阅读时间，跨阶段和重开及时更新，结束后恢复正常主播气泡。
4. 保留三卡金色高亮、强制 S1、正确克制、费米反击、矛盾蓄力教学与存档事件；不同关卡其他现有教学接口仍按原功能工作。
5. 正式 1280×720 和 1920×1080 至少各看一次：教学文字只出现在左侧仓鼠主播气泡，不侵入中央棋盘/卡槽，也不会被房间底边裁切；教学完成气泡收起，主播正常发言。

## 本任务所属分支和文件归属
优先继续 PR #324 原分支，始终将最新 main 纳入基线，解决与已合并 #326/#328 的真实文件变化；B 独占 scenes/sandbox/sandbox.gd、PB-25 引导接线。尽量复用 SandboxBattleHud 的现有 show_dialogue_bubble，不改 E PA-22 的 opponent_tier_portrait.gd，不改 A 的 live_data_hud.gd，不改仍在视觉修改的 #327 身份选择页。

## Godot 开发环境
Godot 4.7.2 / GDScript / 1920×1080、1280×720；工作树、导入缓存、日志、临时录制素材全部 D 盘，严禁写入 C 盘。

## 最小执行流程
按最小补丁修复，更新 PB-25 log，做一次 Sandbox 起步及完整四阶段事件 smoke，附仓鼠气泡关键帧截图；PR #324 保持 Draft 供用户视觉验收。

截图：`docs/Integration/evidence/PB-25-FIX_2026-10-20/`，开场、type_c/S1 和矛盾提示各含 1280×720 与 1920×1080。

## 最终汇报
提交 SHA、PR #324、引导气泡入口与现有面板移除结果、可查看的 D 盘截图及剩余视觉问题。
