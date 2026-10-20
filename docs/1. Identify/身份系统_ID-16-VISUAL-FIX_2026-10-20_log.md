# 身份系统 ID-16-VISUAL-FIX · 2026-10-20（二次视觉返工）

## 基线与提交范围
- 从已合并 #325 的 `main` 建立 PR #327，分支 `fix/id16-identity-parchment-ui-20261020`，本次继续在同一分支调整。
- 唯一运行文件：`ui/identity_setup/identity_selection.gd`、`ui/identity_setup/identity_selection.tscn`。未改身份业务配置、其他 Agent 的工作树和保存逻辑。

## 第一版已具备
- 资源直接引用：`assets/ui/buttons/button_primary.png` / `button_secondary.png`、`assets/ui/identity/cards/identity_card_front_00_blank.png`。
- 羊皮纸背景的暗色遮罩 0.68 → 0.06；移除卡背冗余叠字；翻牌前身份详情隐藏真实身份；保留 6×2 同屏卡、焦点和单选语义。
- 在 1280×720、1920×1080 根据可用宽度约束卡片尺寸，避免布局溢出。

## 二次视觉返工
1. 主内容整体下移：标题引导后添加约 50px 的空间，将两排卡及右侧档案作为单独视觉组合，减轻过度顶边与底部留白。
2. 取消身份卡下缘外贴的纯色标题条：名称用真实深棕色、`ZCOOLKuaiLe` 字体写到空卡片纸面内，与原素材底边装饰保留独立间距。
3. 主、次按钮分别使用素材的有效像素裁切，并按源图约 1.09:1 比例整体缩放至 154×140；取消原先横向九宫格扁平拉伸，保持默认、悬停、按下、禁用状态和相应文字对比。
4. 右侧延用空白卡牌素材，内容明确命名为「身份档案」；依据正式内容区可用高度自适应详情板长度（最高 620px），令其跨越两排卡牌，避免像第 13 张卡片。
5. 提升顶部标题字号至 44、引导至 22，右侧身份名称字号 30、状态 17；版面只在既有场景中改变。

## 验证
- Godot `4.7.2.stable.steam` Windows OpenGL 3 实际运行两档：1280×720、1920×1080；截图均来自正式 `IdentitySelection` 节点实例（非人工合成）。
- `identity_1280x720_back.png`：未翻开 12 卡、主次按钮。
- `identity_1280x720_selected.png`：全翻开并选中第一个身份。
- `identity_1920x1080_selected.png`：完整大分辨率布局，右侧说明、纸面卡名和底部导航无裁切。
- `tests/_id16_visual_workflow_check_tmp.gd` 是本地短期验证脚本，不提交仓库。执行回执：`ID16_VISUAL_REWORK_FUNCTION_PASS 12 cards / flip / select / confirm state / reveal-all`。
- 范围仅 UI：未测试完整跨页身份建立、存档、Android 触控；保留 PR Draft 等待真人美术验收。

## 交接
代码与三张真正 Godot 截图均在 PR #327。该 PR 为视觉候选，不由自动化截图数替代策划的通过判定。
