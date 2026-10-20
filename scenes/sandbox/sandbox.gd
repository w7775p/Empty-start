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
const BARRAGE_IMPACT_SCRIPT: Script = preload("res://systems/presentation/barrage_impact_presenter.gd")
const PA09_FEEDBACK_SCRIPT: Script = preload("res://systems/presentation/combat_hit_feedback.gd")
const BATTLE_AUDIO_SCRIPT: Script = preload("res://core/audio/battle_audio_presenter.gd")
const PARADOX_COMIC_SCENE: PackedScene = preload("res://systems/presentation/paradox_comic_transition.tscn")
const PLAN_B_BATTLE_UI_SCENE: PackedScene = preload("res://ui/plan_b/plan_b_battle_ui.tscn")
const CB17_PARADOX_PRESENTATION_SCENE: PackedScene = preload("res://systems/contradiction_break/contradiction_barrage_presentation.tscn")
const PLAN_B_HOST_SCRIPT: Script = preload("res://systems/plan_b/battle/plan_b_battle_host.gd")
const PLAN_B_SIMULATION_SCRIPT: Script = preload("res://systems/plan_b/simulation/plan_b_unit_simulation.gd")
const PB14_PERFORMANCE_TRACKER_SCRIPT: Script = preload("res://systems/plan_b/performance/pb14_performance_tracker.gd")
const PLAN_B_CONTENT_CATALOG_SCRIPT: Script = preload("res://systems/plan_b/content/plan_b_content_catalog.gd")
const PLAN_B_OPPONENT_DIRECTOR_SCRIPT: Script = preload("res://systems/plan_b/opponent/fermi_opponent_director.gd")
const PB25_TUTORIAL_CONFIG_ID := "tutorial_level_001"
const PB25_LEGACY_TUTORIAL_CONFIG_ID := "tutorial_legacy_level_001"
const PB25_LEVEL_ID := "level_001"
const PB25_STEP_INTRO := "pb25_intro_publish"
const PB25_STEP_PAPER_S1 := "pb25_paper_s1_invasion"
const PB25_STEP_CONVERSION := "pb25_paper_conversion_success"
const PB25_STEP_FERMI_SCISSORS := "pb25_fermi_scissors"
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
var _cb17_paradox_presentation: Control
var _plan_b_host: PlanBBattleHost
var _plan_b_simulation: Node2D
var _plan_b_content_catalog: Object
var _plan_b_opponent_director: Object
var _pb14_performance_tracker: Node
var _plan_b_level_ready: bool = false
var _plan_b_slot_state_sync_elapsed: float = 0.0
var _rest_session: RestSession
var _rest_result_view: RestResultView
var _ending_music: EndingMusicPresenter
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
var _battle_music: TierMusicPresenter
# F3直接改PK不产生命中清场/连线对白，音乐不应等待不存在的完成事件。
var _debug_pk_update_active: bool = false
var _formal_sheet_consumer
var _active_dialogue_config: BubbleDialogueConfig
var _trait_catalog: BarrageTraitCatalog
var _trait_runtime: BarrageTraitRuntime
var _tutorial_runner: TutorialStepRunner
var _pb25_tutorial_active: bool = false
var _pb25_tutorial_ai_paused: bool = false
var _pb25_saved_opponent_auto_publish_enabled: bool = true
var _pb25_saved_counterattack_paused: bool = false
var _pb25_tutorial_paper_draw_requested: bool = false
var _pb25_tutorial_paper_rewrite_completed: bool = false
var _pb25_tutorial_paper_conversion_completed: bool = false
var _pb25_tutorial_paper_word_id: String = ""
var _pb25_tutorial_rewrite_unit_ids: Array[String] = []
var _pb25_tutorial_initial_stone_unit_ids: Dictionary = {}
var _pb25_tutorial_force_conversion_remaining: float = 0.0
var _pb25_tutorial_fermi_story_remaining: float = 0.0
var _pb25_tutorial_fermi_scissors_word_id: String = ""
var _pb25_tutorial_fermi_scissors_published: bool = false
var _pb25_tutorial_fermi_story_pending: bool = false
var _pb25_tutorial_bubble_sequence_id: StringName = &""
var _pb25_tutorial_bubble_step_id: String = ""
var _pb25_tutorial_bubble_pending: Array[Dictionary] = []
var _pb25_tutorial_bubble_sequence_counter: int = 0
var _result_feedback_system: ContradictionBreakSystem
var _opponent_live: LiveSessionData
var _mobile_touch: Control


# 场景只创建生命周期对象并接线；PK、Tier、倾向等状态留在各自所有者。
func _ready() -> void:
	# 在组合流程前绑定 Sandbox，让初始化中断时 F3 仍能显示等待状态。
	_debug_panel.call("bind_sandbox", self)
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
		_battle_audio.call("bind_plan_b_sources", _plan_b_host, _plan_b_simulation)
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
	_ending_music = EndingMusicPresenter.new()
	add_child(_ending_music)
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
	_tutorial_runner.hint_requested.connect(_on_pb25_tutorial_hint_requested)
	_tutorial_runner.tutorial_completed.connect(_on_tutorial_completed)
	_battle_attempt_flow.shot_resolved.connect(_tutorial_runner.on_shot_resolved)
	if use_plan_b_campaign:
		_battle_hud.dialogue_sequence_completed.connect(
			_on_pb25_tutorial_dialogue_sequence_completed
		)
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
	_battle_hud.tier_breakthrough_fading.connect(_on_tier_breakthrough_fading)
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
	_battle_hud.dialogue_bubble_presented.connect(_on_dialogue_bubble_presented)
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
	# CB-17 只观察既有 BArea 和正式准星；候选、释放快照与真假结果继续归现有流程。
	_cb17_paradox_presentation = CB17_PARADOX_PRESENTATION_SCENE.instantiate() as Control
	if _cb17_paradox_presentation == null:
		return false
	_cb17_paradox_presentation.name = "ContradictionBarragePresentation"
	_cb17_paradox_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cb17_paradox_presentation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paradox_layer.add_child(_cb17_paradox_presentation)
	if not bool(_cb17_paradox_presentation.call("bind_battle_nodes", _barrage_area, _aim_reticle)):
		push_error("Sandbox: CB-17 无法绑定现有弹幕区域与准星。")
		return false
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
	_plan_b_host.player_s1_rewrite_resolved.connect(_on_pb25_player_s1_rewrite_resolved)
	_plan_b_host.unit_changed.connect(_on_pb25_unit_changed)
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
	if is_instance_valid(_battle_music):
		if current_tier > 0 and _battle_music.is_waiting_for_connection() and not _debug_pk_update_active:
			_battle_music.begin_connection()
		if _debug_pk_update_active:
			_battle_music.skip_connection_for_debug(current_tier)
		_battle_music.request_tier(current_tier, _battle_music.profile.hold_intro_through_first_tier and not _debug_pk_update_active)
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
	if paused:
		AudioManager.stop_dialogue_voice()
	if is_instance_valid(_ending_music):
		_ending_music.set_paused(paused)
	if is_instance_valid(_rest_result_view):
		_rest_result_view.set_music_paused(paused)
	if is_instance_valid(_battle_music):
		_battle_music.set_paused(paused)
	if paused and _attack_charge_input.has_method("cancel_pointer_attack"):
		_attack_charge_input.call("cancel_pointer_attack")
	_refresh_mobile_touch_phase()


