class_name VelocityGateState extends Node

# Главный state hook'а. Все числа здесь — источник правды (см. docs/systems/M1_numbers.md).
# Player только сообщает current_speed, EnemyBase подклассы зовут apply_hit/apply_kill_restore,
# DebugHud только читает. Единственный owner state: этот autoload.

const BASE_WALK_SPEED := 8.0
const CAP_CEILING := 100.0
const RESPAWN_CAP := 80.0
# M9 conquest: threshold dynamic. Base 0.30 для 0-90с, RunLoop step'ает на 0.45
# в spike phase (90-120с) через current_drain_threshold field. Const оставлен как
# default value для reset_for_run() и для legacy callers (debug_hud, sfx breath).
const THRESHOLD := 0.3
const SPIKE_THRESHOLD := 0.45
const TOLERANCE_BELOW_THRESHOLD := 0.5
const DRAIN_RATE := 15.0
const SHOOTER_PENALTY := 10
const MELEE_PENALTY := 20
const SWARMLING_PENALTY := 5
const KILL_RESTORE := 25
# M9 Hot Zones playtest tweak (2026-05-02): capture sphere → +cap reward.
# Sphere objective был pure (без cap/score gain) — playtest показал, что это делало
# capture'ы "налогом" вместо положительной транзакции. +10 cap превращает sphere
# в parallel resource gain, сохраняя при этом отдельную axis от kill economy.
const SPHERE_REWARD := 10
const I_FRAMES_AFTER_HIT := 0.3
# M9 magazine reload: tradeoff "cap для полного magazine". apply_reload_cost path —
# отдельно от apply_hit, потому что reload сознательный choice (без vignette flash,
# без player_hit emit'а, без i-frames). Single source of truth для cost number.
const RELOAD_COST := 10

var velocity_cap: float = RESPAWN_CAP
var current_speed: float = 0.0
var drain_timer: float = 0.0
var is_draining: bool = false
var i_frames_remaining: float = 0.0
var is_alive: bool = false  # Default false: VelocityGate dormant в меню. reset_for_run() флипает в true при старте run'а, end_run() возвращает false при возврате в меню.
# M9 conquest: dynamic drain threshold. RunLoop step'ает на SPIKE_THRESHOLD при t>=90,
# reset_for_run() возвращает к THRESHOLD. _physics_process читает это поле, не const.
var current_drain_threshold: float = THRESHOLD
# M9 conquest: cap-time accumulator для score formula. Sum of velocity_cap × dt пока
# is_alive. avg_cap = _cap_accumulator / time_alive. Reset на reset_for_run().
# Время accumulator'а тикает в _physics_process (там же где drain logic) — единый
# pacing с остальной gate-логикой.
var _cap_accumulator: float = 0.0
var _alive_time: float = 0.0
# Kill Chain Tier 7+ sustained: разрешает effective ceiling = CAP_CEILING + ceiling_boost
# на время активного стрика. Read через apply_kill_restore (clamp вместо CAP_CEILING).
# Set'ит KillChain через set_ceiling_boost() на streak_entered, clear_ceiling_boost() на
# streak_exited (clamp velocity_cap обратно к CAP_CEILING если был выше).
var ceiling_boost: float = 0.0


func max_speed_at_cap() -> float:
	return BASE_WALK_SPEED * (velocity_cap / 100.0)


# M9 conquest score formula: floor(kills × avg_cap × time_alive_normalized).
# Возвращает avg_cap (0..100). Если run только начался (alive_time near 0) —
# fallback на текущий cap, чтобы score formula не делила на ноль.
func get_avg_cap_over_run() -> float:
	if _alive_time <= 0.001:
		return velocity_cap
	return _cap_accumulator / _alive_time


func get_alive_time() -> float:
	return _alive_time


func speed_ratio() -> float:
	var max_speed := max_speed_at_cap()
	if max_speed <= 0.0:
		return 0.0
	return clampf(current_speed / max_speed, 0.0, 1.0)


