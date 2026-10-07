# 13. FinalOracle 终结神谕系统任务拆分

## 系统目标

终结神谕系统只在矛盾击破成功后出现。

它负责：

1. 等待击破后的过渡与复读展示完成；
2. 冻结战斗；
3. 从本场成功命中的普通话语中生成最多三句候选；
4. 每种倾向优先选择普通复读最多的一句；
5. 处理并列、缺少某种倾向和不足三句；
6. 给玩家 10 秒选择；
7. 超时自动选择；
8. 确认后一次性提交圣典、败者卡和吞并结果；
9. 完成后进入休息时刻。

矛盾文本和复读文本都不进入候选。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| FO-01 | 击破成功后进入神谕并冻结战斗 | 无 |
| FO-02 | 建立合格候选池并按原句去重 | 2 个关键单元测试 |
| FO-03 | 每种倾向选复读最多的一句 | 1 个关键单元测试 |
| FO-04 | 候选并列裁决 | 2 个关键单元测试 |
| FO-05 | 候选补位并限制最多三句 | 1 个关键单元测试 |
| FO-06 | 展示后冻结候选列表 | 无 |
| FO-07 | 10 秒选择计时与暂停 | 无 |
| FO-08 | 超时自动选择 | 1 个关键单元测试 |
| FO-09 | 手动 / 自动确认共用一次提交 | 1 个关键单元测试 |
| FO-10 | 保存到圣典系统 | 无新增自动化测试 |
| FO-11 | 发放败者卡与吞并奖励 | 无新增自动化测试 |
| FO-12 | 完成后进入休息时刻 | 无新增自动化测试 |

## 测试预算

只保留 8 个纯逻辑 case：

- 同一原句多次命中后候选池只保留一条；
- 矛盾与复读文本不进入候选池；
- 每种倾向优先选普通复读最多的一句；
- 复读数并列时优先最近命中的句子；
- 命中时间仍并列时按原句标识排序；
- 候选缺倾向时能够补位且总数不超过三句；
- 超时自动选择按正式排序规则得到一句；
- 同一场手动 / 自动确认最终只提交一次。

UI、10 秒计时器、战斗冻结、奖励系统和休息流程全部做实际联调。

## 依赖顺序

隔离集成分支新增 `FinalOracleSession.open_after_breakthrough(level_id, normal_hit_history, repeat_stats, confirmation_state)` 作为 FO-01 的最小真实接收入口：只接受一次击破完成事实，复用现有候选池并冻结展示快照；战斗冻结仍由调用方负责。`confirm_display_candidate(candidate)` 仅接受本次展示中的原句 ID，并调用周目级 FO-09 确认状态。`ui/final_oracle/final_oracle_screen.tscn` 现由 Sandbox 的 `final_oracle_opened` 接线显示 FO-06 冻结候选；FO-07～09 的计时、超时和单次确认仍需接入该 UI。FO-10～12 继续等待对应奖励与休息系统。

FO-01 等 12. ContradictionBreak 的成功与过渡完成事件。
FO-02～05 在【6. HitResolution】HR-14 的本场普通命中历史与【10. Repeat】普通复读统计存在后完成纯候选逻辑。
FO-06～09 完成神谕选择流程。
FO-10 等 15. Scripture。
FO-11 等 16. LoserCard 与 14. Assimilation。
FO-12 等 18. Rest。

## FO-02 当前候选池接口

- `FinalOracleCandidatePool.build_from_normal_hit_history(normal_hit_history)` 只接收 `HitResolution.get_normal_hit_history()` 返回的普通命中快照。
- 候选按 `original_sentence_id` 去重，并保留首次出现顺序及 HR-14 的原始记录字段；返回值是独立深拷贝。
- 普通复读统计和矛盾复读记录不作为候选来源。后续排序只读取 `RepeatGenerationStats.get_normal_count(original_line_id)`，不会从复读记录新增候选。
- HR-14 已将同一句的普通命中次数和最近命中顺序合并到唯一记录；若输入重复 ID，候选池保留首条记录，不自行汇总第二份统计。

## FO-03 / FO-04 倾向排序接口

- `FinalOracleCandidatePool.select_most_repeated_per_tendency(candidates, repeat_stats)` 对正统、异端、荒谬分别选择普通复读实际生成数最高的一句。
- 计数通过 `RepeatGenerationStats.get_normal_count(StringName(original_sentence_id))` 读取；矛盾复读统计不参与。
- 复读数相同时优先最近命中更晚的句子；最近命中顺序仍并列时按稳定原句 ID 升序裁决。

## FO-05 候选补位接口

- `FinalOracleCandidatePool.fill_missing_tendency_candidates(candidates, repeat_stats)` 先保留各倾向领头候选，再从剩余普通命中候选补足，最多返回三句。
- 补位顺序读取普通复读实际生成数降序、HR-14 的 `last_hit_order` 降序、`original_sentence_id` 升序；复读数由 `RepeatGenerationStats.get_normal_count()` 提供，矛盾复读不参与。若普通话语不足三句，则返回实际数量。

## FO-06 展示快照接口

- 候选展示开放时调用 `snapshot_for_display(final_candidates)` 一次，并保留返回的深拷贝数组作为本次展示列表。
- 选择期间继续显示该快照的原顺序和内容；后续命中或复读统计变化不会重建或重排当前列表。
- Sandbox 在 `final_oracle_opened` 后调用 `FinalOracleScreen.present_session(session)`；界面从 Session 读取一次展示快照，最多显示三句。原句正文按稳定 ID 从当前 `LevelProfile.normal_speech_pool` 补入展示副本，不写回 HitResolution 的历史。

## FO-07 倒计时接口

- 候选列表可操作时调用 `FinalOracleSelectionTimer.start()`，从 10 秒开始计时。
- 每帧调用 `advance(delta_seconds, is_globally_paused)`；当前暂停菜单通过 `get_tree().paused` 管理全局暂停，暂停期间将该值传入，倒计时保持不变。
- `remaining_time_changed(seconds_remaining)` 可驱动倒计时显示；到期时发出 `expired`，由 FO-08 接入自动选择。
- `FinalOracleScreen.present_session(session)` 在非空候选展示时启动计时器；页面使用 `PROCESS_MODE_ALWAYS` 读取全局暂停状态，并将剩余秒数更新到倒计时标签。

## FO-08 超时自动选择接口

- 计时器 `expired` 后，调用 `select_auto_pick_from_display(display_snapshot, repeat_stats)` 从冻结展示列表选择一条候选。
- 正式排序为普通复读实际数量降序、最近命中顺序降序、稳定原句 ID 升序；空展示列表返回空 Dictionary。
- 页面计时到期后调用 `FinalOracleSession.select_timeout_candidate()`，从 Session 持有的冻结展示快照和 Repeat 统计中选句，再发出 `selection_requested(candidate)` 交给 FO-09。

## FO-09 单次确认接口

- 每个当前周目创建并复用一个 `FinalOracleConfirmationState.new(SaveManager.data)`。
- 手动选择和超时自动选择都调用 `confirm_selection(level_id, candidate)`；同一周目同一 `level_id` 只接受第一次有效结果。
- 首次确认发出 `confirmation_committed(run_data, level_id, candidate)`；重复调用返回 `false` 且不会重发信号。`get_confirmed_selection(level_id)` 始终返回首次候选快照。
- 本版确认不改写三项倾向累计值，额外倾向保持为 0。
