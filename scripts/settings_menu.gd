class_name SettingsMenu extends CanvasLayer

# M6 Settings menu — audio часть. 4 ползунка для bus'ов (Master/Music/SFX/Ambient).
# Значения 0..1 linear, persist'ятся через AudioSettings autoload.
#
# Dual mode:
#   - Standalone scene: открывается из main_menu через change_scene_to_file. На BACK —
#     change_scene_to_file(MAIN_MENU). is_overlay = false.
#   - Overlay: instantiate'ится pause_menu'ом и add_child'ится. На BACK — queue_free().
#     is_overlay = true. Esc внутри settings закрывает только settings, pause panel
#     остаётся под ним (мы set_input_as_handled() чтобы pause не словил тот же event).
#
# Mode определяется по флагу is_overlay, который устанавливается caller'ом ДО add_child
# (или не устанавливается, тогда default false → standalone).

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var is_overlay: bool = false

@onready var master_slider: HSlider = $Panel/Center/VBox/MasterRow/Slider
@onready var music_slider: HSlider = $Panel/Center/VBox/MusicRow/Slider
@onready var sfx_slider: HSlider = $Panel/Center/VBox/SfxRow/Slider
@onready var ambient_slider: HSlider = $Panel/Center/VBox/AmbientRow/Slider

@onready var master_value: Label = $Panel/Center/VBox/MasterRow/Value
@onready var music_value: Label = $Panel/Center/VBox/MusicRow/Value
@onready var sfx_value: Label = $Panel/Center/VBox/SfxRow/Value
@onready var ambient_value: Label = $Panel/Center/VBox/AmbientRow/Value

@onready var back_btn: Button = $Panel/Center/VBox/BackButton


func _ready() -> void:
	# ALWAYS — overlay поверх pause тоже должен реагировать на Esc / mouse при
	# tree.paused = true.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Init slider values из AudioSettings.
	master_slider.value = AudioSettings.get_volume("Master")
	music_slider.value = AudioSettings.get_volume("Music")
	sfx_slider.value = AudioSettings.get_volume("SFX")
	ambient_slider.value = AudioSettings.get_volume("Ambient")

	_update_value_label(master_value, master_slider.value)
	_update_value_label(music_value, music_slider.value)
	_update_value_label(sfx_value, sfx_slider.value)
	_update_value_label(ambient_value, ambient_slider.value)

	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	ambient_slider.value_changed.connect(_on_ambient_changed)

	back_btn.pressed.connect(_on_back)

	# Mouse visible (overlay из pause — pause уже visible'ит, но fortify), focus
	# на первом slider для клавиатурного доступа.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	master_slider.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	# Esc внутри settings = BACK. layer=50 (выше pause layer=40) → ловим event ДО
	# pause_menu'a чтобы избежать двойного закрытия (settings → pause → game).
	# Ордер важен: set_input_as_handled() ДО _on_back(), иначе в non-overlay режиме
	# change_scene_to_file фриз'ит ноду, get_viewport() становится null → краш.
	if event.is_action_pressed("mouse_capture_exit"):
		get_viewport().set_input_as_handled()
		_on_back()


func _on_master_changed(v: float) -> void:
	AudioSettings.set_volume("Master", v)
	_update_value_label(master_value, v)


func _on_music_changed(v: float) -> void:
	AudioSettings.set_volume("Music", v)
	_update_value_label(music_value, v)


func _on_sfx_changed(v: float) -> void:
	AudioSettings.set_volume("SFX", v)
	_update_value_label(sfx_value, v)


func _on_ambient_changed(v: float) -> void:
	AudioSettings.set_volume("Ambient", v)
	_update_value_label(ambient_value, v)


func _update_value_label(label: Label, linear: float) -> void:
	label.text = "%d%%" % int(round(linear * 100.0))


func _on_back() -> void:
	if is_overlay:
		# Caller (pause_menu) подписан на tree_exited — он сам вернёт panel.visible.
		queue_free()
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