func set_current_speed(s: float) -> void:
	current_speed = s


func apply_hit(penalty: int) -> void:
	if not is_alive or i_frames_remaining > 0.0:
		return
	velocity_cap = maxf(0.0, velocity_cap - float(penalty))
	i_frames_remaining = I_FRAMES_AFTER_HIT
	if velocity_cap <= 0.0:
		# Симметрия с drain phase: cap = 0 = смерть, независимо от источника падения cap'а.
		# Hit-to-zero раньше оставлял игрока замороженным (max_speed=0) пока drain не добивал
		# через 2.5с tolerance. force_kill идемпотентен → safe вне зависимости от race'ов.
		force_kill()
		return
	Events.player_hit.emit(penalty)


func apply_kill_restore(pos: Vector3, type: String = "melee") -> void:
	if not is_alive:
		return
	# Effective ceiling = CAP_CEILING + ceiling_boost (Kill Chain Tier 7+ sustained
	# приподнимает потолок, позволяя cap > 100 пока streak активен).
	var effective_ceiling: float = CAP_CEILING + ceiling_boost
	velocity_cap = minf(effective_ceiling, velocity_cap + float(KILL_RESTORE))
	# Kill = выдох. Если игрок был под threshold — ratio после kill подскакивает,
	# drain сбрасывается на следующем tick через нормальный путь в _physics_process.
	# Дополнительно явно стопаем drain если он был активен — feel'у это критично:
	# мгновенный "выдох" на kill, не "drain ещё капает 1 кадр".
	if is_draining or drain_timer > 0.0:
		drain_timer = 0.0
		if is_draining:
			is_draining = false
			Events.drain_stopped.emit()
	Events.enemy_killed.emit(KILL_RESTORE, pos, type)


# M9 Hot Zones: sphere capture reward. Pure positive cap gain — отдельно от
# apply_hit (negative, vignette) и apply_kill_restore (kill burst, score). Не эмитит
# player_hit/enemy_killed, не сжигает i-frames. Использует тот же effective_ceiling
# что apply_kill_restore — Tier 7+ kill chain boost тоже распространяется на capture.
func apply_sphere_reward(amount: int = SPHERE_REWARD) -> void:
	if not is_alive:
		return
	var effective_ceiling: float = CAP_CEILING + ceiling_boost
	velocity_cap = minf(effective_ceiling, velocity_cap + float(amount))


func reset_for_run() -> void:
	velocity_cap = RESPAWN_CAP
	current_speed = 0.0
	drain_timer = 0.0
	is_draining = false
	i_frames_remaining = 0.0
	is_alive = true
	ceiling_boost = 0.0  # Свежий run без residual streak boost'а от прошлой смерти
	current_drain_threshold = THRESHOLD  # M9: spike step-up сбрасывается на новый run
	_cap_accumulator = 0.0
	_alive_time = 0.0
	# Lifecycle hook (M4): listeners (SpawnController, ScoreState, RunHud) зануляют
	# своё состояние на этом сигнале. Emit ПОСЛЕ reset state'а — listeners читают
	# уже свежий VelocityGate (например ScoreState проверяет velocity_cap для in-form bonus).
	Events.run_started.emit()


# Single source of truth для "игрок умер" не из drain'а (например fall off arena).
# Идемпотентен: повторные вызовы no-op'нутся, защита от double-emit player_died.
func force_kill() -> void:
	if not is_alive:
		return
	is_alive = false
	velocity_cap = 0.0
	ceiling_boost = 0.0  # Streak оборван смертью; KillChain.player_died тоже emit'ит exit, но идемпотентно safe
	if is_draining:
		is_draining = false
		Events.drain_stopped.emit()
	Events.player_died.emit()


