class_name SpawnController extends Node

# M4 SpawnController — continuous spawn ramp, type curve по фазам, safety-правила.
# Числа — авторитативно из docs/systems/M4_spawn_numbers.md §LOCKED + правила
# из docs/levels/M4_spawn_rules.md §LOCKED. Любой override — туда.
#
# Размещается в main.tscn как child Enemies-нода. Spawn'ит туда же (через
# get_parent().add_child) — у Enemies нет логики, чисто контейнер. Старые
# hard-coded EnemyMelee/EnemyShooter из main.tscn удалены вместе с этим pkg'ем.

# M9 conquest: 120s run с phased ramp. Замена endless формулы (RAMP_K=0.005, RAMP_BASE=4.0,
# FLOOR=0.8). К t=60: ~1.5с. К t=90: ~1.1с. К t=90+ (spike): ~0.5с (×2.2 врагов на пиковое
# давление 90-120). Числа из milestone-spec'а.
const RAMP_K := 0.018                 # interval = max(FLOOR, BASE / (1 + t * K))
const RAMP_BASE := 3.5
const INTERVAL_FLOOR := 0.4           # абсолютный минимум между двумя spawn'ами (spike phase)
const SPIKE_START := 90.0             # сек, instant step-up на peak давление до t=120
const SPIKE_INTERVAL_MULT := 0.45     # base_interval * 0.45 → ~×2.2 врагов в spike phase
# DEBUG: fast spawn для тестирования feel-эффектов (Kill Chain etc.).
# True = override interval на ~0.4с независимо от run_time. ВЕРНУТЬ false перед merge'ем
# в main для production playtest'а. M4 numbers в docs/systems/M4_spawn_numbers.md остаются LOCKED.
const DEBUG_FAST_SPAWN := false
const DEBUG_SPAWN_INTERVAL := 0.4
# DEBUG: skip Phase 0 (60с tutorial где swarm weight=0%) — для quick QA свармлингов.
# True = первый swarm group может спавниться с 0с. ВЕРНУТЬ false перед production playtest.
const DEBUG_SWARM_FROM_START := false
const ENEMY_CAP := 20                 # level-designer prevails (override от systems'овских 25)
const MAX_LIVE_SHOOTERS := 4          # hard cap; шестой стрелок крадёт agency
const MAX_LIVE_SWARMLINGS := 8        # M8 sub-cap (docs/systems/M8_swarmling_numbers §1).
									   # Отдельный от ENEMY_CAP — без него рой заполняет всё (4+4+4=12 swarms).
const SWARMLING_GROUP_MIN := 3        # M8 GROUP_SIZE_MIN
const SWARMLING_GROUP_MAX := 4        # M8 GROUP_SIZE_MAX
const MIN_SPAWN_DISTANCE := 12.0      # < 12u от player'а — skip
const SHOOTER_ANTI_CLUSTER_RADIUS := 8.0
const SPAWN_POINT_COOLDOWN := 3.0
const TELEGRAPH_FADE_SECONDS := 0.25
# M9 spawn-stuck fix (playtest 7min Phase 3 high swarm density). Перед spawn'ом
# проверяем что в радиусе SPAWN_CLEARANCE_RADIUS вокруг spawn-position'а нет
# других врагов. Радиус покрывает swarm ring offset 0.6u + capsule radius 0.5u
# + margin. Если не clear — этот spawn-tick отменяется (точка получает короткий
# soft-cooldown SPAWN_BLOCKED_RECHECK), interval timer не сбрасывается — спавн
# попытается на следующем тике (быстрый retry). См. карпу-чек: альтернатива —
# wire RVO velocity_computed на enemy_base, но это design-decision (M8 revert
# на hard collision был осознанный — flag parent'у в финальном отчёте).
const SPAWN_CLEARANCE_RADIUS := 1.2
const SPAWN_BLOCKED_RECHECK := 0.5
# M5 audio cleanup: spawn-telegraph audio теперь exclusive у Sfx autoload через
# Events.enemy_spawned (melee_spawn.ogg / shooter_spawn.ogg). Раньше здесь
# create'ился AudioStreamPlayer3D с blaster.ogg — был аудио double-trigger.

