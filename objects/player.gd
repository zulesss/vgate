extends CharacterBody3D

@export_subgroup("Properties")
@export_range(0, 100) var number_of_jumps: int = 2
@export var jump_strength = 8

# M1: max walking speed читается из VelocityGate.max_speed_at_cap() — каждый кадр.
# Стартовый base_walk_speed = 8.0 u/s (см. docs/systems/M1_numbers.md). Дефолт Starter
# Kit'а был 5 u/s; перешли на 8 чтобы арена 40×40 пересекалась за читаемое время.
# Локально не храним speed-константу — единственный источник правды VelocityGate.

# Dash (см. docs/systems/M1_numbers.md §Dash).
const DASH_VELOCITY_BURST := 20.0
const DASH_DURATION := 0.2
const DASH_COOLDOWN := 2.5

# FOV single-axis cap mapping (docs/feel/feel_spec.md §1, revised 2026-04-27).
# base_fov = cap_to_fov(velocity_cap):
#   cap≥80 (CAP_MID) → linear 90→95° (in-form headroom)
#   cap<80           → quadratic 90→58° (urgency accelerates near zero)
# Pivot от axis1 (speed_ratio tunnel) + axis2 (cap_ratio plateau) + min(): плато
# давало dead-zone, kill restore не читался визуально. Single-axis = continuous
# read «cap = FOV», kill +25 расширяет окно сразу.
const FOV_NORM := 90.0   # старт (cap=80)
const FOV_PEAK := 95.0   # cap=100 — пик «в форме»
const FOV_FLOOR := 58.0  # motion sickness limit (cap=0)
const CAP_MID := 0.8     # 80 / VelocityGate.CAP_CEILING — точка перегиба кривой
const FOV_BASE_SMOOTH_SECONDS := 0.1  # 100ms сглаживание дёрганья на hit/kill

# Camera bob (§1, MUST). Amplitude → 0 при low ratio, restore при high. 0.5 сек tween.
const BOB_AMPLITUDE := 0.04         # baseline вертикальная амплитуда (units)
const BOB_FREQUENCY := 8.0          # рад/сек, привязано к step-rate ходьбы
const BOB_TAPER_SECONDS := 0.5      # время полного перехода 1↔0
const BOB_THRESHOLD := 0.3          # speed_ratio: ниже — taper к 0, выше — restore к 1

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []

var weapon: Weapon
var weapon_index := 0

var mouse_sensitivity = 700
var gamepad_sensitivity := 0.075

var mouse_captured := true

var movement_velocity: Vector3
var rotation_target: Vector3

var input_mouse: Vector2

var gravity := 0.0

var previously_floored := false

var jumps_remaining: int

var container_offset = Vector3(1.2, -1.1, -2.75)

var tween: Tween

# Dash state.
var _dash_time_remaining: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _dash_velocity: Vector3 = Vector3.ZERO

# Camera bob state.
var _bob_phase: float = 0.0
var _bob_amplitude_modifier: float = 1.0  # 0..1, taper'ится по speed_ratio threshold
var _head_base_y: float = 0.0

# FOV controller (создаётся в _ready как child). Канал для base + kicks.
var fov_controller: FovController

# Audio players для feel-эффектов (programmatic, не в .tscn — конвенция как у
# fov_controller). Не идут через Audio autoload pool: тот рандомит pitch 0.9-1.1
# каждый раз, что конфликтует со спекой «детерминированные числа».
var _kill_crack_player: AudioStreamPlayer

# Dash camera push state (§3): смещение camera.position.z на −DASH_PUSH_DISTANCE
# (forward по local-Z для Camera3D в Godot), tween-возврат к 0 за DASH_PUSH_MS.
const DASH_PUSH_DISTANCE := 0.15  # units forward
const DASH_PUSH_MS := 200          # ease-out
var _camera_push_remaining: float = 0.0  # секунд до восстановления к 0
var _camera_push_total: float = 0.0      # для нормализации t в ease-out

