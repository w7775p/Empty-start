# PresentationAssets 表现资产接入

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../../开发计划_2026-10-09_任务卡依赖整合.md)。开发前核对该表、本卡现行版、main 实际实现及最新完成日志。


## 已交付美术资产

当前 PNG 资产分类、命名、数量及引用入口见 [assets/README.md](../../../assets/README.md)。旧位置的 PNG 已按用途重新归类，后续美术接入从此清单查找最新路径。

## 当前制作与集成安排（2026-10-10）

策划正在考虑调整 Sandbox 的场景组织方式。PA-04～PA-06、PA-08～PA-19 的**独立程序美术资源、视觉组件、可调参数和完成通知**可按任务推进；需要集中修改 Sandbox、BattleHud 和跨系统生命周期的接线，由后续确认的场景集成负责人依据新结构完成。当前的演出需求与分支结果以各任务卡为准。

PK 条贴图按 PA-16 规则：**玩家 PK 低于 40% 显示负向素材，40% 及以上显示最新 Tier 素材**。角色动画先采用 PA-14 的整图通用待机首版、PA-17 的 Kiwi 整图变形首版。现有粉丝牌纹理继续用于 LD-15 直播评论粉丝标识；主播信息区按 PA-20 使用「主播名    ❤粉丝团名❤」文字布局，PA-10 负责最终整屏视觉验收。

## PA-14 双主播整图动效（2026-10-10）

`systems/presentation/streamer_portrait_motion.gd` 使用绑定节点的原生 Tween：外层负责一次射击事件，内层负责循环漂浮、呼吸与微摆，PNG 本体可继续叠加其他表现。HUD 在 `_ready()` 为已有左右 TextureRect 插入这两层；原有素材显示接口继续使用缓存的立绘引用。运行时立绘路径增加 `<PortraitArt>Motion/Idle`，集成代码应使用现有 HUD API 或 `%PlayerPortraitArt` / `%OpponentPortraitArt`，避免硬编码旧子路径。

Lane A 后续接线：

```gdscript
# HUD 已进入树后，绑定本场正式攻击来源；重复调用自动解除旧连接。
battle_hud.bind_portrait_attack(attack_charge_input)
battle_hud.configure_portrait_character("alien") # 支持 alien / kiwi / fox
```

`bind_portrait_attack(null)` 可解除来源。`play_player_shot(snapshot)` 仅应接正式 `shot_snapshot_created`；每发只走绑定或直接转发中的一种入口。当前 Lane E 按分工保留 `sandbox.gd` / `sandbox.tscn`，完整战斗的发射接线 **TO VERIFY / 待 Lane A 集成**。待机已由 HUD 自动启用。

`refresh_pk()` 按 Tier 控制对手：T0 隐藏立绘及占位文字，T1 起显示当前 PNG；专属离线流程可调用 `set_opponent_portrait_connected(false)`。背景、汗滴、翻图、受击和 CRT 继续由对应卡负责。替换阶段 PNG 会复用当前动效层。

可通过公开 `player_portrait_motion` / `opponent_portrait_motion` 调参：

| 参数 | 默认 / 预设 | 作用 |
| --- | --- | --- |
| `idle_period` / `idle_phase` | 玩家 3.4s / 0；alien 3.8s / 2.2；kiwi 2.9s / 1.7；fox 4.1s / 3.2 | 周期 / 弧度相位；修改后 `restart_idle()` |
| `float_distance` / `breath_amount` / `sway_degrees` | 2～4px / 1.5～2.5% / 0.5～0.8° | 角色预设待机强度 |
| `body_pivot` | (0.5, 0.65) | 相对槽尺寸的躯干枢轴；随尺寸变化更新 |
| `shot_direction` / `shot_distance` / `shot_compression` | 向右 / 9px / 6% | 前冲方向、距离、压缩 |
| `recoil_count` / `recovery_seconds` | 2 / 0.18s | 后坐次数、最终回弹；默认总动作约 0.395s |

`set_idle_strength(0.0)` 平顺减弱待机，事件结束调用 `set_idle_strength(1.0)` 恢复；外部 CRT / 受击请作用于原立绘槽或 PNG 本体，保留 PA-14 两个容器的变换归属。`reset_for_attempt()` 取消射击 Tween、恢复幅度并隐藏对手。

Windows 验证入口为 `tests/presentation/pa14_portrait_motion_smoke.tscn`：继承正式 Sandbox Scene，仅在测试场景覆盖组合脚本，使用真实攻击输入、Timer 与 HUD；测试时长 / 分辨率处理仅存放于 `tests/`。Godot 4.7.2 Windows GUI 与 headless 各 23 项通过，GUI 实际 PNG 为 1920×1080。Android 硬件、项目默认 D3D12、PA-09 / PA-11 完整同屏演出仍 **UNVERIFIED**。详见 [PA-14 日志](表现资产_PA-14_2026-10-10_log.md)。

