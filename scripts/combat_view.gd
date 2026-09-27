extends Control

## Combat UI. Player hand shows card faces; opponent hand is backs + a count.
## Played cards briefly face-up in the center of the screen.
## Card backs are a charcoal/gold stand-in until designer PNGs arrive.

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
const DRAW_PILE_SIZE := Vector2(72, 100)
const DRAW_FLY_SEC := 0.28
const DISCARD_FLY_SEC := 0.30
const ARC_LIFT := 92.0
const FLY_STAGGER := 0.05
const MAX_FLYERS := 14
## Drop a texture here later and the procedural back is replaced.
const BACK_TEXTURE_PATH := "res://assets/cards/card_back.png"

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
@onready var choice_panel: PanelContainer = $ResponseOverlay/ChoicePanel
@onready var dodge_btn: Button = $ResponseOverlay/ChoicePanel/ChoiceRow/DodgeButton
@onready var hit_btn: Button = $ResponseOverlay/ChoicePanel/ChoiceRow/HitButton
@onready var player_draw_back: Control = $Root/HandRow/PlayerDraw/PlayerDrawBack
@onready var enemy_draw_back: Control = $Root/EnemyPanel/EnemyRow/EnemyDraw/EnemyDrawBack
@onready var player_draw_count: Label = $Root/HandRow/PlayerDraw/PlayerDrawBadge/PlayerDrawCount
@onready var enemy_draw_count: Label = $Root/EnemyPanel/EnemyRow/EnemyDraw/EnemyDrawCount
@onready var player_discard_art: TextureRect = $Root/HandRow/PlayerDiscard/PlayerDiscardSlot/PlayerDiscardArt
@onready var enemy_discard_art: TextureRect = $Root/EnemyPanel/EnemyRow/EnemyDiscard/EnemyDiscardSlot/EnemyDiscardArt
@onready var player_discard_count: Label = $Root/HandRow/PlayerDiscard/PlayerDiscardBadge/PlayerDiscardCount
@onready var enemy_discard_count: Label = $Root/EnemyPanel/EnemyRow/EnemyDiscard/EnemyDiscardCount
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
var _reveal_card: CardData
var _cards_in_reveal: Array[CardData] = []
var _discard_wait: Array[Dictionary] = []
var _back_tex: Texture2D

func _ready() -> void:
	discard_hint.visible = false
	response_overlay.visible = false
	reveal_group.visible = false
	if ResourceLoader.exists(BACK_TEXTURE_PATH):
		_back_tex = load(BACK_TEXTURE_PATH)
	btn_end.pressed.connect(_on_end_turn)
	dodge_btn.pressed.connect(_on_dodge)
	hit_btn.pressed.connect(_on_take_hit)
	_install_pile_backs()
	resized.connect(_center_reveal)
	resized.connect(_place_choice_panel)
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
	player_hp_lbl.text = "HP %d / %d" % [ctrl.player.hp, ctrl.player.max_hp]
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
		return
	var can_dodge := ctrl.player.find_first_of_type(CardData.CardType.DODGE) >= 0
	dodge_btn.disabled = not can_dodge
	btn_end.visible = false
	_place_choice_panel()

func _place_choice_panel() -> void:
	if choice_panel == null or hand_area == null:
		return
	var panel_size := Vector2(800, 240)
	choice_panel.size = panel_size
	var hand_top := hand_area.get_global_rect().position.y
	var x := (size.x - panel_size.x) * 0.5
	var y := hand_top - panel_size.y - 8.0
	if y < 48.0:
		y = maxf((size.y - panel_size.y) * 0.62, 48.0)
	choice_panel.global_position = Vector2(x, y)

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
	if ctrl == null:
		return
	var n := ctrl.enemy.hand.size()
	enemy_count_lbl.text = str(n)
	while enemy_backs.get_child_count() < n:
		enemy_backs.add_child(_make_card_back(Vector2(54, 76), "Opponent hand"))
	while enemy_backs.get_child_count() > n:
		var last := enemy_backs.get_child(enemy_backs.get_child_count() - 1)
		enemy_backs.remove_child(last)
		last.free()

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
	var gold := Color(0.78, 0.64, 0.32, 0.92)
	_add_frame(host, card_size, gold, 2.0)
	var cols := 4
	var rows := 5
	for i in range(1, cols):
		var line := ColorRect.new()
		line.color = gold
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x := card_size.x * float(i) / float(cols)
		line.position = Vector2(x, 4.0)
		line.size = Vector2(1.0, card_size.y - 8.0)
		host.add_child(line)
	for j in range(1, rows):
		var line := ColorRect.new()
		line.color = gold
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var y := card_size.y * float(j) / float(rows)
		line.position = Vector2(4.0, y)
		line.size = Vector2(card_size.x - 8.0, 1.0)
		host.add_child(line)
	return host

