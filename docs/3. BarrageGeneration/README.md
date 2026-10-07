# 3. BarrageGeneration 弹幕生成系统任务拆分

## 系统目标

弹幕生成系统负责把“这一关允许出现的内容”真正变成场上的弹幕，并管理这些弹幕从出现到消失的生命周期。

它主要负责：

1. 从【关卡配置系统】读取当前关卡可用内容；
2. 按三项倾向比例选择普通话语；
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
- BG-12 已在隔离集成分支提供真假矛盾生成入口；CB-03 负责从当前关卡接入该入口，尚未合入 main。
- INT-01 在普通战斗失败、完成与重开时调用场上清理和 `RepeatDelayQueue.clear_normal_queue()`，完成当前普通战斗阶段的清理接线。
- 2. LevelConfiguration 已拆出关卡资料、词库、倾向比例和基础生成参数任务。
- INT-01 已接入普通战斗的特性结果、攻击、结算、Tier与复读调度；矛盾阶段及其他尚缺真实接口的联调继续保留对应任务卡。

DBG-01 提供只读 `get_current_barrage_counts()`，从当前真实 `BarrageView` 汇总普通与复读数量；开发操作使用 `clear_current_barrages()` 保持自动生成开关、`spawn_normal_batch_now()` 单次生成、`stop_normal_generation()` 与 `resume_normal_generation()` 控制普通批次。正式阶段结束仍使用会停止计时并清理弹幕的 `clear_barrages()`。

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

`BarrageArea.start_contradiction_generation(level_profile, true_lines, false_lines, config)` 停止普通生成，轮换两组矛盾原句，按 Paradox 配置使用每批数量 ×2、生成频率 ×3、移动速度 ×2.5，以及 10 秒实例寿命，不沿用当前普通 Tier 倍率。每个实例保留稳定 `original_sentence_id` 和 `is_contradiction` 标识；真伪由 12 系统按照关卡列表判断，不在弹幕系统结算。`stop_contradiction_generation()` 只停止新批次，`clear_barrages()` 清理场上内容并同时停止两种生成模式。

复读实例额外保存 `is_contradiction_repeat`，`has_visible_contradiction_repeats()` 只读取当前仍在场的矛盾复读视图；等待队列是否为空继续由 10 系统负责。

INT-01 已组合场上清理与【10. Repeat】的等待队列清理；进入后续矛盾阶段时可复用这些入口。

## BG-01 已实现的运行时数据

`systems/barrage_generation/barrage_runtime_record.gd` 定义 `BarrageRuntimeRecord`（`RefCounted`），运行时实例保存显示文本、来源稳定 ID、倾向 ID、强度、稳定 `original_sentence_id` 和生命周期截止时间。来源 ID 表示内容拥有者，当前关话语可取主播 ID；强度默认 `0.0`，创建方按正式参数赋值。记录还为每个实例装配独立的 `BarrageTraitSet`，由 4. BarrageTraits 管理特性 ID 和规则；BarrageGeneration 不解释特性语义。它是运行时数据快照，不改写 `LevelSpeech` 或 `LevelContradiction` 静态 Resource。

记录不保存场景节点或移动状态；`BarrageView` 管理实际显示和移动。`tendency_id` 继续沿用关卡内容提供的字符串，不在弹幕生成系统另建枚举。

## BG-02 普通话语抽取

`NormalSpeechSelector.select_next_normal_speech(current_level)` 每次直接读取传入关卡的当前词库与倾向比例，不缓存旧内容。倾向 ID 使用 `orthodox`、`heretical`、`absurd`；先按关卡比例选择倾向，再按该倾向下各条 `LevelSpeech.appearance_weight` 选择话语。

返回值是原始 `LevelSpeech` Resource，可继续读取文本、倾向和稳定原句 ID；没有有效候选时返回 `null`。本步骤不创建场上实例。

### BG-03 单条普通弹幕实例

