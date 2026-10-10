# 1. Identify 身份系统任务拆分

> **统一派工入口**：[2026-10-09 任务卡整合与依赖顺序](../开发计划_2026-10-09_任务卡依赖整合.md)。开发前核对该表、本卡现行版、main 实际实现及最新完成日志。


> **2026-10-09 已确定的程序流程**：主播取名 → 仓鼠爪印展示事件 → 动机漫画逐格自动/点击推进 → 十二身份牌单张点击翻开或【一键翻开】 → 房间电脑过渡 → 粉丝团取名 → 既有三项信息一次性保存并进入 RS-12。分镜内容和视觉资产由美术提供，程序只负责推进、等待展示完成信号、身份选择及现有存档接线。新增 ID-10～ID-13；[开场程序流程记录](../Original/2026-10-09_开场漫画分镜流程_待讨论.md)。

## 系统目标

身份系统负责本周目的三件基础信息：

1. 玩家确认的主播名；
2. 玩家确认的粉丝团名；
3. 玩家确认的开局身份。

确认后的主播名、粉丝团名和身份需要进入本周目数据，当前关卡重开时继续沿用。后续需要展示玩家侧信息的系统读取对应字段；【三项倾向系统】和【结局系统】读取开局身份。

本系统当前不负责三项倾向的累计，也不负责结局判词。它只把“开局是谁”保存好并提供给后续系统。

## 当前数据约定

- `IdentityOption` 是可编辑的 Godot `Resource`，包含稳定身份 ID、显示名称、完整原文 `description`、`Texture2D` 图标引用和倾向 ID。
- 倾向 ID 使用 `orthodox`、`heretical`、`absurd`，供后续系统读取；身份系统不负责累计倾向。
- 最终确认时，`SaveManager.confirm_opening_identity()` 将所选身份交给 `SaveData.tendency_state.initialize_from_identity_option()`，只提供开局比较参照。
- `data/identity/identity_*_1.tres` 至 `*_4.tres` 提供 12 份正式身份资源，标题、描述与 ID 来自 `data/source_tables/01_身份配置.csv`，图标保持为空。`IdentityOptions.CARDS` 保存任务卡规定的混排顺序；三份旧占位资源仅保留兼容用途，`IdentityOptions.find_option()` 可按正式或旧 ID 查询。
- `IdentityNameRules.confirm_streamer_name()` 与 `confirm_fan_group_name()` 共用 `confirm_name()` 规则；空字符串和纯空白回退到各自默认值，其他输入原样保留。
- 默认主播名目前为临时值“新主播”，正式文案确定后修改 `IdentityNameRules.DEFAULT_STREAMER_NAME`。
- 默认粉丝团名目前为临时值“新粉丝团”，正式文案确定后修改 `IdentityNameRules.DEFAULT_FAN_GROUP_NAME`。
- `IdentityConfirmationState` 首次只接受调用方从当前身份资源整理出的有效 ID，之后拒绝覆盖；运行持有者通过 `get_confirmed_identity_id()` 读取结果。
- `IdentityConfirmationState` 锁定后的身份 ID 可通过 `SaveManager.set_identity_data()` 写入 SaveData，供本周目场景重建后继续读取。
- `SaveData.streamer_name`、`SaveData.fan_group_name` 与 `SaveData.identity_id` 保存本周目确认结果；新周目初始化为空值，确认后由 `SaveManager.set_identity_data()` 一次写入。
- 新增字段有明确空值默认，并兼容旧版 SaveData，因此 `SaveData.CURRENT_VERSION` 保持 `1`。
- `ui/identity_setup/identity_setup.tscn/.gd` 提供三个独立全屏步骤。最终经 SaveManager 写入资料和开局倾向、保存成功后发出 `opening_saved(run_data: SaveData)`；RS-12 接收该事实后通过 SceneRouter 打开独立开局房间；路由失败仅重试进入房间。
- 第二步初始显示十二张占位卡背，首次点击翻开该卡，再次点击正面选择；正面沿用 ID-08 正式标题与描述，图标字段保留且不用于分组表现。

## 当前仓库状态

- 主菜单 Start 新建 SaveData 后进入主播取名 → 十二卡身份选择 → 粉丝团取名。最终提交、保存后经 RS-12 进入房间，玩家点击“开始直播”才进入 Game。
- 身份选项数据类型、12 份正式资源、三份旧兼容资源、独立身份步骤、名称确认、身份锁定、周目存档字段和三步身份设置页面已建立。
- `SaveManager` 已存在，并持有 `SaveData`。
- `SaveData` 包含版本、游玩时间、当前场景、checkpoint、主播名、粉丝团名和身份 ID 字段。
- 当前 `SceneRouter.goto_game()` 仍指向 Sandbox 技术测试场景，后续替换真实游戏入口时更新。
- 当前仓库没有独立单元测试框架。