**2026-10-11 策划决策：PA-07 已取消。** 保留现有攻击流程及反馈；实体言弹外观、飞行特效与专用快照坐标接口从开发范围移除。历史试样留在未合并的 #142。

## 目标

让程序可以稳定接入美术正式资源，同时保持占位素材和正式素材可以直接替换。

当前资产目录：

```text
assets/
├── characters/
├── environment/
├── fonts/
└── ui/
```

共享表现配置为 `data/shared/presentation_asset_config.tres`，保存跨场景共用的 UI Theme 和玩家主角外观引用。需要显式读取共享资源时使用 `PresentationAssetConfig` 对应字段；项目级默认主题仍由 `project.godot` 的 `[gui] theme/custom` 应用。

## 当前规则

各玩法系统的数据 Resource 继续直接保存自己使用的美术资源引用。

例如：

- `IdentityOption.icon` 保存身份图标；玩家主角跨场景复用的立绘、头像、直播背景、房间背景和粉丝牌由 `PresentationAssetConfig` 保存。
- `LevelProfile` 保存每关主播的立绘、头像、直播背景和粉丝牌；主角固定外观不写入样例对手关卡。
- 败者卡资料保存卡面；
- 结局配置保存教派主图；
- UI Theme 保存通用字体和控件样式。

常见资源归属：

| 资源目录 | 内容示例 | Resource 归属 |
| --- | --- | --- |
| `assets/characters/` | 主播立绘、头像、身份/神明图标、败者卡角色图 | 身份、关卡/主播或败者卡 Resource |
| `assets/environment/` | 直播背景、房间背景、转场画面 | 关卡或对应演出配置 Resource |
| `assets/fonts/` | 项目专用字体文件 | 共享 Theme 或排版配置 Resource |
| `assets/ui/` | 跨场景状态图标、准心和通用 UI 贴图 | 共享表现配置；单系统图标归该系统 Resource |

身份图标继续存放在 `IdentityOption.icon`；每关主播立绘、头像、背景和粉丝牌跟随 `LevelProfile`；玩家主角固定外观因会跨场景复用而放在 `PresentationAssetConfig`；败者卡卡面跟随败者卡资料；教派主图跟随结局配置。系统专属资源仍由对应系统 Resource 持有。

`player_streamer_avatar` 当前复用主角立绘纹理；交付独立头像后只替换该字段。PA-02 只建立 Resource 引用，Sandbox HUD 与背景的实际视觉接线由 PA-03 处理。

跨多个场景共同使用、并且需要集中替换的表现素材放进共享表现配置。

## 替换约定

- 占位资源和正式资源使用同一个字段；美术交付后替换该字段对应的 Godot Resource。
- 共享配置只添加已被多个场景共同使用的素材；新增前先核实实际消费者。
- 当前没有共享准心、状态图标、通用转场贴图或 Shader 资源，因此不预建这些字段。
- 不创建 AssetManager 或额外查找服务；需要时通过系统 Resource 字段或显式加载共享配置取得资源。

## 任务

本表作为本程序美术 Agent 的独立执行待办。**PA-14 已交由另一位开发者负责，2026-10-10 起从本 Agent 待办移除**；原 PA-14 任务卡仍由仓库保留供对方开发和最终集成核对。本 Agent 后续跳过该卡。

