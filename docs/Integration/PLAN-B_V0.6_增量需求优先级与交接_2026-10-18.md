# Plan B V0.6 · 最新增量需求执行优先级（2026-10-18）

## 唯一最新规则
本文件消除 PB-06～PB-10 在 2026-10-17 定版后与四张新增任务卡之间的文字冲突；原卡未涉及的 **完整四关正式流程、1920×1080 三列布局、左右主播演出、PK、矛盾击破蓄力射击和结算** 继续生效。

### P0 交互（依次以最新任务为准）
1. **PB-13 / PR #265：** 原先“选句→点击一名中立观众→将该观众转化”的单颗播种改为“选句→点击中央棋盘任意有效位置→按 strength 生成 2/4/8 颗我方/敌方棋子”。基础合法感染率为 50%/60%/70%；批次必须完整创建才算成功，失败不耗词、不耗次数/计时。每批累计成功感染5次可触发一次性 split/reflect 候选特性。旧的 `seed_unit(neutral_unit_id)` 不再用于玩家正式发表，现有真实碰撞/改口/人口PK延续。
2. **PB-12 / PR #266：** 原先“4张手牌、使用后即时抽取补位、玩家全局5秒冷却”改为“**3个固定卡位，数字键1～3，连续可发表；成功使用的那一槽独立等待5秒再抽一张新卡**”。另外两槽不受影响；玩家取消全局发言冷却，对手 AI 冷却独立。失败不消耗；暂停冻结倒计时，重开重抽。
3. **PB-11 / PR #267：** 同阵营棋子主动结群（不融合，不改棋子人数/PK）；同阵营、同词且空间相邻的棋子共享一只复读气泡，保留P1/P2轮廓与1～5根尾巴；PB-20覆盖旧人数定宽规则，主播主泡和复读泡的文字栏按同一字体测量约10个全角汉字，文字块在泡体安全区域居中、每行左对齐，全文自动换行并按高度适配。当前共享内边距为25×16px，团体人数只影响尾巴数与团体锚点。出生、感染、转化和改口即时复读，独立随机复读计时。运动真实碰撞与短暂弹开保留。
4. **PB-14 / PR #268：** 先测真实 Profiler、再优化高频全场搜索/重复快照拷贝/绘制插值；约96棋子为**测量基准而非最终人口上限**。人口上限在优化后用性能及实际画面可读性分档测定，不预先锁定最终值。
5. **PB-15：** 每场正式普通战斗开局保留30名中立观众；A 提供2个费米播种位并完成播种。B 以0.75秒为补人中心间隔、按±25%扰动；自动补人到总人口上限前保留8个位置，供 strength 3 的完整批次使用。人口上限仍待 PB-14 性能与 PB-16 棋子放大后的画面密度共同决定。

### 其他始终生效
- 逻辑画布 1920×1080：主播左右各448；中央 PK 72、棋盘828、底部话语180。PC 默认窗口化；棋子美术采用实际已交付资源。
- 普通 PK 只用话语投放、棋子传播；达到100%后进入原有六选一矛盾击破，**仍使用蓄力射击**。保留四关、Tier、气泡、直播数据/评论、漫画反馈、旧剧情演出、结算与结局。
- 由 A 拥有整批发表原子事务与 PK，B 拥有真实棋子及邻域/碰撞，C 拥有四关词库/AI，D 拥有三槽/棋盘/共享气泡显示，E 测实际性能并出包。对用户电脑仍禁止 GUI 操作时，仅运行非 GUI 构建验证并将需要人工画面验收的部分标为待验。
- 画面遮挡补充（PB-16/PB-17实机验收）：人口统计留在72px PK/Tier栏，瞬时事件文字留在180px底部话语栏；PB-19将当前头像逻辑直径更新为64px。群体气泡优先选择与头像重叠最少的上/左/右/下位置，保持完整话语、尾巴与B的真实单位中心不变。