## 任务顺序

| 任务卡 | 小功能 | 自动化测试 |
| --- | --- | --- |
| ID-01 | 定义身份选项数据 | 无 |
| ID-02 | 确认主播名，空白使用默认名 | 2 个关键单元测试 |
| ID-03 | 确认身份并在本周目锁定 | 2 个关键单元测试 |
| ID-04 | 把姓名和身份写入 SaveData | 无新增自动化测试 |
| ID-05 | 做身份设置界面 | 无新增自动化测试 |
| ID-06 | 接通主菜单 → 身份设置 → 游戏 | 无新增自动化测试 |
| ID-07 | 自定义粉丝团名并写入本周目数据 | 复用 ID-02 名称确认测试 |
| ID-08 | 十二身份卡片选择与开局三倾向映射（独立步骤已实现） | 1 个 CSV/映射回归用例、原锁定测试、真实图形 UI smoke 通过 |
| ID-09 | 三步开局流程：主播取名 → 12 身份卡 → 粉丝团取名，最终提交已实现，房间接入 BLOCKED_RS12 | 复用原有存档测试与真实流程 smoke；RS-12 负责开局房间入口 |
| ID-10 | 单张身份卡独立翻开，二次点击选择，回退保留本轮状态（已实现） | Godot 4.7.2 Windows GUI / headless 事件 smoke，既有身份回归通过 |
| ID-11 | 一键翻开十二张身份卡，保留选择并继续现有保存流程（已实现） | Godot 4.7.2 Windows GUI 合成事件 smoke、身份映射回归通过 |
| ID-12 | 独立漫画分镜计时、点击推进、末格确认与暂停恢复（已实现） | Godot 4.7.2 runtime TEST_ONLY 三格流程 smoke |

## ID-08 可复用身份步骤（2026-10-09）

- `ui/identity_setup/identity_selection.tscn` 是身份第二步的独立全屏视图。基准 1920×1080 同时展示 4×3 卡片；1280×720 提供纵向滚动，960×540 提供双向滚动，状态与下一步控件常驻。卡片标题 30px、描述 21px，统一沿用现有 Theme，不显示底层倾向或图标。
- `selection_changed(option: IdentityOption)` 通知临时选择变化；`next_requested(option: IdentityOption)` 交出具体身份和倾向。视图自身没有 SaveManager、TendencyState 或 SceneRouter 调用。
- `restore_selection(identity_id: StringName, locked: bool = false)` 支持入树前设置与回退恢复。`get_selected_option()` 读取选择；重新显示后调用 `focus_selection()` 恢复键盘焦点。初始空选，下一步禁用。
- ID-09 持有临时 ID，连接 `next_requested` 后切入第三步粉丝团取名，最终复用既有身份锁定、存档与倾向初始化入口提交。真实三步流程及 RS-12 房间跳转已接通。本卡运行 smoke 使用明确标注的临时 TEST_ONLY 第三步接收端。
- 已确认的旧 `identity_orthodox`、`identity_heretical`、`identity_absurd` 以 `locked=true` 恢复时沿用旧 Resource、原 ID 和原开局倾向，卡片禁用、显示沿用记录；不映射到任何新角色。未知已存 ID 同样锁住并禁用下一步。调用方继续负责最终确认锁定。
- 本次资源直接由既有 CSV 建立，正文未改动；Google Sheet 在线内容未能访问。现有导表工具仍负责 Sheet → CSV，后续修改身份正文时同步相应 `.tres` 并运行 `tests/unit/identity_mapping_test.gd` 核对完整正文与映射。没有增加导表基础设施。
- ID-09 已将 `identity_setup.tscn/.gd` 接为三步流程。身份卡底部提供默认隐藏的 `BackButton`，由流程显示，与下一步并排；原独立第二步默认行为保持。

## 三步开局流程（ID-09 / RS-12 已接通）

- 开局身份从当前 3 个占位选项升级为 12 张正式身份卡片，每张卡片展示标题与完整描述；正式内容来自 data/source_tables/01_身份配置.csv，与 Google Sheets 的「01_身份配置」对应。
- 12 张卡片在 1920×1080 的身份页面固定采用 **4 列 × 3 行**混排，顺序详见 ID-08 任务卡。玩家侧仅看到角色扮演信息与统一交互反馈，内部三个倾向仅用于游戏逻辑。
- 12 个独立 identity_id 分别保存具体选中身份，对应的运行时 tendency_id 仍只有 orthodox、heretical、absurd（每类 4 个）。表格中的 heresy 在 Godot 运行时映射为 heretical。
- 现有 SaveData、IdentityConfirmationState、TendencyState 的存档与开局比较职责沿用；**主播名、身份选择、粉丝团名分成三个依次进入的独立全屏步骤**，各自仅显示当前步骤的输入/选择。
- ID-09 确定顺序为「你叫什么？」→ 12 身份卡 →「粉丝团叫什么？」；最终确认后统一保存三项身份数据及开局倾向，然后经 RS-12 入口进入**休息时刻的主角房间**。第一场普通战斗须从房间主动开始。
- ID-09 三页、正式提交、保存、房间展示及主动进入第一普通关已完成真实 Godot 4.7.2 GUI 验收；详见 Rest 的 RS-12 日期日志。