# 按当前关重建尝试；重开与切到下一关共用清理，保留此前周目成果。
func restart_current_attempt() -> void:
	# 已进入终局后不能通过普通重开入口恢复 PK、档位与矛盾规则。
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		return
	AudioManager.stop_dialogue_voice()
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


## DebugPanel 重开后读取真实 Host / Flow 状态，避免把无效请求提示为成功。
func debug_restart_current_attempt() -> bool:
	restart_current_attempt()
	if use_plan_b_campaign:
		return _plan_b_host != null and _plan_b_host.get_battle_state() == &"running"
	return _battle_attempt_flow != null and _battle_attempt_flow.is_normal_combat_active()


# 当前关的角色和素材由一次尝试启动事实提供；HUD 只呈现组合方状态。
func _on_attempt_started(current_level: LevelProfile, _hit: HitResolution, stage: CombatStage, _queue: RepeatDelayQueue) -> void:
	AudioManager.stop_dialogue_voice()
	# 每次尝试先清理旧消费者，再按真实主播选择配置，旧退出回调不能停新曲。
	if is_instance_valid(_battle_music):
		remove_child(_battle_music)
		_battle_music.queue_free()
		_battle_music = null
	var music_profile: TierMusicProfile = BossMusicCatalog.find_profile(StringName(current_level.streamer_id))
	if music_profile != null:
		_battle_music = TierMusicPresenter.new()
		_battle_music.profile = music_profile
		add_child(_battle_music)
		_battle_music.start_battle(stage.get_current_tier())
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
	# 表现表按稳定 level_id 解析，并在同一尝试入口刷新主播、立绘、对白与评论。
	var presentation: Dictionary = _formal_sheet_consumer.get_level_presentation(current_level.level_id)
	_battle_hud.configure_opponent_result(current_level, presentation)
	_trait_runtime.begin_attempt(current_level)
	_reset_pb25_tutorial_attempt_state()
	var tutorial_config_id := ""
	if use_plan_b_campaign and current_level.level_id == PB25_LEVEL_ID:
		tutorial_config_id = current_level.tutorial_config_id
	elif not use_plan_b_campaign and not _battle_attempt_flow.uses_external_pk_source():
		# 保持旧弹幕战的瞄准/蓄力/命中教学；24表为其保留单独配置。
		tutorial_config_id = (
			PB25_LEGACY_TUTORIAL_CONFIG_ID
			if current_level.level_id == PB25_LEVEL_ID
			else current_level.tutorial_config_id
		)
	_pb25_tutorial_active = (
		use_plan_b_campaign and current_level.level_id == PB25_LEVEL_ID
		and tutorial_config_id == PB25_TUTORIAL_CONFIG_ID
	)
	_set_pb25_tutorial_ai_paused(_pb25_tutorial_active)
	if _battle_hud.has_method("set_tutorial_highlighted_battle_types"):
		_battle_hud.call("set_tutorial_highlighted_battle_types", [])
	_tutorial_runner.begin(tutorial_config_id, SaveManager.data.completed_tutorial_step_ids)
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
		elif _battle_audio != null:
			_battle_audio.call("reset_plan_b_attempt", stage.get_current_tier(), _plan_b_host.get_pk_fraction())
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
	if _pb25_tutorial_active and not bool(
			_plan_b_host.call("set_tutorial_initial_opponent_battle_type", &"type_a")):
		push_error("Sandbox: PB-25 无法指定费米初始石头棋子。")
		return false
	_battle_hud.call("set_world_bounds", board_bounds)
	_plan_b_host.start_battle(board_bounds.size, board_bounds.position)
	if _plan_b_host.get_battle_state() != &"running":
		return false
	if _pb25_tutorial_active:
		# Host.start_battle 会重新配置导演；开战后再应用教程暂停，保留 Tier 资格但冻结费米行动。
		_set_pb25_tutorial_ai_paused(true)
		if not _capture_pb25_initial_stones():
			push_error("Sandbox: PB-25 开局未生成两名 type_a 费米信徒。")
			return false
	var current_hand: Array[Dictionary] = _plan_b_host.get_player_hand()
	_refresh_plan_b_hand(current_hand)
	if _pb25_tutorial_active:
		var active_step := _tutorial_runner.get_active_step_id()
		if active_step == PB25_STEP_INTRO:
			_tutorial_runner.notify_event("pb25_tutorial_begin")
		elif active_step == PB25_STEP_PAPER_S1:
			_pb25_request_tutorial_paper_s1()
		elif active_step == PB25_STEP_FERMI_SCISSORS:
			if not _pb25_tutorial_fermi_scissors_published:
				_pb25_tutorial_fermi_story_pending = true
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
	AudioManager.stop_dialogue_voice(true)
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
		if _pb25_tutorial_active and _tutorial_runner.get_active_step_id() == PB25_STEP_INTRO:
			_tutorial_runner.notify_event("pb25_first_player_publish")
			if _tutorial_runner.get_active_step_id() == PB25_STEP_PAPER_S1:
				_pb25_request_tutorial_paper_s1()
	elif team == "opponent" and _opponent_live != null:
		_opponent_live.record_normal_hit_live_rule()
		_opponent_live.record_generated_comments(1)
	if (team == "opponent" and _pb25_tutorial_active
			and not _pb25_tutorial_fermi_scissors_word_id.is_empty()
			and word_id == _pb25_tutorial_fermi_scissors_word_id
			and str(definition.get("battle_type", "")) == "type_b"):
		# 剧情发表走正式 Host 回执，不经过导演反击次数结算。
		_pb25_tutorial_fermi_scissors_published = true
		_pb25_tutorial_fermi_story_pending = false
		_pb25_tutorial_fermi_story_remaining = 0.0
		_tutorial_runner.notify_event("pb25_fermi_scissors_published")
		# 重开恢复到最后一步时，Runner 已显示过触发状态；故事回执到达后补放同一正式提示。
		if (_pb25_tutorial_active
				and _tutorial_runner.get_active_step_id() == PB25_STEP_FERMI_SCISSORS
				and String(_pb25_tutorial_bubble_sequence_id).is_empty()):
			var current_hint: Dictionary = _tutorial_runner.get_current_hint()
			var current_hint_text := str(current_hint.get("hint_text", ""))
			_show_pb25_tutorial_bubble(
				PB25_STEP_FERMI_SCISSORS,
				current_hint_text,
				_pb25_tutorial_bubble_duration_seconds(PB25_STEP_FERMI_SCISSORS, current_hint_text)
			)


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
	if (_pb25_tutorial_active and _tutorial_runner.get_active_step_id() == PB25_STEP_PAPER_S1
			and not _pb25_tutorial_paper_draw_requested):
		_pb25_request_tutorial_paper_s1()


