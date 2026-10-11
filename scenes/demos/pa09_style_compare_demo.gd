extends Control

## 使用未改动的正式 Sandbox 场景树作预览背景，只关闭其开局流程。
## 三版仅替换局部命中词、准星旁结算数值、仓鼠受击动画；无额外 HUD。
const SANDBOX_SCENE: PackedScene = preload("res://scenes/sandbox/sandbox.tscn")
const VIEW: PackedScene = preload("res://systems/barrage_generation/barrage_view.tscn")
const IMPACT_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_presenter.gd")
const ASSET_CONFIG: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const KIWI: Texture2D = preload("res://assets/characters/opponents/kiwi/kiwi_idle.png")
const PREVIEW_DIR := "res://docs/Shared/PresentationAssets/previews"
const STYLE_NAMES := ["a_clean", "b_ink", "c_impact"]
const CASE_NAMES := ["small", "large", "block", "reflect", "multi", "miss"]
const AIM_DESIGN := Vector2(945, 655)

@onready var _feedback: Control = $Feedback
var _sandbox: Control
var _hud: Control
var _reticle: AimReticle
var _targets: Array[BarrageView] = []
var _impact_presenter: BarrageImpactPresenter
var _preview_generation: int = 0
var _style: int = 0
var _case: int = 2
var _auto: bool = false
var _auto_time: float = 0.0
var _capture: bool = false


func _ready() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture-pa09")
	# 复用正式布局和节点；不运行 Sandbox 会启动正式周目的 _ready()。
	_sandbox = SANDBOX_SCENE.instantiate() as Control
	_sandbox.set_script(null)
	_sandbox.name = "ExistingSandbox"
	var unconfigured_input := _sandbox.get_node_or_null("AttackChargeInput")
	if unconfigured_input != null:
		unconfigured_input.set_script(null)
	add_child(_sandbox)
	move_child(_sandbox, 0)
	_sandbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud = _sandbox.get_node("BattleHud")
	_reticle = _sandbox.get_node("BattleHud/AimReticle") as AimReticle
	# 本页对照固定同一发射位置，避免系统鼠标移动让准星与结算字错位。
	_reticle.set_process_input(false)
	var battle_zone: Control = _sandbox.get_node("BattleHud/BattleArea/BarrageArea") as Control
	_hud.call("configure_streamers", "煲煲", "Kiwi")
	_hud.call("configure_streamer_assets", ASSET_CONFIG.player_streamer_portrait, ASSET_CONFIG.player_live_background, null, KIWI, null, null)
	_hud.call("refresh_pk", 0.62, 2)
	_create_real_barrage_views(battle_zone)
	_impact_presenter = IMPACT_SCRIPT.new() as BarrageImpactPresenter
	battle_zone.add_child(_impact_presenter)
	_impact_presenter.size = battle_zone.size
	resized.connect(_refresh_after_layout)
	_fit_preview()
	_choose(0, 2)
	call_deferred("_refresh_after_layout")
	if _capture:
		call_deferred("_capture_variants")


func _create_real_barrage_views(zone: Control) -> void:
	var lines := [
		{"text":"神说：睡觉也算上班", "at":Vector2(540,295),"id":"orthodox"},
		{"text":"这属于另一种福报", "at":Vector2(225,450),"id":"heretical"},
		{"text":"今日宜拜一拜自己", "at":Vector2(740,530),"id":"absurd"}
	]
	for entry in lines:
		var record := BarrageRuntimeRecord.new()
		record.text = String(entry["text"])
		record.original_sentence_id = "pa09_" + String(entry["id"])
		record.original_sentence_text = record.text
		record.tendency_id = String(entry["id"])
		record.strength = 2.0
		if String(entry["id"]) == "heretical":
			record.trait_set.add_trait(&"occlusion")
		elif String(entry["id"]) == "absurd":
			record.trait_set.add_trait(&"reflect")
		record.expires_at_msec = Time.get_ticks_msec() + 1200000
		var view := VIEW.instantiate() as BarrageView
		view.setup(record, 0.0, zone)
		zone.add_child(view)
		view.position = entry["at"]
		_targets.append(view)


# 当前场景由正式 Sandbox 处理 UI 比例；同一坐标尺度供三个局部效果共用。
func _fit_preview() -> void:
	var ratio := Vector2(size.x / 1920.0, size.y / 1080.0)
	_feedback.position = Vector2.ZERO
	_feedback.size = Vector2(1920,1080)
	_feedback.scale = ratio
	if _reticle != null:
		_reticle.move_touch_aim(AIM_DESIGN * ratio, 144.0)


