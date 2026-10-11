# PA-06 漫画命中符号四方案｜Godot 实机预览（2026-10-10）

## 设计结果与选择状态
本次按策划要求绘制四套独立、带透明背景的碎裂/冲击强调符号。**四套均处于待美术选定状态**。当前 PA-06 Inspector 中暂用 01 号作为演示默认贴图，最终采用哪一套以及尺寸位置将由策划依据实机预览确认。

| 编号 | 设计方案 | 实际图形语言 | 独立 PNG / 矢量源 |
| --- | --- | --- | --- |
| 01 | RAZOR COLLAGE / 锐利拼贴 | 非对称尖角、奶油白纸片、中央珊瑚红破裂 | `impact_01_razor.png/.svg` |
| 02 | BRUSH INK / 粗笔触 | 粗重墨迹、锐角斜切、手绘红色划破、飞散碎墨 | `impact_02_ink.png/.svg` |
| 03 | COMIC KRAK / 拟声字体 | **手绘矢量路径**组成的「KRAK!」拟声，不含字体 Label/文字节点；红色斜破裂线穿字 | `impact_03_krak.png/.svg` |
| 04 | MANGA BURST / 漫画漫符 | 双层放射型裂开符号、参差尖角、飞散碎片 | `impact_04_manga.png/.svg` |

上述美术造型参照四个方向的视觉语言重新制作，没有直接复制第三方素材。源文件全部位于 `assets/ui/combat/impact_marks/`，PNG 均是 **512×512 RGBA 透明 PNG**，四角 alpha=0，SVG 是独立可编辑路径。通过 `res://scenes/demos/pa06_export_impact_marks.gd` 使用 Godot 原生 SVG Rasterizer 统一按 2× 输出。

## Godot 中的实际预览
- 四宫格演示：`res://scenes/demos/pa06_mark_variants_demo.tscn`，在真实 PA-04 / PA-05 弹幕中，为四个同内容同强度对象分别触发相同 `BarrageImpactFx.play_fracture()`，**四个方案仅替换 `accent_texture`**。
- 操作：F6 运行独立场景；R 四方案重放；Space 暂停/继续。固定 1920×1080 的截图入口：`res://scenes/demos/pa06_mark_variants_capture.tscn -- --capture-pa06-marks`。
- 实际 GPU 截图：`docs/Shared/PresentationAssets/previews/pa06_four_marks_before.jpg`、`pa06_four_marks_impact.jpg`、`pa06_four_marks_followthrough.jpg`。各 1920×1080。
- 已重拍旧演示 `pa06_impact.jpg`、`pa06_followthrough.jpg`，避免 PR 仍展示曾被否决的字体 Σ。

## 正式运行组件的修改
- `BarrageImpactFx._show_accent()` 只使用 TextureRect 显示独立 PNG，**已移除旧的数学符号 Label fallback**。当 `accent_texture == null` 时不生成符号实例。
- `BarrageImpactPresenter.impact_symbol_texture` 与 `BarrageImpactFx.accent_texture` 均提供 Inspector 参数，单贴图入口可以直接在四个 PNG 之间切换；调整 `impact_symbol_size`、`impact_symbol_offset` 可优化游戏中实际尺寸与位置。
- 运行系统维持 `BarrageTraitResult`、原 `BarrageView`、PA-04 的玻璃/颜色、PA-05 的材质与后续 BT-06 真实子话语接线。没有增加新游戏资源数值或碰撞对象。

## 验收记录
- Godot 4.7.2 Windows OpenGL Compatibility：四张透明 PNG 原生导出 exit 0，全部 512×512 / corner alpha=0；四宫格 GPU 图形运行 exit 0，三张 1920×1080 截图生成成功，stderr 无脚本错误。
- PA-06 现有 **5 组外部行为场景通过**；PA-05 4 组、PA-04 4 组回归通过。对同位置真实碎裂事件的四种方案已经完成视觉对照。
- 仍待策划选定 01 / 02 / 03 / 04 或指定混搭微调，然后正式确定默认贴图。当前 PR #132 继续开放供视觉评审。