func _on_plan_b_counterattack_windup_started(request: Dictionary) -> void:
	if _battle_hud != null and _battle_hud.has_method("show_counterattack_windup"):
		_battle_hud.call("show_counterattack_windup", request.duplicate(true))


func _on_plan_b_counterattack_resolved(result: Dictionary) -> void:
	if _battle_hud != null and _battle_hud.has_method("show_counterattack_result"):
		_battle_hud.call("show_counterattack_result", result.duplicate(true))


func _on_opponent_word_pool_exhausted(_level_id: String, streamer_id: String) -> void:
	if _battle_hud != null:
		_battle_hud.call("show_battle_state", "%s 已用完本关发言" % streamer_id)


# 正式失败先播放 PA-18 局部演出，完成通知后再显示既有失败界面。
func _on_attempt_failed(_level: LevelProfile, _loss_streak_count: int, _hit: HitResolution, _repeat_stats: RepeatGenerationStats) -> void:
	AudioManager.stop_dialogue_voice(true)
	if is_instance_valid(_battle_music):
		_battle_music.finish_battle(&"failed")
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


# HUD已公开真实气泡呈现事实；列巴在开口时才柔化出场音乐。
func _on_dialogue_bubble_presented(side: int, event_id: StringName, text: String) -> void:
	var speaker_id: StringName = &"hamster"
	if side == BubbleDialogueEntry.SpeakerSide.OPPONENT:
		var current_level: LevelProfile = _battle_attempt_flow.get_current_level_profile()
		if current_level != null:
			speaker_id = StringName(current_level.streamer_id)
	AudioManager.play_dialogue_voice(speaker_id, text)
	if side == BubbleDialogueEntry.SpeakerSide.OPPONENT and event_id == &"combat_connected":
		if is_instance_valid(_battle_music):
			_battle_music.begin_connection_dialogue()


# T1 连线对白完整结束后恢复本档战斗，再向外转发已完成事实。
func _on_dialogue_event_sequence_completed(event_id: StringName, sequence_id: StringName, side: int) -> void:
	AudioManager.stop_dialogue_voice(true)
	if event_id == &"combat_connected":
		_pa11_connection_dialogue_active = false
		var resumed: bool = _battle_attempt_flow.resume_after_tier1_dialogue()
		if resumed:
			_resume_plan_b_after_tier_transition()
		if is_instance_valid(_battle_music) and (resumed or _battle_attempt_flow.get_current_tier() > 1):
			_battle_music.finish_connection_dialogue()
		_refresh_mobile_touch_phase()
	dialogue_event_sequence_completed.emit(event_id, sequence_id, side)


# 升档清屏完成后暂停普通战斗，再播放 HUD 现有 Tier 标签的一次突破提示。
func _on_tier_transition_cleared(previous_tier: int, current_tier: int, _cleared_count: int) -> void:
	AudioManager.stop_dialogue_voice(true)
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
func _on_tier_breakthrough_fading(_previous_tier: int, current_tier: int) -> void:
	# 对齐实际箭头淡出，过期档位不放行音乐。
	if is_instance_valid(_battle_music) and _battle_attempt_flow.get_current_tier() == current_tier:
		_battle_music.release_tier_visual(current_tier)


func _on_tier_breakthrough_finished(
		previous_tier: int, current_tier: int, completed: bool
) -> void:
	if not completed or _battle_attempt_flow.get_current_tier() != current_tier:
		return
	# 没有可播放的箭头时，沿用真实完成入口兜底；已经换段时不重播。
	_on_tier_breakthrough_fading(previous_tier, current_tier)
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
	# 转场结束进入可操作矛盾窗口，恢复高段，结果锁定仍按原流程淡出。
	if is_instance_valid(_battle_music) and _battle_music.owns_music():
		AudioManager.restore_music()
	_battle_hud.set_paradox_stage_active(true, _battle_attempt_flow.get_current_tier())
	if _battle_attempt_flow.uses_external_pk_source():
		_battle_hud.set_final_oracle_stage_active(false)
		_barrage_area.visible = true
		var current_level: LevelProfile = _battle_attempt_flow.get_current_level_profile()
		if (use_plan_b_campaign and current_level != null
				and current_level.level_id == PB25_LEVEL_ID):
			# 普通棋子战结束后，未完成提示保留存档进度并交还AI，再播放矛盾蓄力提示。
			if _pb25_tutorial_active:
				_pb25_tutorial_active = false
				_pb25_tutorial_fermi_story_pending = false
				_pb25_tutorial_force_conversion_remaining = 0.0
				_set_pb25_tutorial_ai_paused(false)
				_battle_hud.call("set_tutorial_highlighted_battle_types", [])
			_show_pb25_paradox_prompt()
		elif current_level != null:
			# 旧准心教程继续从独立 24 表配置读取，避免混入 Plan B 剧情步骤。
			var legacy_config_id := (
				PB25_LEGACY_TUTORIAL_CONFIG_ID
				if current_level.level_id == PB25_LEVEL_ID and not use_plan_b_campaign
				else current_level.tutorial_config_id
			)
			_tutorial_runner.begin(legacy_config_id, SaveManager.data.completed_tutorial_step_ids)
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
		_clear_pb25_tutorial_bubble()
	final_oracle_opened.emit(session)
	_refresh_mobile_touch_phase()


