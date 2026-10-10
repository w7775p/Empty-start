# 18. Rest 休息时刻系统任务拆分

## 系统目标

休息时刻系统负责新周目开局房间，以及一场直播结束后的结算与过渡。

它读取本场结果，展示已经真正提交的成果，并决定：

- 还有下一名主播时，进入下一关；
- 普通关卡全部完成时，进入神降临。

它还提供历史经文、败者卡查看入口，以及当前倾向对应的房间表现。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| RS-01 | 接收并保存本场结果快照 | 无 |
| RS-02 | 未击破分支说明 | 无 |
| RS-03 | 读取本场新增圣典 / 卡片 / 吞并 | 无新增自动化测试 |
| RS-04 | 空奖励状态 | 无 |
| RS-05 | 历史圣典查看入口 | 无新增自动化测试 |
| RS-06 | 历史败者卡查看入口 | 无新增自动化测试 |
| RS-07 | 根据倾向切换房间表现 | 无新增自动化测试 |
| RS-08 | 重复打开只读取已有结果 | 1 个关键单元测试 |
| RS-09 | 进入下一普通关 | 1 个关键单元测试 |
| RS-10 | 普通关结束后进入神降临 | 1 个关键单元测试 |
| RS-11 | 结算结束后切换输入 | 无 |
| RS-12 | 新周目直接进入休息时刻的主角房间（开局入口） | 实际流程 smoke，无新增纯逻辑单测 |

## 测试预算

只保留 3 个关键纯逻辑 case：

- 同一份结算重复打开不会再次提交奖励；
- 还有普通关时选择下一关；
- 普通关全部结束时选择神降临。

UI、空态、历史查看、环境变化和输入切换全部做实际运行联调。

## RS-11：结算展示与菜单输入边界

`RestResultView.show_result()` 进入展示阶段时禁用继续、圣典与败者卡按钮，释放旧焦点，拦截输入事件；对应回调也检查阶段，避免直接发出按钮信号绕过。展示结束后才恢复符合资料上下文的按钮与继续焦点。查看历史及返回不会恢复战斗攻击，重复打开继续只读取既有成果。

现有结果页面为静态展示，没有正式演出时长；默认在下一布局帧调用 `finish_result_performance()`。后续演出可使用新增的第五参数 `wait_for_performance = true`，完成时显式调用该接口；`result_performance_finished` 只通知已结束事实。关闭 / 重开会使旧静态等待失效，隐藏时报告完成无效，重复完成不会重复通知。没有补写正式动画、文案或平衡配置。

INT-08 真实回归补齐离树清理：`RestResultView._exit_tree()` 撤销当前展示标记和等待编号，旧布局帧回调不会在关卡重开或场景移除后访问控件焦点。正常关闭仍使用 `hide_result()`；离树只取消等待，避免子控件已离树后再访问空 Viewport。验证见 Integration 的 INT-08 日志。

准心通过公开 `configure_battle_aim(aim: AimReticle)` 注入。Rest 显示期间暂停其输入处理，历史面板保持原生悬停、点击和滚动；`hide_result()` 恢复准心进入前的处理状态。蓄力 / 发射仍由 Sandbox 原有 `set_combat_active(false)` / `lock_new_attacks()` 路径负责，菜单解锁不会调用攻击启用接口。按 [Godot 输入事件文档](https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html)，在 `_input()` 消费移动会同时阻断 GUI，因此菜单阶段保留完整事件传递。

**Lane A 集成完成（2026-10-09，PR #78 补做）**：正式 Sandbox 在 `_ready()` 中创建 Rest 页面并 `add_child()` 后调用一次以下接口。重开及继续路由复用该实例，保留原有唯一的继续信号连接。

```gdscript
_rest_result_view.configure_battle_aim(_aim_reticle)
```

RS-11 没有新增永久单测、Scene 或 Resource。Lane B 已完成 UI 与既有 RS-08 / 09 / 10 单测验收；Lane A 补做使用真实 Godot 4.7.2 D3D12 运行正式 Sandbox，只注入现有 TEST_ONLY 双关目录及临时演出控制，验证展示锁定、完成开放、圣典 / 卡片查看返回、准心冻结、攻击关闭、隐藏 / 重开恢复、旧展示等待隔离、下一关和 RS-10 唯一神降临入口，同时复验 CS-11 满 PK 冻结。实际输出 `RS11_INTEGRATION_REAL_SCENE_PASS`、退出码 0；权限环境错误与证据路径见 `休息时刻系统_RS-11_2026-10-09_log.md`。

## 依赖顺序

