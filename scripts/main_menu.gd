extends Control

@onready var title_label: Label = $Center/VBox/Title
@onready var subtitle: Label = $Center/VBox/Subtitle

func _ready() -> void:
	title_label.text = "三國殺 Roguelike"
	subtitle.text = "Prototype — basic deck only, no character specialties"

func _on_start_pressed() -> void:
	RunManager.start_new_run()
	get_tree().change_scene_to_file("res://scenes/map.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
