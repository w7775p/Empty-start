# 身份系统 ID-16-VISUAL-FIX · 2026-10-20

## 基线与范围
- 从最新 main（开发开工时 52572092，已包含 PR #325）独立分支 fix/id16-identity-parchment-ui-20261020 开发。
- 仅修改 `ui/identity_setup/identity_selection.gd`、`.tscn`，保持 IdentityOptions / selection_changed / next_requested 与 ID-09 存档接口原样。
- 原本 D:\Godot\Empty-start 的未提交修改保持不变；全部工作与 Godot 缓存在 D 盘独立工作树进行。

## 实现
1. 正式羊皮纸背景上的深色覆盖透明度从 0.68 降到 0.06，标题与操作提示采用深褐色。
2. 卡背完整显示素材，移除 12 张卡上遮挡图案的「身份牌/点击翻开」叠字；页面顶部统一给出翻开与再次选择说明。翻牌前详情暂不透露该卡的真实身份与文案。
3. 底部「一键翻开」用 `assets/ui/buttons/button_secondary.png`， 「下一步」用 `assets/ui/buttons/button_primary.png`，引用原图实际有色区域并以九宫格适配水平按钮；完整处理正常、悬停、按下、禁用状态和文本颜色。
4. 右侧详情把 `assets/ui/identity/cards/identity_card_front_00_blank.png` 作为 StyleBoxTexture 底板，保留原画边框；独立 DetailsHolder 限制卡片实际高度为 420，随窗口宽度调节宽度。正文采用深墨色以提升可读性。
5. 修复 1920×1080 时卡片最小宽度反向扩张布局的问题：列宽从实际物理视口可用宽度计算；卡片与详情分区保留 6×2 和小窗口滚动行为。布局信号按帧合并，避免重复排版。

## 最小验证
- 实际 Godot 4.7.2.stable.steam（Windows OpenGL3）载入正式 `IdentitySelection` 场景，在 1280×720 和 1920×1080 两种真实窗口尺寸运行。
- 每种分辨率均确认 12 张身份卡存在；运行演示了未翻开状态、使用现有全翻逻辑及选择第 1 张身份卡。关键截图：
  - `evidence/ID-16-VISUAL-FIX_2026-10-20/identity_1280x720_back.png`
  - `evidence/ID-16-VISUAL-FIX_2026-10-20/identity_1280x720_selected.png`
  - `evidence/ID-16-VISUAL-FIX_2026-10-20/identity_1920x1080_selected.png`
- 运行日志包含两次 `ID16_SCREENSHOT_* status=0`；实际 Godot 渲染与 GDScript 解析通过，无目标脚本错误。
- 修改范围局限于身份选择页面；尚未进行完整身份创建与存档流程、Android 真机及最终真人美术审查。请保留 PR 待用户视觉验收。

## 交接
本 PR 的每张实际截图已附到仓库，可直接打开查看，不依赖本机路径。审美确认后由总控决定合并；若需微调，仅调整 `_button_style` 的九宫格边界、`_configure_detail_panel` 的内容边距和顶部文案样式。
