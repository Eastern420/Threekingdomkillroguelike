extends Control

## Between-fight rewards — NOT character abilities.
## Choices: max HP, heal, extra draw, add a card to deck.

@onready var title: Label = $Margin/VBox/Title
@onready var choices_box: VBoxContainer = $Margin/VBox/Choices
@onready var status: Label = $Margin/VBox/Status

var _options: Array[Dictionary] = []

func _ready() -> void:
	title.text = "Victory — choose a reward"
	status.text = "HP %d/%d  |  Deck %d" % [
		RunManager.player_hp, RunManager.player_max_hp, RunManager.deck_card_ids.size()
	]
	_build_options()
	_render()

func _build_options() -> void:
	_options = [
		{"id": "max_hp", "label": "+1 Max HP (and heal 1)"},
		{"id": "heal", "label": "Heal 2 HP"},
		{"id": "draw", "label": "+1 card drawn at start of each combat"},
		{"id": "add_sha", "label": "Add ATK (殺) to your deck"},
		{"id": "add_tao", "label": "Add HEAL (桃) to your deck"},
		{"id": "add_wuzhong", "label": "Add DRAW (无中生有) to your deck"},
	]
	_options.shuffle()
	_options = _options.slice(0, 3)

func _render() -> void:
	for c in choices_box.get_children():
		c.queue_free()
	for opt in _options:
		var btn := Button.new()
		btn.text = str(opt["label"])
		var oid: String = str(opt["id"])
		btn.pressed.connect(_on_pick.bind(oid))
		choices_box.add_child(btn)

func _on_pick(opt_id: String) -> void:
	match opt_id:
		"max_hp":
			RunManager.bump_max_hp(1)
		"heal":
			RunManager.heal_between_fights(2)
		"draw":
			RunManager.add_extra_draw(1)
		"add_sha":
			RunManager.add_card_to_deck("sha")
		"add_tao":
			RunManager.add_card_to_deck("tao")
		"add_wuzhong":
			RunManager.add_card_to_deck("wuzhong")
	var next := RunManager.advance_after_reward()
	if next == "win":
		get_tree().change_scene_to_file("res://scenes/result.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/map.tscn")