RS-01～02 等 12. ContradictionBreak / 13. FinalOracle 结果。
RS-03 等 14/15/16。
RS-05～06 等 15/16。
RS-07 等 17. ThreeTendencies。
RS-09 等 2. LevelConfiguration。
RS-10 等 19. DivineDescent。
RS-12 等身份系统 ID-09 的三步开局确认，并复用已完成的 RS-07 房间环境。它是开局进入房间的入口，与战后 RS-01～11 结算入口分开处理。

RS-01 已增加 `RestSession.open_result(result_snapshot)` 作为本场结果入口。快照包含来源 `level_id` 与 `result_kind`（`pk_win_unbroken` 或 `breakthrough_oracle_complete`）；会话只接受首次打开，读取方使用 `get_result_snapshot()` 获得深拷贝。

RS-02 为 `pk_win_unbroken` 增加专属结果面板，显示 PK 胜利但矛盾未击破、没有神谕或击败奖励，并发出继续请求。Sandbox 接收继续请求并处理 RS-09 路由，接受一次后发出 `rest_continue_requested(session)` 通知。

RS-03 增加 `RestSession.read_committed_rewards(save_data, level_catalog, loser_card_catalog)`：经文按当前 `level_id` 读取 `ScriptureData.get_entry_for_level()`；吞并用同一 Session 的 `level_id` 和真实 LevelCatalog 对应的 `streamer_id` 调用 `AssimilationData.get_new_content_for_source()`，返回 `new_assimilation` 快照。未打开、未击破、缺少关卡 / 来源或无新增时该字段为 `{}`。Rest 不保存来源映射或计算总量差值，需要总量的消费方使用 14 的 `get_current_content_snapshot()`。

RS-03 已接入 LCARD-07 正式只读入口 `SaveData.loser_card_data.get_new_card_for_level(level_id, loser_card_catalog)`：来源归 16 判断，本场无新增为 `{}`，Rest 映射为 `new_loser_card = null`；正式发卡但 Catalog 缺失时仍能得到主播 ID 与 `profile = null`。败者卡读取不依赖 LevelCatalog，后者仅用于解析吞并的同关主播来源；所有读取均不发奖或改写已提交结果。

RS-04 在现有 `RestResultView` 增加 `show_result(session, save_data, level_catalog, loser_card_catalog)`。三类本场成果均为空时显示“本场没有新增经文、败者卡或吞并内容”；历史经文和败者卡分别复用 `get_ordered_entries()` / `get_acquired_cards()` 判断空集合，在同一面板显示可读提示。缺少数据时不推断历史为空，已有卡片但 Catalog 缺失也保留其非空事实。继续按钮始终可用，仍发出 `continue_requested`；Sandbox 的未击破入口传入真实周目与目录并保留原信号转发。两类历史查看由 RS-05 / RS-06 接入，下一关路由已由 RS-09 接入。

RS-09 增加 `RestSession.continue_to_next_level(run_state) -> LevelRunState.CompletionResult`：只从本场已冻结结果读取 `level_id`，调用关卡所有者的 `complete_level(level_id)`；存在下一普通关时返回 `ADVANCED`，重复提交沿用 `ALREADY_COMPLETED`，Rest 不另存进度或去重记录。

Sandbox 在 `ADVANCED` 时复用 `restart_current_attempt()`，按新的当前 LevelProfile 重建普通战斗；清理旧弹幕、队列、输入、神谕、矛盾、休息界面及未提交暂存，并通过 `OpponentPKBar.complete_current_level()` 清除旧关连败。继续沿用同一 SaveData，入关粉丝基数读取当前已入账粉丝，经文 / 败者卡 / 吞并等已提交成果保留。`level_catalog` 为可注入的现有关卡目录 Resource，运行状态、经文来源与 Rest 展示统一读取它。

重复点击继续时，重建后的当前 Rest 绑定已清空；重复提交旧结果也由 LevelRunState 拒绝，均不会跳过下一关。最后一普通关返回 `ALL_NORMAL_LEVELS_COMPLETED` 时由 RS-10 进入真实神降临 Session。FO-12 已将成功确认并提交奖励后的 `breakthrough_oracle_complete` 接到同一 Rest 入口，既有 `read_committed_rewards()` 从真实周目 / 目录只读获取成果，Continue 继续复用 RS-09。正式 `level_002.tres` 目前只有基础信息，词库 / 矛盾内容仍待补齐；TEST_ONLY 切关 smoke 不代表第二关正式可玩。

