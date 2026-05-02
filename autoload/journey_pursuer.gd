class_name JourneyPursuerNode extends Node

# M10 Journey Pkg C — rear pursuer waves. Когда player пересекает milestone
# трешхолд (Area3D на входах в R2/R3/R4 → emit Events.milestone_crossed(index))
# — мы инстанцируем N свармлингов в start corridor (z≈5..10), x=±2 jitter,
# under Main/Enemies parent. Pacing pressure без подъёма enemy stats: рой просто
# догоняет, заставляя player'а не останавливаться.
#
# Idempotency: каждый milestone index срабатывает ровно один раз за run.
# Tracked в _milestones_fired dict; full reset на Events.run_started (mirrors
# SphereDirector / MarkDirector pattern).
#
# Spawn parent: Main/Enemies node (same как SpawnController spawns'ы) — это
# гарантирует что SpawnController._on_run_started()'s cleanup loop (queue_free
# всех EnemyBase children) очистит pursuer'ов на restart. Pre-placed defenders
# в arena scene live под Defenders/, не Enemies — НЕ затрагиваются.
#
# Active gate: spawn'аем только если current arena в группе objective_journey
# (mirrors SphereDirector ARENA_GROUP_SPHERES gating). Если игрок умирает /
# выигрывает до пересечения milestone — signal не emit'ится, no-op.

const ARENA_GROUP_JOURNEY := &"objective_journey"
const SWARMLING_SCENE: PackedScene = preload("res://objects/swarmling.tscn")
const SPAWN_Y := 0.9
const SPAWN_Z_MIN := 5.0
const SPAWN_Z_MAX := 10.0
const SPAWN_X_JITTER := 2.0

# {index → swarmling count}. R2 entry → 3, R3 → 4, R4 → 5 (нарастающий рой).
const WAVE_COUNTS := {2: 3, 3: 4, 4: 5}

var _milestones_fired: Dictionary = {}
var _spawn_parent: Node = null
var _active: bool = false


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.milestone_crossed.connect(_on_milestone_crossed)


func _on_run_started() -> void:
	_milestones_fired.clear()
	_active = not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty()
	# Drop spawn_parent cache — main scene reload даёт fresh Enemies node.
	_spawn_parent = null


func _on_milestone_crossed(index: int) -> void:
	if not _active:
		return
	if _milestones_fired.get(index, false):
		return
	if not VelocityGate.is_alive:
		return
	_milestones_fired[index] = true
	var count: int = int(WAVE_COUNTS.get(index, 0))
	if count <= 0:
		push_warning("JourneyPursuer: unknown milestone index %d, skip spawn" % index)
		return
	_spawn_wave(count)


func _spawn_wave(count: int) -> void:
	_resolve_spawn_parent()
	if _spawn_parent == null:
		push_warning("JourneyPursuer: spawn parent (Main/Enemies) not found, skip wave")
		return
	for i in count:
		var enemy: Node3D = SWARMLING_SCENE.instantiate() as Node3D
		# is_spawning bypass'ит первый _physics_process tick'а (см. EnemyBase) —
		# даём ноде дойти до глобальной позиции до того как AI начнёт двигаться.
		if "is_spawning" in enemy:
			enemy.is_spawning = true
		_spawn_parent.add_child(enemy)
		enemy.global_position = _pick_spawn_position()
		# Снимаем guard сразу после позиционирования. Telegraph fade у pursuer'ов
		# не делаем — visual surprise irrelevant в start corridor где игрок не
		# смотрит назад в момент спавна.
		if "is_spawning" in enemy:
			enemy.is_spawning = false
		Events.enemy_spawned.emit(enemy)


func _pick_spawn_position() -> Vector3:
	var x: float = randf_range(-SPAWN_X_JITTER, SPAWN_X_JITTER)
	var z: float = randf_range(SPAWN_Z_MIN, SPAWN_Z_MAX)
	return Vector3(x, SPAWN_Y, z)


func _resolve_spawn_parent() -> void:
	if _spawn_parent != null and is_instance_valid(_spawn_parent):
		return
	var tree := get_tree()
	if tree == null:
		return
	var current := tree.current_scene
	if current == null:
		return
	# Main scene: Enemies child хранит spawn'ы (см. main.tscn). Если структура
	# изменится — fallback на current_scene root (SpawnController использует
	# get_parent() для self-located Enemies — здесь напрямую узлом).
	var enemies := current.get_node_or_null("Enemies")
	if enemies != null:
		_spawn_parent = enemies
	else:
		_spawn_parent = current