@onready var head = $Head
@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast
@onready var muzzle = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Muzzle
@onready var container = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Container
@onready var sound_footsteps = $SoundFootsteps
@onready var blaster_cooldown = $Cooldown

@export var crosshair: TextureRect

# Functions

func _ready():
	add_to_group("player")

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	weapon = weapons[weapon_index] # Weapon must never be nil
	initiate_change_weapon(weapon_index)

	# FOV controller — программный child, не в .tscn (проще + матчит conventions).
	# Стартуем с FOV_NORM (cap=80 → 90°) — set_base в _tick_feel перепишет первым же
	# кадром через cap_to_fov(), но snap нужен чтобы не было кадра с дефолтным 75°.
	fov_controller = FovController.new()
	fov_controller.name = "FovController"
	fov_controller.base_fov = FOV_NORM
	fov_controller.min_fov = FOV_FLOOR
	fov_controller.set_camera(camera)
	add_child(fov_controller)
	camera.fov = FOV_NORM  # стартовый snap (Starter-Kit имел 80°)

	_head_base_y = head.position.y

	# Kill burst (§2 Iter 1): FOV +15° punch ease-out-cubic 180ms + audio crack.
	# Reuse существующего enemy_destroy.ogg. Spec: 0 dB, без pitch mod.
	_kill_crack_player = AudioStreamPlayer.new()
	_kill_crack_player.name = "KillCrackPlayer"
	_kill_crack_player.stream = load("res://sounds/enemy_destroy.ogg")
	_kill_crack_player.volume_db = 0.0
	add_child(_kill_crack_player)

	if not Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.connect(_on_enemy_killed)

	if not Events.dash_started.is_connected(_on_dash_started):
		Events.dash_started.connect(_on_dash_started)

func _process(delta):
	# Handle functions
	handle_controls(delta)
	handle_gravity(delta)
	_tick_dash(delta)
	_tick_feel(delta)

	# Movement

	var applied_velocity: Vector3

	movement_velocity = transform.basis * movement_velocity # Move forward

	applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = - gravity

	# Dash overrides walk-acceleration: жёсткий burst в направлении взгляда. Acceleration
	# Starter Kit'а слишком плавный для feel'а dash'а — дашим напрямую через velocity.
	if _dash_time_remaining > 0.0:
		applied_velocity.x = _dash_velocity.x
		applied_velocity.z = _dash_velocity.z

	velocity = applied_velocity
	move_and_slide()

	# Сообщаем VelocityGate XZ-скорость (Y исключён — концепт §Movement: jump-spam
	# не должен поддерживать speed_ratio выше threshold).
	var xz_speed: float = Vector2(velocity.x, velocity.z).length()
	VelocityGate.set_current_speed(xz_speed)
	
	# Rotation 
	container.position = lerp(container.position, container_offset - (basis.inverse() * applied_velocity / 30), delta * 10)
	
	# Movement sound
	
	sound_footsteps.stream_paused = true
	
	if is_on_floor():
		if abs(velocity.x) > 1 or abs(velocity.z) > 1:
			sound_footsteps.stream_paused = false
	
	# Landing after jump or falling
	
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)
	
	if is_on_floor() and gravity > 1 and !previously_floored: # Landed
		Audio.play("sounds/land.ogg")
		camera.position.y = -0.1
	
	previously_floored = is_on_floor()
	
	# Falling out of arena → trigger смерть через тот же путь что drain (RunLoop
	# reset'ит VelocityGate по нажатию RESTART). Пол арены на y=0; -10 это fail-safe
	# если CSG-floor пропал/повредился. force_kill идемпотентен — single source of
	# truth для player_died.
	if position.y < -10:
		VelocityGate.force_kill()

# Mouse movement

func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		handle_rotation(event.relative.x, event.relative.y, false)

