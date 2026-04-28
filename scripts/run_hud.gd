class_name RunHud extends CanvasLayer

# M4 Run HUD — два Label'а в углах. Timer = mm:ss из ScoreState.run_time, score =
# текущий current_score. Score обновляется по Events.score_changed (push), timer —
# каждый _process кадр (не event'ный, run_time тикает непрерывно).
#
# M5 PKG-F: добавлен velocity cap meter (ProgressBar внизу-центра) — читаемость
# Velocity Gate hook'а. Цвет lerp'ится по value: red < 0.5 < yellow < 0.8 < green.

@onready var timer_label: Label = $TopLeft/TimerLabel
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var cap_bar: ProgressBar = $BottomCenter/CapBar
@onready var cap_fill: ColorRect = $BottomCenter/CapBar/Fill

const COLOR_LOW := Color(0.95, 0.25, 0.20)    # < 50 cap
const COLOR_MID := Color(0.95, 0.85, 0.20)    # 50-80 cap
const COLOR_HIGH := Color(0.30, 0.85, 0.40)   # >= 80 cap


func _ready() -> void:
	Events.score_changed.connect(_on_score_changed)
	score_label.text = "0"


func _process(_delta: float) -> void:
	var t: float = ScoreState.run_time
	var m: int = int(t / 60.0)
	var s: int = int(t) % 60
	timer_label.text = "%02d:%02d" % [m, s]

	# Cap meter: VelocityGate.velocity_cap 0..100. Width manual через ColorRect
	# anchor_right (ProgressBar styling в Godot 4.6 через theme — для prototype
	# тон-стиля цена не оправдана, ColorRect-fill даёт прямой control).
	var cap: float = VelocityGate.velocity_cap
	var cap_norm: float = clampf(cap / 100.0, 0.0, 1.0)
	cap_bar.value = cap
	cap_fill.anchor_right = cap_norm
	# Color lerp по cap_norm.
	if cap_norm < 0.5:
		cap_fill.color = COLOR_LOW
	elif cap_norm < 0.8:
		cap_fill.color = COLOR_MID
	else:
		cap_fill.color = COLOR_HIGH


func _on_score_changed(score: int) -> void:
	score_label.text = str(score)
