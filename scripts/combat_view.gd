extends Control

## Combat UI. Player hand shows card faces; opponent hand is backs + a count.
## Played cards briefly face-up in the center, then fly into the discard pile.
## Textures: res://assets/ui/ (see COMBAT_UI_SPEC.md).

const HAND_CARD_SIZE := Vector2(96, 134)
const REVEAL_SIZE_MULT := 1.7
const FRAME_BORDER := 6.0
const REVEAL_IN_SEC := 0.15
const REVEAL_HOLD_SEC := 0.8
const REVEAL_OUT_SEC := 0.2
const REVEAL_START_SCALE := 0.92
const LABEL_H := 22.0
const LABEL_GAP := 8.0
const DRAW_PILE_SIZE := Vector2(72, 100)
const ENEMY_BACK_SIZE := Vector2(54, 76)
const DRAW_FLY_SEC := 0.28
const DRAW_FADE_SEC := 0.05
const DISCARD_FLY_SEC := 0.30
const ARC_LIFT := 92.0
const FLY_STAGGER := 0.05
const MAX_FLYERS := 24
const CHOICE_SIZE := Vector2(800, 240)
const CHOICE_BTN := Vector2(360, 192)
const UI_BACK := "res://assets/ui/card_back.png"

@onready var enemy_name_lbl: Label = $Root/EnemyPanel/EnemyName
@onready var enemy_hp_lbl: Label = $Root/EnemyPanel/EnemyHP
@onready var enemy_backs: HBoxContainer = $Root/EnemyPanel/EnemyRow/EnemyHand/Backs
@onready var enemy_count_lbl: Label = $Root/EnemyPanel/EnemyRow/EnemyHand/CountBadge/CountLabel
@onready var player_name_lbl: Label = $Root/PlayerPanel/PlayerName
@onready var player_hp_lbl: Label = $Root/PlayerPanel/PlayerHP
@onready var phase_lbl: Label = $Root/PhaseLabel
@onready var log_lbl: Label = $Root/LogPanel/LogText
@onready var hand_area: ScrollContainer = $Root/HandRow/HandArea
@onready var hand_box: HBoxContainer = $Root/HandRow/HandArea/HandBox
@onready var btn_end: Button = $Root/Actions/EndTurn
@onready var discard_hint: Label = $Root/DiscardHint
@onready var response_overlay: Control = $ResponseOverlay
@onready var choice_panel: Control = $ResponseOverlay/ChoicePanel
@onready var dodge_host: Control = $ResponseOverlay/ChoicePanel/ChoiceRow/DodgeHost
@onready var dodge_rim: Panel = $ResponseOverlay/ChoicePanel/ChoiceRow/DodgeHost/DodgeRim
@onready var dodge_btn: TextureButton = $ResponseOverlay/ChoicePanel/ChoiceRow/DodgeHost/DodgeButton
@onready var hit_host: Control = $ResponseOverlay/ChoicePanel/ChoiceRow/HitHost
@onready var hit_rim: Panel = $ResponseOverlay/ChoicePanel/ChoiceRow/HitHost/HitRim
@onready var hit_btn: TextureButton = $ResponseOverlay/ChoicePanel/ChoiceRow/HitHost/HitButton
@onready var player_draw: Control = $PlayerDraw
@onready var draw_marker: TextureRect = $PlayerDraw/DrawMarker
@onready var draw_stack: Control = $PlayerDraw/DrawStack
@onready var player_draw_count: Label = $PlayerDraw/PlayerDrawBadge/PlayerDrawCount
@onready var player_discard: Control = $PlayerDiscard
@onready var discard_marker: TextureRect = $PlayerDiscard/DiscardMarker
@onready var discard_art: TextureRect = $PlayerDiscard/DiscardArt
@onready var player_discard_count: Label = $PlayerDiscard/PlayerDiscardBadge/PlayerDiscardCount
@onready var fly_layer: Control = $FlyLayer
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
var _reveal_token: int = 0
var _reveal_serial: int = 0
var _hold_next_discard: bool = false
var _hold_discard_token: int = 0
var _discard_wait: Array[Dictionary] = []
var _back_tex: Texture2D
var _player_order: Array[CardData] = []
var _enemy_order: Array[CardData] = []
var _player_hidden: Array[bool] = []
var _enemy_hidden: Array[bool] = []
var _player_nodes: Array[Control] = []
var _enemy_nodes: Array[Control] = []
var _draw_flights: Array[Dictionary] = []
var _shown_discard_count: int = 0
var _dodge_pointer: bool = false
var _dodge_focus: bool = false
var _hit_pointer: bool = false
var _hit_focus: bool = false

