# 5. CombatAttack 战斗攻击系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。已实现的基础卡用于接口复查；新的视觉、静止弹幕、对话与阶段打磨以最新单卡和此表为准。

## 2026-10-09 现行实现核对与任务状态

**现行判断与差异：** `_capture_target_snapshot()` 已收集准心区域内全部可选实例并在释放时去重冻结；缩放后的变换验收按 CA-13。混合遮挡仍会落入普通逐目标结算与移除路径，CA-15 负责整发落空优先：范围含任何 `occlusion` 特性则复用已有 MISS 惩罚，区域实例保持场上。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [CA-13](tasks/CA-13_scaled-target-range.md) | 已有矩形相交后的缩放回归 | 已有基础 |
| [CA-14](tasks/CA-14_all-overlapped-targets.md) | 多目标快照重叠验收 | 场景验收通过（2026-10-10） |
| [CA-15](tasks/CA-15_whole-shot-miss-on-occlusion.md) | 遮挡覆盖整发落空 | 待修复 |

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


### CA-14 十目标同发与到达复核（2026-10-10）

`tests/combat_attack/ca14_all_targets_gui.tscn` 实例化正式 Sandbox，并通过 `BarrageArea.spawn_normal_barrage()` 从首关真实话语池创建十个独立、可选的 `BarrageView`。首关当前有 3 条唯一 `LevelSpeech` 定义，验收入口循环使用这些正式定义来构造十个运行实例；十个实例有各自的 instance ID，Label 矩形两两重叠且全部与准心相交。

GUI 运行使用 `Input.parse_input_event()` 合成鼠标事件；同一发快照冻结十个不重复 ID。飞行期间删除一条目标、令一条在到达前过期，并将一条移出准心但留在 BarrageArea；到达复核保留移位目标，只向 HitResolution 提交八个仍有效的目标。物理鼠标未验收。该卡只增加 TEST_ONLY 场景验收入口，没有修改生产代码或公开接口。

截图证据：[CA-14 十个重叠目标 GUI 运行截图](evidence/CA-14_2026-10-10_overlapped_targets.png)

## 系统目标

战斗攻击系统负责玩家从“移动准心”到“一发攻击完成”的过程。

它负责：
1. 鼠标 / 触摸输入；
2. 准心位置与判定范围；
3. 蓄力；
4. 释放时记录本发目标；
5. 飞行、到达与硬直；
6. 把普通战斗结果交给【6. HitResolution】；
7. 把矛盾阶段结果交给【12. ContradictionBreak】。

它不负责计算 PK，也不负责弹幕自身的生成和寿命。

## 当前实现

