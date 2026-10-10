# 12. ContradictionBreak 矛盾击破系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。已实现的基础卡用于接口复查；新的视觉、静止弹幕、对话与阶段打磨以最新单卡和此表为准。

## INT-08 当前组合入口（2026-10-10）

矛盾业务规则继续由 `ContradictionBreakSystem` 持有；本场生命周期、释放快照接收、复读等待、静音过渡和 Rest 结果准备由 `ContradictionOracleFlow` 组合，Sandbox 在普通 PK 满值后通过 `start(...)` 注入现有组件。旧接线章节中的 Sandbox 内部协调方法已迁入该流程；接口和完整签名见 [Integration README](../Integration/README.md)。

真、假矛盾命中均创建有限复读，等队列与场上可见矛盾复读全部结束；真击破再经过原 0.5 秒静音进入神谕，未击破提交普通历史与倾向后交付 `pk_win_unbroken` Rest。空命中或十秒超时没有矛盾复读，可直接交接。结果通知保留唯一判定，重复发射及通知不会再生成复读或提交成果。Windows 实景和准确退出码见 INT-08 日志。

## 2026-10-11 CB-13 实现状态

T5 满 PK 后进入独立矛盾击破阶段，UI 表现名为 T6/Paradox。`ContradictionBreakSystem.get_fixed_paradox_candidates()` 按当前关卡顺序取第一条有效真句，再取五个有效假句；假句条目不足五条时循环复用现有原句 ID 与文本，不生成正式内容。阶段协调方把候选分组后交给 `BarrageArea`，后者一次性显示六个实例，按候选集合数量独立限容，不占普通前景容量，也不再轮换后续批次。

当前 `level_001.tres` 示例资源只有一条真矛盾和一条假矛盾，因此该示例运行时会显示一条真句实例与五条同 ID 的假句实例。项目尚无最终对手矛盾文本池，本实现不能证明最终正式文本具备五条不同假句；`tests/fixtures/contradiction_break/test_cb_13_six_candidates_level.tres` 用六个不同 `test_` ID 验证完整内容路径。没有修改关卡源表、导表器或正式关卡 Resource。

现有 10 秒窗口、一发正式射击、释放快照冻结的原句事实、真/假结果与后续复读/神谕/休息流程保持原规则。CB-14 的减速运动仍待实施。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [CB-13](tasks/CB-13_six-fixed-contradictions.md) | T6 固定一真五假候选集；数据不足时复用有效假句 | 已实现；现行 LevelProfile 示例仅提供一个假句 ID |
| [CB-14](tasks/CB-14_contradiction-ease-out-motion.md) | 六句减速停止，运动时可射击 | 待开发 |

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


## 系统目标

矛盾击破系统负责普通 PK 条打满后的特殊阶段。

它需要：

1. 读取当前主播的真矛盾、假矛盾和前文线索；
2. 启动限时窗口和有限发射次数；
3. 接收战斗攻击系统的一发命中集合；
4. 一发中只要含真矛盾就立即判定击破成功；
5. 只命中假矛盾或落空会消耗一次正式发射机会；机会用完或超时后属于“PK 已胜利但未击破”；
6. 真 / 假矛盾命中都可以触发复读；
7. 成功时等待命中复读展示后进入终结神谕；
8. 未击破时直接进入休息时刻；
9. 矛盾命中不产生普通话语 PK 与倾向奖励。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| CB-01 | 接收 PK 满并进入矛盾阶段 | 无 |
| CB-02 | 读取真假矛盾与前文线索 | 无 |
| CB-03 | 请求生成真假矛盾 | 无新增自动化测试 |
| CB-04 | 限时窗口与发射次数 | 2 个关键单元测试 |
| CB-05 | 一发命中集合即时判定 | 3 个关键单元测试 |
| CB-06 | 机会耗尽与超时判定 | 3 个关键单元测试 |
| CB-07 | 判定完成后固定结果并关闭攻击 | 1 个关键单元测试 |
| CB-08 | 真 / 假矛盾命中触发复读 | 无新增自动化测试 |
| CB-09 | 成功后等待复读再进神谕 | 无新增自动化测试 |
| CB-10 | 未击破直接进入休息 | 无新增自动化测试 |
| CB-11 | 暂停时停止倒计时 | 无 |
| CB-12 | 本场普通话语记录随结果提交 | 无新增自动化测试 |

## 测试预算

只保留 9 个核心 case：

