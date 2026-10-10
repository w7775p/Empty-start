# RS-12 新周目开局直接进入主角房间

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- AGENTS.md、known_traps.md、project.godot
- docs/System_Collaboration.md
- docs/18. Rest/README.md
- docs/18. Rest/tasks/RS-07_tendency-environment.md
- docs/18. Rest/tasks/RS-09_next-level.md
- docs/18. Rest/tasks/RS-11_input-switch.md 及相关最新完成日志
- docs/1. Identify/tasks/ID-08_twelve-identity-card-selection.md
- docs/1. Identify/tasks/ID-09_three-step-opening-flow.md
- core/autoload/scene_router.gd、core/rest/rest_session.gd
- ui/rest/rest_room_environment.tscn / .gd、ui/rest/rest_result_view.tscn / .gd
- scenes/sandbox/sandbox.gd、ui/identity_setup/identity_setup.gd

## 已经实现的功能
- RS-07 已实现复用同一房间背景 res://assets/environment/rooms/player_room_01.png，RestRoomEnvironment.apply_tendency() 能在正统、异端、荒谬间切换装饰和光照。
- 当前房间环境仅组合在战斗结束的 RestResultView Overlay 内。RestResultView.show_result() 需要 RestSession 已打开的有效战斗结果，RestSession.open_result() 只接受 pk_win_unbroken 或 breakthrough_oracle_complete 与有效 level_id。
- SceneRouter.goto_game() 当前进入 scenes/sandbox/sandbox.tscn；Sandbox._ready() 随即 restart_current_attempt()，开始第一场普通弹幕和攻击。
- 已有 RS-09 负责战后休息继续到下一普通关；RS-10 负责最后普通关进入神降临。这些已有进度和结算规则继续沿用。

## 本次任务
新增**新周目首次进入的「开局房间」入口**。ID-09 完成主播名、12 身份之一和粉丝团名字的最终确认及存档后，玩家先进入休息时刻的主角房间，在房间界面中再主动进入第一场直播。

### 开局房间展示
- 使用现有 RestRoomEnvironment 场景及唯一共享的主角房间背景，使用已保存的 SaveData.tendency_state.get_primary_tendency_id() 取得开局倾向，以 RS-07 既有规则展示对应装饰与光照。三项累计值为零时，既有 TendencyState 已使用开局身份倾向作为主导参照。
- 房间展示为真实游戏场景或可操作页面，与战后结算页使用同一房间视觉底层及必要可复用控件。
- 开局第一次进入房间时不应该显示战斗胜利、矛盾未击破、获得奖励、圣典 / 败者卡本场结算等文案。只显示适合开局的房间与可用操作；房间内的其他 UI 内容可先以符合现有 Theme 的最小占位实现，后续按策划另行打磨。
- 保留一条明确、可交互的「开始直播」入口，使玩家能够从房间主动开始第一场普通战斗；开始后沿用目前 Sandbox 第一关初始化及关卡配置。
- 进入房间后正常展示主播名与粉丝团名时，读取现有 SaveData 的已确认字段，不新增第二份存档数据。

### 开局与战后房间的区别
- **新周目开局房间**：身份刚完成；没有任何战斗结果；当前普通关还没有开始。展示房间，等待玩家操作。
- **战后休息时刻**：真实战斗结束后，由 RestSession.open_result() 获得冻结结果并进入 RestResultView；继续沿用当前结果、历史查看和 RS-09/RS-10 路由。
- 设计与实现中明确区分两个入口，复用共享 RoomEnvironment。开局时不要为了让旧 show_result() 通过而制造虚假的 level_id、胜利状态或奖励快照，也不把开局房间写成普通关卡已完成。
- 最小复用已有 RoomEnvironment、UI Theme、运行态和 SceneRouter；根据实际 scene tree 与运行边界决定采用单独 Rest 起始页面或与 Sandbox 协作的明确开局态。引入新入口时保证接口名称和 owner 清晰，不增加不必要的全局 manager。
- 若必须修改 scenes/sandbox/sandbox.gd（Lane A 共享入口），先由该 Owner 接入或协作，防止覆盖正常战斗、神谕、战后休息、末关进入神降临的现有行为。

### 进入第一场直播
- 仅在玩家从开局房间主动请求开始直播后，执行一次第一关的标准初始化 / 正常战斗开始；请求成功后隐藏或退出房间 UI，并切换输入状态至战斗模式。
- 重复点击「开始直播」不能启动两份关卡、重置已存在周目资料或重复创建当前尝试。
- 开局房间内战斗攻击/瞄准输入不可生效；房间退出后继续沿用 Sandbox 的攻击、Tier、弹幕、PK 规则。
- 原有战后 RS-09 进入下一关和 RS-10 转入神降临保持当前运行行为。

### 验收条件
1. 新周目在 ID-09 第三页确认保存后显示主角房间，不自动生成第一场弹幕、不启动攻击或敌方 PK 回拉。
2. 房间复用 player_room_01.png 和 RS-07 同一套视觉部件；从四个正统、异端、荒谬身份中各选一个进入时，读取对应开局倾向并展现房间差异。
3. 无 RestSession 成果时可正常进入开局房间；本次没有任何伪造的完成关卡、获奖、胜利或新增历史记录。
4. 点击「开始直播」一次进入真实第一普通关，房间 UI 正确退出，恢复已有战斗输入、弹幕生成和 HUD。
5. 再次重复开始请求不会多次初始化；当前 SaveData 的主播名、身份 ID、粉丝团名、开局倾向保持正确。
6. 真实战斗成功/失败后仍沿用现有 Rest 结果、历史查看与普通关继续流程；开局入口不干扰 RS-09 / RS-10。
7. Godot 4.7.2 实际运行验收：主菜单 → ID-09 三页面 → 房间 → 开播 → 第一关，并核实房间与战斗输入切换、日志无新增错误。

