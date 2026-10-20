# PA-25 · 通用界面底板换成身份卡空白卡

状态：P1，待开发；Owner：通用 UI 美术 Agent。**本卡是美术接线，不是重做全局 UI。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `ui/theme/base_theme.tres`、`ui/identity_setup/identity_selection.tscn`。
- `ui/ending/ending_page.tscn`、`ui/rest/rest_result_view.tscn`（只读确认通用底板的调用情况）。

## 已经实现的功能
- 空白卡片图片：`assets/ui/identity/cards/identity_card_front_00_blank.png`。
- 通用 Theme 已有 `CardPanel`、`DialogPanel`，目前对应 `PanelCard`、`PanelDialog` 两种程序绘制的 StyleBoxFlat；已有页面依赖它们承载标题和正文。

## 本次任务
1. 将**通用内容面板的可见底板**替换成身份卡空白卡图片，优先从现有 `CardPanel`、`DialogPanel` 入手，在 `ui/theme/base_theme.tres` 复用一份纹理风格。图片保留边框/花纹及四角，不可将竖版卡图暴力拉伸变形；按已有面板尺寸使用合适的九宫格边距或同等原生方案。
2. 保留原面板内部布局、标题、内容、按钮、滚动和鼠标事件。原有文字必须可读；如果图片不适合某个超宽或全屏面板，**该面板先沿用旧底板并在日志列出**，不扩大到重构页面。
3. 通用底板仅面向承载信息的内容面板；**不覆盖身份系统12张身份卡、不替换三张发表话语卡、不改主菜单纯文字按钮/暂停背景、不修改底图原始 PNG**。已有独立美术底板的场景继续使用各自美术。
4. 仅检查两处真实通用面板（例如结算与历史收藏）是否正常显示；不为了“全局统一”逐页人工调参。

## 本任务所属分支和文件归属
- 主要可写文件仅 `ui/theme/base_theme.tres`；确实无法通过现有 Theme 纹理 StyleBox 覆盖的局部容器，仅记录后续待办，不跨 Owner 改场景。
- 从开发时最新 `main` 建 D 盘独立工作树，功能 PR → `main`；开始前核对唯一 Owner。与 EN-10 不共同修改结局页，避免文件争用。
- 不触碰任何剧情、结算、导表或漫画相关代码。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080 逻辑画布；Godot-MCP-Native，API 文档 godot_mcp。

## 最小执行流程
确认 Theme 与原图 → 替换原有 StyleBox/可复用纹理 → 运行已有结算/历史页 → 截**一张**实际 Godot 画面（必要时附第二张对比）→ commit、短 log、独立 PR。常规规范遵循 `docs/Original/任务卡模板.md` 14 项，不另建框架。

## 验收标准与最终汇报
- 通用信息面板真实显示空白身份卡纹理，装饰未明显变形，内容/按钮可读可点击；不影响主菜单、身份牌及战斗三卡。
- PR 写出替换的 Theme 项、未适配的大尺寸容器、截图分辨率和 commit SHA；无可看真实截图则 Draft，人工验收前不合并。
