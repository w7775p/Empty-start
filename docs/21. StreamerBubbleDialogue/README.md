# 21. StreamerBubbleDialogue 双主播气泡对话系统

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。开发前核对该表、本卡现行版、main 实际实现及最新完成日志。


## 系统目标
在玩家和对手主播立绘周围显示可随事件出现的**椭圆漫画式说话气泡**。气泡底板与朝向主播的尖尾由 Godot 程序绘制，文本按触发顺序逐条上浮。此系统只持有对白事件、待显示队列和气泡生命周期，**命中结算、Tier、输赢、PK 与正式剧情状态由现有系统提供**。

## 系统边界
- **立绘区域**：玩家和对手各有自己的主播画面，气泡出现于对应立绘四周，随当前画面尺寸适配。
- **内容来源**：所有实际命中的非复读话语默认由玩家侧复述原句，包含正收益和确实命中的负收益话语；普通复读命中不生成复述气泡。命中特定原句另触发对手配置台词。整发遮挡落空由 CA-15 的最终命中事实判断。
- **对手触发**：①指定话语实际命中；②连线、输赢、升降 Tier 等既有状态事件；③本场战斗进行中的时间节点。
- **多条顺序**：玩家和对手各自最多约 3 条（默认上限 3，可配）同时上浮，按到达顺序呈现；较旧的即时气泡在满额时可以提前退场。
- **显示优先级**：关键剧情（连线、Tier、输赢及指定原句对白）最高、普通实际命中次之、定时闲聊最低；关键剧情每句需要完整呈现，定时闲聊等待空闲。
- **已有系统复用**：CS-22/T1 开场对白、CS-27/Tier 降档嘲讽由对应阶段事件调用本系统；对手登场、离线与战斗回拉逻辑仍属于 08 系统。
- **程序美术**：SD-02 以 `_draw()` / `StyleBox` 实现椭圆底板、可左右翻转的尖尾和深色轮廓，`RichTextLabel` 排版内容，Tween 控制短弹、上浮和淡出；沿用现有 Theme 字体和可调视觉参数。

## 单功能任务
| 卡号 | 功能 | 前置 |
| --- | --- | --- |
| [SD-01](tasks/SD-01_bubble-dialogue-config.md) | 双主播气泡对白的数据配置 | 现有 LevelProfile、SandboxBattleHud |
| [SD-02](tasks/SD-02_portrait-side-bubble-view.md) | 在双主播立绘四周绘制上浮气泡 | SD-01、现有 SandboxBattleHud、PA-03 |
| [SD-03](tasks/SD-03_ordered-bubble-events.md) | 按事件到达顺序管理上浮气泡 | SD-02、现有 CS-23 |
| [SD-04](tasks/SD-04_actual-hit-echo.md) | 将实际击中的话语映射为主播气泡 | SD-01～SD-03、CA-14、CA-15、Sandbox 命中回调 |
| [SD-05](tasks/SD-05_specific-sentence-reply.md) | 击中特定话语触发对手预设对白 | SD-01、SD-03、SD-04 |
| [SD-06](tasks/SD-06_combat-state-dialogue-event.md) | 根据连线、Tier、输赢状态播放配置对白 | SD-01、SD-03；CS-22、CS-27 提供状态事件 |
| [SD-07](tasks/SD-07_timed-opponent-dialogue.md) | 战斗进行时按时间触发对手对白 | SD-01、SD-03、Sandbox 战斗状态 |
| [SD-08](tasks/SD-08_per-streamer-dialogue-table-binding.md) | 按当前关剧情配置ID筛选20表并载入SD-01 | SD-01、LC-10；供SD-04～07读取 |

## 当前已确认与后续输入
- 已确认：非复读的实际命中由玩家侧复述，复读命中不复述；对手有特定原句答话、状态对白及定时闲聊；普通气泡允许同侧约 3 条同时上浮；剧情优先且完整，定时对白最低优先。
- 后续策划提供：正式对白、实际展示时长、关键原句映射、定时对白时间点。
- 气泡本体由程序绘制，可后续替换 Theme 正式字体；目前无须独立绘制气泡 PNG。
- T0 离线清理对手当前气泡，继续使用 CS-26 的既有离线事实。

