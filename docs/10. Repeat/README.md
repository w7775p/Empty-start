# 10. Repeat 复读系统任务拆分

> **派工入口**：[2026-10-09 当前任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。本系统的已完成旧卡保留作功能实现依据；下方历史讨论章节的旧数值以现行派工入口覆盖。


## 2026-10-09 现行实现核对与任务状态

**现行复读底座：** `RepeatPlan` 已保存原句与结算 Tier；每次普通命中复读数量 T0～T5 分别为 3/6/8/12/15/20；`RepeatDelayQueue` 已有 0.5～3 秒延迟、独立待生成容量，`BarrageArea` 已有独立同屏容量。正式表现采用纯文本、灰色、零文字描边、中央区域随机静止落点、逐渐透明和最低背景层级。已有实际生成统计保持原规则；升档旧队列清理由 CS-18 调用现成 `clear_normal_queue()`。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [RP-14](tasks/RP-14_plain-text-repeat.md) | 现有纯文本兼容回归 | 已有基础 |
| [RP-15](tasks/RP-15_repeat-cap-calibration.md) | 现有复读独立容量实测 | 已有容量 |
| [RP-16](tasks/RP-16_repeat-shrink-per-tier.md) | 复读随机位置静止生成 | 已完成 · 2026-10-11 |
| [RP-17](tasks/RP-17_repeat-speed-per-tier.md) | 复读随寿命渐隐 | 待开发 |
| [RP-18](tasks/RP-18_repeat-infection-spread.md) | 已有原句计划的复读潮表现 | 已有基础 |
| [RP-19](tasks/RP-19_repeat-grey-text.md) | 灰色复读文字 | 待开发 |
| [RP-20](tasks/RP-20_repeat-zero-outline.md) | 零描边复读 | 待开发 |
| [RP-21](tasks/RP-21_repeat-bottom-layer.md) | 复读最低层 | 待开发 |

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


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

- `RepeatPlan` 是可序列化的复读计划 Resource，字段包括原句 ID / 文本、原句内容类别、模板显示文本、普通或矛盾类型、已确定数量、生成档位、寿命和逐条等待偏移；`wait_offsets_seconds` 每项对应一个待复读条目的计划等待时间。
- `RepeatPlan.create_normal_hit_plan(...)` 在普通命中时创建计划，并把原句、内容类别、结算后档位、调用方已解析的复读数量和寿命复制为固定值。neutral 普通话语的复读仍保留 `neutral` 类别。CS-08 已提供 `CombatStage.get_current_repeat_count_per_hit()`；命中结算完成并更新 Tier 后，普通复读计划创建方读取当前档位和数量并传入工厂，由 RepeatPlan 固定保存本次计划值。延迟队列与生成统计仍分别由 `RepeatDelayQueue` 和 `RepeatGenerationStats` 拥有。
- `RepeatPlan.apply_display_template(template)` 将模板中的 `{原句}` 替换为原句文本并保存到 `display_text`；模板缺少标记时发出警告并回退显示原句。`original_line_id` 始终独立保留，供生成弹幕关联原句。正式模板内容仍待策划提供。
- `RepeatDelayConfig` 位于 `data/repeat/repeat_delay_config.tres`，当前等待范围为 0.5～3.0 秒，正式调参可直接改此资源。
- `RepeatDelayQueue.new(maximum_pending_normal_count)` 接收调用方已解析的普通待生成容量；`enqueue_plan(plan)` 只保留剩余容量内的请求并直接丢弃溢出，返回实际接受数量。
- `RepeatDelayQueue.advance(delta_seconds)` 返回到期单条请求；`advance_and_dispatch(delta_seconds, barrage_area)` 对普通与矛盾计划调用 `spawn_repeat_barrage(plan, true)`，使用 BG-42 的中央区域静止随机落点。神降临的冻结历史复读由 `DivineDescentSpread` 使用同一入口和定位选项。弹幕成功出现后，队列将 1 条实际生成数记入自己持有的 `RepeatGenerationStats`；复读屏幕容量暂满时保留到期请求，等容量释放后重试。待生成队列容量独立于 3. BarrageGeneration 的屏幕弹幕容量。来源原句 ID、命中目标、暂停与计划寿命继续由现有记录和弹幕生命周期管理。
- RP-16 已通过 T0/T3/T5 普通计划、T6 矛盾计划和神降临历史复读的 Godot 运行验证；[生成帧截图](evidence/RP16_static_repeat_spawn.png) 与 [0.75 秒后截图](evidence/RP16_static_repeat_after_0.75s.png)展示同一组静止位置。
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
| RP-13 | 复读独立容量、普通文本及随 Tier 的表现变化（需求暂存，未完成） | 待后续正式拆卡 |

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
RP-12 已复用 13 的本场读取链，并提供 19 已有候选入口可消费的已提交普通数量查询。

## RP-10 普通复读历史提交与回滚

- `RepeatGenerationStats.commit_normal_repeat_history(run_data, level_id)` 在 PK 胜利时深拷贝本场 `normal_counts_by_line_id`，按 `StringName` 关卡 ID 保存至真实 `SaveData.committed_normal_repeat_history_by_level`。每个值是 `{StringName 原句 ID: int 实际普通生成数}`；当前周目同关只保存首份，空普通统计也记录一次提交。
- 普通历史与 `contradiction_counts_by_line_id` 完全分开，计划请求数量和未生成请求不入历史。各关独立保存，即使原句 ID 相同也保留各关实际数量，RP-12 后续负责读取方需要的聚合。
- `discard_uncommitted_normal_repeat_history()` 只清本场未提交普通统计；已提交本场统计仍保留供神谕读取，SaveData 中以前关卡快照保持原值。重开继续创建新的 RepeatDelayQueue / RepeatGenerationStats。
- Sandbox 在 `_complete_normal_combat()` 停止普通生成与等待队列后提交普通统计，时点为 PK 满值进入矛盾阶段；击破成功、未击破、神谕确认分支均沿用同一份已提交历史。失败和当前关重开显式调用回滚接口。
- 本场统计由 RepeatDelayQueue 持有，历史由当前周目 SaveData 保存、Repeat 写入；现有 SaveManager 原生 Resource 存读自动包含该导出字段，新周目与缺少该字段的旧存档默认为空。没有把普通复读数写入普通命中历史。
- RP-10 只建立保存与回滚生命周期；RP-12 的只读聚合与消费边界见下节。

## RP-12 正式只读消费边界

- 13 继续通过 `FinalOracleSession.open_after_breakthrough(..., repeat_stats, ...)` 接收本场队列的同一个 `RepeatGenerationStats`。候选排序与超时选择只调用现有 `get_normal_count(original_line_id)` 读取实际普通数；不创建统计副本，矛盾计数不参与。
- 19 的独立复读来源由 `RepeatGenerationStats.get_committed_normal_counts_by_line_id(run_data)` 提供。该静态查询只遍历真实 `SaveData.committed_normal_repeat_history_by_level`，将各关相同原句数量相加，返回 `{StringName 原句 ID: int 实际普通总数}`；空周目或空历史返回 `{}`。
- 返回字典是即时派生结果，修改它不会写回 SaveData，也不影响之后的查询；未提交本场统计与矛盾统计均不读取，重复查询不会增加历史。
- 调用组合：`DivineDescentCandidateFilter.build_history_candidates(run_data.get_committed_normal_hit_history(), RepeatGenerationStats.get_committed_normal_counts_by_line_id(run_data))`。命中历史与复读历史仍为两个来源；Neutral 继续由已有候选过滤入口处理。
- RP-12 不新增自动化测试，不修改 DD-06 / DD-07 规则；终局进入与冻结生命周期继续等待 DD-01，本卡只提供现有候选入口可消费的只读数据。

## 待整理：RP-13 复读展示与容量

历史讨论中的“500～1000 条普通弹幕”和“复读随 Tier 改变速度或大小”的设想已经更新。现行复读在独立同屏容量内，随 Tier 提高使用现有每发生成数量 3/6/8/12/15/20；表现为中央区域随机静止落点、灰字零描边、固定底层并按寿命渐隐。相关单卡为 RP-14～RP-21；升档取消旧普通复读请求由 CS-18 接线。

## 2026-10-09 战斗打磨单功能开发卡

本轮确认的高密度弹幕、四种运动、交叉层级、富文本、舆论潮汐、弹幕群聚、伪纵深、命中冲击波、复读感染、Tier 升降档与沉默爆发，现已拆为单一功能开发卡。每张卡仅定义触发条件、预期行为与验收结果；可调数值以实测和后续策划配置为准。卡片各自当前状态及可派工顺序以顶部现行表和 `docs/开发计划_2026-10-09_任务卡依赖整合.md` 为准。

| 卡号 | 本卡唯一功能 | 状态 |
| --- | --- | --- |
| [RP-14](tasks/RP-14_plain-text-repeat.md) | 复读使用普通纯文本 | 待实施 |
| [RP-15](tasks/RP-15_repeat-cap-calibration.md) | 复读独立同屏上限与容量验收 | 待实施 |
| [RP-16](tasks/RP-16_repeat-shrink-per-tier.md) | 复读随机位置静止生成 | 已完成 · 2026-10-11 |
| [RP-17](tasks/RP-17_repeat-speed-per-tier.md) | 复读按生命周期渐隐 | 待实施 |
| [RP-18](tasks/RP-18_repeat-infection-spread.md) | 有效命中形成同向复读潮 | 待实施 |

关联依赖及实施顺序以各卡的上游功能卡为准；共享场景与组件按实际 Owner 的任务流程依次集成。

## 2026-10-09 新确认规则与单功能任务卡

当前 T0～T5 每次有效普通命中计划的复读数量沿用 3/6/8/12/15/20；复读同屏容量独立且实际数量随玩家命中浮动。复读采用灰色、纯文本、零文字描边，在中央战斗区随机位置静止显示，按自身寿命渐隐并始终在最底层。RP-16～RP-18 的任务内容已根据最新确认规则修订。

| 任务卡 | 唯一功能 | 状态 |
| --- | --- | --- |
| [RP-19](tasks/RP-19_repeat-grey-text.md) | 复读文字使用灰色 | 待实施 |
| [RP-20](tasks/RP-20_repeat-zero-outline.md) | 复读文本描边宽度为零 | 待实施 |
| [RP-21](tasks/RP-21_repeat-bottom-layer.md) | 复读固定最低层级 | 待实施 |

本轮任务卡逐项说明触发条件、应发生的行为与验收结果；派工时依赖最新卡片和系统当前代码。