| 任务卡 | 功能 | 单元测试 |
| --- | --- | --- |
| PA-01 | 建立表现资产引用规范与共享配置 | 无 |
| PA-02 | 正式美术资产入库与数据接线 | 无 |
| PA-03 | 主战斗正式美术接入，按 INT-06 全高弹幕区与 PA-08 环形准星更新布局 | 运行画面验证 |
| PA-04 | 普通弹幕玻璃底板、倾向/强度外观与富文本文字表现 | 运行画面验证 |
| PA-05 | 特殊弹幕外观：铁质、预裂玻璃、果冻、镂空字、假复读、水军反击 | 运行画面验证 |
| PA-06 | 弹幕命中表现：曲线碎裂、漫画强调符号、硬碰、分裂、果冻回弹 | 运行画面验证 |
| PA-07 | **已取消**：漫画实体言弹、可视轨迹、速度线（#142 已关闭，未合并） | 无 |
| PA-08 | 极简准星：小空心圆、外围环形蓄力进度与状态动效 | 运行画面验证 |
| PA-09 | 战斗结果 UI：命中点反馈、本发净 PK 为负时主播受击、PK 浮字 | 运行画面验证 |
| PA-10 | PA-04～PA-06、PA-08～PA-19 等正式程序美术集成后的全局 Style 统一验收 | 整屏视觉验收 |
| PA-11 | 战斗阶段切换：T0→T1 先上箭头再右侧直播画面 CRT、降档下箭头与震屏 | 运行画面验证 |
| PA-12 | Paradox 程序美术：噤声、漫画双斜切、闪白冲击字、画面撕开及矛盾阶段表现 | 运行画面验证 |
| PA-13 | PK 条仓鼠球指示器：随进度滚动、升降档蹦跳、降档惊慌表情 | 真实战斗画面验收 |
| PA-15 | 对手 T2 idle+漫画汗滴；T3～T5 卡牌翻图与受击漫画冲击 | 实际升降档画面 |
| PA-16 | PK 条阶段 / 负向贴图短闪调色切换，配合 PA-13 滚动球 | 运行画面验证 |
| PA-17 | 真击破对手专属败北：外星人融化、狐狸花瓣雨、Kiwi 方案 A；未击破 T5 离线 | 成败分支实际演示 |
| PA-18 | PK 归零战败：仓鼠球跌落、玩家直播 CRT 断流、对手持续直播、失败 UI | 战败画面与重开 |
| PA-19 | Paradox 两种结果均 CRT 关机、上翻页回主角房间，再弹战后结算 | 双分支战后结算 |
| [PA-20](tasks/PA-20_header-fan-group-name.md) | 双方主播右上角用 ❤粉丝团名❤ 文本替换固定粉丝牌槽；粉丝牌纹理保留给评论 | 双方 HUD 与切关实际画面 |

PA-02 负责把正式美术资产导入工程并接到对应 Resource；PA-03 负责将已经接线的正式资源替换到 Sandbox 主战斗界面。

## PA-04 独立组件交付（2026-10-10）

普通弹幕使用原有 `systems/barrage_generation/barrage_view.tscn` 与独立 `BarrageGlassSurface` 材质节点。**2026-10-10 正式定稿：01 GLASS NOIR**（正统 `#1658A2`、异端 `#B9502D`、荒谬 `#B7865B`、Neutral `#ADA4A3`），S1 轻薄玻璃、S2 明亮柔光、S3 更亮并缓慢呼吸；取消刻痕、左侧竖条及双层硬内框。底板倾向色、三级强度参数全部暴露在 `BarrageGlassSurface` Inspector；S3 文字加重在 `BarrageView` 配置，不增加色板 Resource。`BarrageView.setup()` 按运行记录决定外观，`set_visual_bbcode(bbcode)` 保留富文本接口。独立演示 `scenes/demos/pa04_glass_demo.tscn`，1920×1080 真实 GPU 截图（含同屏重叠）与最小冒烟见 `docs/Shared/PresentationAssets/previews/` 及 `表现资产_PA-04_2026-10-10_log.md`。正式 BG-28 富文本配表、RP 复读规则与 Sandbox 接线按对应系统后续集成，PA-05 可复用已定稿玻璃材质。

## PA-06 弹幕命中短演出（2026-10-10）

**漫画符号新版本（待策划四选一）**：四套独立透明 PNG / 可编辑 SVG 位于 `assets/ui/combat/impact_marks/`；①锐利剪纸、②粗笔触、③手绘 KRAK 拟声、④漫画破裂漫符。通过 `pa06_mark_variants_demo.tscn` 在 Godot 真实碎裂中并排对照，截图见 `previews/pa06_four_marks_impact.jpg` 和 [四方案说明](previews/PA06_four_impact_marks_study.md)。已移除旧的数学符号 Label，运行时只渲染独立 TextureRect；Inspector 可直接切换四个资源。目前暂以 01 作为演示默认，待美术选定。


`BarrageImpactPresenter` 和 `BarrageImpactFx` 位于 `systems/presentation/`，复用 PA-04 / PA-05 真实弹幕 Scene 和 4 系统最终 `BarrageTraitResult`。呈现普通曲线双碎片 + 独立 PNG 漫画碎裂符号、铁板硬碰后留场、分裂母体沿左上→右下曲线分开、果冻受压→回弹→恢复、假复读椭圆碎裂、水军整块 Panel 带小字统一破碎。曲线碎片由一次性 SubViewport 镜像取样，`Polygon2D` 以曲线 UV 裁切并各自退场；实例归 3/5/6 系统照旧结束，演出独立存活约 0.28s。漫画符号已经采用独立透明 PNG 资产，使用 `impact_symbol_texture` 切换四个方案，尺寸、偏移可在 Inspector 设置。

