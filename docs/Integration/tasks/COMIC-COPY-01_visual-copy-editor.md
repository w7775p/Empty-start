# COMIC-COPY-01 · 开头 / 结局漫画可视化文案工具

**状态：实现待视觉验收**

## 开始前阅读
- `AGENTS.md`
- `project.godot`
- `docs/Original/任务卡模板.md`
- `docs/Integration/当前开发基线_2026-10-19.md`
- `ui/comic/comic_player.gd`
- `ui/comic/comic_caption_view.gd`、`comic_frame.gd`、`comic_caption.gd`

## 已经实现的功能
- P1～P4 使用 `data/comics/opening.tres`，共 13 个播放节点。
- P5～P6 使用 `data/comics/ending.tres`，共 6 个播放节点；这两幕属于**正式结局**。
- 漫画播放器根据 `ComicFrame`、`ComicCaption` 生成层、文字与动态表现。

## 本次任务
1. 提供可在 Godot 中单独运行的文案编辑场景，分开选择开头和结局，浏览全部 19 个播放节点。
2. 在原素材上叠加真实 `ComicCaptionView`，同步显示文案输入变化。
3. 支持新增、删除和选择文案框，编辑 speech、narration、danmaku 三种类型以及文本、位置、大小、尾巴、延迟。
4. 支持鼠标拖动文案框，编辑每格主字幕和最短播放时长。
5. 主动保存到两份正式 `.tres`，修改前可预览；原始 PNG 只读。
6. 文档说明使用步骤与预览边界。

## 本任务所属分支和文件归属
- Owner：本任务独立维护。
- 分支：`feat/comic-copy-visual-editor-20261019`；基于 `integrate/gamejam-shared-baseline-20261019`。
- 新增：`tools/comic_copy_editor/`；本任务不改主流程。
- Godot 4.7.2 / GDScript / PC 编辑用途。
- 工作目录：D 盘。

## 验收
- Godot 能加载编辑器场景，选择开头/结局与各分镜。
- 文字、位置、气泡类型实时预览；保存后重新载入一致。
- 实际视觉截图由人工验收补齐，随后再推进 PR 合并。

## 已验证
- Godot 4.7.2：headless 运行该场景 10 帧，退出且无脚本或资源加载错误。
- 使用副本 Resource 在 `res://.godot/` 执行保存/重载 smoke：13/6 帧、修改文字、原资源保持未改全部通过。
- 当前未修改 `data/comics/*.tres`、启动/结局路由、图片、原播放器。

## 后续
- 单独修正旧流程：开场调用 opening；通关后播放 ending，再衔接正式结局页面。
