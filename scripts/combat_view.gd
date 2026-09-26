extends Control

## Combat UI. Player hand shows card faces; opponent hand is backs + a count.
## Played cards briefly face-up in the center of the screen.

const HAND_CARD_SIZE := Vector2(96, 134)
## Center reveal is 1.6–1.8× a hand card. 1.7 sits in the middle of that range.
const REVEAL_SIZE_MULT := 1.7
const FRAME_BORDER := 6.0
const REVEAL_IN_SEC := 0.15
const REVEAL_HOLD_SEC := 0.8
const REVEAL_OUT_SEC := 0.2
const REVEAL_START_SCALE := 0.92
const LABEL_H := 22.0
const LABEL_GAP := 8.0
const BACK_SIZE := Vector2(58, 82)

@onready var enemy_name_lbl: Label = $Root/EnemyPanel/EnemyName
@onready var enemy_hp_lbl: Label = $Root/EnemyPanel/EnemyHP
@onready var enemy_backs: HBoxContainer = $Root/EnemyPanel/EnemyHand/Backs
@onready var enemy_count_lbl: Label = $Root/EnemyPanel/EnemyHand/CountBadge/CountLabel
@onready var player_name_lbl: Label = $Root/PlayerPanel/PlayerName
@onready var player_hp_lbl: Label = $Root/PlayerPanel/PlayerHP
@onready var phase_lbl: Label = $Root/PhaseLabel
@onready var log_lbl: Label = $Root/LogPanel/LogText
@onready var hand_box: HBoxContainer = $Root/HandArea/HandBox
@onready var btn_end: Button = $Root/Actions/EndTurn
@onready var btn_dodge: Button = $Root/Actions/Dodge
@onready var btn_take: Button = $Root/Actions/TakeHit
@onready var discard_hint: Label = $Root/DiscardHint
@onready var reveal_layer: Control = $PlayReveal
@onready var reveal_group: Control = $PlayReveal/RevealGroup
@onready var reveal_frame: Panel = $PlayReveal/RevealGroup/Frame
@onready var reveal_art: TextureRect = $PlayReveal/RevealGroup/Frame/Art
@onready var reveal_label: Label = $PlayReveal/RevealGroup/PlayLabel

var ctrl: CombatController
var log_lines: PackedStringArray = []
var ai_timer: float = 0.0
const AI_STEP_DELAY := 0.55
var discard_mode: bool = false
var _reveal_queue: Array[Dictionary] = []
var _reveal_playing: bool = false
var _reveal_tween: Tween

func _ready() -> void:
	btn_dodge.visible = false
	btn_take.visible = false
	discard_hint.visible = false
	reveal_group.visible = false
	btn_end.pressed.connect(_on_end_turn)
	btn_dodge.pressed.connect(_on_dodge)
	btn_take.pressed.connect(_on_take_hit)
	resized.connect(_center_reveal)
	_configure_reveal_layout()
	call_deferred("_center_reveal")
	_start_fight()

func _start_fight() -> void:
	var node := RunManager.get_current_node()
	var p := Combatant.new()
	p.display_name = "You"
	p.is_player = true
	p.max_hp = RunManager.player_max_hp
	p.hp = RunManager.player_hp
	p.deck = RunManager.build_deck_from_ids(RunManager.deck_card_ids)

	var e := Combatant.new()
	e.display_name = str(node.get("enemy_name", "Enemy"))
	e.is_player = false
	e.max_hp = int(node.get("enemy_max_hp", 4))
	e.hp = e.max_hp
	e.deck = RunManager.make_enemy_deck(int(node.get("enemy_deck_size", 12)))

	ctrl = CombatController.new()
	ctrl.setup(p, e, RunManager.HAND_LIMIT_BASE)
	ctrl.log_message.connect(_on_log)
	ctrl.state_changed.connect(_refresh)
	ctrl.card_played.connect(_on_card_played)
	ctrl.combat_ended.connect(_on_combat_ended)
	ctrl.awaiting_dodge.connect(_on_await_dodge)
	ctrl.awaiting_player_discard.connect(_on_await_discard)
	ctrl.start_combat(RunManager.extra_draw_at_start)
	_refresh()

func _process(delta: float) -> void:
	if ctrl == null or ctrl.phase == CombatController.Phase.ENDED:
		return
	# Let the center reveal finish before the opponent plays the next card.
	if _reveal_playing:
		return
	if ctrl.phase == CombatController.Phase.PLAY and not ctrl.player_turn:
		ai_timer += delta
		if ai_timer >= AI_STEP_DELAY:
			ai_timer = 0.0
			ctrl.run_ai_turn_step()