# Type curve (phased step-wise) — anchors из docs/systems/M8_swarmling_numbers §2.
# Веса: [melee, shooter, swarm_group]. Сумма = 1.0 в каждой фазе.
# Swarmling не нужен в первые 60с — игрок ещё осваивает hook.
const TYPE_PHASE_BOUNDARIES := [45.0, 90.0]          # < 45 / 45-90 / 90+
const TYPE_WEIGHTS_PHASE_0 := [0.60, 0.40, 0.00]     # 0-45c: tutorial pressure (no swarm)
const TYPE_WEIGHTS_PHASE_1 := [0.45, 0.35, 0.20]     # 45-90c: first swarm intro
const TYPE_WEIGHTS_PHASE_2 := [0.35, 0.30, 0.35]     # 90-120c: paritet (overlaps spike phase — final peak)

# Spawn-point weights — flexible через @export. Любая арена задаёт свой словарь
# в Inspector'е. Точки без явного веса получают POINT_WEIGHT_DEFAULT (=1).
# Default value соответствует legacy 40×40 (S1=3,S2=3,S3=2,S4=2 — M4_spawn_rules §1
# сумма 10). Arena B "Плац" override'ит на 8 точек через Inspector в main.tscn.
@export var point_weights: Dictionary = {"S1": 3, "S2": 3, "S3": 2, "S4": 2}
const POINT_WEIGHT_DEFAULT := 1

# Marker'ы лежат на полу (y=0), capsule center'у нужен y=0.9 чтобы враг не
# проваливался ногами в пол при spawn'е.
const SPAWN_Y := 0.9

var _run_time: float = 0.0
var _spawn_timer: float = 0.0
var _last_spawn_point_name: StringName = &""
var _point_cooldowns: Dictionary = {}  # {String: float seconds remaining}
var _live_enemies: int = 0
var _live_shooters: int = 0
var _live_swarmlings: int = 0
var _spawn_points: Array[Marker3D] = []
var _player: Node3D = null
# M9 Hot Zones: pause new spawns когда игрок выполнил objective (≥20 capture).
# Existing enemies продолжают жить до natural death (kill / despawn по timer'у).
# Reset на run_started через _on_run_started.
var _enemies_paused: bool = false
# M10 Journey (Arena C "Дорога"): pre-placed defenders, без dynamic spawn'а.
# Set в _on_run_started если arena root в группе "objective_journey" — тогда
# _enemies_paused=true сразу с run_started, controller noop'ает _process до
# конца run'а. Existing-enemies cleanup (queue_free) тоже пропускается:
# defenders живут в arena scene tree (не Enemies parent), reload арены через
# restart их инстанцирует заново.
const ARENA_GROUP_JOURNEY := &"objective_journey"

var _melee_scene: PackedScene = preload("res://objects/melee.tscn")
var _shooter_scene: PackedScene = preload("res://objects/shooter.tscn")
var _swarmling_scene: PackedScene = preload("res://objects/swarmling.tscn")


func _ready() -> void:
	# Spawn-points из группы — N штук, арена-зависимо. Раньше assert'или ровно 4
	# (40×40 legacy), теперь арены B/A/C поставляют 8. Casts при загрузке —
	# если вдруг в группу попадёт чужой Node, варним и фильтруем.
	# Bake может опаздывать на physics_frame (см. NavBaker), но spawn_points —
	# Marker3D'ы и в дереве сразу с _ready'ем child-сцены, значит к этому моменту
	# уже доступны.
	var raw := get_tree().get_nodes_in_group("spawn_point")
	for n in raw:
		var m := n as Marker3D
		if m == null:
			push_warning("SpawnController: node in 'spawn_point' group is not Marker3D, skipping: %s" % n)
			continue
		_spawn_points.append(m)
	if _spawn_points.is_empty():
		push_warning(
			"SpawnController: no spawn points in 'spawn_point' group — арена не предоставила Marker3D'ы. Spawn'ы заблокированы."
		)

	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		push_warning("SpawnController: player node not in group, spawn'ы будут блокированы distance check'ом.")

	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.objective_complete.connect(_on_objective_complete)


