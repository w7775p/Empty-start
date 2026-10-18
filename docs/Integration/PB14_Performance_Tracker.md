# PB-14 运行时性能 Tracker

## 开关与输出

Tracker 默认关闭。Sandbox 只在环境变量 `PB14_PERF_TRACKER=1` 时创建节点并把它注入 B/D；关闭时不创建对象、不打开文件、不调用计时器。启用后每帧只采集标量引擎监视器和时间戳，每秒写一行 JSONL，不逐帧打印，也不在帧循环创建统计数组或完整场景快照。

PowerShell 示例：

```powershell
$env:PB14_PERF_TRACKER = '1'
$env:PB14_PERF_TRACKER_PATH = 'C:\Users\lvy\.codex\worktrees\10d0\Empty-start\.godot\pb14\run.jsonl'
$env:PB14_PERF_TRACKER_SECONDS = '8'
& 'D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' --headless --path . --log-file .godot\pb14\engine.log res://scenes/sandbox/sandbox_plan_b.tscn
$trackerExitCode = $LASTEXITCODE
Remove-Item Env:PB14_PERF_TRACKER -ErrorAction SilentlyContinue
Remove-Item Env:PB14_PERF_TRACKER_PATH -ErrorAction SilentlyContinue
Remove-Item Env:PB14_PERF_TRACKER_SECONDS -ErrorAction SilentlyContinue
```

先建立输出目录。省略 `PB14_PERF_TRACKER_PATH` 时，输出到 `user://pb14_performance_tracker.jsonl`；省略或设为 `0` 的时长会持续采集，退出 Sandbox 时写结束记录。设置正数时长可用于短时 CLI 采样，结束后 Tracker 请求 SceneTree 正常退出。

每个 JSONL `window` 行包括：

- `frame`：wall frame mean/max、FPS mean、`TIME_PROCESS` mean/max、`TIME_PHYSICS_PROCESS` mean/max、draw calls mean/max。
- `runtime`：玩家/费米/中立数量、关卡、Tier、普通战斗状态、槽位可用/冷却数量、词群数量/成员和活动群泡；`ui` 子项包含 UI 单位快照、词群快照、待发言事件和活动群泡计数。
- `sections`：每秒各观测区段的调用次数、平均/最大微秒数及工作量。包括模拟物理 tick、steering、邻域查询、团体刷新/快照广播、物理位置导出/信号、UI 单位事件/位置/团体快照、UI 来源/视图刷新、单位绘制、群泡布局/成员位置/尾巴绘制和对白气泡创建。
- `events`：群泡生成、对白气泡创建和批次喷涌计数。
- `render_work`：最近场地重绘的单位、活动群泡与尾巴候选数量。

区段可以嵌套。例如 `simulation_tick` 包含 steering 和位置导出，`ui_draw` 包含单位与群泡绘制；分析时不要把父子区段相加。`neighbor_query.work_total` 是空间网格桶候选数，`aux_total` 是半径过滤后返回的邻居数。群泡尾巴计数是布局候选数，零面积保护可能跳过其中一部分。

Headless 模式下 draw calls / GPU 数据不代表 D3D12 绘制成本；需结合 Godot engine log 和正式 renderer profile 阅读。Tracker 不改变模拟规则，也不据自身采样结果自动应用优化。

为限制观测器自身开销，高频邻域查询和 UI 单位快照更新先在各自物理/渲染帧内累加，再批量送入 Tracker；JSONL 的 `calls` 保留内层调用总数，`mean_us` / `max_us` 仍按内层操作计算。`work_max` 表示该区段一次汇总回调中的最大工作量，具体单位见 section 的 `work_total` / `aux_total` 含义。

## 本轮观测

8 秒 headless Sandbox 基线与 7 秒 Tracker 样本保存在：

- [Tracker 样本 JSONL](evidence/PB-14_2026-10-18/pb14_tracker_short_validation.jsonl)
- [Tracker 前基线 JSONL](evidence/PB-14_2026-10-18/pb14_pre_tracker_baseline.jsonl)
- 8秒 headless 基线探针源码与场景是 `evidence/PB-14_2026-10-18/pb14_short_baseline_probe.gd/.tscn`；冷缓存阻断及后续缓存处理记在 PB-14 日志。

Tracker 样本包含 `start`、7个1秒窗口和 `end` 记录；section 和 runtime 字段均有实际运行值。样本由 headless renderer 采集，draw calls 为0，因此只用于确认字段接线与逻辑阶段数据；窗口渲染性能仍由 E 在同口径 D3D12 profile 中测量。A 未执行优化或容量 sweep。

两个样本采集时的 A HEAD 为 `6f192286`，早于 B 的 neutral neighbor skip commit `b0bd8506`。它们证明字段布局和初始运行状态，不能代表当前候选的后优化性能值。
