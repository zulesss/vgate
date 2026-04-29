class_name MainMenu extends Control

# M5 main menu. Простой [START] / [QUIT] (опц. [CREDITS] из PKG-F).
# Settings меню — M6, не здесь. Mode select — M11. UI скейл и шрифт — пока default
# Godot, M5 PKG-F навешает theme'у scifi_minimal.

const ARENA_SCENE := "res://scenes/main.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"
const SETTINGS_SCENE := "res://scenes/settings_menu.tscn"

@onready var start_btn: Button = $Center/VBox/StartButton
@onready var settings_btn: Button = $Center/VBox/SettingsButton
@onready var credits_btn: Button = $Center/VBox/CreditsButton
@onready var quit_btn: Button = $Center/VBox/QuitButton


func _ready() -> void:
	# Cursor visible на меню — игрок мышью кликает кнопки. Player.tscn _ready()
	# при старте арены вернёт CAPTURED. Между сценами state mouse_mode не
	# наследуется автоматически — set'им явно.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	start_btn.pressed.connect(_on_start)
	settings_btn.pressed.connect(_on_settings)
	credits_btn.pressed.connect(_on_credits)
	quit_btn.pressed.connect(_on_quit)
	start_btn.grab_focus()


func _on_start() -> void:
	get_tree().change_scene_to_file(ARENA_SCENE)


func _on_settings() -> void:
	# Standalone scene: settings_menu.gd._on_back() вернёт назад в main menu
	# через change_scene_to_file. is_overlay по умолчанию false.
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_credits() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)


func _on_quit() -> void:
	get_tree().quit()
