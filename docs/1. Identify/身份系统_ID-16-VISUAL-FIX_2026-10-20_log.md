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
