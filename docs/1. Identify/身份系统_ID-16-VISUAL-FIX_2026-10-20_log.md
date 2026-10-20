# ID-16-VISUAL-FIX · 身份选择界面第三版（2026-10-20）

## 基线与范围
- PR #327；原始基线：已合并 PR #325 的 main，独立 D 盘工作树。
- 只改身份选择界面的场景、脚本、符号遮罩着色器与本文件；IdentityOptions、身份确认/存档接口原样保留。
- 前两版的 6×2 卡牌、正式羊皮纸背景、主次按钮素材和空白卡牌素材继续复用。

## 第三版视觉重组
1. 右侧作为身份预览：当前预览卡牌的原始符号从正式 identity_card_front_XX 图提取，叠到空白卡牌底板。Shader 透明化纸面底色，保留符号线稿。
2. 右侧详情纸下方集中两个小按钮：全部翻开/下一步。二者使用仓库主次按钮美术保持原图纵横比，取消居中悬浮于底边的孤立按钮区。
3. 右侧预览与左侧第一排顶端对齐，1280×720 与 1920×1080 采用不同的字号间距、按钮尺寸及卡牌区域上下留白；提升所选身份与 12 卡阵列的主次关系。
4. 增设可滚动的描述容器。窄屏长文案留在详情纸内部滚动，避免越过边框和装饰横线。
5. 键盘焦点采用深棕边框，正式选中才用金色边框；翻牌前显示问号和“尚未揭示”，避免提前剧透。

## Godot 运行验收
- Godot 4.7.2.stable.steam Windows OpenGL 3；场景 IdentitySelection；两档 1280×720、1920×1080 均实际运行。
- 三张真实截图：
  - evidence/ID-16-VISUAL-FIX_2026-10-20/identity_1280x720_back.png
  - evidence/ID-16-VISUAL-FIX_2026-10-20/identity_1280x720_selected.png
  - evidence/ID-16-VISUAL-FIX_2026-10-20/identity_1920x1080_selected.png
- 两档截图记录 ID16_SCREENSHOT_UNREVEALED status=0、ID16_SCREENSHOT_SELECTED status=0。
- 本地临时 GDScript 实测 ID16_VISUAL_REWORK_FUNCTION_PASS 12 cards / flip / select / next / reveal-all / long-description-scroll。
- 截图与短期测试脚本在本地 D 盘工作树生成，PR 仅附三张真实截图；未携带 Godot 自动生成的 import 改动。
- 完整游戏开局流程、手机触控尚未验收；本 PR 维持 Draft 等待用户对第三版视觉效果做最终判断。


## 2026-10-20 · 第三轮背景层级与底部操作区
- 遵循用户指定的 **全局压暗 + 中部提亮**：新增 `ui/identity_setup/identity_backdrop_spotlight.gdshader`，仅对正式羊皮纸背景叠加暖棕色渐变；边缘遮罩约 31%，中部约 5.5%，中心从视觉上相对提亮。源 PNG 保持原样。
- 12 张身份卡按钮默认样式加入轻微暖褐柔影：`shadow_size=5`、`shadow_offset=(0,3)`、`shadow_color alpha=0.13`；第二轮实际截图发现较重阴影形成深色方块后，已主动降低强度。
- `Navigation` 从右侧 `DetailsHolder` 迁回根节点底部，左侧次要动作和右侧主要动作各占一半宽度、间距 24；高度 110，沿用原有 `button_primary.png` / `button_secondary.png` 并以九宫格保持边框，适配两种分辨率。
- 独立更新 `NAVIGATION_RESERVED_HEIGHT=126`，给底部操作区预留区域，保留先前右侧预览图标、身份数据、单张翻牌、二次选中和长描述滚动。
- Godot 4.7.2 正式 `IdentitySelection` 场景以真实窗口 1280×720 / 1920×1080 渲染：每档 12 卡完整显示、整行按钮无裁切，图像见同目录 evidence。
- 行为验证通过：`ID16_VISUAL_REWORK_FUNCTION_PASS 12 cards / flip / select / next / reveal-all / long-description-scroll`。
- 本轮仍保持 PR #327 Draft，待人工视觉确认；无身份系统存档或战斗逻辑修改。

