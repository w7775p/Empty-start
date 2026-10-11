# 美术与音频资源目录（2026-10-11 更新）

本目录按**运行用途**整理素材，保留美术交付的独立图片。角色所属直播间的背景统一归 `environment/live/`，主角休息房间归 `environment/player_room/`。

## 当前结构

```text
assets/
├── characters/
│   ├── player/
│   │   └── hamster_idle.png
│   └── opponents/
│       ├── alien/    # idle、tier_01~03、defeat_transition、defeat
│       ├── fox/      # idle、tier_01~03、defeat；effects/ 独立花瓣
│       ├── frog/     # idle、tier_01~03、defeat（新接收）
│       └── kiwi/     # idle、tier_01~03、defeat
├── environment/
│   ├── player_room/
│   │   ├── background.png       # 非直播：主角休息房间
│   │   └── foreground_desk.png  # 同房间透明桌子前景
│   └── live/
│       ├── hamster/
│       │   ├── background.png       # 主角直播背景（原 bg_ham_live_room）
│       │   └── foreground_desk.png  # 主角直播桌子前景
│       ├── alien/background.png
│       ├── frog/
│       │   ├── background.png       # 10-11 版：原 bg_frog_room1011
│       │   ├── background_alt.png   # 保留早期完整背景：原 bg_frog_room_01
│       │   └── foreground_cutout.png  # 透明前景：原 bg_frog_room_02
│       └── kiwi/background.png
├── ui/
│   ├── combat/
│   │   ├── fan_badges/  # 下文详列 6 张正式金银瓜子/粉丝 UI 资源
│   │   ├── feedback/
│   │   ├── impact_marks/
│   │   └── pk_bar/
│   ├── input_escape.svg
│   └── input_mouse_left.svg
├── audio/
│   ├── music/
│   └── sfx/  # interface、magical、Kenney 音效等（沿用已有内容）
└── fonts/
```

## 直播画面的图层规则

| 渲染顺序 | 内容 | 是否必须 | 说明 |
| --- | --- | --- | --- |
| Layer 0（底层） | `environment/live/<主播>/background.png` | 是 | 背景 |
| Layer 1（中层） | `characters/...` 对应主播立绘 | 是 | 主播 |
| Layer 2（顶层） | `foreground_desk.png` / `foreground_cutout.png` | 否 | 桌子或其他前景切图，在立绘之前遮挡 |

这些层级是**直播主播区的绘制前后顺序**；Godot 具体用节点先后顺序或 `z_index` 实现即可。各主播是否拥有前景层由资源配置决定，未提供切图的主播直接显示背景和角色。

- **主角休息房间**是独立场景，用 `environment/player_room/background.png`，桌子切图属于该房间的可选前景。
- **仓鼠直播间**使用 `environment/live/hamster/background.png`，直播桌子独立使用同目录 `foreground_desk.png`。
- **外星人、青蛙、Kiwi 房间**均按直播背景管理。
- 青蛙的 `background.png` 是 10-11 交付版本，`background_alt.png` 为保留版本；透明的 `foreground_cutout.png` 单独放在 Layer 2，具体遮挡内容可在视觉集成时确认。
- 狐狸直播间背景暂未收到；不以其他主播图片代替。

## 粉丝牌（正式资源）

全部归到 `assets/ui/combat/fan_badges/`，来源为“金银瓜子描边+主角粉丝UI投影”目录：

| 文件 | 用途 | 分辨率 |
| --- | --- | --- |
| `player_fan_badge_01.png` | 粉丝牌图标版本 01 | 144×144 |
| `player_fan_badge_02.png` | 粉丝牌图标版本 02 | 144×144 |
| `player_fan_ui_01_shadow.png` | 版本 01 完整 UI（带投影） | 256×144 |
| `player_fan_ui_01_no_shadow.png` | 版本 01 完整 UI（无投影） | 256×144 |
| `player_fan_ui_02_shadow.png` | 版本 02 完整 UI（带投影） | 256×144 |
| `player_fan_ui_02_no_shadow.png` | 版本 02 完整 UI（无投影） | 256×144 |

版本 01/02 保留原始对应关系，具体金银配置由 UI 系统确认。右上角主播名与粉丝团名的文字布局沿用已确认设计，粉丝牌图片的接入位置由对应直播 UI 组件决定。

## 角色立绘与阶段

现有对手 alien、fox、frog、kiwi 均具备 idle、tier_01~03、defeat；alien 另有 defeat_transition，fox 另有 4 张玫瑰效果。

| 实际战斗阶段 | 美术文件 |
| --- | --- |
| T0 | 不展示对手立绘 |
| T1 | idle |
| T2 | idle + 程序绘制汗滴 |
| T3 | tier_01 |
| T4 | tier_02 |
| T5 | tier_03 |
| Paradox | 继续显示 tier_03；真矛盾击破成功后进入 defeat 演出 |

- Alien：真击破使用 `alien_defeat_transition.png` 融化过渡后转 `alien_defeat.png`。
- Fox：使用 `effects/fox_rose_01~04.png` 构成花瓣演出。
- Kiwi：整张图局部变形演出后切换败北图。
- Frog：本次归档只整理立绘，实际出场配置与演出需求另行联调。

## 其他已接入或交付的 UI

- `ui/combat/pk_bar/`：`pk_bar_pos_01~06`、`pk_bar_neg_01~04`、`pk_indicator_01~02`。
- `ui/combat/impact_marks/`：4 套漫画命中图形及 SVG 原件。
- `ui/combat/feedback/player_hit_comic_01.png`：主角受击漫画画面。
- `ui/input_mouse_left.svg`、`ui/input_escape.svg`：按键图标。
- PK 来源 0 号正式图片仍未提供；当前 0 档使用已有 UI 底板占位。更多分段规则见原任务卡及提交历史。

## Godot 资源与 .import

- 原始 `.png` 和对应 `.png.import` **正常应在同一个目录**。Godot 自动生成/更新 `.import` 里的来源路径、资源 UID 和导入参数。
- Godot 的导入缓存放在项目根目录 `.godot/imported/`，这里的目录不同于源 PNG，是正常现象。
- 本次按用途移动了 **20 张 PNG**，并同步搬移存在的侧车 `.import`；改写了共享资源配置、休息室场景和 5 个演示场景中的旧背景路径。
- 历史遗留的 **37 个孤立 `.import`** 已备份到仓库外 `D:\Godot\Empty-start-asset-import-backup-20261011\`（保留原目录层级），供必要时取回旧 UID/设置。
- 运行 Godot 编辑器导入后，以**新位置**生成的元数据为准。临时资源旧引用 `environment/live/player_live_temp.png` 和 `environment/rooms/player_room_01.png` 已替换为正式图。
- 音频文件及尚未取得的正式字体原样保留。本次目录整理未做全套关卡接线，也未推断对手关卡顺序。

## 尚待美术/系统接入

- 狐狸主播直播间背景；其他主播如需独立前景切图，按 `environment/live/<主播>/foreground_*.png` 补充。
- 正式字体及许可证；其他主菜单、身份卡、败者卡、圣典、开场漫画资源。
- 新增的背景、桌子、青蛙立绘需要由直播场景和关卡配置接入，验证真实 Layer 0/1/2 遮挡关系。
