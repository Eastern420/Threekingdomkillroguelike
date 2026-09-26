extends Control

## Combat UI: ColorRect / Label / Button — playable prototype.

@onready var enemy_name_lbl: Label = $Root/EnemyPanel/EnemyName
@onready var enemy_hp_lbl: Label = $Root/EnemyPanel/EnemyHP
@onready var enemy_hand_lbl: Label = $Root/EnemyPanel/EnemyHand
@onready var player_name_lbl: Label = $Root/PlayerPanel/PlayerName
@onready var player_hp_lbl: Label = $Root/PlayerPanel/PlayerHP
@onready var phase_lbl: Label = $Root/PhaseLabel
@onready var log_lbl: Label = $Root/LogPanel/LogText
@onready var hand_box: HBoxContainer = $Root/HandArea/HandBox
@onready var btn_end: Button = $Root/Actions/EndTurn
@onready var btn_dodge: Button = $Root/Actions/Dodge
@onready var btn_take: Button = $Root/Actions/TakeHit
@onready var discard_hint: Label = $Root/DiscardHint

var ctrl: CombatController
var log_lines: PackedStringArray = []
var ai_timer: float = 0.0
const AI_STEP_DELAY := 0.55
var discard_mode: bool = false

func _ready() -> void:
	btn_dodge.visible = false
	btn_take.visible = false
	discard_hint.visible = false
	btn_end.pressed.connect(_on_end_turn)
	btn_dodge.pressed.connect(_on_dodge)
	btn_take.pressed.connect(_on_take_hit)
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
	ctrl.combat_ended.connect(_on_combat_ended)
	ctrl.awaiting_dodge.connect(_on_await_dodge)
	ctrl.awaiting_player_discard.connect(_on_await_discard)
	ctrl.start_combat(RunManager.extra_draw_at_start)
	_refresh()

func _process(delta: float) -> void:
	if ctrl == null or ctrl.phase == CombatController.Phase.ENDED:
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
	enemy_hand_lbl.text = "Hand: %d  |  Deck: %d" % [ctrl.enemy.hand.size(), ctrl.enemy.deck.size()]
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
			tb.custom_minimum_size = Vector2(96, 134)
			tb.tooltip_text = "%s — %s" % [card.short_label(), card.description]
			btn = tb
		else:
			var fb := Button.new()
			fb.custom_minimum_size = Vector2(96, 134)
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
