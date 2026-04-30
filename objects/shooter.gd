class_name EnemyShooter extends EnemyBase

# M3a Shooter — Chase / Attack / Reposition. Identity: cool color (blue),
# slim/upright capsule. Range attack через raycast в player position; trigger
# Reposition либо при потере line-of-sight, либо периодически каждые
# randf_range(4..6)с — чтобы не торчать на одном месте.

const FLASH_EMISSION_COLOR := Color(1.0, 0.85, 0.2)  # ярко-жёлтый: lock-on warning
const FLASH_EMISSION_ENERGY := 1.5

const REPOSITION_INTERVAL_MIN := 4.0
const REPOSITION_INTERVAL_MAX := 6.0
const REPOSITION_RADIUS := 15.0  # дистанция альтернативной позиции от player'а
const REPOSITION_CANDIDATES := 6  # точек на круге для line-of-sight check
const REPOSITION_REACH := 1.0     # close-enough для is_navigation_finished fallback
const PLAYER_HEAD_OFFSET := Vector3(0, 1.4, 0)  # ray target ≈ camera height
const SHOOTER_RAY_OFFSET := Vector3(0, 1.0, 0)  # ray origin ≈ capsule mid

# LOS raycast mask: env (layer 1) | player (layer 2) = 3. Исключает других врагов
# (layer 4) — иначе shooter теряет LOS из-за того что другой shooter стоит между
# ним и player'ом. См. также objects/*.tscn где collision_layer задан явно.
const LOS_MASK := 1 | 2

var _telegraph_audio: AudioStreamPlayer3D
var _reposition_timer: float = 0.0
var _reposition_target: Vector3 = Vector3.ZERO
var _has_reposition_target: bool = false


func _ready() -> void:
	# Числа (M3_enemy_numbers): Shooter — HP 30, speed 4.0, range 18, windup 350ms,
	# cooldown 4.0s, penalty 10 (SHOOTER_PENALTY), detection 35.
	max_hp = 30
	move_speed = 6.0
	attack_range = 18.0
	attack_windup = 0.35
	attack_cooldown = 4.0
	attack_penalty = VelocityGate.SHOOTER_PENALTY
	detection_radius = 35.0
	super._ready()

	_telegraph_audio = AudioStreamPlayer3D.new()
	_telegraph_audio.name = "TelegraphAudio"
	_telegraph_audio.bus = &"SFX"
	_telegraph_audio.stream = load("res://sounds/blaster.ogg")
	_telegraph_audio.unit_size = 8.0
	add_child(_telegraph_audio)

	_schedule_next_reposition()


# Override _physics_process: декрементируем reposition_timer ДО super, чтобы он
# тикал даже во время windup (super возвращается рано если _is_winding_up). Иначе
# таймер морозился на 350мс на каждой атаке — задержка между repositions росла на
# accumulated windup-кадрах. _update_state() больше не трогает _reposition_timer.
func _physics_process(delta: float) -> void:
	# is_spawning guard: telegraph fade'ит враг 250мс. За это время reposition_timer
	# не должен тикать (иначе сразу после spawn'а уже на cooldown'е минус 0.25с).
	if not is_dying and not is_spawning and _player != null:
		_reposition_timer = maxf(0.0, _reposition_timer - delta)
	super._physics_process(delta)


# Override: добавляем Reposition state поверх Idle/Chase/Attack base'а.
func _update_state() -> void:
	if _is_winding_up:
		return
	var dist := _distance_to_player()
	if dist > detection_radius:
		state = State.IDLE
		return

	# Reposition trigger: периодический таймер (тикает в _physics_process выше)
	# ИЛИ потеря line-of-sight в Attack/Chase.
	var need_reposition := false
	if _reposition_timer <= 0.0:
		need_reposition = true
	elif dist <= attack_range and not _has_line_of_sight():
		# В range но не вижу — обходим cover.
		need_reposition = true

	if need_reposition and state != State.REPOSITION:
		_pick_reposition_target()
		state = State.REPOSITION
		return

	# Если уже репозиционируемся — продолжаем пока не дошли до цели.
	if state == State.REPOSITION:
		if _has_reposition_target:
			var to_target: float = global_position.distance_to(_reposition_target)
			if to_target > REPOSITION_REACH:
				return  # ещё едем
		# Доехали → reset, выбираем нормальное поведение по дистанции.
		_has_reposition_target = false
		_schedule_next_reposition()

	# Стандартная логика (без attack по контакту — нужна line-of-sight для shooter'а).
	if dist <= attack_range and _has_line_of_sight():
		if _attack_cooldown_remaining <= 0.0:
			_start_attack()
			return
		# В range + есть LOS, но cooldown — стоим (не лезем ближе).
		state = State.CHASE
		return
	state = State.CHASE


# Override: Reposition использует _reposition_target. Остальные состояния
# (Idle/Chase/Attack-windup) дефер'им в base (та же логика что у Melee).
func _apply_movement(delta: float) -> void:
	if state == State.REPOSITION and _has_reposition_target and nav_agent != null:
		nav_agent.target_position = _reposition_target
		if nav_agent.is_navigation_finished():
			velocity = Vector3.ZERO
			move_and_slide()
			return
		var nx: Vector3 = nav_agent.get_next_path_position()
		var d: Vector3 = nx - global_position
		d.y = 0.0
		if d.length() > 0.001:
			d = d.normalized()
		velocity = d * move_speed
		move_and_slide()
		return
	super._apply_movement(delta)


