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

func _process(delta):
	# Handle functions
	handle_controls(delta)
	handle_gravity(delta)
	_tick_dash(delta)

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
	
	# Falling out of arena → trigger смерть через тот же путь что drain (RunManager
	# reset'ит VelocityGate). Пол арены на y=0; -10 это fail-safe если CSG-floor
	# пропал/повредился. force_kill идемпотентен — single source of truth для player_died.
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

	# Death → пока RunManager не reload'нул сцену (2.8 сек), глушим input.
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
			print("[TRACE shoot ", n, "] collider=", collider, " path=", collider.get_path() if collider else "<null>", " has_damage=", collider.has_method("damage") if collider else false, " group_enemy=", collider.is_in_group("enemy") if collider else false)

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
# в VelocityGate как shooter-penalty (концепт: hit от стрелка = -10 cap). Свой
# EnemyDummy зовёт VelocityGate.apply_hit(MELEE_PENALTY) напрямую через ContactArea.
func damage(_amount):
	print("[TRACE Player.damage SELF-HIT] amount=", _amount, " — should not happen on shoot")
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