## 派工建议
先做 SD-01～03 的可复用显示能力；SD-04、05、06、07 作为互不重写 HUD 的事件消费者分别接线。阶段系已有卡片继续负责自己的触发条件，保持事件流单向。

## SD-01 当前实现（2026-10-10）

SD-01 数据配置已完成。代码和空的正式配置位于 `data/streamer_bubble_dialogue/`，完成记录见 [SD-01 日志](双主播气泡对话系统_SD-01_2026-10-10_log.md)。

- `BubbleDialogueEntry` 是可在 Inspector 编辑的 Resource：`side` 使用 `SpeakerSide.PLAYER / OPPONENT`，`text` 为显示文本，`original_sentence_id` 沿用 `LevelSpeech` 的 String 原句 ID（可空），`event_id` 为 StringName 事件 ID，`display_duration_seconds` 为停留秒数，`priority` 为可编辑优先级。
- `Priority.PLOT=2 > HIT=1 > TIMED_IDLE=0`；指定原句答话由策划填写对手侧和剧情优先级。条目初值为玩家侧、命中优先级、3 秒，正式时长仍待试玩确认。
- `BubbleDialogueConfig.entries` 保存本场条目。`find_by_sentence(id, side=ANY_SIDE)` 按原句读取；`find_by_event(event_id, side=ANY_SIDE, original_sentence_id="")` 是事件请求的读取入口，空原句参数表示该事件的全部原句。结果保持配置顺序，允许同事件多句；空或未知查询 ID 返回空数组。读取返回共享的静态条目引用，消费者保持只读。
- `create_hit_echo(original_sentence_id, original_sentence_text, is_valid_hit, is_repeat)` 从调用方提供的最终事实构造独立条目：有效的非复读命中映射到玩家侧，事件为 `actual_hit`，优先级为 HIT，文本完整保留原句；落空、复读及空白文本返回 null。时长读取当前 `hit_display_duration_seconds`。接口没有收益筛选，因此同样适用于有效负收益话语；它本身不判定命中。
- `bubble_dialogue_config.tres` 当前无正式对白；策划可新增同类型配置，在 `entries` 中添加条目。后续组合方持有本场配置引用，按事件调用读取接口；本卡未向 `LevelProfile`、Sandbox 或 HUD 增加字段和接线。
- 本卡只保存配置和生成请求数据。队列、显示上限、优先级调度、气泡 UI、实际命中接线与定时触发留给后续卡，不保存 PK、Tier 或命中历史。

Windows 验证命令（Godot 4.7.2）：

```powershell
& ./tests/streamer_bubble_dialogue/run_windows.ps1 -GodotExe '<Godot 4.7.2 Windows exe>'
```

脚本将本模块复制到工作树 `.godot/sd01/harness` 的临时纯数据工程，避免无关 Autoload；执行三个脚本的 `--headless --check-only --script` 与 Resource 读写和查询 smoke。测试文本仅在 `tests/streamer_bubble_dialogue/` 的测试进程内创建；正式数据保持空。已验证 Windows headless，PC GUI、正式场景集成及 Android 硬件均未验证。

## 2026-10-10 当前主播对白接线

Google Sheets `02_主播关卡.story_config_id` 指向 `20_主播气泡对白.story_config_id`；两个表的 `streamer_id` 同时用于对手身份校验。四关预留 `story_level_001`～`story_level_004`，正式对白尚待策划填写。20表保留 `trigger_type`（`hit_word / connect / tier_up / tier_down / win / lose / timed`）、`trigger_key`、`source_word_id`、`trigger_time_s`、发言方、显示时长与优先级，并新增 `line_order` 让相同事件触发的多条剧情对白明确播放顺序。SD-01已完成配置和查询入口；新增 [SD-08](tasks/SD-08_per-streamer-dialogue-table-binding.md) 按当前关剧情配置ID把20表转换为既有 `BubbleDialogueConfig`，由SD-03～07消费事件。

