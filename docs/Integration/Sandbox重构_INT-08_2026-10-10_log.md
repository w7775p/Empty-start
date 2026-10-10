# Sandbox 重构 INT-08 任务日志（2026-10-10）

## 范围与结果

只执行 `INT-08_extract_contradiction_oracle_flow.md`，分支 `codex/lane-a-int08-1010`。开工 HEAD 与当时远端 main 均为 `0963dc5ff79da2b28e27d11a29ddf4dec80f02e9`，包含已合并 INT-07。结束前获取到 main `09c7362`；新增部分仅为 MCP 验收和音乐 TODO 文档，代码与资源没有变化。提交后将本分支变基到该目标。开工已有的 6 个 `.import` 修改保留，未纳入本任务提交。

已阅读 AGENTS、known_traps、project.godot、原任务卡模板、Integration README、INT-04 卡与日志、INT-07 卡与完成日志、整合依赖计划、12/13/14/15/16/18 系统 README，并核对真实 Sandbox、攻击、确认、Scripture、奖励、Rest 与测试源码。只使用既有 Godot Node、signal、Timer、call_deferred 和各业务所有者接口。

使用 `global-work-rules`；GUI 观察使用 `computer-use`；编辑器与 API 分别使用 Godot Native / Docs MCP。Native `get_project_info` 两次返回 `C:/Users/lvy/.codex/worktrees/lane-a-int08-1010/Empty-start/`，对应进程命令行明确含 `--mcp-port=19081`。19080 主工程服务没有操作。Docs 的 `lookup_method(class_name="Node", method="add_child")` 返回真实签名、子树生命周期和 owner 说明。隔离 Native 可用，本次无 Native 不可用降级；纯脚本直接编辑，运行验证采用 CLI 与隔离存读路径。

## 实现与交接

- `core/contradiction_oracle/contradiction_oracle_flow.gd`：统一持有矛盾系统、静音 Timer、神谕 Session、选择计时、同周目确认状态、当前 Rest 结果。`start(...)` 注入本场真实组件；`advance(delta)` 推进矛盾复读与候选计时；`stop()` 停窗口、清等待、断攻击信号、移除临时子节点并取消旧帧尾交接。
- 原十秒 / 一发、释放快照同步判定、真/假矛盾复读、队列与可见实例结束条件、0.5 秒静音、手动和超时排序均复用原实现。`entered` / `outcome_resolved` / `oracle_opened` 交付阶段事实；`state_text_changed` 接既有 HUD。
- `rest_ready(result: RestSession)` 在成果已保存且结果已打开后交付一次同一对象。成功为 `breakthrough_oracle_complete`，未击破为 `pk_win_unbroken`。Sandbox 只显示 Rest、转发原通知、接 Continue、推进下一关及发起 INT-07 神降临。
- 确认仍由 `FinalOracleConfirmationState` 固定一次，Scripture 先同步接收；流程核对保存经文，再依次处理普通历史、倾向、卡片、真正击败、普通继承池与白名单特性。接收方 false 返回通过其已有保存事实区分去重与失败。正式卡目录缺资料、禁止继承及矛盾池继续沿用无新增规则。
- `commit_failed(reason)` 与 `get_commit_error()` 报告中途拒绝；后续奖励和 Rest 停止，此前合法成果保留。来源修复后 `commit_confirmed_rewards()` 补齐同一已确认结果，历史、卡片及吞并仍由各原所有者去重。`HitResolution.has_committed_normal_hit_history()` 只读取原提交标记。
- 成功 Rest 采用帧尾交接，重开使旧 Session 请求失效。已确认同关重开复用首份候选、核验成果并交付新尝试的 Rest。Rest 后可通过流程读取同一神谕 Session，stop 时清空。
- `RestResultView._exit_tree()` 取消静态展示等待，修复实景回归中离树后旧回调抢焦点的错误。这里只取消等待标记，不访问已经离树的 Viewport。
- INT-01 / INT-04 改用公开流程对象和真实 Rest 结果；数据导出既有 smoke 同步迁移读取入口。新增 `int_08_flow_test.gd/.tscn` 仅覆盖抽取后的提交失败、补齐与旧交接取消边界，没有新增 Autoload 或生产配置。

