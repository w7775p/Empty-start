## 普通战斗界面只读取组合方的状态；设计矩形保存于 Scene，运行时只整体缩放。
extends Control

signal dialogue_sequence_completed(sequence_id: StringName, side: int)

const PortraitMotion = preload("res://systems/presentation/streamer_portrait_motion.gd")
const DialogueQueueScript = preload("res://ui/streamer_bubble_dialogue/streamer_bubble_dialogue_queue.gd")

@export_range(1, 8, 1) var max_visible_dialogue_bubbles_per_side: int = 3

var player_portrait_motion: StreamerPortraitMotion
var opponent_portrait_motion: StreamerPortraitMotion
var _portrait_attack: AttackChargeInput
var _opponent_connected: bool = false
var _dialogue_queue: Node

@onready var _aim_reticle: AimReticle = %AimReticle
@onready var _battle_state: Label = %BattleStateFeedback
@onready var _player_name: Label = $PlayerStreamerArea/PlayerInfoArea/PlayerName
@onready var _opponent_name: Label = $OpponentStreamerArea/OpponentInfoArea/OpponentName
@onready var _player_portrait: TextureRect = $PlayerStreamerArea/PlayerPortraitPlaceholder/PlayerPortraitArt
@onready var _player_live_background: TextureRect = $PlayerStreamerArea/PlayerPortraitPlaceholder/PlayerLiveBackground
@onready var _player_fan_badge: TextureRect = $PlayerStreamerArea/PlayerInfoArea/PlayerFanBadge
@onready var _player_portrait_placeholder: Label = $PlayerStreamerArea/PlayerPortraitPlaceholder/PlaceholderLabel
@onready var _player_bubble_stack: StreamerBubbleStack = %PlayerBubbleStack
@onready var _opponent_portrait: TextureRect = $OpponentStreamerArea/OpponentPortraitPlaceholder/OpponentPortraitArt
@onready var _opponent_live_background: TextureRect = $OpponentStreamerArea/OpponentPortraitPlaceholder/OpponentLiveBackground
@onready var _opponent_fan_badge: TextureRect = $OpponentStreamerArea/OpponentInfoArea/OpponentFanBadge
@onready var _opponent_portrait_placeholder: Label = $OpponentStreamerArea/OpponentPortraitPlaceholder/PlaceholderLabel
@onready var _opponent_bubble_stack: StreamerBubbleStack = %OpponentBubbleStack
@onready var _player_pk_label: Label = %PlayerPK
@onready var _opponent_pk_label: Label = $BattleArea/TopBattleStatus/PKBar/OpponentPK
@onready var _pk_progress: ProgressBar = %PlayerShare
@onready var _tier_label: Label = %Tier
@onready var _charge_label: Label = $BattleArea/ChargeFeedback/ChargeState
@onready var _charge_progress: ProgressBar = %ChargeProgress
@onready var _failure_overlay: Control = %FailureOverlay
@onready var _restart_button: Button = %RestartButton


# 保留 Scene 的全部设计矩形，只订阅窗口变化并初始化显示。
func _ready() -> void:
	player_portrait_motion = PortraitMotion.new()
	player_portrait_motion.attach_portrait(_player_portrait)
	opponent_portrait_motion = PortraitMotion.new()
	opponent_portrait_motion.configure_character("alien")
	opponent_portrait_motion.attach_portrait(_opponent_portrait)
	_dialogue_queue = DialogueQueueScript.new()
	_dialogue_queue.name = "BubbleDialogueQueue"
	_dialogue_queue.call(
		"configure",
		max_visible_dialogue_bubbles_per_side,
		Callable(self, "show_dialogue_bubble"),
		Callable(self, "_clear_bubble_stack")
	)
	_dialogue_queue.connect(
		"sequence_completed", Callable(self, "_on_dialogue_sequence_completed")
	)
	add_child(_dialogue_queue)
	var parent_control: Control = get_parent() as Control
	parent_control.resized.connect(_fit_parent_size)
	_fit_parent_size()
	reset_for_attempt()


