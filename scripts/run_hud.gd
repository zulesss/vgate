class_name RunHud extends CanvasLayer

# M4 Run HUD — два Label'а в углах. Timer = mm:ss из ScoreState.run_time, score =
# текущий current_score. Score обновляется по Events.score_changed (push), timer —
# каждый _process кадр (не event'ный, run_time тикает непрерывно).
#
# M5 PKG-F: добавлен velocity cap meter (ProgressBar внизу-центра) — читаемость
# Velocity Gate hook'а. Цвет lerp'ится по value: red < 0.5 < yellow < 0.8 < green.
#
# M5 polish: sci-fi minimal стиль — mono SystemFont, cyan #7AE7E7, bracket-обёртка
# для timer/score. Cap bar получил CAP-title + numeric readout справа.
# Сверху над cap bar — DashRow: тонкий cooldown индикатор (пустой → полный
# за 2.5 сек). Игрок берётся через group "player" +
# публичный метод get_dash_cooldown_remaining().
# Cathedral boss arena: поверх HUD — top-center BossBar (Pkg B): VISIBLE
# только пока boss alive. Phase-color section'ы + 2 vertical tick'а на 67% / 34%.

const DASH_COOLDOWN_DURATION := 2.5
# M9 conquest: countdown timer (120 → 0) с 3 visual phases:
#   0–45с  — cyan/normal (settle in)
#   45–90с — amber (swarm intro warning)
#   90–120с — red (spike phase entry)
# Простой modulate switch, без tween — discrete events на t=45 / t=90.
const RUN_DURATION := 120.0
const WARN_TIME := 45.0
const SPIKE_TIME := 90.0
const TIMER_COLOR_NORMAL := Color(0.478, 0.906, 0.906, 1)
const TIMER_COLOR_WARN := Color(0.95, 0.80, 0.30, 1)
const TIMER_COLOR_SPIKE := Color(0.95, 0.45, 0.35, 1)
# M10 Journey arena (clear-and-escape): теперь 120с deadline активен, timer
# countdown как в обычной арене (cyan/amber/red phase tinting). Вместо
# sphere/hunt counter показываем "ENEMIES: N" — оставшиеся живые враги в
# группе "enemy". Decrements автоматически на queue_free.
const ARENA_GROUP_JOURNEY := &"objective_journey"
const ARENA_GROUP_CATHEDRAL := &"objective_cathedral"
const ENEMY_GROUP := &"enemy"
const ENEMY_COLOR_NORMAL := Color(0.478, 0.906, 0.906, 1)
const ENEMY_COLOR_DONE := Color(0.30, 0.85, 0.40, 1)
# Cathedral altar counter colors. Orange до target (matches contested altar
# emissive), gold на done (matches captured altar — instant association).
const ALTAR_COLOR_NORMAL := Color(1.0, 0.5, 0.3, 1)
const ALTAR_COLOR_DONE := Color(1.0, 0.8, 0.2, 1)

@onready var timer_label: Label = $TopLeft/VBox/TimerLabel
@onready var sphere_label: Label = $TopLeft/VBox/SphereLabel
@onready var hunt_label: Label = $TopLeft/VBox/HuntLabel
@onready var enemy_label: Label = $TopLeft/VBox/EnemyLabel
@onready var altar_label: Label = $TopLeft/VBox/AltarLabel
@onready var score_label: Label = $TopRight/ScoreLabel
@onready var dash_row: Control = $BottomCenter/VBox/DashRow
@onready var dash_fill: ColorRect = $BottomCenter/VBox/DashRow/DashFill
@onready var capturing_row: HBoxContainer = $BottomCenter/VBox/CapturingRow
@onready var capturing_fill: ColorRect = $BottomCenter/VBox/CapturingRow/CapturingBarContainer/CapturingBar/Fill
@onready var cap_bar: ProgressBar = $BottomCenter/VBox/CapRow/CapBarContainer/CapBar
@onready var cap_fill: ColorRect = $BottomCenter/VBox/CapRow/CapBarContainer/CapBar/Fill
@onready var cap_value_label: Label = $BottomCenter/VBox/CapRow/CapValue
@onready var ammo_label: Label = $BottomRight/VBox/AmmoLabel
@onready var reload_row: Control = $BottomRight/VBox/ReloadRow
@onready var reload_fill: ColorRect = $BottomRight/VBox/ReloadRow/ReloadFill
@onready var boss_root: MarginContainer = $TopCenter
@onready var boss_bar_fill: ColorRect = $TopCenter/VBox/BossBarContainer/BossBarFill
@onready var captured_toast: Label = $CapturedToast