func _add_frame(host: Control, card_size: Vector2, color: Color, thickness: float) -> void:
	var top := ColorRect.new()
	top.color = color
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.position = Vector2.ZERO
	top.size = Vector2(card_size.x, thickness)
	host.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = color
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.position = Vector2(0, card_size.y - thickness)
	bottom.size = Vector2(card_size.x, thickness)
	host.add_child(bottom)
	var left := ColorRect.new()
	left.color = color
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.position = Vector2.ZERO
	left.size = Vector2(thickness, card_size.y)
	host.add_child(left)
	var right := ColorRect.new()
	right.color = color
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.position = Vector2(card_size.x - thickness, 0)
	right.size = Vector2(thickness, card_size.y)
	host.add_child(right)

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
	_cards_in_reveal.append(card)
	_reveal_queue.append({"card": card, "by_player": by_player})
	if not _reveal_playing:
		_play_next_reveal()

func _play_next_reveal() -> void:
	if _reveal_queue.is_empty():
		_reveal_playing = false
		_reveal_card = null
		reveal_group.visible = false
		reveal_group.scale = Vector2.ONE
		reveal_group.modulate = Color(1, 1, 1, 0)
		return
	_reveal_playing = true
	var item: Dictionary = _reveal_queue.pop_front()
	var card: CardData = item["card"]
	var by_player: bool = bool(item["by_player"])
	_reveal_card = card
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
	_reveal_tween.tween_callback(_on_reveal_finished)

func _on_reveal_finished() -> void:
	var finished := _reveal_card
	if finished != null:
		_cards_in_reveal.erase(finished)
		_flush_discard_flights(finished)
	_play_next_reveal()

func _install_pile_backs() -> void:
	_fill_back_stack(player_draw_back, DRAW_PILE_SIZE, "Draw pile")
	_fill_back_stack(enemy_draw_back, Vector2(56, 78), "Opponent draw pile")

func _fill_back_stack(host: Control, card_size: Vector2, tip: String) -> void:
	for i in 3:
		var back := _make_card_back(card_size, tip)
		back.position = Vector2(float(2 - i) * 4.0, float(2 - i) * 3.0)
		back.z_index = i
		host.add_child(back)

func _sync_piles() -> void:
	if ctrl == null:
		return
	player_draw_count.text = str(ctrl.player.deck.size())
	enemy_draw_count.text = str(ctrl.enemy.deck.size())
	_show_discard_top(player_discard_art, player_discard_count, ctrl.player.discard_pile)
	_show_discard_top(enemy_discard_art, enemy_discard_count, ctrl.enemy.discard_pile)

func _show_discard_top(art: TextureRect, count_lbl: Label, pile: Array) -> void:
	count_lbl.text = str(pile.size())
	if pile.is_empty():
		art.texture = null
		art.visible = false
		return
	var card: CardData = pile[pile.size() - 1]
	art.texture = card.get_art()
	art.visible = art.texture != null

func _on_cards_drawn(cards: Array, by_player: bool) -> void:
	_fly_draws(cards, by_player)

