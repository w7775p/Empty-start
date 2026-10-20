# EN-10 · 结局主图复用身份卡背面，三倾向仅换颜色

状态：P1，待开发；Owner：结局页面美术 Agent。**只做主图资源映射和局部视觉整理；漫画映射由另一位程序独立负责。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `data/ending/ending_main_art_config.tres` / `.gd`、`ui/ending/ending_page.tscn` / `.gd`、`docs/20. Ending/tasks/EN-02_main-art.md`。
- 用户的结局界面参考图用于最终构图验收；若执行者当前无法访问该图片，**只完成贴图与染色，不主观重排页面**，在 PR 标注待人工对照参考。

## 已经实现的功能
- 正式结局页面已有 `MainArt` TextureRect、`religion_name`、圣典、判词和音乐；`EndingPage.show_ending(display_data)` 接收显示快照。
- `data/ending/ending_main_art_config.tres` 已有正统、异端、荒谬三个 Texture2D 配置位，但当前三项均为 `null`，因此正式主图不显示。
- 现成图：`assets/ui/identity/cards/identity_card_back.png`。

## 本次任务
1. 将三个 `*_main_art` 配置全部指向同一张 **`identity_card_back.png`**，不复制生成三张新图片；保留 EN-02 原有 `get_main_art_for_tendency()` 和显示数据接口。
2. 在既有 `MainArt` 上使用 `modulate` 等 Godot 原生属性区分三种主导倾向；**暂以暖金、紫、青绿为候选配色，不是已审定色值**。仅调整图片本身的颜色，保留原图花纹与可读性；无效/空倾向回退原色。不要为了染色复制/生成三张新 PNG。
3. 主图沿用现有 `MainArt` TextureRect，保持宽高比；本卡**不负责结局页整体布局返工**。教名、圣典、判词、音乐以及滚动容器完全保持原接口。仅在出现明确的主图裁切/遮字时做最小的尺寸调整；参考图未能读取时，构图问题单独记录，不得凭空“复刻”。
4. **漫画严格出范围**：不改 `data/ending/ending_comic.tres`、`data/comics/*`、`ui/ending/ending_sequence_view.*`、`ui/comic/*`、场景路由、漫画播放或结束触发逻辑；不妨碍独立漫画程序。

## 本任务所属分支和文件归属
- 主要可写 `data/ending/ending_main_art_config.tres`、`ui/ending/ending_page.gd`；只有出现主图裁切/遮字时才动 `ui/ending/ending_page.tscn`。不改 `ending_main_art_config.gd` 的数据接口；漫画相关文件禁止修改。
- 最新 `main`、D 盘独立工作树、功能 PR → `main`；不与 PA-25 同时改共享 Theme 文件。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080；Godot-MCP-Native、godot_mcp。

## 最小执行流程
配置同一张卡背 → 结局页按主导倾向应用三种显示色 → 在已有 EndingPage 中核对**一张三色对照截图**（如无法合图，则附一张真实 Godot 图与三色配置）→ commit + 短 log + 功能 PR。遵循任务卡模板通用 14 项；无需重玩四关，也不等待漫画映射完工。

## 验收标准与最终汇报
- 三类结局都显示**同一张身份卡背面**，只有显示色区别，图片不失真、不卡住原教名/圣典/判词。
- 结局配置从 null 变为实际可用纹理，正式 UI 能读到。另一程序的漫画文件与调用完全不动。
- PR 标注配置位置、三种颜色、代码 SHA 和真实截图；参考图构图仍需用户视觉确认，**无图证保持 Draft，不自行声称通过**。