## 测试预算

身份系统只给容易被以后改坏、同时可以快速运行的纯逻辑写单元测试：

- 空白主播名和粉丝团名会分别回退到各自默认名字；
- 正常主播名和粉丝团名会保留玩家输入；
- 第一次身份确认会成功；
- 本周目已经确认后，第二次选择不会改掉身份。

静态 Resource 字段、UI 排版、按钮连接、场景切换和现有 SaveManager 流程不逐项增加单元测试。

这些功能继续按任务卡做最小 Godot 解析、资源加载和实际运行检查。

## 后续系统怎么拿身份数据

ID-07 完成后，本周目的主播名、粉丝团名和身份使用稳定数据保存在 `SaveData` 中。

后续：
- 【三项倾向系统】读取开局身份作为比较依据；
- 直播 UI、休息时刻等需要展示玩家侧信息时读取 `fan_group_name`；
- 【结局系统】读取主播名和开局身份。

等 17、20 系统开发时再做具体接线，不在身份系统阶段提前实现它们。

## ID-09 接口与状态边界（2026-10-09）

- 第一步只输入主播名；继续时应用 `confirm_streamer_name()`。第二步复用 12 张正式卡，第三步只输入粉丝团名，可回看主播名与身份；任一中间步骤均不写 SaveData。回退保留名称和所选具体 ID。
- `SaveManager.confirm_opening_identity(streamer_input, option, fan_input, confirmation) -> Error` 只接受正式 `IdentityOptions.CARDS` 中的 Resource；复用 IdentityConfirmationState 首次锁定及 `set_identity_data()`，在同一次最终调用中初始化开局倾向。已存身份或已锁定对象返回 `ERR_ALREADY_IN_USE`，不会覆盖或重新初始化。
- 第三页提交后锁住输入和回退。保存失败保留同一周目、已确认值与倾向，按钮重试仅执行 `save_game()`；保存成功后发出一次 `opening_saved(run_data: SaveData)`。同步重入和连续确认不会再次写身份或初始化倾向。
- 已存正式 / 旧三身份重新打开时显示第三页且锁定，不转换旧 ID；未知身份锁住且禁止继续。直接启动场景而没有 SaveData 时，第一步显示主菜单提示并禁止前进。
- RS-12 已在页面连接 `opening_saved`，经 `SceneRouter.goto_opening_room()` 打开独立真实房间。成功期间保持忙碌锁；路由失败后按钮变为“重试进入房间”，仅重试路由，保留已存同一周目和身份。房间读取真实倾向与名称；显式开播才调用原 `goto_game()`，没有战后 RestSession。
- RS-12 已补齐 ID-09 的房间与首战验收：三倾向各一张正式卡完成三步保存 → 房间 → 主动开播；房间 / 开播失败重试和连点保护通过。Android 实机触控未验证。
## 漫画式开场分镜状态

ID-12 已提供独立的漫画播放控制 Node，按配置发出 1-based 分镜编号请求，并提供当前编号、点击推进、暂停 / 恢复和末格结束通知。正式分镜顺序、原画与内容仍待美术和策划确认；ID-13 负责把控制器接入开场流程，详见 [开场分镜草案](../Original/2026-10-09_开场漫画分镜流程_待讨论.md)。ID-12 未接入身份页面、存档或 SceneRouter。

## 2026-10-09 开场交互程序任务

| 任务卡 | 单功能 | 前置 |
| --- | --- | --- |
| [ID-10](tasks/ID-10_identity-card-click-reveal.md) | 玩家点击单张身份卡翻开 | 现有 ID-08 |
| [ID-11](tasks/ID-11_reveal-all-identity-cards.md) | 一键翻开全部身份卡 | ID-10 |
| [ID-12](tasks/ID-12_comic-panel-playback-control.md) | 漫画分镜的自动计时与点击推进 | 现有 ID-09 |
| [ID-13](tasks/ID-13_opening-identity-flow-reorder.md) | 将既有身份步骤接入开场漫画流程 | ID-10～ID-12、现有 ID-09/RS-12 |

