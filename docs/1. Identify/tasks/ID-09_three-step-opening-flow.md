# ID-09 新周目开局三步流程：取名 → 身份选择 → 粉丝团取名

**状态：开局三步交付并有日志 · 2026-10-09 · [完成日志](../身份系统_ID-09_2026-10-09_log.md)；原日志所述 RS-12 房间接线须按后续整局验收核查**

> **2026-10-09 已确定的后续程序接线**：本卡三项资料采集及一次性保存已实现。新开场编排归 ID-13，分镜点击/计时推进归 ID-12，身份卡单张翻开与【一键翻开】分别归 ID-10/ID-11。美术负责制作分镜与转场画面，现有 ID-09 的保存与 RS-12 房间入口保持复用。

## 开始前先阅读以下文档
- AGENTS.md、known_traps.md、project.godot
- docs/System_Collaboration.md
- docs/Original/任务卡模板.md
- docs/1. Identify/README.md
- docs/1. Identify/tasks/ID-02_player-name-confirmation.md
- docs/1. Identify/tasks/ID-03_identity-confirm-lock.md
- docs/1. Identify/tasks/ID-04_identity-save-data.md
- docs/1. Identify/tasks/ID-05_identity-setup-ui.md
- docs/1. Identify/tasks/ID-06_identity-flow-wiring.md
- docs/1. Identify/tasks/ID-07_custom-fan-group-name.md
- docs/1. Identify/tasks/ID-08_twelve-identity-card-selection.md 及最新完成日志
- docs/18. Rest/README.md 与 RS-12 开局房间入口任务卡
- 当前代码中的 ui/main_menu/、ui/identity_setup/、core/autoload/scene_router.gd、core/autoload/save_manager.gd、core/save/save_data.gd、core/rest/、ui/rest/

## 已经实现的功能
- 主菜单 Start 已调用 SaveManager.new_game()，再通过 SceneRouter.goto_identity_setup() 打开身份页。
- 当前身份页把「主播名 / 身份选项 / 粉丝团名」放在同一个页面，并在确认后经 SceneRouter.goto_game() 直接进入 Sandbox 普通战斗。
- IdentityNameRules 已分别提供主播名和粉丝团名的输入确认与默认值规则。
- IdentityConfirmationState 实现本周目身份首次确认锁定；SaveManager.set_identity_data()、SaveData 的 streamer_name / identity_id / fan_group_name 保存三项结果；TendencyState.initialize_from_identity_option() 使用所选身份的底层倾向。
- ID-08 已登记 12 张正式身份卡片的 4 列 × 3 行固定混排及三倾向映射；本卡接入该步骤，不重新实现身份列表与映射。
- 当前 RestResultView 属于战后结果视图，RestSession.open_result() 只接受真实关卡结束结果；新周目直接进房间由 RS-12 另行实现。

## 本次任务
将「单页输入两个名字及选身份」重组为**依次前进的三个独立全屏步骤**。功能可复用同一顶层场景中的三个子界面，或采用与项目已有结构一致的顶层场景切换；玩家感知必须是依次跳转的三个界面。

### 页面一：你叫什么？
- 新周目从主菜单 Start 进入本页，主问题文案为「你叫什么？」。
- 仅提供主播名输入与继续操作。沿用 IdentityNameRules.confirm_streamer_name() 与当前空白默认名规则。
- 确认名字后进入第二页「身份选择」。暂存此周目已确认的主播名，在后续步骤可回看；无需因单一中间步骤新增持久存档结构。
- 在界面文案、装饰与轻量动画上延续《邪恶冥刻》式旧纸牌、仪式氛围；设计仍允许后续美术打磨，优先由 Godot Theme / StyleBox 实现可用原型。

### 页面二：你是谁？（十二身份）
- 单独展示 ID-08 的全部 12 张正式身份卡片，4×3 固定混排、标题与完整描述、统一选中/悬停反馈。
- 此页**只负责身份选择**，不出现主播名或粉丝团名输入框，也不显示正统/异端/荒谬类别或类别专属标记。
- 用户选中一张身份卡片并点击确认后，进入第三页「粉丝团取名」；保留该卡片的具体 identity_id 及对应倾向，以供最终一次提交。
- 未选择任何卡片时给出明确提示，允许更换当前选择；沿用 ID-08 既有的稳定身份 ID 和 heresy → heretical 映射。
- 提供按自然步骤返回上一页的能力；返回与再进入本页时保留已输入主播名和临时选中卡片。