func _process(delta: float) -> void:
	if not VelocityGate.is_alive:
		return
	# M9 Hot Zones: после objective_complete (20 sphere'ов capture) — pause всех
	# новых spawn'ов до конца run'а (relief phase). Existing enemies остаются живыми
	# естественно (despawn только через kill).
	if _enemies_paused:
		return

	_run_time += delta

	# Decrement per-point cooldowns. Не пересоздаём dict — просто уменьшаем
	# существующие keys (cooldown=0 эквивалентен «не на cooldown»).
	for k in _point_cooldowns.keys():
		_point_cooldowns[k] = max(0.0, float(_point_cooldowns[k]) - delta)

	_spawn_timer += delta
	var interval: float
	if DEBUG_FAST_SPAWN:
		interval = DEBUG_SPAWN_INTERVAL
	else:
		var base_interval: float = max(INTERVAL_FLOOR, RAMP_BASE / (1.0 + _run_time * RAMP_K))
		# Spike phase: t >= 90 sec → step-up до ~×2.2 врагов. Step (не linear ramp) —
		# игрок должен почувствовать «что-то изменилось» в этот момент.
		interval = base_interval * SPIKE_INTERVAL_MULT if _run_time >= SPIKE_START else base_interval
	if _spawn_timer < interval:
		return
	if _live_enemies >= ENEMY_CAP:
		# Cap reached — level-designer §6: ramp паузится, не накапливает очередь.
		# _spawn_timer оставляем равным interval'у на следующий тик мы снова попробуем.
		# Без сброса: следующий kill моментально освободит spawn-slot.
		_spawn_timer = interval
		return

	var point := _pick_point()
	if point == null:
		# Все точки на cooldown + слишком близко к player'у. Не сбрасываем timer —
		# попробуем следующий тик. Очередь не накапливается за счёт того что timer
		# clamp'ится на interval (вычитанием).
		_spawn_timer = interval
		return

	# M9 anti-overlap: точка может быть free по cooldown'у, но physically заблокирована
	# другим врагом (swarmling not yet cleared spawn area из-за player camping nearby /
	# stuck pursuit). Skip этот tick, soft-cooldown точку на 0.5с — даём свармлингу
	# уйти. Не сбрасываем _spawn_timer (спавн ramp не теряется), на следующем тике
	# _pick_point предложит другую точку (ту, у которой нет soft-cooldown'а).
	if not _is_spawn_area_clear(point.global_position):
		_point_cooldowns[str(point.name)] = SPAWN_BLOCKED_RECHECK
		_spawn_timer = interval
		return

	var type_choice := _pick_type(point)
	if type_choice == "swarmling":
		# Group spawn: 3-4 одновременно, sub-cap MAX_LIVE_SWARMLINGS (M8 spec §2).
		# Если sub-cap не позволяет хотя бы GROUP_SIZE_MIN — отложить (не отменять,
		# spec §2 sub-cap enforcement). Возвращаемся не сбрасывая timer.
		var available_swarm_slots: int = MAX_LIVE_SWARMLINGS - _live_swarmlings
		var available_total_slots: int = ENEMY_CAP - _live_enemies
		var allowed: int = mini(SWARMLING_GROUP_MAX, mini(available_swarm_slots, available_total_slots))
		if allowed < SWARMLING_GROUP_MIN:
			# Не можем spawn'нуть полную группу — fallback на melee/shooter этим тиком.
			# Не отменяем сам тик: иначе spawn'ы вообще встанут пока swarm-cap не освободится.
			var fallback := _pick_non_swarm_type(point)
			_spawn_single(point, fallback)
			_spawn_timer = 0.0
			return
		var group_size: int = randi_range(SWARMLING_GROUP_MIN, allowed)
		_spawn_swarm_group(point, group_size)
		_spawn_timer = 0.0
		return

	_spawn_single(point, type_choice)
	_spawn_timer = 0.0


