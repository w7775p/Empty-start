# Integration

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。开发前核对该表、本卡现行版、main 实际实现及最新完成日志。


Lane A 持有 Sandbox 与顶层路由接线。系统规则、倾向、历史、奖励及结局显示继续归各系统所有者。

## 2026-10-10 开发优先级：INT-09 → INT-10 → S3 依赖复核

INT-07 / INT-08 已合并，下一张 Sandbox 任务优先做 `BattleAttemptFlow`（INT-09），随后精简 Sandbox 根场景（INT-10）。策划在同时填写正式表和决定字段，详见[现行优先开发计划](../开发计划_2026-10-09_任务卡依赖整合.md)；INT-09/10 使用现有接口和 TEST_ONLY 独立配置即可开始，不等待正式四关导表。

INT-10 合并后按计划 S3 核对所有后续任务卡的真实前置、Owner 和公开事件接口，再接线 CA/CS/SD/LD/PA/UI；其他 Lane 当前已投入的独立功能和画面稿予以保留。新表字段适配、正式资源映射及 LC-10 四关联调统一安排在功能/场景稳定之后，不能将 TEST_ONLY 的整局冒烟称为正式四关联调。

## INT-09 普通战斗尝试流程（2026-10-10）

`Sandbox` 组合运行时子节点 `BattleAttemptFlow`，负责 T0～T5 单关尝试的创建、启动、推进、失败、重开和 PK 满值交接。PK、Tier、复读统计仍由同一场的 `HitResolution`、`CombatStage`、`RepeatGenerationStats` 持有；`LevelRunState` 继续持有关卡进度。没有新增 Autoload、配置类型、Scene 或 Resource。

`Sandbox.get_battle_attempt_flow()` 是后续流程和集成测试的稳定入口。流程公开事件如下：

- `attempt_started(level, hit_resolution, combat_stage, repeat_queue)`：一次尝试成功启动；每次新建或重建都会发出。
- `attempt_restarted(level, hit_resolution, combat_stage, repeat_queue)`：失败重开或 Rest 下一关完成重建后发出。
- `shot_resolved(snapshot, submission, current_tier, repeat_stats)`：有效目标移除、倾向暂存和复读计划登记完成后发出；`submission` 保留原 `HitResolution` 整发结果。
- `tier_changed(current_tier, player_pk)`、`pk_feedback_changed(player_pk, current_tier)`、`battle_state_changed(text)`：分别提供稳定档位、PK/HUD 与战斗提示事实。
- `attempt_failed(level, loss_streak_count, hit_resolution, repeat_stats)`：失败回滚已完成后发出。
- `pk_maximum_reached(level, hit_resolution, repeat_stats)`、`normal_combat_completed(level, hit_resolution, repeat_stats)`、`contradiction_entered(level, hit_resolution, repeat_stats)`：顺序标记普通 PK 满值、普通阶段结算完成及矛盾流程成功启动。

整发顺序为：`AttackChargeInput → HitResolution → CombatStage 同步更新 Tier → BattleAttemptFlow 移除命中目标 / 暂存倾向 / 登记复读 → shot_resolved → 正常阶段结束 → ContradictionOracleFlow.start`。PK 满值时立即冻结普通结算、回拉和普通生成；延迟完成回调确保最后一发的复读计划先登记。矛盾流程收到同一 `HitResolution`、`CombatStage` 与 `RepeatDelayQueue`。失败沿用原倾向、普通历史和复读历史回滚；已提交周目成果由各自原所有者保存。

阶段接线可读取 `get_current_level_profile()`、`get_hit_resolution()`、`get_combat_stage()`、`get_repeat_queue()`、`get_repeat_generation_stats()`、`get_current_tier()` 与 `is_normal_combat_active()`；`clear_pending_normal_repeats()`、`clear_barrages_for_stage_transition()`、`complete_current_level()` 提供清屏、清旧复读和下一关收尾入口。CS-18 可先清旧复读请求，再由 CS-14 调用清屏入口。