func _refresh_after_layout() -> void:
	await get_tree().process_frame
	_choose(_style, _case)


func _sync_hit_target_rects() -> void:
	# 将 BarrageView 的实际变换映射到 Feedback 的本地坐标；支持缩放的 Sandbox。
	var to_feedback: Transform2D = _feedback.get_global_transform_with_canvas().affine_inverse()
	var rects: Array[Rect2] = []
	for view in _targets:
		if not is_instance_valid(view):
			continue
		var transform: Transform2D = view.get_global_transform_with_canvas()
		var top_left: Vector2 = to_feedback * (transform * Vector2.ZERO)
		var bottom_right: Vector2 = to_feedback * (transform * view.size)
		rects.append(Rect2(top_left, bottom_right - top_left))
	_feedback.call("set_target_rects", rects)


func _choose(next_style: int, next_case: int) -> void:
	_style = next_style
	_case = next_case
	if _reticle != null:
		_fit_preview()
	_sync_hit_target_rects()
	_feedback.call("preview", _style, _case)
	_play_material_feedback()
	if _reticle != null:
		_reticle.play_shot_feedback()


# 三种材质都来自真实 BarrageView；每次选择同发演出，供程序美术实际观察。
func _play_material_feedback() -> void:
	_preview_generation += 1
	_impact_presenter.reset_effects()
	for view in _targets:
		if is_instance_valid(view):
			view.show()
	var indices: Array[int] = []
	match _case:
		0, 1:
			indices = [0]
		2:
			indices = [1]
		3:
			indices = [2]
		4:
			indices = [1, 2]
	for index in indices:
		var view: BarrageView = _targets[index]
		var result: BarrageTraitResult = view.runtime_record.trait_set.get_hit_result()
		_impact_presenter.play_target_result(view, result)
		if index == 0:
			# 普通玻璃实体退场，保留 Presenter 的临时碎裂副本。
			view.hide()
			_restore_target_after_effect(view, _preview_generation)


func _restore_target_after_effect(view: BarrageView, generation: int) -> void:
	await get_tree().create_timer(0.35).timeout
	if is_instance_valid(view) and _preview_generation == generation:
		view.show()


func _process(delta: float) -> void:
	if _capture or not _auto:
		return
	_auto_time += delta
	if _auto_time >= 2.0:
		_auto_time = 0.0
		_choose(_style, (_case+1) % CASE_NAMES.size())


func _unhandled_key_input(event: InputEvent) -> void:
	if _capture or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1, KEY_2, KEY_3:
			_choose(int(key.keycode)-int(KEY_1), _case)
		KEY_Q:
			_choose(_style, 0)
		KEY_W:
			_choose(_style, 1)
		KEY_E:
			_choose(_style, 2)
		KEY_R:
			_choose(_style, 3)
		KEY_T:
			_choose(_style, 4)
		KEY_Y:
			_choose(_style, 5)
		KEY_P:
			_choose(_style, _case)
		KEY_SPACE:
			_feedback.call("toggle_pause")
		KEY_TAB:
			_auto = not _auto
			_auto_time = 0.0
		_:
			return
	get_viewport().set_input_as_handled()


# 由 Godot GUI 的真实 GPU 帧截取；不对截图进行模拟绘制。
func _capture_variants() -> void:
	var dir_absolute := ProjectSettings.globalize_path(PREVIEW_DIR)
	var err := DirAccess.make_dir_recursive_absolute(dir_absolute)
	if err != OK:
		push_error("PA09 preview directory error %s" % err)
		get_tree().quit(2)
		return
	for i in range(3):
		for j in [0,1,2,4,5]:
			_choose(i,j)
			_feedback.call("seek_at", 0.22)
			await get_tree().create_timer(0.12).timeout
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var resolution: String = "1280" if img.get_width() <= 1300 else "1920"
			var filename: String = "pa09_v2_%s_%s_%s.jpg" % [STYLE_NAMES[i],CASE_NAMES[j],resolution]
			var save_err := img.save_jpg(dir_absolute.path_join(filename),0.94)
			print("PA09_V2_FRAME %s %s saved=%d pixels=%s" % [STYLE_NAMES[i],CASE_NAMES[j],save_err,img.get_size()])
			if save_err != OK:
				get_tree().quit(2)
				return
	print("PA09_V2_DONE frames=15 styles=3 cases=5")
	get_tree().quit(0)
