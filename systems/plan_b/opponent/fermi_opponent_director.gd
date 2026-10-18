class_name PlanBOpponentDirector
extends RefCounted

signal publish_word_requested(word_id: String, spawn_position: Vector2)
signal counterattack_windup_started(request: Dictionary)
signal counterattack_effect_requested(request: Dictionary)
signal counterattack_resolved(result: Dictionary)
signal opponent_word_pool_exhausted(level_id: String, streamer_id: String)

const SPAWN_MARGIN_PIXELS := 16.0

var speech_enabled: bool = true
var counterattack_enabled: bool = true

var _content_catalog: Object
var _profile: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _counterattack_effect_handler: Callable = Callable()
var _level_id: String = ""
var _streamer_id: String = ""
var _spawn_area: Rect2 = Rect2()
var _speech_cooldown_remaining: float = 0.0
var _pending_speech_word_id: String = ""
var _awaiting_speech_publish_result: bool = false
var _counterattack_cooldown_remaining: float = 0.0
var _windup_remaining: float = 0.0
var _pending_counterattack: Dictionary = {}
var _awaiting_counterattack_result: bool = false
var _counterattack_uses: int = 0
var _last_publish_request: Dictionary = {}
var _last_counterattack_event: Dictionary = {}
var _opponent_pool_exhausted_reported: bool = false
var _configured: bool = false


## 注入 C 的静态内容配置与随机种子；时钟、发表和棋子状态继续由 A/B 拥有。
func configure(content_catalog: Object, seed_value: int = 1) -> bool:
	_configured = false
	_content_catalog = content_catalog
	if content_catalog == null or not content_catalog.has_method("get_opponent_config") \
		or not content_catalog.has_method("get_word_ids"):
		return false
	# A 先用正式 LevelProfile 配置 C；导演读取当前主播参数，不再绑定费米配置。
	_profile = content_catalog.call("get_opponent_config")
	if _profile.is_empty():
		return false
	_level_id = str(_profile.get("level_id", ""))
	_streamer_id = str(_profile.get("streamer_id", ""))
	if _level_id.is_empty() or _streamer_id.is_empty():
		return false
	_rng.seed = seed_value
	_spawn_area = Rect2()
	speech_enabled = bool(_profile.get("speech_enabled", false))
	counterattack_enabled = bool(_profile.get("counterattack_enabled", false))
	_speech_cooldown_remaining = float(_profile.get("initial_speech_delay_seconds", 0.0))
	_counterattack_cooldown_remaining = 0.0
	_windup_remaining = 0.0
	_pending_counterattack.clear()
	_awaiting_counterattack_result = false
	_counterattack_uses = 0
	_last_publish_request.clear()
	_last_counterattack_event.clear()
	_pending_speech_word_id = ""
	_awaiting_speech_publish_result = false
	_opponent_pool_exhausted_reported = false
	_configured = true
	return true


## A 可注入执行器调用 B 的公开效果入口；C 不直接修改棋子。
func set_counterattack_effect_handler(handler: Callable) -> void:
	_counterattack_effect_handler = handler


## A 在战斗开始时传入 B 使用的棋盘范围；C 只在范围内选择批次落点。
func set_spawn_area(spawn_area: Rect2) -> bool:
	if not spawn_area.has_area() or spawn_area.size.x <= SPAWN_MARGIN_PIXELS * 2.0 \
		or spawn_area.size.y <= SPAWN_MARGIN_PIXELS * 2.0:
		_spawn_area = Rect2()
		return false
	_spawn_area = spawn_area
	return true


## A 每帧传入 B 的快照与自身可发表词 ID；C 选择词句和坐标，发表结果仍由 A 裁决。
func update_speech(
	delta: float,
	neutral_unit_snapshots: Array[Dictionary],
	available_opponent_word_ids: Array[String]
) -> void:
	if not _configured or not speech_enabled or _awaiting_speech_publish_result:
		return
	var word_ids: Array[String] = _get_publishable_opponent_word_ids(available_opponent_word_ids)
	if word_ids.is_empty():
		_report_opponent_pool_exhausted()
		return
	_speech_cooldown_remaining = maxf(0.0, _speech_cooldown_remaining - maxf(0.0, delta))
	if _speech_cooldown_remaining > 0.0:
		return

	var spawn_position: Variant = _choose_spawn_position(neutral_unit_snapshots)
	if not spawn_position is Vector2:
		return

	var word_id: String = word_ids[_rng.randi_range(0, word_ids.size() - 1)]
	_pending_speech_word_id = word_id
	_awaiting_speech_publish_result = true
	_last_publish_request = {"word_id": word_id, "spawn_position": spawn_position}
	# A 将坐标请求送入双方共用的整批 publish_word；成功事实回来后才启动对手冷却。
	publish_word_requested.emit(word_id, spawn_position)


