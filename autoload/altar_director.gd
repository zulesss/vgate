class_name AltarDirectorNode extends Node

# Cathedral altar capture objective director (Arena C "Собор"). Параллельный axis
# к sphere/mark/journey objective'ам — активируется по group "objective_cathedral"
# на arena root. Driver спавна врагов + altar state machine.
#
# Spec (locked, см. milestone brief):
#   1. 4 altars (NW/NE/SE/SW), все active одновременно с run_started.
#   2. Capture: player в altar Area3D (3u radius placeholder, scene size 4×2×4)
#      4 секунды continuous + zero enemies в той же area → state=captured.
#   3. Enemy в зоне → state=contested + dwell timer reset.
#   4. Captured altar: spawn для этой зоны выключен (relief reward).
#   5. Spawn pressure: каждый uncaptured/contested altar спавнит врагов на
#      собственном spawn-interval (~3-5s) из 2 ассоциированных spawn-points.
#   6. 4/4 captured → 2s silence pause → boss spawn at BossSpawn marker.
#   7. Win: boss killed AND alive AND 4 captured → Events.run_won (RunLoop'у).
#   8. Fail: только drain death. No timer.
#
# State machine per altar:
#   0 = UNCAPTURED — dim red emissive (slow pulse), spawn'ит врагов
#   1 = CONTESTED — orange emissive (fast pulse), spawn'ит, dwell reset
#   2 = CAPTURED — gold emissive static, spawn off
#
# Altar→Top mesh mapping: arena scene имеет AltarArea_<XX> (4 штуки в группе
# "altar_zone") + Altar_<XX>_Top mesh (CSGBox3D, не в группе). Mapping по имени:
#   AltarArea_NW → Altar_NW_Top, etc. Выводим суффикс из area name (split "_").
#   Top находим в arena root через find_child("Altar_<suffix>_Top", true, false).
#
# Spawn-point pairing: каждой altar zone соответствуют 2 marker'а Spawn<XX>_1/_2
# (NW/NE/SE/SW). Lookup по имени marker'а в группе "spawn_point" — берём те
# которые startwith("Spawn<XX>_"). AltarDirector picks random of 2 per spawn cycle.
#
# Lifecycle:
#   _on_run_started → _active set по group, full reset, find altars/markers/top.
#   _process(delta) → state machine + spawn logic per altar (ранний return при
#                     not _active / not is_alive / boss phase pending).
#   altar capture → emit Events.altar_captured(index), apply_altar_reward, +1
#                   counter. Когда counter=4 → emit cathedral_phase_complete +
#                   schedule boss spawn в 2 сек (через timer-based флаг).
#   boss kill via Events.enemy_killed type="boss" → emit boss_killed (re-publish
#                   ради чистого contract'а — listener'ы могут слушать только
#                   boss_killed без знания про enemy_killed shape).

const ARENA_GROUP_CATHEDRAL := &"objective_cathedral"
const ALTAR_GROUP := &"altar_zone"
const SPAWN_POINT_GROUP := &"spawn_point"

# Capture timing
const CAPTURE_DWELL_TIME := 4.0
const ALTAR_COUNT := 4

# Spawn timing per altar (independent timer per zone)
const SPAWN_INTERVAL_BASE := 4.0
const SPAWN_INTERVAL_JITTER := 1.0
# Initial delay перед первым spawn'ом каждой zone (player должен успеть оглядеться).
const SPAWN_INITIAL_DELAY := 2.5

# Boss phase
const BOSS_SPAWN_DELAY := 2.0  # 2s silence pause после 4/4 captured
const BOSS_SPAWN_MARKER_NAME := &"BossSpawn"

# Visual emission colors (per spec)
const COLOR_UNCAPTURED := Color(1.0, 0.2, 0.2)
const COLOR_CONTESTED := Color(1.0, 0.5, 0.0)
const COLOR_CAPTURED := Color(1.0, 0.8, 0.2)
# Pulse params: slow для uncaptured (1.5s period), fast для contested (0.5s).
# Captured static (no tween — set energy=1.5 константой).
const PULSE_ENERGY_LOW := 0.5
const PULSE_ENERGY_HIGH := 1.5
const PULSE_PERIOD_SLOW := 1.5
const PULSE_PERIOD_FAST := 0.5
const PULSE_ENERGY_CAPTURED := 1.5

