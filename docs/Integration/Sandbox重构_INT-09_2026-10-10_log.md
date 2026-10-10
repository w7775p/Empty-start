# Sandbox 重构 INT-09 任务日志（2026-10-10）

## 范围与基线

只执行 INT-09，分支 `codex/lane-a-int09-1010`。开工时工作树干净，HEAD 为用户指定基线 `001d3f525dc7f2ed6f6fa47092a0de9e080a24af`。任务期间本地 `origin/main` 跟踪引用前进到 `41d2e413ec12741cd46319bc4c1bf662daf7b233`，比该基线多 `#126` / `#133` 两笔提交；这两笔未改本卡的 Sandbox、核心流程或集成测试文件。

本次只提取 T0～T5 普通尝试流程。INT-07 `DivineDescentFlow`、INT-08 `ContradictionOracleFlow`、顶层路由、TEST_ONLY 关卡和战斗数值配置沿用原行为；没有处理 INT-10、CA-15、正式四关或 XLSX/CSV 字段。

## 实现与接口

- `core/combat/battle_attempt_flow.gd`：新增场景组合 Node。它创建并启动本场 `HitResolution`、`CombatStage`、`RepeatDelayQueue`，接入现有 `BarrageArea`、`AttackChargeInput`、`OpponentPKBar`、`LevelRunState` 和 `ContradictionOracleFlow`，处理普通发射到达、目标移除、倾向暂存、复读登记、失败回滚、重开、PK 满值及阶段交接。
- `scenes/sandbox/sandbox.gd`：只组合流程、接 Rest/顶层路由、保存和展示数据；新增 `get_battle_attempt_flow()` 与 `get_rest_result_view()`。普通 PK/Tier/复读/失败实现从 Sandbox 移出。INT-07/08 getter 和流程接口保持原名及参数。
- `BattleAttemptFlow` 公开事件：`attempt_started`、`attempt_restarted`、`shot_resolved`、`tier_changed`、`pk_feedback_changed`、`battle_state_changed`、`attempt_failed`、`pk_maximum_reached`、`normal_combat_completed`、`contradiction_entered`。尝试及结算事件携带现有 `LevelProfile`、`HitResolution`、`CombatStage`、`RepeatDelayQueue` 或 `RepeatGenerationStats`，不创建第二份业务状态。
- 阶段读取入口：`get_current_level_profile()`、`get_hit_resolution()`、`get_combat_stage()`、`get_repeat_queue()`、`get_repeat_generation_stats()`、`get_opponent_pk_bar()`、`get_barrage_area()`、`get_attack_input()`、`get_aim_reticle()`、`get_current_tier()`、`is_normal_combat_active()`。阶段动作入口：`clear_pending_normal_repeats()`、`clear_barrages_for_stage_transition()`、`complete_current_level()`。
- 整发顺序：`HitResolution` 同步通知 `CombatStage` 更新 Tier，随后 flow 处理每个目标并按新 Tier 登记复读计划，再发出 `shot_resolved`。满值先冻结普通 PK、回拉与生成，等整发回调返回后提交现有粉丝与复读历史，并把同一组状态交给 `ContradictionOracleFlow.start()`。成功启动后发出 `contradiction_entered`。
- 直播统计继续使用 `SaveData.live_session`。成功弹幕生成仍由 `BarrageArea.barrage_generated` 统计评论，`LiveDataHud` 继续绑定原 Resource；Sandbox 把 flow 的 PK、状态及失败事件交给 `SandboxBattleHud`。没有新直播规则。
- `tests/integration/int_01_playable_battle_sandbox_test.gd`：改用 flow getter，验证命中事件携带更新后的 Tier/同一复读统计，以及 Tier、失败、重开、PK 满值、正常结束和矛盾进入事件。
- `tests/integration/int_04_full_run.gd`、`int_08_flow_test.gd`：普通战斗状态改读公开 flow getter；INT-04 用公开候选显示节点读取候选目标。
- `tests/integration/tt_13_neutral_sandbox_test.gd`：在 Sandbox 入树前注入 TEST_ONLY `LevelCatalog`，改用 flow 查询尝试状态。
- `docs/Integration/README.md`：记录职责、事件顺序及 INT-10 使用入口。

无 `.tscn`、`.tres`、`project.godot`、生产表或 `known_traps.md` 改动。没有新增测试框架、baseline、hash、contract 或 gate。

## Windows Godot 验证

引擎为 `D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`，版本 `4.7.2.stable.steam.ed1daf0bf`。GUI 路线使用 D3D12 12_0 / Forward+、AMD Radeon(TM) Graphics、1152×648；输入来自测试脚本的 `Input.parse_input_event()` 和既有 Button 信号，属于合成输入。存档和设置仅写入隔离副本 `.godot/int09/project`，副本关闭 MCP 编辑器插件、移除 `MCPRuntimeProbe` Autoload，并改用项目内测试路径。原工程 SaveData / Settings 配置保持原值。

