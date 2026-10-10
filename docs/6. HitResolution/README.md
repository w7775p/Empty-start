# 6. HitResolution 命中结算系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。已实现的基础卡用于接口复查；新的视觉、静止弹幕、对话与阶段打磨以最新单卡和此表为准。

## 2026-10-10 现行实现核对与任务状态

**现有结算：** `HitResolution.resolve_shot_results()` 汇总整发贡献并一次更新玩家 PK；HR-16 独立限制正向贡献，HR-17 将目标负贡献与单次整发异常扣分合并后限制负值，再与正向限幅结果相抵。玩家 PK `[0,1]` 范围仍由全局限幅处理。CA-15 的释放快照包含遮挡 ID 时，整发异常选择强制为 `MISS`，CombatAttack 提交空逐目标数组，由本系统沿用一次 `-0.01` 落空惩罚。无快照遮挡时，逐目标结算和既有异常优先级保持原行为。策划尚未确定单发上限数值，正负上限默认均为 `INF`，有限值仅由可选接口注入。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [HR-16](tasks/HR-16_shot-positive-cap.md) | 单发正值贡献独立上限 | 已实现，待提交 PR |
| [HR-17](tasks/HR-17_shot-negative-cap.md) | 单发负值贡献独立上限，包含一次整发异常扣分 | 已实现，PR #139 待 Review |

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


## 系统目标

命中结算系统是普通战斗的统一结算中心。

它负责：
1. 维护唯一玩家 PK 值；
2. 计算正常话语收益和陷阱惩罚；
3. 把同一发所有结果合并后一次性更新 PK；
4. 处理反弹、遮挡、落空等异常；
5. 处理复读零收益与部分目标失效；
6. 把最终 PK 和普通命中结果交给后续系统。

矛盾阶段的胜负不在这里判断。

## 当前已实现接口

INT-01 Sandbox 已接入真实攻击整发结果。CombatAttack 使用本系统计算普通与复读收益，并在结算后把逐目标原句、倾向与结果交给场景协调复读、倾向和弹幕移除。复读不进入普通命中历史。当前关重开创建新的 HitResolution，本次命中历史随旧对象丢弃；跨关提交仍等待正式胜利流程。

HR-01 由 `core/combat/hit_resolution.gd` 持有本场唯一玩家 PK，脚本为场景解耦的 `RefCounted` 对象。创建对象时传入本场初始 PK、下限和上限；重开时可调用 `initialize_player_pk()` 重置。`apply_player_pk_delta()` 统一修改并限制 PK，`get_player_pk()` 提供只读值。

DBG-01 增加 `set_player_pk_for_debug(value)` 作为开发调试入口。它按既有范围限制目标值，并复用 `apply_player_pk_delta()` 发出最终 PK 更新信号，因此 CombatStage 与 HUD 仍沿正式联动链刷新；常规玩法继续使用命中、惩罚和回拉入口。

对手占比只从玩家 PK 派生，不在其他系统保存第二份可写 PK。Tier 通知与攻击整发结算已接入 INT-01 Sandbox。

HR-02 的 `calculate_normal_word_reward(strength, tendency_id)` 按内容强度返回 `pk_delta` 和 `tendency_delta`，不修改当前 PK，也不提交三项倾向。PK 奖励从百分比换算为内部 0–1 比例：强度 1 为 `0.0012 / +1`，强度 2 为 `0.002 / +5`，强度 3 为 `0.005 / +10`；普通 `neutral` 命中保留对应强度的 PK 收益，但倾向增量固定为 0。Tier 不参与该接口。

HR-04 的 `calculate_repeat_hit_result()` 返回有效命中标记和零 PK、零倾向收益；它不修改 PK 或提交倾向。

