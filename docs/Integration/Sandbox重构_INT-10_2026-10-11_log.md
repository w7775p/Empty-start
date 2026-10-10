# Sandbox 重构 INT-10 任务日志（2026-10-11）

## 范围与分支

只继续 INT-10。工作分支为 `codex/lane-a-int10-1010`。开工时先读取并备份未提交的 `sandbox.gd`、INT-01 测试和整份未跟踪证据目录；随后获取最新 `origin/main`，先同步到 `1910eba`，PR 前又更新并重基到 `b676452`。未覆盖或重置原工作区内容；CB-13 上游提交保持原样，本分支没有修改其源文件。

本次保留四条 Sandbox / BattleHud 立绘协调语句，只在根场景绑定正式攻击输入快照、在尝试启动时按 `LevelProfile.streamer_id` 更新对手待机预设。根场景继续组合普通战斗、矛盾/神谕、Rest、神降临和 Ending 三流程；三流程仍拥有各自阶段对象和业务状态。

## 主要改动

- `scenes/sandbox/sandbox.gd`：增加 `SandboxBattleHud.bind_portrait_attack(_attack_charge_input)` 与尝试开始时的 `configure_portrait_character(streamer_id)` 接线，未改 Sandbox 场景节点结构。
- `tests/integration/int_01_playable_battle_sandbox_test.gd`：验证当前关配置待机周期与真实释放快照触发玩家立绘射击动作。按最新 CS-19 规则，将 T0 断言改为 PK 稳定；暂停恢复与重开后的真实回拉改在 T1 验证；归零失败流程通过既有 Debug 入口将 PK 设为 0 后接收真实失败事件。
- `docs/Integration/README.md`、`docs/开发计划_2026-10-09_任务卡依赖整合.md`、`docs/System_Collaboration.md`：记录 Sandbox 三流程真实公开 API、S3 前置与 Owner 分类、正式数据和视觉验收边界。
- 受影响任务卡：`CA-15`、`BG-38`、`CS-14`、`CS-22`、`SD-06`、`PA-17`、`PA-18`、`PA-19`、`INT-06` 更新为当前流程 signal / getter、节点路径和表现完成回调边界。
- `INT-10` 任务卡标为实现完成、PR 待 Review，并注明 INT-04 未执行。验证摘要与本日志记录当日最终检查。

没有修改 `.tscn`、`.tres`、正式数据表、Importer、存档数据或 `known_traps.md`。没有触碰 CB-13 任务源，也没有修改人审视觉 PR #131、#132、#142。

## S3 交接结论

- 前置不变：CA-15 → BG-38、HR-16 → HR-17、CS-18 → CS-14 → CS-15，以及 BG/RP 的独立生成、Tier 与复读规则仍归原系统 Owner。
- 普通战斗接线使用 `BattleAttemptFlow` 的 `attempt_started`、`attempt_restarted`、`shot_resolved`、`tier_changed`、`attempt_failed` 和阶段动作 getter；`shot_resolved` 发生在本发逐目标处理、倾向暂存和复读登记之后。
- 矛盾/神谕/Rest 使用 `ContradictionOracleFlow.outcome_resolved`、`oracle_opened`、`rest_ready`；神降临与结局使用 `DivineDescentFlow.entered`、`completed`。Sandbox 负责场景与 UI 路由，不持有第二份业务状态。`battle_state_changed(text)` 只用于显示。
- SD、LD、PA 和 INT 的 UI / 演出 / 布局仍由各自 Owner 实现；PA-17/18/19 需要定义表现结束回调再由 Sandbox 接回流程。动画等待机制目前尚未实现。
- LC-10/12/13、LD-12、SD-08、CS-28/29、BG-35/41 仍等待正式字段与资源。四关正式映射、Importer、全屏/实体输入/Android 和美术视觉验收仍未完成。

## 验证与证据

- Windows Godot `4.7.2.stable.steam.ed1daf0bf` 在 `b676452` 基线上 headless 最终运行 `tests/integration/int_01_playable_battle_sandbox_test.tscn`：**88 checks，exit 0，stderr 为空**。原始输出为 `evidence/INT-10_2026-10-10/int01_final.stdout.txt` 与 `.stderr.txt`。
- 同一次复测首次出现 9/87 失败：最新主线的 CS-19 已将 T0 回拉倍率设为 0，而旧测试仍要求 T0 自动回拉。按现行规则调整测试后最终 88/88 通过。portrait 待机预设和射击动作断言均通过。
- 既有 `real_flow.stdout.txt` 记录两次 Rest、两次 Continue、一次 Divine 进入和一次 Ending 完成；`verification-summary.md` 记录该先前运行 exit 0、stderr 为空。本次未重跑整局探针。该探针用内存中的 `level_001` 副本作为第二样例，不能证明正式四关数据。
- `sandbox_direct.png` 与 `ending_page.png` 已目视检查。前者是实际 Sandbox 静态画面；后者仍显示未配置经文内容。二者不构成动画、完整视觉或正式内容验收。
- 按当前控制要求未运行 INT-04，未将 INT-04 结果用于验收或发布就绪判断。

## 当前能力与后续接手

Sandbox 已有普通尝试 → 矛盾/神谕 → Rest/Continue → 神降临 → Ending 的实际流程接线；INT-01 检查当前公开接口、布局、输入事件、HUD、立绘协调和失败/重开主链。下一步从本日志、`docs/Integration/README.md` 的 S3 表和对应 Lane 任务卡继续，按其 Owner 实现展示事件或动画完成回调，再另行进行视觉与正式数据验收。

INT-04、手动鼠标/全屏/Android、完整正式四关、正式角色立绘映射和 PA 动画均未在本卡验证。`known_traps.md` 无新问题需要记录。