INT-09 使用 `Sandbox.get_contradiction_oracle_flow()` 与 `start(run_data, catalog, current_level, hit_resolution, combat_stage, area, opponent_pk_bar, attack_input, repeat_queue, candidate_display, battle_config, loser_card_catalog, window_config, audio_manager)`。完整职责和 getter 见 Integration README。粉丝及普通复读胜利入账仍留当前 Sandbox，继续请求与终局路由继续归 Sandbox / SceneRouter。本任务未执行 INT-09/10。

## 实际运行方法

引擎 `D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`，实际版本 `4.7.2.stable.steam.ed1daf0bf`。GUI 使用 Windows D3D12 / Forward+，1152×648。每个进程用 `Start-Process -WindowStyle Hidden -Wait -PassThru` 启动，记录实际 `ExitCode`，分别保存 stdout、stderr 与 Godot log-file；没有用外层 PowerShell 退出码代替 Godot。

运行项目为忽略目录 `.godot/int08/project/`：复制当前工程与本任务文件，仅在副本关闭编辑器 MCP 插件，将 SaveManager 路径改为 `res://.godot/int08_save.res`、SettingsManager 路径改为 `res://.godot/int08_settings.cfg`。函数体保持原值；完整 Autoload 在正式验收前恢复。真实 SaveManager / ResourceSaver / ResourceLoader 完成存读，个人存档和设置保持原值。

```text
godot.windows.opt.tools.64.exe --path <隔离项目> res://tests/integration/int_01_playable_battle_sandbox_test.tscn --resolution 1152x648 --quit-after 9000 --log-file <int01日志>
godot.windows.opt.tools.64.exe --path <隔离项目> res://tests/integration/int_04_full_run.tscn --resolution 1152x648 --quit-after 9000 --log-file <int04日志>
godot.windows.opt.tools.64.exe --path <隔离项目> res://tests/integration/int_08_flow_test.tscn --resolution 1152x648 --quit-after 9000 --log-file <int08日志>
godot.windows.opt.tools.64.exe --headless --path <隔离项目> --script res://tests/unit/<测试脚本> --log-file <测试日志>
godot.windows.opt.tools.64.exe --headless --path <隔离项目> --check-only --script <目标脚本> --log-file <解析日志>
```

准确退出码的全部运行记录见 [exit_codes.json](evidence/INT-08_2026-10-10/exit_codes.json)。最终 stdout / stderr 与两个已查看的 GUI 截图保存在同目录；完整准备、失败及引擎日志仍在本机 `.godot/int08/`。

## 最终验收

| 运行 | Godot 退出码 | 实际证据 |
| --- | --- | --- |
| `int01_gui_short_fixture` | 0 | `INT-01 PASS: 128 checks`；stderr 空 |
| `int04_gui_verified` | 0 | 两行 ROUTE PASS，`88 checks, top_level_routes=10, DD_completed=1`；stderr 空 |
| `int08_gui_verified` | 0 | `23 checks, rest_ready=3, expected_failures=1`；stderr 只有指定失败注入 |
| `sandbox_gui` | 0 | 正式 Sandbox 直接 GUI 运行 120 帧；stderr 空 |
| CB-04 / 05 / 06 / 07 | 各 0 | 原 2 / 3 / 3 / 1 cases 均 PASS；各 stderr 空 |
| FO-02～09 候选池 | 0 | 原候选、排序、超时、首次确认测试通过；stderr 空 |
| RS-08 / 09 / 10 | 各 0 | 原重复查看、下一关、末关路线均 PASS；各 stderr 空 |
| INT-07 flow | 0 | 原完成 / 中断用例 PASS；stderr 空 |
| Flow / HitResolution / RestResultView check-only | 各 0 | 解析通过；各 stderr 空 |
| 恢复完整 Autoload 后 import | 0 | 资源及编辑器导入完成；stderr 空 |
| 额外数据导出 SceneTree smoke | 0 | 普通真实命中、历史、Rest Continue 到第二关 PASS；退出资源引用限制见下文 |

