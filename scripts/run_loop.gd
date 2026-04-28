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

@export var player_path: NodePath
@onready var player: Node = get_node_or_null(player_path)


func _ready() -> void:
	Events.run_restart_requested.connect(_on_restart)


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
