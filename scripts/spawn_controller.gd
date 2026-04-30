class_name SpawnController extends Node

# M4 SpawnController — continuous spawn ramp, type curve по фазам, safety-правила.
# Числа — авторитативно из docs/systems/M4_spawn_numbers.md §LOCKED + правила
# из docs/levels/M4_spawn_rules.md §LOCKED. Любой override — туда.
#
# Размещается в main.tscn как child Enemies-нода. Spawn'ит туда же (через
# get_parent().add_child) — у Enemies нет логики, чисто контейнер. Старые
# hard-coded EnemyMelee/EnemyShooter из main.tscn удалены вместе с этим pkg'ем.

const RAMP_K := 0.005                 # interval = max(FLOOR, BASE / (1 + t * K))
const RAMP_BASE := 4.0
const INTERVAL_FLOOR := 0.8           # абсолютный минимум между двумя spawn'ами
# DEBUG: fast spawn для тестирования feel-эффектов (Kill Chain etc.).
# True = override interval на ~0.4с независимо от run_time. ВЕРНУТЬ false перед merge'ем
# в main для production playtest'а. M4 numbers в docs/systems/M4_spawn_numbers.md остаются LOCKED.
const DEBUG_FAST_SPAWN := false
const DEBUG_SPAWN_INTERVAL := 0.4
const ENEMY_CAP := 20                 # level-designer prevails (override от systems'овских 25)
const MAX_LIVE_SHOOTERS := 4          # hard cap; шестой стрелок крадёт agency
const MIN_SPAWN_DISTANCE := 12.0      # < 12u от player'а — skip
const SHOOTER_ANTI_CLUSTER_RADIUS := 8.0
const SPAWN_POINT_COOLDOWN := 3.0
const TELEGRAPH_FADE_SECONDS := 0.25
# M5 audio cleanup: spawn-telegraph audio теперь exclusive у Sfx autoload через
# Events.enemy_spawned (melee_spawn.ogg / shooter_spawn.ogg). Раньше здесь
# create'ился AudioStreamPlayer3D с blaster.ogg — был аудио double-trigger.

# Type curve (phased lerp) — anchors из M4_spawn_numbers.md §LOCKED.
const PHASE1_END := 180.0   # 0..180c: shooter_prob = 0.30
const PHASE2_END := 480.0   # 180..480: lerp 0.30 → 0.50
const PHASE3_END := 900.0   # 480..900: lerp 0.50 → 0.60
const SHOOTER_PROB_PHASE1 := 0.30
const SHOOTER_PROB_PHASE2 := 0.50
const SHOOTER_PROB_PHASE3 := 0.60

# Spawn-point weights (M4_spawn_rules §1). Сумма 10.
const POINT_WEIGHTS := {"S1": 3, "S2": 3, "S3": 2, "S4": 2}

# Marker'ы лежат на полу (y=0), capsule center'у нужен y=0.9 чтобы враг не
# проваливался ногами в пол при spawn'е.
const SPAWN_Y := 0.9

var _run_time: float = 0.0
var _spawn_timer: float = 0.0
var _last_spawn_point_name: StringName = &""
var _point_cooldowns: Dictionary = {}  # {String: float seconds remaining}
var _live_enemies: int = 0
var _live_shooters: int = 0
var _spawn_points: Array[Marker3D] = []
var _player: Node3D = null

var _melee_scene: PackedScene = preload("res://objects/melee.tscn")
var _shooter_scene: PackedScene = preload("res://objects/shooter.tscn")


