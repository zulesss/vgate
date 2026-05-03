class_name IntroSplash extends CanvasLayer

# M12 intro splash — terminal boot sequence перед первой ареной (от main menu START).
# Не показывается на death-restart loop'е (RunLoop.reload_current_scene минует splash).
#
# Sequence (~3.1s total + skippable):
#   0.00–0.50 — caret blink ("_" toggling)
#   0.50–2.00 — type-on text (~50 chars × ~30ms)
#   2.00–2.60 — hold full text
#   2.60–3.10 — fade out (Bg+Label modulate.a → 0)
#   3.10       — change_scene_to_file(IntroState.target_scene)
#
# Skip — на любой input event (mouse/keyboard) до завершения, switch immediately.

const TARGET_TEXT := "МОДУЛЬ КИНЕТИЧЕСКОГО КОНТРОЛЯ — АКТИВЕН\nЗАПУСК ПРОЦЕДУРЫ ИСПЫТАНИЯ"
const FALLBACK_SCENE := "res://scenes/main.tscn"

const CARET_BLINK_PERIOD := 0.25  # 0.5s total / 2 cycles
const CARET_BLINK_CYCLES := 2
const TYPE_ON_PER_CHAR := 0.030
const HOLD_AFTER_TYPE := 0.6
const FADE_OUT := 0.5

@onready var bg: ColorRect = $Bg
@onready var label: Label = $Center/Label

var _target: String = ""
var _switched: bool = false


func _ready() -> void:
	# Cursor visible на splash — кликабельно skippable (доп. к keyboard).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_target = IntroState.target_scene
	if _target == "":
		_target = FALLBACK_SCENE
	# Очищаем target — single-use per main-menu START. Между смертью и restart
	# splash не показывается (RunLoop загружает arena напрямую).
	IntroState.target_scene = ""
	label.text = "_"
	label.modulate.a = 1.0
	bg.modulate.a = 1.0
	_run_sequence()


func _run_sequence() -> void:
	# Caret blink phase
	for i in range(CARET_BLINK_CYCLES):
		label.text = "_"
		await get_tree().create_timer(CARET_BLINK_PERIOD).timeout
		if _switched:
			return
		label.text = ""
		await get_tree().create_timer(CARET_BLINK_PERIOD).timeout
		if _switched:
			return
	# Type-on phase: char-by-char
	label.text = ""
	for i in range(TARGET_TEXT.length()):
		label.text = TARGET_TEXT.substr(0, i + 1)
		await get_tree().create_timer(TYPE_ON_PER_CHAR).timeout
		if _switched:
			return
	# Hold
	await get_tree().create_timer(HOLD_AFTER_TYPE).timeout
	if _switched:
		return
	# Fade out
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(bg, "modulate:a", 0.0, FADE_OUT)
	t.tween_property(label, "modulate:a", 0.0, FADE_OUT)
	await t.finished
	if _switched:
		return
	_switch_to_target()


func _input(event: InputEvent) -> void:
	# Skip на любой confirm/click. Mouse motion игнорим.
	if _switched:
		return
	if event is InputEventKey and event.pressed:
		_switch_to_target()
	elif event is InputEventMouseButton and event.pressed:
		_switch_to_target()


func _switch_to_target() -> void:
	if _switched:
		return
	_switched = true
	get_tree().change_scene_to_file(_target)
