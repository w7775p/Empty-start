# 4. BarrageTraits 弹幕特性模块系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。已实现的基础卡用于接口复查；新的视觉、静止弹幕、对话与阶段打磨以最新单卡和此表为准。

## 2026-10-09 现行实现核对与任务状态

**现有组件：** `BarrageTraitSet` 已支持一条普通话语挂多个兼容特性，且可查询本关/已继承可用特性。真实普通批次当前尚未随机装配特性，BG-41 负责按后续明确的反击池选择；BG-35 负责特殊实例同屏容量。遮挡特性展示的最高层与随机位置静止生成分别由 BT-14、BT-15 处理；共享随机静止落点能力由 BG-42 提供。

| 卡片 | 按实际代码核对后的唯一功能 | 状态 |
| --- | --- | --- |
| [BT-14](tasks/BT-14_occlusion-top-z.md) | 遮挡话语最高层 | 待开发 |
| [BT-15](tasks/BT-15_occlusion-slow-velocity.md) | 遮挡在中央战斗区随机静止生成 | 待开发 |

本节是当前派工依据；历史章节中的旧默认值与旧任务说明保留用来追溯已有系统演变。开发时以单卡现行版和本节为准。


## 系统目标

弹幕特性模块系统负责给弹幕追加特殊规则。

当前需求中的特性包括：

- 遮挡；
- 水军复制 / 反击弹幕；
- 假牌；
- 不可选；
- 分裂；
- 反弹。

这个系统主要回答两类问题：

1. **这条弹幕现在能不能正常被攻击系统选中？**
2. **玩家打到它以后，这次应该是什么结果？**

特性系统不直接修改 PK 和倾向。最终收益与惩罚统一交给【6. HitResolution 命中结算系统】。

## 当前仓库状态

- BT-01 已提供 `BarrageTraitSet` 运行时数据组件，包含稳定特性 ID，并支持单条弹幕装配和查询多个特性。
- BT-02 已提供 `BarrageTraitSet.is_selectable()`；带 `unselectable` 的弹幕返回 `false`，其他弹幕返回 `true`。
- BT-03 已提供 `BarrageTraitSet.get_hit_result()` 和 `BarrageTraitResult`；遮挡结果不发正常话语收益，并携带 `occlusion` 异常类型供后续结算读取。
- BT-04 已让同一结果接口区分 `FAKE_CARD`；假牌不发正常话语收益，由后续命中结算识别并应用对应惩罚。
- BT-05 可通过 `mark_as_retaliation_copy()` 标记复制品；`is_retaliation_copy()` 可供 UI 显示反击标记，`can_trigger_copy()` 阻止复制链延续，命中时返回 `RETALIATION_COPY` 结果。
- BT-06 已实现正常话语的一次性分裂触发判定；3. BarrageGeneration 现在有 `spawn_normal_barrage()` 和运行时记录，但两个子话语生成、属性配置与母体截止时间继承仍待联调。
- BT-07 反弹目标返回 `REFLECT` 结果，不发正常话语收益，并携带 `reflect` 异常类型；反弹优先于遮挡和基础结果。
- BT-08 将反弹 → 遮挡 → 基础类型固定为唯一结果解析顺序，并新增 3 个关键单元测试。
- BT-09 提供纯逻辑 `BarrageTraitSet.are_compatible()`，判断不可选、分裂、反弹与外部提供的陷阱 / 复读类别之间已明确的互斥规则。
- CA-08 已将现有 `BarrageTraitSet.is_selectable()` 与 `get_hit_result()` 接入 CombatAttack 的释放扫描和到达结果；`BarrageRuntimeRecord` 为每个实例装配独立特性组件。
- 3. BarrageGeneration 已有正式运行时记录与生成入口；BT-13 提供本关 / 已提交继承的可用集合查询和显式普通实例装配，具体分配比例仍待正式配置。
- 2. LevelConfiguration 已拆出“本关特殊玩法标识”的配置任务。
- BT-06 的子话语生成还有待按 3. BarrageGeneration 的正式入口完成场景联调；本系统不自建生成逻辑。
- CA-09 / INT-01 已将逐目标 Trait Result 交给 HitResolution，并由 Sandbox 仅保留遮挡未命中的目标；正常、假牌、反击复制品和反弹结果都结束实例。生命周期与普通收益独立判断，假牌/反击/反弹继续跳过普通收益。当前样例使用空 TraitSet；special_trait_ids 的实例分配与 14. Assimilation 装配继续留后续卡，12 的矛盾特性边界已由 BT-12 核实。

