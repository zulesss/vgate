class_name LevelSelect extends Control

# M13 free-choice mode — открывается только когда все 3 арены пройдены.
# Player может выбрать любую арену для replay'а; per-arena best scores
# показываются на кнопках. Возврат в main menu через НАЗАД.
#
# Best scores читаются напрямую из ConfigFile [high_scores] (не через
# ScoreState API — ScoreState грузит ТОЛЬКО current arena best на _on_run_started,
# а здесь нужны все 3). Coupling минимален: знание save format'а — local,
# не extracted в shared accessor.

const SAVE_PATH := "user://vgate_progress.cfg"
const HIGH_SCORES_SECTION := "high_scores"
const ARENA_SCENE := "res://scenes/main.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const INTRO_SPLASH_SCENE := "res://scenes/intro_splash.tscn"

# Match ScoreState.ARENA_KEY_* + LevelSequence.ARENA_PATHS index order.
const PLAC_KEY := "plac"
const KAMERA_KEY := "kamera"
const CATHEDRAL_KEY := "cathedral"
const PLAC_INDEX := 0
const KAMERA_INDEX := 1
const CATHEDRAL_INDEX := 2

@onready var plac_btn: Button = $Center/VBox/PlacButton
@onready var kamera_btn: Button = $Center/VBox/KameraButton
@onready var cathedral_btn: Button = $Center/VBox/CathedralButton
@onready var back_btn: Button = $Center/VBox/BackButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Defensive: возврат из gameplay сюда теоретически невозможен (level_select
	# открывается только из main_menu), но silence audio на всякий случай.
	MusicDirector.stop_all()
	Sfx.stop_all_loops()
	VelocityGate.end_run()
	# Read all 3 best scores один раз — populate button labels.
	var bests: Dictionary = _load_all_bests()
	plac_btn.text = "ПЛАЦ — лучший: %d" % int(bests.get(PLAC_KEY, 0))
	kamera_btn.text = "КАМЕРА — лучший: %d" % int(bests.get(KAMERA_KEY, 0))
	cathedral_btn.text = "СОБОР — лучший: %d" % int(bests.get(CATHEDRAL_KEY, 0))
	plac_btn.pressed.connect(_on_plac_pressed)
	kamera_btn.pressed.connect(_on_kamera_pressed)
	cathedral_btn.pressed.connect(_on_cathedral_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	plac_btn.grab_focus()


func _load_all_bests() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return {}
	return {
		PLAC_KEY: cf.get_value(HIGH_SCORES_SECTION, PLAC_KEY, 0),
		KAMERA_KEY: cf.get_value(HIGH_SCORES_SECTION, KAMERA_KEY, 0),
		CATHEDRAL_KEY: cf.get_value(HIGH_SCORES_SECTION, CATHEDRAL_KEY, 0),
	}


func _launch_arena(index: int) -> void:
	LevelSequence.current_index = index
	IntroState.target_scene = ARENA_SCENE
	get_tree().change_scene_to_file(INTRO_SPLASH_SCENE)


func _on_plac_pressed() -> void:
	_launch_arena(PLAC_INDEX)


func _on_kamera_pressed() -> void:
	_launch_arena(KAMERA_INDEX)


func _on_cathedral_pressed() -> void:
	_launch_arena(CATHEDRAL_INDEX)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
