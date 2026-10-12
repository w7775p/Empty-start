## 本关普通话语定义，跨系统沿用稳定原句 ID。
class_name LevelSpeech
extends Resource

## 普通弹幕及其复读等派生内容沿用同一个原句 ID。
@export var original_sentence_id: String = ""
@export_multiline var text: String = ""

## 普通前景的可选局部 BBCode 表现；解析后的正文必须与 text 相同。
@export_multiline var local_style_bbcode: String = ""

## 普通话语内容类别；neutral 不参与开局身份与三项倾向累计。
@export var tendency_id: String = ""

## 普通命中按内容强度结算；旧词库未填写时保持既有强度 1。
@export_range(1, 3, 1) var strength: int = 1

## 同一倾向内的相对出现权重；1.0 暂作等权默认值。
@export var appearance_weight: float = 1.0