BT-01 特性 ID：`occlusion`（遮挡）、`retaliation_copy`（水军复制 / 反击）、`fake_card`（假牌）、`unselectable`（不可选）、`split`（分裂）、`reflect`（反弹）。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| BT-01 | 定义特性类型与运行时装配 | 无 |
| BT-02 | 不可选目标判定 | 无 |
| BT-03 | 遮挡结果 | 无 |
| BT-04 | 假牌结果 | 无 |
| BT-05 | 水军复制品 / 反击标记 | 无 |
| BT-06 | 分裂一次并生成两个子话语 | 无 |
| BT-07 | 反弹结果 | 无 |
| BT-08 | 特性结果优先级 | 3 个关键单元测试 |
| BT-09 | 特性兼容规则 | 4 个关键单元测试 |
| BT-10 | 接入战斗攻击的可选目标过滤 | 无新增自动化测试 |
| BT-11 | 接入命中结算 | 无新增自动化测试 |
| BT-12 | 矛盾阶段排除普通战斗陷阱特性 | 无新增自动化测试 |
| BT-13 | 接入吞并继承特性 | 无新增自动化测试 |

## 测试预算

本系统只给两类纯规则写单元测试。

### 特性结果优先级
固定保护：

`反弹 → 遮挡 → 基础类型`

只测 3 个 case：

- 同时存在反弹和遮挡时取反弹；
- 没有反弹、有遮挡时取遮挡；
- 都没有时使用基础类型。

### 特性兼容边界
只测当前需求明确写死的 4 条：

- 不可选 + 分裂：不允许；
- 不可选 + 反弹：不允许；
- 分裂 + 陷阱：不允许；
- 分裂 + 复读：不允许。

总计 7 个核心 case。

不为下面这些逐项增加单元测试：

- 遮挡数值；
- 假牌数值；
- 反弹扣分；
- 分裂场景实例；
- 水军复制表现；
- 反击图标；
- 攻击系统联调；
- 命中结算联调；
- 矛盾阶段联调；
- 吞并联调。

这些继续用最小 Godot 运行和实际联调确认。

## 依赖顺序

BT-01～BT-09 可以先完成大部分纯特性规则。

BT-10 的目标可选过滤与到达结果读取已由 5. CombatAttack CA-08 完成。

## BT-10 可选目标过滤接线

- 复用 CA-08 的真实释放扫描：`AttackChargeInput._capture_target_snapshot()` 遍历当前 BarrageArea 视图，使用既有生命周期、区域可见矩形和准心相交检查，再对每条相交弹幕调用自身 `BarrageTraitSet.is_selectable()`。
- 带 `unselectable` 的目标排除，普通可选目标保留；过滤后的集合仍由现有 `AttackTargetSnapshot.capture_at_release()` 去重并冻结。
- 范围内仅有不可选目标时形成空快照；到达后沿用 CombatAttack → HitResolution 现有整发落空判定、异常选择与一次结算，不在特性系统新增瞄准、惩罚或收益规则。
- BT-10 只明确调整已有过滤调用的顺序并完成真实输入 smoke；没有改 Sandbox、关卡特性分配、神谕选择目标或后续 BT-11 接线，也没有新增自动化测试。

## BT-11 命中结算接线（2026-10-09）

- 复用 CA-09 的真实到达链：每个 BarrageView 的独立 TraitSet 解析最终 `BarrageTraitResult`，CombatAttack 原样携带该对象、内容事实与有效性，交给 `HitResolution.resolve_shot_results(target_results, shot_anomaly)`。
- 原链已区分正常 / 遮挡 / 假牌 / 反击复制品 / 反弹；本次补齐 6 系统此前缺失的特性惩罚。假牌逐目标 `-0.005`，反击逐目标 `-0.007`；反弹、遮挡、落空沿既有优先级每发仅扣 `-0.01`。数值沿用 `data/source_tables/06_战斗数值.csv` 的百分点换算。特殊结果 PK / 倾向普通收益清零；同一反弹目标最终 Kind 为 REFLECT，因此不会再加反击惩罚。
- 4 只提供最终类型；5 只传递已选整发异常；6 计算惩罚并一次更新 PK，17 沿 Sandbox 原回调收正常倾向。Sandbox 未修改，遮挡留场，其余最终结果结束实例的原边界保持。
- Godot `4.7.2.stable.steam.ed1daf0bf` 临时 TEST_ONLY 场景真实驱动鼠标蓄力 → 扫描 → 飞行 Timer → 结算 → Sandbox 回调，通过正常、假牌、反击、遮挡、组合反弹与同发混合联调。每发只更新一次 PK，特殊结果无普通倾向 / 历史；无新增长期测试。证据与限制见 BT-11 日期日志。

## BT-12 矛盾阶段特性边界（已核实）

- `BarrageArea.start_contradiction_generation()` 接收 12 固定的一真五假列表，一次性创建六个新 `BarrageRuntimeRecord`；其构造函数组合独立空 `BarrageTraitSet`，不复制普通实例的特性或关卡特性列表。
- 真矛盾和假矛盾都保留 `is_contradiction=true`、稳定 `original_sentence_id` 与原文。真假归属继续由 12 的当前关真 / 假列表拥有，假矛盾不等同于普通 `fake_card` 特性。
- 真实释放快照 `AttackTargetSnapshot.get_contradiction_facts()` 冻结原句 ID / 文本；Sandbox 原有回调立即交给 CB `resolve_shot_hit_ids()`。`AttackChargeInput` 的矛盾模式跳过普通到达 / HitResolution 提交，因此不会混入普通 PK、倾向或普通命中历史。
- Godot 4.7.2 一次 runtime smoke 使用现有一发上限，按当前关重开分别覆盖假 / 真矛盾：生成时两类均无假牌、反弹、分裂、不可选、遮挡或反击复制品特性，真假判定和选中事实保留。普通阶段六种特性组件规则及真实普通 / 遮挡输入继续工作。
- BT-12 仅补已有生成边界中文注释并完成定向验收；没有新增接口、清洗 TraitSet 的重复逻辑或自动化单测，也没有修改 Sandbox。后续特性分配 / BT-13 仍应只按各自普通实例边界接入，保持矛盾专用记录独立。

