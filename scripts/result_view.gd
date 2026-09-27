extends Control

@onready var title: Label = $Center/VBox/Title
@onready var detail: Label = $Center/VBox/Detail

func _ready() -> void:
	if RunManager.last_combat_won and not RunManager.run_active:
		title.text = "You Win!"
		detail.text = "Boss defeated. Prototype run complete — same rules, no specialties."
	elif RunManager.last_combat_won:
		title.text = "Victory"
		detail.text = RunManager.last_message if RunManager.last_message != "" else "Fight won."
	else:
		title.text = "Defeat"
		detail.text = "You were defeated. Same rules for both sides — try another run."

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