func handle_controls(delta):
	# Mouse capture (всегда активно — даже под input_locked, чтобы можно было освободить курсор).
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true

	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false

		input_mouse = Vector2.ZERO

	# Death → пока DeathScreen не показал кнопку RESTART (3.3с) и юзер не нажал
	# её (RunLoop reset'ит is_alive обратно в true), глушим player input.
	# Single source of truth — VelocityGate.is_alive.
	if not VelocityGate.is_alive:
		movement_velocity = Vector3.ZERO
		return

	# Movement: max-speed читается из VelocityGate каждый кадр. При cap=80 → 6.4 u/s.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * VelocityGate.max_speed_at_cap()

	# Handle Controller Rotation
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	if rotation_input:
		handle_rotation(rotation_input.x, rotation_input.y, true, delta)

	# Shooting

	action_shoot()

	# Jumping

	if Input.is_action_just_pressed("jump"):
		if jumps_remaining:
			action_jump()

	# Dash

	if Input.is_action_just_pressed("dash"):
		_try_start_dash()

	# Weapon switching

	action_weapon_toggle()

# Camera rotation

func handle_rotation(xRot: float, yRot: float, isController: bool, delta: float = 0.0):
	if isController:
		rotation_target -= Vector3(-yRot, -xRot, 0).limit_length(1.0) * gamepad_sensitivity
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)
		rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	else:
		rotation_target += (Vector3(-yRot, -xRot, 0) / mouse_sensitivity)
		rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))
		camera.rotation.x = rotation_target.x;
		rotation.y = rotation_target.y;
	
# Handle gravity

func handle_gravity(delta):
	gravity += 20 * delta

	if gravity < 0 and is_on_ceiling():
		gravity = 0
	
	if gravity > 0 and is_on_floor():
		jumps_remaining = number_of_jumps
		gravity = 0

# Jumping

func action_jump():
	Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
	gravity = - jump_strength
	jumps_remaining -= 1

# Shooting

func action_shoot():
	if Input.is_action_pressed("shoot"):
		if !blaster_cooldown.is_stopped(): return # Cooldown for shooting
		
		Audio.play(weapon.sound_shoot)
		
		# Set muzzle flash position, play animation
		
		muzzle.play("default")
		
		muzzle.rotation_degrees.z = randf_range(-45, 45)
		muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
		muzzle.position = container.position - weapon.muzzle_position
		
		blaster_cooldown.start(weapon.cooldown)
		
		# Shoot the weapon, amount based on shot count
		
		for n in weapon.shot_count:
			raycast.target_position.x = randf_range(-weapon.spread, weapon.spread)
			raycast.target_position.y = randf_range(-weapon.spread, weapon.spread)
			
			raycast.force_raycast_update()
			
			if !raycast.is_colliding(): continue # Don't create impact when raycast didn't hit
			
			var collider = raycast.get_collider()

			# Hitting an enemy

			if collider.has_method("damage"):
				collider.damage(weapon.damage)
			
			# Creating an impact animation
			
			var impact = preload("res://objects/impact.tscn")
			var impact_instance = impact.instantiate()
			
			impact_instance.play("shot")
			
			get_tree().root.add_child(impact_instance)
			
			impact_instance.position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact_instance.look_at(camera.global_transform.origin, Vector3.UP, true)
			
		var knockback = random_vec2(weapon.min_knockback, weapon.max_knockback)
		# print('knockback', knockback)
		container.position.z += 0.25 # Knockback of weapon visual
		camera.rotation.x += knockback.x # Knockback of camera
		rotation.y += knockback.y
		rotation_target.x += knockback.x
		rotation_target.y += knockback.y
		movement_velocity += Vector3(0, 0, weapon.knockback) # Knockback

# Toggle between available weapons (listed in 'weapons')

func action_weapon_toggle():
	if Input.is_action_just_pressed("weapon_toggle"):
		weapon_index = wrap(weapon_index + 1, 0, weapons.size())
		initiate_change_weapon(weapon_index)
		
		Audio.play("sounds/weapon_change.ogg")

# Initiates the weapon changing animation (tween)

func initiate_change_weapon(index):
	weapon_index = index
	
	tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(container, "position", container_offset - Vector3(0, 1, 0), 0.1)
	tween.tween_callback(change_weapon) # Changes the model

# Switches the weapon model (off-screen)

