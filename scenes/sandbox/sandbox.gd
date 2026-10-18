extends Control

signal final_oracle_opened(session: FinalOracleSession)
signal rest_opened(session: RestSession)
signal rest_continue_requested(session: RestSession)
signal divine_descent_entered(session: DivineDescentSession)
signal dialogue_event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int)
signal mobile_safe_area_changed(safe_viewport_rect: Rect2)

const SAMPLE_TIER_CATALOG: CombatStageTierCatalog = preload("res://data/combat_stage/tier_catalog.tres")
const PRESENTATION_ASSETS: PresentationAssetConfig = preload("res://data/shared/presentation_asset_config.tres")
const FORMAL_SHEET_CONSUMER_SCRIPT: Script = preload("res://data/shared/formal_sheet_runtime_consumer.gd")
const CONTRADICTION_WINDOW_CONFIG: ContradictionWindowConfig = preload("res://systems/contradiction_break/contradiction_window_config.tres")
const HIT_ECHO_PRESENTER_SCRIPT: Script = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_hit_echo_presenter.gd")
const SPECIFIC_SENTENCE_REPLY_PRESENTER_SCRIPT: Script = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_specific_sentence_reply_presenter.gd")
const COMBAT_STATE_DIALOGUE_PRESENTER_SCRIPT: Script = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_combat_state_presenter.gd")
const TIMED_OPPONENT_DIALOGUE_PRESENTER_SCRIPT: Script = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_timed_opponent_dialogue_presenter.gd")
const REST_RESULT_VIEW_SCENE: PackedScene = preload("res://ui/rest/rest_result_view.tscn")
const TUTORIAL_HINT_SCENE: PackedScene = preload("res://ui/tutorial/tutorial_hint_view.tscn")
const BARRAGE_IMPACT_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_presenter.gd")
const PA09_FEEDBACK_SCRIPT: Script = preload("res://systems/presentation/combat_hit_feedback.gd")
const BATTLE_AUDIO_SCRIPT: Script = preload("res://core/audio/battle_audio_presenter.gd")
const PARADOX_COMIC_SCENE: PackedScene = preload("res://systems/presentation/paradox_comic_transition.tscn")
const PLAN_B_BATTLE_UI_SCENE: PackedScene = preload("res://ui/plan_b/plan_b_battle_ui.tscn")
const PLAN_B_HOST_SCRIPT: Script = preload("res://systems/plan_b/battle/plan_b_battle_host.gd")
const PLAN_B_SIMULATION_SCRIPT: Script = preload("res://systems/plan_b/simulation/plan_b_unit_simulation.gd")
const PB14_PERFORMANCE_TRACKER_SCRIPT: Script = preload("res://systems/plan_b/performance/pb14_performance_tracker.gd")
const PLAN_B_CONTENT_CATALOG_SCRIPT: Script = preload("res://systems/plan_b/content/plan_b_content_catalog.gd")
const PLAN_B_OPPONENT_DIRECTOR_SCRIPT: Script = preload("res://systems/plan_b/opponent/fermi_opponent_director.gd")
# 关卡资料统一由目录提供，运行验证可注入独立临时目录。
@export var level_catalog: LevelCatalog = preload("res://data/level_configuration/level_catalog.tres")
@export var battle_config: SandboxBattleConfig = preload("res://data/sandbox/playable_battle_config.tres")
# 当前场次的气泡对白配置；测试与后续关卡绑定可以注入独立 Resource。
@export var bubble_dialogue_config: BubbleDialogueConfig = preload("res://data/streamer_bubble_dialogue/bubble_dialogue_config.tres")
# 只从正式败者卡目录发卡；目录缺少资料时由 16 的写入接口拒绝。
@export var loser_card_catalog: LoserCardCatalog = preload("res://data/loser_card/loser_card_catalog.tres")
# 未批准的演出参数默认留空，仅由明确 TEST_ONLY 夹具或后续正式配置注入。
@export var divine_decay_config: DivineDescentDecayConfig = preload("res://data/divine_descent/divine_descent_decay_config.tres")
@export var divine_repeat_interval_seconds: float = 0.0
@export var divine_fade_seconds: float = 0.0
@export var divine_hold_seconds: float = 0.0
@export var divine_input_scale: float = 0.0
@export var divine_input_return_seconds: float = 0.0
@export var divine_trait_colors: Dictionary = {}
## 正式 SceneRouter 路径启用 Plan B；独立 Sandbox 调试场景保留旧普通战斗夹具。
@export var use_plan_b_campaign: bool = false
## 对手胜负热度映射尚待负责人批准，仅供明确启用的独立试玩预览。
@export var opponent_reaction_preview_enabled: bool = false

@onready var _barrage_area: BarrageArea = %BarrageArea
@onready var _aim_reticle: AimReticle = %AimReticle
@onready var _attack_charge_input: AttackChargeInput = %AttackChargeInput
@onready var _oracle_candidate_display: FinalOracleCandidateDisplay = %OracleCandidateDisplay
@onready var _legacy_battle_hud: Control = %BattleHud
@onready var _debug_panel: CanvasLayer = %DebugPanel

var _run_state: LevelRunState
var _battle_attempt_flow: BattleAttemptFlow
var _battle_hud
var _plan_b_host: PlanBBattleHost
var _plan_b_simulation: Node2D
var _plan_b_content_catalog: Object
var _plan_b_opponent_director: Object
var _pb14_performance_tracker: Node
var _plan_b_level_ready: bool = false
var _plan_b_slot_state_sync_elapsed: float = 0.0
var _rest_session: RestSession
var _rest_result_view: RestResultView
var _contradiction_oracle_flow: ContradictionOracleFlow
var _divine_descent_flow: DivineDescentFlow
var _hit_echo_presenter: Node
var _battle_audio: Node
var _barrage_impact_presenter: BarrageImpactPresenter
var _pa09_feedback: Control
var _combat_state_dialogue_presenter: Node
var _timed_opponent_dialogue_presenter: Node
var _specific_sentence_reply_presenter: Node
# 仅跟踪 PA-11 连线演出后的对白呈现，战斗状态仍由 Flow 拥有。
var _pa11_connection_dialogue_active: bool = false
var _paradox_comic: ParadoxComicTransition
var _paradox_entry_level: LevelProfile
var _paradox_entry_hit: HitResolution
var _paradox_entry_repeat_stats: RepeatGenerationStats
var _pending_oracle_session: FinalOracleSession
var _pending_rest_session: RestSession
var _result_feedback_active: bool = false
var _formal_sheet_consumer
var _active_dialogue_config: BubbleDialogueConfig
var _trait_catalog: BarrageTraitCatalog
var _trait_runtime: BarrageTraitRuntime
var _tutorial_runner: TutorialStepRunner
var _tutorial_hint: Control
var _result_feedback_system: ContradictionBreakSystem
var _opponent_live: LiveSessionData
var _mobile_touch: Control