# 满值结算后先完成 PA-12 转场；矛盾流程此时仍未创建窗口或开放输入。
func _on_normal_combat_completed(
		level: LevelProfile, hit_resolution: HitResolution, repeat_stats: RepeatGenerationStats
) -> void:
	if is_instance_valid(_battle_music):
		_battle_music.finish_battle(&"enter_contradiction")
		# 击破标题/斜切出现时压至25%，让演出与音效先被听见。
		if _battle_music.owns_music():
			AudioManager.duck_music()
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
	if is_instance_valid(_battle_music) and _battle_music.owns_music():
		AudioManager.fade_to_silence()
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
	_advance_pb25_tutorial(delta)
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
	var normal_combat_active: bool = _battle_attempt_flow.is_normal_combat_active()
	var contradiction_active: bool = (
		_contradiction_oracle_flow != null and _contradiction_oracle_flow.is_contradiction_active()
	)
	var plan_b_snapshot: Dictionary = {}
	if use_plan_b_campaign and _plan_b_host != null:
		plan_b_snapshot = _plan_b_host.get_debug_snapshot()
	var battle_phase: String = "普通战斗中（NORMAL_COMBAT）" if normal_combat_active else "普通战斗未运行（INACTIVE）"
	if use_plan_b_campaign:
		match str(plan_b_snapshot.get("battle_state", "unavailable")):
			"running": battle_phase = "Plan B 棋子战斗中（RUNNING）"
			"paused": battle_phase = "Plan B 棋子战斗暂停（PAUSED）"
			"ended": battle_phase = "Plan B 棋子战斗已结束（ENDED）"
			"idle": battle_phase = "Plan B 棋子战斗等待启动（IDLE）"
			_: battle_phase = "Plan B 主机尚未就绪"
	if _divine_descent_flow != null and _divine_descent_flow.get_session() != null:
		battle_phase = "神降临（DIVINE_DESCENT）"
	elif contradiction_active:
		battle_phase = "矛盾击破（CONTRADICTION_BREAK）"
	elif _contradiction_oracle_flow != null and _contradiction_oracle_flow.get_oracle_session() != null and _rest_session == null:
		battle_phase = "终结神谕（FINAL_ORACLE）"
	elif _rest_session != null and _rest_session.is_open():
		battle_phase = "休息时刻（REST）"
	elif hit_resolution.get_player_pk() >= battle_config.maximum_player_pk:
		battle_phase = "普通战斗完成（NORMAL_COMBAT_COMPLETE）"
	if get_tree().paused:
		battle_phase += " · 暂停中"
	var can_set_player_pk: bool = normal_combat_active
	var hit_resolution_accepts_debug_pk: bool = hit_resolution.allows_normal_pk_resolution()
	can_set_player_pk = can_set_player_pk and hit_resolution_accepts_debug_pk
	if use_plan_b_campaign:
		can_set_player_pk = (
			can_set_player_pk and str(plan_b_snapshot.get("battle_state", "")) == "running"
		)
	var can_run_legacy_barrage: bool = not use_plan_b_campaign and normal_combat_active
	var director_snapshot: Dictionary = plan_b_snapshot.get("opponent_director", {})
	var can_toggle_opponent_publish: bool = (
		use_plan_b_campaign
		and str(plan_b_snapshot.get("battle_state", "")) == "running"
		and bool(director_snapshot.get("speech_enabled", false))
	)
	return {
		"is_plan_b_campaign": use_plan_b_campaign,
		"level": "第%d关" % current_level.level_order if current_level != null else "无关卡",
		"player_streamer": SaveManager.data.streamer_name if not SaveManager.data.streamer_name.is_empty() else "玩家主播",
		"opponent_streamer": current_level.streamer_name if current_level != null else "无对手",
		"battle_phase": battle_phase,
		"player_pk": hit_resolution.get_player_pk(),
		"tier": combat_stage.get_current_tier(),
		"plan_b": plan_b_snapshot,
		"attack_phase": _attack_charge_input.get_attack_phase(),
		"is_charging": _attack_charge_input.is_charge_held(),
		"normal_barrage_count": int(barrage_counts.get("normal", 0)),
		"repeat_barrage_count": int(barrage_counts.get("repeat", 0)),
		"normal_generation_enabled": _barrage_area.is_normal_generation_enabled(),
		"normal_combat_active": normal_combat_active,
		"can_set_player_pk": can_set_player_pk,
		"can_restart": current_level != null and (_divine_descent_flow == null or _divine_descent_flow.get_session() == null),
		"can_clear_barrages": contradiction_active or can_run_legacy_barrage,
		"can_spawn_normal_batch": can_run_legacy_barrage,
		"can_toggle_normal_generation": can_run_legacy_barrage,
		"can_toggle_opponent_publish": can_toggle_opponent_publish,
		"legacy_barrage_hint": (
			"Plan B 普通阶段使用棋子；矛盾阶段只开放旧弹幕清屏。"
			if use_plan_b_campaign else "旧普通战斗使用弹幕操作；矛盾阶段只开放清屏。"
		),
		"viewer_count": live_session.viewer_count,
		"like_count": live_session.like_count,
		"comment_count": live_session.comment_count,
		"fan_count": live_session.fan_count,
		"attempt_orthodox": tendency_state.attempt_orthodox_total,
		"attempt_heretical": tendency_state.attempt_heretical_total,
		"attempt_absurd": tendency_state.attempt_absurd_total,
	}


