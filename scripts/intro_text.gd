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
# Mouse passthrough: layer высокий чтобы поверх HUD / crosshair'а, но mouse_filter=ignore
# на root + child label чтобы клики/aim проходили насквозь (игрок может играть пока visible).

const FADE_IN := 0.5
const HOLD := 4.0
const FADE_OUT := 0.5

@onready var label: Label = $Label

var _tween: Tween = null


func _ready() -> void:
	# Стартует невидимым — emit run_started в RunLoop._ready пинает первый show.
	modulate.a = 0.0
	Events.run_started.connect(_on_run_started)


func _on_run_started() -> void:
	_refresh_text()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)


func _refresh_text() -> void:
	var target: int = SphereDirector.CAPTURE_TARGET
	label.text = "CAPTURE %d SPHERES\nAND SURVIVE 2 MINUTES" % target
