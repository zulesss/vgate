class_name RunLoop extends Node

# M4 in-place restart loop. Заменяет M1 reload_current_scene (run_manager.gd)
# полностью in-place reset:
#   1. VelocityGate.reset_for_run() — emit'ит Events.run_started
#   2. SpawnController._on_run_started — чистит врагов + state
#   3. ScoreState._on_run_started — обнуляет current_score, run_time
#   4. Здесь: возвращаем игрока на spawn-position, обнуляем velocity
#
# In-place вместо reload_current_scene выгоднее: сохраняет NavMesh, FOV controller,
# debug-hud connection'ы — экономим ~500мс перезагрузки + сохраняем feel'овую
# непрерывность (vignette material остаётся живым, GPU pipeline warm).
#
# M9 conquest: run теперь time-based (120с). RunLoop отвечает за:
#   - Spike phase trigger в t=90 (drain threshold step-up до 0.45)
#   - Win condition в t=120 (Events.run_won → WinScreen)
# Время читается из VelocityGate.get_alive_time() — single source of truth с
# accumulator'ом cap_avg в самом gate'е.

const SPIKE_TRIGGER_TIME := 90.0
const RUN_DURATION := 120.0

@export var player_path: NodePath
@onready var player: Node = get_node_or_null(player_path)

var _spike_active: bool = false
var _won: bool = false


func _ready() -> void:
	# Первый старт run'а: reset_for_run() флипает VelocityGate.is_alive=true и
	# эмитит run_started — Player input разлоч'ивается, Sfx/MusicDirector
	# стартуют loop'ы. До ca9e4e5 дефолт is_alive=true маскировал это, но
	# теперь VelocityGate dormant by default → нужен явный init.
	VelocityGate.reset_for_run()
	Events.run_restart_requested.connect(_on_restart)
	Events.run_started.connect(_on_run_started)


func _process(_delta: float) -> void:
	if not VelocityGate.is_alive or _won:
		return
	var t: float = VelocityGate.get_alive_time()
	# Spike phase step-up: t≥90 → threshold 0.30 → 0.45. Idempotent через
	# _spike_active гард. Чистый data change, без player_hit emit'а — это
	# environmental/wave change, не damage event.
	if not _spike_active and t >= SPIKE_TRIGGER_TIME:
		_spike_active = true
		VelocityGate.current_drain_threshold = VelocityGate.SPIKE_THRESHOLD
	# Win condition: дожил до t≥120 → ARENA COMPLETE. Один раз через _won гард.
	if t >= RUN_DURATION:
		_won = true
		Events.run_won.emit()


func _on_run_started() -> void:
	# Reset state на каждый new run: spike может тригернуться заново, win-flag
	# сбрасывается чтобы restart после победы стартовал чистый.
	_spike_active = false
	_won = false


func _on_restart() -> void:
	# Reset gate state и emit run_started — все listener'ы (spawn, score) подхватят.
	VelocityGate.reset_for_run()
	# Player: respawn() если есть метод (расширяемая convention), иначе fallback —
	# teleport в (0,1,10) (start-position из main.tscn) + zero velocity.
	if player == null:
		push_warning("RunLoop: player_path не указывает на существующую ноду — restart без player reset")
		return
	if player.has_method("respawn"):
		player.respawn()
		return
	if player is Node3D:
		(player as Node3D).global_position = Vector3(0, 1, 10)
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
