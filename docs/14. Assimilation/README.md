# 14. Assimilation 吞并系统任务拆分

## 系统目标

吞并系统负责保存“真正击败对手以后，玩家从对方那里带走了什么”。

它保存两类长期成果：

- 可继承词库与出现权重；
- 可继承弹幕特性。

同时区分“关卡通关”和“真正击败”，并把已获得内容提供给后续关卡、休息时刻和神降临。

## 当前数据底座

- `AssimilationData` 是吞并系统的数据 Resource，由当前周目的 `SaveData.assimilation_data` 持有。
- `completed_streamer_ids` 与 `defeated_streamer_ids` 分别保存已通关主播 ID 和真正击败主播 ID。
- `inherited_word_weights` 以稳定词库 ID 为键、出现权重为值；`inherited_trait_ids` 保存可继承特性 ID。
- `defeated_level_ids` 保存当前周目已经提交真正击败结果的稳定关卡 ID；与主播集合共同阻止同场重复提交和同主播重复奖励。
- `register_defeated_streamer(level_id, streamer_id, contradiction_broken, oracle_confirmed)` 只在两项事实同时成立时登记，首次返回 `true`，重复返回 `false`。击破事实来自 CB 的 `Outcome.BREAKTHROUGH`，确认事实来自同周目同关的 `confirmation_committed` 或 `get_confirmed_selection(level_id)`。
- `register_inherited_word_pool(level_id, pool_id, appearance_weight, can_inherit, is_contradiction_pool)` 只允许已登记真正击败关卡的可继承普通词库；稳定 pool_id 只保存首次权重，矛盾专属池和禁止继承的池被排除。
- `register_inherited_trait(level_id, trait_id, can_inherit)` 只登记已真正击败关卡允许继承的特性，跨主播来源的同一稳定 trait_id 只保留一次；实际特性装配与兼容仍归 4. BarrageTraits。
- 当前 `LevelProfile` 尚无稳定 pool_id、继承权重及允许继承标记；以上 API 接收配置方显式提供的值，配置与实际生成接线留 AS-06 / FO-11。`special_trait_ids` 表示本关所用特性，不能直接当作继承白名单。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| AS-01 | 吞并成果数据 | 无 |
| AS-02 | 真正击败后登记主播结果 | 2 个关键单元测试 |
| AS-03 | 登记可继承词库与权重 | 2 个关键单元测试 |
| AS-04 | 登记可继承特性并去重 | 2 个关键单元测试 |
| AS-05 | 区分通关与真正击败 | 1 个关键单元测试 |
| AS-06 | 提供给后续关卡 | 无新增自动化测试 |
| AS-07 | 当前关失败时保留既有吞并成果 | 无新增自动化测试 |
| AS-08 | 提供给休息时刻 | 无新增自动化测试 |
| AS-09 | 提供给神降临 | 无新增自动化测试 |

## 测试预算

只保留 7 个纯逻辑 case：

- 同一主播第一次真正击败可以登记；
- 同一主播重复登记不会重复；
- 新词库可以登记；
- 同一词库重复登记不会重复；
- 新特性可以登记；
- 同一特性重复登记不会重复；
- 只有通关、没有真正击败时，不产生真正击败型吞并成果。

词库实际生成、特性实际装配、休息展示和终局读取全部做跨系统联调。

## 依赖顺序

AS-01 可先做。
AS-02～05 等 13. FinalOracle 的真正击败结果。
AS-06 等 2. LevelConfiguration / 4. BarrageTraits。
AS-07 等 7. OpponentPKBar。
AS-08 等 18. Rest。
AS-09 等 19. DivineDescent。
