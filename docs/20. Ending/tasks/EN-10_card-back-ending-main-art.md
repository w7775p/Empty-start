# EN-10 · 结局主图复用身份卡背面，三倾向仅换颜色

状态：P1，待开发；Owner：结局页面美术 Agent。**只做主图资源映射和局部视觉整理；漫画映射由另一位程序独立负责。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `data/ending/ending_main_art_config.tres` / `.gd`、`ui/ending/ending_page.tscn` / `.gd`、`docs/20. Ending/tasks/EN-02_main-art.md`。
- **用户提供的结局界面参考图**：用于最终构图核对；本次可读取上下文中未附该图，实施时需能看到该图，但**不阻断先完成主图贴图与染色**。

## 已经实现的功能
- 正式结局页面已有 `MainArt` TextureRect、`religion_name`、圣典、判词和音乐；`EndingPage.show_ending(display_data)` 接收显示快照。
- `data/ending/ending_main_art_config.tres` 已有正统、异端、荒谬三个 Texture2D 配置位，但当前三项均为 `null`，因此正式主图不显示。
- 现成图：`assets/ui/identity/cards/identity_card_back.png`。

## 本次任务
1. 将三个 `*_main_art` 配置全部指向同一张 **`identity_card_back.png`**，不复制生成三张新图片；保留 EN-02 原有 `get_main_art_for_tendency()` 和显示数据接口。
2. **只通过 `MainArt.modulate` 等原生显示颜色区分三种主导倾向**：正统金黄/暖金、异端紫色、荒谬青绿。颜色仅作为初始展示参数，确保原图轮廓、符号和文字不被颜色吞没；无效/空倾向为原色安全回退。**不可把身份卡正面当结局图**。
3. 结局主图沿用原 TextureRect 层级，避免把小竖图强拉到全屏；保留教名、圣典、判词和音乐的真实数据来源。若参考图有构图差异，只在已有 `ending_page.tscn` 内做必要的尺寸/位置/留白调整，不新增结局演出或背景资产。
4. **漫画严格出范围**：不改 `data/ending/ending_comic.tres`、`data/comics/*`、`ui/ending/ending_sequence_view.*`、`ui/comic/*`、场景路由、漫画播放或结束触发逻辑；不妨碍独立漫画程序。

## 本任务所属分支和文件归属
- 可写 `data/ending/ending_main_art_config.tres`、`ui/ending/ending_page.gd` 和确有布局需要时 `.tscn`；不改 `ending_main_art_config.gd` 的数据接口。先确认其他 Agent 是否认领结局页或漫画入口，冲突时仅等待对应文件释放。
- 最新 `main`、D 盘独立工作树、功能 PR → `main`；不与 PA-25 同时改共享 Theme 文件。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080；Godot-MCP-Native、godot_mcp。

## 最小执行流程
配置同一张卡背 → 结局页按三倾向应用三种显示色 → 运行正式 EndingPage 的三类显示状态，保留**至少一张**真实 Godot 截图，颜色有争议时用同一张拼图对照 → commit + 短 log + 功能 PR。遵循任务卡模板通用 14 项；无需完整重玩四关。

## 验收标准与最终汇报
- 三类结局都显示**同一张身份卡背面**，只有显示色区别，图片不失真、不卡住原教名/圣典/判词。
- 结局配置从 null 变为实际可用纹理，正式 UI 能读到。另一程序的漫画文件与调用完全不动。
- PR 标注配置位置、三种颜色、代码 SHA 和真实截图；参考图构图仍需用户视觉确认，**无图证保持 Draft，不自行声称通过**。