# 场景只创建生命周期对象并接线；PK、Tier、倾向等状态留在各自所有者。
func _ready() -> void:
	if use_plan_b_campaign:
		if not _initialize_plan_b_battle_ui():
			push_error("Sandbox: 无法实例化 PB-09 正式界面。")
			return
	else:
		_battle_hud = _legacy_battle_hud
	_formal_sheet_consumer = FORMAL_SHEET_CONSUMER_SCRIPT.new()
	_formal_sheet_consumer.register_audio_events(AudioManager)
	_active_dialogue_config = BubbleDialogueConfig.new()
	_active_dialogue_config.entries = bubble_dialogue_config.entries.duplicate(true) if bubble_dialogue_config != null else []
	# 直接运行场景时等待 Autoload 完成初始化，再创建周目并显式绑定已就绪的子 HUD。
	if SaveManager.data == null:
		SaveManager.new_game()
	if use_plan_b_campaign:
		_battle_hud.bind_player_live_session(SaveManager.data.live_session, [])
	else:
		%LiveDataHud.bind_live_session(SaveManager.data.live_session)
	_run_state = LevelRunState.new(level_catalog)
	# 房间开播使用已保存的下一关，场景重建保留周目进度。
	if not _run_state.restore_progress(
			SaveManager.data.next_normal_level_order,
			SaveManager.data.completed_normal_level_ids):
		push_error("Campaign: invalid saved level order %d" % SaveManager.data.next_normal_level_order)
		return
	if use_plan_b_campaign and not _create_plan_b_runtime():
		push_error("Sandbox: 无法组合正式 Plan B 战斗模块。")
		return
	_contradiction_oracle_flow = ContradictionOracleFlow.new()
	add_child(_contradiction_oracle_flow)
	if not _configure_oracle_parameters():
		push_error("Sandbox: 正式神谕参数不可用。")
		return
	_contradiction_oracle_flow.state_text_changed.connect(_battle_hud.show_battle_state)
	_contradiction_oracle_flow.entered.connect(_on_contradiction_stage_entered)
	_contradiction_oracle_flow.outcome_resolved.connect(_on_contradiction_outcome_resolved)
	_contradiction_oracle_flow.oracle_opened.connect(_on_final_oracle_opened)
	_contradiction_oracle_flow.rest_ready.connect(_on_rest_ready)
	var opponent_pk_bar := OpponentPKBar.new()
	opponent_pk_bar.name = "OpponentPKBar"
	add_child(opponent_pk_bar)
	_barrage_area.barrage_generated.connect(_on_barrage_generated)
	_attack_charge_input.configure_target_query(_aim_reticle, _barrage_area)
	_attack_charge_input.shot_snapshot_created.connect(_on_plan_b_paradox_shot_created)
	if use_plan_b_campaign:
		_battle_audio = BATTLE_AUDIO_SCRIPT.new()
		_battle_audio.name = "BattleAudioPresenter"
		add_child(_battle_audio)
		_battle_audio.call("bind_sources", _attack_charge_input, _barrage_area)
		_battle_audio.call("bind_flows", _contradiction_oracle_flow)
	# PA-06 与 PA-09 只订阅战斗事实，材质播放与数值浮字均不写回结算。
	_barrage_impact_presenter = BARRAGE_IMPACT_SCRIPT.new() as BarrageImpactPresenter
	_barrage_impact_presenter.name = "BarrageImpactPresenter"
	_barrage_area.add_child(_barrage_impact_presenter)
	_barrage_impact_presenter.size = _barrage_area.size
	_barrage_impact_presenter.bind_attack(_attack_charge_input)
	_pa09_feedback = PA09_FEEDBACK_SCRIPT.new() as Control
	_pa09_feedback.name = "ShotFeedback"
	_battle_hud.add_child(_pa09_feedback)
	_pa09_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pa09_feedback.z_index = 20
	_pa09_feedback.call("bind_attack", _attack_charge_input)
	# 战斗 HUD 只订阅正式释放快照播放立绘动作，不自行判断命中结果。
	_battle_hud.bind_portrait_attack(_attack_charge_input)
	_rest_result_view = REST_RESULT_VIEW_SCENE.instantiate() as RestResultView
	add_child(_rest_result_view)
	# 创建时注入一次准心，休息及历史页面统一冻结输入，隐藏时恢复。
	_rest_result_view.configure_battle_aim(_aim_reticle)
	_rest_result_view.continue_requested.connect(_on_rest_continue_requested)
	_battle_attempt_flow = BattleAttemptFlow.new()
	_battle_attempt_flow.name = "BattleAttemptFlow"
	add_child(_battle_attempt_flow)
	_battle_attempt_flow.attempt_started.connect(_on_attempt_started)
	_battle_attempt_flow.attempt_preparing.connect(_prepare_opponent_live)
	_battle_attempt_flow.shot_resolved.connect(_on_opponent_shot_result)
	_battle_attempt_flow.battle_state_changed.connect(_battle_hud.show_battle_state)
	_battle_attempt_flow.pk_feedback_changed.connect(_battle_hud.refresh_pk)
	_battle_attempt_flow.tier_changed.connect(_queue_pk_tier_visual)
	_battle_attempt_flow.attempt_failed.connect(_on_attempt_failed)
	_battle_attempt_flow.normal_combat_completed.connect(_on_normal_combat_completed)
	# 生成目录在第一批出现前注入；反击抽选继续由 Area 的真实 Tier 批次负责。
	_trait_catalog = BarrageTraitCatalog.new()
	_trait_runtime = BarrageTraitRuntime.new()
	if not _trait_catalog.load_production_tables() or not _trait_runtime.bind(_barrage_area, _trait_catalog):
		push_error("Sandbox: 无法接入正式特性目录。")
		return
	if use_plan_b_campaign:
		_battle_audio.call("bind_trait_runtime", _trait_runtime)
	elif _battle_hud.has_method("bind_trait_audio"):
		_battle_hud.call("bind_trait_audio", _trait_runtime)
	_battle_attempt_flow.shot_resolved.connect(_trait_runtime.on_shot_resolved)
	_tutorial_runner = TutorialStepRunner.new()
	_tutorial_runner.step_completed.connect(_on_tutorial_step_completed)
	_battle_attempt_flow.shot_resolved.connect(_tutorial_runner.on_shot_resolved)
	if use_plan_b_campaign:
		_tutorial_hint = TUTORIAL_HINT_SCENE.instantiate() as Control
		_tutorial_hint.name = "TutorialHintView"
		var paradox_overlay: Control = _battle_hud.call("get_paradox_overlay_layer")
		paradox_overlay.add_child(_tutorial_hint)
		_tutorial_hint.position = Vector2(30.0, 90.0)
		_tutorial_hint.size = Vector2(paradox_overlay.size.x - 60.0, 90.0)
		_tutorial_hint.call("bind_runner", _tutorial_runner)
	else:
		_battle_hud.bind_tutorial_runner(_tutorial_runner)
	_battle_hud.opponent_result_presentation_finished.connect(_on_opponent_result_finished)
	_battle_hud.failure_presentation_finished.connect(_on_failure_presentation_finished)
	if use_plan_b_campaign:
		%RestartButton.pressed.connect(Callable(_battle_hud, "request_restart"))
		_battle_hud.connect("restart_requested", Callable(self, "restart_current_attempt"))
	else:
		%RestartButton.pressed.connect(restart_current_attempt)
	%PauseMenu.restart_requested.connect(restart_current_attempt)
	%PauseMenu.paused_changed.connect(_on_pause_changed)
	if use_plan_b_campaign:
		_debug_panel.hide()
	else:
		_debug_panel.call("bind_sandbox", self)
	if not _battle_attempt_flow.configure(
			SaveManager.data, level_catalog, _run_state, battle_config, SAMPLE_TIER_CATALOG,
			_barrage_area, _aim_reticle, _attack_charge_input, opponent_pk_bar,
			_contradiction_oracle_flow, _oracle_candidate_display, loser_card_catalog,
			CONTRADICTION_WINDOW_CONFIG, AudioManager):
		push_error("Sandbox: 无法组合 BattleAttemptFlow。")
		return
	if use_plan_b_campaign:
		if not _battle_attempt_flow.set_external_pk_source(
				Callable(_plan_b_host, "get_pk_fraction")):
			push_error("Sandbox: 无法把 Plan B Host 绑定为唯一普通 PK 源。")
			return
		if not _plan_b_host.set_tier_source(
				Callable(_battle_attempt_flow, "get_current_tier")):
			push_error("Sandbox: 无法把正式 CombatStage 绑定为 Tier 来源。")
			return
		_battle_audio.call("bind_flows", _contradiction_oracle_flow)
	else:
		_battle_hud.bind_audio_flows(_contradiction_oracle_flow)
	_paradox_comic = PARADOX_COMIC_SCENE.instantiate() as ParadoxComicTransition
	_paradox_comic.name = "ParadoxComicTransition"
	_paradox_comic.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_paradox_comic)
	_paradox_comic.transition_finished.connect(_on_paradox_transition_finished)
	_paradox_comic.result_feedback_finished.connect(_on_paradox_result_feedback_finished)
	_battle_attempt_flow.tier_transition_cleared.connect(_on_tier_transition_cleared)
	_battle_hud.tier_breakthrough_finished.connect(_on_tier_breakthrough_finished)
	# 由新消费者读取正式逐目标结算，再通过 HUD 公开队列入口提交玩家复述。
	_hit_echo_presenter = HIT_ECHO_PRESENTER_SCRIPT.new()
	_hit_echo_presenter.name = "StreamerBubbleHitEchoPresenter"
	add_child(_hit_echo_presenter)
	if not bool(_hit_echo_presenter.call(
			"configure",
			_battle_attempt_flow,
			_active_dialogue_config,
			Callable(_battle_hud, "enqueue_dialogue_bubble"))):
		push_error("Sandbox: 无法接入实际命中气泡消费者。")
		return
	# 特定原句回复独立消费同一最终命中事实，剧情优先级由 SD-03 队列调度。
	_specific_sentence_reply_presenter = SPECIFIC_SENTENCE_REPLY_PRESENTER_SCRIPT.new()
	_specific_sentence_reply_presenter.name = "StreamerBubbleSpecificSentenceReplyPresenter"
	add_child(_specific_sentence_reply_presenter)
	if not bool(_specific_sentence_reply_presenter.call(
			"configure",
			_battle_attempt_flow,
			_active_dialogue_config,
			Callable(_battle_hud, "enqueue_dialogue_bubble"))):
		push_error("Sandbox: 无法接入特定原句对手回复消费者。")
		return
	# 状态对白只消费 BattleAttemptFlow / ContradictionOracleFlow 公开事实，并把整句完成通知交回沙盒。
	_combat_state_dialogue_presenter = COMBAT_STATE_DIALOGUE_PRESENTER_SCRIPT.new()
	_combat_state_dialogue_presenter.name = "StreamerBubbleCombatStatePresenter"
	add_child(_combat_state_dialogue_presenter)
	if not bool(_combat_state_dialogue_presenter.call(
			"configure",
			_battle_attempt_flow,
			_contradiction_oracle_flow,
			_active_dialogue_config,
			Callable(_battle_hud, "enqueue_dialogue_sequence"),
			_battle_hud)):
		push_error("Sandbox: 无法接入战斗状态对白消费者。")
		return
	_combat_state_dialogue_presenter.connect(
		"event_sequence_completed", Callable(self, "_on_dialogue_event_sequence_completed")
	)
	# 定时闲聊由可暂停的独立消费者计时，并提交 HUD 已有的低优先级入口。
	_timed_opponent_dialogue_presenter = TIMED_OPPONENT_DIALOGUE_PRESENTER_SCRIPT.new()
	_timed_opponent_dialogue_presenter.name = "StreamerBubbleTimedOpponentDialoguePresenter"
	add_child(_timed_opponent_dialogue_presenter)
	if not bool(_timed_opponent_dialogue_presenter.call(
			"configure",
			_battle_attempt_flow,
			_active_dialogue_config,
			Callable(_battle_hud, "enqueue_dialogue_bubble"))):
		push_error("Sandbox: 无法接入战斗定时对手对白消费者。")
		return
	_setup_pb14_performance_tracker()
	if not _battle_attempt_flow.start_first_attempt():
		push_error("Sandbox: 无法启动首场普通战斗。")