func _on_log(text: String) -> void:
	log_lines.append(text)
	if log_lines.size() > 12:
		log_lines = log_lines.slice(log_lines.size() - 12)
	log_lbl.text = "\n".join(log_lines)

func _refresh() -> void:
	if ctrl == null:
		return
	enemy_name_lbl.text = ctrl.enemy.display_name
	enemy_hp_lbl.text = "HP %d / %d" % [ctrl.enemy.hp, ctrl.enemy.max_hp]
	_sync_enemy_hand()
	player_name_lbl.text = ctrl.player.display_name
	player_hp_lbl.text = "HP %d / %d  |  Deck: %d  |  Discard: %d" % [
		ctrl.player.hp, ctrl.player.max_hp, ctrl.player.deck.size(), ctrl.player.discard_pile.size()
	]
	var phase_names := {
		CombatController.Phase.DRAW: "Draw",
		CombatController.Phase.PLAY: "Play",
		CombatController.Phase.AWAIT_DODGE: "Respond to 殺",
		CombatController.Phase.DISCARD: "Discard",
		CombatController.Phase.ENDED: "Ended",
	}
	var whose := "Your turn" if ctrl.player_turn else "%s's turn" % ctrl.enemy.display_name
	phase_lbl.text = "%s — %s" % [whose, phase_names.get(ctrl.phase, "?")]

	btn_end.visible = ctrl.phase == CombatController.Phase.PLAY and ctrl.player_turn
	btn_end.disabled = not btn_end.visible
	discard_mode = ctrl.phase == CombatController.Phase.DISCARD and ctrl.player_turn
	discard_hint.visible = discard_mode
	if discard_mode:
		discard_hint.text = "Click cards to discard until hand ≤ %d" % ctrl.hand_limit

	_rebuild_hand()

func _rebuild_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	if ctrl == null:
		return
	for i in range(ctrl.player.hand.size()):
		var card: CardData = ctrl.player.hand[i]
		var tex: Texture2D = card.get_art()
		var btn: BaseButton
		if tex != null:
			var tb := TextureButton.new()
			tb.texture_normal = tex
			tb.ignore_texture_size = true
			tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_COVERED
			tb.custom_minimum_size = HAND_CARD_SIZE
			tb.tooltip_text = "%s — %s" % [card.short_label(), card.description]
			btn = tb
		else:
			var fb := Button.new()
			fb.custom_minimum_size = HAND_CARD_SIZE
			fb.text = "%s\n%s" % [card.name_en, card.name_zh]
			fb.tooltip_text = card.description
			fb.modulate = card.color.lightened(0.35)
			btn = fb
		var idx := i
		btn.pressed.connect(_on_card_pressed.bind(idx))
		# Disable play if not allowed (unless discard mode)
		if discard_mode:
			btn.disabled = false
		elif ctrl.phase == CombatController.Phase.AWAIT_DODGE:
			btn.disabled = true
		elif not (ctrl.phase == CombatController.Phase.PLAY and ctrl.player_turn and ctrl.can_play_card(i)):
			btn.disabled = true
		if btn.disabled and tex != null:
			btn.modulate = Color(0.55, 0.55, 0.55, 0.85)
		hand_box.add_child(btn)

func _on_card_pressed(index: int) -> void:
	if discard_mode:
		ctrl.player_discard_at(index)
		return
	ctrl.play_player_card(index)

func _on_end_turn() -> void:
	ctrl.end_player_turn()

func _on_await_dodge(_attacker_is_player: bool) -> void:
	btn_dodge.visible = true
	btn_take.visible = true
	btn_end.visible = false
	# Enable dodge button only if has 閃
	btn_dodge.disabled = ctrl.player.find_first_of_type(CardData.CardType.DODGE) < 0

func _on_dodge() -> void:
	btn_dodge.visible = false
	btn_take.visible = false
	ctrl.respond_dodge(true)

func _on_take_hit() -> void:
	btn_dodge.visible = false
	btn_take.visible = false
	ctrl.respond_dodge(false)

func _on_await_discard(_excess: int) -> void:
	discard_mode = true
	_refresh()

func _on_combat_ended(won: bool) -> void:
	RunManager.last_combat_won = won
	# Persist HP after fight
	RunManager.player_hp = ctrl.player.hp
	btn_end.visible = false
	btn_dodge.visible = false
	btn_take.visible = false
	await get_tree().create_timer(1.2).timeout
	if won:
		var node := RunManager.get_current_node()
		if node.get("is_boss", false):
			# Boss win → reward then win screen via advance
			get_tree().change_scene_to_file("res://scenes/reward.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/reward.tscn")
	else:
		RunManager.lose_run()
		get_tree().change_scene_to_file("res://scenes/result.tscn")