直播统计仍写入原 `SaveData.live_session`：成功生成评论继续由 Sandbox 的 `BarrageArea.barrage_generated` 入口累计，`LiveDataHud` 继续绑定同一 Resource；不新增观众、点赞或评论业务规则。Sandbox 订阅 flow 的 PK、状态与失败事件，并交给 `SandboxBattleHud` 显示。INT-01、INT-04、INT-08 和 TT-13 读取普通战斗状态时使用公开 flow getter，不再读 Sandbox 的尝试私有字段。

INT-10 直接从 `get_battle_attempt_flow()` 订阅上述事实并使用公开阶段入口；终局接线继续使用 `get_divine_descent_flow()`，矛盾/神谕继续使用 `get_contradiction_oracle_flow()`。本卡不改 INT-07/08 的流程接口、不做 INT-10，也不触碰正式 XLSX/CSV 字段或正式关卡。

## INT-08 矛盾 / 神谕与 Rest 交接（2026-10-10）

`Sandbox` 组合运行时子节点 `ContradictionOracleFlow`，持有本次 `ContradictionBreakSystem`、静音过渡 Timer、`FinalOracleSession`、选择计时和准备好的 `RestSession`。同周目确认状态由流程复用；正常重开、换关与终局均显式 `stop()`，离树作最终清理。没有增加 Autoload 或修改生产 Scene / Resource。

- `Sandbox.get_contradiction_oracle_flow()`：INT-09 的阶段组合入口。普通 PK 满值后沿用 Sandbox 的粉丝及普通复读提交，再调用流程 `start(run_data, catalog, current_level, hit_resolution, combat_stage, area, opponent_pk_bar, attack_input, repeat_queue, candidate_display, battle_config, loser_card_catalog, window_config, audio_manager) -> bool`。注入真实本场组件，所有关卡及配置保持原值。
- `advance(delta)`：仅在矛盾阶段推进本场复读队列，在候选阶段推进原十秒选择计时；暂停不推进。释放快照同步消耗一次正式机会并立即判定，飞行只保留演出。真、假矛盾均等候队列及可见复读离场；真击破再执行原 0.5 秒静音 Timer。
- `entered(system)`、`outcome_resolved(outcome)`、`oracle_opened(session)` 是阶段事实；`state_text_changed(text)` 驱动既有 HUD。Sandbox 继续转发原 `final_oracle_opened(session)`。
- `get_contradiction_system()`、`get_oracle_session()`、`get_selection_timer()`、`get_confirmation_state()` 提供同一业务对象；`is_contradiction_active()` 和 `get_result()` 用于阶段及结果读取。Rest 后保留本次神谕 Session 供核对，停止尝试时清空。
- `rest_ready(result: RestSession)` 交付已打开的同一结果对象，一次尝试通知一次。真击破结果为 `breakthrough_oracle_complete`，未击破为 `pk_win_unbroken`。Sandbox 仅调用 `RestResultView.show_result()`、转发 `rest_opened` 并保留 Continue / 下一关 / 末关神降临路由。Rest 继续从各数据所有者读取成果，查看历史和返回不发奖。

确认仍复用 `FinalOracleConfirmationState` 与 `ScriptureData.bind_confirmation_state()`：圣典先同步接收，流程核对实际经文，再依次提交普通历史、倾向、败者卡、真正击败、可继承普通池及特性白名单。返回 false 时查询接收方保存的去重事实；正式空卡目录仍沿用无新卡规则，禁止继承和矛盾池继续跳过。`HitResolution.has_committed_normal_hit_history()` 只读原提交标记。

中途写入失败发出 `commit_failed(reason)`，`get_commit_error()` 保留原因，后续奖励和 Rest 交接停止，此前合法成果保持。修复来源配置后可显式 `commit_confirmed_rewards() -> bool` 补齐当前已确认结果；重试读取原数据所有者的去重事实。普通历史与倾向仅由实际首次确认的 HitResolution 提交，同次失败重试复用其原提交标记。成功后使用 `call_deferred()` 等同步确认和攻击回调结束再交接 Rest；同帧重开会取消旧交接。已确认同关重开沿用首次候选，撤回新尝试的普通历史与倾向暂存，只补齐原奖励并读取稳定成果进入新 Rest；复用确认不触发新的神谕确认上涨。

Windows Godot 4.7.2 运行证据、准确退出码、测试入口适配及限制见 [INT-08 日志](Sandbox重构_INT-08_2026-10-10_log.md)。本次只执行 INT-08。