`systems/barrage_generation/barrage_area.tscn` 是可复用弹幕区域，公开 `spawn_normal_barrage(LevelProfile, LevelSpeech)` 入口；调用后创建 `BarrageRuntimeRecord` 并实例化 `barrage_view.tscn`。视图显示原句文本，并按当前关 `base_move_speed_pixels_per_second` 从右向左移动。

当前游戏入口指向 INT-01 可玩 Sandbox，复用 BG-03 的弹幕表现。强度继续使用 `1.0` 原型值；持续生成、到期、离区和真实命中结束已接通。

### BG-04 普通弹幕持续生成

`BarrageArea.start_normal_generation(LevelProfile)` 打开普通生成，立即生成第一批，随后使用 `base_spawn_interval_seconds` 驱动内置 `Timer`，每批调用 `spawn_normal_barrage()` 共 `base_batch_count` 次。`stop_normal_generation()` 停止后续批次；已经在场的视图继续移动。

Sandbox 负责调用启动入口；战斗阶段可调用相同的启动 / 停止方法。INT-01 让普通话语与复读从轮换行开始寻找真实空位；候选视图和已有视图按各自矩形外留 8 像素检查相交，避免上一轮横移内容仍在时循环回同一行发生文字重叠。

### BG-05 后续生成倍率

`BarrageArea.set_generation_multipliers(generation_count_multiplier, generation_frequency_multiplier, movement_speed_multiplier)` 提供给 CombatStage 的倍率更新入口，字段语义对应 `CombatStageTierConfig`，但当前不直接依赖 8 号系统脚本。

后续批次数量按 `roundi(base_batch_count * generation_count_multiplier)` 取整；Timer 间隔为 `base_spawn_interval_seconds / generation_frequency_multiplier`；新视图速度为 `base_move_speed_pixels_per_second * movement_speed_multiplier`。倍率更新重置下一批计时，已生成视图保留创建时的速度。BG-06 的寿命倍率同样只作用于新实例。

### BG-06 生成时固定弹幕寿命

BarrageArea 暴露可编辑的 `base_lifetime_seconds` 临时基础值（默认 10 秒），并提供 `set_lifetime_multiplier()` 接收当前档位寿命倍率。生成新实例时，`BarrageRuntimeRecord` 保存单调时钟毫秒截止时间。倍率变化只影响之后新建的记录，既有截止时间保持不变。公共数值表尚未落地，基础值可在 Inspector 调整；到期移除由 BG-08 处理，暂停时的截止时间补偿由 BG-11 处理。

### BG-07 普通弹幕共享同屏上限

BarrageArea 从 `LevelProfile.normal_barrage_screen_cap` 读取普通上限。普通话语创建时自动登记，节点离开场景树时自动释放；陷阱等普通容量占用者通过 `try_register_normal_capacity_occupant()` 和 `release_normal_capacity_occupant()` 复用同一账本。达到上限时普通批次 Timer 暂停，释放容量后恢复；Timer 已运行时保留当前剩余时间，普通命中或无位置撤销不会重设正在运行的周期。BG-07 不实现弹幕特性规则；到期和离屏移除仍由 BG-08 负责。

### BG-08 到期与离开区域自然移除

生成时由 `BarrageArea` 把所属 `Control` 注入 `BarrageView`。视图每帧比较当前单调时钟与 `BarrageRuntimeRecord.expires_at_msec`；到期后调用 `queue_free()`。移动后，视图矩形与所属 Control 当前矩形不相交时也会自然结束。Node 离树触发 BG-07 的容量释放。有效区域使用父场景保存的 BarrageArea 实际边界；INT-02 已移除组件按整张舞台重写锚点的逻辑。命中移除由 BG-09 处理；恢复运行时，BG-11 会补偿暂停时长。

### BG-10 复读请求与独立同屏上限

