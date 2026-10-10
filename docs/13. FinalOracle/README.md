# 13. FinalOracle 终结神谕系统任务拆分

## INT-08 当前组合入口（2026-10-10）

`ContradictionOracleFlow` 持有神谕 Session、选择计时与同周目确认状态，并绑定 Scripture 的既有正式确认接收链。手动攻击与超时选择共用 `confirm_candidate(candidate) -> bool`；true 表示首次确认被接受，成果完成由 `rest_ready(result: RestSession)` 通知。流程通过原所有者接口按圣典、普通历史、倾向、败者卡、真正击败、可继承普通池与白名单特性的顺序提交和核验；写入失败停止后续提交及 Rest，已保存成果保留，显式 `commit_confirmed_rewards()` 可在来源修复后补齐。

成果去重继续由确认状态及 14/15/16 保存事实负责。缺卡资料、禁止继承和矛盾池沿用原无新增规则；同关已确认重开复用首次候选并核验已有成果。成功的 Rest 在同步确认与攻击回调结束后延迟交付，重开取消旧交接；Sandbox 只展示 Rest 并保持下一关与终局路由。旧接线章节中的 Sandbox 内部协调已迁入流程，公开接口、实际回归和限制见 [Integration README](../Integration/README.md) 与 INT-08 日志。

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

矛盾文本、复读文本和 neutral 普通闲聊都不进入候选；neutral 仍可保存在普通命中历史中。

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
| FO-13 | 主游戏区内复用普通攻击选择神谕 | 无新增自动化测试 |
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

`FinalOracleSession.open_after_breakthrough(level_id, normal_hit_history, repeat_stats, confirmation_state)` 是 FO-01 的真实接收入口：只接受一次击破完成事实，复用候选池并冻结展示快照；普通战斗冻结由 Sandbox 协调。FO-06～09 的候选快照、倒计时、自动排序和单次确认均已完成；FO-13 将展示与手动操作接入中央主游戏区的普通攻击链；FO-10 已复用 SC-02 的 Scripture 正式确认接收链。FO-11 已完成奖励程序接线与 TEST_ONLY 完整场景验收，正式奖励配置仍待交付；FO-12 已在确认及奖励提交后接通真实 Rest。

FO-01 等 12. ContradictionBreak 的成功与过渡完成事件。
FO-02～05 在【6. HitResolution】HR-14 的本场普通命中历史与【10. Repeat】普通复读统计存在后完成纯候选逻辑。
FO-06～09 完成神谕选择流程。
FO-13 在 FO-06～09 基础上替换正式交互表现：候选进入中央主游戏区，并复用普通攻击完成选择；应在 FO-10～12 奖励与休息联调前完成。
FO-10 已复用 SC-02 已接入的 Scripture 正式确认接口：Sandbox 创建并绑定当前周目的确认状态，确认事实携带 `level_id` 与候选原句 ID / 倾向，Scripture 从 `LevelCatalog` 解析原句文本、主播名、原关卡序号并按 `SaveData.scripture_data` 同关去重写入。
FO-11 已接入 16 发卡、14 真正击败及允许继承词库 / 特性登记，复用前置 TEST_ONLY 资源验收；生产默认目录保持原状，详见下方接线状态。
FO-12 已接入 `RestSession.open_result()` 与 `RestResultView.show_result()`，成功分支沿用 RS-09 的 Continue 进入下一普通关；末关 DD 转场留 RS-10。

## FO-02 当前候选池接口

- `FinalOracleCandidatePool.build_from_normal_hit_history(normal_hit_history)` 只接收 `HitResolution.get_normal_hit_history()` 返回的普通命中快照，并仅保留 `orthodox / heretical / absurd` 三类正式候选。
- 候选按 `original_sentence_id` 去重，并保留首次出现顺序及 HR-14 的原始记录字段；返回值是独立深拷贝。
- 普通复读统计和矛盾复读记录不作为候选来源。后续排序只读取 `RepeatGenerationStats.get_normal_count(original_line_id)`，不会从复读记录新增候选。
- HR-14 已将同一句的普通命中次数和最近命中顺序合并到唯一记录；若输入重复 ID，候选池保留首条记录，不自行汇总第二份统计。

## FO-03 / FO-04 倾向排序接口

- `FinalOracleCandidatePool.select_most_repeated_per_tendency(candidates, repeat_stats)` 对正统、异端、荒谬分别选择普通复读实际生成数最高的一句。
- 计数通过 `RepeatGenerationStats.get_normal_count(StringName(original_sentence_id))` 读取；矛盾复读统计不参与。
- RP-12 已复用并验证这条正式只读链：Sandbox 将本场队列持有的统计直接传入 Session，13 只读取实际普通计数；没有另存复读统计或从周目总量替代本场数量。
- 复读数相同时优先最近命中更晚的句子；最近命中顺序仍并列时按稳定原句 ID 升序裁决。