# F3 调试入口按玩法选择正式 PK 所有者，并保留旧脚本调用的数值返回值。
func debug_set_player_pk(player_pk: float) -> float:
	return float(debug_set_player_pk_with_status(player_pk).get("player_pk", 0.0))


## DebugPanel 使用带结果的入口；Plan B 的写入权仍由唯一 PK Host 持有。
func debug_set_player_pk_with_status(player_pk: float) -> Dictionary:
	if _battle_attempt_flow == null or not is_finite(player_pk):
		return {"ok": false, "player_pk": 0.0, "tier": 0}
	var current_hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
	if (not _battle_attempt_flow.is_normal_combat_active() or current_hit_resolution == null
			or not current_hit_resolution.allows_normal_pk_resolution()):
		return {"ok": false, "player_pk": current_hit_resolution.get_player_pk() if current_hit_resolution != null else 0.0,
			"tier": _battle_attempt_flow.get_current_tier()}
	var expected_pk: float = clampf(player_pk, 0.0, 1.0)
	var accepted: bool = false
	var actual_pk: float = 0.0
	_debug_pk_update_active = true
	if use_plan_b_campaign:
		if _plan_b_host != null:
			accepted = _plan_b_host.set_player_pk_for_debug(expected_pk)
			actual_pk = _plan_b_host.get_pk_fraction()
	else:
		var hit_resolution: HitResolution = _battle_attempt_flow.get_hit_resolution()
		if hit_resolution != null:
			actual_pk = hit_resolution.set_player_pk_for_debug(expected_pk)
			accepted = is_equal_approx(actual_pk, expected_pk)
	_debug_pk_update_active = false
	var combat_stage: CombatStage = _battle_attempt_flow.get_combat_stage()
	var tier: int = combat_stage.get_current_tier() if combat_stage != null else 0
	var verified_pk: float = actual_pk
	if use_plan_b_campaign and _plan_b_host != null:
		verified_pk = _plan_b_host.get_pk_fraction()
	return {
		"ok": accepted and is_equal_approx(verified_pk, expected_pk),
		"player_pk": verified_pk,
		"tier": tier,
	}


# 直播调试值仍写入本场 LiveSessionData，由 Resource.changed 刷新当前 HUD。
func debug_set_live_data(viewer: int, likes: int, comments: int, fans: int) -> bool:
	if SaveManager.data == null or SaveManager.data.live_session == null:
		return false
	var live_session: LiveSessionData = SaveManager.data.live_session
	live_session.viewer_count = maxi(viewer, 0)
	live_session.like_count = maxi(likes, 0)
	live_session.comment_count = maxi(comments, 0)
	live_session.fan_count = maxi(fans, 0)
	return (live_session.viewer_count == maxi(viewer, 0)
		and live_session.like_count == maxi(likes, 0)
		and live_session.comment_count == maxi(comments, 0)
		and live_session.fan_count == maxi(fans, 0))


# 调试倾向只写当前关暂存值，不碰已提交的周目累计。
func debug_set_attempt_tendencies(orthodox: int, heretical: int, absurd: int) -> bool:
	if SaveManager.data == null or SaveManager.data.tendency_state == null:
		return false
	var tendency_state: TendencyState = SaveManager.data.tendency_state
	tendency_state.set_attempt_tendencies_for_debug(orthodox, heretical, absurd)
	return (tendency_state.attempt_orthodox_total == maxi(orthodox, 0)
		and tendency_state.attempt_heretical_total == maxi(heretical, 0)
		and tendency_state.attempt_absurd_total == maxi(absurd, 0))


# 清空当前画面弹幕并取消尚未出现的复读请求，但保留普通生成开关状态。
func debug_clear_barrages() -> bool:
	if not _can_debug_clear_barrages() or _barrage_area == null or _battle_attempt_flow == null:
		return false
	var cleared_count: int = _barrage_area.clear_current_barrages()
	var pending_count: int = _battle_attempt_flow.clear_pending_normal_repeats()
	var counts: Dictionary = _barrage_area.get_current_barrage_counts()
	return (cleared_count >= 0 and pending_count >= 0
		and int(counts.get("normal", 0)) == 0
		and int(counts.get("repeat", 0)) == 0
		and int(counts.get("contradiction", 0)) == 0)


# 使用当前关卡和 Tier 参数立即生成一批普通弹幕。
func debug_spawn_normal_batch() -> int:
	if use_plan_b_campaign or _battle_attempt_flow == null or not _battle_attempt_flow.is_normal_combat_active():
		return 0
	return _barrage_area.spawn_normal_batch_now()


# DEBUG 操作只切换 BarrageArea 的真实普通生成状态。
func debug_set_normal_generation_enabled(enabled: bool) -> bool:
	if use_plan_b_campaign or _battle_attempt_flow == null or not _battle_attempt_flow.is_normal_combat_active():
		return false
	if enabled:
		return _barrage_area.resume_normal_generation() and _barrage_area.is_normal_generation_enabled()
	_barrage_area.stop_normal_generation()
	return not _barrage_area.is_normal_generation_enabled()


## F3 通过 Host 切换对手主动发表；操作结果按 Host 当前值回读确认。
func debug_set_plan_b_opponent_auto_publish_enabled(enabled: bool) -> bool:
	if not use_plan_b_campaign or _plan_b_host == null:
		return false
	var accepted: bool = _plan_b_host.set_opponent_auto_publish_enabled_for_debug(enabled)
	var snapshot: Dictionary = _plan_b_host.get_debug_snapshot()
	return (accepted and bool(snapshot.get("opponent_auto_publish_enabled", not enabled)) == enabled)


func _can_debug_clear_barrages() -> bool:
	if _contradiction_oracle_flow != null and _contradiction_oracle_flow.is_contradiction_active():
		return true
	return not use_plan_b_campaign and _battle_attempt_flow != null and _battle_attempt_flow.is_normal_combat_active()