## A 回报整批发表结果；失败保留词与冷却，成功才开始发言间隔。
func report_speech_publish_result(word_id: String, published: bool) -> bool:
	if not _configured or not _awaiting_speech_publish_result or word_id != _pending_speech_word_id:
		return false
	if published:
		_speech_cooldown_remaining = float(_profile.get("speech_cooldown_seconds", 11.5))
	_pending_speech_word_id = ""
	_awaiting_speech_publish_result = false
	return true


## A 每帧传入双方人数与 B 的对手棋子快照，控制器只发出反击请求事件。
func update_counterattack(
	delta: float,
	faction_counts: Dictionary,
	opponent_unit_snapshots: Array[Dictionary]
) -> void:
	if not _configured or not counterattack_enabled or not bool(_profile.get("counterattack_enabled", false)):
		return
	if _counterattack_uses >= int(_profile.get("counterattack_max_uses", 0)):
		return

	var elapsed: float = maxf(0.0, delta)
	_counterattack_cooldown_remaining = maxf(0.0, _counterattack_cooldown_remaining - elapsed)
	if not _pending_counterattack.is_empty():
		if _awaiting_counterattack_result:
			return
		_windup_remaining = maxf(0.0, _windup_remaining - elapsed)
		if _windup_remaining <= 0.0:
			_request_counterattack_effect()
		return
	if _counterattack_cooldown_remaining > 0.0:
		return

	var player_count: int = int(faction_counts.get("player", 0))
	var opponent_count: int = int(faction_counts.get("opponent", 0))
	var lead_margin: int = int(_profile.get("counterattack_lead_margin", 0))
	if player_count - opponent_count < lead_margin:
		return
	var opponent_unit_ids: Array[String] = _get_unit_ids_for_team(opponent_unit_snapshots, "opponent")
	if opponent_unit_ids.is_empty():
		return

	var request := {
		"skill_id": str(_profile.get("counterattack_skill_id", "")),
		"trigger_event": str(_profile.get("counterattack_trigger_event", "")),
		"target_unit_id": opponent_unit_ids[_rng.randi_range(0, opponent_unit_ids.size() - 1)],
		"effect_id": StringName(str(_profile.get("counterattack_effect_id", ""))),
		"effect_parameters": {
			"child_count": int(_profile.get("counterattack_child_count", 0)),
		},
		"pre_windup_seconds": float(_profile.get("counterattack_pre_windup_seconds", 0.0)),
		"cooldown_seconds": float(_profile.get("counterattack_cooldown_seconds", 0.0)),
	}
	if str(request["skill_id"]).is_empty() or String(request["effect_id"]).is_empty():
		return
	_pending_counterattack = request
	_windup_remaining = float(request["pre_windup_seconds"])
	_last_counterattack_event = request.duplicate(true)
	# D 可在此事件后显示前摇提示；效果到时仍交由 A 调用 B 的公开接口。
	counterattack_windup_started.emit(request.duplicate(true))
	if _windup_remaining <= 0.0:
		_request_counterattack_effect()


## A/B 完成效果后回报结果；本模块据此更新尝试次数和冷却，不改棋子状态。
func report_counterattack_result(applied: bool) -> bool:
	if not _configured or _pending_counterattack.is_empty() or not _awaiting_counterattack_result:
		return false
	var result: Dictionary = _pending_counterattack.duplicate(true)
	result["applied"] = applied
	_counterattack_cooldown_remaining = float(_pending_counterattack.get("cooldown_seconds", 0.0))
	if applied:
		_counterattack_uses += 1
	_pending_counterattack.clear()
	_awaiting_counterattack_result = false
	_windup_remaining = 0.0
	_last_counterattack_event = result.duplicate(true)
	counterattack_resolved.emit(result)
	return true