func _play_telegraph() -> void:
	# Visual: emission flash на жёлтый — "lock-on prepared". Audio frame 0.
	if _material != null:
		_material.emission_enabled = true
		_material.emission = FLASH_EMISSION_COLOR
		_material.emission_energy_multiplier = FLASH_EMISSION_ENERGY
	if _telegraph_audio != null:
		print("[AUDIO] shooter.gd | windup_telegraph | blaster.ogg")
		_telegraph_audio.play()
	# Animation: Charging (one-shot windup pose).
	_play_oneshot(&"Charging")


func _end_telegraph() -> void:
	if _material != null:
		_material.emission = _base_emission_color
		_material.emission_energy_multiplier = _base_emission_energy


func _kill_type() -> String:
	return "shooter"


func _resolve_attack() -> void:
	# Raycast от shooter'а к player'у. Если LOS потеряна (cover вошёл за windup) — miss.
	# Spec: damage = SHOOTER_PENALTY (10) к cap. Не используем weapon-stat: shooter
	# bypassing player.damage() chain, шлём напрямую в VelocityGate (как melee).
	if not is_dying and _player != null and _has_line_of_sight():
		VelocityGate.apply_hit(attack_penalty)
	# Attack one-shot — fire pose. Возврат к Idle через _on_oneshot_finished.
	_play_oneshot(&"Attack")
	super._resolve_attack()


func _anim_for_state(_s: int) -> StringName:
	# Quaternius shooter rig не имеет Run/Walk — используем Idle для всех
	# состояний (CHASE / REPOSITION / IDLE). Шутер скользит на Idle pose
	# при движении — намеренное ограничение модели, не блокер.
	return &"Idle"


func _hit_anim_name() -> StringName:
	return &"Hit"


func _death_anim_name() -> StringName:
	# Shooter rig не имеет TurnOff — используем BackFlip как flat death substitute.
	# Cap 0.6с в base'е обрежет если анимация длиннее.
	return &"BackFlip"


# Line-of-sight: physics raycast от shooter'а к голове player'а. Excludes self.
# Если попали в player'а первым (или ничего не попало в пределах дистанции) — есть LOS.
# Если попали в cover (CSGBox с use_collision) — LOS блокирована.
func _has_line_of_sight() -> bool:
	if _player == null:
		return false
	var space := get_world_3d().direct_space_state
	var origin: Vector3 = global_position + SHOOTER_RAY_OFFSET
	var target: Vector3 = _player.global_position + PLAYER_HEAD_OFFSET
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	query.exclude = [self]
	query.collision_mask = LOS_MASK
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		# Чистый луч до target'а без collision'ов — player в зоне (либо за пределами
		# CharacterBody3D collider'а, что норм для FPS player'а). Считаем LOS есть.
		return true
	var collider = hit.get("collider", null)
	if collider == null:
		return true
	# Hit player'a → LOS есть. Hit cover/wall → нет.
	if collider == _player:
		return true
	if collider is Node and (collider as Node).is_in_group("player"):
		return true
	return false


func _pick_reposition_target() -> void:
	# 6 candidate точек на круге REPOSITION_RADIUS вокруг player'а. Выбираем
	# первую где (a) есть line-of-sight player → candidate, (b) NavigationServer
	# может туда добраться. Если ни одна не подходит — берём ближайшую free
	# (просто рандомную — fallback, чтобы не stuck'аться).
	if _player == null:
		_has_reposition_target = false
		return

	var space := get_world_3d().direct_space_state
	var nav_map := get_world_3d().navigation_map
	var player_head: Vector3 = _player.global_position + PLAYER_HEAD_OFFSET
	var start_angle: float = randf() * TAU  # рандомный стартовый offset чтобы не упорствовать одной точкой
	var fallback: Vector3 = global_position
	var has_fallback := false  # накапливаем первый ВАЛИДНЫЙ snapped, не привязываясь к i==0

	for i in REPOSITION_CANDIDATES:
		var a: float = start_angle + (TAU / REPOSITION_CANDIDATES) * i
		var candidate: Vector3 = _player.global_position + Vector3(cos(a), 0.0, sin(a)) * REPOSITION_RADIUS
		# Snap к navigation mesh — чтобы кандидат всегда был walkable.
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)
		if snapped == Vector3.ZERO:
			continue
		# LOS check: от candidate к player'у. Используем та же физика что в _has_line_of_sight.
		var query := PhysicsRayQueryParameters3D.create(snapped + SHOOTER_RAY_OFFSET, player_head)
		query.exclude = [self]
		query.collision_mask = LOS_MASK
		var hit := space.intersect_ray(query)
		var has_los := hit.is_empty()
		if not has_los:
			var collider = hit.get("collider", null)
			has_los = collider == _player or (collider is Node and (collider as Node).is_in_group("player"))
		if has_los:
			_reposition_target = snapped
			_has_reposition_target = true
			return
		# Fallback: первый ненулевой snapped, независимо от i. Если кандидат i=0
		# отбраковался через `continue` (snapped==ZERO), без флага fallback оставался
		# global_position и shooter "репозился сам в себя".
		if not has_fallback:
			fallback = snapped
			has_fallback = true

	# Fallback: ни одна точка не дала LOS (player полностью окружён cover'ом со
	# всех 6 углов — редкий кейс). Используем первую walkable точку.
	_reposition_target = fallback
	_has_reposition_target = true


func _schedule_next_reposition() -> void:
	_reposition_timer = randf_range(REPOSITION_INTERVAL_MIN, REPOSITION_INTERVAL_MAX)