## 默认不创建 Tracker；只有 PB14_PERF_TRACKER=1 时才向 B/D 注入观测器。
func _setup_pb14_performance_tracker() -> void:
	if not use_plan_b_campaign or OS.get_environment("PB14_PERF_TRACKER") != "1":
		return
	if _plan_b_host == null or _plan_b_simulation == null or _battle_hud == null or _battle_attempt_flow == null:
		push_error("PB14 tracker: runtime sources are unavailable")
		return
	var tracker := PB14_PERFORMANCE_TRACKER_SCRIPT.new() as Node
	if tracker == null:
		push_error("PB14 tracker: unable to create tracker node")
		return
	var duration_seconds: float = 0.0
	var duration_text: String = OS.get_environment("PB14_PERF_TRACKER_SECONDS")
	if duration_text.is_valid_float():
		duration_seconds = duration_text.to_float()
	var output_path: String = OS.get_environment("PB14_PERF_TRACKER_PATH")
	if not bool(tracker.call("configure", output_path, duration_seconds)):
		tracker.free()
		push_error("PB14 tracker: invalid runtime configuration")
		return
	tracker.call("set_runtime_sources", _plan_b_host, _plan_b_simulation, _battle_hud, _battle_attempt_flow)
	add_child(tracker)
	if not bool(tracker.call("is_enabled")):
		tracker.queue_free()
		return
	_pb14_performance_tracker = tracker
	_plan_b_simulation.call("set_performance_tracker", tracker)
	_battle_hud.call("set_performance_tracker", tracker)


## 正式三列 UI 由 D 提供；旧六句矛盾与准心组件复用 D 明确开放的 Paradox 容器。
func _initialize_plan_b_battle_ui() -> bool:
	var battle_ui: Control = PLAN_B_BATTLE_UI_SCENE.instantiate() as Control
	if battle_ui == null:
		return false
	var legacy_ui_index: int = _legacy_battle_hud.get_index()
	_legacy_battle_hud.name = "LegacyBattleHud"
	battle_ui.name = "BattleHud"
	battle_ui.unique_name_in_owner = true
	battle_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(battle_ui)
	# 保持 FailureOverlay、PauseMenu 和 DebugPanel 处于正式 UI 前景。
	move_child(battle_ui, legacy_ui_index)
	if not battle_ui.has_method("get_paradox_overlay_layer"):
		return false
	var paradox_layer: Variant = battle_ui.call("get_paradox_overlay_layer")
	if not paradox_layer is Control or not battle_ui.has_method("get_aim_reticle"):
		return false

	_battle_hud = battle_ui
	_aim_reticle = battle_ui.call("get_aim_reticle") as AimReticle
	if _aim_reticle == null:
		return false
	_legacy_battle_hud.visible = false
	var legacy_paradox_nodes: Array[Control] = [
		_barrage_area,
		_oracle_candidate_display,
	]
	for legacy_node: Control in legacy_paradox_nodes:
		var previous_parent: Node = legacy_node.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(legacy_node)
		paradox_layer.add_child(legacy_node)
		legacy_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paradox_layer.move_child(_barrage_area, 0)
	_barrage_area.visible = false
	_oracle_candidate_display.visible = false
	_legacy_battle_hud.queue_free()
	return true


## 组合正式 B/C 模块；B 运行态只存棋子快照，UI 由 D 读取。
func _create_plan_b_runtime() -> bool:
	var simulation := PLAN_B_SIMULATION_SCRIPT.new() as Node2D
	_plan_b_host = PLAN_B_HOST_SCRIPT.new() as PlanBBattleHost
	if simulation == null or _plan_b_host == null:
		return false
	simulation.name = "Simulation"
	# B 的 Area2D 保留碰撞与逻辑，棋子图形由 D 从只读快照绘制。
	simulation.visible = false
	_plan_b_host.name = "PlanBBattleHost"
	_plan_b_host.add_child(simulation)
	add_child(_plan_b_host)
	_plan_b_simulation = simulation
	_plan_b_content_catalog = PLAN_B_CONTENT_CATALOG_SCRIPT.new()
	_plan_b_opponent_director = PLAN_B_OPPONENT_DIRECTOR_SCRIPT.new()
	if not _plan_b_host.configure_modules(
			_plan_b_simulation, _plan_b_content_catalog, _plan_b_opponent_director):
		return false
	_plan_b_content_catalog.call("set_random_seed", 20261017)
	_plan_b_host.pk_changed.connect(_on_plan_b_pk_changed)
	_plan_b_host.publish_result.connect(_on_plan_b_publish_result)
	_plan_b_host.battle_ended.connect(_on_plan_b_battle_ended)
	_plan_b_host.counterattack_windup_started.connect(_on_plan_b_counterattack_windup_started)
	_plan_b_host.counterattack_resolved.connect(_on_plan_b_counterattack_resolved)
	if _plan_b_content_catalog.has_signal("player_hand_changed"):
		_plan_b_content_catalog.connect(
			"player_hand_changed", Callable(self, "_on_plan_b_hand_changed"))
	_plan_b_host.player_hand_changed.connect(_on_plan_b_hand_changed)
	if _plan_b_opponent_director.has_signal("opponent_word_pool_exhausted"):
		_plan_b_opponent_director.connect(
			"opponent_word_pool_exhausted", Callable(self, "_on_opponent_word_pool_exhausted"))
	_battle_hud.call("bind_sources", _plan_b_host, _plan_b_simulation, _plan_b_content_catalog)
	_battle_hud.connect("publish_requested", Callable(self, "_on_plan_b_publish_requested"))
	return true


