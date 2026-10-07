# 16. LoserCard 败者卡系统任务拆分

## 系统目标

败者卡系统负责记录本周目真正击败过哪些主播。

只有“矛盾击破成功 + 终结神谕确认完成”后才发卡。只赢下 PK 不发新卡。

## 当前数据底座

- `LoserCardProfile` Resource 以稳定 `streamer_id` 标识主播，提供 `streamer_name`、`card_art` 和 `card_text` 展示入口。
- `LoserCardCatalog` 保存资料列表，并通过 `find_profile(streamer_id)` 查找卡片。
- 当前目录中的 `data/loser_card/loser_card_catalog.tres` 是空资料库；正式主播 ID、卡面素材和文案尚未提供。
- `LoserCardData` Resource 保存周目获卡主播 ID 和已发卡关卡 ID；`grant_on_true_defeat(level_id, streamer_id, contradiction_broken, oracle_confirmed, catalog)` 同时要求 CB 击破成功和同关 FinalOracle 正式确认，并通过 Catalog 查到对应资料。同场重复不发，资料缺失不合成卡片。
- 同一个 `LoserCardData` 周目 Resource 内，以 `acquired_streamer_ids` 对主播去重：同场重报和同主播跨关重报均返回 false，保留首张卡。
- `pk_win_unbroken` 分支的 `contradiction_broken=false` 不满足发卡入口；PK 胜利不会替代击破或神谕确认，已有卡片及提交记录保持原值。
- 当前只有纯数据奖励入口；周目存档纳入与休息展示由后续任务卡完成。调用方需核对真实结果的当前周目与 level_id。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| LCARD-01 | 卡片资料数据 | 无 |
| LCARD-02 | 真正击败后发卡 | 2 个关键单元测试 |
| LCARD-03 | 同主播本周目只发一次 | 1 个关键单元测试 |
| LCARD-04 | 未击破分支不发卡 | 1 个关键单元测试 |
| LCARD-05 | 本周目保存已获卡片 | 无 |
| LCARD-06 | 新周目清空卡片 | 1 个关键单元测试 |
| LCARD-07 | 提供给休息时刻 | 无新增自动化测试 |

## 测试预算

只保留 5 个纯逻辑 case：

- 真正击败后可以获得对应卡片；
- 非真正击败结果不满足发卡条件；
- 同主播重复发卡只保留一张；
- 未击破 PK 胜利不新增卡片；
- 新周目开始后卡片记录清空。

## 依赖顺序

LCARD-01 可先做。
LCARD-02～04 等 13. FinalOracle / 12. ContradictionBreak 的真实结果。
LCARD-05 接现有 SaveData。
LCARD-06 接新周目流程。
LCARD-07 等 18. Rest。