func _fly_draws(cards: Array, by_player: bool) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or cards.is_empty():
		return
	var origin_node := player_draw_back if by_player else enemy_draw_back
	var slot_box: Node = hand_box if by_player else enemy_backs
	var origin := _center_of(origin_node)
	if origin == Vector2.ZERO:
		await get_tree().process_frame
		origin = _center_of(origin_node)
	var n := cards.size()
	var slot_count := slot_box.get_child_count()
	var first := maxi(slot_count - n, 0)
	var delay := 0.0
	for i in n:
		var dest := _center_of(slot_box as Control)
		if first + i < slot_count:
			var slot := slot_box.get_child(first + i) as Control
			var slot_center := _center_of(slot)
			if slot_center != Vector2.ZERO:
				dest = slot_center
		var tex: Texture2D = null
		var card = cards[i]
		if by_player and card is CardData:
			tex = (card as CardData).get_art()
		_launch_arc(tex, origin, dest, delay, DRAW_FLY_SEC, 0.0)
		delay = minf(delay + FLY_STAGGER, 0.35)

func _on_card_discarded(card: CardData, by_player: bool) -> void:
	if card != null and _cards_in_reveal.has(card):
		_discard_wait.append({"card": card, "by_player": by_player})
		return
	_start_discard_flight(card, by_player, false)

func _flush_discard_flights(card: CardData) -> void:
	var keep: Array[Dictionary] = []
	for item in _discard_wait:
		if item["card"] == card:
			_start_discard_flight(item["card"], bool(item["by_player"]), true)
		else:
			keep.append(item)
	_discard_wait = keep

func _start_discard_flight(card: CardData, by_player: bool, from_reveal: bool) -> void:
	_fly_discard(card, by_player, from_reveal)

func _fly_discard(card: CardData, by_player: bool, from_reveal: bool) -> void:
	await get_tree().process_frame
	if not is_inside_tree() or card == null:
		return
	var origin := _center_of(reveal_group) if from_reveal else _center_of(hand_box if by_player else enemy_backs)
	var dest := _center_of(player_discard_art if by_player else enemy_discard_art)
	if dest == Vector2.ZERO:
		dest = _center_of(player_discard_art.get_parent() if by_player else enemy_discard_art.get_parent())
	if origin == Vector2.ZERO:
		origin = _center_of(hand_box if by_player else enemy_backs)
	var tex: Texture2D = card.get_art() if by_player else null
	var spin := randf_range(-8.0, 8.0)
	_launch_arc(tex, origin, dest, 0.0, DISCARD_FLY_SEC, spin)

func _center_of(c: Control) -> Vector2:
	if c == null:
		return Vector2.ZERO
	var rect := c.get_global_rect()
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	return rect.get_center()

func _launch_arc(tex: Texture2D, origin: Vector2, dest: Vector2, delay: float, duration: float, spin_deg: float) -> void:
	if origin == Vector2.ZERO or dest == Vector2.ZERO:
		return
	_trim_flyers()
	var card_size := (HAND_CARD_SIZE * 0.62) if tex != null else Vector2(52, 72)
	var node := Control.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.custom_minimum_size = card_size
	node.size = card_size
	node.pivot_offset = card_size * 0.5
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.grow_horizontal = Control.GROW_DIRECTION_BOTH
		art.grow_vertical = Control.GROW_DIRECTION_BOTH
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.add_child(art)
	else:
		node.add_child(_make_card_back(card_size))
	fly_layer.add_child(node)
	node.global_position = origin - card_size * 0.5
	var control := (origin + dest) * 0.5 + Vector2(0, -ARC_LIFT)
	var tw := node.create_tween()
	if delay > 0.0:
		node.modulate.a = 0.0
		tw.tween_interval(delay)
		tw.tween_property(node, "modulate:a", 1.0, 0.04)
	tw.tween_method(_arc_step.bind(node, origin, control, dest, card_size, spin_deg), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(node, "modulate:a", 0.0, 0.05)
	tw.tween_callback(node.queue_free)

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
		oldest.queue_free()
		fly_layer.remove_child(oldest)

func _clear_flyers() -> void:
	for c in fly_layer.get_children():
		c.queue_free()