## 旧任务卡优先级规则与交接
- PB-06 正式流程卡：正式主线仍有效，`publish_word(...,neutral_unit_id)` 的旧目标参数以 PB-13 批次坐标接口替代；旧人物/矛盾击破不变。
- PB-07 棋盘卡：1024×828 的坐标与碰撞仍有效，新增出生容量和 PB-11/PB-14 共用邻域逻辑；总数96先作为测试数，优化后决定正式上限。
- PB-08 词库卡：四关词库和 AI 内容仍有效，旧“四句即时补牌”由 PB-12 三槽独立5秒补位替代；C 提供不重复的新词候选，A 保证一次成功消费。
- PB-09 UI 卡：旧“四句、数字键1～4、点击中立棋子”由三槽1～3、点击任意棋盘有效位置替代；PB-11共享气泡叠加，PB-14负责性能。
- PB-10 打包验收卡：沿用窗口/CSV导出/整链验收，实际包必须覆盖新三槽、批次、结群、共享气泡；优化后的真人性能验证后再确定人口上限。

## 合流工作流
1. A 当前 PB-06 未提交的代码保留并由 A 自己同步新规格；B/C/D/E 在各自原工作树继续，分别提交变更与log。
2. B 先交批次出生/合法容量，再接PB-11运动和PB-14低频决策；A 改发表事务，C 同步对手与三槽词池，D 同步三槽UI与批次视觉，E 在合流后测实际帧率并出包。
3. 游戏完整流程不断开：Boot→身份→房间→四关 Plan B 普通 PK→旧六选一蓄力矛盾击破→败者卡/结算→回房间或结局。

### Lane B 当前已实现的批次接口（PB-13）
- `PlanBUnitSimulation.set_play_area(scene_area: Rect2)` 接收棋盘 scene-global 矩形并转换为模拟节点本地边界；模拟器根按正式场景保持无旋转、单位缩放。单位快照中的 `position` 与 `collision_radius` 使用 scene-global 坐标。
- `spawn_word_batch(scene_position, team, word_definition, word_order, requested_count) -> Dictionary` 由玩家和对手共用。仅接受 strength 1/2/3 对应 2/4/8 的完整数量、有效阵营/词/棋盘落点及足够容量；成功结果含 `ok`, `reason`, `word_order`, `team`, `word_id`, `word_definition`, `spawn_position`, `spawn_target_positions`, `unit_ids`, `count`。失败返回 `ok=false` 和明确 `reason`，人口、单位 ID 与批次事实均不改变。
- `word_batch_spawned(batch: Dictionary)` 每个完整成功批次只发一次，字段沿用上项批次快照；`unit_spawned(unit_id)` 仍按真实单位各发一次。D 用批次事实表现喷涌，继续以 B 的单位快照渲染运行位置。
- 合法感染常量为 strength 1/2/3 = 50%/60%/70%。玩家批次以 `word_order` 累计成功感染；达到5次最多发放一次 split/reflect，并通过 `word_batch_trait_awarded(word_order, unit_id, trait_name)` 通知表现层。

### Lane B 当前已实现的 PB-11 团体与运动接口
- `PlanBUnitSimulation.get_word_groups() -> Array[Dictionary]` 返回按稳定 `group_id` 排序的同阵营、同当前 `word_id` 空间连通组。每组字段包括 `group_id/team/word_id/word_order/member_ids/word_snapshot/member_positions/center_position`；成员位置、几何中心使用 scene-global 坐标，1人单位也保留为一组。
- `word_groups_changed(groups: Array)` 在团体拓扑、阵营、话语成员关系变化时发出完整组快照；清场会在旧组存在时发出空数组。成员实时位置由 `get_word_groups()` 读取，避免每个物理步复制话语字典。
- `PlanBUnit.get_word_id()` 提供稳定当前话语 ID，用于组建团体。玩家、对手棋子以同阵营、同话语、相邻关系组成气泡组；单个棋子也形成独立组。
- 团体邻接默认 72px 加入、90px 离开，成员到组中心半径上限180px；拓扑固定每0.2秒刷新，同一周期内的出生、感染、改口和离场会合并到下一次刷新。成员位置仍由查询接口即时提供。
- 主动移动默认同阵营侦测160px、理想间距36px；物理有效理想间距会按碰撞直径抬升到至少64px。保持同话吸引0.45、同阵营不同话吸引0.225、分离0.65。可感染目标追击与克制威胁回避优先于团体靠拢；无优先目标时向同伴移动。
- 敌我/中立接触反冲持续0.18秒并沿用原接触裁决；同阵营贴碰使用轻量软分离并保留 `word_order` 改口规则。团体始终保留独立 `unit_id`、人口、寿命和PK统计。
- lane D 负责将这些团体快照绘制为共享气泡及尾巴。PB-14 会补充单位物理帧位置事实信号供绘制插值。