| 验证 | 实际结果 | stderr |
| --- | --- | --- |
| 隔离副本 Godot editor import | exit 0；`BattleAttemptFlow` 注册，资产导入完成 | 根证书读取失败、首轮 8 个音频加载提示、CSV locale 提示、Steam 安装目录 editor_settings 写入被拒；无脚本解析错误，详见 evidence 原始输出 |
| `BattleAttemptFlow` `--check-only --script` | exit 0 | 空 |
| INT-01 Windows GUI | `INT-01 PASS: 85 checks`，exit 0 | 根证书读取失败提示 |
| INT-04 Windows GUI | `PASS INT-04 full run checks=96 top_level_routes=10 DD_completed=1`；两条 empty_history 路线 PASS；exit 0 | 根证书读取失败提示 |
| INT-08 flow Windows GUI | `PASS INT-08 flow checks=23 rest_ready=3 expected_failures=1`，exit 0 | 根证书提示，加测试有意触发的一次普通词库继承写入失败 |
| TT-13 neutral Windows GUI | `PASS TT-13 Sandbox: neutral generated, hit, repeated, recorded without tendency`，exit 0 | 根证书读取失败提示 |

INT-04 实际截图保存在 `evidence/INT-09_2026-10-10/`，并已查看普通 Rest、空 Ending 和全屏强调画面。首次 INT-04 尝试发现测试变量作用域错误（`attempt_flow` 声明在循环内，循环外仍读取），该次进程 exit -1；变量移到外层后，完整整局再次运行通过。最初未加 `--editor` 的 isolated import 运行停在首轮文件扫描，手动终止 exit -1；随后按 Godot CLI 帮助指定 `--editor --import` 完成正式导入。两个准备过程及最终运行的原始 stdout/stderr 均收录于 evidence。

另有一次在目标工作树直接执行 `--headless --path <worktree> --import` 的准备探针；启用 MCP 编辑器插件时进程停在首轮文件扫描并输出根证书/未缓存音频提示，手动终止时没有捕获准确退出码。它不是验收结果。该探针只改动了 `addons/godot_mcp/icon.svg.import` 的换行，已恢复；新 `.godot` 缓存和自动生成的忽略态 UID 留在本机工作树。

**尚未执行：**物理键鼠验收、Android 实机、正式四关资源绑定、正式数值表适配。上述 GUI 的输入是合成事件。

## Git、文档与交接

`git diff --check` 在最终提交前执行。工作树的 `.git` 文件指向 `D:/Godot/Empty-start/.git/worktrees/Empty-start90`，该目录位于本会话唯一可写根目录之外。尝试把分支快进到 `origin/main` 时，Git 创建 `rebase-merge` 目录收到 `Permission denied`；清理导入换行差异时，`git restore` 创建 `index.lock` 被拒。最终 `git add` 也以 exit 128 失败，准确报错为 `Unable to create 'D:/Godot/Empty-start/.git/worktrees/Empty-start90/index.lock': Permission denied`。分支仍为 `codex/lane-a-int09-1010`、HEAD `001d3f5`，相对本地跟踪的 `origin/main 41d2e41` 落后 2 笔；没有 commit、push 或 PR。代码、README、任务日志和证据完整留在目标 worktree，未用其他工作树代替。

`known_traps.md` 未更新：沿用 KT-25、KT-27、KT-34、KT-36；Godot 导入提示属于已记录环境限制。本次更新 Integration README，没有改 `docs/Original/`。INT-10 接手从本 README 和本日志开始，使用 `Sandbox.get_battle_attempt_flow()` 订阅尝试、整发、Tier、失败、重开及矛盾进入事件；现有 `get_contradiction_oracle_flow()` 与 `get_divine_descent_flow()` 保持原接线。需先获得当前 worktree Git 元数据目录的写权限，再基于最新 `origin/main` rebase、复跑两条 GUI 回归并提交/推送/开 PR。

## 2026-10-10 总控复测补充

- Windows Godot 4.7.2 隔离 GUI INT-04 再次通过 96 checks、10 routes。
- INT-01 首次复测为 84/85，唯一失败位于普通弹幕持续生成的固定 1.08 秒等待边界；同一隔离工程重跑则 85/85 通过。
- 该检查的正式关卡间隔为 1.0 秒，等待余量 0.08 秒容易遇到帧调度误差。本 PR 仅将这一条测试等待改为 1.50 秒，保留继续生成功能断言。