HR-05 的 `resolve_shot_results(target_results, shot_anomaly=ShotAnomaly.NONE)` 接收逐目标结算字典，一次更新并限制玩家 PK。HR-16 / HR-17 为构造器增加可选的 `max_positive_pk_delta_per_shot=INF` 和 `max_negative_pk_delta_per_shot=INF` 参数；正向贡献按发汇总后独立限制，负向目标贡献与一次 `-0.01` 整发异常扣分合并后独立限制，再计算 PK 净变化。正负上限默认 `INF`，保留既有结算，策划定值前不改正式配置。返回的 `total_pk_delta` 是本发限幅及相抵后的净变化，逐目标结果仍深拷贝返回，倾向、有效命中和复读结果保持逐目标事实；最终 PK 信号仍只发出一次。有限上限通过 TEST_ONLY 用例显式注入。

BT-11（2026-10-09）补齐已存在真实 TraitResult 的惩罚消费：FAKE_CARD 每目标 `-0.005`，RETALIATION_COPY 每目标 `-0.007`，OCCLUSION / REFLECT 的目标 PK 为 0，特殊结果普通倾向与有效普通命中标记清零；CombatAttack 传入 HR-06 选出的整发异常，BOUNCE / OBSTRUCTION / MISS 每发扣 `-0.01`，和目标增量合并后仅更新一次 PK。沿用 `data/source_tables/06_战斗数值.csv` 正式值，4 / 5 不计算惩罚。终局关闭、PK 已归零提前返回的边界保持。尚无真实雷结果类型，雷映射仍待其正式接口；本次仅完成 BT-11 已有特性结果联调。

HR-08 在整发结算前检查当前 PK。若回拉已把 PK 降至下限，返回 `cancelled_by_zero_pk = true`、零 PK 增量和空 `target_results`，本发命中与倾向变化都不再传递；正常结算返回 false。

HR-09 由 `apply_player_pk_delta()` 在 clamp 后发出一次 `final_player_pk_updated(final_player_pk)`。HR-05 的整发汇总只调用该入口一次；OpponentPKBar 每次回拉更新也调用该入口一次。CS-06 负责将该信号连接到 CombatStage。

HR-14 由 `record_normal_word_hit(original_sentence_id, tendency)` 记录有效普通命中，包含 `neutral`。历史按原句 ID 归并，保留内容类别、命中次数、首次顺序和最近顺序；`get_normal_hit_history()` 返回深拷贝快照。复读与矛盾文本不写入此历史。

HR-15 由 `HitResolution.commit_normal_hit_history(SaveData)` 在最终 PK 胜利结果提交本场普通命中一次。`SaveData.committed_normal_hit_history` 按原句累计次数，用 `first_committed_hit_order` 保存第一次正式提交的跨关顺序；再次命中旧句不改变该顺序。失败或手动重开调用 `discard_uncommitted_normal_hit_history()` 丢弃本场暂存，之前已提交的周目历史保持不变。读取方使用 `SaveData.get_committed_normal_hit_history()` 的深拷贝。

HR-06 的 `select_shot_anomaly(has_bounce, has_obstruction, is_miss, has_release_snapshot_occlusion=false)` 每发只选择一个异常。CA-15 的原始释放快照含遮挡 ID 时优先返回 `MISS`；否则沿用 `BOUNCE > OBSTRUCTION > MISS`，无异常时返回 `NONE`。新增参数默认 false，原三参数调用继续兼容。调用方把同一反弹目标的重复报告合并为 `has_bounce` 后调用。

HR-07 的 `is_shot_fully_missed(target_validity)` 仅在没有任何有效目标时返回 true。只要有一个有效目标，其余失效目标不会增加落空异常；全失效或空目标列表仍可交给 HR-06 判断落空。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| HR-01 | PK 初始值与范围限制 | 2 个关键单元测试 |
| HR-02 | 正常话语收益 | 无 |
| HR-03 | 陷阱惩罚事件 | 无 |
| HR-04 | 复读命中零收益 | 无 |
| HR-05 | 同一发汇总后一次更新 PK | 1 个关键单元测试 |
| HR-06 | 单发异常优先级 | 3 个既有规则用例及 1 个 CA-15 快照遮挡用例 |
| HR-07 | 部分目标失效不额外落空 | 1 个关键单元测试 |
| HR-08 | 回拉已归零时取消本次命中 | 1 个关键单元测试 |
| HR-09 | 最终 PK 交给战斗阶段 | 无新增自动化测试 |
| HR-10 | 普通倾向结果交给三项倾向 | 无新增自动化测试 |
| HR-11 | 普通命中交给复读系统 | 无新增自动化测试 |
| HR-12 | 命中结果广播给直播表现 | 无新增自动化测试 |
| HR-13 | 矛盾阶段边界接线 | 无新增自动化测试 |
| HR-14 | 记录本场普通话语命中历史 | 1 个关键单元测试 |
| HR-15 | 普通命中历史提交与失败回滚 | 2 个关键单元测试 |
| HR-16 | 单发正向贡献限幅与旧默认行为 | 1 个关键单元测试 |
| HR-17 | 单发负向贡献限幅、异常只扣一次与旧默认行为 | 1 个测试脚本覆盖 3 项关键路径 |