### Lane B 当前已实现的 PB-14 决策与位置事实
- `target_decision_refresh_seconds` 默认0.1秒。目标、威胁与同伴查询复用同一邻居网格；棋子按稳定 `unit_id` 错峰刷新决策缓存。
- 单位位置积分、真实 Area2D 接触、感染/改口、反冲和边缘反射继续每个物理步运行。物理步之间沿缓存方向和当前速度运动；碰撞反冲期间不由寻敌改写速度。
- 目标方向按单位各自错峰每0.1秒更新；接触、感染和改口在下个决策时隙读取新状态。空间网格默认0.1秒刷新；新生/离场会使成员索引在下一物理步重建，碰撞分离期间以额外候选padding覆盖网格位置偏移。团体拓扑固定每0.2秒刷新，事件不会把它提升到每物理步。
- `unit_physics_positions_updated(unit_ids: PackedInt32Array, previous_positions: PackedVector2Array, current_positions: PackedVector2Array)` 每个物理步发出一次。三组数组按升序 Unit ID 对齐，位置使用 scene-global 坐标，新生首帧的前后位置相同；D 可在渲染帧之间据此插值。
- PB-14 的 pre-optimization 正式 Sandbox CLI profile 与后续同场景 post-optimization 结果记录在 `evidence/PB-14_2026-10-18/`。Engine `TIME_PROCESS/TIME_PHYSICS_PROCESS` 与 CLI GPU/FPS 值按各自计量名记录；GUI Profiler 的 Script/Idle 函数明细及窗口截图需人工验收。

### PB-15 人口配置接线与当前规则

- C 的 population_config.csv 使用 Keep File；PlanBContentCatalog.load_configuration() 验证后由 get_population_config() 返回副本。A 的 PlanBBattleHost.configure_modules() 已将该配置调用 B 的 configure_population_config() 实际写入 PlanBUnitSimulation。
- B 模拟器应用30名中立、C额外播种槽0、中心间隔0.75秒、jitter ratio 0.25。A Host 仍独立持有 initial_opponent_seed_count=2，并显式调用 create_population(-1, 2)：B 创建30名中立加2个待播种槽，A播种后首个PK快照是30中立、2对手。
- 补人使用独立随机流，set_random_seed() 同步重置棋子与补人随机流。自动补人上限为 maximum_population 减去可调 neutral_spawn_batch_reserve（默认8）；达到容量线后冻结周期，释放空间后继续。
- 玩家与对手仍使用现有2/4/8完整批次接口；容量与PK来自实时单位总数和阵营快照。默认最大人口96保留。
- PB-10 packed CSV smoke 已扩展为7份原表，增加 population_config.csv 与 battle_type_emoji.csv；Windows构建脚本的成功摘要预期同步为7。当前集成分支尚未执行PCK导出。
- 30、50、80人口密度、正式场景切关/重开和玩家/对手批次仍待后续验收。
### Lane B 当前已实现的 PB-19 碰撞规则
- `PlanBUnitSimulation.unit_collision_radius` 默认及配置上限为32px；模拟器、单位圆形碰撞资源和单位快照共用该半径，碰撞外接框为64×64，中心距小于64px时进入真实碰撞/感染裁决，分离后至少留出64.5px。
- 棋盘边界、随机出生、分裂出生、点击中立查询与批次内部间距均从32px半径派生。随机出生先从带4px随机微扰的7×6格位选择安全空点，再抽取64个随机候选；空位不足时选择最近邻距离最大的候选，保持生成成功。
- 同队移动的理想间距不小于碰撞直径64px；结群加入阈值为72px、离开阈值为90px。空间网格根据有效离开距离和碰撞半径扩容，移动及碰撞分离的候选padding沿用当前逻辑。
- 30名中立加2个对手种子仍可在1024×828棋盘内优先分散出生；安全圆心区域约960×764，按圆形半径32与理想六角密排估算容量约207名，高于默认总人口上限96。出生格位与随机候选中心距离至少65px；批次继续按strength 1/2/3创建2/4/8颗。
- PB-16的64px半径已由PB-19覆盖。D 的 #275/#276 视觉工作仍独立由 D 负责：棋子逻辑直径目标为64px、中心跟随模拟位置；PopulationRibbon与事件提示移出棋盘，气泡按重叠评分避让。真实64px画面验收由 D/E 的对应任务完成。