const COLOR_LOW := Color(0.95, 0.25, 0.20)    # < 50 cap
const COLOR_MID := Color(0.95, 0.85, 0.20)    # 50-80 cap
const COLOR_HIGH := Color(0.30, 0.85, 0.40)   # >= 80 cap

# Cathedral capturing-bar fill color (yellow — matches CAPTURING altar emissive).
# При progress=0 (signal сброса) бар скрывается полностью — separate state visible=false.
const CAPTURING_FILL_COLOR := Color(1.0, 0.9, 0.0, 1.0)

# CAPTURED toast: hold 1.5s full opacity → fade 0.5s = 2.0s total. Latest-wins
# semantics — rapid back-to-back captures kill prior tween, restart from full
# alpha. Гарантирует bounded visual life и no overlapping fades.
const CAPTURED_TOAST_HOLD := 1.5
const CAPTURED_TOAST_FADE := 0.5

# M9 Hot Zones sphere counter colors. До target — cyan. >= CAPTURE_TARGET (objective met) —
# green tint + галочка вместо countdown'а (signal "относительно расслабься").
# Target value читается из SphereDirector.CAPTURE_TARGET — single source of truth.
const SPHERE_COLOR_NORMAL := Color(0.478, 0.906, 0.906, 1)
const SPHERE_COLOR_DONE := Color(0.30, 0.85, 0.40, 1)

# Marked Hunt counter colors. Magenta до target (matches mark visual aura),
# green на done. Target из MarkDirector.KILL_TARGET — single source of truth.
const HUNT_COLOR_NORMAL := Color(1.0, 0.45, 0.85, 1)
const HUNT_COLOR_DONE := Color(0.30, 0.85, 0.40, 1)

# Boss HP bar colors. Phase 1 (>67% HP) — green/healthy. Phase 2 (34-67%) —
# orange/caution (matches charge telegraph contrast vs. golden idle). Phase 3
# (<34%) — red/finale. Lerp нет — discrete switch on phase boundary совпадает с
# audio cue + emissive flash boss'а (читается как «фаза щёлкнула», not gradient).
const BOSS_PHASE_2_HP_RATIO := 0.67
const BOSS_PHASE_3_HP_RATIO := 0.34
const BOSS_BAR_PHASE1_COLOR := Color(0.30, 0.85, 0.40, 1)
const BOSS_BAR_PHASE2_COLOR := Color(1.0, 0.55, 0.20, 1)
const BOSS_BAR_PHASE3_COLOR := Color(0.95, 0.25, 0.20, 1)

var _player: Node = null
# Set per-run в _on_run_started через group check. Журней-арена → timer count-up
# без phase tinting (timer не дедлайн). Иначе — countdown 120→0 с phases.
var _is_journey: bool = false
# Cathedral arena: timer-less (no deadline), altar counter visible вместо
# sphere/hunt counter'а. Boss phase — timer hidden completely.
var _is_cathedral: bool = false

# Capturing progress bar state. Какой altar index сейчас отображается + текущий
# progress. -1 = ни один altar не tracked (бар скрыт). При входе в новую zone
# director эмитит progress > 0 — мы переключаем _capturing_altar_index на её
# index. При progress == 0 — если индекс совпадает, скрываем бар.
var _capturing_altar_index: int = -1

# CAPTURED toast tween handle. Хранится чтобы kill старый при back-to-back
# capture (otherwise двойной fade накладывается → mid-alpha glitch).
var _captured_toast_tween: Tween = null


func _ready() -> void:
	Events.score_changed.connect(_on_score_changed)
	Events.sphere_captured.connect(_on_sphere_captured)
	Events.mark_killed.connect(_on_mark_killed)
	Events.altar_captured.connect(_on_altar_captured)
	Events.altar_dwell_progress.connect(_on_altar_dwell_progress)
	Events.run_started.connect(_on_run_started)
	Events.boss_phase_started.connect(_on_boss_phase_started)
	Events.boss_hp_changed.connect(_on_boss_hp_changed)
	Events.boss_killed.connect(_on_boss_phase_ended)
	Events.player_died.connect(_on_boss_phase_ended)
	score_label.text = "[ 0 ]"
	_refresh_objective_labels()
	# Player reference: нет explicit signal'а, читаем напрямую из группы "player"
	# (выставляется в objects/player.gd). На случай если Player ещё не в дереве —
	# resolve лениво в _process.
	_player = get_tree().get_first_node_in_group("player")
	dash_row.visible = false
	reload_row.visible = false
	capturing_row.visible = false
	capturing_fill.anchor_right = 0.0
	boss_root.visible = false
	boss_bar_fill.anchor_right = 1.0