func _ready() -> void:
	discard_hint.visible = false
	response_overlay.visible = false
	reveal_group.visible = false
	_back_tex = load(UI_BACK) as Texture2D
	btn_end.pressed.connect(_on_end_turn)
	dodge_btn.pressed.connect(_on_dodge)
	hit_btn.pressed.connect(_on_take_hit)
	_bind_choice_buttons()
	_install_draw_stack()
	resized.connect(_layout_hud)
	_configure_reveal_layout()
	call_deferred("_layout_hud")
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
	ctrl.cards_drawn.connect(_on_cards_drawn)
	ctrl.card_discarded.connect(_on_card_discarded)
	ctrl.combat_ended.connect(_on_combat_ended)
	ctrl.awaiting_dodge.connect(_on_await_dodge)
	ctrl.awaiting_player_discard.connect(_on_await_discard)
	ctrl.start_combat(RunManager.extra_draw_at_start)
	_refresh()

func _process(delta: float) -> void:
	if ctrl == null or ctrl.phase == CombatController.Phase.ENDED:
		return
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
	_align_tracking(false)
	_sync_enemy_hand()
	player_name_lbl.text = ctrl.player.display_name
	player_hp_lbl.text = "HP %d / %d" % [ctrl.player.hp, ctrl.player.max_hp]
	_align_tracking(true)
	_sync_piles()
	_sync_response_choice()
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
	_clear_children(hand_box)
	_player_nodes.clear()
	if ctrl == null:
		return
	var hand := ctrl.player.hand
	for i in range(hand.size()):
		var hidden := i < _player_hidden.size() and _player_hidden[i]
		if hidden:
			var placeholder := Control.new()
			placeholder.custom_minimum_size = HAND_CARD_SIZE
			placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
			placeholder.modulate = Color(1, 1, 1, 0)
			hand_box.add_child(placeholder)
			_player_nodes.append(placeholder)
			continue
		var card: CardData = hand[i]
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
		if discard_mode:
			btn.disabled = false
		elif ctrl.phase == CombatController.Phase.AWAIT_DODGE:
			btn.disabled = true
		elif not (ctrl.phase == CombatController.Phase.PLAY and ctrl.player_turn and ctrl.can_play_card(i)):
			btn.disabled = true
		if btn.disabled and tex != null:
			btn.modulate = Color(0.55, 0.55, 0.55, 0.85)
		hand_box.add_child(btn)
		_player_nodes.append(btn)

func _on_card_pressed(index: int) -> void:
	if discard_mode:
		ctrl.player_discard_at(index)
		return
	ctrl.play_player_card(index)

func _on_end_turn() -> void:
	ctrl.end_player_turn()

func _on_await_dodge(_attacker_is_player: bool) -> void:
	_sync_response_choice()

func _on_dodge() -> void:
	if dodge_btn.disabled:
		return
	response_overlay.visible = false
	ctrl.respond_dodge(true)

func _on_take_hit() -> void:
	response_overlay.visible = false
	ctrl.respond_dodge(false)

func _sync_response_choice() -> void:
	if ctrl == null:
		return
	var responding := ctrl.phase == CombatController.Phase.AWAIT_DODGE
	response_overlay.visible = responding
	if not responding:
		_dodge_pointer = false
		_dodge_focus = false
		_hit_pointer = false
		_hit_focus = false
		_paint_choice(true)
		_paint_choice(false)
		return
	var can_dodge := ctrl.player.find_first_of_type(CardData.CardType.DODGE) >= 0
	dodge_btn.disabled = not can_dodge
	if dodge_btn.disabled:
		_dodge_pointer = false
		_dodge_focus = false
	btn_end.visible = false
	_paint_choice(true)
	_paint_choice(false)
	_place_choice_panel()

func _bind_choice_buttons() -> void:
	dodge_host.pivot_offset = CHOICE_BTN * 0.5
	hit_host.pivot_offset = CHOICE_BTN * 0.5
	dodge_btn.mouse_entered.connect(func() -> void: _set_choice_pointer(true, true))
	dodge_btn.mouse_exited.connect(func() -> void: _set_choice_pointer(true, false))
	dodge_btn.focus_entered.connect(func() -> void: _set_choice_focus(true, true))
	dodge_btn.focus_exited.connect(func() -> void: _set_choice_focus(true, false))
	hit_btn.mouse_entered.connect(func() -> void: _set_choice_pointer(false, true))
	hit_btn.mouse_exited.connect(func() -> void: _set_choice_pointer(false, false))
	hit_btn.focus_entered.connect(func() -> void: _set_choice_focus(false, true))
	hit_btn.focus_exited.connect(func() -> void: _set_choice_focus(false, false))