身份资源、十二卡固定混排顺序、单选信号、姓名确认、三项存档与房间入口均沿用现有实现；程序任务以界面事件与流程为边界，画面内容由美术自行制作。

## ID-10 单张身份卡翻开（2026-10-10）

- `identity_selection.gd` 以身份 ID 保存各卡的页面临时翻开状态；新页面初始十二张背面。首次点击只翻该卡，保留已有选择且不发 `selection_changed`；正面再次点击复用原单选与 `next_requested`。
- 卡背使用“身份牌 / 点击翻开”文字占位。`_present_card_face(button: Button, revealed: bool)` 是统一表现入口，目前直接切换 `CardFace/Front` 与 `CardFace/Back`，后续美术从此接图片或翻面动画；本卡没有正式翻牌美术。
- ID-09 返回主播取名或从粉丝团取名回退时复用同一控件，保留已翻开的卡及当前选择。`restore_selection()` 恢复正式选项时让所选卡保持正面；其余卡的状态保持。创建新页面会重置临时状态。
- 键盘聚焦仅滚动到卡片，Enter 与鼠标采用相同的两次操作。十二份资源、名称、正文、顺序、稳定 ID、SaveData 与既有信号签名保持原样。
- Windows Godot `4.7.2.stable.steam.ed1daf0bf` 的实际 GUI 和 headless smoke 各通过 115 项检查，退出码均为 0；1920×1080 与 960×540 截图已核对。自动事件注入覆盖逐卡两次点击、选择保留、两个步骤回退、键盘和小窗口下一步。既有映射、名称和锁定测试退出码均为 0。
- 未进行人工物理键鼠、Android 实机、最终保存或房间路由复验；详细命令、失败修正与证据位置见 [ID-10 日志](身份系统_ID-10_2026-10-10_log.md)。ID-11～ID-13 继续由各自任务卡负责。

## ID-11 一键翻开身份卡（2026-10-10）

- `identity_selection.tscn` 在现有导航行加入 `RevealAllButton`。新页面十二张牌从背面开始；点击“一键翻开”会遍历正式 `IdentityOptions.CARDS`，逐张复用 `_present_card_face()`，并保存到页面现有的 `_revealed_ids`。
- 全部翻开后按钮显示“已全部翻开”并禁用。流程不改当前选中身份、不额外发出 `selection_changed`；下一步继续使用原有 `next_requested` 和 `identity_setup.gd` 接线。身份资源、SaveData、SaveManager 与 SceneRouter 均未改动。
- Windows Godot `4.7.2.stable.steam.ed1daf0bf`、D3D12 / Forward+ 的 GUI smoke 通过，真实运行退出码为 0：从十二张背面一键翻开；再从主播名页进入身份页，先翻三张、选择第三张、执行一键翻开；验证选择保持、十二张正面、下一步显示所选身份、保存到磁盘并进入现有开局房间。
- 自动操作使用 `Viewport.push_input()` 注入合成鼠标事件。实体键鼠、Android 触控未验收。截图和运行日志保存在忽略目录 `.godot/id11/`；详细结果与 MCP/导入边界见 [ID-11 日志](身份系统_ID-11_2026-10-10_log.md)。

## ID-12 漫画分镜播放控制（2026-10-10）

- `ui/identity_setup/comic_panel_playback_control.gd` 是独立 Node。调用方在 `start_playback()` 前配置 `panel_count` 与 `panel_interval_seconds`；启动立即发出第 1 格请求，之后由子 Timer 自动推进。`current_panel_number` 供外部读取，`panel_display_requested(panel_number)` 供外部美术组件选择素材。
- `advance_on_click()` 在普通格立即请求下一格并重新计时；末格停止自动计时，保持当前编号，下一次点击发出一次 `playback_completed`。`pause_playback()` / `resume_playback()` 直接暂停和恢复 Timer，保留剩余时间。
- `tests/identity_setup/id12_comic_panel_playback_test.tscn` 用 3 个显式 `TEST_ONLY_PANEL_n` 内容核对请求映射、自动 / 点击推进、暂停边界、末格停留与单次完成；内容占位可整体替换，不包含正式剧本文案或美术资源。
- Windows Godot `4.7.2.stable.steam.ed1daf0bf` headless runtime 退出码为 0、stderr 为空。暂停前剩余期望约 617 ms，恢复后 611 ms 自动到达下一格；完整输出、环境隔离与边界说明见 [ID-12 日志](身份系统_ID-12_2026-10-10_log.md)。
- 本卡未接 ID-09 开场流程，也未修改正式素材、身份数据、存档、导表器、四关数据或 SceneRouter。视觉与美术验收随正式分镜资源接入再进行。