# CombatStage 的起始 Tier 通知早于 attempt_started；延后一帧避免新场误播升降档动作。
func _queue_pk_tier_visual(current_tier: int, _player_pk: float) -> void:
	if _plan_b_host != null:
		_plan_b_host.notify_external_tier_changed(current_tier)
	# 延迟只保存来源和档位，PK在执行时读取，避免旧回调覆盖回拉或新尝试。
	_deliver_pk_tier_visual.call_deferred(_battle_attempt_flow.get_combat_stage(), current_tier)


## 回调到达时只接受当前Stage；T6/终局也不会被旧普通Tier演出覆盖。
func _deliver_pk_tier_visual(source: CombatStage, tier: int) -> void:
	if source != _battle_attempt_flow.get_combat_stage() or source.get_current_tier() != tier:
		return
	if not _battle_attempt_flow.is_normal_combat_active():
		return
	_battle_hud.refresh_pk(_battle_attempt_flow.get_hit_resolution().get_player_pk(), tier)


## C的公开入口只撤销当前指针蓄力，保留已发射言弹及硬直计时。
func _on_pause_changed(paused: bool) -> void:
	if paused and _attack_charge_input.has_method("cancel_pointer_attack"):
		_attack_charge_input.call("cancel_pointer_attack")
	_refresh_mobile_touch_phase()


# 按当前关重建尝试；重开与切到下一关共用清理，保留此前周目成果。
func restart_current_attempt() -> void:
	# 已进入终局后不能通过普通重开入口恢复 PK、档位与矛盾规则。
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		return
	_contradiction_oracle_flow.stop()
	_reset_paradox_presentation()
	_rest_session = null
	_rest_result_view.hide_result()
	if use_plan_b_campaign:
		%FailureOverlay.hide()
	_attack_charge_input.set_contradiction_mode(false)
	%PauseMenu.resume_game()
	if not _battle_attempt_flow.restart_current_attempt():
		push_error("Sandbox: 无法重建当前战斗尝试。")
	_refresh_mobile_touch_phase()


# 当前关的角色和素材由一次尝试启动事实提供；HUD 只呈现组合方状态。
func _on_attempt_started(current_level: LevelProfile, _hit: HitResolution, stage: CombatStage, _queue: RepeatDelayQueue) -> void:
	%PauseMenu.set_restart_available(true)
	_refresh_mobile_touch_phase()
	_pa11_connection_dialogue_active = false
	_barrage_impact_presenter.reset_effects()
	_pa09_feedback.call("clear_feedback")
	_battle_hud.reset_for_attempt(stage.get_current_tier())
	_battle_hud.set_paradox_stage_active(false, stage.get_current_tier())
	if use_plan_b_campaign:
		_battle_hud.set_final_oracle_stage_active(false)
		_barrage_area.visible = false
		_oracle_candidate_display.visible = false
	if _tutorial_hint != null:
		_tutorial_hint.call("clear_hint")
	# 表现表按稳定 level_id 解析，并在同一尝试入口刷新主播、立绘、对白与评论。
	var presentation: Dictionary = _formal_sheet_consumer.get_level_presentation(current_level.level_id)
	_battle_hud.configure_opponent_result(current_level, presentation)
	_trait_runtime.begin_attempt(current_level)
	if _battle_attempt_flow.uses_external_pk_source():
		_tutorial_runner.begin("", SaveManager.data.completed_tutorial_step_ids)
	else:
		_tutorial_runner.begin(
			current_level.tutorial_config_id, SaveManager.data.completed_tutorial_step_ids
		)
	var streamer_id: String = str(presentation.get("streamer_id", current_level.streamer_id))
	var opponent_name: String = str(presentation.get("streamer_name", current_level.streamer_name))
	var fan_group_name: String = str(presentation.get("fan_group_name", current_level.fan_group_name))
	var player_name: String = SaveManager.data.streamer_name
	_battle_hud.configure_streamers(player_name if not player_name.is_empty() else "玩家主播", opponent_name)
	_battle_hud.configure_fan_group_names(SaveManager.data.fan_group_name, fan_group_name)
	_battle_hud.configure_portrait_character(streamer_id)
	_battle_hud.configure_streamer_assets(
		PRESENTATION_ASSETS.player_streamer_portrait,
		PRESENTATION_ASSETS.player_live_background,
		PRESENTATION_ASSETS.player_fan_badge,
		presentation.get("portrait_idle", current_level.streamer_portrait) as Texture2D,
		presentation.get("background", current_level.streamer_live_background) as Texture2D,
		presentation.get("fan_badge", current_level.fan_badge_texture) as Texture2D
	)
	if _battle_hud.has_method("configure_opponent_foreground"):
		_battle_hud.call("configure_opponent_foreground", current_level.streamer_live_foreground)
	var portraits: Array = presentation.get("portrait_tiers", [])
	if portraits.size() == 4:
		_battle_hud.configure_opponent_tier_textures(
			portraits[0] as Texture2D, portraits[1] as Texture2D,
			portraits[2] as Texture2D, portraits[3] as Texture2D)
	var story_id: String = str(presentation.get("story_config_id", ""))
	if not story_id.is_empty():
		_active_dialogue_config.entries = _formal_sheet_consumer.create_dialogue_config(story_id).entries
	if use_plan_b_campaign:
		_battle_hud.configure_formal_comments(BubbleDialogueEntry.SpeakerSide.OPPONENT,
			_formal_sheet_consumer.get_comments("opponent", streamer_id),
			_formal_sheet_consumer.comment_parameters)
		_battle_hud.configure_formal_comments(BubbleDialogueEntry.SpeakerSide.PLAYER,
			_formal_sheet_consumer.get_comments("player", ""),
			_formal_sheet_consumer.comment_parameters)
		if not _plan_b_level_ready or not _start_plan_b_battle(current_level):
			_battle_attempt_flow.stop()
			push_error("Sandbox: 无法启动当前关卡的 Plan B 棋子战斗。")
	else:
		%OpponentLiveDataHud.configure_formal_comments(
			_formal_sheet_consumer.get_comments("opponent", streamer_id),
			_formal_sheet_consumer.comment_parameters)
		%LiveDataHud.configure_formal_comments(
			_formal_sheet_consumer.get_comments("player", ""),
			_formal_sheet_consumer.comment_parameters)


## 每次正式开播从 D 的实际 UnitField 读取场地区域，B/D 共用同一 scene-global Rect2。
func _start_plan_b_battle(level: LevelProfile) -> bool:
	if level == null or _plan_b_host == null or _battle_hud == null:
		return false
	if (
		not _battle_hud.has_method("get_board_world_bounds")
		or not _battle_hud.has_method("set_world_bounds")
		or not _battle_hud.has_method("set_word_hand")
	):
		return false
	var board_bounds: Rect2 = _battle_hud.call("get_board_world_bounds")
	if board_bounds.size.x <= 0.0 or board_bounds.size.y <= 0.0:
		return false
	_plan_b_host.available_level = level.level_id
	_battle_hud.call("set_world_bounds", board_bounds)
	_plan_b_host.start_battle(board_bounds.size, board_bounds.position)
	if _plan_b_host.get_battle_state() != &"running":
		return false
	var current_hand: Array[Dictionary] = _plan_b_host.get_player_hand()
	_refresh_plan_b_hand(current_hand)
	return true


## 手牌状态由 C 保有；A 只提供 Host 的权威已用词数量给 D。
func _refresh_plan_b_hand(hand: Array[Dictionary]) -> void:
	if _battle_hud == null or _plan_b_host == null or not _battle_hud.has_method("set_word_hand"):
		return
	var available_ids: Array[String] = _plan_b_host.get_available_word_ids("player")
	var occupied_slot_count: int = 0
	for card: Dictionary in hand:
		if not str(card.get("word_id", "")).is_empty():
			occupied_slot_count += 1
	var draw_pool_remaining: int = maxi(0, available_ids.size() - occupied_slot_count)
	_battle_hud.call("set_word_hand", hand, draw_pool_remaining)
	if _battle_hud.has_method("set_player_slot_states"):
		_battle_hud.call("set_player_slot_states", _plan_b_host.get_player_slot_states())


func _on_plan_b_pk_changed(_pk_percent: float) -> void:
	# BattleAttemptFlow 通过 HitResolution 的只读 getter 转发 Host PK，驱动旧 Tier/HUD/终结流程。
	if _battle_attempt_flow != null:
		_battle_attempt_flow.notify_external_pk_changed()


