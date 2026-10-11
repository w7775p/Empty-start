# known_traps

> 职责：Godot、资源、状态边界和回归问题的编号化排错记录。

## 一、Godot / 生命周期

<table fit-page-width="true" header-row="true">
<tr>
<td>ID</td>
<td>陷阱</td>
<td>正确做法</td>
</tr>
<tr>
<td>KT-01</td>
<td>Autoload 名称与 `class_name` 冲突，或新增 Autoload 后实际未注册。</td>
<td>Autoload 不声明同名 `class_name`；修改后核对 `project.godot` 的 `[autoload]`。</td>
</tr>
<tr>
<td>KT-02</td>
<td>`PackedScene.instantiate()` 后立即调用依赖 `@onready` 的方法，节点尚未进入树。</td>
<td>先 `add_child()` 并等待初始化，或让 setup 不依赖 `@onready`。</td>
</tr>
<tr>
<td>KT-03</td>
<td>依赖 `_exit_tree()` 自动完成任务、派遣、占用等关键清理。</td>
<td>生命周期拥有者提供显式结束方法；场景销毁只做最终清理。</td>
</tr>
<tr>
<td>KT-04</td>
<td>场景化 / UI 重构后遗漏 Button 或 Signal 连接。</td>
<td>修改 `.tscn` 后逐项核对交互节点引用和信号连接。</td>
</tr>
<tr>
<td>KT-05</td>
<td>`_input()` 对未处理事件也调用 `set_input_as_handled()`，导致其他 UI 失效。</td>
<td>只消费明确处理的事件。</td>
</tr>
</table>
## 二、状态与系统边界
<table fit-page-width="true" header-row="true">
<tr>
<td>ID</td>
<td>陷阱</td>
<td>正确做法</td>
</tr>
<tr>
<td>KT-06</td>
<td>同一事实被多个对象保存，例如 Task 与 Dispatch 各维护一份可修改派遣成员。</td>
<td>指定唯一拥有者；其他位置只引用或保存明确不可变历史快照。</td>
</tr>
<tr>
<td>KT-07</td>
<td>UI 或其他 System 直接修改不属于自己的运行状态。</td>
<td>通过状态拥有者公开 API 修改；UI 只提交请求。</td>
</tr>
<tr>
<td>KT-08</td>
<td>用 Signal 发送隐式业务命令，调用链无法追踪。</td>
<td>命令走 API；Signal 只通知已经发生的事实。</td>
</tr>
<tr>
<td>KT-09</td>
<td>把当前值、占用、关系进度等运行事实写回静态 `.tres` Resource。</td>
<td>静态 Resource 运行时只读；变化写入对应运行系统。</td>
</tr>
<tr>
<td>KT-10</td>
<td>为了方便维护“虚拟计数”“is_busy”“is_dispatchable”等第二副本。</td>
<td>能派生的值即时计算，不增加第二真相源。</td>
</tr>
</table>
## 三、数据 / ID / 测试资产
<table fit-page-width="true" header-row="true">
<tr>
<td>ID</td>
<td>陷阱</td>
<td>正确做法</td>
</tr>
<tr>
<td>KT-11</td>
<td>修改源字段后只更新链路的一部分，造成 Excel / Python / JSON / Godot 字段漂移。</td>
<td>字段变化必须验证完整生产链和消费端。</td>
</tr>
<tr>
<td>KT-12</td>
<td>跨资产 ID 不一致，或使用显示名称代替稳定 ID。</td>
<td>ID 全局稳定；修改后全局搜索所有引用。</td>
</tr>
<tr>
<td>KT-13</td>
<td>JSON 数字 / Variant 类型直接进入强类型 GDScript，出现 float/int 或无类型 Array 错误。</td>
<td>Importer 边界显式转换并构造目标类型。</td>
</tr>
<tr>
<td>KT-14</td>
<td>直接修改上游生成出的 JSON / 运行资产，导致下次导出覆盖。</td>
<td>回到真正源数据修改，再重新生成。</td>
</tr>
<tr>
<td>KT-15</td>
<td>TEST_ONLY 的临时字段或 fixture 被顺手做成正式 Schema。</td>
<td>测试资产使用 `test_` 和独立目录；正式 Schema 只能由真实策划验证后冻结。</td>
</tr>
<tr>
<td>KT-16</td>
<td>测试判定包含随机，导致测试不稳定且无法判断回归原因。</td>
<td>首轮 fixture 使用确定性条件；需要随机时固定 seed 或注入 RNG。</td>
</tr>
<tr>
<td>KT-17</td>
<td>派遣前预览和最终结算分别随机，玩家看到的依据与结果来源不一致。</td>
<td>一次生成并保存随机结果，后续全部读取同一事实。</td>
</tr>
</table>
## 四、Resource / Scene 文件
<table fit-page-width="true" header-row="true">
<tr>
<td>ID</td>
<td>陷阱</td>
<td>正确做法</td>
</tr>
<tr>
<td>KT-18</td>
<td>手写 `.tres` 时 `[resource]` 先于其引用的 `[sub_resource]`，产生前向引用解析错误。</td>
<td>顺序保持 `[gd_resource] → [ext_resource] → [sub_resource] → [resource]`。</td>
</tr>
<tr>
<td>KT-19</td>
<td>复制 / 手写 `.tscn` 节点后 `parent` 路径仍指向旧节点。</td>
<td>修改场景文本后核对实际父子树。</td>
</tr>
<tr>
<td>KT-20</td>
<td>Resource 被共享加载后又当作某一实例的可变状态使用，导致多个对象互相污染。</td>
<td>静态 Resource 保持只读；确需独立可变副本时先确认所有权和复制语义。</td>
</tr>
</table>
## 五、代码修改与验证
<table fit-page-width="true" header-row="true">
<tr>
<td>ID</td>
<td>陷阱</td>
<td>正确做法</td>
</tr>
<tr>
<td>KT-21</td>
<td>批量重命名残留旧引用，或 replace-all 二次污染已替换名称。</td>
<td>重命名后立即全局搜索旧名；避免目标字符串互为子串的盲目 replace-all。</td>
</tr>
<tr>
<td>KT-22</td>
<td>新增方法与父类 / 现有方法同名，产生覆盖或签名冲突。</td>
<td>新增公开方法前搜索现有类和 Godot 基类方法。</td>
</tr>
<tr>
<td>KT-23</td>
<td>只运行 `--headless --quit` 就认为所有脚本编译通过。</td>
<td>新增 / 修改 `.gd` 对相关脚本执行单文件 `--check-only --script`，并运行对应测试。</td>
</tr>
<tr>
<td>KT-24</td>
<td>未经确认 push，或提交混入无关文件。</td>
<td>push 必须用户明确授权；提交前检查 `git diff` 和 scope。</td>
</tr>
<tr>
<td>KT-25</td>
<td>使用 `--script` 直接运行验证脚本时，项目 Autoload 不会自动作为全局标识符注入；项目中预载资源的无关 Autoload 也可能在该运行方式下报加载错误。</td>
<td>依赖 Autoload 的测试使用真实场景启动，或在脚本中显式加载并实例化目标脚本。纯逻辑测试不需要的 Autoload 可临时从 `project.godot` 移除，验证后立即恢复配置。</td>
</tr>
<tr>
<td>KT-26</td>
<td>headless --script 验证脚本以 record 作为局部变量名时，只加载脚本而未输出用例结果，退出码仍为 0。</td>
<td>运行时记录使用 runtime_record、barrage_record 等明确变量名；测试检查预期输出和用例结果，不能只看进程退出码。</td>
</tr>
<tr>
<td>KT-27</td>
<td>新 worktree 首次直接启动 headless 场景时，Global Script Class Cache 尚未生成，出现多个 `Could not find type` / Autoload 脚本解析错误。</td>
<td>先使用 `--headless --path 项目路径 --import` 完成项目导入，再启动场景；确认 `.godot/global_script_class_cache.cfg` 已包含新增 `class_name`。</td>
</tr>
<tr>
<td>KT-28</td>
<td>同时启动多个启用 Godot-MCP-Native 的编辑器时，后启动的实例可能因默认端口 9080 已被占用而无法连接 MCP；仅因 Codex 工具列表未显示 Godot 工具就判断项目 MCP 未启动，也会漏掉正在运行的服务。</td>
<td>先请求 `http://127.0.0.1:9080/cli/v1/doctor` 检查 `editor_connected` 与 `project_path`，目标编辑器已连接时复用它的本地 MCP 接口；确需启动第二个编辑器时配置独立端口，纯脚本校验仍可使用 Godot CLI。</td>
</tr>
<tr>
<td>KT-29</td>
<td>直接运行场景时在 `_enter_tree()` 创建 SaveData，随后 Autoload 的 `_ready()` 又将数据初始化为 null，导致场景读取 live_session 报 Nil；仅在已初始化存档的测试场景中无法暴露该问题。</td>
<td>等待场景 `_ready()` 再创建需要的内存周目；已经就绪的子 HUD 通过公开绑定方法接收当前 Resource，同时验证直接启动正式场景。</td>
</tr>
<tr>
<td>KT-30</td>
<td>headless 的物理窗口与逻辑视口大小不同，直接将弹幕画布坐标传给 `Input.parse_input_event()` 会被再次缩放，准心偏离目标后产生 MISS。</td>
<td>先将画布目标通过 Canvas 变换和 `Viewport.get_final_transform()` 转成窗口坐标，再注入事件并刷新输入缓冲；准心从接收到的事件位置转换回画布坐标。INT-01 曾实测到 1/18 的窗口缩放。</td>
</tr>
<tr>
<td>KT-31</td>
<td>命中移除或生成位置不足时释放普通容量，每次都重启正在运行的生成 Timer，会让频繁命中持续推迟下一批。</td>
<td>释放容量时仅恢复已经停止的 Timer；运行中的剩余周期保持原值。Tier 频率改变继续显式更新时间间隔。INT-01 已用真实 Timer 验证非满容量移除后剩余时间保持。</td>
</tr>
<tr>
<td>KT-32</td>
<td>外部修改嵌套 PackedScene 后，只关闭再打开父场景可能仍复用旧子场景缓存。INT-02 中 LiveDataHud 新标题和卡片排版已写盘，编辑器仍显示旧卡片。</td>
<td>核对实际子节点与 Inspector；重新加载相关子场景，或重启本任务拥有的编辑器后再次打开父场景。验收截图必须来自重新加载后的真实节点树。</td>
</tr>
</table>
## GSD 接入工具

