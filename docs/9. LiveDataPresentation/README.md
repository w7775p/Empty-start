# 9. LiveDataPresentation 直播数据表现系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。已实现的基础卡用于接口复查；新的视觉、静止弹幕、对话与阶段打磨以最新单卡和此表为准。

## 系统目标

直播数据表现系统只负责把直播间表现做得像“真的在涨热度”。

它保存并显示四项数据：

- 观看人数；
- 点赞数；
- 评论数；
- 粉丝数。

这些数据由战斗事件驱动，但不参与 PK、三项倾向和关卡解锁。

## 当前数据底座

- `LiveSessionData` 是直播数据系统唯一持有的四项数据 Resource，字段为 `viewer_count`、`like_count`、`comment_count` 和 `fan_count`。
- 当前周目通过 `SaveData.live_session` 持有该 Resource；跨场景和存档读写沿用现有 `SaveManager`。
- `LiveSessionData.initialize_session(initial_fan_count)` 清空本场观看、点赞、评论，并设置本周目当前粉丝数；新周目默认粉丝数为 0，正式起始粉丝值待策划配置。
- `LiveSessionData.record_generated_comments(actual_generated_count)` 只累计弹幕系统确认成功生成的实例数量。INT-01 Sandbox 统一监听 `BarrageArea.barrage_generated(view)`，普通与复读每个成功实例传 1；队列返回数量不再重复计评论。
- LD-02 通过 `set_opening_viewers(multiplier)` 以本次开播单次抽取的倍率计算并保存 `viewer_count`；计算将结果截为非负整数。倍率范围待策划提供；此入口接收抽取后的倍率，不负责随机抽取。
- LD-06 的 `start_short_boost(event, viewer_gain, like_gain, duration_seconds) -> bool` 接收 `BoostEvent.CONTRADICTION_BREAK` 或 `ORACLE_CONFIRMATION`，两种事件在本次开播各接收一次。总增量与时长在触发时固定；负增量、非正时长或全零增量不启动表现。`advance_short_boosts(delta)` 按实际游戏帧时间逐步补齐整数观看 / 点赞增量，到期停止增长并保留累计值；两段重叠时各自只贡献一次配置总量。
- Sandbox 只在 `outcome_locked(BREAKTHROUGH)` 成功分支和校验同场身份后的 `confirmation_committed` 分支触发上述接口，`_process(delta)` 负责推进；未击破、神谕仅开放或重复请求均不会额外触发。SceneTree 暂停冻结推进；`initialize_session()` 清除旧上涨与触发记录。计时 / 触发记录不存档，不修改 PK、倾向、评论或粉丝。
- LD-06 复用 `SandboxBattleConfig` 的 `break_boost_viewer_gain`、`break_boost_like_gain`、`break_boost_duration_seconds` 和对应的 `oracle_boost_*` 三项配置。增量为本次上涨总量，时长单位为秒；正式策划值待交付，六项缺省均为 0，当前正式配置保持关闭。HUD 继续通过 `Resource.changed` 展示逐步上涨，无新增布局、文案或动画资源。
- LD-07 的 `LiveSessionData.commit_pk_win_fans(level_id, fan_gain) -> bool` 由正式 PK 胜利入口提交配置增量；首次提交返回 `true`，同关重复提交返回 `false`。空关卡 ID 或负增量拒绝提交。`settled_fan_level_ids` 与粉丝数一起随 `SaveData.live_session` 保存，新周目独立初始化；开播初始化保留去重记录。
- Sandbox 在 `HitResolution` 最终 PK 达到满值、进入矛盾阶段前结算粉丝，矛盾未击破仍保留收益。胜利后同步重开粉丝基数，重复重开或读档进入同关不会回退已入账收益或再次增加。`SandboxBattleConfig.pk_win_fan_gain` 复用现有运行配置，正式策划增量待交付，缺省 0；零增量也视为本关已提交，验证中的正数只注入临时运行实例。
- LD-09 / INT-03 的 `LiveDataHud` 用四个独立 RichTextLabel 显示四项数值；LiveSessionData 计数属性变化时发出 `Resource.changed`，HUD 随信号刷新。
- `LiveDataHud.bind_live_session(session)` 为场景组合方提供显式绑定入口：初始化或替换 SaveData 后传入当前 `LiveSessionData`，HUD 断开旧 Resource 的订阅、连接当前 Resource 并立即刷新四项数值；传入 `null` 时显示 0。Sandbox 在创建运行时 SaveData 后调用此入口，避免直接运行场景时 Autoload 初始化顺序使 HUD 留在早期空数据上。
- 当前 `SceneRouter.goto_game()` 指向可玩 Sandbox，左主播区复用 `ui/live_data/live_data_hud.tscn`。开局及原地重开通过 `initialize_session()` 清空本场数据并保留入关粉丝数；Viewer / Like 的事件增量仍等待策划规则。
- INT-02 将左右下部设为 `448×520`；INT-03 复用同一HUD场景。左边为ICON→数字左对齐，右边为数字→ICON右对齐。旧 Panel / CardPanel、2×2排版和字段标题已移除；四个控件为 `Metrics/ViewerMetric`、`LikeMetric`、`CommentMetric`、`FanMetric`。
- `display_side` 仅控制图标顺序与对齐；独立的 `auto_bind_player_session` 决定运行时是否默认绑定玩家数据。Sandbox右实例关闭自动绑定，通过 `set_values(0,0,0,0)` 提供明确的零值占位；未来可显式 `bind_live_session()` 注入真实敌方数据源。
- `set_values(viewer_count,like_count,comment_count,fan_count)` 保留四项原始整数作为最近展示输入，再格式化富文本；该缓存只供重新排版，业务数值仍由 `LiveSessionData` 或调用方持有。入树前的显式输入可在就绪后展示。当前ICON为可配置的👤/👍/🔊/👥字符串，可换成BBCode图像；单项视觉更新集中在 `_render_metric()`，尚未加入数值动画。
- 未绑定数据源时，运行期改方向或ICON沿用最近展示输入，避免从缩写文字反解析整数；绑定时重新读取当前 Resource。显式 `bind_live_session(null)` 仍清成四项0。
- HUD的 `@tool` 分支只渲染编辑器预览和对齐，跳过SaveManager访问。四项支持BBCode、单行、禁滚动、忽略鼠标，保留实际战斗输入。
- 这些值只供表现和展示读取，不作为 PK、倾向或关卡解锁输入。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| LD-01 | 本场直播四项数据状态 | 无 |
| LD-02 | 开播观看人数计算 | 2 个关键单元测试 |
| LD-03 | 命中事件改变观看与点赞 | 无 |
| LD-04 | 档位变化影响直播热度 | 无 |
| LD-05 | 弹幕 / 复读生成增加评论 | 无 |
| LD-06 | 矛盾击破 / 神谕触发短时上涨 | 无 |
| LD-07 | PK 胜利只结算一次新增粉丝 | 2 个关键单元测试 |
| LD-08 | 本关重开重置本场数据 | 2 个关键单元测试 |
| LD-09 | 直播数据 UI 显示 | 无 |
| LD-10 | 休息时刻展示本场结果 | 无新增自动化测试 |
| [LD-11](tasks/LD-11_live-data-k-number-abbreviation.md) | 直播数据数字从 1000 起显示 k 缩写 | Godot HUD 显示与刷新验收 |

