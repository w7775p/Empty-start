# 开头 / 结局漫画可视化文案编辑器

## 打开

1. 在 Godot 项目的「文件系统」中打开 `res://tools/comic_copy_editor/comic_copy_editor.tscn`。
2. 按 **F6（运行当前场景）**。建议最大化运行窗口。
3. 顶部选「开头 · P1–P4」或「结局 · P5–P6」，左边选分镜，中间预览，右边编辑文案。
4. 点击画面上的文案区域可选中、拖动；也可在右边直接输入坐标、尺寸、尾巴方向和延迟。
5. **Ctrl+S** 或点「保存两段文案」后，直接写回 `data/comics/opening.tres` 和 `data/comics/ending.tres`。随后可用 Git 比较差异并提交。

## 能修改什么

- 每格的主字幕（`ComicFrame.text`）、基础时长（`seconds`）
- 每个文案框的类型（speech/narration/danmaku）、文本、位置及尺寸、尾巴目标点、延迟秒数
- 新增和删除文案框
- 同一分镜多气泡独立编辑；原画 `assets/manga/P1`～`P6` 保持只读

## 预览边界

- 使用生产版 `ComicCaptionView`，文本外形、背景与字号与实际播放器共用一份代码。
- 中间画面展示**当前分镜最终合成状态**，实时动画、屏幕震动、翻书声、字幕逐字效果仍以正式 `ui/comic/comic_player.tscn` 运行结果为准。
- 文案区显示完整文字。正式运行时依照 delay、characters_per_second 与 seconds 播放；长文案会延长每格实际停留时间。
- 保存会改写 Godot 资源文本的格式和资源内部 ID；请在独立开发分支操作并用 Git 审核差异。保存前的修改仅驻留内存，关闭工具即可放弃。

## 特别注意：开头与结局归属

- `data/comics/opening.tres` = P1～P4，13 个播放节点。
- `data/comics/ending.tres` = P5～P6，6 个播放节点，**属于真正结局**。
- 目前旧主流程仍将两段在首次 Boot 中合并播放（`intro`）。本工具只负责文案编辑；正式流程需另卡纠正为启动只播 opening、通关后播 ending，然后衔接 `EndingPage`。

## 文件归属

本工具新增独立场景和脚本，复用现有 ComicSequence、ComicFrame、ComicCaption 与 ComicCaptionView。未修改主流程、原图片和剧情资源内容。

## 大字与字体

右侧点击 **＋ 大字**，创建无底框、无尾巴的纯 Label 文案。连续点击两次可以分别在左右位置创建两条文字。新条目的“**大字**”仅作填写提示，请在右侧“文案内容”中换成最终文字。字体支持项目自带 **Noto Sans SC** 和 **ZCOOL KuaiLe**，可调字号（12–300）、文字颜色、位置和尺寸。所有普通气泡也可以单独调整字体和字号。

## 选中文字添加动态特效

在右侧“文案内容”中选中几个字，点 **粗体 / 金色 / 抖动 / 波浪 / 脉冲**；没有选中文本时作用于整条。编辑器和正式漫画都用 RichTextLabel 呈现 BBCode，F6 运行时即可看到动态效果。保存会把 BBCode 字符串写入原有 .tres 文案资源。原图不变。
