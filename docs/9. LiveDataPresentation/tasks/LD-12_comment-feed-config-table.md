# LD-12 直播评论词库导表与配置读取

**状态：待开发 · 普通直播评论流**

## 开始前阅读
- `AGENTS.md`、`project.godot`、本系统 README 及最新完成日志
- 现有 `LiveDataHud`、`Sandbox`、源表导出器与主播粉丝牌资源
- 前置或接口参考：现有 `tools/export_game_data.py`、直播数据与关卡数据读取方式；后续 LD-13

## 当前实现与复用入口
当前 `data/source_tables/09_直播数据.csv` 是观看、点赞、评论计数与粉丝规则表；现有 `tools/export_game_data.py` 使用 `SHEET_NAMES`、`RULES`、`NUMERIC` 校验并导出策划表。

## 本卡唯一功能
直播评论词库导表与配置读取。

## 触发条件
策划编辑直播评论配置，或一场战斗创建玩家/对手评论流时。

## 应发生的行为
新增独立的「19_直播评论词库」策划表及同名 CSV 导表入口，定义每条评论的 `comment_id`（稳定 ID）、`username`（用户名）、`text`（评论正文）、`audience_type`（fan / passerby）、`side_scope`（player / opponent / both）、`weight`（随机权重）、`enabled`（是否参加抽取）及可选 `streamer_id`（限定对手主播的稳定ID）。延续既有导表器及资源读取约定，向后续评论生成提供可读取、按侧和当前主播筛选、仅包含启用且合法条目的配置数据。`streamer_id` 为空时属于通用评论，填写具体对手ID时只在该主播对应关卡参与候选。策划以后按此结构直接补充评论文本与昵称。

## 验收
策划表导出后，每条有效评论可正确读取用户名、正文、粉丝/路人、可用阵营与权重；指定玩家或对手时按 `side_scope` 取得候选，并按当前关 `LevelProfile.streamer_id` 同时选出通用评论与该对手专属评论；修改配置后再次导表可生效；保留文字中的标点、Emoji 与空格。

## 交付
提交本卡对应的程序、Godot 实际运行验证与日期日志，更新本系统 README。
