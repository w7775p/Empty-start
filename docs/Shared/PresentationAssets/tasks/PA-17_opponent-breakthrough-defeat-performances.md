# PA-17 真矛盾击破：对手三种专属击败演出与未击破离线

> 状态：需求已确认，待实施
> 类型：程序美术 / PresentationAssets
> 依赖：CB-07 `outcome_locked`、CB-09/CB-10 现有结果分流；PA-12 Paradox 结果提示；PA-15 阶段立绘映射

## 开始前阅读
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md` 与最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/12. ContradictionBreak/README.md`、`docs/13. FinalOracle/README.md`（若有）
- `docs/Shared/PresentationAssets/tasks/PA-12_paradox-comic-transition-visual.md`
- `docs/Shared/PresentationAssets/tasks/PA-15_opponent-tier-portrait-flip-and-sweat.md`

## 最新策划配置来源（2026-10-10）
- 对手表现资源从 `02_主播关卡.portrait_set_id` 定位 `23_对手立绘配置`；使用其中 `defeat_asset_path`、可选 `defeat_transition_asset_path` 和 `defeat_effect_id` 选择本场演出。
- 已登记 `alien_melt`（外星人融化）、`kiwi_wobble`（Kiwi整图乱舞）、`fox_petal_rain`（狐狸花瓣雨）三种对手演出标识；具体美术与时序沿用本卡下述已确认需求。
- 第四关青蛙 `frog` 的专属素材和演出方案留待后续策划交付，再补到相同配置入口。

## 画面结果对应关系
- **进入 Paradox 时**，对手仍展示 T5 使用的 `{opponent}_tier_03.png`。
- **真实命中真矛盾并得到正式 BREAKTHROUGH 结果后**，才执行以下专属击败动画，动画结束时切至 `{opponent}_defeat.png`。
- **未击破（只中假句、落空、超时）时**，继续展示 T5 的 `tier_03`，播放短促离线演出；无需使用 defeat 图片。两种 Paradox 结果最终都遵照 PA-19 回房间结算，但成功方仍先走既有 FinalOracle 正式确认与奖励流程。

## 本卡：角色专属击败动画
### 1. 外星人（alien）：融化
- 资源：`assets/characters/opponents/alien/alien_tier_03.png`、`alien_defeat_transition.png`、`alien_defeat.png`。
- 从 T5 立绘开始向下松弛、局部波动；短暂展示现有**融化过渡帧**，同时做边缘波形 / 向下拉伸、整体压扁坍塌；自然过渡到已经提交的倒地 / 融化完成图 `alien_defeat.png`。
- 使用现有 Tween / Shader 完成动态伸缩和软体扭曲，过渡时长、局部强度、画面震颤可调。

### 2. 狐狸（fox）：花瓣雨
- 资源：`assets/characters/opponents/fox/fox_tier_03.png`、`fox_defeat.png` 与 `fox/effects/fox_rose_01～04.png`。
- 用**现有四张玫瑰 / 花瓣贴图**组合粒子流：上方和两侧先有少量花瓣飘入，继而一阵密集花瓣雨从上落下，粒子具有旋转、飘动、速度差、透明度变化。
- 花瓣形成短暂视觉遮挡时，右侧直播画面下的狐狸立绘切成 `fox_defeat.png`；花瓣逐渐散开，露出击败图。
- 采用 Godot 2D 粒子 / Node2D+Tween，数量、速度、大小与持续时间集中可调；保持 16:9 主画面可读。

### 3. Kiwi：先用原 PNG 整图模拟乱舞（方案 A）
- 资源：`assets/characters/opponents/kiwi/kiwi_tier_03.png`、`kiwi_defeat.png`。
- 先使用**整张立绘**做左右剧烈摇晃、连续角度摆动与局部弹性扭曲（上半身 / 两侧翅膀区域摇摆、下半身节奏交错伸缩），让人视觉上感到翅膀和双腿同时乱甩；中途可辅以速度线。
- 摇摆动作频率逐渐加速再骤停，切入 `kiwi_defeat.png` 并回弹到稳定状态。
- 第一版用现有整图、Tween / Shader / 遮罩实现；**试玩后如果肢体动作不够明确，再由策划决定是否让美术只切 Kiwi 的必要肢体层**，美术切层目前为候选而非先决交付。

### 4. Paradox 未击破：维持 T5 图后离线
- 在 `UNBROKEN` 结果出现后，保持现有 `tier_03`（T5）立绘，先显示 PA-12 的未击破漫画结果反馈，再让对手直播画面短暂信号波动、变暗 / 收拢至无信号状态，表现对手离线。
- 可复用 PA-11 的 CRT 视觉材料及现有右侧直播层；离线提示只属于对手画面局部。

## 接口与交接
- 使用现有 `ContradictionBreakSystem.outcome_locked` 与 Sandbox 结果分支读取胜负，播放对应视觉并向场景协调方发送**击败 / 离线演出完成**通知。
- 真击破后原有 CB-09 等复读展示、FO-13 终结神谕、FO 选择确认与奖励继续正常执行；本卡负责角色图和显示完成通知，PA-19 负责之后的直播结束转场。
- 未击破后接 CB-10 的休息时刻展示转场；两条路径结果状态以现有系统为准。

## 验收
- 进入 Paradox 时三名对手保持 T5 图；只有命中真矛盾才触发各自击败表演和 `defeat` 图。
- 外星人确实经过现有融化过渡帧；狐狸的四种花瓣组成飘落雨；Kiwi 用完整图变形做出明显乱舞动作。
- 只击中假矛盾、落空或超时始终不显示 `defeat`，保留 T5 图直至离线。
- 两条结果对应原有 CB / FO / Rest 流程；真实 Godot Windows / Android 演示通过。

## 完成记录
新增 `docs/Shared/PresentationAssets/表现资产_PA-17_YYYY-MM-DD_log.md`，记录每名对手效果与是否需要后续 Kiwi 切图的验收判断。