func _on_plan_b_battle_ended(result: StringName) -> void:
	if result != &"enter_contradiction":
		return
	# 矛盾神谕与神降临按真实玩家复读棋子数排序；统计在旧普通胜利提交前冻结。
	if not _battle_attempt_flow.record_plan_b_population_repeats(
			_plan_b_host.get_unit_snapshots(), _plan_b_content_catalog):
		push_error("Sandbox: 无法提交 Plan B 玩家复读统计。")


func _on_plan_b_publish_result(team: String, word_id: String, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	var definition: Dictionary = _plan_b_host.get_word_definition(word_id)
	if team == "player":
		if not _battle_attempt_flow.record_plan_b_player_publication(definition):
			push_error("Sandbox: Plan B 玩家发表缺少旧结算所需话语字段：%s" % word_id)
		_hit_echo_presenter.call("on_plan_b_player_publication", definition)
		_specific_sentence_reply_presenter.call("on_plan_b_player_publication", definition)
		SaveManager.data.live_session.record_generated_comments(1)
	elif team == "opponent" and _opponent_live != null:
		_opponent_live.record_normal_hit_live_rule()
		_opponent_live.record_generated_comments(1)


func _on_plan_b_publish_requested(slot_id: int, word_id: String, spawn_position: Vector2) -> void:
	# 玩家以中央棋盘场景坐标提交整批发表；失败回执由 D 保留原句与选中状态。
	var result: Dictionary = _plan_b_host.publish_word("player", word_id, spawn_position, slot_id)
	_battle_hud.call("resolve_publish_request", slot_id, word_id, spawn_position, result)


func _on_plan_b_hand_changed(hand: Array) -> void:
	var typed_hand: Array[Dictionary] = []
	for card: Variant in hand:
		if card is Dictionary:
			typed_hand.append((card as Dictionary).duplicate(true))
	_refresh_plan_b_hand(typed_hand)


func _on_plan_b_counterattack_windup_started(request: Dictionary) -> void:
	if _battle_hud != null and _battle_hud.has_method("show_counterattack_windup"):
		_battle_hud.call("show_counterattack_windup", request.duplicate(true))


func _on_plan_b_counterattack_resolved(result: Dictionary) -> void:
	if bool(result.get("applied", false)) and str(result.get("effect_id", "")) == "split":
		AudioManager.play_event(&"trait_split")
	if _battle_hud != null and _battle_hud.has_method("show_counterattack_result"):
		_battle_hud.call("show_counterattack_result", result.duplicate(true))


func _on_opponent_word_pool_exhausted(_level_id: String, streamer_id: String) -> void:
	if _battle_hud != null:
		_battle_hud.call("show_battle_state", "%s 已用完本关发言" % streamer_id)


# 正式失败先播放 PA-18 局部演出，完成通知后再显示既有失败界面。
func _on_attempt_failed(_level: LevelProfile, _loss_streak_count: int, _hit: HitResolution, _repeat_stats: RepeatGenerationStats) -> void:
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("set_enabled", false)
	if opponent_reaction_preview_enabled and _opponent_live != null:
		_opponent_live.commit_pk_win_fans(StringName(_level.level_id), BattleAttemptFlow.FORMAL_COMBAT_NUMERICS.pk_win_fan_gain)
	_reset_paradox_presentation()
	_pa11_connection_dialogue_active = false
	_barrage_impact_presenter.reset_effects()
	_pa09_feedback.call("clear_feedback")
	_battle_hud.set_paradox_stage_active(false, _battle_attempt_flow.get_current_tier())
	_battle_hud.play_failure_presentation()


# T1 连线对白完整结束后恢复本档战斗，再向外转发已完成事实。
func _on_dialogue_event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int) -> void:
	if event_id == &"combat_connected":
		_pa11_connection_dialogue_active = false
		if _battle_attempt_flow.resume_after_tier1_dialogue():
			_resume_plan_b_after_tier_transition()
		_refresh_mobile_touch_phase()
	dialogue_event_sequence_completed.emit(event_id, sequence_id, side)


# 升档清屏完成后暂停普通战斗，再播放 HUD 现有 Tier 标签的一次突破提示。
func _on_tier_transition_cleared(previous_tier: int, current_tier: int, _cleared_count: int) -> void:
	if not _battle_attempt_flow.begin_tier_breakthrough_transition(previous_tier, current_tier):
		return
	if _plan_b_host != null:
		_plan_b_host.pause_battle()
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("set_enabled", false)
	if previous_tier == CombatStage.INITIAL_TIER and current_tier > CombatStage.INITIAL_TIER:
		# T1 立绘先由 PK 反馈显示；转场期间收起，动画结束后再接入对白。
		_battle_hud.set_opponent_portrait_connected(false)
	if not _battle_hud.play_tier_breakthrough(previous_tier, current_tier):
		_on_tier_breakthrough_finished(previous_tier, current_tier, true)


# 转场结束后先恢复 T1 立绘，再让公开 Tier 完成事件触发对白 / 战斗恢复。
func _on_tier_breakthrough_finished(
		previous_tier: int, current_tier: int, completed: bool
) -> void:
	if not completed or _battle_attempt_flow.get_current_tier() != current_tier:
		return
	if previous_tier == CombatStage.INITIAL_TIER and current_tier > CombatStage.INITIAL_TIER:
		_battle_hud.set_opponent_portrait_connected(true)
	# 空配置可能同步完播，所以必须在完成入口发出通知前设置此标记。
	_pa11_connection_dialogue_active = previous_tier == 0 and current_tier == 1
	if not _battle_attempt_flow.finish_tier_breakthrough_transition():
		push_error("Sandbox: 升档突破过渡结束后无法恢复当前流程。")
	elif not _pa11_connection_dialogue_active:
		_resume_plan_b_after_tier_transition()
	_refresh_mobile_touch_phase()


func _resume_plan_b_after_tier_transition() -> void:
	if (_battle_attempt_flow.is_normal_combat_active() and _plan_b_host != null
			and _plan_b_host.get_battle_state() == &"paused"):
		_plan_b_host.resume_battle()


# 真实矛盾流程发出进入事实后，HUD 才展示 T6 / Paradox。
func _on_contradiction_stage_entered(_system: ContradictionBreakSystem) -> void:
	_battle_hud.set_paradox_stage_active(true, _battle_attempt_flow.get_current_tier())
	if _battle_attempt_flow.uses_external_pk_source():
		_battle_hud.set_final_oracle_stage_active(false)
		_barrage_area.visible = true
		var current_level: LevelProfile = _battle_attempt_flow.get_current_level_profile()
		if current_level != null:
			# 旧准心教程只在恢复射击的矛盾阶段出现。
			_tutorial_runner.begin(
				current_level.tutorial_config_id, SaveManager.data.completed_tutorial_step_ids
			)
	_refresh_mobile_touch_phase()


func _on_plan_b_paradox_shot_created(snapshot: AttackTargetSnapshot) -> void:
	if (not _battle_attempt_flow.uses_external_pk_source()
			or not _contradiction_oracle_flow.is_contradiction_active()
			or snapshot == null):
		return
	if not snapshot.get_contradiction_facts().is_empty():
		_tutorial_runner.notify_event("tutorial_normal_hit")


# 神谕接管阶段展示时恢复当前 CombatStage 档位，再转发既有对外事件。
func _on_final_oracle_opened(session: FinalOracleSession) -> void:
	if _result_feedback_active:
		_pending_oracle_session = session
		return
	if use_plan_b_campaign:
		_barrage_area.visible = false
	_battle_hud.set_paradox_stage_active(false, _battle_attempt_flow.get_current_tier())
	if use_plan_b_campaign:
		_battle_hud.set_final_oracle_stage_active(true)
	final_oracle_opened.emit(session)
	_refresh_mobile_touch_phase()


# 满值结算后先完成 PA-12 转场；矛盾流程此时仍未创建窗口或开放输入。
func _on_normal_combat_completed(
		level: LevelProfile, hit_resolution: HitResolution, repeat_stats: RepeatGenerationStats
) -> void:
	_reset_paradox_presentation()
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("set_enabled", false)
	_paradox_entry_level = level
	_paradox_entry_hit = hit_resolution
	_paradox_entry_repeat_stats = repeat_stats
	_paradox_comic.play_transition()