INT-04 普通路线仍为粉丝 14、倾向 `[6,0,0]`、两条普通历史、经文 1、卡片 1、池 1、特性 `occlusion`。空路线为粉丝 14、倾向 `[0,0,0]`、历史及奖励为空。两路保存后读回一致，DD 一次接收并销毁。新增核对流程交付的同一 Rest 对象、结果分支、真实圣典与卡片历史按钮、返回和 Continue；历史查看不改变成果、不恢复攻击。

INT-01 覆盖原普通战斗、失败重开、暂停、真实释放、真矛盾、假矛盾、神谕单句 / 三句重叠选择、十秒自动选择，并检查正式 Rest 对象。真击破仍检查正式 120 条复读计划并实际生成；假矛盾演示等待显式使用既有 INT-04 TEST_ONLY 的 3 条 / 0.3 秒配置，按真实队列与离场事实等待。

INT-08 定向回归将内存 TEST_ONLY 继承池权重设为 -1：经文、历史、倾向、卡片和击败已提交后，原 Assimilation 接口拒绝池写入。流程报告一次 `普通词库继承提交失败`、未交付 Rest、没有继续写特性；修复为 1.0 后补齐池 / 特性并只交付一次 Rest，历史 hit_count、倾向和收藏均未重复。还覆盖同关已确认重开、第二关真实十秒未击破超时、确认后同帧重开取消旧 Rest 及保留已合法成果。指定错误通过 BEGIN / END 标记和 `expected_failures=1` 识别，验收没有宣称该 stderr 为空。

已查看实际 Rest 与空 Ending PNG：结果标题、粉丝增量、历史按钮、Continue 及两关缺章可见；空 Ending 标题 Y=24、滚动 0。`computer-use` 同时成功观察过 INT-01 实际神谕窗口；所有回归输入由 Godot 事件或既有按钮信号驱动，人工物理键鼠体验仍 UNVERIFIED。

## 准备及失败记录

- 首两次资源准备进程 `import` / `import_cached` 在本任务隔离路径内终止，实际各 -1；首轮含音频尚未导入的加载错误。临时移除 Autoload 的 `import_noautoload` 实际已完成，退出 0；显式 quit 的导入也为 0，两者有 boot 缺 SceneRouter 提示。恢复完整 Autoload 后最终导入 0、stderr 空。
- 准备阶段与导入并发的 `flow_check` 实际退出 `-1073741819`；未宣称底层原因已确认。导入完成后串行 `flow_check_final` 为 0，正式场景运行通过。
- 首轮 INT-01 为 1，包含旧假矛盾立即 Rest 预期、多候选释放前瞄准未重新注入两类失败。重新注入释放前坐标后同发两个冻结目标和最近中心裁决通过。45 秒等待正式 120 条路线曾退出 0，也曾因容量 / 生成位置等待未结束退出 1；最终使用已有短复读 fixture 验证实景结束条件，退出 0。
- 首轮 INT-04 为 1：新 main 已合入 ID-10，第一次点卡只翻开；旧测试随即 Next 没有选中身份。按真实两次点击适配后两次完整路线均为 0。
- 中间 INT-01 检查全过但有旧 Rest 离树后 `grab_focus` 错误；尝试在 Sandbox 已离树时调用 hide_result 又暴露空 Viewport。最终由 Rest 子节点自身取消等待，INT-01/04 stderr 为空，定向回归也只剩指定失败注入。
- 补充导出 smoke 首次临时场景未创建退出 1；修正后旧输入事件没有坐标，CA-12 将准心恢复到零点，命中检查退出 1。事件补上真实 Viewport 坐标后 PASS、退出 0。

## 限制、文档与下一位接手入口

补充数据导出 smoke 退出 0，但引擎仍报告 4 个 ObjectDB 实例和 2 个资源在退出时未释放；多留两帧也未消除，根因 UNVERIFIED，该无效等待改动已撤回。此输出保留在 `export_scene_smoke_verified.stderr`。主 INT-01/04 和 9 个相关既有回归没有此报告，不将补充 smoke 称为无错误验收。