# Type weights per phase (number of captured altars). Same axis как
# spawn_controller _current_type_weights, но проще: пара anchors.
# Phase = 0..1 captured: melee + shooter heavy (no swarm — игрок ещё learns map).
# Phase 2+: swarm intro для finale pressure.
const TYPE_WEIGHTS_EARLY := {"melee": 0.55, "shooter": 0.40, "swarmling": 0.05}
const TYPE_WEIGHTS_LATE := {"melee": 0.35, "shooter": 0.30, "swarmling": 0.35}

const SWARM_GROUP_SIZE := 3

const MELEE_SCENE := preload("res://objects/melee.tscn")
const SHOOTER_SCENE := preload("res://objects/shooter.tscn")
const SWARMLING_SCENE := preload("res://objects/swarmling.tscn")
const BOSS_SCENE := preload("res://objects/boss.tscn")

# Y offset для spawn position (capsule center чтобы не провалиться в пол) —
# mirror SpawnController.SPAWN_Y.
const SPAWN_Y := 0.9


# Per-altar state. Index 0..3 соответствует order'у group("altar_zone") на момент
# _on_run_started — стабилен в пределах run'а (arena instance не меняется до
# restart'а, который reset'ит этот массив).
class AltarState:
	var area: Area3D
	var top_mesh: GeometryInstance3D
	var top_material: StandardMaterial3D
	var spawn_points: Array[Marker3D] = []
	var state: int = 0  # 0=uncaptured, 1=contested, 2=captured
	var dwell_timer: float = 0.0
	var spawn_timer: float = 0.0
	var pulse_phase: float = 0.0  # 0..1, для emission energy mod
	var index: int = 0


var _active: bool = false
var captured_count: int = 0
var _altars: Array[AltarState] = []
# Boss phase state machine:
#   _boss_phase_pending=true после 4/4 capture → ждём BOSS_SPAWN_DELAY → spawn boss
#   _boss_phase_active=true после spawn'а boss'а — гард против повторного spawn'а
#   _boss_killed=true когда Events.enemy_killed type="boss" прилетел
var _boss_phase_pending: bool = false
var _boss_phase_pending_timer: float = 0.0
var _boss_phase_active: bool = false
var _boss_killed: bool = false
var _cathedral_phase_complete_emitted: bool = false

# Spawn parent — Enemies node main scene'ы. Резолвим лениво на первом spawn'е,
# mirror sphere_director pattern. Если main scene не загружена (меню) — _try_spawn
# просто no-op'ит.
var _spawn_parent: Node = null


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	if not _active:
		return
	if not VelocityGate.is_alive:
		return

	# Boss spawn pending: ждём BOSS_SPAWN_DELAY сек тишины после 4/4 capture'а.
	# После timeout — spawn boss + emit boss_phase_started. Это ОТДЕЛЬНО от
	# altar tick'ов (они уже captured, spawn off, visuals static).
	if _boss_phase_pending and not _boss_phase_active:
		_boss_phase_pending_timer -= delta
		if _boss_phase_pending_timer <= 0.0:
			_spawn_boss()
		return  # До spawn'а boss'а altars в captured state'е, нечего тикать

	# Boss phase active: altars stay captured, no spawning. Только pulse
	# captured visuals (already static). Win check делается RunLoop'ом через
	# Events.boss_killed listener.
	if _boss_phase_active:
		_tick_visual_pulses(delta)
		return

	# Normal phase: tick capture state + spawning per altar.
	_tick_altar_states(delta)
	_tick_visual_pulses(delta)
	_tick_spawning(delta)


func _on_run_started() -> void:
	_active = not get_tree().get_nodes_in_group(ARENA_GROUP_CATHEDRAL).is_empty()
	# Full reset for every run — даже если не active (на случай переключения арен).
	_altars.clear()
	captured_count = 0
	_boss_phase_pending = false
	_boss_phase_pending_timer = 0.0
	_boss_phase_active = false
	_boss_killed = false
	_cathedral_phase_complete_emitted = false
	_spawn_parent = null
	if not _active:
		return

	_collect_altars()


# ────── Altar / spawn-point collection

