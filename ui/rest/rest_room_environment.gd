class_name RestRoomEnvironment
extends Control

@onready var _backdrop: TextureRect = %RoomBackdrop
@onready var _tint: ColorRect = %RoomTint
@onready var _left_votive: ColorRect = %LeftVotive
@onready var _right_votive: ColorRect = %RightVotive


# 只更改同一房间的光照和装饰；空或未知倾向还原中性状态。
func apply_tendency(tendency_id: String) -> void:
	_left_votive.rotation_degrees = 0.0
	_right_votive.rotation_degrees = 0.0
	match tendency_id:
		"orthodox":
			_backdrop.modulate = Color(1.0, 0.88, 0.68)
			_tint.color = Color(0.48, 0.28, 0.06, 0.28)
			_left_votive.color = Color(1.0, 0.76, 0.30, 0.68)
			_right_votive.color = _left_votive.color
			_left_votive.show()
			_right_votive.show()
		"heretical":
			_backdrop.modulate = Color(0.75, 0.70, 1.0)
			_tint.color = Color(0.27, 0.10, 0.53, 0.34)
			_left_votive.color = Color(0.67, 0.32, 0.94, 0.72)
			_right_votive.color = Color(0.44, 0.80, 1.0, 0.56)
			_right_votive.rotation_degrees = 13.0
			_left_votive.show()
			_right_votive.show()
		"absurd":
			_backdrop.modulate = Color(0.94, 1.0, 0.92)
			_tint.color = Color(0.02, 0.40, 0.36, 0.30)
			_left_votive.color = Color(1.0, 0.25, 0.66, 0.85)
			_right_votive.color = Color(0.24, 1.0, 0.82, 0.85)
			_left_votive.rotation_degrees = -13.0
			_right_votive.rotation_degrees = 14.0
			_left_votive.show()
			_right_votive.show()
		_:
			_backdrop.modulate = Color.WHITE
			_tint.color = Color(0.08, 0.10, 0.13, 0.20)
			_left_votive.hide()
			_right_votive.hide()
