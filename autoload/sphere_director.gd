class_name SphereDirectorNode extends Node

# M9 Hot Zones — sphere spawn director (autoload).
#
# Spawn schedule:
#   - 25 sphere'ов всего за 120с run'а
#   - First spawn t≈3 (let player settle), последующие через 4.67с ± 1с jitter
#   - Last spawn t≈115 (last expire ~122 — overhang acceptable; sphere queue_free
#     сама когда run закончится через _on_run_started если restart)
#   - Stop when total_spawned >= TOTAL_SPHERES
#
# Slot positions: 11 spots (slot_1 центр + 10 по арене 50×50 Arena B).
# Anti-cluster: при выборе нового slot'а исключаем те, что в радиусе ANTI_CLUSTER_DIST
# от _last_spawn_pos. Не cumulative — только last (per spec).
#
# Capture tracking: captured_count++ on Events.sphere_captured. Когда достигает
# CAPTURE_TARGET (20) — emit Events.objective_complete (один раз).
#
# Lifecycle: Events.run_started — full reset (counter, schedule, free все live spheres).
# VelocityGate.is_alive=false (death/win) — пауза spawn'а (без despawn — death screen
# сам остановит run, sphere'ы доживают свой lifetime естественно).

const TOTAL_SPHERES := 25
const CAPTURE_TARGET := 20
const FIRST_SPAWN_TIME := 3.0
const LAST_SPAWN_TIME := 115.0
const SPAWN_JITTER := 1.0
const ANTI_CLUSTER_DIST := 8.0
const SPHERE_Y_CAPTURE := 1.0  # Area3D capture-height (mesh поднят на VISUAL_Y_OFFSET в sphere.gd)

const SPHERE_SCENE := preload("res://objects/sphere.tscn")

# Arena B 50×50 slot positions (per brief). Y=1.0 capture-height.
const SLOT_POSITIONS: Array[Vector3] = [
	Vector3(0, 1, 0),         # slot_1 center
	Vector3(15, 1, 5),        # slot_2 E inner
	Vector3(-15, 1, 5),       # slot_3 W inner
	Vector3(5, 1, 15),        # slot_4 S inner
	Vector3(5, 1, -15),       # slot_5 N inner
	Vector3(-15, 1, -5),      # slot_6 W inner mirror
	Vector3(15, 1, -5),       # slot_7 E inner mirror
	Vector3(12, 1, 12),       # slot_8 SE diagonal
	Vector3(-12, 1, 12),      # slot_9 SW diagonal
	Vector3(-12, 1, -12),     # slot_10 NW diagonal
	Vector3(12, 1, -12),      # slot_11 NE diagonal
]

var captured_count: int = 0
var total_spawned: int = 0
var _run_time: float = 0.0
var _next_spawn_time: float = 0.0
var _last_spawn_pos: Vector3 = Vector3.INF  # INF на старте → anti-cluster не блокирует первый spawn
var _objective_complete_emitted: bool = false
var _live_spheres: Array[Node] = []

# Parent для instantiated sphere'ов. Лениво находим Main scene'у. Если main
# нет (в menu / при load'е) — spawn просто не произойдёт (early-return).
var _spawn_parent: Node = null


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.sphere_captured.connect(_on_sphere_captured)
	# sphere_expired не учитывается в captured_count, но подписку держим если
	# понадобится statistic'а для death/win screen'а (миссы). Пока — no-op listener
	# на случай чтобы signal не висел без subscriber'ов в логе.


func _process(delta: float) -> void:
	if not VelocityGate.is_alive:
		return
	if total_spawned >= TOTAL_SPHERES:
		return
	_run_time += delta
	if _run_time >= _next_spawn_time:
		_try_spawn()
		_schedule_next()


func _on_run_started() -> void:
	# Full reset на каждый new run (включая restart после death/win).
	captured_count = 0
	total_spawned = 0
	_run_time = 0.0
	_next_spawn_time = FIRST_SPAWN_TIME
	_last_spawn_pos = Vector3.INF
	_objective_complete_emitted = false
	# Free любые живые sphere'ы из предыдущего run'а (если игрок умер/выиграл с активными
	# sphere'ами на арене). Defensive: queue_free безопасен на already-freed nodes
	# через is_instance_valid гард.
	for s in _live_spheres:
		if is_instance_valid(s):
			s.queue_free()
	_live_spheres.clear()


func _try_spawn() -> void:
	_resolve_spawn_parent()
	if _spawn_parent == null:
		# Main scene не загружена — spawn skip, total_spawned не инкрементим
		# (на следующем тике попробуем снова после _schedule_next).
		return
	var pos: Vector3 = _pick_slot_position()
	var sphere: Node3D = SPHERE_SCENE.instantiate()
	_spawn_parent.add_child(sphere)
	sphere.global_position = pos
	_live_spheres.append(sphere)
	_last_spawn_pos = pos
	total_spawned += 1


func _schedule_next() -> void:
	if total_spawned >= TOTAL_SPHERES:
		return
	# Average interval = (LAST_SPAWN_TIME - FIRST_SPAWN_TIME) / (TOTAL_SPHERES - 1)
	# = 112 / 24 ≈ 4.67с. Spawn'ов после первого: TOTAL_SPHERES-1=24 интервала.
	# Jitter ±SPAWN_JITTER рандомизирует каждый interval независимо (без cumulative
	# drift'а, потому что schedule считаем как _run_time + interval, а не как
	# fixed schedule).
	var avg_interval: float = (LAST_SPAWN_TIME - FIRST_SPAWN_TIME) / float(TOTAL_SPHERES - 1)
	var jitter: float = randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	_next_spawn_time = _run_time + avg_interval + jitter


func _pick_slot_position() -> Vector3:
	# Anti-cluster: исключаем slots в радиусе ANTI_CLUSTER_DIST от _last_spawn_pos.
	# Если все slots блокированы (теоретически невозможно при 11 slots / dist=8u
	# на 50×50 арене — diagonals друг от друга >24u) — fallback на чистый random.
	var eligible: Array[Vector3] = []
	for slot in SLOT_POSITIONS:
		if _last_spawn_pos == Vector3.INF or slot.distance_to(_last_spawn_pos) >= ANTI_CLUSTER_DIST:
			eligible.append(slot)
	if eligible.is_empty():
		return SLOT_POSITIONS[randi() % SLOT_POSITIONS.size()]
	return eligible[randi() % eligible.size()]


func _resolve_spawn_parent() -> void:
	if _spawn_parent != null and is_instance_valid(_spawn_parent):
		return
	# Main scene root — first child of root который НЕ autoload. Используем same
	# pattern как get_tree().current_scene.
	var tree := get_tree()
	if tree == null:
		return
	_spawn_parent = tree.current_scene


func _on_sphere_captured(_pos: Vector3) -> void:
	captured_count += 1
	if not _objective_complete_emitted and captured_count >= CAPTURE_TARGET:
		_objective_complete_emitted = true
		Events.objective_complete.emit()
