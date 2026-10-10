# Sandbox 重构 INT-07 任务日志（2026-10-10）

## 范围与结果

仅执行 INT-07，分支 `codex/lane-a-int07-1010`，干净起点 `9182d29af130cc163e185b91ac4127d6de4541ad`。指定代理查询远端 main 仍为此提交；本机共享 main 指针不同，工作树始终保留用户指定起点。已阅读 AGENTS、known_traps、整合开发计划、原始任务卡模板、INT-07 / INT-04、Integration README / 最新日志、DivineDescent / Ending README 与最新日志，并核对实际 Sandbox、SceneRouter、DD / Ending 源码、场景、配置和测试。

完成 `DivineDescentFlow` 抽取，保留同一冻结 Session、两路分流、真实演出、输入、普通规则关闭、一次 Ending 接收与原存读 / 顶层路由。没有实现 INT-08/09/10、合并分支、修改其他 Lane、Codex 配置或个人文件。原 DD Session / Spread / CombatMode / Emphasis、Ending 和 SceneRouter 源码保持原值。

## 文件与接口

- `core/divine_descent/divine_descent_flow.gd`：独立 Node，持有 Session、Mode、Spread 和 Ending 接收结果。公开 start / advance / handle_input / stop 与四个读取入口；entered 交给根场景收起旧阶段，completed 携带已接收的同一 EndingSession。原始空历史延迟完成；非空沿用 DD-05/08/13/14/16/17。显式 stop 取消生成和演出，不补发结果。
- `scenes/sandbox/sandbox.gd`：运行时组合一个流程子节点；末关 Continue 发起流程，保留普通 / 神谕 / Rest 顶层协调、原 entered 转发、真实存盘和 SceneRouter 请求。逐帧及输入转给流程；debug 和重开判断读流程原 Session。新增 `get_divine_descent_flow()`。
- `tests/integration/int_04_full_run.gd`：替换神降临私有字段读取，使用公开流程接口；新增两路一次接收、同一 Ending 路由对象、冻结倾向及流程销毁检查。保留原输入、玩法、存读与 TEST_ONLY 数值。
- `core/divine_descent/tests/test_int07_flow.gd`：仅新增抽取相关边界测试，真实空态接收一次、重复启动拒绝、延迟空态取消、真实收束后 Tween 中断与输入拒绝。内存测试数据使用 TEST_ONLY 标识。
- `docs/Integration/README.md`：记录流程归属及 INT-08 可用接口；本日志记录交接。

没有 `.tscn` / `.tres` / project.godot 的生产改动，没有新增 Autoload、配置类型或生产 TEST_ONLY 内容。

## 实际运行方法

引擎 `4.7.2.stable.steam.ed1daf0bf`，Windows exe `D:/steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe`。Godot MCP doctor 无法连接，采用 CLI。所有进程使用 `Start-Process -WindowStyle Hidden -Wait -PassThru`，读取实际 `ExitCode`，stdout / stderr / log-file 保存到本工作树忽略目录 `.godot/int07/`。

隔离副本 `.godot/int07/project/` 复制当前工程跟踪文件和新流程 / 测试文件，只在副本关闭编辑器 MCP 插件、把 SaveManager `SAVE_PATH` 改为 `res://.godot/int07_save.res`，SettingsManager 路径改为 `res://.godot/int07_settings.cfg`。其函数体保持原值，测试真实 ResourceSaver / ResourceLoader。正式工程与个人存档 / 设置保持原值。

GUI 参数：

```text
--path <隔离项目> res://tests/integration/int_04_full_run.tscn --resolution 1152x648 --quit-after 9000 --log-file <int04_gui.log>
--path <隔离项目> res://scenes/sandbox/sandbox.tscn --resolution 1152x648 --quit-after 120 --log-file <sandbox_gui.log>
```

Headless 参数：

```text
--headless --path <隔离项目> --import --log-file <import_restored.log>
--headless --path <隔离项目> --script res://core/divine_descent/tests/test_int07_flow.gd --log-file <flow_test.log>
--headless --path <隔离项目> --script res://tests/unit/divine_descent/<既有脚本>.gd --log-file <脚本名.log>
--headless --path <隔离项目> --check-only --script res://<受影响脚本> --log-file <check.log>
```

