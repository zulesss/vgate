class_name AltarDirectorNode extends Node

# Cathedral altar capture objective director (Arena C "Собор"). Параллельный axis
# к sphere/mark/journey objective'ам — активируется по group "objective_cathedral"
# на arena root. Driver спавна врагов + altar state machine.
#
# Spec (locked, см. milestone brief):
#   1. 4 altars (NW/NE/SE/SW), все active одновременно с run_started.
#   2. Capture: player в altar Area3D (~5u radius disc footprint, scene size 10×2×10)
#      4 секунды continuous + zero enemies в той же area → state=captured.
#   3. Enemy + player в зоне → state=contested + dwell timer reset.
#   4. Captured altar: spawn для этой зоны выключен (relief reward).
#   5. Spawn pressure: каждый non-captured altar спавнит врагов на
#      собственном spawn-interval (~3-5s) из 2 ассоциированных spawn-points.
#   6. 4/4 captured → 2s silence pause → boss spawn at BossSpawn marker.
#   7. Win: boss killed AND alive AND 4 captured → Events.run_won (RunLoop'у).
#   8. Fail: только drain death. No timer.
#
# State machine per altar:
#   0 = UNCAPTURED — red emissive (slow pulse), spawn'ит врагов, no dwell
#   1 = CAPTURING — yellow emissive (medium pulse), spawn'ит, dwell тикает
#   2 = CONTESTED — red emissive (fast pulse), spawn'ит, dwell reset (signal "враги в зоне")
#   3 = CAPTURED — green emissive static, spawn off
# Note: state IDs стабильны с предыдущей реализации только частично — старый
# CONTESTED был index 1 (теперь CAPTURING), captured переехал с 2 на 3.
# Listeners (run_hud) знают только captured_count + altar_captured(index) — не
# зависят от state ID, поэтому safe.
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

# Visual emission colors (per spec — red/yellow/green semantics).
# UNCAPTURED + CONTESTED share red color: signal "не прогрессирует / прогресс
# прерван". Distinguished by pulse speed (slow vs fast).
const COLOR_UNCAPTURED := Color(1.0, 0.2, 0.2)
const COLOR_CAPTURING := Color(1.0, 0.9, 0.0)
const COLOR_CONTESTED := Color(1.0, 0.2, 0.2)
const COLOR_CAPTURED := Color(0.2, 1.0, 0.3)
# Pulse params: slow для uncaptured (1.5s), medium для capturing (1.0s),
# fast для contested (0.5s). Captured static.
const PULSE_ENERGY_LOW := 0.5
const PULSE_ENERGY_HIGH := 1.5
const PULSE_PERIOD_SLOW := 1.5
const PULSE_PERIOD_MEDIUM := 1.0
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

# Anti-overlap clearance: радиус sphere-query вокруг spawn position'а — если в
# нём уже есть другой враг (collision_mask=4), spawn skip'ается. Mirror
# SpawnController.SPAWN_CLEARANCE_RADIUS (1.2u — capsule radius 0.5 + swarm
# ring offset 0.6 + margin). Playtest 2026-05-03: enemies spawn'ились друг на
# друге когда altar director выбирал ту же spawn-point подряд.
const SPAWN_CLEARANCE_RADIUS := 1.2