- CA-01 提供独立 `AimReticle` 场景并接入当前 sandbox 游戏入口。
- **2026-10-10 PC 策划数值定稿：视觉区域 96×96 设计像素，实际可击中区域 144×144 设计像素。** `AimReticle.visual_diameter` 控制独立绘制边界；`reticle_diameter` 表示现有圆形命中区域的直径，PC 默认 144，命中包络框 144×144。准心、蓄力环、中心与攻击快照共用一个位置；目标相交继续按现有圆-矩形判定规则。INT-01 将 `AimReticle` 放在 `BattleHud` 内，与弹幕统一继承 1920×1080 舞台缩放。此前 32 设计像素为旧原型默认值。
- INT-01 鼠标移动读取事件的 Viewport 坐标并转换为画布坐标，中心偏移按完整变换基底换算；`get_aim_center_global_position()` 将绘制中心变换到画布坐标。`refresh_mouse_position()` 供 HUD 在初始化和窗口缩放完成后重新对齐鼠标。
- CA-02 提供 `BarrageAimIntersection.circle_overlaps_rect()`，边缘接触判为相交；`AimReticle.intersects_target_area()` 将画布目标矩形逆变换至准心局部坐标，再使用同一设计直径判定。等比与非等比舞台缩放下，显示和判定范围保持一致。
- CA-03 提供 `AttackChargeInput` 和纯状态 `AttackChargeProgress`；按住鼠标左键会累积到 `AttackTimingConfig.charge_time_s`，和准心 / 候选目标状态解耦。
- CA-04 未蓄满松开会清空当前进度，不产生攻击结果。
- CA-05 在 Sandbox 中接入真实 `BarrageArea` / `BarrageView`：满蓄释放时检查当前视图、运行时到期时间和区域内可见矩形，再按准心相交结果创建去重快照；释放后的候选变化不会修改本发目标。
- CA-06 在到达时按真实 `BarrageRuntimeRecord` / `BarrageView` 状态过滤已释放目标；目标移动后仍保留资格，到期、离开 BarrageArea、脱离所属区域、排队删除或已释放的目标均失效，不再检查原准心范围。
- CA-07 提供可注入 `AttackTimingConfig` 和普通攻击阶段计时：快照释放后进入飞行，到达时复核并发出结果，再进入硬直；硬直期间不推进蓄力。`tests/fixtures/combat_attack/ca07_short_attack_timing.tres` 只用于计时逻辑验证；INT-01 为 Sandbox 注入独立运行配置。
- CA-11 让 AttackChargeInput 在全局暂停时冻结蓄力处理，并让飞行 / 硬直 Timer 使用可暂停模式；恢复后沿用暂停前的进度。
- CA-08 为每条 `BarrageRuntimeRecord` 装配独立 `BarrageTraitSet`；释放扫描调用 `is_selectable()`，到达复核调用 `get_hit_result()`，并通过 `shot_arrival_resolved` 传递目标 ID、目标节点和原始 `BarrageTraitResult`。
- BT-10 将释放扫描中的 `is_selectable()` 明确放在生命周期、区域可见性及准心相交检查后，逐个过滤范围内不可选弹幕；全部排除时空快照继续进入现有落空结算链。准心判定、快照去重与正常目标收益继续复用原实现。
- 当前生成记录的特性集合默认为空；如何把 `LevelProfile.special_trait_ids` 分配到具体弹幕实例尚无已定规则，本卡不猜分配方式。
- CA-09 通过注入的 `HitResolution` 调用正常收益、整发落空 / 异常优先级、单次 `resolve_shot_results()` 和普通命中历史接口；HitResolution 持有唯一 PK。INT-01 Sandbox 从独立运行配置读取初始 PK（当前0.5），并把最终 PK 信号接给 CombatStage。
- `shot_hit_resolution_submitted` 同发包含目标有效性、`ShotAnomaly`、逐目标 `BarrageTraitResult` / 奖励字典及 HitResolution 返回值。异常惩罚映射等待 HR-03；INT-01 由 Sandbox 据逐目标结果连接普通复读与本场倾向暂存。
- FO-13 增加临时选择目标接口 `set_selection_targets(targets: Array[Control])` / `clear_selection_targets()`。目标模式仍复用同一准心、蓄力、发射和飞行流程；到达时按释放快照的准心中心裁决最近 Control，并发出 `selection_target_hit(target)`，绕过 HitResolution。
- CA-10 Sandbox 补做（2026-10-09，#92 blocker）：最后一发假矛盾立即锁定未击破结果并禁止后续发射，Sandbox 保持矛盾队列调度，等本发有限复读全部生成且可见实例自然结束，再单次进入 Rest。空命中与超时没有复读时即时进入 Rest；真命中的复读、静音、神谕路径继续沿用原实现。复读数量、延迟、寿命与容量使用现有配置，未增加奖励或第二套管理器。

### INT-01 战斗生命周期与结算事实

`AttackChargeInput.set_combat_active(active: bool)` 供场景协调战斗停止与重开。传入 `false` 会禁用攻击输入、清零蓄力、取消飞行 / 硬直和 Timer，并恢复阶段为 READY；传入 `true` 后可开始下一发。暂停继续通过 SceneTree 控制，保留当前蓄力与剩余计时。

矛盾阶段由 Sandbox 调用 `set_contradiction_mode(true)`；满蓄释放的 `shot_snapshot_created` 携带当帧冻结的矛盾原句事实，由 12 系统立即判定并消耗机会。飞行计时只保留演出，不再复核目标或发送到达结算；结果锁定后 `lock_new_attacks()` 禁止下一发而保留当前飞行。进入 Rest / FinalOracle 时停止攻击；重开普通战斗时调用 `set_contradiction_mode(false)`。

FinalOracle 选择阶段由 Sandbox 将中央 `FinalOracleCandidateDisplay` 生成的 Label 控件注入 `set_selection_targets()`。攻击系统只发出释放快照中实际命中的目标；同发多目标时按快照准心中心到控件中心的距离选择最近一句。Sandbox 用该目标 ID 回读 Session 的冻结候选，并提交至唯一确认入口。选择阶段不会调用 HitResolution。

