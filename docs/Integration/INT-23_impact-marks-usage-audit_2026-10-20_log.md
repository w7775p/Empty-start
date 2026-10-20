# INT-23 命中漫画特效资源映射与战斗接线复核日志

日期：2026-10-20
基线：`origin/main` / `c7fec1a434dfcf15327ddd4c128debea61f77d57`
分支：`codex/int23-impact-marks-audit-20261020`

审计初始扫描基于 `e61dff31`；提交前 `main` 依次合入 ID-16 与 PAUSE-V2，更新至 `c7fec1a4`。期间变更集中于身份/暂停 UI 与截图，不涉及本卡核对的资源、表现脚本及资产表；本任务提交已重放到 `c7fec1a4`。

## 审计结论

当前没有需要接入 PA-06 独立漫画标记的正式战斗入口。普通 Plan B 接触、感染与反击使用各自的棋盘反馈；矛盾阶段的进场与结果使用全屏 PA-12 漫画演出及 PA-17 对手结果演出。PA-06 常规 BarrageImpactPresenter 仍播放材质反馈，其独立漫画贴图默认关闭，符合 2026-10-11 策划定稿。没有把素材接入不匹配的战斗事件。

## 四种资源方案映射

四组 PNG 均为 PA-06 512×512 RGBA 漫画符号；对应 SVG 是可编辑源图，由 `scenes/demos/pa06_export_impact_marks.gd` 导出 PNG。PNG 方案预览场景 `scenes/demos/pa06_mark_variants_demo.gd` 通过四个明确的 `preload` 加载各款素材。

| 资源 | 当前引用与用途 | INT-23 判定 |
| --- | --- | --- |
| `impact_01_razor.png` | PA-06 方案演示；`systems/presentation/crt_connection_fx.gd` 直接预载，并在 CRT 连线闪击中绘制。旧 `SandboxBattleHud` 有 `play_connection()` 调用；正式 Plan B `PlanBStreamerPanel` 目前能创建该效果并提供包装方法，已查到的 Plan B 调用仅重置状态，未发现启动连线动画的调用。 | 有直接 Resource 引用；CRT 连线用途独立于战斗命中。它不是当前 Plan B 普通碰撞或矛盾击破的命中图标。 |
| `impact_01_razor.svg` | PA-06 矢量源，交由导出脚本生成同名 PNG。 | 源文件 / 导出输入，不是运行时战斗消费资源。 |
| `impact_02_ink.png` | PA-06 方案演示显式预载。 | 演示候选；没有正式战斗播放入口。 |
| `impact_02_ink.svg` | PA-06 矢量源，交由导出脚本生成同名 PNG。 | 源文件 / 导出输入。 |
| `impact_03_krak.png` | PA-06 方案演示显式预载。 | 演示候选；没有正式战斗播放入口。 |
| `impact_03_krak.svg` | PA-06 矢量源，交由导出脚本生成同名 PNG。 | 源文件 / 导出输入。 |
| `impact_04_manga.png` | PA-06 方案演示显式预载。 | 演示候选；没有正式战斗播放入口。 |
| `impact_04_manga.svg` | PA-06 矢量源，交由导出脚本生成同名 PNG。 | 源文件 / 导出输入。 |

### PA-06 旧 BarrageView 命中路径

`scenes/sandbox/sandbox.gd` 创建 `BarrageImpactPresenter` 并绑定 `AttackChargeInput.shot_arrival_resolved`。Presenter 按遮挡、反弹、分裂、假复读和普通结果调用对应材质效果。`impact_symbol_texture` 默认 `null`，并传给每个特效副本；`BarrageImpactFx._show_accent()` 对空贴图直接返回。现行 `tests/visual/pa06_impact_smoke.gd` 也明确核验常规碎裂没有独立漫画符号。

正式 `sandbox_plan_b.tscn` 启用 Plan B；其普通阶段以棋子模拟为主，并隐藏旧 `BarrageArea`。旧 BarrageView Presenter 的命中符号入口不能据此视作 Plan B 单位碰撞的消费端。