### KT-33：GSD 自动发现漏掉 Godot 与中文规格

- **现象**：GSD 1.15.0 的 `init onboard` 对本仓库返回 `has_existing_code: false` 和 `doc_candidate_count: 0`，实际存在 GDScript 源码、系统 README 和 `docs/Original/`。
- **触发原因**：已检查本地 `onboard-projection.cjs`：代码扩展名集合未包含 `.gd`，包入口列表未包含 `project.godot`；文档候选只按 ADR/PRD/SPEC/RFC、四位编号及 REQUIREMENTS 命名/目录发现，当前中文文件名和系统 README 未匹配。
- **规避**：以工程及正式文档核对真实状态，复用 codebase map，通过显式 ingest manifest 纳入资料。`.planning/onboarding/INGEST-MANIFEST.yaml` 保存本次清单；自动检测的缺失结果不能据此判定工程为空。核心规划建立后再检查 GSD 状态路由。

### KT-34：PowerShell 启动 Godot 图形版 exe 提前返回

- **现象**：用 `& godot.windows.opt.tools.64.exe ...` 启动后，后续命令可能在 Godot 结束前执行，`$LASTEXITCODE` 为空且日志只有启动头；外层 PowerShell 的退出码不能代表 Godot 结果。
- **触发条件**：Windows PowerShell 执行图形子系统 Godot exe，且同一工作流继续读取输出、清理或运行下一条验证。
- **规避**：使用 `Start-Process -Wait -PassThru -WindowStyle Hidden` 并重定向 stdout / stderr，读取进程的 `ExitCode`；接口 smoke 同时检查预期成功输出和错误日志。AS-08 已用此方式确认完整导入及真实接口运行结果。

