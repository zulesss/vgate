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
# Slot positions: externalized в arena scene через group "sphere_slot" (Marker3D'ы).
# Каждая арена задаёт свои slots — топология/размер арен различается, hardcoded
# 50×50 positions ломались в arena A 26×26. Director собирает slot world-positions
# в _ready'е через get_nodes_in_group, кеширует в _slot_positions. Если арена не
# поставила Marker3D'ы — spawn заблокирован (warning + early-return в _try_spawn).
# Anti-cluster: при выборе нового slot'а исключаем те, что в радиусе ANTI_CLUSTER_DIST
# от _last_spawn_pos. Не cumulative — только last (per spec).
#
# Capture tracking: captured_count++ on Events.sphere_captured. Когда достигает
# CAPTURE_TARGET (15) — emit Events.objective_complete (один раз).
#
# Lifecycle: Events.run_started — full reset (counter, schedule, free все live spheres).
# VelocityGate.is_alive=false (death/win) — пауза spawn'а (без despawn — death screen
# сам остановит run, sphere'ы доживают свой lifetime естественно).

const TOTAL_SPHERES := 25
const CAPTURE_TARGET := 15
const FIRST_SPAWN_TIME := 3.0
const LAST_SPAWN_TIME := 115.0
const SPAWN_JITTER := 1.0
const ANTI_CLUSTER_DIST := 8.0

const SPHERE_SCENE := preload("res://objects/sphere.tscn")

# Slot positions из scene'ы — собираются лениво при первом spawn'е (см.
# _ensure_slots_loaded). _ready'е делать нельзя — autoload ready'ит ДО
# main scene'ы, group ещё пуста.
var _slot_positions: Array[Vector3] = []

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
	# Drop slot cache: при reload_current_scene новая arena instance даёт
	# новые Marker3D'ы. Re-collect через _ensure_slots_loaded на первом spawn'е.
	_slot_positions.clear()
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
	_ensure_slots_loaded()
	if _slot_positions.is_empty():
		# Arena не предоставила Marker3D'ы в группе "sphere_slot" — spawn заблокирован.
		# Warning emit'ится в _ensure_slots_loaded на каждой попытке (раз в spawn-interval
		# ~4.67с, не на каждый тик). Defensive — каждая arena scene должна иметь slots.
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
	# Если все slots блокированы (на тесных аренах типа A 26×26 это возможнее) —
	# fallback на чистый random.
	var eligible: Array[Vector3] = []
	for slot in _slot_positions:
		if _last_spawn_pos == Vector3.INF or slot.distance_to(_last_spawn_pos) >= ANTI_CLUSTER_DIST:
			eligible.append(slot)
	if eligible.is_empty():
		return _slot_positions[randi() % _slot_positions.size()]
	return eligible[randi() % eligible.size()]


func _ensure_slots_loaded() -> void:
	if not _slot_positions.is_empty():
		return
	var markers := get_tree().get_nodes_in_group("sphere_slot")
	if markers.is_empty():
		# Arena не настроена — _try_spawn'ы будут no-op до restart'а с правильной ареной.
		# Без _slot_positions.append не помечаем "loaded", на следующих тиках
		# повторим попытку (на случай deferred arena instantiation).
		push_warning("SphereDirector: no nodes in 'sphere_slot' group — sphere spawn заблокирован")
		return
	for n in markers:
		var m := n as Marker3D
		if m == null:
			continue
		_slot_positions.append(m.global_position)


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
	# Cap reward: каждый capture +SPHERE_REWARD к velocity_cap (clamp к effective ceiling
	# делается внутри apply_sphere_reward). Через VelocityGate API — не дублируем
	# clamp logic здесь, single source of truth для cap mutations.
	VelocityGate.apply_sphere_reward()
	if not _objective_complete_emitted and captured_count >= CAPTURE_TARGET:
		_objective_complete_emitted = true
		Events.objective_complete.emit()
