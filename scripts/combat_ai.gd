## Simple enemy AI — same card rules as the player, no specialties.
class_name CombatAI
extends RefCounted

## Choose a card index to play this turn, or -1 to pass / end turn.
## Priority: Heal if low HP → Attack if has 殺 → Draw Two → Dismantle → else pass.
static func choose_play(me: Combatant, opponent: Combatant) -> int:
	# Heal if hurt and have 桃
	if me.hp < me.max_hp:
		var heal_i := me.find_first_of_type(CardData.CardType.HEAL)
		if heal_i >= 0:
			return heal_i

	# Attack if we have 殺
	var atk_i := me.find_first_of_type(CardData.CardType.ATTACK)
	if atk_i >= 0:
		return atk_i

	# Draw two if hand is thin
	if me.hand.size() <= 3:
		var draw_i := me.find_first_of_type(CardData.CardType.DRAW)
		if draw_i >= 0:
			return draw_i

	# Dismantle if opponent has cards
	if not opponent.hand.is_empty():
		var dis_i := me.find_first_of_type(CardData.CardType.DISCARD)
		if dis_i >= 0:
			return dis_i

	# Fallback: draw if available
	var draw2 := me.find_first_of_type(CardData.CardType.DRAW)
	if draw2 >= 0:
		return draw2

	return -1

## Decide whether to respond to 殺 with 閃 (always if available).
static func should_dodge(me: Combatant) -> bool:
	return me.find_first_of_type(CardData.CardType.DODGE) >= 0