func _collect_altars() -> void:
	# Find altars в group "altar_zone" — их 4 (NW/NE/SE/SW). Iteration order
	# зависит от scene load order; мы фиксируем index per-run и используем его
	# как stable identifier. Spawn_points lookup по prefix имени.
	var areas := get_tree().get_nodes_in_group(ALTAR_GROUP)
	var spawn_markers := get_tree().get_nodes_in_group(SPAWN_POINT_GROUP)

	for i in areas.size():
		var area := areas[i] as Area3D
		if area == null:
			continue
		var altar := AltarState.new()
		altar.area = area
		altar.index = _altars.size()
		altar.spawn_timer = SPAWN_INITIAL_DELAY + randf_range(0.0, 0.5)
		altar.pulse_phase = randf()  # desync pulses между altars
		altar.top_mesh = _find_altar_top(area)
		altar.top_material = _ensure_altar_material(altar.top_mesh)
		altar.spawn_points = _find_spawn_points_for_altar(area, spawn_markers)
		_apply_state_visual(altar, true)  # init colour without tween jitter
		_altars.append(altar)

	if _altars.size() != ALTAR_COUNT:
		push_warning(
			"AltarDirector: ожидалось %d altars в группе '%s', найдено %d. Cathedral spec ломается."
			% [ALTAR_COUNT, ALTAR_GROUP, _altars.size()]
		)


# Найти Altar_<suffix>_Top mesh для AltarArea_<suffix>. Suffix берём из имени
# Area3D после "AltarArea_" (e.g. "NW", "NE"). Mesh ищем через find_child от
# arena root — recursive lookup, owned=false (CSG nodes свои, scene их owner).
func _find_altar_top(area: Area3D) -> GeometryInstance3D:
	var area_name: String = str(area.name)
	var prefix := "AltarArea_"
	if not area_name.begins_with(prefix):
		push_warning("AltarDirector: altar area '%s' не имеет prefix'а '%s'" % [area_name, prefix])
		return null
	var suffix: String = area_name.substr(prefix.length())
	var top_name: String = "Altar_%s_Top" % suffix
	var arena_root: Node = _find_arena_root(area)
	if arena_root == null:
		return null
	var top := arena_root.find_child(top_name, true, false)
	if top == null:
		push_warning("AltarDirector: Altar Top '%s' не найден под arena root" % top_name)
		return null
	return top as GeometryInstance3D


