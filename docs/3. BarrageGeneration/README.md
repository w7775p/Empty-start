# 3. BarrageGeneration 弹幕生成系统任务拆分

> **派工入口**：[2026-10-09 当前任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。本系统的已完成旧卡保留作功能实现依据；下方历史讨论章节的旧数值以现行派工入口覆盖。


## 2026-10-10 现行实现核对与任务状态

**现行生成规则：** 前景普通话语与挂特性的特殊话语共用 T0～T5 各档少量容量，T1=10、T2=13、T3=16、T4=19、T5=22。T0 的 0 表示未填，普通阶段沿用 `LevelProfile.normal_barrage_screen_cap`。BG-16 已接入 CS-24 的 Tier 名额；普通话语与带特性话语共用同一账本，实例离树释放容量。Paradox 继续采用关卡上限，复读保留独立容量。复读在中央战斗区随机静止生成、按寿命渐隐并固定底层；遮挡特性话语在战斗区随机静止生成且固定最高层。普通前景采用可读的多运动方式。Paradox 阶段按 CB-13 读取一真五假六句。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [BG-16](tasks/BG-16_high-density-cap.md) | 按 Tier 读取前景容量 | 已合并 main；Tier 容量回归通过 |
| [BG-17](tasks/BG-17_pc-android-performance.md) | 分层性能与可读性验收 | 待组合实测 |
| [BG-42](tasks/BG-42_static-random-placement.md) | 复读和遮挡共用的中央区域随机静止落点 | 待开发 |
| [BG-24](tasks/BG-24_overlap-pass-through.md) | 实例出生与运动允许重叠 | 待开发 |
| [BG-27](tasks/BG-27_animated-size.md) | 连续缩放 | 已有脉冲入口 |
| [BG-28](tasks/BG-28_mixed-rich-text-style.md) | 前景富文本 | 待开发 |
| [BG-29](tasks/BG-29_local-text-animation.md) | 局部随机文字动画 | 待开发 |
| [BG-30](tasks/BG-30_opinion-tide.md) | 复读潮的疏密起伏 | 待开发 |
| [BG-31](tasks/BG-31_spatial-clusters.md) | 同句复读成批涌现（复用 RP-18） | 归档重复能力 |
| [BG-32](tasks/BG-32_linked-faux-depth.md) | 伪纵深观感 | 候选暂缓 |
| [BG-33](tasks/BG-33_impact-motion-wave.md) | 命中后的短时局部运动扰动 | 可选试玩后实施 |
| [BG-34](tasks/BG-34_frequency-based-refill.md) | 既有定时批次按 Tier 名额补位 | T2=13 组件级计时回归通过；Sandbox 布局待联调 |
| [BG-35](tasks/BG-35_special-instance-cap.md) | 特殊实例占用独立容量 | 待开发 |
| [BG-36](tasks/BG-36_downgrade-count-grace.md) | 降档超额自然回落 | T3→T2 自然回落与计时补位实测通过 |
| [BG-37](tasks/BG-37_foreground-text-outline.md) | 非复读文字描边 | 待开发 |
| [BG-38](tasks/BG-38_effective-area-clear.md) | 现有命中结束目标接线回归 | 已有链路 |
| [BG-39](tasks/BG-39_tier-motion-proportions.md) | 四种运动类型随 Tier 权重变化 | 待开发 |
| [BG-40](tasks/BG-40_foreground-speed-ceiling.md) | 前景话语最大速度 | 待开发 |
| [BG-41](tasks/BG-41_random-trait-selection.md) | 按已解锁池随机分配特性 | 技能池待定 |

**BG-34（2026-10-10）** `CombatStage` 将 T2=13 发布给 `BarrageArea`。满槽后移除 4 条，现场数量回到 9；容量释放恢复现有 `SpawnTimer`，下一次批次经 `NormalSpeechSelector` 补到 13，额外普通生成由现有上限拦截。复读继续走独立账本。本卡确认现有 BG-16 接线已满足频率补位规则，并新增真实组件回归。

`test_bg34_t2_timed_refill.gd` 使用当前 `BarrageArea` Scene、`CombatStage` 和 Tier Catalog。测试区为 1024×1200，为当前单列放置提供 13 个位置；1024×1008 实测可放 12 条。Sandbox 当前 BarrageArea 高 760px，完整同屏容量需在布局任务完成后实场复验。本卡未修改 Sandbox 或 PA 资产。

**BG-36（2026-10-10）** `CombatStage` 从 T3 降到 T2 后，`BarrageArea` 发布 13 个新名额；已有 16 条 `BarrageView` 保持原实例、移动和生成时保存的寿命。共享账本仍满于新名额时暂停普通生成；数量降到 13 时继续停表，四条较早生成的测试视图自然到期至 12 后，现有 `SpawnTimer` 才恢复并按 T2 间隔补到 13。此行为复用 BG-16 / BG-34 的容量和 Timer 逻辑，无需改动生产脚本。

`test_bg36_tier_downgrade_grace.gd` 使用真实 `CombatStage`、`BarrageArea`、`BarrageView` 与 `SpawnTimer`，逐项检查原实例 ID、绝对寿命截止值、运动、超额时停表、降到 12 后等待 timeout 再新增一条视图，以及补到 13 后停表。测试用 `LevelProfile` 和 `LevelSpeech` 均为脚本内构造的 TEST_ONLY 数据；这项组件级验证不代表 Sandbox 正式玩法验收。

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


## DD-16 终局表现接口（2026-10-09）

`BarrageArea.enter_terminal_presentation(trait_ids=[], trait_colors={})` 由 DivineDescentCombatMode / Spread 配置同一终局区域，只影响后续普通 / 复读实例。普通特性选择在终局忽略，运行记录 TraitSet 保持为空；冻结继承 ID 独立交给 BarrageView 的 `apply_terminal_trait_presentation()`，仅消费显式 Color 配色，缺配色沿用 Theme。`get_presentation_trait_ids()` 返回独立副本，原句和截止时间保持原值。区域终局状态持续至实例销毁，新普通周目创建新区域。

`allows_trap_generation()` 在终局返回 false，外部 `try_register_normal_capacity_occupant()` 同时拒绝准入；内部普通话语容量及复读容量照常工作。当前没有雷生成器或雷类型，未来外部陷阱源必须在创建前检查该公开边界。Sandbox 调用归 Lane A；完整接线及正式特性配色尚待集成，详见 19 README DD-16。

## 系统目标

弹幕生成系统负责把“这一关允许出现的内容”真正变成场上的弹幕，并管理这些弹幕从出现到消失的生命周期。

它主要负责：

1. 从【关卡配置系统】读取当前关卡可用内容；
2. 按三项倾向及 neutral 类别比例选择普通话语；
3. 按当前生成参数持续创建弹幕；
4. 给每个实例保存来源、倾向、强度和唯一原句标识；
5. 管理寿命、同屏上限、暂停和移除；
6. 接入【复读系统】的复读生成请求；
7. 在矛盾阶段改为生成真假矛盾；
8. 普通战斗结束时清理普通弹幕和未出现的普通复读。

弹幕生成系统不负责玩家瞄准、不负责计算 PK、不负责判断矛盾真假，也不负责弹幕特性的具体结算规则。

## 当前仓库状态

- BG-01～BG-08、BG-11 与 BG-14 核心任务已完成；BG-10 消费 RepeatPlan 并维护独立复读容量。INT-01 提供指定目标结束与场上清理入口，由 Sandbox 根据真实结算结果调用。
- Repeat 的延迟队列调用接线由 10. Repeat 的 RP-06 提供；INT-01 在 Sandbox 组合 CombatStage、命中移除和复读请求。
- BG-12 真/假矛盾生成入口与 CB-03 的当前关卡接线均已进入 main；现行一真五假六句固定出现由 CB-13 承接。
- INT-01 在普通战斗失败、完成与重开时调用场上清理和 `RepeatDelayQueue.clear_normal_queue()`，完成当前普通战斗阶段的清理接线。
- 2. LevelConfiguration 已拆出关卡资料、词库、倾向比例和基础生成参数任务。
- INT-01 已接入普通战斗的特性结果、攻击、结算、Tier与复读调度；矛盾阶段及其他尚缺真实接口的联调继续保留对应任务卡。

DBG-01 提供只读 `get_current_barrage_counts()`，从当前真实 `BarrageView` 汇总普通、复读与矛盾弹幕；开发操作使用 `clear_current_barrages()` 保持当前生成开关、`spawn_normal_batch_now()` 单次生成、`stop_normal_generation()` 与 `resume_normal_generation()` 控制普通批次。Paradox 阶段继续由矛盾专属生成器接管。

DD-12（2026-10-09）新增只读 `get_visible_barrage_records() -> Array[BarrageRuntimeRecord]`，即时读取区域内实际可见、矩形仍与区域相交的 BarrageView 记录；纯 UI、空记录、隐藏及待删除节点排除。返回新数组，记录引用供只读消费；19 使用稳定原句 ID 计算锁句占比，生成、容量与生命周期继续由 3 拥有。

BT-13 增加 `get_available_trait_ids(level_profile)`，读取当前 SaveManager 周目的已提交继承 ID，与本关特性合并并去重。`spawn_normal_barrage(level_profile, speech, selected_trait_ids=[])` 支持显式选择可用特性，复用 4 的 BT-09 校验，不可用 / 互斥选择返回 null。默认空选择保持原批次行为；正式分配比例待配置，不自动把全部可用特性装到每条弹幕。矛盾和复读入口保持独立，接口详情见 4 README 与 BT-13 日志。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| BG-01 | 定义单条弹幕运行时记录 | 无 |
| BG-02 | 读取当前关普通词库并按倾向比例抽取一句 | 无 |
| BG-03 | 生成单条普通弹幕实例 | 无 |
| BG-04 | 按基础数量与频率持续生成普通弹幕 | 无 |
| BG-05 | 当前档位倍率只影响后续生成 | 无 |
| BG-06 | 生成时固定弹幕寿命 | 2 个关键单元测试 |
| BG-07 | 普通话语与陷阱共用同屏上限 | 2 个关键单元测试 |
| BG-08 | 自然到期 / 离开有效区域移除 | 无 |
| BG-09 | 有效命中后的移除规则 | 无 |
| BG-10 | 接入复读生成请求与独立上限 | 2 个关键单元测试 |
| BG-11 | 全局暂停时停止生成与寿命计时 | 无 |
| BG-12 | 进入矛盾阶段时切换真假矛盾生成 | 无 |
| BG-13 | 普通战斗结束时清理普通弹幕和待生成复读 | 无 |
| BG-14 | 读取舞台布局尺寸 | 无 |
| BG-15 | 高密度动态弹幕与区域群体命中需求暂存（未完成，暂不派工） | 待后续正式拆卡确定 |

## 历史记录：BG-15 初始高密度设想（已被现行拆卡取代）

本节是早期需求记录：原先提出普通话语 500～1000 同屏，现已调整为**每档少量可读前景 + 独立容量的多量灰字复读**，最终基于 BG-16、RP-15、BG-17 验收；战斗区域四周及内部随机出生；直线、曲线、加减速、游荡四种运动；允许交叉、穿透、随机前后层级及运动中变层；弹幕动态缩放和变速；一句话内部不同样式与局部文字动画；视觉完全遮住仍可按实际区域群体命中；单发 PK 正向收益与负向惩罚分别封顶，但所有有效命中仍按实际结果进入对应系统结算。具体参数与实现方案仍未确定。

当前只记录在 `tasks/BG-15_pending-high-density-dynamic-barrage-requirements.md`，**未完成且暂不派工**。本次未修改程序实现；待关联的 05、06、10 等系统讨论后再整理具体 Agent 任务卡。

## 测试预算

本系统只给两个高风险边界写少量单元测试：

### 寿命边界
- 已经生成的弹幕，到期时间在档位变化后保持不变；
- 档位变化后新生成的弹幕使用新的寿命配置。

### 同屏上限
- 普通话语和陷阱共同占用普通弹幕上限；
- 普通弹幕腾出位置后可以继续生成；
- 复读上限与普通弹幕上限分别计算；
- 普通弹幕满时，如果复读仍有容量，复读仍可以生成。

总计最多 6 个核心 case。

下面这些不逐项写单元测试：

- 随机抽词结果；
- Resource / 实例字段；
- 生成动画和移动表现；
- 到期 / 离屏的场景行为；
- 暂停；
- 命中移除；
- 阶段清理；
- 矛盾阶段联调；
- 舞台布局。

这些继续用最小 Godot 解析、资源加载和实际场景运行确认。

## 依赖顺序

BG-01～BG-08、BG-11、BG-14 可以在大部分后续战斗系统尚未完成时开发。

INT-01 已组合【4. BarrageTraits】和【6. HitResolution】的逐目标结果与 BG-09 指定目标结束入口。

BG-10 等【10. Repeat】提供真实复读生成请求后再接。

BG-12 使用 Sandbox 的满 PK 阶段入口与 `ContradictionBreakSystem` 当前关卡内容；由 CB-03 接线。

## BG-12 矛盾生成接口

`BarrageArea.start_contradiction_generation(level_profile, true_lines, false_lines, config)` 停止普通生成，并一次性显示调用方提供的一条真句与五条假句。矛盾容量按本组候选数量独立计算，不共用普通前景账本；初始化失败会撤销本次生成的部分视图。实例沿用 Paradox 配置的移动速度与 10 秒寿命，保留稳定 `original_sentence_id` 和 `is_contradiction` 标识；真假由 12 系统判定，不在弹幕系统结算。`stop_contradiction_generation()` 停止矛盾阶段，`clear_barrages()` 清理场上内容并同时停止两种生成模式。

复读实例额外保存 `is_contradiction_repeat`，`has_visible_contradiction_repeats()` 只读取当前仍在场的矛盾复读视图；等待队列是否为空继续由 10 系统负责。

INT-01 已组合场上清理与【10. Repeat】的等待队列清理；进入后续矛盾阶段时可复用这些入口。

## BG-01 已实现的运行时数据

`systems/barrage_generation/barrage_runtime_record.gd` 定义 `BarrageRuntimeRecord`（`RefCounted`），运行时实例保存显示文本、来源稳定 ID、倾向 ID、强度、稳定 `original_sentence_id` 和生命周期截止时间。来源 ID 表示内容拥有者，当前关话语可取主播 ID；强度默认 `0.0`，创建方按正式参数赋值。记录还为每个实例装配独立的 `BarrageTraitSet`，由 4. BarrageTraits 管理特性 ID 和规则；BarrageGeneration 不解释特性语义。它是运行时数据快照，不改写 `LevelSpeech` 或 `LevelContradiction` 静态 Resource。

记录不保存场景节点或移动状态；`BarrageView` 管理实际显示和移动。`tendency_id` 继续沿用关卡内容提供的字符串，不在弹幕生成系统另建枚举。

## BG-02 普通话语抽取

`NormalSpeechSelector.select_next_normal_speech(current_level, neutral_weight_multiplier = 1.0)` 每次直接读取传入关卡的当前词库与类别比例，不缓存旧内容。普通话语类别为 `orthodox`、`heretical`、`absurd`、`neutral`；先按类别有效权重选择，再按该类别下各条 `LevelSpeech.appearance_weight` 选择话语。`neutral_ratio` 默认 0；Neutral 的有效类别权重为 `neutral_ratio × 当前 Tier 的 neutral_weight_multiplier`，其余三类仍用关卡原始比例，最后共同归一化。Tier 5 的倍率为 0，Neutral 不参与抽取。

返回值是原始 `LevelSpeech` Resource，可继续读取文本、倾向和稳定原句 ID；没有有效候选时返回 `null`。本步骤不创建场上实例。

### BG-03 单条普通弹幕实例

`systems/barrage_generation/barrage_area.tscn` 是可复用弹幕区域，公开 `spawn_normal_barrage(LevelProfile, LevelSpeech)` 入口；调用后创建 `BarrageRuntimeRecord` 并实例化 `barrage_view.tscn`。视图显示原句文本，并按当前关 `base_move_speed_pixels_per_second` 从右向左移动。

当前游戏入口指向 INT-01 可玩 Sandbox，复用 BG-03 的弹幕表现。普通弹幕强度从 `LevelSpeech.strength` 读取，旧内容默认为 1；持续生成、到期、离区和真实命中结束已接通。

### BG-04 普通弹幕持续生成

`BarrageArea.start_normal_generation(LevelProfile)` 打开普通生成，立即生成第一批，随后使用 `base_spawn_interval_seconds` 驱动内置 `Timer`，每批调用 `spawn_normal_barrage()` 共 `base_batch_count` 次。`stop_normal_generation()` 停止后续批次；已经在场的视图继续移动。

Sandbox 负责调用启动入口；战斗阶段可调用相同的启动 / 停止方法。INT-01 让普通话语与复读从轮换行开始寻找真实空位；候选视图和已有视图按各自矩形外留 8 像素检查相交，避免上一轮横移内容仍在时循环回同一行发生文字重叠。

### BG-05 后续生成倍率

`BarrageArea.set_generation_multipliers(generation_count_multiplier, generation_frequency_multiplier, movement_speed_multiplier)` 提供给 CombatStage 的倍率更新入口，字段语义对应 `CombatStageTierConfig`，但当前不直接依赖 8 号系统脚本。

`BarrageArea.set_neutral_weight_multiplier(multiplier)` 接收 CombatStage 当前 Tier 的 Neutral 权重倍率。普通生成每次选新话语时传给 `NormalSpeechSelector`；升降档后下一批立即使用新值，场上已经生成的弹幕不变。

后续批次数量按 `roundi(base_batch_count * generation_count_multiplier)` 取整；Timer 间隔为 `base_spawn_interval_seconds / generation_frequency_multiplier`；新视图速度为 `base_move_speed_pixels_per_second * movement_speed_multiplier`。倍率更新重置下一批计时，已生成视图保留创建时的速度。BG-06 的寿命倍率同样只作用于新实例。

### BG-06 生成时固定弹幕寿命

BarrageArea 暴露可编辑的 `base_lifetime_seconds` 临时基础值（默认 10 秒），并提供 `set_lifetime_multiplier()` 接收当前档位寿命倍率。生成新实例时，`BarrageRuntimeRecord` 保存单调时钟毫秒截止时间。倍率变化只影响之后新建的记录，既有截止时间保持不变。公共数值表尚未落地，基础值可在 Inspector 调整；到期移除由 BG-08 处理，暂停时的截止时间补偿由 BG-11 处理。

### BG-07 普通弹幕共享同屏上限

BarrageArea 的普通容量在 Tier 名额大于 0 时采用当前 Tier 值；T0 的 0 沿用 `LevelProfile.normal_barrage_screen_cap`。普通话语与带特性话语由同一入口登记，陷阱等普通占用者通过 `try_register_normal_capacity_occupant()` 和 `release_normal_capacity_occupant()` 复用同一账本。实例离树自动释放；容量满时普通批次 Timer 暂停，释放后恢复。Paradox 继续使用关卡上限，复读继续使用独立账本。BG-07 管理共享账本与生命周期；Tier 名额接线由 BG-16 完成。

### BG-16 按当前 Tier 控制前景容量

`CombatStageTierConfig.foreground_slot_count` 通过 `CombatStage.bind_barrage_area()` 发布给 `BarrageArea.set_foreground_slot_count()`。普通阶段 T1～T5 分别使用 10、13、16、19、22 个前景名额；T0 的 0 继续回退到 `LevelProfile.normal_barrage_screen_cap`。普通话语、带兼容特性的普通话语及外部普通容量占用者共享这些名额，节点离树后释放。矛盾阶段保持原关卡容量，复读仍由独立容量账本控制。

### BG-08 到期与离开区域自然移除

生成时由 `BarrageArea` 把所属 `Control` 注入 `BarrageView`。视图每帧比较当前单调时钟与 `BarrageRuntimeRecord.expires_at_msec`；到期后调用 `queue_free()`。移动后，视图矩形与所属 Control 当前矩形不相交时也会自然结束。Node 离树触发 BG-07 的容量释放。有效区域使用父场景保存的 BarrageArea 实际边界；INT-02 已移除组件按整张舞台重写锚点的逻辑。命中移除由 BG-09 处理；恢复运行时，BG-11 会补偿暂停时长。

### BG-10 复读请求与独立同屏上限

`BarrageArea.spawn_repeat_barrage(RepeatPlan)` 接收单条计划，复制原句 ID、内容类别、display_text 和计划寿命到运行时记录。复读使用独立的 `repeat_barrage_screen_cap`（临时默认 24，可在 Inspector 调整）和独立容量账本；普通容量满时复读仍可生成。复读容量满时方法返回 `null`，Repeat 调用方按既定溢出规则处理。延迟与数量由 RepeatDelayQueue 决定，本系统只显示到期请求。

### INT-01 生成事实、内容类别与结束接口

`BarrageRuntimeRecord.is_repeat` 由生成入口写入，普通话语为 `false`、复读为 `true`。`original_sentence_text` 保存原句；`text` 继续保存实际显示内容。CombatAttack 据此选择普通收益或复读零收益，复读不会进入普通命中历史。

`BarrageArea.barrage_generated(view: BarrageView)` 在普通话语或复读成功入树并完成定位后发送一次。协调方统一监听该事实更新 LiveData Comment，避免复读同时按计划与实际生成各计一次。

普通话语和复读都需要找到可放置的位置才算实际生成。所有行入口均有内容时，生成入口返回 `null`，移除尚未公布的视图并归还刚申请的容量；普通生成 Timer 在后续间隔再试，复读继续由现有 RepeatDelayQueue 保留到期请求重试。等待空间期间不发送生成通知，也不提前计评论或实际复读数；位置直接读取当前视图矩形，没有新增占位账本或队列。

`end_barrage(target_instance_id: int) -> bool` 只结束当前区域中的目标，立即离树释放容量，随后排队释放节点。Sandbox 根据最终 `BarrageTraitResult` 决定是否调用：仅遮挡未命中结果保留，正常、假牌、反击复制品及反弹结果都结束。移除与正常收益分别判断。无效、其他区域或已经结束的目标返回 `false`。

`clear_barrages()` 停止普通生成并结束当前区域全部弹幕，重置可见行轮换；等待中的复读继续由 RepeatDelayQueue 的清理入口处理。重开可立即生成新一局，旧视图不会占用新一局容量。

正式 `barrage_area.tscn` 已移除早期技术预览标题；外层 HUD 通过区域根节点组合组件，保持对子场景内部 NodePath 的独立性。

### BT-12 矛盾记录的特性边界

`start_contradiction_generation()` 的初始固定集合与 `spawn_contradiction_barrage()` 都通过新 `BarrageRuntimeRecord` 取得独立空 TraitSet；真 / 假实例保留矛盾标记、稳定原句 ID 和文本，生成入口不复制普通战斗特性。真假仍由 CB 根据当前关内容判断，普通 `fake_card` 等特性不承担真伪标记。CB-13 后续不自动轮换或补位矛盾句，也不更改普通生成规则。

### BG-11 全局暂停生成与弹幕寿命

`BarrageArea` 沿用场景树默认的可暂停处理模式，普通生成 Timer 在 `SceneTree.paused` 时停止计时。`BarrageView` 使用 `PROCESS_MODE_ALWAYS` 观察暂停状态；暂停期间跳过移动和到期检查，并记录暂停开始时间。恢复时把实际暂停时长补加到 `expires_at_msec`，使已有弹幕按暂停前剩余寿命继续运行。该处理只覆盖弹幕生成和弹幕寿命。

### BG-14 / INT-02 舞台设计规格与静态布局

`data/stage_layout/stage_layout_profile.tres` 当前仍保存 INT-02 的历史矩形：1920×1080、左右各 448px、中央顶部 72px，弹幕区 `(448,72,1024,760)`、底部交互区 248px。**最新目标**以 INT-06 为准：保留 72px 顶部，中央弹幕区扩展为 `(448,72,1024,1008)`，左下角悬浮操作 ICON；该布局是待实施任务。

INT-02 采用静态 Scene 方案：`sandbox.tscn` 保存所有区域 Rect，编辑器预览与运行时沿用同一位置/尺寸，HUD 只整体缩放。StageLayoutProfile 保存区域设计规格；尺寸改变时按相同值编辑 Scene Rect，使配置规格和实际布局保持一致。

`barrage_area.tscn` 根节点为中性 Full Rect，由父场景实例明确设置自己的区域。Sandbox 中为相对 BattleArea 的 `(0,72,1024,760)`；组件继续根据自身 `size` 管理生成、移动边界与裁剪。已删除陈旧的 `stage_layout_profile` 导出字段和内部 `_apply_stage_layout()`，生成/倍率/容量/生命周期公开方法保持原接口。

## 2026-10-09 战斗打磨单功能开发卡

本轮确认的高密度弹幕、四种运动、交叉层级、富文本、舆论潮汐、弹幕群聚、伪纵深、命中冲击波、复读感染、Tier 升降档与沉默爆发，现已拆为单一功能开发卡。每张卡仅定义触发条件、预期行为与验收结果；可调数值以实测和后续策划配置为准。实际状态与可派工顺序以本 README 顶部现行表及 `docs/开发计划_2026-10-09_任务卡依赖整合.md` 为准。

| 卡号 | 本卡唯一功能 | 状态 |
| --- | --- | --- |
| [BG-16](tasks/BG-16_high-density-cap.md) | 按 Tier 维持少量前景话语名额 | 待实施 |
| [BG-17](tasks/BG-17_pc-android-performance.md) | 前景少量话语与大量复读的分层性能验收 | 待实施 |
| [BG-18](tasks/BG-18_four-edge-spawn.md) | 战斗区域四周随机出生 | 待实施 |
| [BG-19](tasks/BG-19_interior-random-spawn.md) | 战斗区域内部随机出生 | 待实施 |
| [BG-20](tasks/BG-20_random-straight-motion.md) | 前景普通话语随机方向直线运动 | 待实施 |
| [BG-21](tasks/BG-21_curved-motion.md) | 前景普通话语连续曲线运动 | 待实施 |
| [BG-22](tasks/BG-22_speed-change-motion.md) | 前景普通话语平缓加减速 | 待实施 |
| [BG-23](tasks/BG-23_wandering-motion.md) | 前景普通话语低速游荡 | 待实施 |
| [BG-24](tasks/BG-24_overlap-pass-through.md) | 弹幕自由重叠与穿透 | 待实施 |
| [BG-25](tasks/BG-25_random-start-layer.md) | 普通前景话语随机初始层级 | 待实施 |
| [BG-26](tasks/BG-26_moving-layer-order.md) | 常规前景话语运动中随机改变层级 | 待实施 |
| [BG-27](tasks/BG-27_animated-size.md) | 普通前景话语的适度缩放 | 待实施 |
| [BG-28](tasks/BG-28_mixed-rich-text-style.md) | 单句话语内部富文本混合样式 | 待实施 |
| [BG-29](tasks/BG-29_local-text-animation.md) | 普通话语随机局部文字动画 | 待实施 |
| [BG-30](tasks/BG-30_opinion-tide.md) | 底层复读潮汐密度节奏 | 待实施 |
| [BG-31](tasks/BG-31_spatial-clusters.md) | 同一句复读成批出现 | 待实施 |
| [BG-32](tasks/BG-32_linked-faux-depth.md) | 伪纵深视觉候选体验验证 | 候选暂缓 |
| [BG-33](tasks/BG-33_impact-motion-wave.md) | 群体命中后的局部冲击波 | 待实施 |

关联依赖及实施顺序以各卡的上游功能卡为准；共享场景与组件按实际 Owner 的任务流程依次集成。

## 2026-10-09 新确认规则与单功能任务卡

前景包含普通话语及挂有特性的普通话语，二者共用当前 Tier 少量同屏名额，击中后按配置的正常生成频率补充。前景话语具备描边，运动方式与速度按可读性限制；复读在中央区随机静止生成并始终底层、按寿命渐隐；遮挡特性实例在随机位置静止显示并保持最高层。旧 BG-16、BG-17 需求已改为少量前景及背景复读的实际性能与可读性验收，BG-32 伪纵深保持候选暂缓状态。

| 任务卡 | 唯一功能 | 状态 |
| --- | --- | --- |
| [BG-34](tasks/BG-34_frequency-based-refill.md) | 按生成频率补足前景话语 | 待实施 |
| [BG-35](tasks/BG-35_special-instance-cap.md) | 限制携带特性的前景实例数量 | 待实施 |
| [BG-36](tasks/BG-36_downgrade-count-grace.md) | 降档后让超额前景实例自然回落 | 已实施（2026-10-10） |
| [BG-37](tasks/BG-37_foreground-text-outline.md) | 所有非复读话语文字描边 | 待实施 |
| [BG-38](tasks/BG-38_effective-area-clear.md) | 有效攻击后清除命中区域全部话语 | 待实施 |
| [BG-39](tasks/BG-39_tier-motion-proportions.md) | 按 Tier 改变前景运动类型权重 | 待实施 |
| [BG-42](tasks/BG-42_static-random-placement.md) | 复读与遮挡共享静止随机落点 | 待实施 |
| [BG-40](tasks/BG-40_foreground-speed-ceiling.md) | 普通前景话语速度上限 | 待实施 |

本轮任务卡逐项说明触发条件、应发生的行为与验收结果；派工时依赖最新卡片和系统当前代码。