`HitResolution.resolve_shot_results()` 同步发送最终 PK，回调可能在满值或失败时停止攻击。到达处理在回调后检查本发仍有效，保证已停止的战斗不会再次启动硬直 Timer。当前这一发成功结算的提交事实仍会发送，供协调方处理命中与倾向。

`submission.hit_resolution_result.target_results` 每个目标除 `target_instance_id`、`target`、`trait_result` 外，携带 `original_sentence_id`、`original_sentence_text`、`source_id`、`is_repeat`、`tendency_id`、`tendency_delta`、`is_valid_hit`。内容事实在提交前从运行时记录复制，协调方无需回读可能已结束的弹幕节点。正常普通话语取得 HitResolution 计算的奖励并记录普通命中历史；复读调用 `calculate_repeat_hit_result()`，有效命中、PK 与倾向增量为零，且不会记录普通命中历史。整发在 PK 下限作废时，HitResolution 返回空目标结果。

- DBG-01 增加 `AttackChargeInput.is_charge_held()`，供调试面板读取真实按住状态并显示“蓄力中”；阶段和蓄力比例仍由 `get_attack_phase()`、`get_charge_progress()` 提供。

### CA-12 触屏输入与 Lane A 接线

`AttackChargeInput.configure_mobile_input(config: MobileAttackInputConfig) -> bool` 注入移动端准心设计直径 `touch_reticle_diameter`。仓库尚无正式移动端数值表，本 Resource 默认为 0（未配置），拒绝零值、负值和非有限值；未注入时触屏攻击保持关闭。PC 已批准的准心尺寸保持原配置。

触屏首次按下由 `_unhandled_input()` 接收，UI 可优先消费。接管单指后拖动更新准心，按住沿用现有蓄力计时，松开先更新最终坐标再调用原释放流程；未满蓄取消，满蓄沿用快照、飞行、结算和硬直。第二指不能改变攻击手势；触屏模拟鼠标事件不会重复触发攻击。系统取消、后台切换、暂停中抬指、战斗停止均丢弃当前触屏蓄力。暂停中保持按住则冻结进度，恢复后继续。

`AimReticle.move_touch_aim(viewport_position, diameter)` 使用原有画布逆变换和中心偏移，准心显示及目标相交共用同一直径。布局刷新保留最近触屏位置，实体鼠标重新操作恢复 PC 尺寸。

CA-12 / INT-04 鼠标回归修复（2026-10-09）：`AimReticle.restore_mouse_aim(viewport_position: Vector2)` 必须传入当前真实鼠标事件的 Viewport 位置。左键按下使用 `InputEventMouseButton.position`，恢复 PC 直径并按原画布逆变换设置中心；按下路径不再调用系统光标读取。这样触屏结束后直接按鼠标也能正确定位，无需额外 MouseMotion。初始化 / 布局刷新接口保持原行为。

针对性 TEST_ONLY GUI 入口为 `res://tests/combat_attack/ca12_mouse_restore_gui.tscn`，使用 `Input.parse_input_event()`，覆盖无移动首按、Canvas / 父级缩放、触屏切回鼠标及触屏 / UI / HR-13 回归。修复前后 INT-04 整局对照与精确退出码见 CA-12 当日日志和 `evidence/CA-12_INT-04_2026-10-09_mouse_fix.txt`。这些证据来自 Windows 注入事件；硬件鼠标和 Android 实机仍待验收。

**A 集成位置**：Sandbox `_ready()` 现有 `configure_target_query()` 之后，将场景读取的移动端配置传入 `configure_mobile_input()`，检查返回值。重开沿用已注入的只读配置，继续用现有 `set_combat_active()` 清理手势。本卡没有修改 Sandbox / Rest / 其他场景，也没有自动启用测试数值。

**精确交接**：由 A 增加场景导出属性 `@export var mobile_input_config: MobileAttackInputConfig`，在 Inspector 给 Sandbox 实例指定正式移动尺寸 Resource；上述位置的一行调用为 `var mobile_input_ready: bool = _attack_charge_input.configure_mobile_input(mobile_input_config)`，返回 false 时报告配置未就绪。TEST_ONLY 联调 Scene 可显式绑定既有 fixture，正式 Scene 继续等待策划资源。当前 Sandbox 没有该导出属性或配置调用，生产触屏输入仍关闭。