func _set_choice_pointer(is_dodge: bool, hot: bool) -> void:
	if is_dodge:
		_dodge_pointer = hot
	else:
		_hit_pointer = hot
	_paint_choice(is_dodge)

func _set_choice_focus(is_dodge: bool, hot: bool) -> void:
	if is_dodge:
		_dodge_focus = hot
	else:
		_hit_focus = hot
	_paint_choice(is_dodge)

func _paint_choice(is_dodge: bool) -> void:
	var btn := dodge_btn if is_dodge else hit_btn
	var host := dodge_host if is_dodge else hit_host
	var rim := dodge_rim if is_dodge else hit_rim
	var hot: bool = (_dodge_pointer or _dodge_focus) if is_dodge else (_hit_pointer or _hit_focus)
	if btn.disabled:
		host.scale = Vector2.ONE
		rim.visible = false
		btn.modulate = Color(0.5, 0.5, 0.5, 1)
		return
	var show := hot
	host.scale = Vector2(1.05, 1.05) if show else Vector2.ONE
	rim.visible = show
	btn.modulate = Color(1.15, 1.08, 0.82) if show else Color.WHITE

func _place_choice_panel() -> void:
	if choice_panel == null:
		return
	choice_panel.size = CHOICE_SIZE
	var top_left := Vector2((size.x - CHOICE_SIZE.x) * 0.5, size.y * 0.52 - CHOICE_SIZE.y * 0.5)
	choice_panel.position = top_left

func _layout_hud() -> void:
	_layout_piles()
	_place_choice_panel()
	_center_reveal()

func _layout_piles() -> void:
	if player_draw == null or player_discard == null:
		return
	player_draw.position = Vector2(48, size.y - 220)
	player_draw.size = DRAW_PILE_SIZE
	player_discard.position = Vector2(size.x - 48 - DRAW_PILE_SIZE.x, size.y - 220)
	player_discard.size = DRAW_PILE_SIZE

func _on_await_discard(_excess: int) -> void:
	discard_mode = true
	_refresh()

func _on_combat_ended(won: bool) -> void:
	RunManager.last_combat_won = won
	RunManager.player_hp = ctrl.player.hp
	btn_end.visible = false
	response_overlay.visible = false
	_clear_flyers()
	await get_tree().create_timer(1.2).timeout
	if won:
		get_tree().change_scene_to_file("res://scenes/reward.tscn")
	else:
		RunManager.lose_run()
		get_tree().change_scene_to_file("res://scenes/result.tscn")

func _sync_enemy_hand() -> void:
	_clear_children(enemy_backs)
	_enemy_nodes.clear()
	if ctrl == null:
		return
	var shown := 0
	for i in range(ctrl.enemy.hand.size()):
		var back := _make_card_back(ENEMY_BACK_SIZE, "Opponent hand")
		var hidden := i < _enemy_hidden.size() and _enemy_hidden[i]
		if hidden:
			back.modulate = Color(1, 1, 1, 0)
		else:
			shown += 1
		enemy_backs.add_child(back)
		_enemy_nodes.append(back)
	enemy_count_lbl.text = str(shown)

func _make_card_back(card_size: Vector2 = DRAW_PILE_SIZE, tip: String = "") -> Control:
	var host := Control.new()
	host.custom_minimum_size = card_size
	host.size = card_size
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tip != "":
		host.tooltip_text = tip
	if _back_tex != null:
		var art := TextureRect.new()
		art.texture = _back_tex
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.grow_horizontal = Control.GROW_DIRECTION_BOTH
		art.grow_vertical = Control.GROW_DIRECTION_BOTH
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		host.add_child(art)
		return host
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.16, 0.17)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)
	return host

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
	_reveal_serial += 1
	var token := _reveal_serial
	_hold_next_discard = true
	_hold_discard_token = token
	_reveal_queue.append({"card": card, "by_player": by_player, "token": token})
	if not _reveal_playing:
		_play_next_reveal()