# 流程已经提交成果并准备好 Rest；根场景只展示同一结果对象。
func _on_rest_ready(result: RestSession) -> void:
	if is_instance_valid(_battle_music) and _battle_music.owns_music():
		_battle_music.set_paused(false)
		AudioManager.fade_out_music()
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
	_divine_descent_flow.phase_changed.connect(_ending_music.on_divine_phase)
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
	# 结局页面接管同曲，不让旧场景退出在淡入途中把音乐停掉。
	_ending_music.set_handoff(true)
	var error := SceneRouter.goto_ending(result)
	if error != OK:
		_ending_music.set_handoff(false)
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
	AudioManager.stop_dialogue_voice()
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


## PB-25 每次正式重开都清空棋子引用与计时，只保留 SaveData 已完成步骤。
func _reset_pb25_tutorial_attempt_state() -> void:
	if _pb25_tutorial_ai_paused:
		_set_pb25_tutorial_ai_paused(false)
	_pb25_tutorial_active = false
	_pb25_tutorial_paper_draw_requested = false
	_pb25_tutorial_paper_rewrite_completed = false
	_pb25_tutorial_paper_conversion_completed = false
	_pb25_tutorial_paper_word_id = ""
	_pb25_tutorial_rewrite_unit_ids.clear()
	_pb25_tutorial_initial_stone_unit_ids.clear()
	_pb25_tutorial_force_conversion_remaining = 0.0
	_pb25_tutorial_fermi_story_remaining = 0.0
	_pb25_tutorial_fermi_scissors_word_id = ""
	_pb25_tutorial_fermi_scissors_published = false
	_pb25_tutorial_fermi_story_pending = false
	_clear_pb25_tutorial_bubble()
	if _battle_hud != null and _battle_hud.has_method("set_tutorial_highlighted_battle_types"):
		_battle_hud.call("set_tutorial_highlighted_battle_types", [])


## 教学期只暂停普通自动发话与一般反击；恢复时回到本局原始开关状态。
func _set_pb25_tutorial_ai_paused(paused: bool) -> void:
	if _plan_b_host == null:
		return
	if paused:
		if not _pb25_tutorial_ai_paused:
			_pb25_saved_opponent_auto_publish_enabled = _plan_b_host.opponent_auto_publish_enabled
			var director_state: Dictionary = _plan_b_host.get_debug_snapshot().get("opponent_director", {})
			_pb25_saved_counterattack_paused = bool(director_state.get("counterattack_paused", false))
		_plan_b_host.opponent_auto_publish_enabled = false
		_plan_b_host.set_counterattack_paused(true)
		_pb25_tutorial_ai_paused = true
		return
	if not _pb25_tutorial_ai_paused:
		return
	_plan_b_host.opponent_auto_publish_enabled = _pb25_saved_opponent_auto_publish_enabled
	_plan_b_host.set_counterattack_paused(_pb25_saved_counterattack_paused)
	_pb25_tutorial_ai_paused = false


## 24表仍拥有提示文案与事件顺序；正式 Plan B 将当前步骤送入煲煲主播气泡。
func _on_pb25_tutorial_hint_requested(step_id: String, hint_text: String) -> void:
	if not _pb25_tutorial_active:
		return
	if step_id == PB25_STEP_FERMI_SCISSORS and not _pb25_tutorial_fermi_scissors_published:
		# 已完成的剪刀发表在重开后重新执行；先等成功回执再显示鼠的求助文案。
		_pb25_tutorial_fermi_story_pending = true
		return
	_show_pb25_tutorial_bubble(
		step_id, hint_text, _pb25_tutorial_bubble_duration_seconds(step_id, hint_text)
	)
	match step_id:
		PB25_STEP_INTRO:
			_battle_hud.call("set_tutorial_highlighted_battle_types", ["type_a", "type_b", "type_c"])
		PB25_STEP_PAPER_S1:
			_battle_hud.call("set_tutorial_highlighted_battle_types", ["type_c"])
		PB25_STEP_CONVERSION:
			_battle_hud.call("set_tutorial_highlighted_battle_types", [])
		PB25_STEP_FERMI_SCISSORS:
			_battle_hud.call("set_tutorial_highlighted_battle_types", [])


## 正式提示保持一条剧情序列，排版、尾巴、动画与寿命均沿用左侧主播气泡。
func _show_pb25_tutorial_bubble(step_id: String, text: String, duration_seconds: float) -> bool:
	if (_battle_hud == null or not _battle_hud.has_method("enqueue_dialogue_sequence")
			or not _battle_hud.has_method("clear_dialogue_bubbles")):
		push_error("Sandbox: Plan B HUD 缺少现有主播气泡队列接口。")
		return false
	# 真实步骤可以提前推进；上一句教程对白必须播完，再轮到下一句。
	if not String(_pb25_tutorial_bubble_sequence_id).is_empty():
		_pb25_tutorial_bubble_pending.append({
			"step_id": step_id,
			"text": text,
			"duration_seconds": duration_seconds,
		})
		return true
	# 本任务当前没有活跃对白时，才清理左侧普通复读并开始新阶段。
	_pb25_tutorial_bubble_sequence_id = &""
	_pb25_tutorial_bubble_step_id = ""
	_battle_hud.call("clear_dialogue_bubbles", BubbleDialogueEntry.SpeakerSide.PLAYER)
	_pb25_tutorial_bubble_sequence_counter += 1
	var sequence_id := StringName(
		"pb25_tutorial_%s_%d" % [step_id, _pb25_tutorial_bubble_sequence_counter]
	)
	var entry := BubbleDialogueEntry.new()
	entry.side = BubbleDialogueEntry.SpeakerSide.PLAYER
	entry.text = text
	entry.event_id = &"pb25_tutorial_hint"
	entry.priority = BubbleDialogueEntry.Priority.PLOT
	entry.display_duration_seconds = maxf(duration_seconds, 0.1)
	var entries: Array[BubbleDialogueEntry] = [entry]
	_pb25_tutorial_bubble_sequence_id = sequence_id
	_pb25_tutorial_bubble_step_id = step_id
	var queued_id: Variant = _battle_hud.call("enqueue_dialogue_sequence", entries, sequence_id)
	if str(queued_id) != str(sequence_id):
		_pb25_tutorial_bubble_sequence_id = &""
		_pb25_tutorial_bubble_step_id = ""
		push_error("Sandbox: PB-25 引导文案未进入仓鼠主播气泡队列：%s" % step_id)
		return false
	return true