# Per-altar state. Index 0..3 соответствует order'у group("altar_zone") на момент
# _on_run_started — стабилен в пределах run'а (arena instance не меняется до
# restart'а, который reset'ит этот массив).
class AltarState:
	var area: Area3D
	var top_mesh: GeometryInstance3D
	var top_material: StandardMaterial3D
	var spawn_points: Array[Marker3D] = []
	var state: int = 0  # 0=uncaptured, 1=capturing, 2=contested, 3=captured
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
		_apply_state_visual(altar)
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
	# CSGBox3D имеет .material свойство. Читаем через .get() (не typed accessor —
	# GeometryInstance3D base type не объявляет material, но runtime у CSG-нод оно есть).
	var src_mat := top.get("material") as Material
	if src_mat == null:
		# Fallback на surface override (если CSG ещё не built) — все равно вернём null.
		push_warning("AltarDirector: altar top '%s' без material — visual cue заблокирован" % top.name)
		return null
	var dup := src_mat.duplicate() as StandardMaterial3D
	if dup == null:
		return null
	dup.emission_enabled = true
	# Initial emission color уже uncaptured (red). Albedo: preserve scene alpha
	# (beam material — semi-transparent, alpha~0.4) — иначе RGB-only assignment
	# даст alpha=1.0 и solid pillar вместо луча.
	dup.emission = COLOR_UNCAPTURED
	dup.emission_energy_multiplier = PULSE_ENERGY_LOW
	dup.albedo_color = _color_with_alpha(COLOR_UNCAPTURED, dup.albedo_color.a)
	top.set("material", dup)
	return dup


# Build Color(rgb, a) — preserve scene-defined alpha при state color updates,
# чтобы semi-transparent beam material'а не превращался в solid.
static func _color_with_alpha(rgb: Color, a: float) -> Color:
	return Color(rgb.r, rgb.g, rgb.b, a)


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
		if altar.state == 3:
			continue  # captured, freeze
		var bodies: Array = altar.area.get_overlapping_bodies()
		var has_player := false
		var has_enemy := false
		for b in bodies:
			if not is_instance_valid(b):
				continue
			if b.is_in_group("player"):
				has_player = true
			elif b is EnemyBase:
				has_enemy = true
		if has_player and has_enemy:
			# Contested — player + enemy together. Red fast pulse + dwell reset.
			if altar.state != 2:
				altar.state = 2
				_apply_state_visual(altar)
			altar.dwell_timer = 0.0
			Events.altar_dwell_progress.emit(altar.index, 0.0)
			continue
		if has_player:
			# Pure player → CAPTURING. Yellow medium pulse, dwell тикает.
			altar.dwell_timer += delta
			if altar.dwell_timer >= CAPTURE_DWELL_TIME:
				_capture_altar(altar)
				continue
			if altar.state != 1:
				altar.state = 1
				_apply_state_visual(altar)
			Events.altar_dwell_progress.emit(
				altar.index, clampf(altar.dwell_timer / CAPTURE_DWELL_TIME, 0.0, 1.0)
			)
		else:
			# Empty zone (no player) — uncaptured red slow pulse, dwell instant reset.
			# (Enemy alone в zone тоже сюда — не contested без player'а, чтобы враг
			# не "поднимал тревогу" если игрока рядом нет.)
			var was_active := altar.state == 1 or altar.state == 2
			if altar.state != 0:
				altar.state = 0
				_apply_state_visual(altar)
			altar.dwell_timer = 0.0
			if was_active:
				# Сообщаем HUD'у что прогресс сброшен → бар скрыть.
				Events.altar_dwell_progress.emit(altar.index, 0.0)


func _capture_altar(altar: AltarState) -> void:
	altar.state = 3
	altar.dwell_timer = 0.0
	captured_count += 1
	_apply_state_visual(altar)
	VelocityGate.apply_altar_reward()
	Events.altar_captured.emit(altar.index)
	# Hide progress bar — capture done, no more progress for this altar.
	Events.altar_dwell_progress.emit(altar.index, 0.0)
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
		if altar.state == 3:
			# Captured — static energy.
			altar.top_material.emission_energy_multiplier = PULSE_ENERGY_CAPTURED
			continue
		var period: float = PULSE_PERIOD_SLOW
		match altar.state:
			1:
				period = PULSE_PERIOD_MEDIUM
			2:
				period = PULSE_PERIOD_FAST
		altar.pulse_phase += delta / period
		if altar.pulse_phase >= 1.0:
			altar.pulse_phase = fmod(altar.pulse_phase, 1.0)
		# Sine-wave pulse 0..1, mapped в [PULSE_ENERGY_LOW, PULSE_ENERGY_HIGH].
		var s: float = (sin(altar.pulse_phase * TAU) * 0.5) + 0.5
		altar.top_material.emission_energy_multiplier = lerpf(
			PULSE_ENERGY_LOW, PULSE_ENERGY_HIGH, s
		)


