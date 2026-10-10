# SD-02 漫画气泡 3 套美术预览｜2026-10-10

本次新增三套**独立美术方向的 Godot 可运行预览**，提供策划实际对比和选型。继续使用项目正式仓鼠立绘 `res://assets/characters/player/hamster_idle.png`。三套方案在同一画面横向对照，共享文字内容、人物缩放、对话数量和视口条件。

**预览阶段**：尚未将任何一套替换到正式 `StreamerBubbleView` 或 `StreamerBubbleStack`，也未对既有 Sandbox 接口、SD-01 配置或正式动画做更改。PR #131 保持开放，等待策划选定方案。

## 三个方向

| 方案 | 参考方向 | 实际实现 | 侧重点 |
| --- | --- | --- | --- |
| **A 轻量短句** | DELTARUNE 式文字框 | 深海军蓝矩形与细边框，最新一句薄荷绿高亮，旧句降为细窄记录框 | 高频发言、快速识别、最少遮挡 |
| **B 侧边对白卡** | Hi-Fi RUSH 式图形语言 | 锐角倾斜剪纸卡、黑色硬阴影，黄 / 粉 / 青层级，最新句带 LIVE 标签 | 强风格化、活泼、方便长句 |
| **C 漫画主气泡** | TWEWY / 日漫气泡概念 | 乳白超椭圆主气泡、漫画尖尾，前两条转为无尾浅色旁注 | 漫画味、角色表演与重点发言 |

实际造型为本项目新绘制的 Godot 矢量图形，仅借鉴上述作品的总体视觉语言。三套均显示原文完整文字；一条主对白加两条历史对白；主要位于主播立绘下方左侧，让角色眼睛和脸部保持可见。B 目前是三套中最鲜艳的方案，A 最克制，C 更偏漫画叙事。

## 运行与切换

- 直接用 Godot 4.7.2 运行 `res://scenes/demos/sd02_style_compare_demo.tscn`。
- `1`：短句；`2`：中句；`3`：长句；`R / Space`：切换下一组台词。
- 从同一立绘与同一句台词，直观比较短、中、长文本时的遮挡和排版效果。
- 批量实际截图：Windows Godot 图形模式下执行 `--script res://scenes/demos/sd02_style_capture.gd`，生成本目录下五张截图。

| 图像 | 用途 |
| --- | --- |
| `sd02_three_styles_short_1920.jpg` | 三列同屏，短句，1920×1080 |
| `sd02_three_styles_medium_1920.jpg` | 三列同屏，中句，1920×1080 |
| `sd02_three_styles_long_1920.jpg` | 三列同屏，长句，1920×1080 |
| `sd02_three_styles_short_1280.jpg` | 短句，1280×720 |
| `sd02_three_styles_long_1280.jpg` | 长句，1280×720 |

## 验证

Godot `4.7.2.stable.steam.ed1daf0bf`，Windows AMD Radeon OpenGL Compatibility；`sd02_style_capture.gd` GPU 渲染退出码 0，所有五张 JPG 成功生成且尺寸准确，stderr 无新增错误。实际预览已人工检查，三种方案和正式仓鼠立绘均可见，长句分行后文字完整。此处仍属于**美术方案对比**；用户选择后，才将对应造型、字体、文字排版、生命周期应用到正式 SD-02 组件，并进行双主播及正式 Sandbox 全面验收。