# Arena root = первая ancestor, которая в группе "objective_cathedral".
func _find_arena_root(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.is_in_group(ARENA_GROUP_CATHEDRAL):
			return n
		n = n.get_parent()
	return null


# Material instance для Top mesh'а. Если на mesh'е StandardMaterial3D через
# .material override — duplicate'нём чтобы не делить с другими instance'ами
# (у CSGBox3D shared material даст visual flicker всех altars одновременно).
# Mat_altar_top — sub_resource scene'ы; duplicate даёт own copy.
func _ensure_altar_material(top: GeometryInstance3D) -> StandardMaterial3D:
	if top == null:
		return null
	# CSGBox3D имеет .material свойство. Material override на per-surface уровне
	# через get_active_material (если CSG mesh уже built). Самый robust path —
	# читаем .material напрямую.
	var src_mat: Material = null
	if top.has_method("get") and top.get("material") != null:
		src_mat = top.get("material") as Material
	if src_mat == null:
		# Fallback на surface override (если CSG ещё не built) — все равно вернём null.
		push_warning("AltarDirector: altar top '%s' без material — visual cue заблокирован" % top.name)
		return null
	var dup := src_mat.duplicate() as StandardMaterial3D
	if dup == null:
		return null
	dup.emission_enabled = true
	# Initial emission color уже uncaptured (red)
	dup.emission = COLOR_UNCAPTURED
	dup.emission_energy_multiplier = PULSE_ENERGY_LOW
	dup.albedo_color = COLOR_UNCAPTURED
	top.set("material", dup)
	return dup


# Найти 2 spawn marker'а для altar zone. Suffix = "NW"/"NE"/etc, marker имя
# начинается с "Spawn<suffix>_".
func _find_spawn_points_for_altar(area: Area3D, all_markers: Array) -> Array[Marker3D]:
	var area_name: String = str(area.name)
	var prefix := "AltarArea_"
	var result: Array[Marker3D] = []
	if not area_name.begins_with(prefix):
		return result
	var suffix: String = area_name.substr(prefix.length())
	var marker_prefix: String = "Spawn%s_" % suffix
	for m in all_markers:
		var marker := m as Marker3D
		if marker == null:
			continue
		if str(marker.name).begins_with(marker_prefix):
			result.append(marker)
	if result.is_empty():
		push_warning(
			"AltarDirector: не найдены spawn-points с prefix '%s' для altar '%s'"
			% [marker_prefix, area_name]
		)
	return result


# ────── State machine tick

func _tick_altar_states(delta: float) -> void:
	for altar in _altars:
		if altar.state == 2:
			continue  # captured, freeze
		var bodies: Array = altar.area.get_overlapping_bodies()
		var has_player := false
		var has_enemy := false
		for b in bodies:
			if not is_instance_valid(b):
				continue
			if b.is_in_group("player"):
				has_player = true
			elif b is EnemyBase or b.is_in_group("enemy"):
				has_enemy = true
		if has_enemy:
			# Contested — reset dwell timer, switch to contested visual.
			if altar.state != 1:
				altar.state = 1
				_apply_state_visual(altar, false)
			altar.dwell_timer = 0.0
			continue
		if has_player:
			# Pure player presence (no enemy) → tick dwell timer.
			altar.dwell_timer += delta
			if altar.dwell_timer >= CAPTURE_DWELL_TIME:
				_capture_altar(altar)
				continue
			# Pure player: считается uncaptured visual (slow red pulse), но dwell
			# тикает. Можно было бы добавить промежуточный progress visual, но
			# spec'е три state'а — UI/HUD progress bar делается отдельно (не в
			# scope этого milestone'а).
			if altar.state != 0:
				altar.state = 0
				_apply_state_visual(altar, false)
		else:
			# Empty zone — uncaptured visual, dwell decay (мгновенный reset, чтобы
			# игрок не "копил" half-progress оставив altar).
			if altar.state != 0:
				altar.state = 0
				_apply_state_visual(altar, false)
			altar.dwell_timer = 0.0


func _capture_altar(altar: AltarState) -> void:
	altar.state = 2
	altar.dwell_timer = 0.0
	captured_count += 1
	_apply_state_visual(altar, false)
	VelocityGate.apply_altar_reward()
	Events.altar_captured.emit(altar.index)
	# 4/4 — trigger boss phase. _cathedral_phase_complete_emitted guard на случай
	# одновременного capture'а двух altars в одном кадре (shouldn't happen — capture
	# requires 4s dwell — но defensive).
	if not _cathedral_phase_complete_emitted and captured_count >= ALTAR_COUNT:
		_cathedral_phase_complete_emitted = true
		_boss_phase_pending = true
		_boss_phase_pending_timer = BOSS_SPAWN_DELAY
		Events.cathedral_phase_complete.emit()


# ────── Visual

func _tick_visual_pulses(delta: float) -> void:
	for altar in _altars:
		if altar.top_material == null:
			continue
		if altar.state == 2:
			# Captured — static energy. Set если drift'нул (не должен, но cheap идемпотент).
			altar.top_material.emission_energy_multiplier = PULSE_ENERGY_CAPTURED
			continue
		var period: float = PULSE_PERIOD_SLOW if altar.state == 0 else PULSE_PERIOD_FAST
		altar.pulse_phase += delta / period
		if altar.pulse_phase >= 1.0:
			altar.pulse_phase = fmod(altar.pulse_phase, 1.0)
		# Sine-wave pulse 0..1, mapped в [PULSE_ENERGY_LOW, PULSE_ENERGY_HIGH].
		var s: float = (sin(altar.pulse_phase * TAU) * 0.5) + 0.5
		altar.top_material.emission_energy_multiplier = lerpf(
			PULSE_ENERGY_LOW, PULSE_ENERGY_HIGH, s
		)


# Set color emission/albedo по state'у. _initial=true → energy сразу low (чтобы
# не было spike при rebuild).
func _apply_state_visual(altar: AltarState, _initial: bool) -> void:
	if altar.top_material == null:
		return
	var color: Color = COLOR_UNCAPTURED
	match altar.state:
		1:
			color = COLOR_CONTESTED
		2:
			color = COLOR_CAPTURED
	altar.top_material.emission = color
	altar.top_material.albedo_color = color


# ────── Spawning (per-altar)

func _tick_spawning(delta: float) -> void:
	_resolve_spawn_parent()
	if _spawn_parent == null:
		return
	for altar in _altars:
		if altar.state == 2:
			continue  # captured altar — spawn off
		if altar.spawn_points.is_empty():
			continue
		altar.spawn_timer -= delta
		if altar.spawn_timer > 0.0:
			continue
		# Pick spawn point + type, instantiate.
		_spawn_for_altar(altar)
		altar.spawn_timer = SPAWN_INTERVAL_BASE + randf_range(-SPAWN_INTERVAL_JITTER, SPAWN_INTERVAL_JITTER)


func _spawn_for_altar(altar: AltarState) -> void:
	var marker := altar.spawn_points[randi() % altar.spawn_points.size()]
	var pos := marker.global_position
	pos.y = SPAWN_Y
	var t: String = _pick_type_for_phase()
	if t == "swarmling":
		# Group of SWARM_GROUP_SIZE с tiny ring offset (mirror spawn_controller).
		for i in SWARM_GROUP_SIZE:
			var angle: float = TAU * float(i) / float(SWARM_GROUP_SIZE) + randf() * 0.2
			var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.6
			_instantiate_enemy_at(pos + offset, "swarmling")
	else:
		_instantiate_enemy_at(pos, t)


func _pick_type_for_phase() -> String:
	# Phase = captured_count. Early (0-1) — melee/shooter. Late (2-3) — swarm intro.
	# Single dict pick по weighted random, no sub-caps (cathedral simpler than M4).
	var weights: Dictionary = TYPE_WEIGHTS_EARLY if captured_count < 2 else TYPE_WEIGHTS_LATE
	var total: float = 0.0
	for v in weights.values():
		total += float(v)
	var r: float = randf() * total
	var acc: float = 0.0
	for k in weights.keys():
		acc += float(weights[k])
		if r < acc:
			return str(k)
	return "melee"


func _instantiate_enemy_at(world_pos: Vector3, type: String) -> void:
	var scene: PackedScene = MELEE_SCENE
	match type:
		"shooter":
			scene = SHOOTER_SCENE
		"swarmling":
			scene = SWARMLING_SCENE
	var enemy = scene.instantiate()
	# is_spawning ставим ДО add_child (mirror spawn_controller pattern) — иначе
	# первый physics-кадр AI отработает на frozen frame'е.
	if "is_spawning" in enemy:
		enemy.is_spawning = true
	_spawn_parent.add_child(enemy)
	(enemy as Node3D).global_position = world_pos
	# Без telegraph fade (упрощение для cathedral — врагов спавнит altar director
	# на видных marker'ах, telegraph fade сложно тестировать через 4 параллельные
	# зоны). Альтернатива в будущем — копировать spawn_controller telegraph поверх.
	if "is_spawning" in enemy:
		enemy.is_spawning = false
	Events.enemy_spawned.emit(enemy)


func _resolve_spawn_parent() -> void:
	if _spawn_parent != null and is_instance_valid(_spawn_parent):
		return
	# Main scene имеет node "Enemies" — spawn_controller туда же кладёт. Mirror.
	var tree := get_tree()
	if tree == null:
		return
	var current := tree.current_scene
	if current == null:
		return
	var enemies := current.get_node_or_null("Enemies")
	if enemies != null:
		_spawn_parent = enemies
	else:
		# Fallback на current_scene root — work if main без Enemies контейнера.
		_spawn_parent = current


# ────── Boss phase

func _spawn_boss() -> void:
	if _boss_phase_active:
		return
	_boss_phase_active = true
	_boss_phase_pending = false
	_resolve_spawn_parent()
	if _spawn_parent == null:
		push_warning("AltarDirector: spawn parent null on boss spawn — cathedral run будет зависшим")
		return
	# Find BossSpawn marker on cathedral arena. Searching from arena root by name.
	var marker_pos := _find_boss_spawn_position()
	var boss := BOSS_SCENE.instantiate()
	if "is_spawning" in boss:
		boss.is_spawning = true
	_spawn_parent.add_child(boss)
	(boss as Node3D).global_position = marker_pos
	if "is_spawning" in boss:
		boss.is_spawning = false
	Events.boss_phase_started.emit()
	Events.enemy_spawned.emit(boss)


func _find_boss_spawn_position() -> Vector3:
	# Search cathedral arena instance for BossSpawn marker. Arena root в группе
	# objective_cathedral; находим первый, читаем child by name.
	var roots := get_tree().get_nodes_in_group(ARENA_GROUP_CATHEDRAL)
	if roots.is_empty():
		return Vector3.ZERO
	var arena: Node = roots[0]
	var marker := arena.find_child(str(BOSS_SPAWN_MARKER_NAME), true, false) as Marker3D
	if marker == null:
		push_warning("AltarDirector: BossSpawn marker не найден — boss spawn at origin")
		return Vector3.ZERO
	var pos := marker.global_position
	pos.y = SPAWN_Y
	return pos


func _on_enemy_killed(_restore: int, _pos: Vector3, type: String) -> void:
	if not _active:
		return
	if type != "boss":
		return
	if _boss_killed:
		return
	_boss_killed = true
	# Re-publish как dedicated signal — RunLoop / любые listener'ы могут подписаться
	# на boss_killed без знания про enemy_killed shape.
	Events.boss_killed.emit()
