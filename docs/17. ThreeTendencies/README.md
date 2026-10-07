# 17. ThreeTendencies 三项倾向系统任务拆分

## 系统目标

三项倾向系统负责记录玩家一路更偏向正统、异端还是荒谬。

它只接收普通话语产生的倾向变化，精确数值保持隐藏。

## 当前数据底座

- `TendencyState` 保存 `orthodox_total`、`heretical_total`、`absurd_total` 三个精确累计值和 `opening_identity_tendency_id` 比较参照。
- `attempt_orthodox_total`、`attempt_heretical_total`、`attempt_absurd_total` 保存当前关尚未提交的普通话语倾向；`record_normal_speech_tendency(tendency_id, tendency_delta)` 按稳定倾向 ID 只增加对应暂存值，不改周目累计值。
- 当前关失败时调用 `rollback_attempt_tendency()` 清空三个本场暂存，不修改此前已提交总值。
- DBG-01 的 `set_attempt_tendencies_for_debug(orthodox, heretical, absurd)` 只设置当前关暂存值并将负数限制为0，调试面板不改动已提交的周目累计。
- 本关 PK 胜利的最终结果形成时调用 `commit_attempt_tendency()`，把三个本场暂存分别加到周目累计并清空暂存；重复结果不会重复累计。12 系统的未击破休息入口与成功后神谕确认事件均已接入。退出 Sandbox 时仍回滚未提交的本场暂存。
- 当前周目通过 `SaveData.tendency_state` 持有此 Resource。
- 身份确认时调用 `initialize_from_identity_option(identity_option)`，从已选 `IdentityOption.tendency_id` 复制开局比较参照，并将累计值与本场暂存都初始化为 0。
- `get_primary_tendency_id()` 返回主导倾向 ID；最高值并列时优先并列项中的 `opening_identity_tendency_id`，否则按正统、异端、荒谬顺序裁决。`is_primary_tied()` 即时计算并列标记。
- `get_secondary_tendency_id()` 从剩余两项选择最高正分项，剩余项并列沿用相同裁决顺序；剩余项都没有正分时返回主导倾向。
- `has_no_effective_behavior()` 在三项值全零时返回 `true`，主导和次要都沿用 `opening_identity_tendency_id`。
- INT-01 Sandbox 已把 HitResolution 整发逐目标结果中的 `tendency_id` / `tendency_delta` 交给 `record_normal_speech_tendency()`；复读和遮挡等结果跳过普通倾向。失败、重开及离开验收场调用 `rollback_attempt_tendency()`，此前周目累计保持原值。PK 满值停在矛盾击破接入点，本场记录尚未跨关提交。精确值继续隐藏，仅由调试和验收测试读取。

本系统需要：

1. 三项累计值从 0 开始；
2. 开局身份数据里配置的对应倾向作为比较参照；
3. 本场 PK 胜利后提交本场倾向；
4. 本场失败重开时撤回本次未提交倾向；
5. 计算主导倾向、次要倾向、并列与全零状态；
6. 向休息时刻提供环境表现结果；
7. 进入神降临时冻结最终倾向；
8. 向神降临和结局提供同一份最终结果。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| TT-01 | 三项倾向运行时状态 | 无 |
| TT-02 | 普通话语累计本场倾向 | 无 |
| TT-03 | PK 胜利提交本场倾向 | 1 个关键单元测试 |
| TT-04 | 失败重开撤回本场倾向 | 1 个关键单元测试 |
| TT-05 | 主导倾向基础判定 | 1 个关键单元测试 |
| TT-06 | 主导倾向并列裁决 | 2 个关键单元测试 |
| TT-07 | 次要倾向判定 | 2 个关键单元测试 |
| TT-08 | 全零状态 | 1 个关键单元测试 |
| TT-09 | 神谕不追加倾向 | 无 |
| TT-10 | 提供休息时刻环境结果 | 无新增自动化测试 |
| TT-11 | 进入神降临时冻结最终倾向 | 1 个关键单元测试 |
| TT-12 | 提供给神降临与结局 | 无新增自动化测试 |

## 测试预算

只保留 9 个纯逻辑 case：

- PK 胜利会把本场倾向提交到累计值；
- 失败重开撤回本场未提交倾向；
- 单一最高值得到主导倾向；
- 主导并列且包含开局身份对应倾向时优先该倾向；
- 主导并列且不含开局身份时按正统→异端→荒谬裁决并保留并列标记；
- 次要倾向取剩余最高正分项；
- 剩余项全为 0 时次要倾向采用主导倾向；
- 三项全为 0 时主导/次要沿用开局身份对应倾向并标记无有效行为；
- 进入神降临后后续输入不能修改冻结的最终倾向。

精确数值显示、环境视觉和跨系统读取都不写额外单元测试。

## 依赖顺序

TT-01 可先做。
TT-02 等 6. HitResolution 的普通话语倾向事件。
TT-03 / TT-04 等本场胜负与 7. OpponentPKBar 重开流程。
TT-05～08 可完成纯判定逻辑。
TT-10 等 18. Rest。
TT-11 / TT-12 等 19. DivineDescent 与 20. Ending。