# ────── Spawn-point selection (weighted random + anti-repeat + distance + cooldown)

func _pick_point() -> Marker3D:
	var primary: Array[Marker3D] = []
	var primary_weights: Array[int] = []
	# Pass 1: anti-repeat strict — исключаем _last_spawn_point_name
	for p in _spawn_points:
		if not _is_point_eligible(p):
			continue
		if p.name == _last_spawn_point_name:
			continue
		primary.append(p)
		primary_weights.append(int(point_weights.get(str(p.name), POINT_WEIGHT_DEFAULT)))

	if not primary.is_empty():
		return _weighted_pick(primary, primary_weights)

	# Pass 2: anti-repeat relaxed (все 4 точки на cooldown кроме last или single point).
	var relaxed: Array[Marker3D] = []
	var relaxed_weights: Array[int] = []
	for p in _spawn_points:
		if not _is_point_eligible(p):
			continue
		relaxed.append(p)
		relaxed_weights.append(int(point_weights.get(str(p.name), POINT_WEIGHT_DEFAULT)))
	if not relaxed.is_empty():
		return _weighted_pick(relaxed, relaxed_weights)

	# Pass 3: hard fallback. Player сидит вплотную к всем точкам / все 4 на cooldown.
	# Берём самую дальнюю от player'а — даже если < min distance / на cooldown.
	# Это редкий edge case (level-designer §2: 40×40 арена с P в центре делает
	# "все < 12u" практически невозможным), но без fallback ramp просто бы стопался.
	if _player == null:
		return _spawn_points[0] if not _spawn_points.is_empty() else null
	var farthest: Marker3D = null
	var max_d: float = -1.0
	for p in _spawn_points:
		var d := p.global_position.distance_to(_player.global_position)
		if d > max_d:
			max_d = d
			farthest = p
	return farthest


func _is_point_eligible(p: Marker3D) -> bool:
	if float(_point_cooldowns.get(str(p.name), 0.0)) > 0.0:
		return false
	if _player != null:
		if p.global_position.distance_to(_player.global_position) < MIN_SPAWN_DISTANCE:
			return false
	return true


# Physics overlap check: есть ли уже враг в радиусе SPAWN_CLEARANCE_RADIUS
# вокруг spawn position'а. Layer 4 = enemies (см. objects/*.tscn collision_layer).
# Возвращает true когда area clear (можно спавнить). PhysicsServer3D direct API
# чтобы не создавать transient Area3D на каждый тик. Sphere shape прощает
# вертикальный clearance (capsule height не критично — на полу).
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


func _weighted_pick(candidates: Array[Marker3D], weights: Array[int]) -> Marker3D:
	var total: int = 0
	for w in weights:
		total += w
	if total <= 0:
		return candidates[0]
	var r: int = randi() % total
	var acc: int = 0
	for i in candidates.size():
		acc += weights[i]
		if r < acc:
			return candidates[i]
	return candidates[candidates.size() - 1]


# ────── Type curve (phased step-wise — M8 spec §2)

func _current_type_weights() -> Array:
	# [melee, shooter, swarmling] для текущей фазы run_time. 120с conquest → 3 фазы.
	var t := _run_time
	if DEBUG_SWARM_FROM_START and t < TYPE_PHASE_BOUNDARIES[0]:
		return TYPE_WEIGHTS_PHASE_1
	if t < TYPE_PHASE_BOUNDARIES[0]:
		return TYPE_WEIGHTS_PHASE_0
	if t < TYPE_PHASE_BOUNDARIES[1]:
		return TYPE_WEIGHTS_PHASE_1
	return TYPE_WEIGHTS_PHASE_2