## 验证结果与输出

1. **真实 PC GUI 两路 PASS / exit 0**：D3D12 12_0 / Forward+ / AMD Radeon(TM) Graphics，1152×648，没有 headless 参数，输入为原生事件自动注入。真实 MainMenu → 身份三页 → 开局房间 → 两普通关 → Rest → 神降临 → Ending；含失败重开、一次确认 / 奖励、真实衰减、锁句、收束、Tween、空格输入、磁盘存读和场景销毁。`int04_gui.err` 为空。

```text
INT04 ROUTE PASS empty_history=false
INT04 ROUTE PASS empty_history=true
PASS INT-04 full run checks=68 top_level_routes=10 DD_completed=1
Godot ExitCode=0
```

普通路线粉丝 14、倾向 `[6,0,0]`，普通历史 `test_word_01` / `test_word_09`，经文 1、卡片 1、继承池 1、occlusion；空路线粉丝 14、倾向 `[0,0,0]`，普通历史及收藏为空。两路读取结果与写盘前相等，flow completed 各一次，路由使用同一已接收 Ending，flow 随 Sandbox 销毁。

2. **正式 Sandbox 直接 PC GUI 启动 exit 0**：生产场景和默认资源运行 120 帧，D3D12 / Forward+，stderr 为空。仅证明真实启动，未宣称默认非空终局配置已交付。
3. **新增流程定向 headless PASS / exit 0**：`PASS INT-07 flow completion/cancellation`，stderr 为空。原 Session 快照与 Ending 姓名沿用首次事实；重复启动拒绝；stop 后延迟空态与真实 Tween 均不通知，扩散节点销毁，输入拒绝。
4. **8 个既有 DD headless 脚本全部 PASS / exit 0**：DD-02 历史归并、DD-06 基础权重、DD-07 圣典加权、DD-09 最高权重、DD-10 并列、DD-12 可见比例、DD-13 90% 收束、DD-15 原始空历史。各 stderr 为空。RS-10 和 EN-09 也各 PASS / exit 0，stderr 为空。
5. **解析**：Flow 和新增定向测试 `--check-only` 均 exit 0、stderr 空。Sandbox check-only exit 1，缺少 SaveManager 全局标识；INT-04 check-only exit 1，缺少 SceneRouter / SaveManager 标识，沿用 KT-25。恢复全部 Autoload 后 import exit 0、stderr 空，实际 GUI 场景编译 / 运行通过。没有用单文件失败代替实际场景判定。
6. **导入准备过程**：前两次未完成资源导入的进程在本任务范围内终止，实际退出 -1；首次有未缓存音频加载错误。第三次仅临时从隔离配置移除 Autoload 后资源导入 exit 0，含既有 CSV locale 提示及 boot 缺 SceneRouter 解析错误。随后恢复全部 Autoload，再次完整 import exit 0、stderr 为空。最终验收使用恢复配置和完成缓存后的结果，前期输出保留作追溯。
7. **实际截图查看**：全屏强调为黑色背景与居中锁句；空圣典页面顶部标题、两章缺章可见，滚动 0、标题 Y=24。截图位于副本 `.godot/int04_main_full_screen_emphasis.png`、`int04_empty_ending.png`，完整截图 / 日志留忽略目录。
8. `git diff --check` 通过；所有交付文件限定在 Sandbox、专用流程 / 测试、INT-04 接口迁移及 Integration README / 日志。

## 限制与交接

正式终局演出时长 / 输入表现参数默认仍为 0，正式内容与美术继续待所属 Owner 交付；本次完整两路为显式 TEST_ONLY 配置验证。Neutral 原始历史非空但过滤候选为空，继续沿用原拒绝启动规则，未新增结局规则。个人默认存档路径的写权限、Android 硬件 / 打包、音频听感、人工物理键鼠和正式平衡均 UNVERIFIED。

INT-08 从 Integration README、当前卡与本日志接手，使用 `Sandbox.get_divine_descent_flow()` 和流程公开接口。存盘与顶层路由仍由 Sandbox / SceneRouter 持有。只更新本系统 README；沿用 known_traps KT-25 / 27 / 34，本次未新增长期陷阱，known_traps 保持原值。本任务完成后停止，不启动下一卡。