func _ready() -> void:
	# Spawn-points из группы (4 Marker3D на main.tscn). Casts при загрузке —
	# если вдруг туда попадёт чужой Node, варним и фильтруем.
	var raw := get_tree().get_nodes_in_group("spawn_point")
	for n in raw:
		var m := n as Marker3D
		if m == null:
			push_warning("SpawnController: node in 'spawn_point' group is not Marker3D, skipping: %s" % n)
			continue
		_spawn_points.append(m)
	if _spawn_points.size() != 4:
		push_warning(
			"SpawnController: expected 4 spawn points, got %d. Type curve / weights tuned для 4."
			% _spawn_points.size()
		)

	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null:
		push_warning("SpawnController: player node not in group, spawn'ы будут блокированы distance check'ом.")

	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	if not VelocityGate.is_alive:
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
		interval = max(INTERVAL_FLOOR, RAMP_BASE / (1.0 + _run_time * RAMP_K))
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

	var want_shooter := _decide_shooter(point)
	_spawn_enemy(point, want_shooter)
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
		primary_weights.append(int(POINT_WEIGHTS.get(str(p.name), 1)))

	if not primary.is_empty():
		return _weighted_pick(primary, primary_weights)

	# Pass 2: anti-repeat relaxed (все 4 точки на cooldown кроме last или single point).
	var relaxed: Array[Marker3D] = []
	var relaxed_weights: Array[int] = []
	for p in _spawn_points:
		if not _is_point_eligible(p):
			continue
		relaxed.append(p)
		relaxed_weights.append(int(POINT_WEIGHTS.get(str(p.name), 1)))
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


# ────── Type curve (phased piecewise-linear)

func _shooter_probability() -> float:
	var t := _run_time
	if t < PHASE1_END:
		return SHOOTER_PROB_PHASE1
	if t < PHASE2_END:
		# linear lerp 0.30 → 0.50
		var a: float = (t - PHASE1_END) / (PHASE2_END - PHASE1_END)
		return lerpf(SHOOTER_PROB_PHASE1, SHOOTER_PROB_PHASE2, a)
	if t < PHASE3_END:
		# linear lerp 0.50 → 0.60
		var a: float = (t - PHASE2_END) / (PHASE3_END - PHASE2_END)
		return lerpf(SHOOTER_PROB_PHASE2, SHOOTER_PROB_PHASE3, a)
	return SHOOTER_PROB_PHASE3


func _decide_shooter(point: Marker3D) -> bool:
	var want_shooter := randf() < _shooter_probability()
	if not want_shooter:
		return false
	# Hard cap (M3_identity §4): max 4 живых стрелка.
	if _live_shooters >= MAX_LIVE_SHOOTERS:
		return false
	# Anti-cluster (level-designer §3): если в радиусе 8u от выбранной точки
	# уже стоит стрелок — этот тик идёт melee. Не reroll'им point — упрощаем
	# и доверяем weighted-random: следующий тик скорее всего ляжет на другую точку.
	if _has_shooter_within(point.global_position, SHOOTER_ANTI_CLUSTER_RADIUS):
		return false
	return true


func _has_shooter_within(pos: Vector3, radius: float) -> bool:
	for child in get_parent().get_children():
		if child is EnemyShooter:
			var s := child as Node3D
			if s.global_position.distance_to(pos) < radius:
				return true
	return false


# ────── Spawn

func _spawn_enemy(point: Marker3D, want_shooter: bool) -> void:
	var scene: PackedScene = _shooter_scene if want_shooter else _melee_scene
	var enemy = scene.instantiate()
	# is_spawning ставим ДО add_child — чтобы _physics_process на первом физкадре
	# уже вернулся рано (enemy_base ловит флаг). Альтернатива (set_after_add) —
	# гонка с физкадром между add_child и _ready'ем.
	if "is_spawning" in enemy:
		enemy.is_spawning = true
	var spawn_pos := point.global_position
	spawn_pos.y = SPAWN_Y
	get_parent().add_child(enemy)
	(enemy as Node3D).global_position = spawn_pos

	_start_telegraph_fade(enemy)

	_live_enemies += 1
	if want_shooter:
		_live_shooters += 1
	_last_spawn_point_name = point.name
	_point_cooldowns[str(point.name)] = SPAWN_POINT_COOLDOWN
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