## FO-05 候选补位接口

- `FinalOracleCandidatePool.fill_missing_tendency_candidates(candidates, repeat_stats)` 先保留各倾向领头候选，再从剩余普通命中候选补足，最多返回三句。
- 补位顺序读取普通复读实际生成数降序、HR-14 的 `last_hit_order` 降序、`original_sentence_id` 升序；复读数由 `RepeatGenerationStats.get_normal_count()` 提供，矛盾复读不参与。若普通话语不足三句，则返回实际数量。

## FO-06 展示快照接口

- 候选展示开放时调用 `snapshot_for_display(final_candidates)` 一次，并保留返回的深拷贝数组作为本次展示列表。
- 选择期间继续显示该快照的原顺序和内容；后续命中或复读统计变化不会重建或重排当前列表。
- Sandbox 在 `final_oracle_opened` 后将 Session 的展示快照交给 `FinalOracleCandidateDisplay.show_candidates()`；正文从当前 `LevelProfile.normal_speech_pool` 按稳定 ID 补到 HitResolution 返回的深拷贝，不写回命中历史。
- FO-13 的候选显示为中央 `BattleArea` 内的普通 Label，最多三条，文字框也是普通攻击的目标区域；不显示倾向、序号、卡片或选择按钮。

## FO-07 倒计时接口

- 候选列表可操作时调用 `FinalOracleSelectionTimer.start()`，从 10 秒开始计时。
- Sandbox 在候选显示且普通攻击目标配置成功后启动计时器，并在 `_process()` 中调用 `advance(delta, get_tree().paused)`。
- PauseMenu 暂停 `SceneTree` 时 Sandbox 不推进计时；`remaining_time_changed(seconds_remaining)` 更新既有战斗状态栏。
- 到期时发出 `expired`，由 Sandbox 执行 FO-08 自动候选选择。

## FO-08 超时自动选择接口

- 计时器 `expired` 后，调用 `select_auto_pick_from_display(display_snapshot, repeat_stats)` 从冻结展示列表选择一条候选。
- 正式排序为普通复读实际数量降序、最近命中顺序降序、稳定原句 ID 升序；空展示列表返回空 Dictionary。
- 计时器到期后 Sandbox 调用 `FinalOracleSession.select_timeout_candidate()`，从冻结展示快照和 Repeat 统计中选句，再交给 FO-09 共同确认入口。

## FO-09 单次确认接口

- 每个当前周目创建并复用一个 `FinalOracleConfirmationState.new(SaveManager.data)`。
- 手动攻击命中和超时自动选择都调用 `confirm_display_candidate(candidate)` → `confirm_selection(level_id, candidate)`；同一周目同一 `level_id` 只接受第一次有效结果。
- 首次确认发出 `confirmation_committed(run_data, level_id, candidate)`；重复调用返回 `false` 且不会重发信号。`get_confirmed_selection(level_id)` 始终返回首次候选快照。
- 本版确认不改写三项倾向累计值，额外倾向保持为 0。

## FO-13 主游戏区攻击选择

- `FinalOracleCandidateDisplay` 位于 `BattleHud/BattleArea` 内，候选控件固定排布，原句正文直接使用 Label 显示。
- Sandbox 将这些 `Control` 注入 `AttackChargeInput.set_selection_targets()`；玩家仍使用现有准心、蓄力、发射和飞行阶段。
- `AttackTargetSnapshot` 在释放时冻结命中候选 ID 和准心中心；到达时只复核仍可见的冻结目标。同发命中多句时只发出准心中心最近的一句，等距时保留展示顺序。
- 选择模式不会调用 HitResolution、PK、倾向或普通复读结算；普通弹幕生成和对手回拉在进入神谕时保持停止。
- 手动攻击命中和超时自动选择统一进入 `Sandbox._confirm_oracle_candidate()`，最终由 FO-09 的当前周目 `SaveData + level_id` 确认器防重。
- 旧 `FinalOracleScreen` Panel / Button 页面已删除；Sandbox 保留 `final_oracle_opened(session)` 作为阶段事实通知。

## Scripture 确认接收

- SC-02 已由 `run_data.scripture_data.bind_confirmation_state(confirmation_state, level_catalog)` 订阅正式确认事实；Sandbox 在创建确认状态后完成绑定。
- 当前候选仅有原句 ID 和倾向，Scripture 从注入的真实关卡目录解析原句文本、主播名和章号，保存首条经文；同关重复提交保持首条。
- Scripture 的未确认快照由 `stage_oracle()` 单独暂存；正式确认按本次候选写入并清同关暂存，重开只撤回暂存，已经确认的经文和节号保留。

## FO-10 圣典接线状态