# 只消费当前尚未启动的一次满值结算，旧尝试发来的完成不能进入新阶段。
func _on_paradox_transition_finished() -> void:
	if _paradox_entry_hit == null or not is_inside_tree():
		return
	var level: LevelProfile = _paradox_entry_level
	var hit_resolution: HitResolution = _paradox_entry_hit
	var repeat_stats: RepeatGenerationStats = _paradox_entry_repeat_stats
	_paradox_entry_level = null
	_paradox_entry_hit = null
	_paradox_entry_repeat_stats = null
	_battle_attempt_flow.begin_contradiction_after_transition(level, hit_resolution, repeat_stats)


# 锁定结果只启动一次对应漫画，并暂存同步到达的神谕或 Rest 展示。
func _on_contradiction_outcome_resolved(outcome: int) -> void:
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("set_enabled", false)
	if _result_feedback_active:
		return
	_result_feedback_active = true
	_result_feedback_system = _contradiction_oracle_flow.get_contradiction_system()
	_contradiction_oracle_flow.hold_result_presentation()
	var broken := outcome == ContradictionBreakSystem.Outcome.BREAKTHROUGH
	if not _battle_hud.play_opponent_result(broken):
		_on_opponent_result_finished(broken)


## 同一场 PA-17 完成后才播放 PA-12；重开后的旧结果不能推进新流程。
func _on_opponent_result_finished(broken: bool) -> void:
	if not _result_feedback_active or _result_feedback_system == null or _result_feedback_system != _contradiction_oracle_flow.get_contradiction_system():
		return
	_paradox_comic.play_result_feedback(broken)


# PA-12 结果漫画结束后才允许显示已有 Owner 提交的后续页面。
func _on_paradox_result_feedback_finished(_success: bool) -> void:
	if not _result_feedback_active or _result_feedback_system != _contradiction_oracle_flow.get_contradiction_system():
		return
	_result_feedback_active = false
	_contradiction_oracle_flow.complete_result_presentation(_result_feedback_system)
	_result_feedback_system = null
	if _pending_oracle_session != null:
		var oracle_session := _pending_oracle_session
		_pending_oracle_session = null
		_on_final_oracle_opened(oracle_session)
	if _pending_rest_session != null:
		var rest_session := _pending_rest_session
		_pending_rest_session = null
		_show_rest_result(rest_session)


# 中断时清除上一尝试的动画和待展示结果，避免过期回调污染新流程。
func _reset_paradox_presentation() -> void:
	_paradox_entry_level = null
	_paradox_entry_hit = null
	_paradox_entry_repeat_stats = null
	_pending_oracle_session = null
	_pending_rest_session = null
	_result_feedback_active = false
	_result_feedback_system = null
	if use_plan_b_campaign and _battle_hud != null:
		var current_tier: int = (
			_battle_attempt_flow.get_current_tier()
			if _battle_attempt_flow != null
			else CombatStage.INITIAL_TIER
		)
		_battle_hud.set_paradox_stage_active(false, current_tier)
		_battle_hud.set_final_oracle_stage_active(false)
		_barrage_area.visible = false
		_oracle_candidate_display.visible = false
	if is_instance_valid(_paradox_comic):
		_paradox_comic.reset_for_attempt()


# 暂停由 SceneTree 冻结此节点，复读等待只使用实际游戏帧时间。
func _process(delta: float) -> void:
	if _battle_attempt_flow == null or _contradiction_oracle_flow == null:
		return
	# PA-11：战斗提前结束时取消旧演出，防止它向已停止流程发出完成通知。
	if not _battle_attempt_flow.is_normal_combat_active() and _battle_hud.is_stage_transition_playing():
		_battle_hud.cancel_tier_breakthrough()
	if not _battle_attempt_flow.is_normal_combat_active() and _pa11_connection_dialogue_active:
		_pa11_connection_dialogue_active = false
		_battle_hud.clear_dialogue_bubbles(BubbleDialogueEntry.SpeakerSide.OPPONENT)
	if _divine_descent_flow != null:
		_divine_descent_flow.advance(delta)
	# 直播上涨只推进表现数据；SceneTree 暂停时此帧回调也暂停。
	SaveManager.data.live_session.advance_short_boosts(delta)
	_battle_attempt_flow.advance(delta)
	_contradiction_oracle_flow.advance(delta)
	if _tutorial_runner != null:
		if _battle_attempt_flow.uses_external_pk_source():
			if _contradiction_oracle_flow.is_contradiction_active():
				_tutorial_runner.observe_combat_frame(
					_barrage_area, _aim_reticle, _attack_charge_input, true
				)
		elif _battle_attempt_flow.is_normal_combat_active():
			_tutorial_runner.observe_combat_frame(_barrage_area, _aim_reticle, _attack_charge_input)
	_battle_hud.refresh_attack(_attack_charge_input.get_charge_progress(), _attack_charge_input.get_attack_phase())
	if use_plan_b_campaign and _plan_b_host != null and _battle_hud.has_method("set_player_slot_states"):
		_plan_b_slot_state_sync_elapsed += delta
		if _plan_b_slot_state_sync_elapsed >= 0.1:
			_plan_b_slot_state_sync_elapsed = 0.0
			_battle_hud.call("set_player_slot_states", _plan_b_host.get_player_slot_states())


# DEBUG 面板每次刷新时从现有系统即时收集快照，不把可变业务值保存在 UI。
func get_debug_snapshot() -> Dictionary:
	if SaveManager.data == null or _run_state == null or _battle_attempt_flow == null:
		return {}
	var hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	var combat_stage: CombatStage = _battle_attempt_flow.get_combat_stage()
	if hit_resolution == null or combat_stage == null:
		return {}
	var current_level: LevelProfile = _battle_attempt_flow.get_current_level_profile()
	var live_session: LiveSessionData = SaveManager.data.live_session
	var tendency_state: TendencyState = SaveManager.data.tendency_state
	var barrage_counts: Dictionary = _barrage_area.get_current_barrage_counts()
	var battle_phase: String = "普通战斗中（NORMAL_COMBAT）" if _battle_attempt_flow.is_normal_combat_active() else "普通战斗未运行（INACTIVE）"
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		battle_phase = "神降临（DIVINE_DESCENT）"
	elif _contradiction_oracle_flow.is_contradiction_active():
		battle_phase = "矛盾击破（CONTRADICTION_BREAK）"
	elif _contradiction_oracle_flow.get_oracle_session() != null and _rest_session == null:
		battle_phase = "终结神谕（FINAL_ORACLE）"
	elif _rest_session != null and _rest_session.is_open():
		battle_phase = "休息时刻（REST）"
	elif hit_resolution.get_player_pk() >= battle_config.maximum_player_pk:
		battle_phase = "普通战斗完成（NORMAL_COMBAT_COMPLETE）"
	if get_tree().paused:
		battle_phase += " · 暂停中"
	return {
		"level": "第%d关" % current_level.level_order if current_level != null else "无关卡",
		"player_streamer": SaveManager.data.streamer_name if not SaveManager.data.streamer_name.is_empty() else "玩家主播",
		"opponent_streamer": current_level.streamer_name if current_level != null else "无对手",
		"battle_phase": battle_phase,
		"player_pk": hit_resolution.get_player_pk(),
		"tier": combat_stage.get_current_tier(),
		"attack_phase": _attack_charge_input.get_attack_phase(),
		"is_charging": _attack_charge_input.is_charge_held(),
		"normal_barrage_count": int(barrage_counts.get("normal", 0)),
		"repeat_barrage_count": int(barrage_counts.get("repeat", 0)),
		"normal_generation_enabled": _barrage_area.is_normal_generation_enabled(),
		"viewer_count": live_session.viewer_count,
		"like_count": live_session.like_count,
		"comment_count": live_session.comment_count,
		"fan_count": live_session.fan_count,
		"attempt_orthodox": tendency_state.attempt_orthodox_total,
		"attempt_heretical": tendency_state.attempt_heretical_total,
		"attempt_absurd": tendency_state.attempt_absurd_total,
	}


# F3 调试入口经 HitResolution 正式更新 PK，让 CombatStage 和 HUD 收到同一变化信号。
func debug_set_player_pk(player_pk: float) -> float:
	var hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	if hit_resolution == null:
		return 0.0
	return hit_resolution.set_player_pk_for_debug(player_pk)