## 本卡专项交付说明
- Godot 4.7.2 / GDScript / Windows / Android。涉及 Godot API 查询 godot_mcp，场景及节点优先通过 Godot-MCP-Native 检查。
- 本卡建立 Rest 的「开局入口」，不改写 RestSession 的战后冻结结果定义；仅对实际需要的 UI 组合、SceneRouter 入口及关卡启动最小接线。
- 先核实 main 最新状态与并发分工：RestRoomEnvironment / RestResultView 由 Rest UI owner 协调，Sandbox 与 SceneRouter 共享部分由相应 Owner 接入；不要在不同 Agent 工作区同时覆盖同一文件。
- 任务完成同步 docs/18. Rest/README.md 并新建 docs/18. Rest/休息时刻系统_RS-12_YYYY-MM-DD_log.md，记录开局入口、RoomEnvironment 复用、开始直播接线、真实运行结果和未确认内容。

## Godot 开发环境
- Godot 版本：4.7.2（开工核对 `project.godot`）
- 脚本语言：GDScript
- 项目根目录：仓库根目录（`project.godot` 所在目录）
- 目标平台：Windows / Android（基准分辨率 1920×1080，16:9）
- Godot 工程操作 MCP：`Godot-MCP-Native`
- Godot 官方文档 MCP：`godot_mcp`

## 执行要求
### 1. 先检查当前项目状态
- 确认当前 branch、未提交修改、已有实现；核对 `project.godot` 的版本、Autoload、插件、Input Map、渲染器。
- 检查相关 `.tscn`、`.gd`、`.tres`、`.res`、节点职责、信号与资源依赖；以真实工程和最新已合并代码为准。

### 2. 严格控制任务范围
- 本张卡只完成“本次任务”所定义的功能和验收；发现关联问题在日志中说明，按任务依赖单独处理。

### 3. 保持最小必要复杂度
- 依赖方向清晰、代码高内聚；拆分场景或脚本以独立变化、生命周期、状态、流程或复用等实际需求为依据。

### 4. 组合优于继承
- 根据现有结构，优先采用子节点、子场景、Resource、signal、公开方法组合行为；仅在明确的 is-a 关系中使用业务继承。

### 5. 保持场景边界
- 父场景协调生命周期与组合，子模块维护自身状态；跨系统通过公开接口、稳定 ID、signal 或数据对象协作。

### 6. 区分场景、逻辑和数据
- Node/Scene 承载场景行为，Resource 承载静态配置，普通脚本对象承载纯逻辑；新增 Autoload 需有真实跨场景生命周期需求。

### 7. 新增实现前按顺序检查
- 依次检查仓库已有实现、Godot 原生 API、已安装 addon/plugin 和语言标准能力；需要新实现时采用满足本卡的最小方案。

### 8. Godot API 不允许猜
- 对 Node、属性、方法、signal、枚举和版本行为存疑时，使用 `godot_mcp` 查询对应 Godot 官方文档并核实后实现。

### 9. 使用 Godot-MCP-Native 检查真实工程
- 涉及场景树、节点、Inspector、连接、运行状态与画面时优先使用 `Godot-MCP-Native` 实际检查；MCP 不可用时记录原因和可替代的 CLI / 人工验证。

### 10. 自动化与额外保障机制
- 优先复用既有测试入口；仅针对稳定可复现的规则补充必要自动化。视觉、动画、交互与手感以真实运行及人工验收为依据。
- hash、baseline、gate、contract 或额外框架必须有明确且可复现的失败依据。

### 11. 避免脆弱的 Godot 依赖
- 检查跨模块内部 NodePath、固定父级层级、节点名业务身份、跨场景 Node 引用和多余 Singleton 耦合；使用稳定公开接口协作。

### 12. 修改现有场景时尊重现有结构
- 修改前核对场景实例、继承、owner、Resource 内嵌/外部关系及信号连接来源，保留有效 UID、节点路径和现有引用。

### 13. 验证实际 Godot 行为
- 完成后检查脚本解析、Scene/Resource 加载、相关场景运行、Output/Debugger，以及本卡“验收条件”。
- 涉及 UI、动画、运动、输入或其他视觉表现时实际运行并保存必要截图；Headless 结果按其覆盖范围说明。

### 14. 完成前检查
- 复查范围、复用、复杂度、Scene/Resource 引用与信号方向、死代码和测试投入；确认本卡实际通过后提交。
- 每张开发任务使用独立 branch，按 `AGENTS.md` 提交对应系统的完成日志；合并前同步最新目标分支重新验证。

## 最终汇报
提交与本卡功能对应的变更及 Godot 实际运行结果，维护本系统 README 和本卡完成日志。
- **改动文件**：逐个说明文件、Scene、Resource 与公开接口的修改。
- **场景 / 节点变化**：列出相关 Scene 和 Node 的增删调整。
- **当前能做什么**：给出本卡完成后的可验证能力。
- **还不能做什么**：写清未覆盖、未验证及需人工确认的部分。
- **验证结果**：记录 Godot MCP、CLI、真实运行及必要的人工/截图验收结果。
- **下一步建议**：只提出由本卡实际状态支持的工作。
- **任务交接**：更新对应系统 README，按 `系统名_任务卡_YYYY-MM-DD_log.md` 写入并提交日期日志，包含主要变更、验证结果、遗留项、接手入口与文档更新情况。