func _play_next_reveal() -> void:
	if _reveal_queue.is_empty():
		_reveal_playing = false
		_reveal_token = 0
		reveal_group.visible = false
		reveal_group.scale = Vector2.ONE
		reveal_group.modulate = Color(1, 1, 1, 0)
		return
	_reveal_playing = true
	var item: Dictionary = _reveal_queue.pop_front()
	var card: CardData = item["card"]
	var by_player: bool = bool(item["by_player"])
	_reveal_token = int(item["token"])
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
	_reveal_tween.tween_callback(_on_reveal_hold_ended)
	_reveal_tween.tween_property(reveal_group, "modulate:a", 0.0, REVEAL_OUT_SEC)
	_reveal_tween.tween_callback(_on_reveal_finished)

func _on_reveal_hold_ended() -> void:
	_flush_discard_flights(_reveal_token)

func _on_reveal_finished() -> void:
	_play_next_reveal()

func _install_draw_stack() -> void:
	_clear_children(draw_stack)
	for i in 3:
		var back := _make_card_back(DRAW_PILE_SIZE, "Draw pile")
		back.position = Vector2(float(i - 2) * 4.0, float(i - 2) * 3.0)
		back.z_index = i
		draw_stack.add_child(back)

func _sync_piles() -> void:
	if ctrl == null:
		return
	var deck_n := ctrl.player.deck.size()
	player_draw_count.text = str(deck_n)
	var deck_empty := deck_n <= 0
	draw_stack.visible = not deck_empty
	draw_marker.visible = deck_empty
	var piled := _discard_data_count()
	if piled == 0:
		_reset_discard_visual()
	elif piled < _shown_discard_count:
		_shown_discard_count = piled
		player_discard_count.text = str(piled)

func _discard_data_count() -> int:
	if ctrl == null:
		return 0
	return ctrl.player.discard_pile.size() + ctrl.enemy.discard_pile.size()

func _reset_discard_visual() -> void:
	_shown_discard_count = 0
	player_discard_count.text = "0"
	discard_art.texture = null
	discard_art.visible = false
	discard_marker.visible = true

func _show_discard_landed(card: CardData) -> void:
	if _discard_data_count() <= 0:
		_reset_discard_visual()
		return
	_shown_discard_count = mini(_shown_discard_count + 1, _discard_data_count())
	player_discard_count.text = str(_shown_discard_count)
	var tex: Texture2D = card.get_art() if card != null else null
	if tex != null:
		discard_art.texture = tex
		discard_art.visible = true
		discard_marker.visible = false

func _on_cards_drawn(cards: Array, by_player: bool) -> void:
	if cards.is_empty() or ctrl == null:
		return
	var hand: Array = ctrl.player.hand if by_player else ctrl.enemy.hand
	var start := hand.size() - cards.size()
	if start < 0:
		start = 0
	_align_tracking(by_player)
	var hidden: Array[bool] = _player_hidden if by_player else _enemy_hidden
	var indices: Array[int] = []
	for i in range(cards.size()):
		var idx := start + i
		if idx >= 0 and idx < hidden.size():
			hidden[idx] = true
			indices.append(idx)
	_fly_draws(by_player, indices)

func _fly_draws(by_player: bool, indices: Array[int]) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or indices.is_empty():
		for idx in indices:
			_reveal_drawn_index(by_player, idx)
		return
	var origin := _player_draw_origin() if by_player else _enemy_draw_origin()
	var box: Control = hand_box if by_player else enemy_backs
	var card_size := HAND_CARD_SIZE if by_player else ENEMY_BACK_SIZE
	var from_scale := DRAW_PILE_SIZE / card_size if by_player else Vector2(0.82, 0.82)
	var delay := 0.0
	for idx in indices:
		var dest := _center_of(box)
		if idx >= 0 and idx < box.get_child_count():
			var slot_center := _center_of(box.get_child(idx) as Control)
			if slot_center != Vector2.ZERO:
				dest = slot_center
		var ticket := {"by_player": by_player, "index": idx}
		_draw_flights.append(ticket)
		_launch_flyer(_back_tex, origin, dest, {
			"duration": DRAW_FLY_SEC,
			"delay": delay,
			"fade_in": DRAW_FADE_SEC,
			"size": card_size,
			"from_scale": from_scale,
			"to_scale": Vector2.ONE,
			"trans": Tween.TRANS_CUBIC,
			"on_done": _on_draw_landed.bind(ticket),
		})
		delay = minf(delay + FLY_STAGGER, 0.35)

func _on_draw_landed(ticket: Dictionary) -> void:
	_draw_flights.erase(ticket)
	_reveal_drawn_index(bool(ticket["by_player"]), int(ticket["index"]))

