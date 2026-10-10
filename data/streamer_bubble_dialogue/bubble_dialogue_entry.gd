## 单条气泡对白配置，只保存文本与触发信息。
class_name BubbleDialogueEntry
extends Resource

enum SpeakerSide { PLAYER, OPPONENT }
enum Priority { TIMED_IDLE = 0, HIT = 1, PLOT = 2 }

@export var side: SpeakerSide = SpeakerSide.PLAYER
@export_multiline var text: String = ""
## 沿用 LevelSpeech 的稳定原句 ID；状态和闲聊对白可留空。
@export var original_sentence_id: String = ""
@export var event_id: StringName = &""
## 3 秒仅为可调初值，正式时长等待策划试玩确认。
@export_range(0.1, 60.0, 0.1, "or_greater") var display_duration_seconds: float = 3.0
@export var priority: Priority = Priority.HIT