`BarrageArea.spawn_repeat_barrage(RepeatPlan)` 接收单条计划，复制原句 ID、display_text 和计划寿命到运行时记录。复读使用独立的 `repeat_barrage_screen_cap`（临时默认 24，可在 Inspector 调整）和独立容量账本；普通容量满时复读仍可生成。复读容量满时方法返回 `null`，Repeat 调用方按既定溢出规则处理。延迟与数量由 RepeatDelayQueue 决定，本系统只显示到期请求。

### INT-01 生成事实、内容类别与结束接口

`BarrageRuntimeRecord.is_repeat` 由生成入口写入，普通话语为 `false`、复读为 `true`。`original_sentence_text` 保存原句；`text` 继续保存实际显示内容。CombatAttack 据此选择普通收益或复读零收益，复读不会进入普通命中历史。

`BarrageArea.barrage_generated(view: BarrageView)` 在普通话语或复读成功入树并完成定位后发送一次。协调方统一监听该事实更新 LiveData Comment，避免复读同时按计划与实际生成各计一次。

普通话语和复读都需要找到可放置的位置才算实际生成。所有行入口均有内容时，生成入口返回 `null`，移除尚未公布的视图并归还刚申请的容量；普通生成 Timer 在后续间隔再试，复读继续由现有 RepeatDelayQueue 保留到期请求重试。等待空间期间不发送生成通知，也不提前计评论或实际复读数；位置直接读取当前视图矩形，没有新增占位账本或队列。

`end_barrage(target_instance_id: int) -> bool` 只结束当前区域中的目标，立即离树释放容量，随后排队释放节点。Sandbox 根据最终 `BarrageTraitResult` 决定是否调用：仅遮挡未命中结果保留，正常、假牌、反击复制品及反弹结果都结束。移除与正常收益分别判断。无效、其他区域或已经结束的目标返回 `false`。

`clear_barrages()` 停止普通生成并结束当前区域全部弹幕，重置可见行轮换；等待中的复读继续由 RepeatDelayQueue 的清理入口处理。重开可立即生成新一局，旧视图不会占用新一局容量。

正式 `barrage_area.tscn` 已移除早期技术预览标题；外层 HUD 通过区域根节点组合组件，保持对子场景内部 NodePath 的独立性。

### BG-11 全局暂停生成与弹幕寿命

`BarrageArea` 沿用场景树默认的可暂停处理模式，普通生成 Timer 在 `SceneTree.paused` 时停止计时。`BarrageView` 使用 `PROCESS_MODE_ALWAYS` 观察暂停状态；暂停期间跳过移动和到期检查，并记录暂停开始时间。恢复时把实际暂停时长补加到 `expires_at_msec`，使已有弹幕按暂停前剩余寿命继续运行。该处理只覆盖弹幕生成和弹幕寿命。

### BG-14 / INT-02 舞台设计规格与静态布局

`data/stage_layout/stage_layout_profile.tres` 保存共享设计规格：基准 `1920×1080`，左右主播区各 `448×1080`，主播信息区 `448×128`、立绘区 `448×432`、直播数据区 `448×520`；中央 PK / Tier / 状态区 `1024×72`、弹幕区 `(448,72,1024,760)`、底部交互区 `1024×248`。这些区域相接覆盖整张基准舞台。

INT-02 采用静态 Scene 方案：`sandbox.tscn` 保存所有区域 Rect，编辑器预览与运行时沿用同一位置/尺寸，HUD 只整体缩放。StageLayoutProfile 保存区域设计规格；尺寸改变时按相同值编辑 Scene Rect，使配置规格和实际布局保持一致。

`barrage_area.tscn` 根节点为中性 Full Rect，由父场景实例明确设置自己的区域。Sandbox 中为相对 BattleArea 的 `(0,72,1024,760)`；组件继续根据自身 `size` 管理生成、移动边界与裁剪。已删除陈旧的 `stage_layout_profile` 导出字段和内部 `_apply_stage_layout()`，生成/倍率/容量/生命周期公开方法保持原接口。
