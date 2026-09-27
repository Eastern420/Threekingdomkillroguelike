## Turn-based combat controller for one fight.
## Phases: draw → play (player or AI) → discard → next turn.
## Identical rules for both sides. No character specialties.
class_name CombatController
extends RefCounted

signal log_message(text: String)
signal state_changed
signal combat_ended(player_won: bool)
signal awaiting_dodge(attacker_is_player: bool)
signal awaiting_player_discard(excess: int)
## A card was played from hand (either side), including reactive 閃.
signal card_played(card: CardData, by_player: bool)
## Cards moved from a combatant's deck into their hand.
signal cards_drawn(cards: Array, by_player: bool)
## A card entered a combatant's discard pile (play, dodge, or forced discard).
signal card_discarded(card: CardData, by_player: bool)

enum Phase {
	DRAW,
	PLAY,
	AWAIT_DODGE,
	DISCARD,
	ENDED,
}

var player: Combatant
var enemy: Combatant
var phase: Phase = Phase.DRAW
var player_turn: bool = true
var hand_limit: int = 5
## Inspired by classic table: at most one 殺 per turn (both sides).
var sha_used_this_turn: bool = false
var pending_attack_from_player: bool = false

func setup(p: Combatant, e: Combatant, limit: int = 5) -> void:
	player = p
	enemy = e
	hand_limit = limit
	phase = Phase.DRAW
	player_turn = true
	sha_used_this_turn = false

func start_combat(extra_draw: int = 0) -> void:
	player.shuffle_deck()
	enemy.shuffle_deck()
	var opening_player := player.draw_cards(4 + extra_draw)
	var opening_enemy := enemy.draw_cards(4)
	_note_draw(player, opening_player)
	_note_draw(enemy, opening_enemy)
	_log("%s vs %s — fight!" % [player.display_name, enemy.display_name])
	_begin_turn()

func _begin_turn() -> void:
	phase = Phase.DRAW
	sha_used_this_turn = false
	var actor := _actor()
	var drawn := actor.draw_cards(2)
	_note_draw(actor, drawn)
	_log("%s draws %d." % [actor.display_name, drawn.size()])
	phase = Phase.PLAY
	state_changed.emit()

func _note_draw(who: Combatant, drawn: Array) -> void:
	if drawn.is_empty():
		return
	cards_drawn.emit(drawn, who.is_player)

func _bury(who: Combatant, card: CardData) -> void:
	if card == null:
		return
	who.discard_pile.append(card)
	card_discarded.emit(card, who.is_player)

func _note_discard(who: Combatant, card: CardData) -> void:
	if card == null:
		return
	card_discarded.emit(card, who.is_player)

func _actor() -> Combatant:
	return player if player_turn else enemy

func _other() -> Combatant:
	return enemy if player_turn else player

func can_play_card(index: int) -> bool:
	if phase != Phase.PLAY or not player_turn:
		return false
	if index < 0 or index >= player.hand.size():
		return false
	return _can_actor_play(player, player.hand[index])

func _can_actor_play(actor: Combatant, card: CardData) -> bool:
	if card.type == CardData.CardType.DODGE:
		return false
	if card.type == CardData.CardType.ATTACK and sha_used_this_turn:
		return false
	if card.type == CardData.CardType.HEAL and actor.hp >= actor.max_hp:
		return false
	var tgt := enemy if actor.is_player else player
	if card.type == CardData.CardType.DISCARD and tgt.hand.is_empty():
		return false
	return true

func play_player_card(index: int) -> bool:
	if not can_play_card(index):
		return false
	var card: CardData = player.hand[index]
	player.hand.remove_at(index)
	_resolve_card(card, player, enemy, true)
	state_changed.emit()
	return true

func end_player_turn() -> void:
	if phase != Phase.PLAY or not player_turn:
		return
	_enter_discard_phase()

func _enter_discard_phase() -> void:
	phase = Phase.DISCARD
	var actor := _actor()
	var excess := actor.hand.size() - hand_limit
	if excess <= 0:
		_finish_discard()
		return
	if actor.is_player:
		_log("Discard down to %d (pick %d)." % [hand_limit, excess])
		awaiting_player_discard.emit(excess)
		state_changed.emit()
	else:
		var dropped := actor.discard_down_to(hand_limit)
		for c in dropped:
			_note_discard(actor, c)
		if dropped.size() > 0:
			_log("%s discards %d." % [actor.display_name, dropped.size()])
		_finish_discard()

func player_discard_at(index: int) -> void:
	if phase != Phase.DISCARD or not player_turn:
		return
	if index < 0 or index >= player.hand.size():
		return
	var c := player.discard_from_hand(index)
	if c:
		_note_discard(player, c)
		_log("You discard %s." % c.short_label())
	if player.hand.size() <= hand_limit:
		_finish_discard()
	else:
		state_changed.emit()

func _finish_discard() -> void:
	if not player.is_alive() or not enemy.is_alive():
		_check_end()
		return
	player_turn = not player_turn
	_begin_turn()

