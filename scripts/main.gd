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

@export var arena_scene: PackedScene = preload("res://scenes/arenas/arena_c_cathedral.tscn")

# Кэш текущего arena instance для re-instantiation на restart. Pre-placed
# defenders в arena scene (под Defenders/) на первом run'е queue_free'ятся
# при kill'ах — на restart их нужно вернуть как фрешо инстансы. Делаем
# через free()+add_child() нового инстанса; вызывается из RunLoop._on_restart
# СИНХРОННО до VelocityGate.reset_for_run() чтобы listener'ы run_started
# (SpawnController, Sphere/Mark директора, RunLoop._on_run_started) уже
# видели новые группы (player_start / spawn_point / objective_journey).
var _arena_node: Node = null


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
	_arena_node = arena_scene.instantiate()
	add_child(_arena_node)


# Restart-time arena reset. Вызывается из RunLoop._on_restart СИНХРОННО до
# VelocityGate.reset_for_run() — порядок критичен: listener'ы run_started
# (SpawnController, директора) должны видеть свежие Marker3D'ы / pre-placed
# defenders, а не старые (уже удалённые / частично queue_free'нутые).
#
# Pattern: remove_child + queue_free старого + add_child нового. remove_child
# выкидывает старый из дерева СИНХРОННО (значит группы player_start/
# spawn_point/objective_journey/enemy из него уйдут до того, как мы запросим
# их у tree). queue_free() добивает память на следующем idle frame'е.
func reinstantiate_arena() -> void:
	if arena_scene == null:
		push_error("Main: arena_scene не задан — re-instantiate skipped")
		return
	if _arena_node != null and is_instance_valid(_arena_node):
		remove_child(_arena_node)
		_arena_node.queue_free()
	_arena_node = arena_scene.instantiate()
	add_child(_arena_node)


# Initial player positioning по PlayerStart Marker3D из активной арены.
# Делаем в _ready() (а не в _enter_tree()) чтобы Player.tscn успел отработать
# свой _ready и rotation_target проинициализировался — иначе наш set перетрётся.
# Restart-loop reposition'ит игрок RunLoop._on_restart — этот хук только
# для первого спавна сессии.
func _ready() -> void:
	var player: Node = get_node_or_null("Player")
	if player == null:
		return
	PlayerSpawn.teleport_to_start(player, get_tree())