func _process(_delta: float) -> void:
	# M9 conquest / M10 Journey: countdown 120→0. 3-phase timer tint — cyan /
	# amber / red на t=0/45/90. Каждая граница — instant swap, signal что давление
	# шагнуло вверх. Journey arena использует те же phases — clear-and-escape
	# теперь deadline-driven (см. RunLoop).
	# Cathedral: no deadline. Timer label показывает alive time count-up без phase
	# tinting — чистая reference value (не давление).
	var t_alive: float = ScoreState.run_time
	if _is_cathedral:
		# Cathedral: no deadline, no reference timer — label hidden completely.
		# Player tracks progress via altar counter + boss bar, timer не нужен.
		timer_label.visible = false
	else:
		timer_label.visible = true
		var remaining: float = maxf(0.0, RUN_DURATION - t_alive)
		var m: int = int(remaining / 60.0)
		var s: int = int(remaining) % 60
		timer_label.text = "[ %02d:%02d ]" % [m, s]
		if t_alive >= SPIKE_TIME:
			timer_label.modulate = TIMER_COLOR_SPIKE
		elif t_alive >= WARN_TIME:
			timer_label.modulate = TIMER_COLOR_WARN
		else:
			timer_label.modulate = TIMER_COLOR_NORMAL

	# Journey enemy counter: live update каждый кадр (нет дешёвого signal'а на
	# enemy spawn — pursuers spawn'ятся async из spawn_controller). Group size
	# через get_nodes_in_group — O(N) но N ≤ 30, copy-cost negligible.
	if _is_journey:
		var alive_enemies: int = get_tree().get_nodes_in_group(ENEMY_GROUP).size()
		if alive_enemies <= 0:
			enemy_label.text = "✓ CLEAR"
			enemy_label.modulate = ENEMY_COLOR_DONE
		else:
			enemy_label.text = "ENEMIES: %d" % alive_enemies
			enemy_label.modulate = ENEMY_COLOR_NORMAL

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
	_refresh_objective_labels()


func _on_mark_killed() -> void:
	_refresh_objective_labels()


func _on_altar_captured(_index: int) -> void:
	_refresh_objective_labels()
	_show_captured_toast()


func _show_captured_toast() -> void:
	# Latest-wins: kill любой in-flight tween, restart from full alpha. Без kill'а
	# старый fade продолжит mute'ить нашу свежую entry'ю → flicker.
	if _captured_toast_tween != null and _captured_toast_tween.is_valid():
		_captured_toast_tween.kill()
	captured_toast.visible = true
	captured_toast.modulate = Color(1, 1, 1, 1)
	_captured_toast_tween = create_tween()
	_captured_toast_tween.tween_interval(CAPTURED_TOAST_HOLD)
	_captured_toast_tween.tween_property(captured_toast, "modulate:a", 0.0, CAPTURED_TOAST_FADE)
	_captured_toast_tween.tween_callback(func() -> void: captured_toast.visible = false)


# Capturing progress bar follow logic. Multiple altars могут быть в states
# CAPTURING/CONTESTED одновременно (rare — игрок одновременно в двух zone'ах
# не помещается, но overlapping zones вокруг corners theoretically возможны),
# поэтому бар следует за тем altar'ом который последним прислал progress > 0.
# Progress == 0 от tracked altar'а → скрыть бар. Progress == 0 от другого
# altar'а → игнорируем (он не tracked).
func _on_altar_dwell_progress(index: int, progress: float) -> void:
	if progress > 0.0:
		_capturing_altar_index = index
		capturing_row.visible = true
		capturing_fill.anchor_right = clampf(progress, 0.0, 1.0)
	else:
		# Reset signal — скрыть только если касается отслеживаемого altar'а.
		if index == _capturing_altar_index:
			_capturing_altar_index = -1
			capturing_row.visible = false
			capturing_fill.anchor_right = 0.0


func _on_run_started() -> void:
	_is_journey = not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty()
	_is_cathedral = not get_tree().get_nodes_in_group(ARENA_GROUP_CATHEDRAL).is_empty()
	# Clean capturing bar на каждый run start (предыдущий run'а residue).
	_capturing_altar_index = -1
	capturing_row.visible = false
	capturing_fill.anchor_right = 0.0
	# Boss bar — hide на каждый run start. Show по boss_phase_started signal'у
	# (cathedral specific) — другие арены никогда не эмитят, бар не появится.
	boss_root.visible = false
	# CAPTURED toast — kill in-flight tween, hide. Reload во время mid-fade
	# иначе оставит residue alpha при start'е следующего run'а.
	if _captured_toast_tween != null and _captured_toast_tween.is_valid():
		_captured_toast_tween.kill()
	_captured_toast_tween = null
	captured_toast.visible = false
	captured_toast.modulate = Color(1, 1, 1, 0)
	_refresh_objective_labels()


