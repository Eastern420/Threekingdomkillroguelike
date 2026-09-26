extends Control

@onready var status_label: Label = $Margin/VBox/Status
@onready var nodes_box: VBoxContainer = $Margin/VBox/Nodes
@onready var hint: Label = $Margin/VBox/Hint

func _ready() -> void:
	_refresh()

func _refresh() -> void:
	for c in nodes_box.get_children():
		c.queue_free()
	status_label.text = "HP %d/%d  |  Deck %d  |  Extra draw +%d" % [
		RunManager.player_hp, RunManager.player_max_hp,
		RunManager.deck_card_ids.size(), RunManager.extra_draw_at_start
	]
	for i in range(RunManager.map_nodes.size()):
		var node: Dictionary = RunManager.map_nodes[i]
		var row := HBoxContainer.new()
		var lbl := Label.new()
		var mark := "✓" if node.get("cleared", false) else ("►" if i == RunManager.current_node_index else "·")
		var kind := "BOSS" if node.get("is_boss", false) else "Fight"
		lbl.text = "%s  [%s] %s — %s (HP %d)" % [
			mark, kind, node.get("label", "?"), node.get("enemy_name", "?"), node.get("enemy_max_hp", 0)
		]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if i == RunManager.current_node_index and not node.get("cleared", false):
			var btn := Button.new()
			btn.text = "Enter Combat"
			btn.pressed.connect(_on_enter_combat)
			row.add_child(btn)
		nodes_box.add_child(row)
	hint.text = "Clear fights left-to-right. Rewards appear after each win."

func _on_enter_combat() -> void:
	get_tree().change_scene_to_file("res://scenes/combat.tscn")
