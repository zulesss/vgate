class_name CreditsScreen extends Control

# M5 credits — attribution для CC-BY 4.0 ассетов (music). Для CC0 ассетов
# attribution не требуется юридически, но листим — uplift и good practice.
# Back button — возврат в main menu.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var back_btn: Button = $Center/VBox/BackButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	back_btn.pressed.connect(_on_back)
	back_btn.grab_focus()


func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
