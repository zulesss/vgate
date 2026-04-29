class_name VelocityGateState extends Node

# Главный state hook'а. Все числа здесь — источник правды (см. docs/systems/M1_numbers.md).
# Player только сообщает current_speed, EnemyBase подклассы зовут apply_hit/apply_kill_restore,
# DebugHud только читает. Единственный owner state: этот autoload.

const BASE_WALK_SPEED := 8.0
const CAP_CEILING := 100.0
const RESPAWN_CAP := 80.0
const THRESHOLD := 0.3
const TOLERANCE_BELOW_THRESHOLD := 2.5
const DRAIN_RATE := 15.0
const SHOOTER_PENALTY := 10
const MELEE_PENALTY := 20
const KILL_RESTORE := 25
const I_FRAMES_AFTER_HIT := 0.3

var velocity_cap: float = RESPAWN_CAP
var current_speed: float = 0.0
var drain_timer: float = 0.0
var is_draining: bool = false
var i_frames_remaining: float = 0.0
var is_alive: bool = false  # Default false: VelocityGate dormant в меню. reset_for_run() флипает в true при старте run'а, end_run() возвращает false при возврате в меню.


func max_speed_at_cap() -> float:
	return BASE_WALK_SPEED * (velocity_cap / 100.0)


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
	Events.player_hit.emit(penalty)


func apply_kill_restore(pos: Vector3, type: String = "melee") -> void:
	if not is_alive:
		return
	velocity_cap = minf(CAP_CEILING, velocity_cap + float(KILL_RESTORE))
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


func reset_for_run() -> void:
	velocity_cap = RESPAWN_CAP
	current_speed = 0.0
	drain_timer = 0.0
	is_draining = false
	i_frames_remaining = 0.0
	is_alive = true
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


func _physics_process(delta: float) -> void:
	if i_frames_remaining > 0.0:
		i_frames_remaining = maxf(0.0, i_frames_remaining - delta)

	if not is_alive:
		return

	# Drain timer: накапливаем время под threshold ТОЛЬКО до старта drain'а — после
	# того как drain активен, его роль (gate в drain phase) выполнена и расти ему
	# незачем (иначе float бы рос бесконечно во время затяжного drain).
	if speed_ratio() < THRESHOLD:
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
