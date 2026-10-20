# INT-22 · 八张直播统计图标正式接线

状态：已完成（PR #336 已合并至 main），Owner：A。直接依赖：已合并 LD-17-FIX PR #326。

## 开始前先阅读以下文档
AGENTS.md、known_traps.md、docs/Original/任务卡模板.md、INT-21 审计复核、LD-17-FIX 任务与日志、ui/live_data/live_data_hud.gd、ui/plan_b/plan_b_streamer_panel.gd。

## 已经实现的功能
左右主播直播间均有观看、点赞、评论、粉丝等统计行；8 张对应图标资源已在 assets/ui/live/stats/ 入库，PR #336 已将其接入正式 HUD。PNG 正常加载时显示正式图标，资源缺失时才回退 Emoji；数值数据与增长逻辑保持原样。#326 的小粉丝评论名牌已由用户授权合入 main。

## 本次任务
1. 核对正式 UI 各项数据与图标的实际含义，把 player_viewers/likes/comments/followers 与 opponent_viewers/likes/comments/followers 八张 png 正确接到左右主播实时统计行（顺序与资源语义匹配），取代原粗糙 Emoji；保留现有数据、增长逻辑和主播分侧。
2. 使用 Godot TextureRect/Theme 按图标原始比例呈现，数值仍可读；左右摆位镜像对应、统计行间距稳定，未加载图片时可用安全回退。不要修改粉丝评论的昵称牌、品牌颜色、文本换行和 #326 已批准排版。
3. 以 1920×1080、1280×720 的正式 Plan B 三列 UI 截图核对：所有 8 张图标清晰可辨，不遮挡主播/棋盘/评论，不影响数值实时更新。

## 本任务所属分支和文件归属
A 唯一负责 ui/live_data/live_data_hud.gd 的直播统计部分；先从最新 main 新建 D 盘独立工作树/分支，PR 目标 main。B 正改 PB-25 教学气泡，不改 Sandbox、教程或 Plan B 核心；E 的 PA-22 不动。

## Godot 开发环境
Godot 4.7.2；只用 D 盘工程/工作树/缓存/产物。

## 最小执行流程
确认资源文件→最小运行接线→最基础场景检查/截图→按子任务 commit，写 INT-22 log→开 PR。繁杂自动测试可跳过。

## 最终汇报
8 图到 UI 节点的对应表、Git commit、PR、左右两档分辨率截图和遗留问题。