# 直播调试值仍写入本场 LiveSessionData，由 Resource.changed 刷新当前 HUD。
func debug_set_live_data(viewer: int, likes: int, comments: int, fans: int) -> void:
	if SaveManager.data == null or SaveManager.data.live_session == null:
		return
	var live_session: LiveSessionData = SaveManager.data.live_session
	live_session.viewer_count = maxi(viewer, 0)
	live_session.like_count = maxi(likes, 0)
	live_session.comment_count = maxi(comments, 0)
	live_session.fan_count = maxi(fans, 0)


# 调试倾向只写当前关暂存值，不碰已提交的周目累计。
func debug_set_attempt_tendencies(orthodox: int, heretical: int, absurd: int) -> void:
	if SaveManager.data == null or SaveManager.data.tendency_state == null:
		return
	SaveManager.data.tendency_state.set_attempt_tendencies_for_debug(orthodox, heretical, absurd)


# 清空当前画面弹幕并取消尚未出现的复读请求，但保留普通生成开关状态。
func debug_clear_barrages() -> void:
	_barrage_area.clear_current_barrages()
	_battle_attempt_flow.clear_pending_normal_repeats()


# 使用当前关卡和 Tier 参数立即生成一批普通弹幕。
func debug_spawn_normal_batch() -> int:
	return _barrage_area.spawn_normal_batch_now()


# DEBUG 操作只切换 BarrageArea 的真实普通生成状态。
func debug_set_normal_generation_enabled(enabled: bool) -> bool:
	if enabled:
		return _barrage_area.resume_normal_generation()
	_barrage_area.stop_normal_generation()
	return true


# 流程已经提交成果并准备好 Rest；根场景只展示同一结果对象。
func _on_rest_ready(result: RestSession) -> void:
	if _result_feedback_active:
		_pending_rest_session = result
		return
	_show_rest_result(result)


func _show_rest_result(result: RestSession) -> void:
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("set_enabled", false)
	if use_plan_b_campaign:
		_barrage_area.visible = false
		_oracle_candidate_display.visible = false
	%PauseMenu.set_restart_available(false)
	_rest_session = result
	_battle_hud.set_paradox_stage_active(false, _battle_attempt_flow.get_current_tier())
	if use_plan_b_campaign:
		_battle_hud.set_final_oracle_stage_active(false)
	if not _rest_result_view.show_result(result, SaveManager.data, level_catalog, loser_card_catalog):
		push_error("Sandbox: 无法显示本场 Rest 结果。")
		return
	rest_opened.emit(result)


# 继续请求使用本场结果 ID 推进；仅下一普通关路线重建当前场景的尝试。
func _on_rest_continue_requested() -> void:
	if _rest_session == null or not _rest_session.is_open():
		return
	var finished_session: RestSession = _rest_session
	var completion: LevelRunState.CompletionResult = finished_session.continue_to_next_level(_run_state)
	if completion == LevelRunState.CompletionResult.ADVANCED:
		# 结算后先保存下一关并回房间，由玩家主动再次开播。
		var finished_level_id := str(finished_session.get_result_snapshot().get("level_id", ""))
		SaveManager.data.scripture_data.rollback_uncommitted(StringName(finished_level_id))
		_battle_attempt_flow.complete_current_level()
		var next_profile: LevelProfile = _run_state.get_current_level_profile()
		if next_profile == null:
			push_error("Campaign: advanced but next level is missing.")
			return
		SaveManager.data.next_normal_level_order = next_profile.level_order
		SaveManager.data.current_scene = SceneRouter.OPENING_ROOM_SCENE_PATH
		if not SaveManager.data.completed_normal_level_ids.has(finished_level_id):
			SaveManager.data.completed_normal_level_ids.append(finished_level_id)
		if SaveManager.save_game() != OK:
			push_error("Campaign: failed to save progress before returning to room.")
			return
		var route_error: Error = SceneRouter.goto_opening_room()
		if route_error != OK:
			push_error("Campaign: cannot return to room: %s" % error_string(route_error))
	elif completion == LevelRunState.CompletionResult.ALL_NORMAL_LEVELS_COMPLETED:
		_enter_divine_descent()
	else:
		return
	rest_continue_requested.emit(finished_session)


# 末关只发起独立终局流程，战斗事实和演出由组件持有。
func _enter_divine_descent() -> void:
	if _divine_descent_flow != null or not _run_state.is_all_normal_levels_completed():
		return
	_divine_descent_flow = DivineDescentFlow.new()
	add_child(_divine_descent_flow)
	_divine_descent_flow.entered.connect(_on_divine_descent_entered)
	_divine_descent_flow.completed.connect(_finish_divine_descent)
	if use_plan_b_campaign:
		_battle_audio.call("bind_flows", _contradiction_oracle_flow, _divine_descent_flow)
	else:
		_battle_hud.bind_audio_flows(_contradiction_oracle_flow, _divine_descent_flow)
	if not _divine_descent_flow.configure_formal_parameters(
			divine_decay_config.auto_repeat_interval_min_seconds, divine_decay_config.auto_repeat_interval_max_seconds,
			divine_decay_config.converge_ratio, divine_decay_config.final_emphasis_duration_seconds):
		push_error("Sandbox: 神降临正式参数无效。")
		return
	var attempt_hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	var attempt_stage: CombatStage = _battle_attempt_flow.get_combat_stage()
	var attempt_opponent: OpponentPKBar = _battle_attempt_flow.get_opponent_pk_bar()
	if not _divine_descent_flow.start(
			SaveManager.data, level_catalog, _run_state.get_current_level_profile(),
			SAMPLE_TIER_CATALOG, attempt_hit_resolution, attempt_stage, _contradiction_oracle_flow.get_contradiction_system(),
			_barrage_area, attempt_opponent, _attack_charge_input, battle_config, divine_decay_config,
			{
				"repeat_interval_seconds": divine_repeat_interval_seconds,
				"fade_seconds": divine_fade_seconds, "hold_seconds": divine_hold_seconds,
				"input_scale": divine_input_scale, "input_return_seconds": divine_input_return_seconds,
				"trait_colors": divine_trait_colors,
			}):
		_divine_descent_flow.queue_free()
		_divine_descent_flow = null
		push_error("Sandbox: 无法启动神降临流程。")


# 根场景收起普通、神谕和休息阶段，再通知外部终局已经进入。
func _on_divine_descent_entered(session: DivineDescentSession) -> void:
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("set_enabled", false)
	_battle_attempt_flow.stop()
	_contradiction_oracle_flow.stop()
	_rest_result_view.hide_result()
	_rest_session = null
	if use_plan_b_campaign:
		# 神降临复用旧弹幕记录收束占比；Plan B 普通战斗隐藏该视图，进入终局时恢复。
		_barrage_area.visible = true
		_oracle_candidate_display.visible = false
	_battle_hud.show_battle_state("神降临")
	divine_descent_entered.emit(session)


# 完成信号已经携带接收结果；根场景只存盘并请求顶层路由。
func _finish_divine_descent(result: EndingSession) -> void:
	if not is_inside_tree():
		return
	# 同一真实存档保留已提交倾向与奖励；写盘失败必须留下明确证据。
	SaveManager.data.ending_display_data = result.get_display_data()
	SaveManager.data.current_scene = SceneRouter.ENDING_SCENE_PATH
	var last_id := _run_state.get_current_level_profile().level_id
	if not SaveManager.data.completed_normal_level_ids.has(last_id):
		SaveManager.data.completed_normal_level_ids.append(last_id)
	if SaveManager.save_game() != OK:
		push_error("Sandbox: 终局成果存盘失败。")
	var error := SceneRouter.goto_ending(result)
	if error != OK:
		push_error("Sandbox: Ending 顶层路由失败：%s" % error_string(error))


# 根场景只消费流程实际接受的终局输入。
func _input(event: InputEvent) -> void:
	if _divine_descent_flow != null and _divine_descent_flow.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# B的结果复读交互由原Flow接收，不能绕过PA-17/PA-12完成边界。
	if _contradiction_oracle_flow != null and _contradiction_oracle_flow.has_method("handle_input") and bool(_contradiction_oracle_flow.call("handle_input", event)):
		get_viewport().set_input_as_handled()


# 联调和后续普通战斗流程通过公开入口读取阶段与 Rest 结果。
func get_contradiction_oracle_flow() -> ContradictionOracleFlow:
	return _contradiction_oracle_flow