# Weighted random выбор типа с учётом sub-caps. Если выпавший тип не может
# spawn'нуть из-за cap'а — возвращаем next-best fallback (другой тип).
func _pick_type(point: Marker3D) -> String:
	var weights: Array = _current_type_weights()
	var melee_w: float = float(weights[0])
	var shooter_w: float = float(weights[1])
	var swarm_w: float = float(weights[2])

	# Sub-cap pre-filter: если swarm cap полон — обнуляем swarm weight, перераспределение
	# идёт через нормализацию total. Аналогично shooter sub-cap.
	if _live_swarmlings >= MAX_LIVE_SWARMLINGS:
		swarm_w = 0.0
	if _live_shooters >= MAX_LIVE_SHOOTERS:
		shooter_w = 0.0
	# Anti-cluster: в радиусе 8u от точки уже стрелок — этот тик не shooter.
	if shooter_w > 0.0 and _has_shooter_within(point.global_position, SHOOTER_ANTI_CLUSTER_RADIUS):
		shooter_w = 0.0

	var total: float = melee_w + shooter_w + swarm_w
	if total <= 0.0:
		# Все типы заблокированы (теоретически невозможно — melee никогда не cap'ится).
		# Defensive fallback на melee.
		return "melee"

	var r: float = randf() * total
	if r < melee_w:
		return "melee"
	elif r < melee_w + shooter_w:
		return "shooter"
	return "swarmling"


# Вариант _pick_type без swarmling — используется когда выпал swarm, но group
# не помещается в sub-cap. Делит вес между melee/shooter, sub-caps учитываются.
func _pick_non_swarm_type(point: Marker3D) -> String:
	var weights: Array = _current_type_weights()
	var melee_w: float = float(weights[0])
	var shooter_w: float = float(weights[1])
	if _live_shooters >= MAX_LIVE_SHOOTERS:
		shooter_w = 0.0
	if shooter_w > 0.0 and _has_shooter_within(point.global_position, SHOOTER_ANTI_CLUSTER_RADIUS):
		shooter_w = 0.0
	var total: float = melee_w + shooter_w
	if total <= 0.0:
		return "melee"
	var r: float = randf() * total
	if r < melee_w:
		return "melee"
	return "shooter"


func _has_shooter_within(pos: Vector3, radius: float) -> bool:
	for child in get_parent().get_children():
		if child is EnemyShooter:
			var s := child as Node3D
			if s.global_position.distance_to(pos) < radius:
				return true
	return false


# ────── Spawn

func _scene_for_type(type: String) -> PackedScene:
	match type:
		"shooter":
			return _shooter_scene
		"swarmling":
			return _swarmling_scene
		_:
			return _melee_scene


func _spawn_single(point: Marker3D, type: String) -> void:
	_instantiate_at(point.global_position, type)
	_last_spawn_point_name = point.name
	_point_cooldowns[str(point.name)] = SPAWN_POINT_COOLDOWN


# M8: group spawn 3-4 swarmlings одновременно на одну spawn-точку с небольшим
# offset'ом — чтобы они не overlap'ились в физике. Stagger физический, не
# временной (single tick) — identity группы как roy'я важнее individual telegraph'а.
func _spawn_swarm_group(point: Marker3D, count: int) -> void:
	var base_pos := point.global_position
	for i in count:
		# Tiny ring offset (~0.5u radius) вокруг spawn-точки. capsule radius=0.25
		# × 2 = 0.5u + margin → не overlap'аются на spawn'е.
		var angle: float = TAU * float(i) / float(count) + randf() * 0.2
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.6
		_instantiate_at(base_pos + offset, "swarmling")
	_last_spawn_point_name = point.name
	_point_cooldowns[str(point.name)] = SPAWN_POINT_COOLDOWN


func _instantiate_at(world_pos: Vector3, type: String) -> void:
	var scene := _scene_for_type(type)
	var enemy = scene.instantiate()
	# is_spawning ставим ДО add_child — чтобы _physics_process на первом физкадре
	# уже вернулся рано (enemy_base ловит флаг). Альтернатива (set_after_add) —
	# гонка с физкадром между add_child и _ready'ем.
	if "is_spawning" in enemy:
		enemy.is_spawning = true
	var spawn_pos := world_pos
	spawn_pos.y = SPAWN_Y
	get_parent().add_child(enemy)
	(enemy as Node3D).global_position = spawn_pos

	_start_telegraph_fade(enemy)

	_live_enemies += 1
	if type == "shooter":
		_live_shooters += 1
	elif type == "swarmling":
		_live_swarmlings += 1
	Events.enemy_spawned.emit(enemy)


