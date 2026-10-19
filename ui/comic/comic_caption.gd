class_name ComicCaption
extends Resource

# Each caption can be a speech bubble, narration, danmaku, or bare on-screen text.
@export_enum("speech", "narration", "danmaku", "label") var kind: String = "speech"
@export_multiline var text: String = "【角色台词待定】"
@export var rect: Rect2 = Rect2(1200, 750, 580, 140)
@export var tail: Vector2 = Vector2(-1, -1)
@export var delay: float = 0.55

# Optional per-caption typography. Empty font uses the project theme.
# Transparent color preserves legacy speech/narration/danmaku colors.
@export_range(12, 300, 1) var font_size: int = 30
@export_file("*.ttf", "*.otf") var font_path: String = ""
@export var text_color: Color = Color.TRANSPARENT


static func visible_text_length(bbcode: String) -> int:
	# Playback durations count readable characters, not markup tags.
	var tag_pattern := RegEx.create_from_string("\\[[^\\]]+\\]")
	return tag_pattern.sub(bbcode, "", true).length()