**正式接线 API：** 场景集成方将 Presenter 实例加在 BattleArea 同画布层，调用 `presenter.bind_attack(attack_charge_input)`，消费原 `shot_arrival_resolved(snapshot, target_results)` 信号；亦可直接调用 `play_target_result(view, view.runtime_record.trait_set.get_hit_result())`。本次将 CA-15 整发遮挡视为仅铁板硬碰，其余目标保持；正式整发落空事实由 5/6 负责。3/4 系统完成 BT-06 子话语真实生成时，以其实际 `Array[BarrageView]` 调用 `play_spawned_split_children(children)`，弹幕生成系统继续持有文本、倾向、强度和生命周期。重新开局或离开战斗时 `reset_effects()`，解绑旧来源调用 `bind_attack(null)`；切关接线将在 Sandbox 重构后完成。

**独立演示：** `res://scenes/demos/pa06_impact_demo.tscn`，按 `R` 重播、`Space` 暂停；`pa06_capture_1920.tscn -- --capture-pa06` 生成四张 1920×1080 真实 Godot GPU 截图：`pa06_before.jpg`、`pa06_impact.jpg`、`pa06_followthrough.jpg`、`pa06_recovered.jpg`。演示中两条子话语是独立创建的真实 BarrageView，仅核实 Presenter 消费外部子视图的表现；正式 BT-06 子文本和生成接线另有任务。真实证据与未完成交接见 [PA-06 日志](表现资产_PA-06_2026-10-10_log.md)。本卡只负责独立程序美术及公开表现接口，PA-09 继续负责 PK 浮字和主播受击反馈。
## PA-05 六种特殊弹幕视觉组件（2026-10-10）

继承 PA-04 的 `BarrageGlassSurface`，由 `BarrageSpecialSurface` 依据 `BarrageView.runtime_record.trait_set.get_trait_ids()` 选择唯一主材质：`reflect → occlusion → fake_card → retaliation_copy → split → glass`，`unselectable` 叠加空心字。正式入口沿用 `systems/barrage_generation/barrage_view.tscn`，`setup()` 自动接线，不新建战斗状态与可命中对象；通过 `get_special_material()` 查询表现类型。铁质、预裂玻璃、有厚度且持续微动的凝胶、放大增强轮廓的镂空字、与真复读同色同透明度的椭圆假复读与单实例多处小字水军板均在 Godot 4.7.2 实际绘制；果冻最多约 24Hz 重绘。普通复读继续使用灰色圆角玻璃与零描边；分裂子句进入普通无特性视图时自动使用小尺寸普通玻璃。可调颜色、裂痕、果冻幅度、刷屏字号集中在 `barrage_special_surface.gd` 的 Inspector。

独立演示：`res://scenes/demos/pa05_special_barrage_demo.tscn`；全高清截图入口：`res://scenes/demos/pa05_capture_1920.tscn -- --capture-pa05`；画面与日志见 `docs/Shared/PresentationAssets/previews/pa05_*.jpg` 和 [PA-05 完成日志](表现资产_PA-05_2026-10-10_log.md)。PA-06 继续负责命中碎裂、回弹和硬质碰撞的事件演出；此处只有常态材质与果冻微动。

## PA-08 独立视觉组件交付（2026-10-10）

`systems/combat_attack/aim_reticle.gd` 已具备小空心圆、环形蓄力、满蓄、发射和运动反馈。2026-10-10 按策划表确认 PC 视觉范围 96×96、实际圆形命中包络框 144×144，分别由 `visual_diameter` 与 `reticle_diameter` 设置；美术双层明暗描边保持可调。触屏仍通过 `MobileAttackInputConfig` 注入独立判定直径。集成方用 `set_charge_visual_state(progress, held, full)` 传入原有攻击进度，在 `shot_snapshot_created` 事实发出后调用 `play_shot_feedback()`；可通过 `animation_finished`、`reset_visual_state()`、`set_visual_paused()` 协调表现生命周期。现有准星命中几何接口保留。独立演示为 `scenes/demos/pa08_reticle_demo.tscn`，固定分辨率截图入口为 `scenes/demos/pa08_capture_1920.tscn`，四状态截图位于 `docs/Shared/PresentationAssets/previews/`；完整接口与测试见 `表现资产_PA-08_2026-10-10_log.md`。Sandbox 接线等待重构后的场景集成任务。

## 最新任务卡分工口径（2026-10-09）

普通前景话语保留清晰文字及描边；真正复读以灰字、零文字描边和背景层级呈现。**假复读与真复读的底色、透明度、字号、字色及文字描边一致，只有外框分别为椭圆、圆角**；假复读继续是携带 `fake_card` 特性的可命中前景话语。PA-04 负责视觉材质与文字风格，BG-28/BG-37 负责普通前景文本能力，RP-19～RP-21 负责复读字色、描边与层级；PA-06 表现遮挡撞击时遵循 CA-15 的整发落空结算。
