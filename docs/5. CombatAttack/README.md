# 5. CombatAttack 战斗攻击系统任务拆分

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
- `reticle_diameter` 是准心局部设计坐标中的直径；INT-01 将 `AimReticle` 放在 `BattleHud` 内，与弹幕统一继承 1920×1080 舞台缩放。默认 32 设计像素在 1152×648 窗口显示为 19.2 像素。
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
- CA-10（2026-10-09）已用现有 TEST_ONLY Sandbox 实际核验接线：满蓄释放的 `shot_snapshot_created` 经 Sandbox 合并冻结原句 ID，依次调用 12 的 `register_launched_shot()` / `resolve_shot_hit_ids()`；真、假命中均创建 10 的矛盾复读计划。未蓄满释放没有快照，当前单发机会保持为 1；正式释放后机会为 0，结果锁定禁止第二发。当前运行代码已满足这些接口验收，本卡仅更新文档。
- CA-10 展示交接给 Lane A：最后一发假矛盾的复读计划已入队，但 `_open_rest_after_unbroken()` 同步清空矛盾队列，实际生成数为 0；成功分支能实际生成复读。若要求假矛盾展示完再进入 Rest，由 Sandbox 所有者调整未击破过渡，具体位置见 CA-10 日志。

### INT-01 战斗生命周期与结算事实

`AttackChargeInput.set_combat_active(active: bool)` 供场景协调战斗停止与重开。传入 `false` 会禁用攻击输入、清零蓄力、取消飞行 / 硬直和 Timer，并恢复阶段为 READY；传入 `true` 后可开始下一发。暂停继续通过 SceneTree 控制，保留当前蓄力与剩余计时。

矛盾阶段由 Sandbox 调用 `set_contradiction_mode(true)`；满蓄释放的 `shot_snapshot_created` 携带当帧冻结的矛盾原句事实，由 12 系统立即判定并消耗机会。飞行计时只保留演出，不再复核目标或发送到达结算；结果锁定后 `lock_new_attacks()` 禁止下一发而保留当前飞行。进入 Rest / FinalOracle 时停止攻击；重开普通战斗时调用 `set_contradiction_mode(false)`。

FinalOracle 选择阶段由 Sandbox 将中央 `FinalOracleCandidateDisplay` 生成的 Label 控件注入 `set_selection_targets()`。攻击系统只发出释放快照中实际命中的目标；同发多目标时按快照准心中心到控件中心的距离选择最近一句。Sandbox 用该目标 ID 回读 Session 的冻结候选，并提交至唯一确认入口。选择阶段不会调用 HitResolution。

`HitResolution.resolve_shot_results()` 同步发送最终 PK，回调可能在满值或失败时停止攻击。到达处理在回调后检查本发仍有效，保证已停止的战斗不会再次启动硬直 Timer。当前这一发成功结算的提交事实仍会发送，供协调方处理命中与倾向。

`submission.hit_resolution_result.target_results` 每个目标除 `target_instance_id`、`target`、`trait_result` 外，携带 `original_sentence_id`、`original_sentence_text`、`source_id`、`is_repeat`、`tendency_id`、`tendency_delta`、`is_valid_hit`。内容事实在提交前从运行时记录复制，协调方无需回读可能已结束的弹幕节点。正常普通话语取得 HitResolution 计算的奖励并记录普通命中历史；复读调用 `calculate_repeat_hit_result()`，有效命中、PK 与倾向增量为零，且不会记录普通命中历史。整发在 PK 下限作废时，HitResolution 返回空目标结果。

- DBG-01 增加 `AttackChargeInput.is_charge_held()`，供调试面板读取真实按住状态并显示“蓄力中”；阶段和蓄力比例仍由 `get_attack_phase()`、`get_charge_progress()` 提供。

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
CA-10 接线已在 e3558b4 基线实际验收；假矛盾复读展示保留 Lane A 交接项。
CA-12 #83 仍开放，由 Android 输入适配任务处理；CA-10 未修改其 `attack_charge_input.gd`，Android 导出尚未验证。
