# SD-08 本场主播对白表的载入与查询绑定

**状态：新需求 · 待开发**
**类型：数据配置与主播对白**
**关联：SD-01、SD-03～SD-07、LC-10、20_主播气泡对白**

## 开始前阅读
- `AGENTS.md`、`project.godot`
- `docs/21. StreamerBubbleDialogue/README.md`、SD-01完成日志
- `data/streamer_bubble_dialogue/bubble_dialogue_config.gd` 与 `bubble_dialogue_entry.gd`
- `LevelProfile.streamer_id` 和 Google Sheets `20_主播气泡对白` 最新字段

## 已实现的基础
- SD-01 已提供 `BubbleDialogueEntry`、`BubbleDialogueConfig` 及按原句/事件查询入口。
- 20表已有 `streamer_id`、发言方、触发类别/键、关联原句、正文、优先级、停留秒数、定时节点和启用状态。

## 本次任务
根据当前 `LevelProfile.streamer_id` 从20表筛选本场对手的启用对白，将表中发言方、正文、`source_word_id`、触发事件、优先级、`display_duration_s` 映射到现有SD-01配置与查询入口，并提供 `trigger_time_s` 供SD-07读取。

本场开始、切关及重开时加载正确主播的对白资源，供SD-03队列及SD-04/05/06/07事件消费。匹配所用的 `streamer_id` 与02关卡、04矛盾及21反击技能的稳定ID相同。

## 验收
- `kiwi` 的对白仅匹配Kiwi当前关，`alien`、`fox` 各自读取匹配记录，未提供正式台词时返回空条目集合。
- 原句命中与事件对白使用SD-01既有查询语义；定时节点可被SD-07读取。
- 重开/切关后当前配置准确刷新，运行中能从正确的主播配置发起对白请求。

## 完成记录
记录导表映射、当前场次筛选与Godot实测结果，新增SD-08日期日志。