## 提供调试用值副本，便于 A/D 观察冷却、请求和反击阶段。
func get_debug_snapshot() -> Dictionary:
	return {
		"configured": _configured,
		"level_id": _level_id,
		"streamer_id": _streamer_id,
		"speech_enabled": speech_enabled,
		"speech_cooldown_remaining": _speech_cooldown_remaining,
		"pending_speech_word_id": _pending_speech_word_id,
		"awaiting_speech_publish_result": _awaiting_speech_publish_result,
		"spawn_area": _spawn_area,
		"last_publish_request": _last_publish_request.duplicate(true),
		"counterattack_enabled": counterattack_enabled,
		"counterattack_cooldown_remaining": _counterattack_cooldown_remaining,
		"counterattack_windup_remaining": _windup_remaining,
		"counterattack_uses": _counterattack_uses,
		"pending_counterattack": _pending_counterattack.duplicate(true),
		"last_counterattack_event": _last_counterattack_event.duplicate(true),
		"opponent_word_pool_exhausted_reported": _opponent_pool_exhausted_reported,
	}


func _get_publishable_opponent_word_ids(available_ids: Array[String]) -> Array[String]:
	var result: Array[String] = []
	var configured_ids: Array = _content_catalog.call("get_word_ids", _level_id, "opponent")
	for word_id_value: Variant in configured_ids:
		var word_id: String = str(word_id_value)
		if not available_ids.has(word_id):
			continue
		var definition: Dictionary = _content_catalog.call("get_word_definition", word_id)
		if str(definition.get("available_level", "")) == _level_id \
			and str(definition.get("available_to", "")) == "opponent" \
			and str(definition.get("streamer_id", "")) == _streamer_id:
			result.append(word_id)
	return result


func _report_opponent_pool_exhausted() -> void:
	# A 收到一次耗尽事件后继续推进流程；避免逐帧重复通知。
	if _opponent_pool_exhausted_reported:
		return
	_opponent_pool_exhausted_reported = true
	opponent_word_pool_exhausted.emit(_level_id, _streamer_id)


func _choose_spawn_position(neutral_snapshots: Array[Dictionary]) -> Variant:
	if _spawn_area.has_area():
		var min_x: float = _spawn_area.position.x + SPAWN_MARGIN_PIXELS
		var max_x: float = _spawn_area.position.x + _spawn_area.size.x - SPAWN_MARGIN_PIXELS
		var min_y: float = _spawn_area.position.y + SPAWN_MARGIN_PIXELS
		var max_y: float = _spawn_area.position.y + _spawn_area.size.y - SPAWN_MARGIN_PIXELS
		return Vector2(_rng.randf_range(min_x, max_x), _rng.randf_range(min_y, max_y))

	# 兼容旧 A 调用：范围尚未注入时，只复用已有中立单位坐标，不传递其 unit_id。
	var candidate_positions: Array[Vector2] = []
	for snapshot: Dictionary in neutral_snapshots:
		if str(snapshot.get("team", "")) != "neutral":
			continue
		var position: Variant = snapshot.get("position", null)
		if position is Vector2:
			candidate_positions.append(position)
	if candidate_positions.is_empty():
		return null
	return candidate_positions[_rng.randi_range(0, candidate_positions.size() - 1)]


func _get_unit_ids_for_team(snapshots: Array[Dictionary], team: String) -> Array[String]:
	var result: Array[String] = []
	for snapshot: Dictionary in snapshots:
		if str(snapshot.get("team", "")) != team:
			continue
		var unit_id: String = str(snapshot.get("unit_id", ""))
		if not unit_id.is_empty():
			result.append(unit_id)
	return result


func _request_counterattack_effect() -> void:
	_awaiting_counterattack_result = true
	_last_counterattack_event = _pending_counterattack.duplicate(true)
	var request: Dictionary = _pending_counterattack.duplicate(true)
	if _counterattack_effect_handler.is_valid():
		# 执行入口由 A 注入并转接 B；返回值只表示本次效果是否成功应用。
		report_counterattack_result(bool(_counterattack_effect_handler.call(request)))
	else:
		counterattack_effect_requested.emit(request)