## SD-02 当前实现（2026-10-10）

玩家、对手立绘区各挂一份 `StreamerBubbleStack`；[SandboxBattleHud](../../scenes/sandbox/sandbox_battle_hud.gd) 公开 `show_dialogue_bubble(entry: BubbleDialogueEntry)`，按 `entry.side` 转发 SD-01 条目。浮层仅渲染传入条目，不选择对白或处理战斗事件；同侧按调用顺序由上到下同时显示，气泡到期后回收并重排。

- [StreamerBubbleStack](../../ui/streamer_bubble_dialogue/streamer_bubble_stack.gd) 使用全锚点贴合当前 `448×432` 立绘区，窗口缩放继续沿用 HUD 的整体设计缩放；浮层忽略鼠标并裁切到主播画面。
- [StreamerBubbleView](../../ui/streamer_bubble_dialogue/streamer_bubble_view.gd) 使用 `_draw()` 绘制椭圆填色、深色描边、阴影和尾巴；玩家尾巴向右、对手尾巴向左，均指向画面内的主播。每侧的颜色、描边、尾巴位置/宽度、最大气泡宽度、文字边距、弹出/上浮/渐隐时长可在对应浮层 Inspector 单独调整。
- 文字沿用项目 Theme 的字体，由 `RichTextLabel` 自动换行。文本宽度按字体测量后限制在可调宽度内，气泡高度按测量行数增加。
- HUD 重开尝试时显式清空两侧显示。显示时长读取 `BubbleDialogueEntry.display_duration_seconds`；当前正式对白仍为空，未写入临时验收台词。
- 可见 GUI 回归入口为 [SD-02 smoke 场景](../../tests/streamer_bubble_dialogue/sd02_bubble_view_smoke.tscn)，将实际 `Sandbox` 场景嵌入测试窗，通过公开 HUD 接口在内存中注入左右各三条 TEST_ONLY 条目，并将 Godot Viewport PNG 暂存到 `.godot/sd02/`。已提交的 1920 窗口与 1280 小窗口截图见 [SD-02 视觉证据](evidence/SD-02_2026-10-10/)。窗口/Viewport 尺寸、渲染器、实际台词、命令和测试边界见 [SD-02 完成日志](双主播气泡对话系统_SD-02_2026-10-10_log.md)。

本卡没有实现 SD-03 队列策略、优先级调度、命中/状态/定时事件消费者或随机闲聊。PA-03 当前样例没有对手立绘资源，验收画面保留现有对手占位区域。

## SD-02 气泡美术优化（2026-10-10，PR #131）

依照策划反馈，在原 SD-02 分支更新为更饱满的乳白色漫画圆角椭圆气泡，并为当前发言提供向主播方向上扬的尖尾。仍由 `StreamerBubbleView._draw()` 程序绘制，继续使用 Theme + RichTextLabel，可直接通过 Inspector 调整两侧底色、字体/边距、最大宽度和持续时间；无需独立气泡 PNG。

显示层级按调用顺序保留：**最新一条完整气泡、前两条收缩为实底紧凑历史气泡**，历史气泡去掉尾巴并缩小文字与轮廓，完整文字继续可读。固定的 `448×432` 立绘画面中从下向上沿外边缘排布，减少遮住主播眼睛和表情的时间；弹出 0.14s、缓浮 18px、渐隐 0.24s。SD-03 后续仍负责真正的队列最大数量、优先级和节奏。

已修复 Godot `Control.custom_minimum_size` 导致历史长气泡无法缩小、面积虚高的缺陷；`sd02_bubble_view_smoke.gd` 新增实际尺寸回归。**1280×720 和 1920 宽 Windows Godot GUI 各 21 项 PASS / 0 failures**，新版实景截图见 [视觉优化证据](evidence/SD-02_2026-10-10-v2/)；与原版 [旧截图](evidence/SD-02_2026-10-10/) 可直接对比。仍待策划正式审美验收、对手立绘与 Android 真机。
