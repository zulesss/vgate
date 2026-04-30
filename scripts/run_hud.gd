class_name RunHud extends CanvasLayer

# M4 Run HUD — два Label'а в углах. Timer = mm:ss из ScoreState.run_time, score =
# текущий current_score. Score обновляется по Events.score_changed (push), timer —
# каждый _process кадр (не event'ный, run_time тикает непрерывно).
#
# M5 PKG-F: добавлен velocity cap meter (ProgressBar внизу-центра) — читаемость
# Velocity Gate hook'а. Цвет lerp'ится по value: red < 0.5 < yellow < 0.8 < green.
#
# M5 polish: sci-fi minimal стиль — mono SystemFont, cyan #7AE7E7, bracket-обёртка
# для timer/score. Cap bar получил CAP-title + numeric readout справа +
# threshold tick (30%, статичный). Сверху над cap bar — DashRow: тонкий cooldown
# индикатор (пустой → полный за 2.5 сек). Игрок берётся через group "player" +
# публичный метод get_dash_cooldown_remaining().

const DASH_COOLDOWN_DURATION := 2.5

@onready var timer_label: Label = $TopLeft/TimerLabel
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var dash_row: Control = $BottomCenter/VBox/DashRow
@onready var dash_fill: ColorRect = $BottomCenter/VBox/DashRow/DashFill
@onready var cap_bar: ProgressBar = $BottomCenter/VBox/CapRow/CapBarContainer/CapBar
@onready var cap_fill: ColorRect = $BottomCenter/VBox/CapRow/CapBarContainer/CapBar/Fill
@onready var cap_value_label: Label = $BottomCenter/VBox/CapRow/CapValue

const COLOR_LOW := Color(0.95, 0.25, 0.20)    # < 50 cap
const COLOR_MID := Color(0.95, 0.85, 0.20)    # 50-80 cap
const COLOR_HIGH := Color(0.30, 0.85, 0.40)   # >= 80 cap

var _player: Node = null


func _ready() -> void:
	Events.score_changed.connect(_on_score_changed)
	score_label.text = "[ 0 ]"
	# Player reference: нет explicit signal'а, читаем напрямую из группы "player"
	# (выставляется в objects/player.gd). На случай если Player ещё не в дереве —
	# resolve лениво в _process.
	_player = get_tree().get_first_node_in_group("player")
	dash_row.visible = false


func _process(_delta: float) -> void:
	# Timer
	var t: float = ScoreState.run_time
	var m: int = int(t / 60.0)
	var s: int = int(t) % 60
	timer_label.text = "[ %02d:%02d ]" % [m, s]

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
	cap_value_label.text = "%d" % int(cap)

	# Dash cooldown bar — поверх cap bar'а. Пустой сразу после dash → полный к
	# моменту готовности. visible=false когда dash готов (cd == 0).
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_method("get_dash_cooldown_remaining"):
		var cd: float = _player.get_dash_cooldown_remaining()
		if cd > 0.0:
			dash_row.visible = true
			dash_fill.anchor_right = clampf(1.0 - cd / DASH_COOLDOWN_DURATION, 0.0, 1.0)
		else:
			dash_row.visible = false
	else:
		dash_row.visible = false


func _on_score_changed(score: int) -> void:
	score_label.text = "[ %d ]" % score
