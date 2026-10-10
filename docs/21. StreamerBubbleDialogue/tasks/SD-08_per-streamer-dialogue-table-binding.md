# SD-08 根据关卡剧情配置载入事件气泡对白

**状态：新需求已确认 · 待开发**
**类型：数据配置与主播对白**
**关联：SD-01、SD-03～SD-07、LC-10、02_主播关卡、20_主播气泡对白**

## 开始前阅读
- `AGENTS.md`、`project.godot`、当前21系统README和SD-01完成日志
- `data/streamer_bubble_dialogue/bubble_dialogue_config.gd`、`bubble_dialogue_entry.gd`
- `data/level_configuration/level_profile.gd` 及当前关卡读取入口
- Google Sheets `02_主播关卡`、`20_主播气泡对白` 的当前表头及正式策划记录

## 已实现的功能
- SD-01已经提供 `BubbleDialogueEntry`、`BubbleDialogueConfig`、`find_by_sentence()`、`find_by_event()` 与玩家命中复述入口。
- 02表已确定四关的 `story_config_id`：`story_level_001`～`story_level_004`。
- 20表已有发言方、主播ID、事件类型/触发键、原句ID、对白正文、优先级、时长、定时节点和启用状态；新增 `story_config_id` 与 `line_order`。
- SD-03负责请求队列与关键剧情逐句完整播放；SD-05、SD-06、SD-07分别消费命中原句、战斗状态事件和定时事件。

## 本次任务
1. 读取当前 `LevelProfile` 对应的02.`story_config_id` 与02.`streamer_id`，筛选20表中 `story_config_id` 匹配、`enabled` 为真的本场对白；同时核对20.`streamer_id` 的主播归属，保证当前关只读取本场剧情。
2. 将20.`speaker_side`、`text`、`source_word_id`、`priority`、`display_duration_s` 对应到已有 `BubbleDialogueEntry`；将 `trigger_type + trigger_key` 映射为稳定的SD-01 `event_id`，同时为SD-07提供 `trigger_time_s`。
3. 同一剧情配置、同一触发事件下，按正整数 `line_order` 升序组织连续对白，将剧情对白交给SD-03顺序播放；同一事件的多句对白在关键剧情完成时发出既有队列完成通知。
4. 把事件映射分配给既有入口：`hit_word` 对应实际命中指定 `source_word_id`（SD-05）；`connect`、`tier_up`、`tier_down`、`win`、`lose` 对应真实战斗状态事件（SD-06）；`timed` 对应本场可暂停的战斗时间（SD-07）。
5. 当前关开播、重开、进入下一关时按新的 `story_config_id` 读取本场对白；与现有 `LevelProfile`、Sandbox和SD-01资源接口协调，使用同一静态配置供SD-03～07消费。

## 验收
- 四关读取对应剧情配置ID；有条目的关卡按本场ID和主播筛选，未填写正式对白的关卡可进入正常战斗。
- `connect` 的多条对白按 `line_order` 播放；SD-03确认完整播毕后，CS-23接到现有完成通知。
- `hit_word` 由真实命中事实触发；升降Tier、胜负与定时事件均可匹配20表配置；优先级遵循SD-03既有规则。
- 重开与切关重新选择剧情配置；不同关卡的同名事件读取各自台词。
- Godot 4.7.2下完成导表、Resource载入与实际事件验收。

## Godot开发环境
- 引擎：Godot 4.7.2；脚本：GDScript
- 目标平台：PC / Android
- 工程操作：Godot-MCP-Native；官方文档：godot_mcp

## 完成记录
提交SD-08日期日志，记录表字段映射、事件ID映射、顺序对白和本场切换的实际验收结果。