func change_weapon():
	weapon = weapons[weapon_index]

	# Step 1. Remove previous weapon model(s) from container
	
	for n in container.get_children():
		container.remove_child(n)
	
	# Step 2. Place new weapon model in container
	
	var weapon_model = weapon.model.instantiate()
	container.add_child(weapon_model)
	
	weapon_model.position = weapon.position
	weapon_model.rotation_degrees = weapon.rotation
	
	# Step 3. Set model to only render on layer 2 (the weapon camera)
	
	for child in weapon_model.find_children("*", "MeshInstance3D"):
		child.layers = 2
		
	# Set weapon data
	
	raycast.target_position = Vector3(0, 0, -1) * weapon.max_distance
	crosshair.texture = weapon.crosshair

# Starter Kit enemy.gd зовёт player.damage(amount) если ему попасть. Маршрутизируем
# в VelocityGate как shooter-penalty (концепт: hit от стрелка = -10 cap). M3a
# Shooter/Melee подклассы EnemyBase шлют apply_hit напрямую (resolve_attack path).
func damage(_amount):
	VelocityGate.apply_hit(VelocityGate.SHOOTER_PENALTY)

# Create a random knockback vector
static func random_vec2(_min: Vector2, _max: Vector2) -> Vector2:
	var _sign = -1 if randi() % 2 == 0 else 1
	return Vector2(randf_range(_min.x, _max.x), randf_range(_min.y, _max.y) * _sign)


# Dash --------------------------------------------------------------------

func _try_start_dash() -> void:
	if _dash_cooldown_remaining > 0.0 or _dash_time_remaining > 0.0:
		return

	# Направление взгляда (XZ-проекция от камеры). Если игрок смотрит в стену
	# и input нулевой — дашим вперёд. Если есть input — дашим в сторону input'а
	# для предсказуемости (FPS convention).
	var input_vec := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir: Vector3
	if input_vec.length() > 0.01:
		dir = (transform.basis * Vector3(input_vec.x, 0, input_vec.y)).normalized()
	else:
		var fwd: Vector3 = -transform.basis.z
		fwd.y = 0.0
		dir = fwd.normalized()

	_dash_velocity = dir * DASH_VELOCITY_BURST
	_dash_time_remaining = DASH_DURATION
	_dash_cooldown_remaining = DASH_COOLDOWN
	Events.dash_started.emit()


func _tick_dash(delta: float) -> void:
	if _dash_time_remaining > 0.0:
		_dash_time_remaining = maxf(0.0, _dash_time_remaining - delta)
	if _dash_cooldown_remaining > 0.0:
		_dash_cooldown_remaining = maxf(0.0, _dash_cooldown_remaining - delta)


# Читается DebugHud'ом. M2 уберём в HUD-проекте отдельным узлом.
func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_remaining


