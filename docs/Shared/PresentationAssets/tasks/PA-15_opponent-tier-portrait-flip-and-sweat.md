# PA-15 对手阶段立绘：T2 漫画汗滴与卡牌翻转切图

> 状态：需求已确认，待实施
> 类型：程序美术 / PresentationAssets
> 依赖：CombatStage `tier_state_changed`、现有对手立绘入口、PA-11 升降档演出

## 开始前阅读
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md`、最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

- `docs/Shared/PresentationAssets/tasks/PA-11_stage-transition-visuals.md`
- `docs/8. CombatStage/README.md`、现有 `CombatStageTierConfig` / `CombatStageTierCatalog`

## 正式运行 Tier → 对手立绘映射
| 运行阶段 | 显示 |
| --- | --- |
| T0 | 无对手立绘，使用等待连线状态 |
| T1 | `{opponent}_idle.png` |
| T2 | **仍为 `{opponent}_idle.png`，额外叠加漫画汗滴** |
| T3 | `{opponent}_tier_01.png` |
| T4 | `{opponent}_tier_02.png` |
| T5 | `{opponent}_tier_03.png` |
| T6 / Paradox | **保留 T5 的 `tier_03` 立绘**，结果明确之后按 PA-17 演出；仅真矛盾成功时才能使用 `defeat` |

`{opponent}` 按当前关的外星人 `alien`、Kiwi `kiwi`、狐狸 `fox` 等稳定角色类型选择。美术文件名里的 `tier_01` 是变化版本 1，并非战斗 T1。

## 最新策划配置来源（2026-10-10）
- `02_主播关卡.portrait_set_id` 关联 `23_对手立绘配置.portrait_set_id`；23表每组记录所属 `streamer_id`、idle、tier_01～03、defeat、可选击败过渡图与 `defeat_effect_id`。
- 当前已登记 `portrait_alien`、`portrait_kiwi`、`portrait_fox` 三组正式素材路径；第四关 `frog` 的阶段图片与专属演出由策划、美术后续补充。
- 按23表的阶段图实际加载纹理并在 T1/T2/T3/T4/T5/T6 映射中使用；从现有 `LevelProfile.streamer_portrait`、`OpponentPortraitArt`、PA-14动效层复用入口。
- 阶段图标识是图片变化版本，不作为额外战斗Tier；当前关角色类型来源为02.`streamer_id`。

## 本卡程序美术
### 1. T2 漫画流汗
- 当对手进入 T2，在待机立绘头部附近绘制**一到两滴醒目的漫画水滴状汗珠**，使用程序绘制带高光 / 描边的水滴、多帧透明度和少量下滑，表现对手开始紧张。
- 汗滴跟随立绘位置与缩放变化；可以周期性缓慢出现、下滑、淡出，频率可调。
- 升档至 T3 后，贴图切为 `tier_01`，汗滴随之淡出；降回 T2 后恢复 idle + 汗滴；回 T1 不再显示汗滴。

### 2. 有图像变化时的立绘卡牌翻转
- 对当前旧立绘做**快速横向压扁 / 仿卡牌绕 Y 轴翻转 → 最窄点更换 Texture → 横向展开并轻微过冲回弹**。
- 换图完成瞬间配合 **PA-06 / PA-09 已确定风格的漫画受击冲击线 / 尖锐图形**短促弹出，再消隐；可从已有手绘视觉参数取色，保证与角色动效协调。
- T2→T3、T3→T4、T4→T5 及反方向跨越不同贴图时有明显翻转；T1↔T2 保持同一张 idle，只用汗滴出现 / 消失及小幅受击震颤，而非无意义重复翻同图。
- 跨多个 Tier 时根据最终实际阶段只显示一次对应落点画面，保持与 PA-11 箭头、PA-13 仓鼠球响应同步。

### 3. 与阶段事件同步
- 源数据读取当前对手外观与 `CombatStage` 的真实阶段，刷新现有 `OpponentPortraitArt` 的 Texture。
- T0→T1 由 PA-11 先播中央箭头和 CRT 接入，再显示 idle；普通升降档保留 PA-11 既有画面与清屏时序。
- 使用现有立绘容器与 Tween、AnimationPlayer、轻量 Shader；调参入口包含翻转时长、最窄比例、回弹、漫画冲击强度、汗滴位置 / 频率。

## 验收
- 在 T0～T5 逐档升降时，T2 为 idle+漫画汗滴、T3 为变化图 01、T4 为 02、T5 为 03；T1↔T2 不更换底图。
- 不同底图切换有清楚的卡片翻面动效与漫画冲击；临界档位快速变化能够正确显示最终素材。
- 正式 Paradox 开始时仍显示 T5 图，击破胜负由 PA-17 接手；支持当前角色资源缺失时的现有占位。
- Windows / Android 实景验证无丢图 / 错位。

## 完成记录
新增 `docs/Shared/PresentationAssets/表现资产_PA-15_YYYY-MM-DD_log.md`，注明阶段图片、绘制汗滴、翻转参数及实测。
