# PA-04｜三套设计师配色预览（2026-10-10）

**本分支为色彩预览，不会改变 PR #112 的正式玻璃组件，也不代表最终 S1～S3 强度表现。**

- 参考一：[Aavatto，Glassmorphism Chat Application UI Kit](https://dribbble.com/shots/14796692-Glassmorphism-Chat-Application-UI-Kit)。GLASS NOIR：正统 `#1658A2`、异端 `#B9502D`、荒谬 `#B7865B`、Neutral `#ADA4A3`；背景 `#070C16`。
- 参考二：[Yatish，Direct Messaging App Design using glassmorphism](https://dribbble.com/shots/14741658-Direct-Messaging-App-Design-using-glassmorphism)。SOFT GLASS：正统 `#66CADE`、异端 `#C8948F`、荒谬 `#E3B688`、Neutral `#C4D4C3`；背景 `#17121A`。
- 参考三：[Jasmine Shahinpour，AI Chat Bot UI Concept](https://dribbble.com/shots/26842736-AI-Chat-Bot-UI-Concept)。DIGITAL RITUAL：正统 `#5B99D9`、异端 `#9A69A5`、荒谬 `#B7865B`（借用一号参考的旧金以拉开倾向）、Neutral `#C5BECA`；背景 `#090A20`。

这些是根据作品色板为四倾向重新组合的配色实验，不意味着源作品采用了这些游戏倾向定义。

## 实际运行入口

- 交互：`res://scenes/demos/pa04_designer_palette_preview.tscn`，使用数字键 1 / 2 / 3 切换配色。
- 全高清截图：`res://scenes/demos/pa04_designer_palette_capture.tscn -- --capture-designer`。
- 已输出的四张 JPG 位于同级目录：`pa04_designer_palettes_comparison.jpg`、`pa04_designer_01_NOIR.jpg`、`pa04_designer_02_SOFT.jpg`、`pa04_designer_03_RITUAL.jpg`。三个独立文件均基于 1920×1080 的 Godot 4.7.2 GPU 渲染帧。

## 设计和工程约束

每种配色沿用现有 `BarrageView` 和 `BarrageGlassSurface`，以真实 `BarrageRuntimeRecord` 的倾向和强度绘制。未改变原文、移动与判定机制。演示中 S1、S2、S3 的边框/透明度/高光为**待筛选的结构草案**；正式强度层次以及 S3 富文本粗字重表现另需 PA-04 视觉验收与修复。当前截图没有 S3 左侧专属竖条。

当前不提交正式配色或修改 `main`，选择方案后再更新 PR #112。