## 中文正文按实际字符数留出阅读时间，RichTextLabel 负责气泡内折行与滚动。
func _pb25_tutorial_bubble_duration_seconds(step_id: String, text: String) -> float:
	var text_reading_time := clampf(4.0 + float(text.length()) / 8.0, 6.5, 10.0)
	match step_id:
		PB25_STEP_INTRO:
			return maxf(text_reading_time, 8.0)
		PB25_STEP_PAPER_S1:
			return maxf(text_reading_time, 12.0)
		PB25_STEP_CONVERSION:
			return maxf(text_reading_time, 6.5)
		PB25_STEP_FERMI_SCISSORS:
			return maxf(text_reading_time, 9.0)
		"pb25_paradox_prompt":
			return maxf(text_reading_time, 9.0)
	return text_reading_time



## 只在仍有本任务气泡时清理左侧队列；其他关卡沿用自己的对白生命周期。
func _clear_pb25_tutorial_bubble() -> void:
	_pb25_tutorial_bubble_pending.clear()
	if String(_pb25_tutorial_bubble_sequence_id).is_empty():
		return
	_pb25_tutorial_bubble_sequence_id = &""
	_pb25_tutorial_bubble_step_id = ""
	if _battle_hud != null and _battle_hud.has_method("clear_dialogue_bubbles"):
		_battle_hud.call("clear_dialogue_bubbles", BubbleDialogueEntry.SpeakerSide.PLAYER)


## 最终教程只在左主播剧情气泡完整播放并渐隐后完成。
func _on_pb25_tutorial_dialogue_sequence_completed(sequence_id: StringName, side: int) -> void:
	if (side != BubbleDialogueEntry.SpeakerSide.PLAYER
			or sequence_id != _pb25_tutorial_bubble_sequence_id):
		return
	var completed_step_id := _pb25_tutorial_bubble_step_id
	_pb25_tutorial_bubble_sequence_id = &""
	_pb25_tutorial_bubble_step_id = ""
	# 费米的剧情发表要在成功感染的鼓励台词播完后才触发。
	if (completed_step_id == PB25_STEP_CONVERSION and _pb25_tutorial_active
			and _tutorial_runner.get_active_step_id() == PB25_STEP_CONVERSION):
		_schedule_pb25_fermi_scissors()
	if (completed_step_id == PB25_STEP_FERMI_SCISSORS and _pb25_tutorial_active
			and _tutorial_runner.get_active_step_id() == PB25_STEP_FERMI_SCISSORS):
		_tutorial_runner.notify_event("pb25_final_hint_finished")
	if not _pb25_tutorial_bubble_pending.is_empty():
		var next_hint: Dictionary = _pb25_tutorial_bubble_pending.pop_front()
		_show_pb25_tutorial_bubble(
			str(next_hint.get("step_id", "")),
			str(next_hint.get("text", "")),
			float(next_hint.get("duration_seconds", 8.0))
		)


## 只发起一次合法的 type_c/S1 抽牌；开局前恢复提示时由正式开战入口重试。
func _pb25_request_tutorial_paper_s1() -> bool:
	if (_pb25_tutorial_paper_draw_requested or _plan_b_host == null
			or _tutorial_runner.get_active_step_id() != PB25_STEP_PAPER_S1):
		return _pb25_tutorial_paper_draw_requested
	if not _plan_b_host.request_tutorial_type_c_s1_draw():
		return false
	_pb25_tutorial_paper_draw_requested = true
	return true


## 保存本次新开局的两名石头 Fermi ID；这些临时引用绝不写进存档。
func _capture_pb25_initial_stones() -> bool:
	_pb25_tutorial_initial_stone_unit_ids.clear()
	for snapshot: Dictionary in _plan_b_host.get_unit_snapshots():
		if (str(snapshot.get("team", "")) == "opponent"
				and str(snapshot.get("battle_type", "")) == "type_a"):
			_pb25_tutorial_initial_stone_unit_ids[str(snapshot.get("unit_id", ""))] = true
	return _pb25_tutorial_initial_stone_unit_ids.size() == 2


## PB-23 只报告真实成功 S1；PB-25 额外要求玩家此前旧友军实际改口至少一名。
func _on_pb25_player_s1_rewrite_resolved(result: Dictionary) -> void:
	if (not _pb25_tutorial_active
			or _tutorial_runner.get_active_step_id() != PB25_STEP_PAPER_S1):
		return
	var word_id := str(result.get("word_id", ""))
	var definition := _plan_b_host.get_word_definition(word_id)
	var rewrite_ids_value: Variant = result.get("rewrite_unit_ids", [])
	if (str(definition.get("battle_type", "")) != "type_c"
			or int(definition.get("strength", 0)) != 1
			or int(result.get("rewrite_count", 0)) < 1
			or not rewrite_ids_value is Array):
		return
	_pb25_tutorial_paper_word_id = word_id
	_pb25_tutorial_paper_rewrite_completed = true
	_pb25_tutorial_rewrite_unit_ids.clear()
	for unit_id: Variant in rewrite_ids_value:
		_pb25_tutorial_rewrite_unit_ids.append(str(unit_id))
	_pb25_tutorial_force_conversion_remaining = 2.0
	_try_complete_pb25_paper_stage()


## 只接受初始石头在真实转换后变成当前玩家✋话语的单位变化。
func _on_pb25_unit_changed(unit_id: String, reason: StringName) -> void:
	if (not _pb25_tutorial_active or reason != &"convert"
			or not _pb25_tutorial_initial_stone_unit_ids.has(unit_id)):
		return
	var snapshot := _pb25_get_unit_snapshot(unit_id)
	if (str(snapshot.get("team", "")) != "player"
			or str(snapshot.get("word_id", "")) != _pb25_tutorial_paper_word_id
			or str(snapshot.get("battle_type", "")) != "type_c"):
		return
	_pb25_tutorial_paper_conversion_completed = true
	_try_complete_pb25_paper_stage()


## 旧友军改口和初始✊被✋压制均为真后，才完成异端阶段。
func _try_complete_pb25_paper_stage() -> void:
	if (not _pb25_tutorial_active or not _pb25_tutorial_paper_rewrite_completed
			or not _pb25_tutorial_paper_conversion_completed
			or _tutorial_runner.get_active_step_id() != PB25_STEP_PAPER_S1):
		return
	_pb25_tutorial_force_conversion_remaining = 0.0
	_tutorial_runner.notify_event("pb25_paper_type_c_conversion")