func _start_telegraph_fade(enemy: Node) -> void:
	# 250мс alpha fade-in. EnemyBase в _ready'е уже клонировал material из mesh
	# override (`_material` поле) — мы переключаем его в TRANSPARENCY_ALPHA, тянем
	# albedo.a 0→1, по окончании — обратно DISABLED + снимаем is_spawning гард.
	var mat: StandardMaterial3D = null
	if "_material" in enemy:
		mat = enemy._material as StandardMaterial3D
	if mat == null:
		# Никакого material override (legacy случай) — просто снимаем гард сразу,
		# чтобы AI не frozen'ился навсегда. Telegraph fade visual теряем — приемлемо.
		_finish_telegraph(enemy)
		return

	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var c0: Color = mat.albedo_color
	c0.a = 0.0
	mat.albedo_color = c0

	# Bind material + enemy в callable: tween_method тянет alpha 0→1, callable
	# проверяет валидность enemy на каждом кадре (если умер до окончания fade —
	# просто no-op'аем). Inline multiline lambda даёт GDScript parse-error на
	# unindent, поэтому отдельный метод _set_enemy_alpha.
	var tween := create_tween()
	tween.tween_method(_set_enemy_alpha.bind(enemy, mat), 0.0, 1.0, TELEGRAPH_FADE_SECONDS)
	tween.finished.connect(_finish_telegraph.bind(enemy))


func _set_enemy_alpha(a: float, enemy: Node, mat: StandardMaterial3D) -> void:
	if not is_instance_valid(enemy) or mat == null:
		return
	var c: Color = mat.albedo_color
	c.a = a
	mat.albedo_color = c


func _finish_telegraph(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	if "_material" in enemy:
		var mat := enemy._material as StandardMaterial3D
		if mat != null:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			var c: Color = mat.albedo_color
			c.a = 1.0
			mat.albedo_color = c
	if "is_spawning" in enemy:
		enemy.is_spawning = false


# ────── Lifecycle hooks

func _on_run_started() -> void:
	_run_time = 0.0
	_spawn_timer = 0.0
	_last_spawn_point_name = &""
	_point_cooldowns.clear()
	_live_enemies = 0
	_live_shooters = 0
	_live_swarmlings = 0
	_enemies_paused = false
	# Refresh spawn-points + player из дерева: на restart Main.reinstantiate_arena()
	# free'ит старый arena root — кэшированные с _ready() Marker3D references
	# становятся stale. Перечитываем группы каждый run, чтобы новые Marker'ы
	# ловились корректно. Player — единственный, его не пересоздаём, но defensive
	# refresh на случай будущих player respawn-as-fresh-instance путей.
	_spawn_points.clear()
	var raw := get_tree().get_nodes_in_group("spawn_point")
	for n in raw:
		var m := n as Marker3D
		if m == null:
			continue
		_spawn_points.append(m)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	# Journey arena: pre-placed defenders only, dynamic spawning отключаем
	# через _enemies_paused=true с самого старта. Mirror existing pause path
	# (objective_complete) — _process'ится early-return пока флаг true.
	if not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty():
		_enemies_paused = true
	# Очистить любых живых врагов (M4 in-place restart). Parent = Enemies-нода;
	# скрипт сам себя не free'ит (он же child Enemies, не EnemyBase).
	if get_parent() != null:
		for child in get_parent().get_children():
			if child is EnemyBase:
				child.queue_free()


func _on_enemy_killed(_restore: int, _pos: Vector3, type: String) -> void:
	_live_enemies = max(0, _live_enemies - 1)
	if type == "shooter":
		_live_shooters = max(0, _live_shooters - 1)
	elif type == "swarmling":
		_live_swarmlings = max(0, _live_swarmlings - 1)


func _on_objective_complete() -> void:
	_enemies_paused = true