RS-10 在末关 Continue 后调用 `DivineDescentSession.enter(SaveManager.data)`，持有首次冻结的倾向、经文、普通命中 / 复读历史、候选和吞并快照；原 SaveData 的粉丝与败者卡等成果保持。随后组合既有 `DivineDescentCombatMode.enter_terminal_mode()` 固定 Tier 5、禁用普通 PK / 升降档 / 矛盾并停止回拉，清理旧攻击、弹幕、候选与休息界面，发出一次 `Sandbox.divine_descent_entered(session)`。

末关连点由原关卡去重和当前 Rest 绑定清空阻止再次进入；终局 Session 存在时普通重开入口拒绝恢复战斗。RS-10 只接通真实 19 入口及规则边界，扩散、衰减、锁句、空历史后续分支和结局转场仍留对应演出卡。

RS-05 在结果面板增加“查看历史圣典”，沿用 `show_result()` 传入的 `SaveData.scripture_data` 与 `LevelCatalog`。组合子场景 `ui/rest/scripture_history_view.tscn` 的 `show_history(scripture_data, level_catalog)` 只读数据，复用 `EndingScriptureDisplayData.build_from_scripture()` → `ScriptureData.get_chapter_slots()` 和 `EndingScriptureRow` 显示原章号、固定节号、主播、正式原文及“未形成神谕”的缺章；暂存 `pending_entry` 不作为正式经文展示。章节规则仍由 15 持有，Rest 没有新增历史数据层。

历史为空时保留清楚的空提示与缺章行，空目录另行提示；缺少 SaveData / ScriptureData / LevelCatalog 时显示“历史圣典资料暂不可用”并禁用查看入口，避免将未知资料视为空收藏。子面板沿用项目 Theme，长文本自动换行并使用原生 ScrollContainer 纵向滚动，返回按钮固定在滚动区外。返回请求恢复原结果面板与按钮焦点，原继续信号保持可用；重新显示或隐藏结果时同步收起历史面板。Sandbox 已有上下文足够，本卡无需修改其接线。

RS-06 在同一结果面板增加“查看历史败者卡”，与圣典入口并排，沿用 `show_result()` 传入的 `SaveData.loser_card_data` / `LoserCardCatalog`。子场景 `ui/rest/loser_card_history_view.tscn` 的 `show_history(loser_card_data, catalog)` 调用正式 `get_acquired_cards(catalog)`，按其返回顺序组合 `LoserCardHistoryRow`，展示 Profile 中的真实主播名、卡面和完整文案；获得与排序规则继续归 16，Rest 没有新增收藏或奖励登记。

有效获卡数据返回空数组时显示“暂无已获卡片”；目录为 null、空目录或某个档案缺失时保留正式读取接口返回的已获主播 ID，并清楚提示档案暂缺。Profile 存在但卡面 / 文案缺少时也显示对应缺资料提示，不合成素材。缺少 SaveData / LoserCardData 属于上下文不可用，禁用查看入口且保留继续按钮；缺少卡片目录仍允许查看已获记录，和空收藏区分。卡片页沿用项目 Theme，长文换行、原生纵向滚动，固定返回按钮恢复原面板与败者卡入口焦点；圣典查看与原继续信号保留，两个子面板互斥显示。Sandbox 接线继续由 Lane A 持有，本卡无需修改。

RS-08 已核实并保护现有重复查看路径：用同一所属周目 SaveData、冻结 `level_id` 的 RestSession 与目录重新调用 `RestResultView.show_result()`，每次仅通过 `read_committed_rewards()` 和历史 getter 刷新界面。`show_result()` / `hide_result()` 不调用奖励提交或关卡推进，也不发出继续信号；重复 `open_result()` 保留首次结果快照。界面重新实例化后读取同一场已提交记录仍保持成果数量与固定节号。

只有显式继续才调用 `RestSession.continue_to_next_level(run_state)`；同一周目的 LevelRunState 已完成该 `level_id` 后，再次提交旧结果返回 `ALREADY_COMPLETED`，当前关保持原值。重复保护继续归 14 / 15 / 16 与关卡所有者，Rest 不增加第二套奖励 / 推进记录。`tests/unit/rest/test_rs_08_reopen_idempotent.gd` 只含一个关键用例，验证重复接收 / 读取、成果不增加、固定节号不变、显式推进后重开旧结果也无法额外推进。实际 UI 重开及圣典 / 败者卡返回流程另用临时 Godot 场景 smoke 验证。

## RS-07：同一房间按倾向改变装饰与光照

休息结果页面复用 `res://assets/environment/rooms/player_room_01.png` 的单间背景，环境独立子场景 `ui/rest/rest_room_environment.tscn` 仅切换背景调色、覆盖光照、左右装饰块与符号：正统暖金/对称，异端冷紫/倾斜，荒谬霓虹双色/错位。当前颜色、图形和符号仅为可替换的开发期视觉占位；后续美术可只替换 RoomEnvironment 内的贴图与装饰，无需改变 Rest 结算逻辑或三种背景。

