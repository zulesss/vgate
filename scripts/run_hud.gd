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
# M9 conquest: countdown timer (120 → 0) с visual cue для spike phase (t≥90).
# Cyan дефолт → красноватый при spike. Простой modulate switch, без tween — это
# discrete event на t=90, не плавный ramp.
const RUN_DURATION := 120.0
const SPIKE_TIME := 90.0
const TIMER_COLOR_NORMAL := Color(0.478, 0.906, 0.906, 1)
const TIMER_COLOR_SPIKE := Color(0.95, 0.45, 0.35, 1)

@onready var timer_label: Label = $TopLeft/TimerLabel
@onready var score_label: Label = $TopRight/VBox/ScoreLabel
@onready var sphere_label: Label = $TopRight/VBox/SphereLabel
@onready var dash_row: Control = $BottomCenter/VBox/DashRow
@onready var dash_fill: ColorRect = $BottomCenter/VBox/DashRow/DashFill
@onready var cap_bar: ProgressBar = $BottomCenter/VBox/CapRow/CapBarContainer/CapBar
@onready var cap_fill: ColorRect = $BottomCenter/VBox/CapRow/CapBarContainer/CapBar/Fill
@onready var cap_value_label: Label = $BottomCenter/VBox/CapRow/CapValue
@onready var ammo_label: Label = $BottomRight/VBox/AmmoLabel
@onready var reload_row: Control = $BottomRight/VBox/ReloadRow
@onready var reload_fill: ColorRect = $BottomRight/VBox/ReloadRow/ReloadFill

const COLOR_LOW := Color(0.95, 0.25, 0.20)    # < 50 cap
const COLOR_MID := Color(0.95, 0.85, 0.20)    # 50-80 cap
const COLOR_HIGH := Color(0.30, 0.85, 0.40)   # >= 80 cap

# M9 Hot Zones sphere counter colors. До target — cyan. >= 20 (objective met) —
# green tint + galочка вместо countdown'а (signal "относительно расслабься").
const SPHERE_COLOR_NORMAL := Color(0.478, 0.906, 0.906, 1)
const SPHERE_COLOR_DONE := Color(0.30, 0.85, 0.40, 1)
const SPHERE_TARGET := 20

var _player: Node = null


func _ready() -> void:
	Events.score_changed.connect(_on_score_changed)
	Events.sphere_captured.connect(_on_sphere_captured)
	Events.run_started.connect(_on_run_started)
	score_label.text = "[ 0 ]"
	_refresh_sphere_label()
	# Player reference: нет explicit signal'а, читаем напрямую из группы "player"
	# (выставляется в objects/player.gd). На случай если Player ещё не в дереве —
	# resolve лениво в _process.
	_player = get_tree().get_first_node_in_group("player")
	dash_row.visible = false
	reload_row.visible = false


func _process(_delta: float) -> void:
	# M9 conquest: countdown 120→0. Spike (t≥90) → red tint timer'а как visual cue
	# что что-то изменилось в момент step-up'а threshold'а / spawn ramp'а.
	var t_alive: float = ScoreState.run_time
	var remaining: float = maxf(0.0, RUN_DURATION - t_alive)
	var m: int = int(remaining / 60.0)
	var s: int = int(remaining) % 60
	timer_label.text = "[ %02d:%02d ]" % [m, s]
	timer_label.modulate = TIMER_COLOR_SPIKE if t_alive >= SPIKE_TIME else TIMER_COLOR_NORMAL

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

	# Ammo counter + reload progress. Player-method gated — иначе HUD trash'ит лог
	# когда RunHud жив без player'а (на arena reload между смертью и spawn'ом).
	if _player != null and _player.has_method("get_current_ammo"):
		var cur: int = _player.get_current_ammo()
		var amax: int = _player.get_max_ammo()
		ammo_label.text = "%d / %d" % [cur, amax]
		var reloading: bool = _player.is_reloading()
		if reloading:
			reload_row.visible = true
			reload_fill.anchor_right = clampf(_player.get_reload_progress(), 0.0, 1.0)
		else:
			reload_row.visible = false


func _on_score_changed(score: int) -> void:
	score_label.text = "[ %d ]" % score


func _on_sphere_captured(_pos: Vector3) -> void:
	_refresh_sphere_label()


func _on_run_started() -> void:
	_refresh_sphere_label()


func _refresh_sphere_label() -> void:
	# До target: "07/20" cyan. На target и выше: "✓ 20+" green (objective met,
	# enemy spawn paused — visual signal "ты можешь дышать").
	var c: int = SphereDirector.captured_count
	if c >= SPHERE_TARGET:
		sphere_label.text = "✓ %d" % c
		sphere_label.modulate = SPHERE_COLOR_DONE
	else:
		sphere_label.text = "%02d / %d" % [c, SPHERE_TARGET]
		sphere_label.modulate = SPHERE_COLOR_NORMAL