# 使用设计坐标统一缩放文字和容器，窗口变化时保持左右区和中央区的比例。
func _fit_parent_size() -> void:
	var parent_control: Control = get_parent() as Control
	if parent_control == null or size.x <= 0.0 or size.y <= 0.0:
		return
	scale = parent_control.size / size
	# 准心继承同一设计缩放，布局更新后通过其公开入口重新对齐当前鼠标。
	_aim_reticle.refresh_mouse_position()


# 主播名称由当前关资料提供，后续立绘可以替换占位节点。
func configure_streamers(player_name: String, opponent_name: String) -> void:
	_player_name.text = player_name
	_opponent_name.text = opponent_name


# 只显示 PA-02 已接入 Resource 的主播素材；空资源继续保留文字占位。
func configure_streamer_assets(
	player_portrait: Texture2D,
	player_live_background: Texture2D,
	player_fan_badge: Texture2D,
	opponent_portrait: Texture2D,
	opponent_live_background: Texture2D,
	opponent_fan_badge: Texture2D
) -> void:
	_set_texture_rect(_player_live_background, player_live_background, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_set_texture_rect(_player_portrait, player_portrait, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_set_texture_rect(_player_fan_badge, player_fan_badge, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_player_portrait_placeholder.visible = player_portrait == null

	_set_texture_rect(_opponent_live_background, opponent_live_background, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_set_texture_rect(_opponent_portrait, opponent_portrait, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_set_texture_rect(_opponent_fan_badge, opponent_fan_badge, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_opponent_portrait_placeholder.visible = opponent_portrait == null
	set_opponent_portrait_connected(_opponent_connected)


# 集成方显式绑定正式发射通知；重复绑定不会叠加回调，null 可解除旧来源。
func bind_portrait_attack(attack: AttackChargeInput) -> void:
	if is_instance_valid(_portrait_attack) and _portrait_attack.shot_snapshot_created.is_connected(play_player_shot):
		_portrait_attack.shot_snapshot_created.disconnect(play_player_shot)
	_portrait_attack = attack
	if is_instance_valid(_portrait_attack):
		_portrait_attack.shot_snapshot_created.connect(play_player_shot)


# 此入口仅接收正式满蓄快照；命中、飞行到达和蓄力刷新均不触发射击动作。
func play_player_shot(snapshot: AttackTargetSnapshot) -> void:
	if snapshot != null and _player_portrait.is_visible_in_tree():
		player_portrait_motion.play_shot()


# T0 隐藏立绘，阶段换图仍复用当前待机容器；背景与其他演出由集成方管理。
func set_opponent_portrait_connected(connected: bool) -> void:
	_opponent_connected = connected
	if _dialogue_queue != null:
		_dialogue_queue.call(
			"set_side_enabled", BubbleDialogueEntry.SpeakerSide.OPPONENT, connected
		)
	_opponent_portrait.visible = connected and _opponent_portrait.texture != null
	_opponent_portrait_placeholder.visible = connected and _opponent_portrait.texture == null


# 当前关角色 ID 由集成方传入；后续换阶段 PNG 无需重建动画层。
func configure_portrait_character(opponent_character_id: String) -> void:
	opponent_portrait_motion.configure_character(opponent_character_id)


# 组合方提交 SD-01 条目；HUD 只按发言侧转发给对应立绘区，不判断触发规则。
func show_dialogue_bubble(entry: BubbleDialogueEntry) -> StreamerBubbleView:
	if entry == null or entry.text.strip_edges().is_empty():
		return null
	match entry.side:
		BubbleDialogueEntry.SpeakerSide.PLAYER:
			return _player_bubble_stack.show_bubble(entry)
		BubbleDialogueEntry.SpeakerSide.OPPONENT:
			return _opponent_bubble_stack.show_bubble(entry)
	return null


# 后续事件消费者使用队列入口；同侧顺序、容量和优先级由 SD-03 单一持有。
func enqueue_dialogue_bubble(entry: BubbleDialogueEntry) -> bool:
	return bool(_dialogue_queue.call("enqueue_entry", entry)) if _dialogue_queue != null else false


# 关键剧情序列返回稳定本场 ID，完成时由 dialogue_sequence_completed 通知 CS-23。
func enqueue_dialogue_sequence(
	entries: Array[BubbleDialogueEntry], sequence_id: StringName = &""
) -> StringName:
	if _dialogue_queue == null:
		return &""
	return StringName(_dialogue_queue.call("enqueue_sequence", entries, sequence_id))


# 重开、关卡更换和场景离开前可显式清理指定侧或双方队列。
func clear_dialogue_bubbles(side: int = -1) -> void:
	if _dialogue_queue != null:
		_dialogue_queue.call("clear_side", side)
	else:
		_clear_bubble_stack(side)


# Queue 不持有 Stack 节点，只经 HUD 回调清理对应侧的显示对象。
func _clear_bubble_stack(side: int) -> void:
	if side == -1 or side == BubbleDialogueEntry.SpeakerSide.PLAYER:
		_player_bubble_stack.clear_bubbles()
	if side == -1 or side == BubbleDialogueEntry.SpeakerSide.OPPONENT:
		_opponent_bubble_stack.clear_bubbles()


func _on_dialogue_sequence_completed(sequence_id: StringName, side: int) -> void:
	dialogue_sequence_completed.emit(sequence_id, side)


# TextureRect 沿用当前设计框尺寸，背景裁切铺满，立绘和粉丝牌保留完整比例。
func _set_texture_rect(texture_rect: TextureRect, texture: Texture2D, stretch_mode: int) -> void:
	texture_rect.texture = texture
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = stretch_mode
	texture_rect.visible = texture != null


# PK 唯一值归 HitResolution，HUD 只将它映射为玩家占比和对手占比。
func refresh_pk(player_pk: float, current_tier: int) -> void:
	set_opponent_portrait_connected(current_tier > 0)
	var player_share: float = clampf(player_pk, 0.0, 1.0)
	_pk_progress.value = player_share
	_player_pk_label.text = "玩家 PK %.1f%%" % (player_share * 100.0)
	_opponent_pk_label.text = "对手 %.1f%%" % ((1.0 - player_share) * 100.0)
	_tier_label.text = "Tier %d" % current_tier


# 蓄力与阶段归 CombatAttack，HUD 使用公开读取结果提供可释放、飞行和硬直反馈。
func refresh_attack(progress: float, phase: int) -> void:
	var charge_progress: float = clampf(progress, 0.0, 1.0)
	_charge_progress.value = charge_progress
	match phase:
		AttackChargeInput.AttackPhase.PROJECTILE_FLIGHT:
			_charge_label.text = "飞行中"
		AttackChargeInput.AttackPhase.RECOVERY:
			_charge_label.text = "硬直中"
		_:
			_charge_label.text = "蓄满 100% · 松开发射" if charge_progress >= 1.0 else "蓄力 %d%%" % roundi(charge_progress * 100.0)


# 普通战斗完成及下一阶段等待提示由 Sandbox 生命周期组合方决定。
func show_battle_state(message: String) -> void:
	# 顶部状态区只有两行；消息内部换行统一显示为分隔符，保持反馈完整可读。
	_battle_state.text = message.replace("\n", " · ")


# 失败只切换可见界面；停止输入、回拉和生成继续由各状态拥有者处理。
func show_failure() -> void:
	_failure_overlay.show()
	_restart_button.grab_focus()


# 重开仅复位界面提示，各系统的本场状态由 Sandbox 分别初始化。
func reset_for_attempt() -> void:
	player_portrait_motion.reset_shot()
	opponent_portrait_motion.reset_shot()
	clear_dialogue_bubbles()
	player_portrait_motion.set_idle_strength(1.0)
	opponent_portrait_motion.set_idle_strength(1.0)
	set_opponent_portrait_connected(false)
	_failure_overlay.hide()
	show_battle_state("瞄准弹幕，蓄满后松开左键")
	refresh_attack(0.0, AttackChargeInput.AttackPhase.READY)