func _reveal_drawn_index(by_player: bool, index: int) -> void:
	if index >= 0:
		var hidden: Array[bool] = _player_hidden if by_player else _enemy_hidden
		if index < hidden.size():
			hidden[index] = false
	if by_player:
		_rebuild_hand()
	else:
		_sync_enemy_hand()

func _player_draw_origin() -> Vector2:
	var origin := _center_of(draw_stack if draw_stack.visible else player_draw)
	if origin == Vector2.ZERO:
		origin = _center_of(player_draw)
	return origin

func _enemy_draw_origin() -> Vector2:
	var rect := get_global_rect()
	return rect.position + Vector2(size.x * 0.5, -20.0)

func _on_card_discarded(card: CardData, by_player: bool) -> void:
	var hand_origin := _take_lost_card_origin(by_player)
	if _hold_next_discard:
		_hold_next_discard = false
		_discard_wait.append({
			"card": card,
			"by_player": by_player,
			"token": _hold_discard_token,
		})
		return
	_start_discard_flight(card, by_player, false, hand_origin)

func _flush_discard_flights(token: int) -> void:
	var keep: Array[Dictionary] = []
	for item in _discard_wait:
		if int(item["token"]) == token:
			_start_discard_flight(item["card"], bool(item["by_player"]), true, Vector2.ZERO)
		else:
			keep.append(item)
	_discard_wait = keep

func _start_discard_flight(card: CardData, by_player: bool, from_reveal: bool, hand_origin: Vector2) -> void:
	var origin := _center_of(reveal_group) if from_reveal else hand_origin
	if origin == Vector2.ZERO:
		origin = _center_of(hand_box if by_player else enemy_backs)
	var dest := _center_of(player_discard)
	var tex: Texture2D = _back_tex
	var card_size := ENEMY_BACK_SIZE
	if from_reveal or by_player:
		tex = card.get_art() if card != null else _back_tex
		card_size = (HAND_CARD_SIZE * REVEAL_SIZE_MULT) if from_reveal else HAND_CARD_SIZE
	if tex == null:
		tex = _back_tex
		card_size = DRAW_PILE_SIZE
	var to_scale := Vector2.ONE
	if card_size.x > 0.0 and card_size.y > 0.0:
		to_scale = DRAW_PILE_SIZE / card_size
	var spin := randf_range(-8.0, 8.0)
	_launch_flyer(tex, origin, dest, {
		"duration": DISCARD_FLY_SEC,
		"spin": spin,
		"size": card_size,
		"from_scale": Vector2.ONE,
		"to_scale": to_scale,
		"trans": Tween.TRANS_CUBIC,
		"z": 25,
		"on_done": _show_discard_landed.bind(card),
	})

func _take_lost_card_origin(by_player: bool) -> Vector2:
	var order: Array[CardData] = _player_order if by_player else _enemy_order
	var nodes: Array[Control] = _player_nodes if by_player else _enemy_nodes
	var now: Array = ctrl.player.hand if by_player else ctrl.enemy.hand
	var box: Control = hand_box if by_player else enemy_backs
	var idx := _first_removed_index(order, now)
	var origin := _center_of(box)
	if idx >= 0 and idx < nodes.size() and is_instance_valid(nodes[idx]):
		var slot_center := _center_of(nodes[idx])
		if slot_center != Vector2.ZERO:
			origin = slot_center
	if idx >= 0:
		_drop_tracked_index(by_player, idx)
	return origin

func _first_removed_index(old: Array, now: Array) -> int:
	if old.size() != now.size() + 1:
		return -1
	for i in now.size():
		if old[i] != now[i]:
			return i
	return now.size()

func _drop_tracked_index(by_player: bool, idx: int) -> void:
	var order: Array[CardData] = _player_order if by_player else _enemy_order
	var hidden: Array[bool] = _player_hidden if by_player else _enemy_hidden
	var nodes: Array[Control] = _player_nodes if by_player else _enemy_nodes
	if idx < order.size():
		order.remove_at(idx)
	if idx < hidden.size():
		hidden.remove_at(idx)
	if idx < nodes.size():
		nodes.remove_at(idx)
	for flight in _draw_flights:
		if bool(flight["by_player"]) != by_player:
			continue
		var flight_index := int(flight["index"])
		if flight_index > idx:
			flight["index"] = flight_index - 1
		elif flight_index == idx:
			flight["index"] = -1