## 测试预算

当前保留 16 个核心 case：

- PK 低于下限会被限制；
- PK 高于上限会被限制；
- 多目标同发只做一次最终 PK 更新；
- 异常优先级：常规反弹 > 遮挡 > 落空（3 case）；CA-15 释放快照遮挡强制 MISS（1 case）；
- 同发仍有有效目标时，其他目标失效不追加落空；
- 回拉先把 PK 归零时，本次命中取消；
- 同一原句重复命中时历史正确归并；
- PK 胜利提交普通命中历史；
- 失败重开撤回本次未提交普通命中历史。
- 单发正向贡献高于显式上限时先限幅，再与负贡献相抵，并保留逐目标倾向和复读有效命中事实；
- 未注入上限时继续按原始正负贡献汇总。
- 单发正负贡献分别限幅后求净变化；异常扣分并入负向上限且只计一次；未注入上限时维持旧结果。

正常话语数值、陷阱数值、复读零收益、跨系统广播全部不逐项堆单测。

## 依赖顺序

HR-01～08、HR-14 可以先完成纯结算核心和本场命中历史。
HR-09 等 8. CombatStage。
HR-10 / HR-11 已由 INT-01 组合真实整发结果、本场倾向和普通复读计划。
HR-12 的普通命中 / 陷阱表现增量继续等待 9. LiveDataPresentation 的数值规则；生成评论已接通。
HR-13（2026-10-09）已核实真实矛盾边界：满 PK 后 Sandbox 关闭普通结算，AttackChargeInput 的矛盾模式在释放时交付冻结快照，飞行结束跳过普通结算；12 的 `resolve_shot_hit_ids()` 独占成败判定，既有场景回调把真假矛盾命中创建为 10 的专用复读计划。阶段关闭后的晚到普通提交保留 `terminal_mode=true`，返回空 `target_results`，攻击端跳过其普通历史，避免倾向或普通复读收益泄漏。打满 PK 的最后一发仍按已完成的普通结算保留收益与历史。没有增加永久测试或重复接线，未修改 Sandbox；运行证据见本系统 HR-13 日志及 evidence。
HR-15 的失败回滚已接 Sandbox 重开与失败事件；胜利提交入口已提供，实际调用由 CB-12 按未击破或神谕确认后的最终结果接入。

## 2026-10-09 战斗打磨单功能开发卡

本轮确认的高密度弹幕、四种运动、交叉层级、富文本、舆论潮汐、弹幕群聚、伪纵深、命中冲击波、复读感染、Tier 升降档与沉默爆发，现已拆为单一功能开发卡。每张卡仅定义触发条件、预期行为与验收结果；可调数值以实测和后续策划配置为准。卡片状态均为**待实施**。

| 卡号 | 本卡唯一功能 | 状态 |
| --- | --- | --- |
| [HR-16](tasks/HR-16_shot-positive-cap.md) | 单发 PK 正向收益封顶 | 待实施 |
| [HR-17](tasks/HR-17_shot-negative-cap.md) | 单发 PK 负向惩罚封顶 | 待实施 |

关联依赖及实施顺序以各卡的上游功能卡为准；共享场景与组件按实际 Owner 的任务流程依次集成。
