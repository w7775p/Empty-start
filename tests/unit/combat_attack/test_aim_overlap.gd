extends SceneTree

const AimIntersectionScript = preload("res://systems/combat_attack/barrage_aim_intersection.gd")

var _failures: int = 0
var _completed: int = 0


func _init() -> void:
	_test_internal_intersection()
	_test_edge_contact_intersection()
	# 原边界坐标确实为半径 5；向外挪 0.01 必须落空，防止恒真判定。
	_expect_intersection(false, AimIntersectionScript.circle_overlaps_rect(
		Vector2.ZERO, 10.0, Rect2(5.01, -2.0, 4.0, 4.0)
	), "outside edge misses")

	if _failures > 0:
		push_error("CA-02: %d/%d case(s) failed." % [_failures, _completed])
		quit(1)
		return

	print("CA-02: %d cases passed." % _completed)
	quit(0)


# 准心圆心位于弹幕矩形内部时判为相交。
func _test_internal_intersection() -> void:
	var intersects: bool = AimIntersectionScript.circle_overlaps_rect(
		Vector2(5.0, 5.0),
		10.0,
		Rect2(0.0, 0.0, 10.0, 10.0)
	)
	_expect_intersection(true, intersects, "internal intersection")


# 准心圆周恰好接触弹幕矩形边缘时也判为相交。
func _test_edge_contact_intersection() -> void:
	var intersects: bool = AimIntersectionScript.circle_overlaps_rect(
		Vector2.ZERO,
		10.0,
		Rect2(5.0, -2.0, 4.0, 4.0)
	)
	_expect_intersection(true, intersects, "edge contact")


func _expect_intersection(expected: bool, actual: bool, case_name: String) -> void:
	_completed += 1
	if actual == expected:
		print("PASS: %s" % case_name)
		return

	_failures += 1
	push_error("FAIL: %s; expected intersection=%s, got %s." % [case_name, expected, actual])
