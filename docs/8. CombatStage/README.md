# 8. CombatStage 战斗阶段系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。开发前核对该表、本卡现行版、main 实际实现及最新完成日志。


> **派工入口**：[2026-10-09 当前任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。本系统的已完成旧卡保留作功能实现依据；下方历史讨论章节的旧数值以现行派工入口覆盖。


## 2026-10-09 现行实现核对与任务状态

**阶段结构：** `CombatStage` 的运行档位为 T0～T5，普通 T5 继续战斗到满 PK。进入真实 `ContradictionBreak` 后，SandboxBattleHud 显示 `T6 / Paradox`（CS-25）；此文案沿用运行 Tier 5、PK 比例与现有胜负流程。CS-18 已在整发命中、倾向及复读登记和 `shot_resolved` 消费者处理后，仅对本发实际升档调用 `clear_pending_normal_repeats()` 清空旧普通请求；CS-14 仍负责升档后的可见弹幕清理。T0 回拉倍率为 0（CS-19）；CS-22 的 T1 连线开场事件与完播通知已验收，正式对白配置仍为空；CS-15 已接入开场对白完播后的恢复；CS-23 已通过真实 T0→T1 攻击与双句对白联调验收。T2～T5 每档仅在本场首次到达时抽取一项反击（CS-28）；已抽技能按当前 Tier 生效，降档暂停高档反击、回升恢复原抽取结果（CS-29），具体候选池后续确定。降至 T0 对手离线（CS-26），降至 T1 触发嘲讽（CS-27）。
CS-14 已实现：升档整发通知完成后清除可见弹幕，保留新 Tier 的普通生成能力。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [CS-14](tasks/CS-14_tier-up-clear-all.md) | 本发结算完成后升档清屏 | 已完成 · Godot 4.7.2 GUI 运行通过（76 checks） |
| [CS-15](tasks/CS-15_tier-up-breakthrough.md) | 清屏后短暂突破与本档战斗恢复 | 已完成 |
| [CS-16](tasks/CS-16_tier-down-shake.md) | 降档统一震动（离线与嘲讽由 CS-26/27 叠加） | 已完成 · 4 档与跨档 Headless 验收通过 |
| [CS-17](tasks/CS-17_silence-and-burst.md) | 沉默爆发候选节点 | 待策划 |
| [CS-18](tasks/CS-18_tier-up-clear-old-repeat-requests.md) | 现有队列清理升档接线 | 已完成 · Godot 4.7.2 聚焦运行通过 |
| [CS-19](tasks/CS-19_tier0-zero-pullback.md) | T0 回拉倍率数值 0 | 配置完成；Sandbox T0/T1 现行回拉验证通过，对白后恢复已由 CS-15 接入，CS-23 联调验收通过 |
| [CS-20](tasks/CS-20_tier0-matching-status.md) | T0 搜索对手文案 | 已完成：开局/重开显示可配置等待状态，T1 接线后切换为对手已连线 |
| [CS-21](tasks/CS-21_tier1-opponent-portrait.md) | T0/T1 对手立绘出现 | 部分完成：显隐与回切已验证；level_001 素材映射待确认 |
| [CS-22](tasks/CS-22_tier1-bubble-dialogue.md) | T1 开场气泡对白 | 部分完成：事件序列与完播通知已验收；正式对白待配置 |
| [CS-23](tasks/CS-23_tier1-resume-on-dialogue-end.md) | T1 对话后恢复战斗 | 已完成 · 真实升档对白完播恢复验收通过 |
| [CS-24](tasks/CS-24_tier-foreground-slot-catalog.md) | Tier 唯一前景容量字段与 BarrageArea 读取接口 | 已完成 |
| [CS-25](tasks/CS-25_paradox-tier6-stage-label.md) | T6/Paradox HUD 阶段标记 | 已完成 |
| [CS-26](tasks/CS-26_tier1-to-tier0-disconnect.md) | 降至 T0 时对手离线 | 部分完成：离线、对白清理与 CS-16 震屏已联测；正式立绘映射待确认 |

CS-16 比较 HUD 已记录 Tier 与新最终 Tier；下降时通过 Tween 短时移动 BattleArea。HUD Inspector 可调整位移幅度和持续时间，当前默认初值为 6 设计像素、0.18 秒。该表现只移动显示父节点，BarrageArea 继续推进现存弹幕的运动与寿命。

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


## 系统目标

INT-01 已在正式 Sandbox 完成 HitResolution、BarrageArea、OpponentPKBar 和 AudioManager 的绑定，开局调用 `begin_combat()`。每次最终 PK 更新先同步档位，再由攻击提交回调读取档位创建复读计划；生成倍率只影响新弹幕。Tier 状态已连接可见反馈，Viewer / Like 的档位数值规则仍待配置。PK 满值由 Sandbox 停止普通战斗并启动真实 ContradictionBreak 入口。

战斗阶段系统负责根据当前 PK 判断普通战斗处于 Tier 0～5 的哪个档位，并把这个档位告诉其他系统。

它负责：
1. 开局 Tier 0；
2. 升档、降档和跨多档；
3. 一发命中全部结算完以后再更新档位；
4. 把当前档位配置交给弹幕生成、复读、对手回拉和表现系统；
5. PK 满时结束普通战斗并进入矛盾阶段；
6. 协调进入矛盾阶段前的清理。

## 当前已实现数据

`data/combat_stage/tier_catalog.tres` 为 Tier 0～5 的静态配置来源。`CombatStageTierCatalog.get_tier_config(tier)` 按档位读取各自的升/降档阈值、生成数量/频率/移动/寿命倍率、对手回拉倍率、每次命中复读数和对手立绘状态标识。正式对手回拉倍率 T0～T5 为 `0/1.3/1.6/1.8/2.0/2.2`；CS-19 的 Godot 4.7.2 Sandbox 运行测试确认 T0 玩家 PK 稳定、当前 T1 流程仍通过原 PK 所有者回拉。T1 开场对白事件与完播通知已由 CS-22 验收；CS-15 已接入对白完播后的回拉与生成恢复，CS-23 已用真实升档和 TEST_ONLY 双句对白验收完播恢复。

CS-25 由 `ContradictionOracleFlow.entered` 驱动 SandboxBattleHud 的 `set_paradox_stage_active(active, current_tier)`。真实矛盾流程进入时显示 `T6 / Paradox`；Final Oracle、Rest、失败和新尝试接线会按当前 `CombatStage.get_current_tier()` 恢复普通档位文字。该展示不增加 Tier 6 配置，也不改 PK 比例、胜负判定或矛盾规则。聚焦场景 `tests/combat_stage/cs25_paradox_stage_label_smoke.tscn` 覆盖 HUD 内容、真实矛盾流程、六个候选、Rest、失败重试及第二次尝试；GUI 视口截图保存在 `evidence/cs25_2026-10-11/`。截图与运行断言使用现有 `level_001.tres` 示例内容，正式四关文本仍需策划确认。

CS-20 通过 `SandboxBattleHud.t0_matching_status_text` 暴露可配置的 T0 等待文案，默认显示「等待对手连线……」。新开局和重开沿用 `show_battle_state()` 显示该状态；进入 T1 时，仅在当前文案仍由 HUD 管理时切换为「对手已连线」，普通 Tier 刷新继续保留其他来源的即时战斗提示。CS-26 增加明确的已连线→T0 离线优先级：切断对手时显示 T0 匹配状态，避免旧战斗提示遮住离线事实。刷新复用既有 `BattleAttemptFlow.pk_feedback_changed` 接口，不改 Sandbox 根脚本或战斗流程。

CS-21 复用 `SandboxBattleHud.set_opponent_portrait_connected()` 与 `refresh_pk()` 的当前 Tier 反馈：T0 隐藏对手立绘与对白侧，进入 T1 显示已配置的待机立绘，降回 T0 后再次隐藏，再进入 T1 可重新显示。连接状态仅在 Tier 实际变化时切换。当前正式 `level_001.tres` 的 `streamer_portrait` 为空；素材台账仍要求关卡角色映射确认后再绑定，因此正式 Sandbox 的 T1 暂时继续显示占位内容。聚焦场景 `tests/combat_stage/cs21_opponent_portrait_smoke.tscn` 使用仓库现有 `alien_idle.png` 经 HUD 公开素材接口做视图验收，不代表 `streamer_sample` 已映射为 alien；四张 GUI 证据保存在 `evidence/cs21_2026-10-11/`。Tier 接线沿用当前 `BattleAttemptFlow.pk_feedback_changed` 时点；CS-14 清屏与 CS-15 突破过渡现已接入，本卡未修改 Sandbox 根脚本。

CS-22 复用 `StreamerBubbleCombatStatePresenter` 的 `combat_connected` 事件：Tier 更新先发 `pk_feedback_changed` 刷新对手立绘；真实攻击升档的开场事件由 CS-15 在清屏提示完成后通过 `tier_transition_completed` 交给 SD-06，调试 PK 验收仍由 `tier_changed` 即时驱动。Sandbox 通过 `dialogue_event_sequence_completed(event_id, sequence_id, side)` 转发 SD-03 的实际完播通知，T0→T1 完播后恢复生成和回拉。`tests/combat_stage/cs22_tier1_bubble_dialogue_smoke.tscn` 以正式 Sandbox 和深复制 TEST_ONLY 配置验证两句顺序、立绘先显示、末句结束后仅发送一次完成通知；GUI 截图保存在 `evidence/cs22_2026-10-11/`。正式 `bubble_dialogue_config.tres` 当前没有开场台词，正式关卡的 `streamer_portrait` 也待素材映射确认，因此本卡标记为部分完成。

CS-26 复用同一 Tier 刷新入口：从 T1 或更高档降到 T0 时，HUD 显示配置的匹配提示、隐藏对手立绘，并通过 `set_opponent_portrait_connected(false)` 关闭 SD-03 对手侧、清空活动与待播对白及中断剧情序列。离线期间新对白会被拒绝；重新升到 T1 后，对手侧队列和立绘恢复。`tests/combat_stage/cs26_tier1_to_tier0_disconnect_smoke.tscn` 以正式 Sandbox 验收该完整路径、状态提示优先级及现存弹幕运动，GUI 证据保存在 `evidence/cs26_2026-10-11/`。CS-16 降档震屏已接入，震屏验收需在该卡完成后联测；`level_001.tres` 尚无正式 `streamer_portrait` 映射，截图测试仅经 HUD 接口临时使用仓库已有 `alien_idle.png`。

CS-24 增加 `CombatStageTierConfig.foreground_slot_count`。正式配置 T0=0（尚待策划填写）、T1～T5=10/13/16/19/22；各档 Resource 可独立调整。CombatStage 在绑定 BarrageArea、开局和档位切换时通过 `barrage_foreground_slot_count_changed` 发布当前值；BarrageArea 通过 `set_foreground_slot_count()` 接收并由 `get_foreground_slot_count()` 提供受控读取。0 保留为未配置标记，后续 BG-16 应沿用 `LevelProfile.normal_barrage_screen_cap` 的现有行为；CS-24 不改变容量准入或生成逻辑。

TT-14 在 `CombatStageTierConfig` 增加 `neutral_weight_multiplier`（默认 1.0）；正式 Tier 0～5 分别为 `1.00 / 0.99 / 0.70 / 0.40 / 0.15 / 0.00`。CombatStage 随当前 Tier 通过 `neutral_weight_multiplier_changed` 把该倍率交给 BarrageArea，绑定时也补发。它只改变后续普通话语类别抽取，不改动静态关卡比例或已有弹幕。

CS-02 的运行时 `CombatStage` 对象通过 `CombatStage.new(tier_catalog)` 接收 Tier 配置目录；`begin_combat()` 在新一场或当前关重开时把当前 Tier 设为 0，`get_current_tier()` 只读该状态。CS-03 的 `try_tier_up(final_player_pk)` 按当前 Tier 配置，在最终 PK 达到升档阈值时升一档；CS-04 的 `try_tier_down(final_player_pk)` 在最终 PK 严格低于降档阈值时降一档。CS-05 的 `update_tier_for_pk(final_player_pk)` 循环应用这两条既有规则，直到最终 Tier 与 PK 所在区间一致。

CS-06 的 `bind_hit_resolution(hit_resolution)` 连接 `HitResolution.final_player_pk_updated`，每次收到整发或回拉更新后的最终 PK 时调用 `update_tier_for_pk()`。命中中间计算不会进入该回调。CS-09 在当前 Tier 确定后广播回拉倍率与 Tier 5 状态；OpponentPKBar 通过 `bind_opponent_pk_bar()` 接收。

CS-07 通过 `bind_barrage_area(barrage_area)` 连接 BarrageArea 的真实倍率入口：`set_generation_multipliers()` 接收生成数量、频率和移动速度倍率，`set_lifetime_multiplier()` 接收寿命倍率。开局和最终 Tier 变化后，CombatStage 从当前 Tier 配置广播四个值；绑定时也立即补发当前配置。倍率具体应用和新弹幕实例仍由 BarrageArea 负责，既有弹幕保留生成时的速度和寿命。Sandbox 组合时由场景拥有者实例化并加入 BarrageArea 后，再调用 `bind_barrage_area()`；Lane C 不修改 Sandbox。

BG-39 在 `CombatStageTierConfig` 添加四种普通前景运动相对权重。`CombatStage` 沿用唯一当前 Tier，在 `_publish_barrage_state()` 通过 `barrage_foreground_motion_weights_changed` 发布该档权重；`bind_barrage_area()` 将接口接到 `BarrageArea.set_foreground_motion_weights()`。配置 Resource 默认仅选直线，正式表值待策划填写；Tier 状态仍由 CombatStage 单独持有。

CS-08 提供 `get_current_repeat_count_per_hit()`，返回当前 Tier 配置的 `repeat_count_per_hit`。命中结算完成并更新 Tier 后，普通复读计划创建方读取该数量与 `get_current_tier()`，传给 `RepeatPlan.create_normal_hit_plan()`；RepeatPlan 在创建时保存固定数量和结算档位。CombatStage 不缓存复读计划，也不拥有复读统计。

CS-18 在 `shot_arrival_resolved` 到达时记录本发 Tier，避免飞行期间的对手回拉变化被误认作本发升档。整发命中、倾向和复读计划处理完成并发出 `shot_resolved` 后，若结算 Tier 高于到达 Tier，`BattleAttemptFlow` 调用 `clear_pending_normal_repeats()`，复用 `RepeatDelayQueue.clear_normal_queue()` 清除旧档与同发仍待生成的普通请求；本发提交回调返回后，延迟中的普通战斗完成才可进入突破流程。队列清理只撤销待生成请求，实际已生成统计继续沿用原规则，新档请求可正常入队。

CS-14 在 `shot_resolved` 的所有消费者返回后，对比本发到达 Tier 与最终 Tier；仅实际升档时清空 `BarrageArea` 中当前可见的普通、带特性和复读视图。`clear_barrages_for_stage_transition()` 返回移除数量，并通过 `clear_current_barrages()` 保留普通生成状态；清理完成后发出 `tier_transition_cleared(previous_tier, current_tier, cleared_barrage_count)`，供 CS-15 接入升档演出。聚焦场景覆盖 T0→T1、T1→T2 和跨档上升，GUI 截图保存在 `evidence/cs14_2026-10-11/cs14_t0_to_t1_clear.png`。

CS-10 提供 `tier_state_changed(current_tier)`，在开局同步 Tier 0，并在跨档计算完成后只广播一次最终 Tier。Tier 上升时发出 `audio_event_requested(&"tier_up")`；`bind_audio_manager(audio_manager)` 将该事件接到 AU-01 的 `AudioManager.play_event(StringName)`。当前 LiveDataHud 只显示四项计数，没有 Tier 接收端；Sandbox 场景拥有者需把 `tier_state_changed` 接到实际 Tier 表现组件。此接口不包含 AU-02 音乐状态切换。

## 任务顺序

CS-11 提供 `get_stage_result(final_player_pk, maximum_player_pk)`：低于配置满值返回 `StageResult.NORMAL_COMBAT`，达到满值返回 `StageResult.ENTER_CONTRADICTION`。该结果即时派生，不保存第二份 PK 或阶段状态。Sandbox 收到最终 PK 后读取结果，立即调用 `HitResolution.set_normal_pk_resolution_enabled(false)` 固定满值，并停止对手回拉与普通生成；本发事实提交后沿用既有 `_complete_normal_combat()` 启动 12 系统。延迟切换期间的负增量也无法改低 PK。重开创建新的 HitResolution，普通结算恢复。真假矛盾内容和成败判定继续归 12 系统；缺失内容只用独立 TEST_ONLY 关卡验收，正式配置保持原样。

CS-11 仅新增 `tests/combat_stage/test_cs_11_enter_contradiction.gd` 一个用例；图形运行 Sandbox 的临时验收驱动验证满值冻结、回拉停止、真实矛盾入口和重开恢复，驱动在验收后删除。

CS-12 已核实并沿用 Sandbox `_stop_normal_combat()` 的协调入口：AttackChargeInput 停用时取消蓄力、飞行快照与硬直 Timer；BarrageArea 停止生成并清空旧普通 / 复读视图与容量；RepeatDelayQueue 清空普通等待请求，实际生成统计保留供胜利提交。全部清理完成后 `_complete_normal_combat()` 才启动 ContradictionBreak 内容、矛盾生成与限时窗口。各状态继续由所属系统清理。

满值通知与帧尾清理之间，Sandbox 的普通复读调度还检查 `HitResolution.allows_normal_pk_resolution()`，普通结算关闭后立即停止推进，防止到期请求在延迟窗口生成并进入胜利统计；本发事实提交仍按原流程完成。矛盾复读继续按矛盾阶段开关调度。CS-12 未新增永久自动化测试；Godot 4.7.2 TEST_ONLY 图形 Sandbox 临时冒烟已覆盖蓄力、飞行和硬直三种清理状态。

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| CS-01 | 定义 Tier 配置数据 | 无 |
| CS-02 | 开局固定 Tier 0 | 无 |
| CS-03 | 升档判定 | 1 个关键单元测试 |
| CS-04 | 降档判定 | 1 个关键单元测试 |
| CS-05 | 一次 PK 变化跨多档 | 2 个关键单元测试 |
| CS-06 | PK 更新后重新判断档位 | 无新增自动化测试 |
| CS-07 | 把生成倍率交给弹幕生成 | 无新增自动化测试 |
| CS-08 | 把复读配置交给复读系统 | 无新增自动化测试 |
| CS-09 | 把回拉倍率和 Tier 5 状态交给对手系统 | 无新增自动化测试 |
| CS-10 | 把档位变化交给直播/视听表现 | 无新增自动化测试 |
| CS-11 | PK 满进入矛盾阶段 | 1 个关键单元测试 |
| CS-12 | 进入矛盾阶段前清理普通战斗 | 无新增自动化测试 |
| CS-13 | Tier 升档清屏、降档震动反馈（需求暂存，未完成） | 待后续正式拆卡 |

## 测试预算

只保留 5 个纯逻辑 case：

- 到达升档阈值会升档；
- 低于降档阈值会降档；
- 一次 PK 上升可以跨多档；
- 一次 PK 下降可以跨多档；
- PK 满会得到“进入矛盾阶段”的阶段结果。

Tier 配置字段、跨系统通知、画面音乐、阶段清理和静音过渡全部做最小联调。

## 依赖顺序

CS-01～05 可以先完成纯档位逻辑。
CS-06 等 6. HitResolution。
CS-07 已接入 3. BarrageGeneration 的 BarrageArea 公开接口。
CS-08 已提供 10. Repeat 创建普通复读计划所需的当前 Tier 数量接口。
CS-09 等 7. OpponentPKBar。
CS-10 的 Tier 状态与 AU-01 音效绑定已在 INT-01 Sandbox 接通；直播热度数值变化继续等待具体规则。
CS-11 等 12. ContradictionBreak 有真实入口后联调。
CS-12 等 3/5/10 的清理入口存在。

## 历史记录：CS-13 升降档表现需求初稿（已拆卡）

现行需求：全部普通战斗升档按 CS-18→CS-14→CS-15 处理旧队列清理、清屏和过渡；全部降档通过 CS-16 震屏并保留弹幕，降至 T0 另触发 CS-26 对手离线，降至 T1 另触发 CS-27 对手嘲讽。历史讨论档见 `tasks/CS-13_pending-tier-transition-feedback.md`。

## 2026-10-09 战斗打磨单功能开发卡

本轮确认的高密度弹幕、四种运动、交叉层级、富文本、舆论潮汐、弹幕群聚、伪纵深、命中冲击波、复读感染、Tier 升降档与沉默爆发，现已拆为单一功能开发卡。每张卡仅定义触发条件、预期行为与验收结果；可调数值以实测和后续策划配置为准。当前单卡状态以顶部现行表、各卡自身状态和 `docs/开发计划_2026-10-09_任务卡依赖整合.md` 为准。

| 卡号 | 本卡唯一功能 | 状态 |
| --- | --- | --- |
| [CS-14](tasks/CS-14_tier-up-clear-all.md) | 所有升档清空全部可见弹幕 | 待实施 |
| [CS-15](tasks/CS-15_tier-up-breakthrough.md) | 清屏后短暂突破与本档战斗恢复 | 已完成 |
| [CS-16](tasks/CS-16_tier-down-shake.md) | 降档统一震屏，其他剧情由 CS-26/27 提供 | 待实施 |
| [CS-17](tasks/CS-17_silence-and-burst.md) | 关键阶段沉默后爆发 | 待实施 |

关联依赖及实施顺序以各卡的上游功能卡为准；共享场景与组件按实际 Owner 的任务流程依次集成。

CS-15 在清屏完成后暂停普通输入、生成、回拉和复读推进，复用 HUD 当前 Tier 标签完成短暂弹出。T2～T5 演出结束后恢复本档弹幕与回拉；T0→T1 先显示连接立绘，再提交 CS-22 开场事件，对话完整结束后恢复普通战斗。测试入口使用现有 Tier 参数，无新增资源或正式数值。

## 2026-10-09 新确认规则与单功能任务卡

T0 为等待匹配对手阶段，对手回拉倍率为 0；进入 T1 后清屏、展示对手待机立绘和气泡对话，对话结束后恢复 T1 正常弹幕和回拉。升档同步刷新旧复读等待队列；降档统一震屏且原有弹幕按寿命自然回落，落到 T0/T1 时可分别叠加离线/嘲讽。T5 继续属于普通战斗，T5 结束后才进入 T6 / Paradox（矛盾击破）。T2～T5 的随机对手反击技能库继续保留后续专题设计。

| 任务卡 | 唯一功能 | 状态 |
| --- | --- | --- |
| [CS-18](tasks/CS-18_tier-up-clear-old-repeat-requests.md) | 升档同步清理旧复读生成队列 | 待实施 |
| [CS-19](tasks/CS-19_tier0-zero-pullback.md) | T0 的对手 PK 回拉倍率为零 | 待实施 |
| [CS-20](tasks/CS-20_tier0-matching-status.md) | T0 显示等待连线状态 | 待实施 |
| [CS-21](tasks/CS-21_tier1-opponent-portrait.md) | T1 连线展示对手待机立绘 | 待实施 |
| [CS-22](tasks/CS-22_tier1-bubble-dialogue.md) | T1 连线播放对手气泡对话 | 待实施 |
| [CS-23](tasks/CS-23_tier1-resume-on-dialogue-end.md) | T1 对话结束后进入正式 PK | 待实施 |

本轮任务卡逐项说明触发条件、应发生的行为与验收结果；派工时依赖最新卡片和系统当前代码。

## 2026-10-09 新增确认：降档剧情与反击技能生命周期

对手的阶段表现与战斗 Tier 对应：**T1→T0 对手离线并恢复匹配提示**；**T2→T1 对手嘲讽**。降档仍沿用 CS-16 震屏和场上弹幕自然回落。T2、T3、T4、T5 在**每场战斗每个 Tier 首次到达**时各随机抽取一项反击；已抽结果本场记住，当前 Tier 只启用已抽取且所属 Tier 不高于当前档位的反击。降档暂停高档技能的后续触发，回升到原档后恢复此前抽取的技能。技能候选池、具体技能效果继续由策划后续确定。

| 任务卡 | 单功能 | 状态 |
| --- | --- | --- |
| [CS-26](tasks/CS-26_tier1-to-tier0-disconnect.md) | 降至 T0 时对手离线 | 待开发 |
| [CS-27](tasks/CS-27_tier2-to-tier1-taunt.md) | T2+ 降至 T1 时嘲讽，并继续 T1 普通战斗 | 已完成 · Godot 4.7.2 Sandbox Headless：37 checks，0 failures |
| [CS-28](tasks/CS-28_first-entry-one-retaliation-per-tier.md) | 每个 Tier 本场首次到达抽取一次反击 | 待开发 |
| [CS-29](tasks/CS-29_retaliation-effective-by-current-tier.md) | 已抽反击按当前 Tier 生效 | 待开发 |

**数值与术语记录：** 单场普通战斗的体验目标约为 **2～4 分钟**，后续通过 PK 得分、阈值、回拉等函数统一建模。向美术说明「正确弹幕加分、错误弹幕扣分」时，继续使用现有弹幕特性和 HitResolution 的得分结果作为实际程序判定来源。

## 与 21. StreamerBubbleDialogue 的事件接线（2026-10-09）

CS-22 在 T1 首次连线时触发配置好的开场对白，实际气泡展示由 [SD-02](../21.%20StreamerBubbleDialogue/tasks/SD-02_portrait-side-bubble-view.md)、[SD-03](../21.%20StreamerBubbleDialogue/tasks/SD-03_ordered-bubble-events.md)、[SD-06](../21.%20StreamerBubbleDialogue/tasks/SD-06_combat-state-dialogue-event.md) 负责；CS-15 已将开场对白序列完播后的生成与对手回拉恢复接入正式流程，CS-23 已验证完播后恢复正式战斗流程。CS-27 降至 T1 的嘲讽也通过 SD-06 映射，CS-26 降至 T0 将对手离线事实交给气泡队列清理。普通话语命中映射与指定话语触发对手台词分别归 SD-04、SD-05；定时对白归 SD-07。剧情数值与阶段所有权继续归 CombatStage/Sandbox。
