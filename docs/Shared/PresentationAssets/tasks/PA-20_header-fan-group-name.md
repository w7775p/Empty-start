# PA-20 战斗主播信息区以粉丝团名替换静态粉丝牌

**状态：待开发 · 最新 HUD 顶部规则**

## 开始前先阅读以下文档
- `AGENTS.md`、`project.godot`、`docs/Original/任务卡模板.md`
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`
- `core/save/save_data.gd`、`data/level_configuration/level_profile.gd`、`docs/2. LevelConfiguration/README.md`
- `docs/9. LiveDataPresentation/tasks/LD-15_camp-fan-badges.md`、当前最新完成日志

## 已经实现的功能
当前 `BattleHud` 的左右 `InfoArea` 各有主播名 Label 和静态 `PlayerFanBadge` / `OpponentFanBadge` TextureRect；`SaveData.fan_group_name` 已在开局录入、保存并由休息房间读取；对手 `LevelProfile` 已有主播名和粉丝牌图片接口。策划总表 `02_主播关卡` 旧 `fan_badge_text` 字段更新为 `fan_group_name`。

## 本次任务
将**双方主播信息区右上角的固定粉丝牌图片槽**替换为粉丝团名称文字。

### 触发条件
玩家开播进入主战斗画面、读取本周目资料、切换当前对手或重开当前关时。

### 预期行为
继续沿用 `PlayerStreamerArea/PlayerInfoArea`、`OpponentStreamerArea/OpponentInfoArea` 现有主播名显示入口，在原顶部粉丝牌槽位置使用右对齐文字标签显示 `❤粉丝团名❤`，与主播名称形成同一行的 `主播名    ❤粉丝团名❤` 排列。玩家侧从 `SaveManager.data.fan_group_name`（即 `SaveData`）读取真实自定义名称；对手侧从当前 `LevelProfile` 增加的可编辑 `fan_group_name` 字段读取，供 `02_主播关卡.fan_group_name` 导表接入。主播信息区的静态粉丝牌 TextureRect 按本版布局调整为文本显示位，复用现有 HUD 资源与事件入口。左右 448px 信息区应适应较长合法名称、窗口缩放与上下文替换；空值时提供短占位文字保证排版完整。

原有玩家 `PresentationAssetConfig.player_fan_badge` 和对手 `LevelProfile.fan_badge_texture` 继续服务 LD-15 的直播评论粉丝徽章，不承担顶部名字展示。

### 验收条件
自定义粉丝团名从开局房间进入战斗后可在玩家主播名右方以 `❤名字❤` 展示；修改对手关卡粉丝团名后对手右上角显示对应文字，切关与重开同步更新；顶部原静态粉丝牌不再占位；已有评论徽章图片资源仍可由 LD-15 使用；1920×1080/1280×720 和 Android 缩放下主播名与团名清晰可辨。

## 本卡专项交付说明
提交本卡对应的 HUD 与配置接线变更、Godot 实际运行验证和日期日志，更新表现资产系统 README。

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

