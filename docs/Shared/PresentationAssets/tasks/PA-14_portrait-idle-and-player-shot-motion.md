# PA-14 主播立绘基础动效与主角射击反馈

> 状态：已完成 · PR #109 已合并 · 2026-10-10 · [完成日志](../表现资产_PA-14_2026-10-10_log.md)
> 类型：程序美术 / PresentationAssets
> 依赖：PA-03 已接入的双主播立绘、CombatAttack 正式发射通知

## 开始前先阅读以下文档
- docs/Original/任务卡模板.md、known_traps.md
- `AGENTS.md`、`known_traps.md`、`project.godot`、`docs/System_Collaboration.md`
- `docs/Shared/PresentationAssets/README.md`、`assets/README.md`、最新相关完成日志
- `scenes/sandbox/sandbox.tscn`、`scenes/sandbox/sandbox_battle_hud.gd`

## 已有素材与目标
- 主角：`res://assets/characters/player/hamster_idle.png`；对手：`res://assets/characters/opponents/{alien,kiwi,fox}/` 下已有的待机 / 阶段 PNG。
- **所有在场的主播立绘平时都具有轻微动画**。第一版统一采用整张静态 PNG 的轻量呼吸、漂浮或摇摆，按每个角色提供不同频率与强度的可调预设；待实际录屏试玩后，再确定是否需要专属的局部动作。第一版不依赖新增切图交付。
- 主角正式发射言弹时，主播立绘配合做一个短促射击动作；玩家实际言弹仍由 PA-07 从准星中心飞出。

## 已经实现的功能
- PA-03 已接入 `scenes/sandbox/sandbox_battle_hud.gd/.tscn` 的 `PlayerPortraitArt`、`OpponentPortraitArt` 两个正式 PNG 槽；`configure_streamer_assets()` 和 `set_opponent_portrait_connected()` 是贴图与连线可见性入口。
- `AttackChargeInput.shot_snapshot_created` 是满蓄正式发射时的事件来源；玩家图为 `assets/characters/player/hamster_idle.png`，对手素材位于 `assets/characters/opponents/{alien,kiwi,fox}/`。
- 本卡交付的动效层及真实 HUD 接线另列在完成结果中，区别于开工时的基础。

## 本次任务
### 1. 通用待机
- 对当前已显示的玩家和对手立绘，使用 `Tween` / `AnimationPlayer` 组合**轻微上下位移、1～3% 左右的呼吸伸缩、微小角度左右摇摆**，形成可循环的生命感；不同角色通过参数改变频率 / 相位，使两侧并非完全同步。
- 保留原始立绘构图，运动中心设置在角色身躯附近；对手在 T0 离线不显示，在切换立绘时保持同一动画容器。
- 幅度、周期、相位、缩放、旋转可调；与右侧接入直播 CRT、左侧受击及其他事件动画叠加时，允许在独立容器上做叠加或短暂降低待机幅度，事件完成后平顺恢复。

### 2. 主角仓鼠发射言弹时的反应
- 读取 CombatAttack 的**有效满蓄发射**通知（当前 `shot_snapshot_created`），让左侧仓鼠做一次**小幅度向前冲 / 身体压缩 → 轻微后坐抖动 → 回弹原位**的漫画式反应。
- 发射动作短促，保持仓鼠外形和可读性；连续射击时可取消前一段事件 Tween 并从正确姿态重新播放。
- 可调前冲距离、方向、压缩幅度、震颤次数、恢复时间；发射后仍持续轻微待机。

## 程序接线
- 优先复用已有左右 `TextureRect` 显示入口，在立绘本体与父层拆分待机 / 事件视觉变换；统一从已有攻击信号触发一次射击演出。
- 使用 PNG 整体动效完成首版，无需新增逐帧美术。

### 验收条件
- 左右主播实际显示时各有轻微呼吸、漂浮或摇摆，画面不会像静态截图；T0 无对手。
- 一发真实射击只触发一次仓鼠短促冲刺 / 回弹；未蓄满松开不会播放发射动作。
- 动画与 PA-09、PA-11 等事件同屏时可正常叠加 / 恢复；1920×1080 及 Windows / Android 运行验证通过。

## 本卡专项交付说明
新增 `docs/Shared/PresentationAssets/表现资产_PA-14_YYYY-MM-DD_log.md`，记录表现入口、参数和真实画面验证。

## 本卡完成结果（2026-10-10）
- [PR #109](https://github.com/w7775p/Empty-start/pull/109) 已合并；新增 `systems/presentation/streamer_portrait_motion.gd` 和 HUD 的 `bind_portrait_attack()`、`play_player_shot()`、`configure_portrait_character()`。
- [完成日志](../表现资产_PA-14_2026-10-10_log.md) 包含独立 HUD 动效验证；整局战斗接线仍待集成验证，不把局部测试扩展为整局已过。

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
