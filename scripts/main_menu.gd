class_name MainMenu extends Control

# M5 main menu (M13 expanded): [НОВАЯ ИГРА] / [ПРОДОЛЖИТЬ] / [НАСТРОЙКИ] / [АВТОРЫ] / [ВЫХОД].
# M13 split START into two buttons:
#   - НОВАЯ ИГРА — wipes campaign progress, starts from Plac.
#   - ПРОДОЛЖИТЬ — resumes from highest_unlocked. Если все 3 пройдены — открывает
#     level_select. Если progress нет — fallback на new game (one-button feel).
# Кнопка ПРОДОЛЖИТЬ disabled visually когда no progress.

const ARENA_SCENE := "res://scenes/main.tscn"
const CREDITS_SCENE := "res://scenes/credits.tscn"
const SETTINGS_SCENE := "res://scenes/settings_menu.tscn"
const INTRO_SPLASH_SCENE := "res://scenes/intro_splash.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/level_select.tscn"

@onready var new_game_btn: Button = $Center/VBox/NewGameButton
@onready var continue_btn: Button = $Center/VBox/ContinueButton
@onready var settings_btn: Button = $Center/VBox/SettingsButton
@onready var credits_btn: Button = $Center/VBox/CreditsButton
@onready var quit_btn: Button = $Center/VBox/QuitButton


func _ready() -> void:
	# Cursor visible на меню — игрок мышью кликает кнопки. Player.tscn _ready()
	# при старте арены вернёт CAPTURED. Между сценами state mouse_mode не
	# наследуется автоматически — set'им явно.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Возврат в меню из gameplay (через pause → MAIN MENU или через credits)
	# может оставить музыку/heartbeat играющими — autoload'ы переживают смену сцены.
	# Глушим явно, чтобы меню было тихим.
	MusicDirector.stop_all()
	Sfx.stop_all_loops()
	# Velocity Gate в dormant state — иначе drain в меню → player_died через ~8с.
	VelocityGate.end_run()
	new_game_btn.pressed.connect(_on_new_game_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	settings_btn.pressed.connect(_on_settings)
	credits_btn.pressed.connect(_on_credits)
	quit_btn.pressed.connect(_on_quit)
	# ПРОДОЛЖИТЬ disabled (grayed) если нет save'нутого progress'а — visual signal
	# "сначала пройди что-нибудь". Focus на ПРОДОЛЖИТЬ если progress есть (returning
	# player'у быстрее), иначе на НОВАЯ ИГРА (fresh start).
	continue_btn.disabled = not CampaignProgress.has_progress()
	if CampaignProgress.has_progress():
		continue_btn.grab_focus()
	else:
		new_game_btn.grab_focus()


func _on_new_game_pressed() -> void:
	# M13: новая кампания — wipe campaign progress (но не high_scores), reset
	# LevelSequence на Plac. Best scores сохраняются — игрок не теряет их при
	# рестарте кампании.
	CampaignProgress.reset()
	LevelSequence.reset()
	IntroState.target_scene = ARENA_SCENE
	get_tree().change_scene_to_file(INTRO_SPLASH_SCENE)


func _on_continue_pressed() -> void:
	# Все 3 арены пройдены → level_select (free choice mode).
	if CampaignProgress.all_completed():
		get_tree().change_scene_to_file(LEVEL_SELECT_SCENE)
		return
	# Defense-in-depth: button disabled когда no progress, но если как-то всё-таки
	# clicked'ed (focus + Enter race) — fallback на new_game поведение, чтобы
	# не запустить broken state.
	if not CampaignProgress.has_progress():
		_on_new_game_pressed()
		return
	# Resume from highest_unlocked (next un-completed arena).
	LevelSequence.current_index = CampaignProgress.highest_unlocked
	IntroState.target_scene = ARENA_SCENE
	get_tree().change_scene_to_file(INTRO_SPLASH_SCENE)


func _on_settings() -> void:
	# Standalone scene: settings_menu.gd._on_back() вернёт назад в main menu
	# через change_scene_to_file. is_overlay по умолчанию false.
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_credits() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)


func _on_quit() -> void:
	get_tree().quit()