## 测试预算

只保留 6 个纯逻辑 case：

- 开播人数按粉丝数与倍率计算；
- 开播人数不会小于 0；
- 同一场 PK 胜利第一次可以结算粉丝；
- 同一场重复提交不会再次增加粉丝；
- 重开后观看 / 点赞 / 评论回到本场初始状态；
- 重开后开局粉丝数保持不变。

事件增量、UI、动画、数字跳动和跨系统广播全部用最小运行联调。

## 依赖顺序

LD-01～02 可以先完成。
LD-03 等 6. HitResolution。
LD-04 等 8. CombatStage。
LD-05 等 3. BarrageGeneration 与 10. Repeat。
LD-06 已接入 12 / 13 的正式击破成功与神谕确认事件；上涨幅度和时长待策划配置。
LD-07 已接入 Sandbox 的正式 PK 胜利入口；正式粉丝增量待策划配置。
LD-08 等 7. OpponentPKBar 重开流程。
LD-10 等 18. Rest。

## LD-10：休息页面只读本场直播结果

`LiveSessionData.commit_pk_win_fans()` 在首次实际入账时同步保存 `settled_fan_gains_by_level`，键为关卡 ID 字符串，值为该关实际增量；开播 / 重开保留记录，随原 SaveData 存档。去重继续使用 LD-07 的 `settled_fan_level_ids`，重复提交不覆盖增量。

`LiveSessionData.get_result_snapshot(level_id)` 只读当前观看 / 点赞 / 评论 / 总粉丝与该关已提交 `fan_delta`，返回独立 Dictionary。旧存档或尚未提交的关卡缺少增量记录时返回 `null`，保留未知事实；正式零增量返回 0。