- FO-10 没有新增接口：当前 main 已具备 `FinalOracleConfirmationState.confirmation_committed`、`ScriptureData.bind_confirmation_state()` 和 Sandbox 周目初始化绑定。
- 手动候选与超时候选都经过同一 `FinalOracleSession.confirm_display_candidate()`，首次确认触发 Scripture 写入；同关第二次确认由确认状态和 Scripture 保存列表共同拒绝。
- Scripture 写入保留原句 ID、原句文本、倾向、主播名、关卡 ID 和章号；本卡只确认接线，不改动节号、奖励或休息流程。

## FO-11 奖励接线状态（程序接线完成，正式内容待配置）

- 手动 / 自动选择仍共用现有 Session 和确认状态。`confirmation_committed` 后，Sandbox 的现有回调检查当前周目、Session 关卡、CB `BREAKTHROUGH` 与当前 LevelProfile，提交普通历史后调用 `LoserCardData.grant_on_true_defeat()` 和 `AssimilationData.register_defeated_streamer()`。
- 关卡 / 主播来源直接读取当前 `LevelProfile.level_id / streamer_id`；状态数据继续由 `SaveData.loser_card_data / assimilation_data` 拥有。首次确认广播一次，接收方沿用已有周目内关卡 / 主播去重；仅 PK 胜利未击破分支不会进入此接线。
- Sandbox 的 `loser_card_catalog` 默认读取正式 `data/loser_card/loser_card_catalog.tres`。当前目录仍为空，16 收到提交请求后按已有规则拒绝无资料卡片，正式发卡验收尚未成立。
- Sandbox 在 `AssimilationData.register_defeated_streamer()` 首次返回 `true` 后读取 `LevelProfile.normal_pool_inheritance`，把稳定 pool_id、整池权重、`can_inherit` 与 `is_contradiction_pool` 交给 `register_inherited_word_pool()`；null 配置跳过，继承资格和矛盾排除继续由 14 判断。
- 特性仅遍历当前关卡的 `inheritable_trait_ids`，逐项调用 `register_inherited_trait()`；本关启用的 `special_trait_ids` 不作为奖励白名单。词库 / 特性权重与去重继续由 14 保存，13 不维护另一份成果或兼容规则。
- RS-09 已提供可注入的 Sandbox `level_catalog`，运行状态与 Scripture 绑定共用同一目录。FO-11 验收实例显式注入 `tests/fixtures/fo11/test_level_catalog.tres` 与 `test_loser_card_catalog.tres`，通过真实 PK、矛盾成功和正式 Session 确认取得一张测试卡、普通池 `test_only_streamer_sample_normal`（TEST_ONLY 权重 1.0）及 `occlusion`；重复手动 / 自动确认及重开同关均保持首份奖励。
- 正式默认空卡目录、null 池和空白名单下仍可确认，14 仅保存真正击败事实，内容保持为空；测试配置存在时的 PK 胜利但未击破分支也没有卡片、击败或继承奖励。缺少正式资源时不补造内容，换正式配置后使用新周目验收，已确认关卡不擅自补发。
- FO-11 只负责奖励登记；后续吞并影响生成的 AS-06 未执行，成功进入休息由下方 FO-12 接线负责。生产默认引用与 TEST_ONLY fixture 均未替换，未新增永久测试。先前前置记录保留历史状态，奖励验收结果见 `终结神谕系统_FO-11_2026-10-08_log.md`。

## FO-12 成功进入休息

- Sandbox 在合法 CB BREAKTHROUGH 的同场正式确认回调中完成普通历史 / 倾向和 FO-11 奖励提交后，通过 Godot `call_deferred()` 在帧尾调用 `_open_rest_after_oracle(run_data, session)`。同步确认和攻击回调先完成，避免其后续显示操作覆盖休息界面。
- 帧尾核对同一 SaveData、同一当前 Session、关卡 ID 与首次确认事实；换周目、重开、换关的旧请求退出。已有打开的 Rest 不重复创建，同场重复确认仍由 FO-09 拒绝。
- 只传递 `level_id`、`result_kind = breakthrough_oracle_complete`、PK 胜利与击破事实给 `RestSession.open_result()`；调用 `RestResultView.show_result(rest_session, run_data, level_catalog, loser_card_catalog)`，成果由 Rest 现有公开 getter 读取。转场没有再次写入历史、倾向、圣典、卡片或吞并。
- 进入 Rest 时停止普通 / 矛盾生成、回拉与攻击，清空旧弹幕、复读等待、候选目标和神谕计时，收起候选显示。当前神谕 Session 绑定清空，首次确认仍由确认状态及 SaveData 保存，Rest 期间战斗输入保持关闭。
- 无正式卡片 / 继承配置时正常显示已存经文及对应空态。原 `pk_win_unbroken` 路线保持不变；两种 Rest 均复用 RS-09 Continue。验收使用显式 TEST_ONLY 注入，生产资源未覆盖；#61 的 `get_normal_speech_pool()` 外部词库读取链保持，第二关正式内容是否就绪以实际配置为准。