### PB-23 玩家 S1 即时改口规则
- 玩家 S1 完整批次成功生成2颗后，A 调用 B 的 `rewrite_player_units_nearby_after_s1(center_position, word_definition, new_word_order, excluded_unit_ids) -> Array[int]`。B 排除本批新生单位，只处理落点120逻辑像素半径内、已有话语且 `word_order` 更旧的玩家单位；候选按距离升序、再按 `unit_id` 升序，最多4名。半径由 `s1_instant_rewrite_radius` 导出配置，默认120。
- B 通过 `PlanBUnit.apply_word_snapshot()` 替换完整词语快照与新顺序号，保留原阵营、`unit_id`、位置、年龄和寿命；每名改口单位复用 `unit_changed(unit_id, "relay")`，由现有 S1 改口反馈合并显示，并促使下一物理步重算同词团体拓扑。
- A 的 `player_s1_rewrite_resolved(result)` 与成功发表回执同时提供 `rewrite_count`、`rewrite_unit_ids`，包含0目标的成功S1发表。失败发表不调用改口；S2/S3只保留原有4/8颗批次及自然接触传播。

### PB-26 PK系数与T2/T4反击轮次
- Plan B 的权威 PK 系数由 `PlanBBattleHost.pk_rate_pp_per_second` 提供，试玩版默认3.0；计分公式、方向、Tier 和终局事件保持既有入口。正式 Sandbox 继续以 CombatStage 为Tier来源，Tier Catalog 中的 T1→T2 64% 和 T3→T4 79% 阈值是反击资格的唯一依据。
- C 每帧接收 A 的当前正式 Tier；首次到达Tier 2 / Tier 4 后分别锁存一轮资格，回落不清除。若首次更新已处于T4，调度仍先选T2，再选T4。每次成功消耗对应顺序轮次；失败不增加使用次数或25秒成功冷却。
- 反击请求要求己方玩家人数领先至少2名，保留1.2秒前摇与25秒成功冷却；前摇中领先条件失效或目标离场时发出带原因的失败事实，轮次仍可重新安排。无可用目标也发出单次明确结果，资格不消耗。
- `PlanBBattleHost.set_counterattack_paused(paused)` 供 PB-25 按实际教学状态暂停/恢复通用反击。暂停期间继续记录Tier资格，冻结前摇与冷却时钟；教程结束后按当前人数和剩余资格恢复。
- 前摇与结果沿用 `counterattack_windup_started` / `counterattack_resolved`，请求提供 `counterattack_round`、资格Tier、当前 `streamer_id`、`skill_id`、`skill_name_cn`、`effect_parameters`、目标ID与时间参数，供 PB-27 的专属技能效果消费。

