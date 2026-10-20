# RS-14 · 休息房间开播电脑图与操作界面美术接入

**状态：待开发（仅任务卡）。优先级：P1。Owner：RS-14 休息室 UI Agent，领取时独占本卡列出的运行文件。**
**基线：开发前核对最新 `main` HEAD；功能 PR → `main`。** 以 2026-10-20 已实施的最新 main 任务卡为准，避免沿 2026-10-19 的旧候选分支重放改动。

## 开始前先阅读以下文档
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/Original/任务卡模板.md`。
- `docs/18. Rest/README.md`、`docs/18. Rest/tasks/RS-12_new-run-opening-room.md`、`docs/18. Rest/tasks/RS-13_post-victory-result-continue-or-rest.md`。
- `docs/Shared/PresentationAssets/PA-21_资产接入状态_2026-10-19.md`、`docs/Shared/PresentationAssets/Art_Intake_Rename_2026-10-19.md`。
- `ui/rest/rest_opening_room.gd` / `.tscn`、`ui/rest/rest_room_environment.gd` / `.tscn`、`core/autoload/scene_router.gd`；如有必要只读确认 `scenes/sandbox/sandbox.gd` 结算后返回房间的调用。

## 已经实现的功能
- `RestOpeningRoom` 已经使用 `RestRoomEnvironment` 展示主角房间背景和桌面、正统/异端/荒谬倾向环境效果，并显示主播名、粉丝团名、当前关卡提示与“开始直播”按钮。
- `rest_opening_room.gd` 的 `start_live()` 已通过 `SceneRouter.goto_game()` 开播，具备存档验证、暂停中拒绝、重复点击锁定、跳转失败恢复入口与进度恢复。主菜单继续已完成关卡进度时可直接回这个房间。
- 当前开播页在正式房间背景前仍显示中央通用 `PanelContainer`，作为视觉交互比较临时；仓库已有 `assets/environment/player_room/laptop_start_stream.png`（764×512）但正式开播场景未找到图像消费。
- **共享环境场景** `rest_room_environment.tscn` 同时被身份建档过渡、休息房间及战斗结算使用；修改它会影响其他界面。

## 本次任务
1. **正式使用电脑图：** 在 `ui/rest/rest_opening_room.tscn` 开播页接入 `assets/environment/player_room/laptop_start_stream.png`，作为房间里的**开播交互主体**。在原有背景、桌面、倾向效果上按实际画稿比例安排位置、上下遮挡关系，保持图片原始宽高比；图片必须在正式场景运行可见，禁止通过新黑底或全屏大面板遮住房间。
2. **替换临时中央面板的呈现：** 去掉或显著弱化笨重的中央通用 `PanelContainer`，让视线落在电脑上；“主播名 / 粉丝团名 / 即将开始第几场 / 开始直播”信息使用可读、轻量的房间内文字与按钮编排。沿用已有站酷快乐体/思源字体与项目主题；不要新增身份、奖励、历史收藏或其他未确认房间功能。
3. **电脑开播交互：** 点击电脑的明确可见热区可调用**现有唯一 `start_live()` 入口**。维持原 `StartLiveButton` 的键盘焦点/确认键、鼠标悬停或按下反馈和已绑定的通用点击音效；可把既有按钮视觉与电脑图绑定，避免新增第二套开播逻辑。点击区域与图像实际可见位置一致；暂停、载入失败、重复连点时原错误提示与 disabled 状态必须仍然可见且正确。
4. **只修改开播页，保护共享房间：** 默认仅调整 `rest_opening_room.gd` / `.tscn` 的本地表现；保持共享 `RestRoomEnvironment` 的背景、桌子、倾向色和场景结构；**不要把电脑直接加进共享环境**，以免身份确认过渡与结算面板都出现开播电脑。不得改变 `SaveManager`、`SceneRouter`、`RestSession`、`ui/rest/rest_result_view.*` 的业务行为。
5. **双分辨率和正式流程验收：** 真实运行 `rest_opening_room.tscn` 的 1920×1080 与 1280×720，检查电脑图、字体、信息区、鼠标热区和遮挡。至少在正式流程确认两条入口：新周目身份确认→房间→开播、已完成关卡的继续游戏→房间→开播；使用实际数据而非固定文本。暂停菜单仍可用，保存后的下一关号正确，开播失败能再次点击。

## 本任务所属分支和文件归属
- **唯一主要运行文件 Owner：RS-14 Agent → `ui/rest/rest_opening_room.gd`、`ui/rest/rest_opening_room.tscn`。** 只在这两个文件内修改/连接开播页画面，不改变被多个流程复用的 `rest_room_environment.gd/.tscn`。
- 与 INT-24 战斗背景、INT-22 直播统计图标、PB-25 教学、RS-13 后结算选择相互独立；不得改 `ui/live_data/live_data_hud.gd`、`ui/plan_b/plan_b_battle_ui.gd`、`scenes/sandbox/sandbox.gd` 或 `ui/rest/rest_result_view.*`。若有其他任务占用本卡文件，先锁唯一 Owner 再开工。
- 开发从最新 main 建独立分支和 D 盘工作树；保存缓存、日志、截图和临时文件均放 D 盘，不占 C 盘。

## Godot 开发环境
Godot 4.7.2；GDScript；项目根目录 `Empty-start/`；Windows PC、1920×1080 逻辑分辨率，检查 1280×720。工程操作 MCP：Godot-MCP-Native；官方文档 MCP：godot_mcp。

## 最小执行流程
1. 核对 main 与现有开播页场景节点、电脑素材尺寸、当前文件 Owner。
2. 在 D 盘独立工作树完成电脑图、信息区与现有开播按钮的视觉组合；每个独立子任务分别 commit。
3. 最小场景加载 + 真实 1920×1080 / 1280×720 关键截图；一次涵盖鼠标、键盘、暂停及恢复关卡的开播行为检查即可。
4. 写 `docs/18. Rest/休息系统_RS-14_2026-10-20_log.md`（按实际实施日期调整），同一功能 PR 提交代码与真实截图；视觉未人工确认保持 Draft。

## 执行要求（沿用仓库14项模板）
1. **先检查当前项目状态：** 分支、未提交更改、场景树、实际图层与入口。
2. **严格控制任务范围：** 仅开播房间视觉与交互。
3. **保持最小必要复杂度：** 使用现有房间实例和输入节点。
4. **组合优于继承：** 直接组合电脑图片及既有 Button，无新基类。
5. **保持场景边界：** 房间页只表现，开播仍由既有入口完成。
6. **区分场景、逻辑和数据：** 画面不推算关卡进度或操纵 SaveData。
7. **新增实现前按顺序检查：** 查现有 Godot UI 组件、主题、点击声。
8. **Godot API 不允许猜：** 焦点、鼠标事件和纹理缩放查 godot_mcp。
9. **使用 Godot-MCP-Native 检查真实工程：** 看共享房间实例、画面、按钮与信号。
10. **自动化与额外保障机制：** 最小手动/Godot检查即可，不扩建框架。
11. **避免脆弱的 Godot 依赖：** 保留现有业务方法和数据来源。
12. **修改现有场景时尊重现有结构：** 保留 UID、owner、`StartLiveButton` 信号语义。
13. **验证实际 Godot 行为：** 单次开播、暂停、失败回退、重进房间均正确。
14. **完成前检查：** 不覆盖身份建档、结算房间、关卡恢复与音量菜单。

## 验收标准与最终汇报
- 正式房间确实显示 `laptop_start_stream.png`，电脑成为明确开播交互区域；中央临时大面板不再遮挡主要房间画面。
- 1920×1080、1280×720 下电脑、文字和热区对应，鼠标点击与键盘确认均能开播；暂停与输入焦点正常，失败时保留可重试入口，无双重开播。
- 主播名/团名与下一关来自已有真实存档；从新周目或继续游戏回房间、再开播均使用正确进度；结算界面与身份建档的共享房间表现未被本卡污染。
- 功能 PR 交代 PNG → 运行节点、改动文件、最少相关 Godot 画面、代码 SHA 和已知问题。无真实图证或审美未通过时保持 Draft，不自动合并。