# Set color emission/albedo по state'у. Energy multiplier живёт в _tick_visual_pulses
# (pulse loop для uncaptured/contested, static для captured) — не дублируем здесь.
func _apply_state_visual(altar: AltarState) -> void:
	if altar.top_material == null:
		return
	var color: Color = COLOR_UNCAPTURED
	match altar.state:
		1:
			color = COLOR_CAPTURING
		2:
			color = COLOR_CONTESTED
		3:
			color = COLOR_CAPTURED
	altar.top_material.emission = color
	altar.top_material.albedo_color = _color_with_alpha(color, altar.top_material.albedo_color.a)


# ────── Spawning (per-altar)

func _tick_spawning(delta: float) -> void:
	_resolve_spawn_parent()
	if _spawn_parent == null:
		return
	for altar in _altars:
		if altar.state == 3:
			continue  # captured altar — spawn off
		if altar.spawn_points.is_empty():
			continue
		altar.spawn_timer -= delta
		if altar.spawn_timer > 0.0:
			continue
		# Pick spawn point + type, instantiate. Если все spawn-points заблокированы
		# overlap'ом — defer на следующий tick (НЕ ресетим interval, оставляем timer
		# на 0 → попытаемся снова со следующим _process'ом). Это soft-fail: spawn
		# flow восстановится как только swarmling'и/melee отойдут от точки.
		if _spawn_for_altar(altar):
			altar.spawn_timer = SPAWN_INTERVAL_BASE + randf_range(-SPAWN_INTERVAL_JITTER, SPAWN_INTERVAL_JITTER)


# Returns true если spawn состоялся, false если все spawn-points заблокированы.
# Каждый altar zone имеет 2 marker'а — пробуем оба в random order'е перед defer.
func _spawn_for_altar(altar: AltarState) -> bool:
	var t: String = _pick_type_for_phase()
	# Shuffle spawn-points (small array, 2 элемента) — random order попыток.
	var candidates: Array[Marker3D] = altar.spawn_points.duplicate()
	candidates.shuffle()
	for marker in candidates:
		var pos := marker.global_position
		pos.y = SPAWN_Y
		if not _is_spawn_area_clear(pos):
			continue  # try next spawn-point
		if t == "swarmling":
			# Group of SWARM_GROUP_SIZE с tiny ring offset (mirror spawn_controller).
			for i in SWARM_GROUP_SIZE:
				var angle: float = TAU * float(i) / float(SWARM_GROUP_SIZE) + randf() * 0.2
				var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.6
				_instantiate_enemy_at(pos + offset, "swarmling")
		else:
			_instantiate_enemy_at(pos, t)
		return true
	# Все spawn-points этой zone заблокированы overlap'ом — defer.
	return false


# Physics overlap check вокруг spawn position'а (mirror SpawnController._is_spawn_area_clear).
# Layer 4 = enemies. Возвращает true когда area clear (можно спавнить). Sphere
# shape прощает вертикальный clearance.
func _is_spawn_area_clear(world_pos: Vector3) -> bool:
	var space := get_viewport().get_world_3d().direct_space_state
	if space == null:
		return true  # No physics space yet (early frame) — let spawn proceed
	var shape := SphereShape3D.new()
	shape.radius = SPAWN_CLEARANCE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(world_pos.x, SPAWN_Y, world_pos.z))
	query.collision_mask = 4  # enemies only — игнорируем env (layer 1) и player (layer 2)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var results := space.intersect_shape(query, 1)
	return results.is_empty()


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