# 普通战斗与后续阶段通过此入口订阅同一尝试流程。
func get_battle_attempt_flow() -> BattleAttemptFlow:
	return _battle_attempt_flow


## PB-06 integration runner and sibling flows read the same live Plan B Host.
func get_plan_b_battle_host() -> PlanBBattleHost:
	return _plan_b_host


func get_plan_b_content_catalog() -> Object:
	return _plan_b_content_catalog


func get_plan_b_battle_ui() -> Control:
	return _battle_hud


func get_oracle_candidate_display() -> FinalOracleCandidateDisplay:
	return _oracle_candidate_display


# Rest 页面验收与结果展示共用同一视图实例。
func get_rest_result_view() -> RestResultView:
	return _rest_result_view


# 终局读取同一流程对象。
func get_divine_descent_flow() -> DivineDescentFlow:
	return _divine_descent_flow


# 普通与复读都由同一生成事实计评论，等待请求和失败生成不提前入账。
func _on_barrage_generated(_view: BarrageView) -> void:
	SaveManager.data.live_session.record_generated_comments(1)
	# 对手普通前景实际生成才记对手评论；复读与装饰聊天不冒充对手业务事件。
	if _opponent_live != null and _view.runtime_record != null and not _view.runtime_record.is_repeat and not _view.runtime_record.is_contradiction:
		_opponent_live.record_generated_comments(1)


## 首批生成前绑定真实对手数据；正式表缺初始人数，明确保留缺配置状态。
func _prepare_opponent_live(level: LevelProfile) -> void:
	if level == null:
		return
	if use_plan_b_campaign:
		_plan_b_level_ready = false
		_plan_b_host.available_level = level.level_id
		_plan_b_content_catalog.call("set_random_seed", 20261017 + level.level_order)
		if not bool(_plan_b_content_catalog.call("configure_level", level)):
			push_error("Sandbox: C 无法为当前 LevelProfile 配置四关 Plan B 词池。")
			return
		_plan_b_level_ready = true
	_opponent_live = SaveManager.data.get_opponent_live_session(level.streamer_id)
	_opponent_live.configure_formal_rules(BattleAttemptFlow.FORMAL_COMBAT_NUMERICS)
	_opponent_live.initialize_session(_opponent_live.fan_count)
	_opponent_live.set_opening_viewers(randf_range(
		BattleAttemptFlow.FORMAL_COMBAT_NUMERICS.opening_viewer_multiplier_min,
		BattleAttemptFlow.FORMAL_COMBAT_NUMERICS.opening_viewer_multiplier_max))
	_battle_hud.bind_opponent_live_session(_opponent_live, ["fan_count"])
	if not use_plan_b_campaign:
		%OpponentLiveDataHud.tooltip_text = "对手评论来自实际前景生成。初始粉丝与热度事件映射尚待配置。"


## 独立A/B预览沿用09增量，对手事件含义须人工批准后才能作为正式规则。
func _on_opponent_shot_result(_snapshot: AttackTargetSnapshot, submission: Dictionary, _tier: int, _stats: RepeatGenerationStats) -> void:
	if not opponent_reaction_preview_enabled or _opponent_live == null:
		return
	var delta := float(submission.get("hit_resolution_result", {}).get("total_pk_delta", 0.0))
	if delta < 0.0:
		_opponent_live.record_normal_hit_live_rule()
	elif delta > 0.0:
		_opponent_live.record_trap_hit_live_rule()


## UI及实机验收读取同一所有者快照，缺配置标记随结果交接。
func get_opponent_live_snapshot() -> Dictionary:
	if _opponent_live == null:
		return {}
	return {
		"viewer_count": _opponent_live.viewer_count, "like_count": _opponent_live.like_count,
		"comment_count": _opponent_live.comment_count, "fan_count": _opponent_live.fan_count,
		"reaction_preview": opponent_reaction_preview_enabled,
		"initial_fans_configured": false,
	}


# 离开验收场时撤销尚未提交的本场倾向，已有周目成果由 SaveData 保留。
func _exit_tree() -> void:
	_reset_paradox_presentation()
	if _trait_runtime != null:
		_trait_runtime.unbind()
	if _contradiction_oracle_flow != null:
		_contradiction_oracle_flow.stop()
	if _divine_descent_flow != null:
		_divine_descent_flow.stop()
	if is_instance_valid(_battle_attempt_flow):
		_battle_attempt_flow.stop()
	if SaveManager.data != null:
		SaveManager.data.tendency_state.rollback_attempt_tendency()


# PA-18 完成只放行既有失败 UI，失败路由仍由 Sandbox / Flow 拥有。
func _on_failure_presentation_finished() -> void:
	if use_plan_b_campaign:
		%FailureOverlay.show()
	_battle_hud.show_failure()


## 12 表正式字段直接交给已有 Flow，避免再次维护一组默认数值。
func _configure_oracle_parameters() -> bool:
	var file := FileAccess.open("res://data/source_tables/12_神谕参数.csv", FileAccess.READ)
	if file == null:
		return false
	file.get_csv_line()
	var values: Dictionary = {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() >= 2:
			values[row[0]] = row[1]
	return _contradiction_oracle_flow.configure_oracle_parameters(
		float(values.get("selection_time_s", 0)), int(values.get("max_candidates", 0)))


## 真实教学完成后立即保存步骤；失败重开及跨场景恢复均消费同一记录。
func _on_tutorial_step_completed(step_id: String) -> void:
	if SaveManager.data.completed_tutorial_step_ids.has(step_id):
		return
	SaveManager.data.completed_tutorial_step_ids.append(step_id)
	if SaveManager.save_game() != OK:
		push_error("Sandbox: 教学进度保存失败。")


## 集成验收读取正式运行器，测试不直接通知教学完成事件。
func get_tutorial_runner() -> TutorialStepRunner:
	return _tutorial_runner


## E交付后由组合方注入已批准布局；生产根不引用TEST_ONLY或固化A/B偏置。
func configure_mobile_touch(layout: Resource) -> bool:
	var path := "res://ui/mobile/mobile_touch_aim.tscn"
	if layout == null or not ResourceLoader.exists(path) or not _attack_charge_input.has_method("cancel_pointer_attack"):
		return false
	var offset: Variant = layout.get("aim_offset_mm")
	if not offset is Vector2 or (offset as Vector2).is_zero_approx():
		return false
	if not is_instance_valid(_mobile_touch):
		_mobile_touch = (load(path) as PackedScene).instantiate() as Control
		_mobile_touch.set("layout", layout)
		add_child(_mobile_touch)
		_mobile_touch.connect("safe_area_changed", func(rect: Rect2): mobile_safe_area_changed.emit(rect))
		get_viewport().size_changed.connect(_configure_mobile_regions)
	else:
		_mobile_touch.set("layout", layout)
	if not bool(_mobile_touch.call("bind_attack_input", _attack_charge_input)):
		return false
	_configure_mobile_regions()
	_refresh_mobile_touch_phase()
	return true


## HUD可消费E实际安全区，未注入时返回当前Viewport范围。
func get_mobile_safe_viewport_rect() -> Rect2:
	return _mobile_touch.call("get_safe_viewport_rect") if is_instance_valid(_mobile_touch) else get_viewport().get_visible_rect()


## 只传实际战斗区Viewport矩形，重排时由E组件取消旧手势。
func _configure_mobile_regions() -> void:
	if is_instance_valid(_mobile_touch):
		_mobile_touch.call("configure_regions", _barrage_area.get_global_rect())


## 阶段状态归原Flow，移动组件只在当前允许玩家参与时接管触摸。
func _refresh_mobile_touch_phase() -> void:
	if not is_instance_valid(_mobile_touch) or _battle_attempt_flow == null:
		return
	var active: bool = _battle_attempt_flow.is_normal_combat_active() and not _battle_hud.is_stage_transition_playing() and not _pa11_connection_dialogue_active
	var system := _contradiction_oracle_flow.get_contradiction_system()
	if system != null and _contradiction_oracle_flow.is_contradiction_active():
		active = system.get_outcome() == ContradictionBreakSystem.Outcome.PENDING
	var timer := _contradiction_oracle_flow.get_selection_timer()
	if timer != null and timer.is_running():
		active = true
	_mobile_touch.call("set_enabled", active and not get_tree().paused and _rest_session == null)
