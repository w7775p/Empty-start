# PA-25 · 通用界面底板换成身份卡空白卡

状态：P1，待开发；Owner：通用 UI 美术 Agent。**本卡是美术接线，不是重做全局 UI。**

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `ui/theme/base_theme.tres`、`ui/identity_setup/identity_selection.tscn`（仅参考卡片贴图及其比例）。
- `ui/ending/ending_page.tscn`、`ui/rest/rest_result_view.tscn`（只读确认通用底板的调用情况）。

## 已经实现的功能
- 空白卡片图片：`assets/ui/identity/cards/identity_card_front_00_blank.png`。
- 通用 Theme 已有 `CardPanel`、`DialogPanel`，目前对应 `PanelCard`、`PanelDialog` 两种程序绘制的 StyleBoxFlat；已有页面依赖它们承载标题和正文。

## 本次任务
1. **只处理通用内容卡片样式 `CardPanel`**：将 `identity_card_front_00_blank.png` 接入其现有 Theme 样式，在不裁掉花纹、扭曲四角的前提下适配卡片容器；必要时使用 Godot 原生 `StyleBoxTexture` 九宫格。**不在本卡直接全局替换 `DialogPanel`**，因为该样式还用于宽幅结算/全屏历史窗口，盲换一张竖卡有大面积变形风险。
2. 原文本、内边距、按钮、滚动和鼠标行为保持不变。先用一处现成 `CardPanel` 页面检查是否变形；如果原图内部花纹无法安全九宫格拉伸，**不要强行交付全局变形效果**，写明具体症状与受影响节点，留给人工确认，无需重建主题系统或逐页做补丁。
3. 通用底板仅面向承载信息的内容面板；**不覆盖身份系统12张身份卡、不替换三张发表话语卡、不改主菜单纯文字按钮/暂停背景、不修改底图原始 PNG**。已有独立美术底板的场景继续使用各自美术。
4. 验证一处真实使用 `CardPanel` 的页面及其文字布局；`DialogPanel` 保持原样。不做全站逐页回归。

## 本任务所属分支和文件归属
- 主要可写文件仅 `ui/theme/base_theme.tres`；确实无法通过现有 Theme 纹理 StyleBox 覆盖的局部容器，仅记录后续待办，不跨 Owner 改场景。
- 从开发时最新 `main` 建 D 盘独立工作树，功能 PR → `main`；开始前核对唯一 Owner。与 EN-10 不共同修改结局页，避免文件争用。
- 不触碰任何剧情、结算、导表或漫画相关代码。

## Godot 开发环境
Godot 4.7.2 / GDScript；Windows PC；1920×1080 逻辑画布；Godot-MCP-Native，API 文档 godot_mcp。

## 最小执行流程
确认 Theme 与原图 → 替换原有 StyleBox/可复用纹理 → 运行已有结算/历史页 → 截**一张**实际 Godot 画面（必要时附第二张对比）→ commit、短 log、独立 PR。常规规范遵循 `docs/Original/任务卡模板.md` 14 项，不另建框架。

## 验收标准与最终汇报
- 现有 `CardPanel` 的内容卡片能显示空白身份卡纹理且无明显变形、遮字或输入异常；`DialogPanel`、主菜单、身份牌和战斗三卡保持原样。
- PR 写出替换的 Theme 项、保留的宽幅 `DialogPanel`、截图分辨率和 commit SHA；无可看真实截图则 Draft，人工验收前不合并。