## INT-07 神降临流程抽取（2026-10-10）

`Sandbox` 组合运行时子节点 `DivineDescentFlow`。流程统一持有本次冻结 `DivineDescentSession`、`DivineDescentCombatMode`、子节点 `DivineDescentSpread` 及已接收的 `EndingSession`。原 DD / Ending 规则和生产配置沿用当前实现；没有新增 Autoload 或修改场景资源。

- `start(run_data, catalog, current_level, tier_catalog, hit_resolution, combat_stage, contradiction_break, area, opponent_pk_bar, attack_input, battle_config, decay_config, presentation) -> bool`：入树后调用一次，注入同场组件与完整目录。返回 true 表示已进入终局；正式演出配置缺失仍停留在已进入状态并输出提示，保持 INT-04 行为。
- `presentation` 消费 Sandbox 已有的 `repeat_interval_seconds`、`fade_seconds`、`hold_seconds`、`input_scale`、`input_return_seconds`、`trait_colors`，默认值与 TEST_ONLY 注入来源保持原值。
- `entered(session)`：冻结及普通规则关闭后同步通知 Sandbox 收起普通、神谕和 Rest 阶段；Sandbox 继续转发原 `divine_descent_entered(session)`。原始空历史延迟接收 Ending；非空历史沿用扩散、衰减归零、锁句、90% 可见占比及真实 Tween 完成顺序。
- `advance(delta)`、`handle_input(event) -> bool`：由 Sandbox 每帧及输入入口调用；暂停、停止或完成后不推进。只有实际接受的左键 / 非重复空格表现输入返回 true，Sandbox 此时消费事件。
- `completed(result: EndingSession)`：同一冻结 Session 接收成功后通知一次。`get_result()` 返回同一已接收对象，Sandbox 只调用真实 SaveManager 存盘和 `SceneRouter.goto_ending(result)`。
- `stop()`：显式停止新话生成及普通攻击，扩散子树离树并销毁，取消 Timer / Tween；中断不形成完成事实。场景离树执行最终清理。
- `Sandbox.get_divine_descent_flow()` 与流程的 `get_session()`、`get_combat_mode()`、`get_spread()` 是联调读取入口。冻结快照和可变扩散池仍通过各原组件公开 getter 读取。

Windows Godot 4.7.2 D3D12 / Forward+ 的 INT-04 两条真实 GUI 路线通过（68 checks、10 routes、DD_completed=1、退出 0），含成果存读、一次接收和节点销毁。8 个既有 DD 脚本、RS-10、EN-09 及新增流程完成 / 中断定向测试均 headless 退出 0；正式 Sandbox 直接 GUI 启动退出 0。具体过程、命令和单文件检查限制见 [INT-07 日志](Sandbox重构_INT-07_2026-10-10_log.md)。Android 实机、正式演出参数及人工操作体验仍未验收。INT-08 接手时使用上述流程接口；本卡未执行 INT-08/09/10。

## INT-04（2026-10-09）

已接通真实 MainMenu → ID-09 三页 → RS-12 开局房间 → 主动开播 → 普通关 1 → Rest → 普通关 2 → DivineDescent → Ending。

- Sandbox 在末关继续后使用同一 `DivineDescentSession`、`DivineDescentCombatMode`、`BarrageArea`。DD-15 原始历史为空时直接接收 Ending；非空时组合 Spread、新话衰减、锁句、90% 收束、DD-17 全屏强调及完成事件。
- DD-14 左键 / 空格只调用表现接口；普通攻击、PK、Tier 与矛盾规则关闭。DD-16 只消费冻结继承表现，切页销毁所属终局节点与区域。
- 完成事件只创建一次 `EndingSession.receive_final_state(session, full_catalog)`；`SceneRouter.goto_ending(ending_session)` 保留接收结果，经真实顶层切换后调用 `EndingPage.show_ending()`。终局结束调用真实 SaveManager 存盘，不追加奖励。
- `SceneRouter.game_scene_override` 默认 null，仅为显式夹具入口。生产场景与 `.tres` 引用保持原值。

### TEST_ONLY 入口与配置

