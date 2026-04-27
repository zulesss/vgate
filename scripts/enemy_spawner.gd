class_name EnemySpawner extends Node

# M1 minimum spawner: один враг живёт на арене, после смерти — 1.5 сек wait и
# spawn на случайном Marker3D из группы "spawn_point". Полный ramp (Devil Daggers
# формула, multi-enemy) — M4.

const RESPAWN_DELAY := 1.5

@export var enemy_scene: PackedScene
@export var initial_spawn_position: Vector3 = Vector3(5.0, 0.9, -5.0)


func _ready() -> void:
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.run_restarted.connect(_on_run_restarted)
	# Parent (Main) ещё формирует children в _ready'е. Deferred = после frame'а.
	_spawn_initial.call_deferred()


func _on_run_restarted() -> void:
	# При reload_current_scene scene tree пересобирается → этот узел тоже новый,
	# initial_spawn вызовется через _ready. Ничего отдельного делать не надо.
	pass


func _on_enemy_killed(_restore: int, _pos: Vector3) -> void:
	var timer := get_tree().create_timer(RESPAWN_DELAY)
	await timer.timeout
	# Защита от reload во время задержки: если уже не в дереве — выходим.
	if not is_inside_tree():
		return
	_spawn_at_random_marker()


func _spawn_initial() -> void:
	if enemy_scene == null:
		push_warning("EnemySpawner: enemy_scene не задан")
		return
	var enemy := enemy_scene.instantiate()
	get_parent().add_child(enemy)
	enemy.global_position = initial_spawn_position


func _spawn_at_random_marker() -> void:
	if enemy_scene == null:
		return
	var markers := get_tree().get_nodes_in_group("spawn_point")
	if markers.is_empty():
		_spawn_initial()
		return
	var marker: Marker3D = markers[randi() % markers.size()]
	var enemy := enemy_scene.instantiate()
	get_parent().add_child(enemy)
	# Y из marker'а = 0 (M1_arena_layout), но нам нужен capsule center на 0.9.
	var spawn_pos := marker.global_position
	spawn_pos.y = 0.9
	enemy.global_position = spawn_pos