`RestResultView.show_result(session, run_data, ...)` 沿用现有上下文，在首次展示时调用 `RestSession.capture_live_result(run_data)`，冻结此时的真实直播结果；后续使用 `get_live_result_snapshot()` 返回副本。同一 RestSession 的重复打开、页面重新实例化及切关后的回看均沿用首次快照，不重新提交粉丝。缺少周目 / LiveSessionData 时显示“本场直播数据暂不可用”；缺增量时显示“本场粉丝变化记录暂缺”。默认生产粉丝增量仍为 0。

冻结时点为首次 Rest 展示，后续 LD-06 尚在运行的短时上涨继续按原规则推进 LiveSessionData，结果页保持当时快照。本卡没有修改短时上涨时长或收益规则。RestSession 的直播快照只属于运行时会话，跨进程历史直播结果浏览未在本卡实现。

两个正式 Sandbox 分支已有 `show_result()` 所需 SaveData，无需新增 Lane A 接线；`show_unbroken_result(session)` 的无上下文兼容入口仍明确显示资料不可用。新增一个 `LiveResult` 原生 Label，沿用现有 Theme，未制作正式展示美术、配置数值或新增永久测试。真实 Godot 4.7.2 D3D12 smoke 与既有单测结果见 `直播数据表现系统_LD-10_2026-10-09_log.md`。
## LD-11：四项直播数据 k 缩写

[LD-11 任务卡](tasks/LD-11_live-data-k-number-abbreviation.md) 已实现四项一致的显示层格式化：0～999 沿用整数；从 1000 起按千保留一位小数并使用小写 `k`，例如 `999 → 999`、`1000 → 1.0k`、`1100 → 1.1k`、`12500 → 12.5k`。小数按 Godot `%.1f` 格式化规则舍入。复用当前四个 `RichTextLabel` 和 `set_values()`，玩家区 ICON 在前、敌方区 ICON 在后。数据源和最近展示输入保持原始整数，切换图标/显示方向继续使用真实值。

最小场景验收入口为 `tests/live_data/ld11_hud_smoke.tscn`，覆盖正式战斗两侧 HUD、四项边界值、Resource 通知、图标与方向切换、数据源替换和显式解绑；`-- --gui-review` 保留图形窗口 45 秒供查看。验证结果见 [LD-11 日志](直播数据表现系统_LD-11_2026-10-10_log.md)。Android 真机验收未执行。

## LD-12～LD-16：双侧直播评论流（普通评论第一版）

已确认：直播间评论采用**配置表随机文字**，每条评论有用户名、正文与粉丝/路人类型；玩家、对手两侧各自独立刷新并向上滚动。粉丝显示所在主播阵营粉丝牌，路人仅显示昵称和正文；本版只显示普通评论。刷新频率、滚动速度、同屏可见数采用可调参数，实机以清晰、不眼花缭乱为验收标准。

此显示流独立于现有 LD-05 的 `comment_count`：LD-05 继续按真实弹幕/复读生成事实累计四项指标中的评论数；模拟直播聊天只展示观众评论文本与滚动，不引入额外 PK、粉丝资源或统计增量。

| 任务卡 | 单功能 | 前置 |
| --- | --- | --- |
| [LD-12](tasks/LD-12_comment-feed-config-table.md) | 直播评论词库导表与配置读取 | 现有导表工具 |
| [LD-13](tasks/LD-13_independent-random-chat-timing.md) | 玩家与对手直播评论分别随机刷新 | LD-12 |
| [LD-14](tasks/LD-14_scrolling-chat-display.md) | 直播评论从下向上滚动显示 | LD-13 |
| [LD-15](tasks/LD-15_camp-fan-badges.md) | 评论按粉丝身份显示双方专属粉丝牌 | LD-14 |
| [LD-16](tasks/LD-16_chat-feed-lifecycle-wiring.md) | 战斗时启动与重置双方直播评论流 | LD-12～LD-15 |

当前仓库中 `PresentationAssetConfig.player_fan_badge` 与 `LevelProfile.fan_badge_texture` 已可提供两侧资源；正式风格由现有美术资源替换入口承接。新词库为独立 `19_直播评论词库`，与 `09_直播数据` 数值规则表分别管理。

## 2026-10-10 直播评论按对手配置

策划 `19_直播评论词库` 在原 `comment_id / username / text / audience_type / side_scope / weight / enabled` 后新增可选 `streamer_id`。LD-12导表按 `side_scope` 与当前 `LevelProfile.streamer_id` 共同过滤；`streamer_id` 空表示通用评论，指定值表示该对手专属评论。LD-16在直播开场、重开与关卡切换时按新对手重取候选，并复用当前侧粉丝牌。四项直播统计继续由现有LiveSessionData更新，随机聊天属于展示。
