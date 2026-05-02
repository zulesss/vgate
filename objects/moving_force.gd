class_name MovingForce extends Node3D

# Journey level moving fog force (Arena C). Sweeps forward (+Z) at constant speed
# from start corridor to R4 entry, draining player cap on touch and silently
# absorbing missed enemies (без kill burst, без enemy_killed emit).
#
# Lifecycle:
#   - На run_started: reset position to scene start (cached from initial transform),
#     idle (visible=false, monitoring=false), start ACTIVATION_DELAY таймер.
#   - После delay: visible=true, monitoring=true, движение начинается (+Z по dt).
#   - На position.z >= STOP_Z: deactivate (visible=false, monitoring=false), движение стоп.
#
# Player overlap → drain accumulator. Каждую секунду overlap'а списывает
# DRAIN_PER_SECOND cap'а через VelocityGate.apply_force_drain (не apply_hit —
# silent damage без vignette/player_hit emit).
# Enemy overlap → queue_free без die() и без Events.enemy_killed.emit (silent absorb).

const STOP_Z := 147.0
const SPEED := 4.0  # u/s, +Z direction
const ACTIVATION_DELAY := 3.0  # сек grace period после run_started
const DRAIN_PER_SECOND := 10  # cap per second пока player в overlap

@onready var area: Area3D = $ForceArea
@onready var visual: CSGBox3D = $ForceVisual

var _start_position: Vector3
var _active: bool = false
var _drain_accumulator: float = 0.0
var _player_overlapping: bool = false
var _activation_timer: float = 0.0
var _pending_activation: bool = false


func _ready() -> void:
	# Cache start position from scene transform — single source of truth.
	# Scene places node at desired start (e.g. (0, 2, -10) в arena_c_journey.tscn).
	_start_position = position
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	Events.run_started.connect(_on_run_started)
	# Initial state — idle до первого run_started. Журney scene re-instantiate'ится
	# на restart (Pkg A b7ee067), так что _ready всегда стартует свежий run.
	_reset_to_idle()
	_pending_activation = true


func _process(delta: float) -> void:
	# Activation delay phase
	if _pending_activation:
		_activation_timer += delta
		if _activation_timer >= ACTIVATION_DELAY:
			_activate()
		return

	if not _active:
		return

	# Movement
	position.z += SPEED * delta
	if position.z >= STOP_Z:
		position.z = STOP_Z
		_deactivate()
		return

	# Drain tick: accumulator > 1.0 → списываем DRAIN_PER_SECOND, reset.
	# Идёт ровно по wall-clock через delta accumulation, независимо от FPS.
	if _player_overlapping:
		_drain_accumulator += delta
		while _drain_accumulator >= 1.0:
			_drain_accumulator -= 1.0
			VelocityGate.apply_force_drain(DRAIN_PER_SECOND)


func _reset_to_idle() -> void:
	position = _start_position
	_active = false
	_pending_activation = false
	_activation_timer = 0.0
	_drain_accumulator = 0.0
	_player_overlapping = false
	visual.visible = false
	area.monitoring = false


func _activate() -> void:
	_pending_activation = false
	_active = true
	visual.visible = true
	area.monitoring = true


func _deactivate() -> void:
	_active = false
	_player_overlapping = false
	_drain_accumulator = 0.0
	visual.visible = false
	area.monitoring = false


func _on_run_started() -> void:
	# Defensive: arena re-instantiate handles fresh state, но если scene не
	# пере-инстанцирована (например debug reload) — корректно reset'имся вручную.
	_reset_to_idle()
	_pending_activation = true


func _on_body_entered(body: Node) -> void:
	if not _active:
		return
	if body.is_in_group("player"):
		_player_overlapping = true
		return
	if body.is_in_group("enemy"):
		# Silent absorb: queue_free без die() (который бы emit'нул enemy_killed
		# через kill burst path). Просто убираем node из дерева.
		body.queue_free()


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_overlapping = false
