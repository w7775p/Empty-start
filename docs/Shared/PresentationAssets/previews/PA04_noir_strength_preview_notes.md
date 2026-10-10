# PA-04｜01 GLASS NOIR 强度样式对照｜2026-10-10

这是一张等待美术确认的**独立 Godot 实景预览**。不修改正式 PR #112，既有四种倾向色与 24px 基础字号保持一致。

## 倾向配色（已选 01）
- 正统 `#1658A2`
- 异端 `#B9502D`
- 荒谬 `#B7865B`
- Neutral `#ADA4A3`

## 三档强度
| 材质层 | S1 基础 | S2 强调 | S3 强目标 |
| --- | --- | --- | --- |
| 外框 | 1px | 2px | 3px |
| 玻璃透明度 alpha | 0.63 | 0.77 | 0.89 |
| 底板色混合比例 | 0.18 | 0.27 | 0.36 |
| 折光 | 右上薄反光 | 右上切面与局部反射 | 双层内框、右上双切面、下缘厚度 |
| 文字 | 24px 常规 | 24px 常规 | 24px FontVariation +0.34 加粗、描边 3px |

所有强度均取消左侧竖向专属装饰，也取消旧实现横贯全板的按钮式顶部反光。四倾向同一句文本分别在 S1～S3 对照；底部额外显示三档放大细节。针对 S3 使用 `FontVariation` 做字重变化，避免先前 BBCode `RichTextLabel` 截断问题。

## 演示
- 真实 PackedScene：`res://systems/barrage_generation/barrage_view.tscn`
- 预览场景：`res://scenes/demos/pa04_noir_strength_preview.tscn`
- 截图：`res://scenes/demos/pa04_noir_strength_capture.tscn -- --capture-strength`
- 截图输出：`docs/Shared/PresentationAssets/previews/pa04_noir_strength_comparison.jpg`，1920×1080
- 表现脚本：`scenes/demos/pa04_noir_strength_surface.gd`，只用于当前演示；确认后再把定稿样式转入正式 PA-04 组件。

验证：Godot 4.7.2，脚本 `--check-only` 成功，OpenGL Compatibility 实际 GPU 截图退出码 0，无新增 stderr 错误。材质结构仍需负责人看画面确认；真实密集弹幕下的对比与移动端阅读测试留待集成。