生产默认卡片资料、正式第二关内容、神降临演出参数仍沿用已知待交付状态；TEST_ONLY 两路 PASS 只证明程序接线。正式 120 条全部复读的压力和展示耗时、Android 实机 / 打包、音频听感及人工物理操作未完成验收。奖励重试只处理当前流程已确认结果，未建立新存档迁移或整局事务。

更新 Integration README 与 12/13/18 的现行组合 / 生命周期说明。新离树问题已写入 Rest 正式文档，按 AGENTS 的归属规则继续由该文档负责；known_traps 保持原值，复用 KT-25/27/34/39。没有修改 Original 原始需求，没有执行其他任务卡。

下一位从 Integration README、INT-09 卡、本日志及 `get_contradiction_oracle_flow()` 开始。PR 提交后停止本任务，等待 review。

## 2026-10-10 PR #116 review 修正：已确认关重放的普通命中

仍在 `codex/lane-a-int08-1010` 继续同一 INT-08 卡。review 复现为：奖励已提交后重开同关，新尝试再命中普通话语，真击破后复用旧神谕；旧入口将新 HitResolution 的历史与倾向再次入账。此前重开用例没有加入普通命中，原“未重复成果”的验收范围因此不足。修改后的用例在旧实现实际 GUI 退出 1，明确失败在重放成果断言。

最小修正仅在流程引用实际首次确认事件所属的 HitResolution，stop 时清空引用。首次确认仍按原顺序提交；同次部分写入失败重试仍使用该拥有者的提交标记及各奖励所有者保存事实；同关重放撤回新尝试历史与倾向暂存，只核验或补齐原奖励、展示原神谕，不再触发神谕确认上涨。没有新增存档字段、管理器、配置、Scene 或 Resource。

只调整现有 `int_08_flow_test.gd` 的一个重放边界：重开后经正式记录接口新增一次普通命中和 +3 正统暂存，核对全部已提交历史、三项累计倾向、暂存撤回、首次确认候选、原节号、圣典 / 卡片数量和吞并快照保持。原中途拒绝、补齐及旧帧尾交接取消用例继续保留。

Windows Godot `4.7.2.stable.steam.ed1daf0bf` 实际复跑结果：INT-08 GUI 23 checks / exit 0，stderr 只有一次预期的“普通词库继承提交失败”；INT-01 GUI 128 checks / exit 0、stderr 空；INT-04 GUI 两路、88 checks / 10 routes / DD_completed=1、exit 0、stderr 空。CB-04/05/06/07、FO-02～09、RS-08/09/10、INT-07 flow 共 9 个既有 headless 入口全部 PASS / exit 0、stderr 空；Flow check-only exit 0、stderr 空。各进程使用 Start-Process -Wait -PassThru 读取真实 ExitCode，GUI 没有 headless 参数。

本轮沿用 `.godot/int08/project/` 已导入的隔离副本，仅存读路径和副本编辑器插件与工程不同。核对所有跟踪的 gd / tscn / tres，相关运行时代码一致；副本 Sandbox 原有两个空行差异已同步，未运行的额外数据导出 smoke 旧等待已同步。没有重新导入或改动任何 `.import` 文件。19081 的 MCP get_project_info 在修改前及结束前均确认当前 worktree，19080 未操作；本轮没有需要查证的新 Godot API。

真实退出码、失败复现和最终 stdout / stderr 保存在 [review_correction](evidence/INT-08_2026-10-10/review_correction/exit_codes.json)，9 个既有断言日志按入口名合并保留。更新 Integration README 与 FinalOracle README 的确认归属说明，该规则由正式文档负责，known_traps 未修改。额外数据导出 smoke、Android、音频听感和人工物理键鼠本轮未复验；旧限制仍适用。交接从本段和该边界用例开始。本轮作为 PR #116 的独立修正提交，推送后停止，不执行 INT-09 或测试整并。