func _align_tracking(by_player: bool) -> void:
	var order: Array[CardData] = _player_order if by_player else _enemy_order
	var hidden: Array[bool] = _player_hidden if by_player else _enemy_hidden
	var hand: Array = ctrl.player.hand if by_player else ctrl.enemy.hand
	if order.size() == hand.size():
		var same := true
		for i in hand.size():
			if order[i] != hand[i]:
				same = false
				break
		if same:
			while hidden.size() < hand.size():
				hidden.append(false)
			while hidden.size() > hand.size():
				hidden.pop_back()
			return
	var new_order: Array[CardData] = []
	var new_hidden: Array[bool] = []
	var used: Array[bool] = []
	used.resize(order.size())
	used.fill(false)
	for c in hand:
		var card := c as CardData
		var found := -1
		for j in order.size():
			if not used[j] and order[j] == card:
				found = j
				used[j] = true
				break
		new_order.append(card)
		if found >= 0 and found < hidden.size():
			new_hidden.append(hidden[found])
		else:
			new_hidden.append(false)
	if by_player:
		_player_order = new_order
		_player_hidden = new_hidden
	else:
		_enemy_order = new_order
		_enemy_hidden = new_hidden

func _center_of(c: Control) -> Vector2:
	if c == null or not is_instance_valid(c):
		return Vector2.ZERO
	var rect := c.get_global_rect()
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	return rect.get_center()

func _launch_flyer(tex: Texture2D, origin: Vector2, dest: Vector2, opts: Dictionary) -> void:
	var on_done: Callable = opts.get("on_done", Callable())
	if origin == Vector2.ZERO or dest == Vector2.ZERO:
		if on_done.is_valid():
			on_done.call_deferred()
		return
	_trim_flyers()
	var duration: float = float(opts.get("duration", DRAW_FLY_SEC))
	var delay: float = float(opts.get("delay", 0.0))
	var fade_in: float = float(opts.get("fade_in", 0.0))
	var spin: float = float(opts.get("spin", 0.0))
	var card_size: Vector2 = opts.get("size", HAND_CARD_SIZE)
	var from_scale: Vector2 = opts.get("from_scale", Vector2.ONE)
	var to_scale: Vector2 = opts.get("to_scale", Vector2.ONE)
	var trans: int = int(opts.get("trans", Tween.TRANS_CUBIC))
	var z: int = int(opts.get("z", 0))
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.custom_minimum_size = card_size
	node.size = card_size
	node.pivot_offset = card_size * 0.5
	node.z_index = z
	node.scale = from_scale
	var art := TextureRect.new()
	art.texture = tex if tex != null else _back_tex
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.grow_horizontal = Control.GROW_DIRECTION_BOTH
	art.grow_vertical = Control.GROW_DIRECTION_BOTH
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.add_child(art)
	fly_layer.add_child(node)
	node.global_position = origin - card_size * 0.5
	if fade_in > 0.0:
		node.modulate.a = 0.0
	var control := (origin + dest) * 0.5 + Vector2(0, -ARC_LIFT)
	var finished := {"done": false}
	var finish := func() -> void:
		if bool(finished["done"]):
			return
		finished["done"] = true
		if on_done.is_valid():
			on_done.call()
		if is_instance_valid(node):
			node.queue_free()
	node.tree_exiting.connect(finish)
	var tw := node.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	if fade_in > 0.0:
		tw.tween_property(node, "modulate:a", 1.0, fade_in)
	tw.tween_property(node, "scale", to_scale, duration)
	tw.tween_method(_arc_step.bind(node, origin, control, dest, card_size, spin), 0.0, 1.0, duration) \
		.set_trans(trans).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(finish)

func _arc_step(t: float, node: Control, start: Vector2, control: Vector2, end: Vector2, card_size: Vector2, spin_deg: float) -> void:
	if not is_instance_valid(node):
		return
	var p := _quad(start, control, end, t)
	node.global_position = p - card_size * 0.5
	node.rotation = deg_to_rad(spin_deg) * t

func _quad(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c

func _trim_flyers() -> void:
	while fly_layer.get_child_count() >= MAX_FLYERS:
		var oldest := fly_layer.get_child(0)
		fly_layer.remove_child(oldest)
		oldest.queue_free()

func _clear_flyers() -> void:
	for c in fly_layer.get_children():
		fly_layer.remove_child(c)
		c.queue_free()

func _clear_children(node: Node) -> void:
	if node == null:
		return
	for c in node.get_children():
		node.remove_child(c)
		c.free()
