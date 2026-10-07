# 10. Repeat 复读系统任务拆分

## 系统目标

复读系统负责把“某句话被打中以后，大家跟着重复”变成可执行的数据和生成请求。

它负责：

1. 接收普通话语和矛盾命中记录；
2. 根据数值配置决定复读数量；
3. 普通复读在 0.5～3 秒内陆续出现；
4. 普通复读使用该发结算后的档位，并在等待期间保持已确定数量；
5. 保留原句标识并套用复读模板；
6. 记录普通复读和矛盾复读的实际生成统计；
7. 在 PK 胜利后提交普通复读历史，失败重开时撤回；
8. 给终结神谕和神降临提供统计。

复读实例真正出现在屏幕上仍由【3. BarrageGeneration】完成。

## 当前数据底座

- `RepeatPlan` 是可序列化的复读计划 Resource，字段包括原句 ID / 文本、模板显示文本、普通或矛盾类型、已确定数量、生成档位、寿命和逐条等待偏移；`wait_offsets_seconds` 每项对应一个待复读条目的计划等待时间。
- `RepeatPlan.create_normal_hit_plan(...)` 在普通命中时创建计划，并把原句、结算后档位、调用方已解析的复读数量和寿命复制为固定值。CS-08 已提供 `CombatStage.get_current_repeat_count_per_hit()`；命中结算完成并更新 Tier 后，普通复读计划创建方读取当前档位和数量并传入工厂，由 RepeatPlan 固定保存本次计划值。延迟队列与生成统计仍分别由 `RepeatDelayQueue` 和 `RepeatGenerationStats` 拥有。
- `RepeatPlan.apply_display_template(template)` 将模板中的 `{原句}` 替换为原句文本并保存到 `display_text`；模板缺少标记时发出警告并回退显示原句。`original_line_id` 始终独立保留，供生成弹幕关联原句。正式模板内容仍待策划提供。
- `RepeatDelayConfig` 位于 `data/repeat/repeat_delay_config.tres`，当前等待范围为 0.5～3.0 秒，正式调参可直接改此资源。
- `RepeatDelayQueue.new(maximum_pending_normal_count)` 接收调用方已解析的普通待生成容量；`enqueue_plan(plan)` 只保留剩余容量内的请求并直接丢弃溢出，返回实际接受数量。
- `RepeatDelayQueue.advance(delta_seconds)` 返回到期单条请求；`advance_and_dispatch(delta_seconds, barrage_area)` 则直接调用 3. BarrageGeneration 的 `spawn_repeat_barrage(plan)`。弹幕成功出现后，队列将 1 条实际生成数记入自己持有的 `RepeatGenerationStats`；复读屏幕容量暂满时保留到期请求，等容量释放后重试。待生成队列容量独立于 3. BarrageGeneration 的屏幕弹幕容量。
- Sandbox / 战斗场景组合方每帧调用 `advance_and_dispatch(delta, barrage_area)`；复读系统只发起实例请求，弹幕实例、寿命与屏幕容量仍由 BarrageGeneration 拥有。
- `RepeatDelayQueue.clear_normal_queue()` 丢弃所有尚未到期的普通复读；进入矛盾阶段时由阶段流程调用，已返回生成请求的弹幕不属于此等待队列。
- 原计划的 `wait_offsets_seconds` 保存每条复读的相对等待时间；队列不创建或管理屏幕上的弹幕实例。
- `RepeatGenerationStats.record_generated(plan, actual_generated_count)` 仅根据计划类型把弹幕生成系统确认的实际生成数量按 `original_line_id` 累计；`get_normal_count(id)` 与 `get_contradiction_count(id)` 分别读取两类统计。
- INT-01 Sandbox 在攻击整发提交后读取结算后 Tier 和复读数量，创建普通复读计划并逐帧调度。成功复读进入场上，可被真实攻击选中；命中沿用 HitResolution 的有效零收益结果，不创建后续复读或普通命中历史。失败 / 满值清理普通等待队列，重开创建新的队列和实际生成统计。RP-08 已在隔离分支补齐矛盾复读计划、调度和显示状态读取；CB-08 负责命中后调用。

矛盾计划由 `RepeatPlan.create_contradiction_hit_plan()` 固定原句、类型、数量和寿命；`RepeatDelayQueue.enqueue_plan()` 接收两类计划，普通待生成上限只约束普通类型。`get_pending_contradiction_count()` 与 `BarrageArea.has_visible_contradiction_repeats()` 供击破成功后的展示完成判定，实际生成后统计仍由 `RepeatGenerationStats` 分类记录。当前 Sandbox 的矛盾复读数量按原始系统案暂配 120 条/命中，寿命暂配 6 秒；正式数值表到位后替换资源来源。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| RP-01 | 复读生成计划数据 | 无 |
| RP-02 | 普通命中生成复读计划 | 2 个关键单元测试 |
| RP-03 | 复读模板保留原句标识 | 无 |
| RP-04 | 普通复读延迟队列 | 无 |
| RP-05 | 普通复读上限溢出丢弃 | 2 个关键单元测试 |
| RP-06 | 请求弹幕生成系统显示复读 | 无新增自动化测试 |
| RP-07 | 复读命中规则接线 | 无新增自动化测试 |
| RP-08 | 矛盾命中生成复读 | 无新增自动化测试 |
| RP-09 | 普通 / 矛盾复读统计分开 | 2 个关键单元测试 |
| RP-10 | PK 胜利提交与失败回滚普通历史 | 2 个关键单元测试 |
| RP-11 | 进入矛盾阶段清空旧普通复读队列 | 无 |
| RP-12 | 给神谕 / 神降临提供复读统计 | 无新增自动化测试 |

## 测试预算

只保留 8 个纯逻辑 case：

- 普通命中创建计划时会固定生成数量；
- 普通命中创建计划时会固定结算后档位；
- 普通复读到达上限时溢出部分被丢弃；
- 有容量时请求可以正常保留；
- 普通复读统计只增加普通计数；
- 矛盾复读统计只增加矛盾计数；
- PK 胜利提交普通历史；
- 失败重开撤回本次未提交普通历史。

延迟计时、模板显示、生成实例、阶段衔接和跨系统统计读取都用最小运行联调。

## 依赖顺序

RP-01～05、RP-09～11 可以先做核心逻辑。
RP-06 等 3. BarrageGeneration 复读入口。
RP-07 等 6. HitResolution。
RP-08 等 12. ContradictionBreak。
RP-10 等 7. OpponentPKBar / 本场结果提交。
RP-12 等 13. FinalOracle 与 19. DivineDescent。