## 当前正式战斗事件与视觉入口

| 事件 | 正式事实与画面入口 | 对 PA-06 标记的判断 |
| --- | --- | --- |
| 普通碰撞 / 弹开 | `PlanBUnitSimulation.contact_resolved` → `PlanBBattleUI._on_contact_resolved()` → `PlanBUnitField.show_contact_feedback()` → `_draw_contact_feedback()`；绘制双方之间的短线和头像外圈，并依结果着色。 | 现有位置与结果提示已经接线；原策划没有要求叠加 PA-06 漫画贴图。 |
| 感染成功 | `PlanBUnitSimulation._attempt_conversion()` 发出 `unit_changed(reason="convert")` 和 `contact_resolved(outcome="converted")`；UI 同时提交头像脉冲与接触线/结果色。 | 现有感染反馈已接线；不需要借用独立命中漫画符号。 |
| 被对手反击 | `PlanBBattleUI.show_counterattack_windup/result()` 调用 `show_unit_feedback(..., "counterattack")`，并显示主播、技能与受影响数量；棋子绘制品红脉冲。 | 反击预警与结算已有可见反馈。PA-06 的 `RETALIATION_COPY` 分支属于旧 BarrageView 材质碎裂，不等于 Plan B 对手技能反击。 |
| 矛盾击破 | `ContradictionOracleFlow.outcome_resolved` → Sandbox 锁定演出 → `play_opponent_result(broken)` → `ParadoxComicTransition.play_result_feedback(broken)`。PA-12 用全屏压暗/闪白和“击破 / 未击破”结果字；阶段入口另有斜切、冲击线和撕幕。 | 原策划要求的全屏强调与真假结果揭示已有专属演出。PA-06 小贴图不会替代或增强这条结果链。 |

## 台账修正

更新 `data/source_tables/18_表现资产.csv` 的 `hit_effect` 条目：将目标目录改为真实 `assets/ui/combat/impact_marks/`，并把 PA-06 四套图形说明为演示候选；补记 01 号图形的 CRT 连线引用，以及它与常规碰撞 / 矛盾结果入口的边界。静态引用数为零不能作为删除或强制接线依据。

## 验证与画面证据

- Godot `4.7.2.stable.steam.ed1daf0bf`，D 盘新建工作树与缓存。
- 首次冷启动出现 KT-45 记录过的字体/音频 loader 提示。随后用标准 `--headless --editor --import --path <worktree> --quit` 完成导入，日志到达 `[DONE] loading_editor_layout`，D 盘 `.godot/imported` 共生成 779 个缓存文件。
- 导入完成后运行 `tests/visual/pa06_impact_smoke.gd`，退出码 0、日志无 `ERROR` / `SCRIPT ERROR`，输出 `PA06_SMOKE_PASS: 5 observable behavior scenarios`，包含“常规碎裂不显示独立漫画符号”核验。
- 完整 Sandbox/Plan B 战斗场景未运行；调用链审计与行为 smoke 不代表整局或艺术手感验收。
- 复用基线内已有的真实 Godot 画面：`docs/Shared/PresentationAssets/previews/pa06_four_marks_impact.jpg`（1920×1080，四方案演示）、`docs/Shared/PresentationAssets/previews/pa09_real_battle_hit.jpg`（1280×720，实际命中反馈）、`docs/Integration/evidence/PB-09_2026-10-17/pb09_1920x1080_paradox.png`（1920×1080，Plan B 矛盾阶段）。截图随初始扫描基线 `e61dff31` 存在，并保留在最新基线 `c7fec1a4`。

## 交接

- 没有改动战斗结算、PA-06 Presenter、PA-12/PA-17 演出、Scene 或公开接口。
- `known_traps.md` 无需更新；当前载入问题已有冷工作树资源导入记录可沿用，详见 KT-27 与 KT-45。
- 后续如策划要求某一矛盾结果单独播放 PA-06 贴图，应新增明确事件规则并由该视觉入口 Owner 处理；本卡没有确认这样的需求。