`RestResultView.show_result()` 只读取当前周目 `SaveData.tendency_state.get_primary_tendency_id()`，直接沿用 17 的开局全零和主导并列裁决；不接触累计值或本场暂存。缺有效上下文时使用不带倾向装饰的中性房间，`hide_result()` 同步复位。环境子节点均不接收鼠标，结果面板、圣典、败者卡、返回和继续信号仍沿用原 UI 接线。RS-07 不新增永久自动化单测；开发临时场景已做真实 Godot 4.7.2 UI 交互 Smoke，详见日期日志。

## RS-12：新周目开局房间（2026-10-09）

新周目先经过 ID-09 的「主播取名 → 12 身份卡 → 粉丝团取名」，正式确认并保存后，先进入主角房间。房间复用 `RestRoomEnvironment` 和 RS-07 当前已实现的三倾向装饰及光照；以开局身份的倾向显示初始房间状态，等待玩家点击「开始直播」后才启动第一普通关。开局此时无已完成关卡，也没有战后 `RestSession` 结果。首次房间入口与战后结算入口明确区分，详见 `tasks/RS-12_new-run-opening-room.md`。

独立顶层场景 `ui/rest/rest_opening_room.tscn/.gd` 只读 `SaveManager.data` 的已确认主播名、粉丝团名及 `tendency_state.get_primary_tendency_id()`；直接组合现有 `rest_room_environment.tscn`，使用同一 `player_room_01.png`。页面只有开局提示与“开始直播”，没有战后成果、历史或关卡完成操作。资料缺失时展示明确提示并禁用开播，直接启动不会生成新周目。三倾向装饰继续采用 RS-07 开发期视觉占位；本卡修正共享背景 TextureRect 的无效 `stretch_mode = 7` 为 `STRETCH_KEEP_ASPECT_COVERED = 6`，开局与战后页面均能显示真实底图。

ID-09 页面在 `_ready()` 连接自身 `opening_saved(run_data)` 到 `_on_opening_saved()`，保存成功后请求 `SceneRouter.goto_opening_room() -> Error`。路由失败时保留已保存身份，按钮只重试房间跳转；成功期间保持忙碌标记。开局房间 `start_live() -> Error` 只在显式按钮请求后调用现有 `SceneRouter.goto_game()`，第一次成功后锁住页面，后续调用返回 `ERR_ALREADY_IN_USE`；切换失败可重试，周目对象变化时拒绝启动。

**Lane A 交接**：Sandbox 原样保留。独立房间期间没有 Sandbox、AttackChargeInput、AimReticle、PK 回拉或弹幕节点；开播后才实例化正式 Sandbox，由其既有 `_ready()` → `restart_current_attempt()` 初始化第一关。共享 SceneRouter 仅增加 `OPENING_ROOM_SCENE_PATH` 和 `goto_opening_room()`，原游戏/重开路由保持。集成时 A 保留此入口和 ID-09 信号接收，不再叠加自动开播或另一份房间路由；当前无需 A 补接。

实际 Godot 4.7.2 GUI smoke 已覆盖三倾向各一张正式身份、三步输入保存及磁盘读回、点击前零战斗节点、主动开播、同帧重复请求、房间/开播失败重试、战斗蓄力恢复，以及 TEST_ONLY 双关未击破 Rest → 下一关 → 神降临入口。证据与环境权限日志见 `休息时刻系统_RS-12_2026-10-09_log.md`。未新增永久纯逻辑单测；Android 和正式美术仍待验收。

## LD-10：本场直播结果展示

结果页面新增 `LiveResult` 文本标签，展示真实观看、点赞、评论、本场粉丝增量和总粉丝。`show_result()` 首次调用 `RestSession.capture_live_result(run_data)` 从直播数据公开 getter 冻结数值，随后 `get_live_result_snapshot()` 只返回副本。冻结值属于当前 RestSession；重复查看及重新创建页面均读取同一场结果，跨关也保持原值。页面没有粉丝入账入口，缺数据 / 缺历史增量明确提示。

现有 Sandbox 未击破与神谕成功分支已经传入真实 SaveData，本卡无需 Lane A 补接。直播增量记录归 9 系统并随原存档保存，Rest 只持有显示时的不可变快照；快照不作为跨进程历史存档。短时上涨继续沿用 LD-06，结果快照固定在首次显示时。接口与验收证据见 9 系统 README 和 LD-10 日期日志。原输入切换、历史查看、继续及房间环境保持现有行为。
