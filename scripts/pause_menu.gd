class_name PauseMenu extends CanvasLayer

# M5 pause overlay. Esc toggle, 4 buttons. process_mode=ALWAYS чтобы оставаться
# отзывчивым при tree.paused = true. mouse_mode переключается VISIBLE/CAPTURED.
#
# Disable: pause НЕ поднимается во время death sequence (DeathScreen уже владеет
# UI mode'ом, две модальности сломают логику) и в main_menu (там pause не имеет
# смысла). Гард: VelocityGate.is_alive — единственный signal жив или нет.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

@onready var panel: Control = $Panel
@onready var resume_btn: Button = $Panel/Center/VBox/ResumeButton
@onready var restart_btn: Button = $Panel/Center/VBox/RestartButton
@onready var menu_btn: Button = $Panel/Center/VBox/MainMenuButton
@onready var quit_btn: Button = $Panel/Center/VBox/QuitButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	resume_btn.pressed.connect(_on_resume)
	restart_btn.pressed.connect(_on_restart)
	menu_btn.pressed.connect(_on_main_menu)
	quit_btn.pressed.connect(_on_quit)


func _unhandled_input(event: InputEvent) -> void:
	# Esc — единственный pause-toggle. mouse_capture_exit действие (Esc) уже
	# существует в InputMap — но player.gd использует его для cursor release.
	# Здесь reuse того же события, ловим _unhandled_input ДО player'а через
	# CanvasLayer ordering (layer=40 высокий → handled first).
	if event.is_action_pressed("mouse_capture_exit"):
		# Не открываем pause если игрок мёртв (death-screen активен).
		if not VelocityGate.is_alive:
			return
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	if panel.visible:
		_close()
	else:
		_open()


func _open() -> void:
	panel.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_btn.grab_focus()


func _close() -> void:
	panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resume() -> void:
	_close()


func _on_restart() -> void:
	# Восстанавливаем un-pause + CAPTURED перед emit'ом — RunLoop reset'ит state
	# и Player.gd начнёт читать input уже на следующем кадре.
	panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Через тот же canonical path что DeathScreen: emit signal, RunLoop reset'ит
	# player + VelocityGate (последний emit'ит run_started). Прямой VelocityGate.reset_for_run()
	# не вернул бы player'а на spawn-position.
	Events.run_restart_requested.emit()


func _on_main_menu() -> void:
	# Возврат в main menu. Tree должен быть un-paused чтобы change_scene успел
	# обработать (paused tree блокирует scene transitions в некоторых edge case'ах).
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_quit() -> void:
	get_tree().quit()