### PB-26试玩数值与事件口径
- `PlanBBattleHost.pk_rate_pp_per_second` 默认值为3.0；正式场景当前没有另存属性覆盖。调试快照同时返回该实际属性值，PK仍只从真实阵营人数差按原公式推进。
- 反击资格使用正式Tier编号：Tier Catalog 的 `tier_1.upgrade_threshold=0.64` 让正式状态进入T2，`tier_3.upgrade_threshold=0.79` 让状态进入T4；导演不复制百分比常量。
- `opponent_config.csv` 四关统一配置领先2名、成功冷却25秒、前摇1.2秒、每局成功上限2次；T2/T4资格由正式Tier事件派生。效果失败或无目标不消耗成功次数与成功冷却。
- PB-25 的真实教程在 Sandbox 开始/结束时调用 `PlanBBattleHost.set_counterattack_paused(true/false)`。教学接线和事件约定见下方 PB-25 集成规则。

### PB-25 首关剧情教学规则
- 正式 `level_001` 使用 24 表 `tutorial_level_001` 的四个新步骤 ID：开场发表、type_c/S1 改口及克制感染、费米 type_b 剪刀发表、最终提示短暂展示。每个已完成步骤仍只写入 `SaveData.completed_tutorial_step_ids`；重开重建30名中立观众和2名费米，单位 ID/坐标不进入存档。
- `PlanBBattleHost.set_tutorial_initial_opponent_battle_type(type_a)` 将一次性类型覆写缓存到下一次 `start_battle()`，正式教学初始两名费米因此都使用 type_a。Sandbox 在第二阶段调用 PB-22 的 `request_tutorial_type_c_s1_draw()` 请求一次合法 type_c/S1；只有正式发表回执中 `rewrite_count >= 1` 才算玩家完成旧信徒改口。
- 自然接触优先完成 type_c 克制 type_a 感染。无自然成功时，Sandbox 等待2秒，再调用 `PlanBBattleHost.apply_tutorial_conversion(source_id, target_id)`；Host 只在战斗运行时转发给 Simulation，Simulation 再验证玩家/对手阵营、话语有效和真实 `_counters()` 关系，成功后发出原 `unit_changed("convert")` 与 `contact_resolved("converted")` 事实。
- 费米剪刀话语通过正式 `publish_word("opponent", type_b_word_id, position)` 成功发表，沿用正常词池、批次、显示与发表事件，不经过特殊技能次数结算。教学进行时 Sandbox 关闭普通自动发话并暂停通用反击，完播后恢复暂停前的开关状态。
- `PlanBBattleUI.set_tutorial_highlighted_battle_types([...])` 仅突出指定属性卡片，不替代固定卡槽和抽牌状态。PB-25 引导经现有 `enqueue_dialogue_sequence()` / `BubbleDialogueEntry` 以 PLOT 优先级呈现在左侧煲煲 `StreamerBubbleStack`；最终步骤等真实 `dialogue_sequence_completed` 后完成。矛盾阶段的三句蓄力提示沿用同一左侧主播气泡，进入 Final Oracle 时清除当前引导。

### PB-27 四主播专属反击效果
- `PlanBUnitSimulation.apply_counterattack_effect(request) -> Dictionary` 是四种反击效果的权威执行入口，返回 `ok/reason/effect_id/affected_count/affected_unit_ids` 与必要效果数据；A 将实际结果回传 C，C 仅在 `ok=true` 时消耗 PB-26 对应轮次。
- `alien` 分裂沿用完整快照和人口上限，最多生成2名子体；`kiwi` 按玩家现存信徒属性数量选主流属性，平局顺序为type_a→type_b→type_c，再从当前关合法未用敌方词池选择克制词，最多改写3名Kiwi单位并消费新word_id/word_order。
- `frog` 以一名现存己方信徒为施法者，将120px内最近的最多3名中立观众改为同阵营、同完整词快照；`fox` 给最多3名现存己方信徒添加一次性reflect。合法的玩家/对手感染都消费接收单位的reflect保护。
- D 消费 `counterattack_resolved` 中的技能名、影响数量、目标ID与结果消息；分裂/改口/转换/reflect仍通过现有单位更新信号和快照链展示。