2026-10-09 基于 main `c03bd17` 的合并状态已用 Godot 4.7.2 重验：触屏 MISS / 反弹 / 遮挡均通过 `resolve_shot_results(hit_resolution_targets, shot_anomaly)` 交给 6 扣分一次；HR-13 的 `terminal_mode` 会阻止晚到触屏命中写普通历史。完整验收与环境限制见 CA-12 日志。

正式数值到位前，A 仅在明确的 TEST_ONLY 联调入口加载 `res://tests/fixtures/combat_attack/ca12_test_only_mobile_input.tres`；其中 80 设计像素只用于 PC 模拟验收。正式发布须换成策划数值表导出的 `MobileAttackInputConfig`，不得将 fixture 当成正式平衡值。正式 Android 场景接线、构建及手机分辨率/手感验收见 CA-12 日志中的未验证项。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| CA-01 | 鼠标准心移动 | 无 |
| CA-02 | 准心与弹幕相交判定 | 2 个关键单元测试 |
| CA-03 | 蓄力进度 | 2 个关键单元测试 |
| CA-04 | 未蓄满松开取消 | 1 个关键单元测试 |
| CA-05 | 释放时记录并去重目标 | 2 个关键单元测试 |
| CA-06 | 飞行结束后复核目标有效性 | 无 |
| CA-07 | 普通攻击硬直节奏 | 无 |
| CA-08 | 接入弹幕特性的可选/遮挡/反弹 | 无新增自动化测试 |
| CA-09 | 普通攻击结果交给命中结算 | 无新增自动化测试 |
| CA-10 | 矛盾攻击交给矛盾击破 | 无新增自动化测试 |
| CA-11 | 暂停时冻结蓄力/飞行/硬直 | 无 |
| CA-12 | Android 触摸输入接入 | 无 |

## 测试预算

只保留 7 个纯逻辑 case：

- 相交时可选；
- 边缘接触也算相交；
- 没有目标仍可蓄力；
- 移动 / 换目标不清空蓄力；
- 未蓄满松开清零；
- 同一实例同发只记录一次；
- 释放后后来进入准心的目标不加入本发。

UI、飞行表现、硬直、暂停、触摸和跨系统传递全部用最小运行联调。

## 依赖顺序

CA-01～09、CA-11 已完成。
CA-10 已有真实接线；#94 已合并 Sandbox 假命中复读展示修复，历史文档 PR #92 已关闭。
CA-12 输入组件已通过 PC 真实场景模拟触屏 smoke；Android JDK/SDK 环境已于 2026-10-09 安装并用独立 TEST_ONLY Godot APK 验证，但正式 Sandbox 移动配置接线、游戏本体 APK 与真机验收仍待完成。

## 2026-10-09 战斗打磨单功能开发卡

本轮确认的高密度弹幕、四种运动、交叉层级、富文本、舆论潮汐、弹幕群聚、伪纵深、命中冲击波、复读感染、Tier 升降档与沉默爆发，现已拆为单一功能开发卡。每张卡仅定义触发条件、预期行为与验收结果；可调数值以实测和后续策划配置为准。卡片状态均为**待实施**。

| 卡号 | 本卡唯一功能 | 状态 |
| --- | --- | --- |
| [CA-13](tasks/CA-13_scaled-target-range.md) | 按弹幕当前缩放范围命中 | 待实施 |
| [CA-14](tasks/CA-14_all-overlapped-targets.md) | 重叠区域全部有效弹幕群体命中 | 待实施 |

关联依赖及实施顺序以各卡的上游功能卡为准；共享场景与组件按实际 Owner 的任务流程依次集成。

## 2026-10-09 新确认规则与单功能任务卡

当准心范围存在遮挡特性实例时，将本发按已有落空流程结算并保留场上弹幕；其他有效群体命中按已有完整目标集合结算并交给 03 清屏。

| 任务卡 | 唯一功能 | 状态 |
| --- | --- | --- |
| [CA-15](tasks/CA-15_whole-shot-miss-on-occlusion.md) | 准心区域含遮挡则整发落空 | 待实施 |

本轮任务卡逐项说明触发条件、应发生的行为与验收结果；派工时依赖最新卡片和系统当前代码。
