## Combatant state used by both player and AI enemy (identical rules).
class_name Combatant
extends RefCounted

var display_name: String = ""
var max_hp: int = 4
var hp: int = 4
var hand: Array[CardData] = []
var deck: Array[CardData] = []
var discard_pile: Array[CardData] = []
var is_player: bool = false

func is_alive() -> bool:
	return hp > 0

func shuffle_deck() -> void:
	deck.shuffle()

func draw_cards(n: int) -> Array[CardData]:
	var drawn: Array[CardData] = []
	for i in range(n):
		if deck.is_empty():
			_recycle_discard()
		if deck.is_empty():
			break
		var c: CardData = deck.pop_back()
		hand.append(c)
		drawn.append(c)
	return drawn

func _recycle_discard() -> void:
	if discard_pile.is_empty():
		return
	deck.append_array(discard_pile)
	discard_pile.clear()
	shuffle_deck()

func discard_from_hand(index: int) -> CardData:
	if index < 0 or index >= hand.size():
		return null
	var c: CardData = hand[index]
	hand.remove_at(index)
	discard_pile.append(c)
	return c

func discard_random_from_hand() -> CardData:
	if hand.is_empty():
		return null
	return discard_from_hand(randi() % hand.size())

func remove_card_instance(card: CardData) -> bool:
	var idx := hand.find(card)
	if idx < 0:
		return false
	hand.remove_at(idx)
	discard_pile.append(card)
	return true

func find_first_of_type(t: CardData.CardType) -> int:
	for i in range(hand.size()):
		if hand[i].type == t:
			return i
	return -1

func count_of_type(t: CardData.CardType) -> int:
	var n := 0
	for c in hand:
		if c.type == t:
			n += 1
	return n

func discard_down_to(limit: int) -> Array[CardData]:
	## Prefer discarding DODGE when over limit, then extras — simple heuristic for AI;
	## for player, combat UI asks them to pick.
	var dropped: Array[CardData] = []
	while hand.size() > limit:
		var idx := find_first_of_type(CardData.CardType.DODGE)
		if idx < 0:
			idx = hand.size() - 1
		dropped.append(discard_from_hand(idx))
	return dropped
