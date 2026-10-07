# 6. HitResolution 命中结算系统任务拆分

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

HR-02 的 `calculate_normal_word_reward(strength)` 按强度返回 `pk_delta` 和 `tendency_delta`，不修改当前 PK，也不提交三项倾向。PK 奖励从百分比换算为内部 0–1 比例：强度 1 为 `0.0012 / +1`，强度 2 为 `0.002 / +5`，强度 3 为 `0.005 / +10`。Tier 不参与该接口。

HR-04 的 `calculate_repeat_hit_result()` 返回有效命中标记和零 PK、零倾向收益；它不修改 PK 或提交倾向。

HR-05 的 `resolve_shot_results(target_results)` 接收逐目标结算字典，先汇总全部 `pk_delta`，再一次性更新并限制玩家 PK。返回整发的 `total_pk_delta` 与 `final_player_pk`，并深拷贝保留原有 `target_results`，供后续读取每个目标的倾向变化；最终 PK 信号同步交给 CombatStage。

HR-08 在整发结算前检查当前 PK。若回拉已把 PK 降至下限，返回 `cancelled_by_zero_pk = true`、零 PK 增量和空 `target_results`，本发命中与倾向变化都不再传递；正常结算返回 false。

HR-09 由 `apply_player_pk_delta()` 在 clamp 后发出一次 `final_player_pk_updated(final_player_pk)`。HR-05 的整发汇总只调用该入口一次；OpponentPKBar 每次回拉更新也调用该入口一次。CS-06 负责将该信号连接到 CombatStage。

HR-14 由 `record_normal_word_hit(original_sentence_id, tendency)` 记录有效普通命中。历史按原句 ID 归并，保留倾向、命中次数、首次顺序和最近顺序；`get_normal_hit_history()` 返回深拷贝快照。复读与矛盾文本不写入此历史。

HR-15 由 `HitResolution.commit_normal_hit_history(SaveData)` 在最终 PK 胜利结果提交本场普通命中一次。`SaveData.committed_normal_hit_history` 按原句累计次数，用 `first_committed_hit_order` 保存第一次正式提交的跨关顺序；再次命中旧句不改变该顺序。失败或手动重开调用 `discard_uncommitted_normal_hit_history()` 丢弃本场暂存，之前已提交的周目历史保持不变。读取方使用 `SaveData.get_committed_normal_hit_history()` 的深拷贝。

HR-06 的 `select_shot_anomaly(has_bounce, has_obstruction, is_miss)` 每发只选择一个异常，顺序为 `BOUNCE > OBSTRUCTION > MISS`；没有异常时返回 `NONE`。调用方把同一反弹目标的重复报告合并为 `has_bounce` 后调用。

HR-07 的 `is_shot_fully_missed(target_validity)` 仅在没有任何有效目标时返回 true。只要有一个有效目标，其余失效目标不会增加落空异常；全失效或空目标列表仍可交给 HR-06 判断落空。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| HR-01 | PK 初始值与范围限制 | 2 个关键单元测试 |
| HR-02 | 正常话语收益 | 无 |
| HR-03 | 陷阱惩罚事件 | 无 |
| HR-04 | 复读命中零收益 | 无 |
| HR-05 | 同一发汇总后一次更新 PK | 1 个关键单元测试 |
| HR-06 | 单发异常优先级 | 3 个关键单元测试 |
| HR-07 | 部分目标失效不额外落空 | 1 个关键单元测试 |
| HR-08 | 回拉已归零时取消本次命中 | 1 个关键单元测试 |
| HR-09 | 最终 PK 交给战斗阶段 | 无新增自动化测试 |
| HR-10 | 普通倾向结果交给三项倾向 | 无新增自动化测试 |
| HR-11 | 普通命中交给复读系统 | 无新增自动化测试 |
| HR-12 | 命中结果广播给直播表现 | 无新增自动化测试 |
| HR-13 | 矛盾阶段边界接线 | 无新增自动化测试 |
| HR-14 | 记录本场普通话语命中历史 | 1 个关键单元测试 |
| HR-15 | 普通命中历史提交与失败回滚 | 2 个关键单元测试 |

## 测试预算

只保留 11 个核心 case：

- PK 低于下限会被限制；
- PK 高于上限会被限制；
- 多目标同发只做一次最终 PK 更新；
- 异常优先级：反弹 > 遮挡 > 落空（3 case）；
- 同发仍有有效目标时，其他目标失效不追加落空；
- 回拉先把 PK 归零时，本次命中取消；
- 同一原句重复命中时历史正确归并；
- PK 胜利提交普通命中历史；
- 失败重开撤回本次未提交普通命中历史。

正常话语数值、陷阱数值、复读零收益、跨系统广播全部不逐项堆单测。

## 依赖顺序

HR-01～08、HR-14 可以先完成纯结算核心和本场命中历史。
HR-09 等 8. CombatStage。
HR-10 / HR-11 已由 INT-01 组合真实整发结果、本场倾向和普通复读计划。
HR-12 的普通命中 / 陷阱表现增量继续等待 9. LiveDataPresentation 的数值规则；生成评论已接通。
HR-13 等 12. ContradictionBreak。
HR-15 的失败回滚已接 Sandbox 重开与失败事件；胜利提交入口已提供，实际调用由 CB-12 按未击破或神谕确认后的最终结果接入。
