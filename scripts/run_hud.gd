class_name RunHud extends CanvasLayer

# M4 Run HUD — два Label'а в углах. Timer = mm:ss из ScoreState.run_time, score =
# текущий current_score. Score обновляется по Events.score_changed (push), timer —
# каждый _process кадр (не event'ный, run_time тикает непрерывно).

@onready var timer_label: Label = $TopLeft/TimerLabel
@onready var score_label: Label = $TopRight/ScoreLabel


func _ready() -> void:
	Events.score_changed.connect(_on_score_changed)
	score_label.text = "0"


func _process(_delta: float) -> void:
	var t: float = ScoreState.run_time
	var m: int = int(t / 60.0)
	var s: int = int(t) % 60
	timer_label.text = "%02d:%02d" % [m, s]


func _on_score_changed(score: int) -> void:
	score_label.text = str(score)
