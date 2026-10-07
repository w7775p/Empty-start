extends SceneTree

const TENDENCY_STATE = preload("res://core/tendencies/tendency_state.gd")


func _initialize() -> void:
	var state: TendencyState = TENDENCY_STATE.new()
	state.orthodox_total = 7
	state.heretical_total = 11
	state.absurd_total = 13
	state.record_normal_speech_tendency("orthodox", 2)
	state.record_normal_speech_tendency("heretical", 3)
	state.record_normal_speech_tendency("absurd", 5)
	state.commit_attempt_tendency()
	state.commit_attempt_tendency()
	var passed: bool = state.orthodox_total == 9 and state.heretical_total == 14 and state.absurd_total == 18
	passed = passed and state.attempt_orthodox_total == 0 and state.attempt_heretical_total == 0 and state.attempt_absurd_total == 0
	if passed:
		print("PASS TT-03 PK win commits attempt tendency once")
		quit(0)
	else:
		push_error("TT-03 win tendency commit failed")
		quit(1)