## 仅当自然接触未成功时，按 simulation 的正式克制表为一对现存棋子执行一次感染。
func _apply_pb25_tutorial_conversion_fallback() -> bool:
	var snapshots: Array[Dictionary] = _plan_b_host.get_unit_snapshots()
	# 优先让已经真实改口的老友军完成剧情感染，失效时才退到同批其他✋单位。
	var source_unit_ids: Array[String] = _pb25_tutorial_rewrite_unit_ids.duplicate()
	for snapshot: Dictionary in snapshots:
		var unit_id := str(snapshot.get("unit_id", ""))
		if (str(snapshot.get("team", "")) == "player"
				and str(snapshot.get("word_id", "")) == _pb25_tutorial_paper_word_id
			and str(snapshot.get("battle_type", "")) == "type_c"
			and not source_unit_ids.has(unit_id)):
			source_unit_ids.append(unit_id)
	for source_unit_id: String in source_unit_ids:
		var snapshot := _pb25_get_unit_snapshot(source_unit_id)
		if (str(snapshot.get("team", "")) != "player"
				or str(snapshot.get("word_id", "")) != _pb25_tutorial_paper_word_id
				or str(snapshot.get("battle_type", "")) != "type_c"):
			continue
		for target_id: String in _pb25_tutorial_initial_stone_unit_ids:
			var target_snapshot := _pb25_get_unit_snapshot(target_id)
			if (str(target_snapshot.get("team", "")) != "opponent"
					or str(target_snapshot.get("battle_type", "")) != "type_a"):
				continue
			var result: Dictionary = _plan_b_host.call(
				"apply_tutorial_conversion", snapshot.get("unit_id", ""), target_id
			)
			if bool(result.get("ok", false)):
				_pb25_tutorial_paper_conversion_completed = true
				_try_complete_pb25_paper_stage()
				return true
	return false


## 不持有 Unit 节点引用；只按 Host 权威快照查当前棋子事实。
func _pb25_get_unit_snapshot(unit_id: String) -> Dictionary:
	for snapshot: Dictionary in _plan_b_host.get_unit_snapshots():
		if str(snapshot.get("unit_id", "")) == unit_id:
			return snapshot
	return {}


## 反馈先展示一小段时间，再由 Fermi 通过正常发表接口讲出指定✌️神谕。
func _schedule_pb25_fermi_scissors() -> void:
	_pb25_tutorial_fermi_story_pending = true
	_pb25_tutorial_fermi_story_remaining = 0.25


## 找一条当前关卡可用的 type_b 词句，用真实 Host 批次发表来完成剧情动作。
func _publish_pb25_fermi_scissors() -> bool:
	if _plan_b_host == null or _plan_b_host.get_battle_state() != &"running":
		return false
	for word_id: String in _plan_b_host.get_available_word_ids("opponent"):
		var definition := _plan_b_host.get_word_definition(word_id)
		if str(definition.get("battle_type", "")) != "type_b":
			continue
		var bounds: Rect2 = _battle_hud.call("get_board_world_bounds")
		_pb25_tutorial_fermi_scissors_word_id = word_id
		var result: Dictionary = _plan_b_host.publish_word("opponent", word_id, bounds.get_center())
		if bool(result.get("ok", false)):
			return true
		_pb25_tutorial_fermi_scissors_word_id = ""
		if StringName(str(result.get("reason", ""))) == &"cooldown":
			return false
	return false


## 给自然感染两秒机会，并在本关 S1 或故事词发表失败时短间隔重试。
func _advance_pb25_tutorial(delta: float) -> void:
	if not _pb25_tutorial_active or _tutorial_runner == null or _plan_b_host == null:
		return
	var active_step := _tutorial_runner.get_active_step_id()
	var battle_running := _plan_b_host.get_battle_state() == &"running"
	if battle_running:
		if active_step == PB25_STEP_PAPER_S1:
			if not _pb25_tutorial_paper_draw_requested:
				_pb25_request_tutorial_paper_s1()
			if (_pb25_tutorial_paper_rewrite_completed
					and not _pb25_tutorial_paper_conversion_completed):
				_pb25_tutorial_force_conversion_remaining = maxf(
					0.0, _pb25_tutorial_force_conversion_remaining - delta
				)
				if _pb25_tutorial_force_conversion_remaining <= 0.0:
					if not _apply_pb25_tutorial_conversion_fallback():
						_pb25_tutorial_force_conversion_remaining = 0.5
		if (_pb25_tutorial_fermi_story_pending
				and active_step in [PB25_STEP_CONVERSION, PB25_STEP_FERMI_SCISSORS]):
			_pb25_tutorial_fermi_story_remaining = maxf(
				0.0, _pb25_tutorial_fermi_story_remaining - delta
			)
			if _pb25_tutorial_fermi_story_remaining <= 0.0:
				if not _publish_pb25_fermi_scissors():
					_pb25_tutorial_fermi_story_remaining = 0.5
## 故事教学完播后关闭高亮并恢复本局对手原始 AI 状态。
func _on_tutorial_completed(config_id: String) -> void:
	if config_id != PB25_TUTORIAL_CONFIG_ID or not _pb25_tutorial_active:
		return
	_pb25_tutorial_active = false
	_pb25_tutorial_force_conversion_remaining = 0.0
	_pb25_tutorial_fermi_story_remaining = 0.0
	_pb25_tutorial_fermi_story_pending = false
	_clear_pb25_tutorial_bubble()
	_set_pb25_tutorial_ai_paused(false)
	if _battle_hud != null and _battle_hud.has_method("set_tutorial_highlighted_battle_types"):
		_battle_hud.call("set_tutorial_highlighted_battle_types", [])


## 矛盾阶段沿用既有攻击输入，只替换当前教程面板里的提示文字。
func _show_pb25_paradox_prompt() -> void:
	_show_pb25_tutorial_bubble(
		"pb25_paradox_prompt",
		"它的身上藏着秘密！\n\n真相只有一个！\n\n长按蓄力射击！",
		8.0
	)


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
