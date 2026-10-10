# PA-04｜01 GLASS NOIR 强度视觉修订（2026-10-10）

此分支仅供视觉评审，未合并正式 PR #112。收到反馈：旧 S3 右上斜线和双层内框像“刻痕”，与“强度越高越让玩家想打”的视觉目标背离，现已改为**亮度、外发光、字重**明确递进。

## 统一颜色（倾向）
- 正统 `#1658A2`；异端 `#B9502D`；荒谬 `#B7865B`；Neutral `#ADA4A3`。
- 所有档位保留 01 GLASS NOIR 色系。文字基础字号 24px、尺寸随文本自适应，不改变判定与生命周期。

## 强度与视觉权重

| | S1 普通 | S2 值得注意 | S3 高优先级 |
| --- | --- | --- | --- |
| 玻璃颜色混合 | 0.16 | 0.38 | 0.62 |
| 玻璃 alpha | 0.66 | 0.84 | 0.95 |
| 边框 | 1px 低亮 | 2px 明亮 | 3px 最亮 |
| 视觉外光 | 无 | 8px 柔和常亮 | 13～20px 随时间缓慢呼吸 |
| 字体 | 24px 普通字重 | 24px 普通字重 | 24px 加重 FontVariation，3px 文字描边 |
| 装饰 | 顶部低透明反射 | 顶部浅反射 | 顶部更亮反射 |

**已移除**：S3 左侧竖条、斜向切痕、双层硬内框及局部钻石刻纹。当前演示使用 `BarrageGlassSurface` 的 StyleBox 阴影形成真正可感知的外发光，呼吸节奏约 1.85 秒一轮，运行时只有 S3 做限频重绘。

## 实际工程验证
- 脚本：`pa04_noir_strength_surface.gd`、`pa04_noir_strength_preview.gd` Godot 4.7.2 `--check-only` exit 0。
- 真实图形运行：1920×1080，OpenGL Compatibility，`pa04_noir_strength_comparison.jpg` 和 `pa04_noir_strength_comparison_breathing.jpg` 两个时刻均保存成功，exit 0，未出现脚本 stderr。
- 每种倾向同一句文字纵向对照 S1/S2/S3，底部另有三档放大版。外光效果是否适度，等待负责人看截图后决定。
- 预览入口：`res://scenes/demos/pa04_noir_strength_preview.tscn`；截图入口：`res://scenes/demos/pa04_noir_strength_capture.tscn -- --capture-strength`。