- 已蓄满实际发射才消耗一次发射机会；
- 未蓄满取消不消耗机会；
- 一发含真矛盾 → 成功；
- 一发只有假矛盾时消耗一次机会并继续；
- 一发落空时消耗一次机会并继续；
- 发射机会耗尽时得到未击破结果；
- 倒计时到期且尚无结果时得到未击破结果；
- 结果固定后，后续流程继续使用这份已确定结果。

计时器运行、弹幕生成、复读演出、休息和神谕流程全部用最小实际联调。

## 依赖顺序

CB-01 等 8. CombatStage。
CB-02 可在 2. LevelConfiguration 数据完成后做。
CB-13 使用 BG-12 的 `BarrageArea.start_contradiction_generation()`；`ContradictionBreakSystem` 读取当前关内容并创建固定候选集，阶段协调方传入一条真句与五条假句。`BarrageArea` 保存稳定原句 ID、矛盾标记与空 TraitSet，按六个矛盾实例独立限容并仅生成初始集合；真假判定仍归本系统。
CB-04 由 Sandbox 从 `contradiction_window_config.tres` 启动 10 秒窗口，攻击系统满蓄释放的 `shot_snapshot_created` 通知本系统登记一次发射。矛盾模式不提交普通 PK 与倾向。
CB-05 由 Sandbox 从释放瞬间冻结的 `AttackTargetSnapshot.get_contradiction_facts()` 读取稳定原句 ID，一发合并成 `Array[String]` 立即调用 `resolve_shot_hit_ids()`；落空传空数组。目标在飞行期间移动或消失不改变结果，飞行只做演出；命中的矛盾视图由弹幕区域结束，不进入普通结算。
CB-07 由 Sandbox 订阅 `outcome_locked`，一旦结果固定便禁止新攻击并清理剩余矛盾弹幕；后续成功与未击破分支均读取 `get_outcome()`。
CB-08 对每条有效命中的真 / 假矛盾，都按当前 Sandbox 矛盾复读配置创建 `RepeatPlan.RepeatType.CONTRADICTION` 计划；实际生成和分类统计归 10 系统。成功时等展示完成；未击破直接进入 Rest 时撤销尚未展示的队列。
CB-09 成功结果等待矛盾复读队列及场上可见实例全部结束，再调用 `AudioManager.stop_music()` 完成 0.5 秒可暂停的过渡；随后向 `FinalOracleSession.open_after_breakthrough()` 交付当前关和本场普通历史 / 普通复读统计，并发出 `Sandbox.final_oracle_opened`。FO-13 由 Sandbox 在中央 BattleArea 显示冻结候选，并把其目标交给普通 AttackChargeInput 选择链。
CB-10 未击破结果直接将当前关 ID、PK 胜利且未击破标记与空新增奖励交给 `RestSession.open_result()`，结束 CB 阶段并发出 `Sandbox.rest_opened`。成功分支在 `FinalOracleSession.open_after_breakthrough()` 接受结果后同样结束 CB 阶段。18 系统后续负责展示与继续流程。
CB-12 调用 HR-15 的 `HitResolution.commit_normal_hit_history(SaveManager.data)`：未击破分支在休息入口接受结果后提交；成功分支等 `FinalOracleConfirmationState.confirmation_committed` 发出且当前关与当前周目匹配后提交。两条路径均由 HR-15 保证本场仅提交一次，失败重开只丢弃本场暂存。
CB-04～07 可以完成核心判定逻辑。
CB-08 等 10. Repeat。
CB-09 等 13. FinalOracle。
CB-10 已接 18. Rest 的 RS-01 结果入口。
CB-12 已接 HR-15 的普通命中历史提交入口；成功分支由 FO-13 的中央候选与普通攻击完成选择，奖励和休息继续按 13 系统后续任务卡接入。

INT-01 留下的胜利倾向提交缺口已在隔离集成分支按 TT-03 补齐：未击破进入休息和成功后神谕确认时调用 `TendencyState.commit_attempt_tendency()`；失败、重开及退出场景仍只回滚未提交的本场暂存。

## 2026-10-09 新确认：T6 六句的速度曲线

T6 / Paradox 保留 **1 真 + 5 假** 的六句构成。六句在出现后先移动，再沿可配置速度曲线逐渐减速到停止；**移动期间已经可以蓄力、释放并完成命中判定**，停止后同样可射击。继续使用现有 10 秒窗口和一发机会。

| 任务卡 | 单功能 | 状态 |
| --- | --- | --- |
| [CB-13](tasks/CB-13_six-fixed-contradictions.md) | 固定一真五假初始集合 | 已实现；缺少不同假句时复用现有有效条目 |
| [CB-14](tasks/CB-14_contradiction-ease-out-motion.md) | 六句逐渐减速至停止，运动时可射击 | 待开发 |