func _sync_enemy_hand() -> void:
	if ctrl == null:
		return
	var n := ctrl.enemy.hand.size()
	enemy_count_lbl.text = str(n)
	while enemy_backs.get_child_count() < n:
		enemy_backs.add_child(_make_card_back())
	while enemy_backs.get_child_count() > n:
		var last := enemy_backs.get_child(enemy_backs.get_child_count() - 1)
		enemy_backs.remove_child(last)
		last.free()

func _make_card_back() -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = BACK_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.tooltip_text = "Opponent hand"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.46, 0.08, 0.1)
	style.border_color = Color(0.84, 0.66, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.shadow_color = Color(0, 0, 0, 0.4)
	style.shadow_size = 3
	panel.add_theme_stylebox_override("panel", style)

	var inner := Panel.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.position = Vector2(6, 6)
	inner.size = BACK_SIZE - Vector2(12, 12)
	var inner_style := StyleBoxFlat.new()
	inner_style.bg_color = Color(0.36, 0.06, 0.08)
	inner_style.border_color = Color(0.72, 0.54, 0.24, 0.9)
	inner_style.set_border_width_all(1)
	inner_style.set_corner_radius_all(3)
	inner.add_theme_stylebox_override("panel", inner_style)
	panel.add_child(inner)

	var cx := BACK_SIZE.x * 0.5
	var cy := BACK_SIZE.y * 0.5
	var diamond := Polygon2D.new()
	diamond.color = Color(0.9, 0.75, 0.38)
	diamond.polygon = PackedVector2Array([
		Vector2(cx, cy - 14.0),
		Vector2(cx + 10.0, cy),
		Vector2(cx, cy + 14.0),
		Vector2(cx - 10.0, cy),
	])
	panel.add_child(diamond)
	return panel

func _configure_reveal_layout() -> void:
	var card_size := HAND_CARD_SIZE * REVEAL_SIZE_MULT
	var frame_size := card_size + Vector2(FRAME_BORDER, FRAME_BORDER) * 2.0
	reveal_frame.position = Vector2.ZERO
	reveal_frame.size = frame_size
	reveal_art.position = Vector2(FRAME_BORDER, FRAME_BORDER)
	reveal_art.size = card_size
	reveal_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reveal_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reveal_label.position = Vector2(0, -(LABEL_H + LABEL_GAP))
	reveal_label.size = Vector2(frame_size.x, LABEL_H)
	reveal_group.size = frame_size
	reveal_group.pivot_offset = frame_size * 0.5
	_center_reveal()

func _center_reveal() -> void:
	if reveal_group == null or reveal_layer == null:
		return
	var frame_size := reveal_group.size
	if frame_size == Vector2.ZERO:
		return
	reveal_group.pivot_offset = frame_size * 0.5
	reveal_group.position = (reveal_layer.size - frame_size) * 0.5

func _on_card_played(card: CardData, by_player: bool) -> void:
	_reveal_queue.append({"card": card, "by_player": by_player})
	if not _reveal_playing:
		_play_next_reveal()

func _play_next_reveal() -> void:
	if _reveal_queue.is_empty():
		_reveal_playing = false
		reveal_group.visible = false
		reveal_group.scale = Vector2.ONE
		reveal_group.modulate = Color(1, 1, 1, 0)
		return
	_reveal_playing = true
	var item: Dictionary = _reveal_queue.pop_front()
	var card: CardData = item["card"]
	var by_player: bool = bool(item["by_player"])
	reveal_label.visible = not by_player
	reveal_art.texture = card.get_art()
	_center_reveal()
	reveal_group.visible = true
	reveal_group.modulate = Color(1, 1, 1, 0)
	reveal_group.scale = Vector2(REVEAL_START_SCALE, REVEAL_START_SCALE)
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.tween_property(reveal_group, "modulate:a", 1.0, REVEAL_IN_SEC)
	_reveal_tween.parallel().tween_property(reveal_group, "scale", Vector2.ONE, REVEAL_IN_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_interval(REVEAL_HOLD_SEC)
	_reveal_tween.tween_property(reveal_group, "modulate:a", 0.0, REVEAL_OUT_SEC)
	_reveal_tween.tween_callback(_play_next_reveal)
