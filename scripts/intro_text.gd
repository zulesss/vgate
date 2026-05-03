class_name IntroText extends CanvasLayer

# M9 polish — intro text overlay показывает goal на старте каждого run'а:
#   "CAPTURE N SPHERES / AND SURVIVE 2 MINUTES" где N = SphereDirector.CAPTURE_TARGET
#   (single source of truth — text не отстанет если target поменяют).
#
# Жизненный цикл (5 сек total):
#   - run_started: alpha=0 → text refresh → fade in 0.5с → hold 4с → fade out 0.5с
#   - Если новый run_started прилетит во время предыдущего fade'а (быстрый death-restart) —
#     прерываем активный tween и стартуем заново. Иначе бы tween'ы накладывались.
#
# Tween таргетит дочерние CanvasItem'ы (Backdrop, Label) — у CanvasLayer нет modulate.
# Pattern same как kill_chain_flash.gd: rect.modulate.a tween, не self.modulate.

const FADE_IN := 0.5
const HOLD := 4.0
const FADE_OUT := 0.5

@onready var backdrop: ColorRect = $Backdrop
@onready var label: Label = $Label

var _tween: Tween = null


func _ready() -> void:
	# Стартует невидимым — emit run_started в RunLoop._ready пинает первый show.
	backdrop.modulate.a = 0.0
	label.modulate.a = 0.0
	Events.run_started.connect(_on_run_started)


func _on_run_started() -> void:
	# Active director switches intro text per arena. _active set'ится в каждом
	# director'е в _on_run_started ДО HUD/Intro listener'ов? — порядок connect'а
	# не гарантирован, но autoload'ы регистрируются в project.godot order
	# (Sphere до Mark до RunHud/Intro). VelocityGate.reset_for_run() emit'ит
	# Events.run_started, Godot вызывает callback'и в connect-order. Director'ы
	# подписываются в _ready'е (autoload startup), Intro подписывается в _ready'е
	# scene'ы (после autoload'ов) → director'ы run_started'ятся раньше.
	# M10 Journey arena: short directive — нет timer'а, нет counter'а, only
	# physical objective "дойди до конца не умирая". Detection через group check
	# на arena root (single source of truth с RunLoop / SpawnController).
	if not get_tree().get_nodes_in_group(&"objective_journey").is_empty():
		label.text = "ЗАЧИСТИ ВРАГОВ И ПОКИНЬ ЗОНУ\nЗА 2 МИНУТЫ"
	elif AltarDirector._active:
		label.text = "ЗАХВАТИ %d АЛТАРЕЙ\nИ УБЕЙ ИСПОЛНИТЕЛЯ" % AltarDirector.ALTAR_COUNT
	elif MarkDirector._active:
		label.text = "УСТРАНИ %d МЕЧЕНЫХ\nИ ВЫЖИВИ 2 МИНУТЫ" % MarkDirector.KILL_TARGET
	else:
		label.text = "ЗАХВАТИ %d СФЕР\nИ ВЫЖИВИ 2 МИНУТЫ" % SphereDirector.CAPTURE_TARGET
	if _tween != null and _tween.is_valid():
		_tween.kill()
	backdrop.modulate.a = 0.0
	label.modulate.a = 0.0
	# Все 4 tween'а параллельны во времени, sequencing через set_delay —
	# bulletproof против quirk'ов chain() + set_parallel в Godot 4.x.
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(backdrop, "modulate:a", 1.0, FADE_IN)
	_tween.tween_property(label, "modulate:a", 1.0, FADE_IN)
	_tween.tween_property(backdrop, "modulate:a", 0.0, FADE_OUT).set_delay(FADE_IN + HOLD)
	_tween.tween_property(label, "modulate:a", 0.0, FADE_OUT).set_delay(FADE_IN + HOLD)
