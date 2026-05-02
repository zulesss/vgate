class_name Main extends Node3D

# M9 arena swap host. Раньше arena geometry лежала inline в main.tscn (40×40 +
# CoverC1/C2/C3). Теперь это отдельная scene через @export — для swap'а между
# arena_c_shaft (default) / arena_a_camera / arena_b_plac / _legacy_40x40
# (rollback) через Inspector.
#
# Контракт arena_scene:
#   1. Root — Node3D в группе "navigation_geometry" (парсится NavMesh'ем)
#   2. Внутри: CSGBox'ы + NavigationRegion3D + NavBaker + SpawnPoints/S* Marker3D'ы
#   3. Marker3D'ы в группе "spawn_point" — SpawnController подхватит их сам

@export var arena_scene: PackedScene = preload("res://scenes/arenas/arena_c_journey.tscn")


# Инстанцируем arena в _enter_tree(), а НЕ в _ready(). Причина — Godot
# вызывает _ready() bottom-up: child'ы (включая SpawnController внутри Enemies)
# получают _ready ДО parent'а Main. SpawnController._ready() делает
# get_tree().get_nodes_in_group("spawn_point") — если arena ещё не в дереве,
# группа пуста и spawn'ы блокируются навсегда (post-M9 regression).
# _enter_tree() запускается top-down — Marker3D'ы арены попадают в группу
# ДО того как Spawner откроет глаза.
func _enter_tree() -> void:
	if arena_scene == null:
		push_error("Main: arena_scene не задан — арена не будет инстанциирована")
		return
	add_child(arena_scene.instantiate())
