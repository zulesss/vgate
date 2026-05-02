class_name Main extends Node3D

# M9 arena swap host. Раньше arena geometry лежала inline в main.tscn (40×40 +
# CoverC1/C2/C3). Теперь это отдельная scene через @export — для swap'а между
# arena_b_plac (default) и _legacy_40x40 (rollback) через Inspector.
#
# Контракт arena_scene:
#   1. Root — Node3D в группе "navigation_geometry" (парсится NavMesh'ем)
#   2. Внутри: CSGBox'ы + NavigationRegion3D + NavBaker + SpawnPoints/S* Marker3D'ы
#   3. Marker3D'ы в группе "spawn_point" — SpawnController подхватит их сам

@export var arena_scene: PackedScene = preload("res://scenes/arenas/arena_b_plac.tscn")


func _ready() -> void:
	if arena_scene == null:
		push_error("Main: arena_scene не задан — арена не будет инстанциирована")
		return
	add_child(arena_scene.instantiate())