func _on_boss_phase_started() -> void:
	# Boss instantiate'нут AltarDirector'ом — bar visible. Boss._ready() уже
	# emit'ит boss_hp_changed(max, max), но show до того как первый damage пришёл —
	# fill anchor_right = 1.0 (set из _ready'я выше).
	boss_root.visible = true
	boss_bar_fill.anchor_right = 1.0
	boss_bar_fill.color = BOSS_BAR_PHASE1_COLOR


func _on_boss_hp_changed(current: int, max_value: int) -> void:
	if max_value <= 0:
		return
	var ratio: float = clampf(float(current) / float(max_value), 0.0, 1.0)
	boss_bar_fill.anchor_right = ratio
	# Phase color shift — discrete на boundary. Совпадает с boss phase
	# transition flash + audio cue, читается как unified «фаза щёлкнула».
	if ratio > BOSS_PHASE_2_HP_RATIO:
		boss_bar_fill.color = BOSS_BAR_PHASE1_COLOR
	elif ratio > BOSS_PHASE_3_HP_RATIO:
		boss_bar_fill.color = BOSS_BAR_PHASE2_COLOR
	else:
		boss_bar_fill.color = BOSS_BAR_PHASE3_COLOR


func _on_boss_phase_ended() -> void:
	# Скрыть bar на boss death OR player death. Идемпотентно — multi-emit ok.
	boss_root.visible = false


func _refresh_objective_labels() -> void:
	# Per-arena objective: один из director'ов active (run_started ставит _active
	# по group check'у). Активный label видим, неактивный hidden — без dimmed
	# варианта чтобы HUD не cluttered'ил. Journey arena: enemy counter, остальные
	# скрыты — counter обновляется per-frame в _process.
	if _is_cathedral:
		sphere_label.visible = false
		hunt_label.visible = false
		enemy_label.visible = false
		altar_label.visible = true
		_refresh_altar_label()
	elif _is_journey:
		sphere_label.visible = false
		hunt_label.visible = false
		enemy_label.visible = true
		altar_label.visible = false
	elif SphereDirector._active:
		sphere_label.visible = true
		hunt_label.visible = false
		enemy_label.visible = false
		altar_label.visible = false
		_refresh_sphere_label()
	elif MarkDirector._active:
		sphere_label.visible = false
		hunt_label.visible = true
		enemy_label.visible = false
		altar_label.visible = false
		_refresh_hunt_label()
	else:
		# До run_started все директора dormant. Hide — main_menu / pre-run state.
		sphere_label.visible = false
		hunt_label.visible = false
		enemy_label.visible = false
		altar_label.visible = false


func _refresh_sphere_label() -> void:
	# До target: "07/15" cyan. На target и выше: "✓ 15+" green (objective met,
	# enemy spawn paused — visual signal "ты можешь дышать").
	var c: int = SphereDirector.captured_count
	var target: int = SphereDirector.CAPTURE_TARGET
	if c >= target:
		sphere_label.text = "✓ %d" % c
		sphere_label.modulate = SPHERE_COLOR_DONE
	else:
		sphere_label.text = "%02d / %d" % [c, target]
		sphere_label.modulate = SPHERE_COLOR_NORMAL


func _refresh_hunt_label() -> void:
	# Magenta до target ("HUNT 03 / 15"), green на target+ ("✓ HUNT 15+").
	# Цвет коррелирует с emissive aura mark'а — instant association.
	var k: int = MarkDirector.kills
	var target: int = MarkDirector.KILL_TARGET
	if k >= target:
		hunt_label.text = "✓ HUNT %d" % k
		hunt_label.modulate = HUNT_COLOR_DONE
	else:
		hunt_label.text = "HUNT %02d / %d" % [k, target]
		hunt_label.modulate = HUNT_COLOR_NORMAL


func _refresh_altar_label() -> void:
	# Orange до 4/4 ("ALTARS 2 / 4"), gold на 4/4 — "BOSS PHASE" hint после
	# capture'а 4-го altar'а. Гарантирует игроку что осталось — kill the boss.
	var c: int = AltarDirector.captured_count
	var target: int = AltarDirector.ALTAR_COUNT
	if c >= target:
		altar_label.text = "KILL THE BOSS"
		altar_label.modulate = ALTAR_COLOR_DONE
	else:
		altar_label.text = "ALTARS %d / %d" % [c, target]
		altar_label.modulate = ALTAR_COLOR_NORMAL