# Возврат в меню (не смерть): тушим run-state, не эмитим player_died.
# Используется main_menu.gd._ready() после возврата из gameplay'а через
# pause → MAIN MENU, credits → MAIN MENU, или любой другой path.
# Идемпотентен: повторные вызовы no-op.
func end_run() -> void:
	is_alive = false
	velocity_cap = RESPAWN_CAP
	current_speed = 0.0
	drain_timer = 0.0
	if is_draining:
		is_draining = false
		Events.drain_stopped.emit()
	i_frames_remaining = 0.0
	ceiling_boost = 0.0
	current_drain_threshold = THRESHOLD
	_cap_accumulator = 0.0
	_alive_time = 0.0


# M9 magazine reload: списывает RELOAD_COST cap'а как сознательный tradeoff.
# Возвращает true если cost списан (reload разрешён), false если cap < RELOAD_COST
# (reload запрещён — игрок stuck без kill'а). Не эмитит player_hit (отличается от
# apply_hit), не сжигает i-frames. Если cap уйдёт в 0 — force_kill (симметрия с
# apply_hit hit-to-zero). Игрок не должен случайно «выжать» reload до смерти, но
# guard на cap < RELOAD_COST в player'е делает этот edge-case формально невозможным.
func apply_reload_cost() -> bool:
	if not is_alive:
		return false
	if velocity_cap < float(RELOAD_COST):
		return false
	velocity_cap = maxf(0.0, velocity_cap - float(RELOAD_COST))
	if velocity_cap <= 0.0:
		force_kill()
	return true


# Journey moving force: silent cap drain без player_hit emit (никакой vignette
# flash, никаких i-frames — фоговая угроза работает sustained, не per-jolt).
# Mirror apply_reload_cost pattern: direct decrement, force_kill при cap=0 для
# симметрии с apply_hit hit-to-zero. Идемпотентен по is_alive guard.
func apply_force_drain(amount: int) -> void:
	if not is_alive:
		return
	velocity_cap = maxf(0.0, velocity_cap - float(amount))
	if velocity_cap <= 0.0:
		force_kill()


# Kill Chain Tier 7+ entry: приподнимает effective ceiling. apply_kill_restore сразу
# подхватит на следующем kill'е через минимум(CAP_CEILING + boost, ...).
func set_ceiling_boost(boost: float) -> void:
	ceiling_boost = maxf(0.0, boost)


# Kill Chain Tier 7+ exit: возвращает потолок к CAP_CEILING. Если cap был приподнят
# выше CAP_CEILING во время стрика — clamp обратно к 100. Это intended: мы не
# «забираем» накопленное, а возвращаем нормальный потолок (next kill restore не
# поднимет выше 100 как обычно).
func clear_ceiling_boost() -> void:
	ceiling_boost = 0.0
	velocity_cap = minf(velocity_cap, CAP_CEILING)


func _physics_process(delta: float) -> void:
	if i_frames_remaining > 0.0:
		i_frames_remaining = maxf(0.0, i_frames_remaining - delta)

	if not is_alive:
		return

	# M9 conquest: накапливаем cap × dt и alive_time для avg_cap score formula.
	# Делаем здесь (а не в _process) чтобы pacing совпадал с drain logic — fixed
	# delta = устойчивый avg на разных FPS.
	_cap_accumulator += velocity_cap * delta
	_alive_time += delta

	# Drain timer: накапливаем время под threshold ТОЛЬКО до старта drain'а — после
	# того как drain активен, его роль (gate в drain phase) выполнена и расти ему
	# незачем (иначе float бы рос бесконечно во время затяжного drain).
	if speed_ratio() < current_drain_threshold:
		if not is_draining:
			drain_timer += delta
	else:
		if drain_timer > 0.0 or is_draining:
			drain_timer = 0.0
			if is_draining:
				is_draining = false
				Events.drain_stopped.emit()

	# Drain phase: tolerance кончился → tick'аем cap вниз.
	if drain_timer > TOLERANCE_BELOW_THRESHOLD:
		if not is_draining:
			is_draining = true
			Events.drain_started.emit()
		velocity_cap = maxf(0.0, velocity_cap - DRAIN_RATE * delta)
		if velocity_cap <= 0.0:
			is_alive = false
			is_draining = false
			Events.player_died.emit()