BT-13 已接入【14. Assimilation】的真实继承输出，接口与验收范围见下文。

## AS-06 提供的已提交特性输入

`LevelCatalog.get_inherited_content_snapshot(current_run_data.assimilation_data)` 的 `inherited_trait_ids` 直接来自 14 的已提交总量公开快照，与可解析普通池一起返回独立数据。没有正式奖励时数组为空；没有从本关 special_trait_ids 或待确认白名单补造已获特性。

4 系统可将返回 ID 交给已有 `BarrageTraitSet.add_trait()`，使用 `are_compatible()` 按实际普通 / 陷阱 / 复读上下文校验。AS-06 smoke 已验证第一关真实确认后，第二关读取 occlusion 并装配到独立 TraitSet；这里只验证数据消费，不代表 BT-13 的实际弹幕分配或战斗触发已完成，BT-12 矛盾隔离边界继续保持。

## BT-13：普通关可用集合与显式装配

- `BarrageTraitSet.get_available_for_level(level_profile, assimilation_data)` 先读取本关 `special_trait_ids`，再经 AS-06 `LevelCatalog.get_inherited_content_snapshot()` 读取已提交特性。特性查询无需词库目录，内部空目录只取 trait 数组；不解析或替代生成词库。复用 `add_trait()` 过滤未知 ID、去重，返回独立数组，保留原关卡顺序与继承顺序。
- 可用集合允许互斥候选共存。`add_available_traits(selected_ids, available_ids, includes_trap=false, includes_repeat=false)` 检查所选 ID 全部可用，并把已有装配与所选组合交给 BT-09 `are_compatible()`。失败返回 false，原集合保持不变；成功通过 `add_trait()` 登记。没有自动删除冲突候选或改写保存成果。
- `BarrageArea.get_available_trait_ids(level_profile)` 读取已登记 `SaveManager` 的当前 `SaveData.assimilation_data`；每次查询当前周目，换关、重开与新周目无需维护另一份继承缓存。没有周目时仍返回本关原有特性。
- `spawn_normal_barrage(level_profile, speech, selected_trait_ids=[])` 在新记录上装配显式选择；不可用或互斥选择返回 null，容量与场上实例保持不变。默认空选择保留现有普通批次行为。调用方可查询集合后显式传入 `[BarrageTraitSet.OCCLUSION]`，真实实例的攻击 / 命中结果继续读取同一 TraitSet。
- 自动批次的特性分配名单、比例和选择策略尚未提供正式数据，因此本卡保留原默认行为；可用特性不会自动全装到每条弹幕。Sandbox、陷阱、复读和矛盾生成入口未修改；矛盾记录保持空特性。没有新增永久测试或生产配置。
- Godot 4.7.2 两种临时 TEST_ONLY runtime smoke 已通过：无继承保留本关集合和默认生成；已提交继承可在后续关显式生成并返回遮挡 / 反弹结果，同时验证重复 ID、实例隔离、BT-09 拒绝及 BT-12 边界。详情见 BT-13 日志。

## FO-11 测试配置前置

- `LevelProfile.inheritable_trait_ids` 提供独立继承白名单，和当前关 `special_trait_ids` 分开；14 只登记白名单项，后续实例装配继续复用本系统支持 ID 与兼容规则。
- `tests/fixtures/fo11/test_level_001.tres` 使用已有 `occlusion`，Godot smoke 已验证 `add_trait()` 接受该 ID、`are_compatible()` 通过，以及 14 写入 / 读取后保持同一稳定 ID。
- 本次没有修改特性语义、生成分配或继承装配，也没有执行 BT-13。正式特性名单由策划填写生产关卡字段，fixture 仅供显式注入验收。

## 2026-10-09 新确认规则与单功能任务卡

特殊弹幕属于带有 TraitSet 的普通话语实例。每条实例可携带多项兼容特性；遮挡特性实例始终最高层、缓慢移动。携带特性的实例数量由 2/3 系统配置和计数，特性优先级继续复用本系统既有能力。

| 任务卡 | 唯一功能 | 状态 |
| --- | --- | --- |
| [BT-14](tasks/BT-14_occlusion-top-z.md) | 遮挡实例保持最高显示层级 | 待实施 |
| [BT-15](tasks/BT-15_occlusion-slow-velocity.md) | 遮挡实例缓慢移动 | 待实施 |

本轮任务卡逐项说明触发条件、应发生的行为与验收结果；派工时依赖最新卡片和系统当前代码。