func run_ai_turn_step() -> void:
	if phase != Phase.PLAY or player_turn:
		return
	var choice := _ai_choose_legal()
	if choice < 0:
		_log("%s ends turn." % enemy.display_name)
		_enter_discard_phase()
		return
	var card: CardData = enemy.hand[choice]
	enemy.hand.remove_at(choice)
	_resolve_card(card, enemy, player, false)
	state_changed.emit()

func _ai_choose_legal() -> int:
	## Same priorities as CombatAI, but only among currently legal plays.
	var me := enemy
	var opp := player
	if me.hp < me.max_hp:
		var heal_i := _find_legal(CardData.CardType.HEAL)
		if heal_i >= 0:
			return heal_i
	var atk_i := _find_legal(CardData.CardType.ATTACK)
	if atk_i >= 0:
		return atk_i
	if me.hand.size() <= 3:
		var draw_i := _find_legal(CardData.CardType.DRAW)
		if draw_i >= 0:
			return draw_i
	if not opp.hand.is_empty():
		var dis_i := _find_legal(CardData.CardType.DISCARD)
		if dis_i >= 0:
			return dis_i
	var draw2 := _find_legal(CardData.CardType.DRAW)
	if draw2 >= 0:
		return draw2
	return -1

func _find_legal(t: CardData.CardType) -> int:
	for i in range(enemy.hand.size()):
		var c: CardData = enemy.hand[i]
		if c.type == t and _can_actor_play(enemy, c):
			return i
	return -1

func _resolve_card(card: CardData, src: Combatant, tgt: Combatant, from_player: bool) -> void:
	card_played.emit(card, from_player)
	_log("%s plays %s." % [src.display_name, card.display_name()])
	match card.type:
		CardData.CardType.ATTACK:
			sha_used_this_turn = true
			_bury(src, card)
			_start_attack(src, tgt, from_player)
			return
		CardData.CardType.HEAL:
			src.hp = mini(src.hp + 1, src.max_hp)
			_bury(src, card)
			_log("%s heals to %d/%d." % [src.display_name, src.hp, src.max_hp])
		CardData.CardType.DRAW:
			_bury(src, card)
			var d := src.draw_cards(2)
			_note_draw(src, d)
			_log("%s draws %d (无中生有)." % [src.display_name, d.size()])
		CardData.CardType.DISCARD:
			_bury(src, card)
			var removed := tgt.discard_random_from_hand()
			if removed:
				_note_discard(tgt, removed)
				_log("%s loses %s (过河拆桥)." % [tgt.display_name, removed.short_label()])
			else:
				_log("%s has no cards to discard." % tgt.display_name)
		CardData.CardType.DODGE:
			_bury(src, card)
		_:
			_bury(src, card)
	_check_end()

func _start_attack(src: Combatant, tgt: Combatant, from_player: bool) -> void:
	pending_attack_from_player = from_player
	if tgt.is_player:
		phase = Phase.AWAIT_DODGE
		_log("殺 incoming — play 閃 or take the hit.")
		awaiting_dodge.emit(from_player)
		state_changed.emit()
		return
	else:
		if CombatAI.should_dodge(tgt):
			var di := tgt.find_first_of_type(CardData.CardType.DODGE)
			var dodge_card := tgt.hand[di]
			tgt.hand.remove_at(di)
			card_played.emit(dodge_card, false)
			_bury(tgt, dodge_card)
			_log("%s plays 閃 — cancelled!" % tgt.display_name)
		else:
			_apply_damage(tgt, 1)
	_check_end()

func respond_dodge(use_dodge: bool) -> void:
	if phase != Phase.AWAIT_DODGE:
		return
	var tgt := player
	if use_dodge:
		var di := tgt.find_first_of_type(CardData.CardType.DODGE)
		if di >= 0:
			var dodge_card := tgt.hand[di]
			tgt.hand.remove_at(di)
			card_played.emit(dodge_card, true)
			_bury(tgt, dodge_card)
			_log("You play 閃 — cancelled!")
		else:
			_apply_damage(tgt, 1)
	else:
		_apply_damage(tgt, 1)
	phase = Phase.PLAY
	state_changed.emit()
	_check_end()

func _apply_damage(tgt: Combatant, amount: int) -> void:
	tgt.hp -= amount
	_log("%s takes %d damage (%d/%d)." % [tgt.display_name, amount, maxi(tgt.hp, 0), tgt.max_hp])
	if tgt.hp <= 0:
		tgt.hp = 0

func _check_end() -> void:
	if phase == Phase.ENDED:
		return
	if not player.is_alive():
		phase = Phase.ENDED
		_log("You fall…")
		combat_ended.emit(false)
		state_changed.emit()
	elif not enemy.is_alive():
		phase = Phase.ENDED
		_log("%s defeated!" % enemy.display_name)
		combat_ended.emit(true)
		state_changed.emit()

func _log(text: String) -> void:
	log_message.emit(text)