## 2026-10-20 · 第四轮返工：按钮边框比例及详情文字安全区
- 根因：旧九宫格直接对 391×359 原始按钮图片取边距（左右各 88px），在超过 900px 的通栏宽度下角部变成夸张胶囊；正文和空白卡美术边框仅相隔约十几像素，滚动文本触碰装饰线。
- 按钮：仍引用 `button_primary.png`、`button_secondary.png`；运行时先裁切正式按钮美术有效区域 (27,66,391,359)，缩放成 112×103 小尺寸九宫格素材，四边切分 23px 后仅水平延展中段，修复巨大圆角和扁平化变形。主/次按钮继续各占底部一半，间距与按键状态保持。
- 详情：`IdentityDetailsPanel` 的纸张安全边距提高为左右 36px、顶部 38px，新增 `InnerPadding` 独立 MarginContainer（左右 18px、上 10px、下 12px），避免描述文字压到纸边。保留原图边框与滚动行为；略微扩大详情宽度到 280–365px，高度 425px（紧凑）／565px（常规），缩短图案预览高度让正文有更多实际空间。
- 本次恢复原有 Shader 暗角与中心暖色提亮、卡牌轻投影不变。正式 Godot 4.7.2 实际窗口 1280×720 与 1920×1080 再次截图比对，按钮、卡面、详情全部可见。行为测试打印 `ID16_VISUAL_REWORK_FUNCTION_PASS 12 cards / flip / select / next / reveal-all / long-description-scroll`。
- 修改范围仅 `ui/identity_setup/identity_selection.gd` 与 `ui/identity_setup/identity_selection.tscn`；本 PR 继续 Draft，等待人工美术验收。

## 2026-10-20 · 卡背提示与翻开详情分态（第五轮）
- 右侧 `DescriptionScroll` 保留供翻开后的 `option.description` 显示；卡背时将其隐藏，改由独立的 `UnrevealedHint` Label 左对齐显示「请点击身份卡翻开」，卡背无滚动条。
- `IdentityDetailsName` 水平居中，翻开后身份名称例如「随侍」居中，配表描述继续左对齐。保留 `SelectionStatus` 和其余选择逻辑。
- Godot 4.7.2 / Windows OpenGL 3 真实运行：验证 12 卡、卡背提示无滚动、翻开后 `description == option.description`、切换到卡背再切回、长文本产生滚动条、第二次点击选择；1280×720 与 1920×1080 截图已输出，均返回 `PR327_CORRECTED_PASS` / exit 0。
- 修改范围：`ui/identity_setup/identity_selection.gd`、`.tscn`；后续界面美术仍等人工确认，保持 Draft。

## 2026-10-20 · 右侧预览字阶适配（第六轮）
- 症状：1280×720 下固定 19/30px 的描述/身份名显得偏大，1920×1080 下显得偏小。
- 在 `identity_selection.gd` 新增 `_fit_detail_typography(physical_height)`，按实际窗口高度在 720–1080px 之间连续插值，并限制上下界；视口变化时更新右侧标题、问号、身份名、状态、未翻牌提示、配表正文与行距。只在字号变化时覆写主题，避免布局反复振荡。
- 720px 时：正文及未翻牌提示 16、身份名 24、状态 14；1080px 时：正文 22、身份名 34、状态 18；中间分辨率线性过渡。
- 保留 `option.description` 作为翻开后的唯一配表文案、长文滚动、身份名居中、详情左对齐、卡背提示与翻牌/选择流程。
- Godot 4.7.2 / Windows / OpenGL 3 实际验收：1280×720 的 `PR327_TYPE_PASS height=720 body=16 name=24`，较大 Windows 窗口受桌面工作区限制为 1055px，回执 `PR327_TYPE_PASS height=1055 body=22 name=33`；两档均确认 12 卡、卡背提示、配表详情、长文滚动、两次点击选择；退出码均为 0。
- 本次新增截图在 `evidence/ID-16-VISUAL-FIX_2026-10-20/pr327_typography_720.png` 与 `pr327_typography_1055.png`，替代之前固定字号的预览供视觉验收。保持 Draft。

## 2026-10-20 · 移除详情状态提示（第七轮）
- 右侧身份预览的 `SelectionStatus` 节点设置为 `visible = false`，统一隐藏「等待翻牌」「当前选择／未确认」等状态文案，避免额外占用正文空间。
- 保留节点和既有脚本赋值，避免影响选择状态计算；卡背独立提示「请点击身份卡翻开」及翻开后配表 `option.description`、滚动能力保持。
- 使用 GitHub PR 最新脚本与场景在 Godot 4.7.2 / Windows 进行运行验收，`PR327_STATUS_PASS hidden in both states / configured details preserved`，退出码 0。测试后恢复 D 盘工作树原文件，保持 PR Draft。