### 页面三：粉丝团叫什么？
- 单独提供粉丝团名输入及最终确认。主问题可采用「粉丝团叫什么？」作为暂定界面文案。
- 沿用 IdentityNameRules.confirm_fan_group_name() 与空白使用现有默认粉丝团名的规则。
- 确认后，使用现有 SaveManager / IdentityConfirmationState 完成三项资料的一次性正式提交：streamer_name、identity_id、fan_group_name；同时初始化 TendencyState 的开局倾向，并保存本周目。
- 本步骤确认成功后，**首先进入休息时刻的主角房间**，调用 RS-12 提供的开局房间入口；不能沿用旧流程直接进入普通战斗。
- 若提交 / 存档 / 进入房间失败，提供明确反馈和重试入口；重复点击不能多次完成身份确认、丢失输入内容或生成多个新周目。
- 最终确认前可返回修改上一步；最终成功确认后本周目身份保持锁定，符合现有 IdentityConfirmationState 规则。

### 流程与状态边界
```text
MainMenu.Start（新建 SaveData）
  → ① 你叫什么？ / 主播名输入
  → ② 你是谁？ / 12 身份卡片选择
  → ③ 粉丝团叫什么？ / 粉丝团名输入
  → 正式确认、保存三个字段及开局倾向
  → 休息时刻：主角房间（依赖 RS-12）
  → 由房间中现有/后续确认的进入直播操作开始第一场正常战斗
```
- 每一步分离显示；逻辑中间状态归开局页面管理，正式确认仍复用已有存档所有者，防止中间数据被误判为已完成周目。
- 游戏阶段切换由 SceneRouter / 当前实际入口所有者完成；按现有 Godot 结构最小改动，避免为三个页面创建三套重复的保存/确认机制。
- 若 RS-12 尚未完成，ID-09 可以先实现步骤切换和最终提交准备，最后的房间跳转在 RS-12 完成后联调。**不能用战斗页或伪造的战后 RestSession 充当房间入口。**
- 保持已有身份卡设计：12 个显示选项、内部 3 种倾向；身份逻辑不添加第四种倾向。
- PC / Android 项目基准为 1920×1080、16:9；三个步骤均保证基本操作、焦点、可读性。正式风格与转场动画可后续细化，本卡完成可运行流程。

### 验收条件
1. 从主菜单新周目开始，首次看到「你叫什么？」及主播名输入，而非旧的三项混合页面。
2. 确认主播名后仅进入 12 身份卡片页；选择身份后仅进入粉丝团取名页，三个页面独立可辨识。
3. 返回上一步及再前进时能保留已输入/选中的临时信息；改选身份最终保存最新身份 ID。
4. 空白主播名、空白粉丝团名沿用原有集中默认值，填写的文字正常保留。
5. 最终确认后 SaveData 保存正确的主播名、独立身份 ID、粉丝团名，TendencyState 保存正确的三倾向之一；读档仍是相同结果。
6. 最终确认成功后看见主角房间及对应开局倾向的房间表现，由 RS-12 负责接入；此时第一场 PK 没有自动开始。
7. 页面前进/回退、点击、键盘焦点、最终重试行为可用；连续确认不会重复初始化周目或触发多次房间切换。
8. 在 Godot 4.7.2 真实运行新周目完整流程并检查 Output/Debugger；有独立子测试价值的纯规则沿用已有测试。

## 本卡专项交付说明
- 引擎 Godot 4.7.2，GDScript；Windows / Android。Godot-MCP-Native 用于场景与 UI 实际检查；godot_mcp 用于核实存在疑问的 API。
- 开工先确认 main 当前代码、已合并 PR 与 ID-08 的实现程度；检查 AGENTS.md 和 known_traps.md。
- 优先复用现有身份 Resource / 名称规则 / 保存 API 与 Godot UI 组件。职责集中，真实有独立变化原因时才拆分子页面。UI 不直接修改 17 的累计规则。
- 本任务可以独立分支开发，涉及 SceneRouter 等共享入口时与 Lane A / RS-12 的实际修改 Owner 协调，合并前以最新 main 复审。遵守项目一张卡一个 Agent、完成写中文日志的约定。
- 完成后更新 docs/1. Identify/README.md 现状与接口说明，新增 docs/1. Identify/身份系统_ID-09_YYYY-MM-DD_log.md，记录修改位置、实际运行步骤、最终保存的字段与倾向、房间跳转结果和未验证项。

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