`tests/integration/int_04_full_run.tscn` 是一个实景 smoke，依次跑主路线和空历史路线；其中按钮信号执行正式页面流程，真实鼠标 / 空格事件经 `Input.parse_input_event()` 进入游戏。PK 满值及失败使用已有 debug API；矛盾与神谕选择必须通过真正蓄力、释放和 Timer。

`int_04_test_only_sandbox.tscn/.gd` 复用现有双关目录与 FO-11 夹具，仅深拷贝到内存后适配测试主播 ID、两关继承池与卡片。注入短攻击计时、3 条矛盾复读 / 0.3 秒寿命、普通复读 0.6 秒、每关粉丝 +7、静止移动、新话衰减 1 秒、自动复读间隔 0.1 秒、淡变 0.15 秒 / 停留 0.6 秒、输入 1.35 倍 / 0.2 秒及 occlusion 青色。数值均为联调占位；正式身份仍读取批准的十二卡。

正式演出参数未交付，Sandbox 的间隔、全屏时长及输入参数默认 0。非空历史到此会输出配置待交付提示，须显式注入夹具或未来批准值；原始空历史可直接 Ending。正式第二关内容、奖励配表、教名、判词、主图及特性配色继续待所属 Owner 交付，不能据 TEST_ONLY PASS 宣称正式版本内容完整。

### 运行与边界

指定基线 `1b84c098` 的 Godot 4.7.2 Windows D3D12 / Forward+ 实际 SceneTree 完成两条路线、真实磁盘存读、重开及去重检查，退出 0。运行期间曾发现 CA-12 旧输入代码在隐藏 GUI 中的准心跳位回归；现已由 #103 修复并合并。2026-10-09 12:16 基于最新 main 5ee1eff（合并 #103）的完整隔离工程已重新导入并实测：Godot 4.7.2 Windows D3D12 两条顶层流程全部通过，实际进程 ExitCode 0，62 checks、10 routes、DD_completed=1，stdout/stderr 存在本 evidence 目录 latest_main_pass_*。旧失败记录仅留作追溯，不代表当前阻断。详见 [INT-04 日志](./INT-04_2026-10-09_log.md) 和 `evidence/INT-04_2026-10-09/`。

保护用户存档的复现方式：在忽略目录复制当前工程与这四个集成测试文件，关闭副本的编辑器 MCP 插件，仅将副本 SaveManager 的 `SAVE_PATH` 改为 `res://.godot/int04_save.res`；函数体保持原值。导入完成后运行：

```text
godot.windows.opt.tools.64.exe --path <隔离项目绝对路径> res://tests/integration/int_04_full_run.tscn --resolution 1152x648 --quit-after 9000 --log-file <可写绝对日志路径>
```

等待真实子进程，要求退出 0、两行 `INT04 ROUTE PASS`、最终 `PASS INT-04`，同时检查错误日志。最终证据包含已有根证书及用户 settings.cfg 写入权限错误；没有 GDScript / 资源加载 / INT-04 断言错误。Sandbox 单脚本 check-only 因该模式缺少 SaveManager 全局标识退出 1（KT-25），其实际编译运行已由实景验证；SceneRouter check-only 退出 0，原 DD-15 / EN-09 回归各 1/1 PASS。

早期空经文截图在布局稳定前裁切标题；补齐输入抬起并等待布局稳定后，最终两条路线标题 Y=24、scroll=0，截图完整，无 Ending 源码修改。Android 设备、打包、正式美术与平衡、音频听感及完整人工操作体验均 UNVERIFIED。

## INT-06 中央战斗区全高与操作 ICON（待开发）

[INT-06 单功能程序任务卡](tasks/INT-06_battle-area-full-height-and-input-icon-overlay.md)：中央顶部保持 1024×72，中央 `BarrageArea` 调整为 1024×1008；旧底部交互栏空间归还弹幕场；中央战斗区左下角悬浮鼠标左键、ESC 两枚竖排操作 ICON。现有攻击进度与阶段程序入口继续提供给后续正式美术蓄力反馈，场景布局及 Paradox/神谕中央目标显示随之统一。该布局更新覆盖旧 INT-02 的中央 760px 弹幕区和 248px 底部区设计基线。