# Feel pass §1 — каждый кадр пересчитываем base FOV (single-axis cap) и bob taper.
# Per-frame дёшево: одна if-ветка + lerpf. Дёрганье на дискретных hit/kill событиях
# гасится 100ms экспоненциальным smoothing'ом внутри fov_controller.set_base().
func _tick_feel(delta: float) -> void:
	var sr: float = VelocityGate.speed_ratio()

	if fov_controller != null:
		fov_controller.set_base(cap_to_fov(VelocityGate.velocity_cap), FOV_BASE_SMOOTH_SECONDS)

	# --- Camera bob amplitude taper ---
	# threshold 0.3: ниже — modifier к 0 за BOB_TAPER_SECONDS, выше — к 1 за то же.
	var target_mod: float = 0.0 if sr < BOB_THRESHOLD else 1.0
	var step: float = delta / BOB_TAPER_SECONDS
	if absf(target_mod - _bob_amplitude_modifier) <= step:
		_bob_amplitude_modifier = target_mod
	else:
		_bob_amplitude_modifier += signf(target_mod - _bob_amplitude_modifier) * step

	# Bob phase advance — только если игрок реально движется по полу. На floor'е и
	# при non-zero XZ velocity. Иначе amplitude 0 (нет шага = нет bob'а).
	var xz: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and xz > 0.5:
		_bob_phase += delta * BOB_FREQUENCY
	# Применяем offset на head.position.y (camera.position.y занят landing dip'ом).
	var bob_offset: float = sin(_bob_phase) * BOB_AMPLITUDE * _bob_amplitude_modifier
	head.position.y = _head_base_y + bob_offset

	# Dash camera push decay (§3). camera.position.z =0 baseline; во время dash'а
	# смещаем на −DASH_PUSH_DISTANCE (forward в Camera3D local) и плавно возвращаем
	# к 0 за DASH_PUSH_MS ease-out. camera.position.z не трогается ни в каком другом
	# месте — конфликтов нет.
	if _camera_push_remaining > 0.0:
		_camera_push_remaining = maxf(0.0, _camera_push_remaining - delta)
		var t: float = 1.0 - (_camera_push_remaining / _camera_push_total)  # 0..1
		var inv: float = 1.0 - t
		var ease_out: float = inv * inv  # quadratic ease-out for return-to-0
		camera.position.z = -DASH_PUSH_DISTANCE * ease_out
		if _camera_push_remaining <= 0.0:
			camera.position.z = 0.0  # snap to baseline (no drift)


# Kill burst (§2 Iter 1, MUST). FOV +15° punch ease-out-cubic 180 мс + audio crack
# в frame 0. Hit-stop (Iter 2) и time-dilation (Iter 3) отложены до результата
# главного feel-чека из §5: «читается ли kill как выдох?». Если да — Iter 2/3 могут
# быть избыточны; если нет — добавляем поверх.
func _on_enemy_killed(_restore: int, _pos: Vector3, _type: String) -> void:
	# Dead-frame guard: матчит vignette_flash.gd — никаких feel-эффектов от kill'а
	# в кадр смерти, иначе FOV punch / audio crack играют поверх death-screen.
	if not VelocityGate.is_alive:
		return
	if fov_controller != null:
		fov_controller.kick(15.0, 180, "ease_out_cubic")
	if _kill_crack_player != null:
		_kill_crack_player.play()


# Dash feel (§3, MUST). FOV +12° stretch ease-out-quart 250ms + camera push 0.15u
# forward → ease-out 200ms. Audio whoosh теперь в SfxBus._on_dash_started — здесь
# только визуальные слои. Все три слоя срабатывают на один и тот же signal
# Events.dash_started, который emit'ится из _try_start_dash() в момент старта.
func _on_dash_started() -> void:
	# No is_alive guard here: handle_controls() возвращает рано если is_alive=false,
	# поэтому _try_start_dash() не может вызваться и signal не эмитится на dead-кадре.
	if fov_controller != null:
		fov_controller.kick(12.0, 250, "ease_out_quart")
	# Camera push: instant offset, decay через _tick_feel.
	_camera_push_total = float(DASH_PUSH_MS) / 1000.0
	_camera_push_remaining = _camera_push_total
	camera.position.z = -DASH_PUSH_DISTANCE


# Spec §1 (revised 2026-04-27): single-axis cap → base FOV.
#   cap_norm ≥ 0.8 → linear 90→95° (in-form headroom)
#   cap_norm < 0.8 → quadratic 90→58° (urgency accelerates near zero)
# Sanity: cap=80→90, cap=60→~88, cap=40→~82, cap=20→~72, cap=0→58.
static func cap_to_fov(cap: float) -> float:
	var cap_norm: float = cap / VelocityGate.CAP_CEILING
	if cap_norm >= CAP_MID:
		var t_up: float = (cap_norm - CAP_MID) / (1.0 - CAP_MID)
		return lerpf(FOV_NORM, FOV_PEAK, clampf(t_up, 0.0, 1.0))
	var t_down: float = (CAP_MID - cap_norm) / CAP_MID
	t_down = clampf(t_down, 0.0, 1.0)
	return lerpf(FOV_NORM, FOV_FLOOR, t_down * t_down)