### KT-35：const Resource 属性读取被解析期折叠

- **现象**：AU-02 临时运行验收将音频配置的淡入 / 静音时长改为 0，通过局部 Resource 引用读取已是 0，`const AUDIO_EVENT_CONFIG.music_*_seconds` 路径仍按原时长淡变，零时长检查失败。
- **触发条件**：Godot 4.7.2 直接读取 const 预载 Resource 的字段，随后同一 Resource 的字段发生变化；参见引擎维护仓库 [Issue #101628](https://github.com/godotengine/godot/issues/101628)。
- **规避**：需要查询当前字段时，通过普通 Resource 引用读取；AU-02 的 `_audio_config` 引用原配置，未复制 Resource。修正后实际 WASAPI 运行验收的零时长检查通过。生产静态资源仍保持运行时只读，验收修改只存在于临时进程内。

### KT-36：受限 Windows 工作区下 Godot 日志与编辑器目录写入失败

- **现象**：Godot CLI 可解析脚本并输出预期 PASS，但默认 `user://logs` 或 Steam 自包含 `editor_data/editor_settings-4.7.tres` 写入被拒绝，进程仍可能退出 0。
- **触发条件**：工作区允许写当前目录，用户数据 / 引擎安装目录只读；DD-09 的受限 worktree 中已复现。
- **处理**：先用引擎 `--help` 确认 `--log-file`，将运行日志显式指向可写临时目录；同时检查 PASS、退出码和 stderr。编辑器导入的目录权限、系统证书读取错误单独记录为环境限制，不将其误报为业务解析失败或无错误验证，也不改用户全局目录权限。

### KT-37：窗口缩放延迟回调在身份卡视图离树后抵达

- **现象**：缩放窗口并通过 SceneRouter 替换身份设置场景时，旧 `IdentitySelection._fit_layout()` 的延迟调用读取空 Viewport，产生脚本错误。
- **条件**：`Window.size_changed` 使用 `call_deferred` 排版，同一帧旧场景离树；ID-09 GUI smoke 切换至 960×540 新周目时已复现。
- **处理**：排版入口先检查 `is_inside_tree()`，离树视图直接返回。真实 GUI 复跑没有该脚本错误。

### KT-38：TextureRect 无效拉伸枚举导致背景静默不绘制

- **现象**：RS-12 真实 GUI 截图只显示倾向色块与装饰，已加载的房间贴图没有绘制，运行日志未报告相关脚本错误。
- **条件**：共享 `RestRoomEnvironment/RoomBackdrop` 的 `stretch_mode` 写为 `7`；Godot 4.7.2 的 TextureRect 拉伸枚举有效范围为 0～6。
- **处理**：场景改为 `6`（`TextureRect.STRETCH_KEEP_ASPECT_COVERED`），实际 GUI 重跑并查看开局三态及战后截图。背景资源引用存在、解析成功均无法证明贴图实际可见。官方枚举依据：https://docs.godotengine.org/en/stable/classes/class_texturerect.html#enum-texturerect-stretchmode。

### KT-39：鼠标按下重新读取系统光标覆盖有效事件位置

- **现象**：CA-12 合入后 INT-04 第一发普通攻击 MISS，准心跳到约 `8.81e8`；实际注入事件位置为 `(727.2001,86.4)`。
- **条件**：受限 Windows 隐藏 GUI 中，`get_global_mouse_position()` 返回异常大值；左键按下调用恢复方法重新读取该值。旧 CA-12 探针用按下后补 MouseMotion 掩盖过此问题。异常系统读数的底层原因、真实硬件鼠标行为尚未确认。
- **处理**：真实按下将事件 Viewport 坐标传给 `restore_mouse_aim(viewport_position)`，沿用画布逆变换恢复 PC 尺寸与中心；首发验证不添加补定位事件。2026-10-09 同一 INT-04 隔离副本修复前 exit 1、修复后完整两路线 exit 0。

### KT-40：headless 位移测速要累计引擎帧时间

- **现象**：BG-40 首轮 headless 位移测试用 `Time.get_ticks_usec()` 作为分母，测得 T1 速度 7756.8 px/s、Repeat 243.7 px/s、Paradox 305.2 px/s；改为累计节点 `_process(delta)` 后，T1/T5、Repeat 与 Paradox 均与各自配置速度相符。
- **条件**：本机 Godot 4.7.2 `--headless --script` 运行中，`SceneTreeTimer` 累计的引擎处理时间与墙钟时间不同步；用墙钟除位置变化会错误报告速度。
- **处理**：测试节点在 `_process(delta)` 中累加模拟秒数，并用位置变化除以同一引擎时间；保留 `SceneTreeTimer` 作为等待条件。

### KT-41：Curve2D 三次采样可能突破弧长速度上限

- **现象**：BG-21 将弧长偏移按上限推进后，`sample_baked(offset, true)` 的三次插值仍可能让单帧位置差超过对应弧长步长；严格逐帧速度断言可复现超速。
- **条件**：运动按 `Curve2D` 烘焙弧长前进，同时把 `cubic` 插值设为 `true`。
- **处理**：细分烘焙点间改用 `sample_baked(offset, false)` 线性插值，并用同一 `_process(delta)` 帧时间累计实际路径距离验证速度。BG-21 的 2 px 烘焙步长和 96 px/s 上限回归通过。

## 六、自查入口
遇到问题优先按类别检查：
- UI 不响应 / 空引用：KT-02、KT-04、KT-05。
- 状态不同步 / 重复：KT-06～KT-10。
- 数据加载 / ID 问题：KT-11～KT-17。
- `.tres / .tscn` 解析问题：KT-18～KT-20。
- 重构后编译或引用异常：KT-21～KT-23。
- 新 worktree 首次 headless 启动出现全局类缺失：KT-27。
- Godot MCP 连接 / 端口占用：KT-28。
- headless 位移速度与计时验证：KT-40；Curve2D 速度上限：KT-41。

## 附录 A：Godot 生命周期提醒

- Autoload 名称不得与 `class_name` 冲突。
- 新增 Autoload 后核对 `project.godot`。
- `PackedScene.instantiate()` 后，节点未进入树时不得假设 `@onready` 已初始化。
- 关键 Task / Dispatch 清理必须显式完成，不依赖 `_exit_tree()` 等销毁副作用。
- UI 只提交请求和显示事实，不直接写业务状态。
