## Data-driven card definition (Resource).
## Used by combat for both player and enemies — no character specialties.
class_name CardData
extends Resource

enum CardType {
	ATTACK,   ## 殺 / ATK — deal damage; can be dodged by 閃
	DODGE,    ## 閃 / DODGE — reactive dodge against 殺
	HEAL,     ## 桃 / HEAL — restore 1 HP (cannot exceed max HP)
	DISCARD,  ## 过河拆桥 / BREAK — discard one random card from opponent hand
	DRAW,     ## 无中生有 — draw 2 cards
}

@export var id: String = ""
@export var name_zh: String = ""
@export var name_en: String = ""
@export var description: String = ""
@export var type: CardType = CardType.ATTACK
@export var color: Color = Color(0.75, 0.2, 0.2)
## Portrait art (vertical card texture). Optional — UI falls back to tinted label button.
@export var art: Texture2D

func display_name() -> String:
	return "%s (%s)" % [name_zh, name_en]

func short_label() -> String:
	return name_en if name_en != "" else name_zh

## Resolve art even if the .tres ExtResource failed to import yet (editor first open).
func get_art() -> Texture2D:
	if art != null:
		return art
	return null
