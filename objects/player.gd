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

# Jump CD (rate-limit ТОЛЬКО на double-jump). 1.5с — балансовый pivot M13 (от 1.25),
# чуть жёстче gating'а ledge-spam mobility, но double-jump всё ещё доступен внутри
# DASH_COOLDOWN (2.5с) окна. First jump с земли всегда instant и CD не ставит.
# CD persists across landings — не reset'ится на ground touch (см. handle_gravity);
# double-jumped → land → first jump immediate, но next double-jump в воздухе всё
# ещё gated CD'ом.
const JUMP_COOLDOWN := 1.8

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

# Jump CD state. Tick'ается в _tick_dash рядом с dash CD. НЕ reset'ится при ground
# touch — CD это rate-limit на double-jump globally, persists across landings.
var _jump_cooldown_remaining: float = 0.0

# M9 magazine + reload (docs: brief PLAN.md M9). State в player'е (Resource holds spec
# через weapon.max_ammo). Single source of truth для cost — VelocityGate.RELOAD_COST.
# Reload запрещён при cap < RELOAD_COST (silent fail). Auto-reload на empty НЕ
# запускается если cap < RELOAD_COST — иначе игрок stuck (empty → не shoot, no cap →
# не reload). Под dash — продолжается; на death — отменяется (run_started reset'ит).
const RELOAD_DURATION := 1.0
var _current_ammo: int = 0
var _is_reloading: bool = false
var _reload_timer: float = 0.0

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

# Dash whoosh: legacy path возвращён 2026-04-29 после F5-плейтеста. M5 ассет
# `dash_whoosh.ogg` звучал как шорох-артефакт; pre-M5 jump_b.ogg + pitch shift
# +200 cents даёт чистый whoosh. Asset в `assets/audio/sfx/` оставлен на диске
# на случай будущей замены. Old M5-path (autoload/sfx.gd `_dash_player`) удалён.
const DASH_WHOOSH_PITCH := 2.0 ** (200.0 / 1200.0)  # +200 cents ≈ 1.122
var _dash_whoosh_player: AudioStreamPlayer

# Dash camera push state (§3): смещение camera.position.z на −DASH_PUSH_DISTANCE
# (forward по local-Z для Camera3D в Godot), tween-возврат к 0 за DASH_PUSH_MS.
const DASH_PUSH_DISTANCE := 0.15  # units forward
const DASH_PUSH_MS := 200          # ease-out
var _camera_push_remaining: float = 0.0  # секунд до восстановления к 0
var _camera_push_total: float = 0.0      # для нормализации t в ease-out

# Dash Relief (M7 nice-to-have, docs/feel/M7_polish_spec.md §Эффект 4).
# Particle trails dropped 2026-04-30 (invisible в 1st-person). Остались только
# эффекты которые игрок чувствует/слышит:
# Mode A (Normal) при speed_ratio ≥ DASH_RELIEF_THRESHOLD на момент dash_started:
#   no-op (только базовый dash whoosh + camera push выше).
# Mode B (Relief) при speed_ratio < DASH_RELIEF_THRESHOLD:
#   FOV exhale −3° + delayed audio check.
# Аудио-выдох играется через 0.5с (PostDashCheckTimer.wait_time в .tscn) после
# dash_started ТОЛЬКО если ratio поднялся выше threshold (dash «спас») — иначе
# нет облегчения.
const DASH_RELIEF_THRESHOLD := 0.40
const DASH_RELIEF_FOV_EXHALE := -3.0
const DASH_RELIEF_FOV_RETURN_MS := 400  # ease-out возврат к 0
var _was_relief_dash: bool = false  # set true в Mode B; читается в timeout

# M7 Kill Chain (docs/feel/M7_polish_spec.md §Эффект 3, revised 2026-04-30).
# Tier 1/2 — additive feel-effects (FOV punch + camera roll) поверх kill burst'а
# через 50ms задержку. Tier 7+ переведён на sustained semantics (см. ниже
# _on_kill_chain_streak_*) после плейтеста: per-kill jolts (FOV punch +15°,
# camera shake) на 7+ читались как «дёрганые», sustained FOV +10° + cap ceiling
# +10 = «in the zone» ощущение пока стрик активен.
const CHAIN_DELAY_S := 0.05  # пропуск kill burst frame'а перед chain effects
# FOV punch per tier (additive к kill burst +15°)
const CHAIN_FOV_T1 := 8.0
const CHAIN_FOV_T2 := 12.0
const CHAIN_FOV_RETURN_T1_MS := 250
const CHAIN_FOV_RETURN_T2_MS := 300
# Camera roll ±deg → возврат
const CHAIN_ROLL_T1 := 1.5
const CHAIN_ROLL_T2 := 2.5
const CHAIN_ROLL_KICK_S := 0.10  # время до пика (snap-ish)
const CHAIN_ROLL_RETURN_T1_S := 0.20
const CHAIN_ROLL_RETURN_T2_S := 0.25

# Tier 7+ sustained streak. Entry: ramp to +10° за 0.3с ease-out, hold пока стрик
# активен. Exit: ramp обратно к 0 за 0.4с. Cap ceiling +10 параллельно через
# VelocityGate.set_ceiling_boost (apply_kill_restore берёт effective ceiling).
const STREAK_FOV_OFFSET := 10.0
const STREAK_FOV_RAMP_IN_S := 0.3
const STREAK_FOV_RAMP_OUT_S := 0.4
const STREAK_CEILING_BOOST := 10.0

# Heavy Breath integration: TODO M7 пакет 1 — когда breath audio будет интегрирован
# в audio-менеджере, добавить fade-out 1.2s в _on_dash_started Mode B (spec §Эффект
# 4 → Audio response). Сейчас breath не существует — заглушка ниже.

@onready var head = $Head
@onready var camera = $Head/Camera
@onready var raycast = $Head/Camera/RayCast
@onready var muzzle = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Muzzle
@onready var container = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Container
@onready var sound_footsteps = $SoundFootsteps
@onready var blaster_cooldown = $Cooldown
@onready var _post_dash_check_timer: Timer = $PostDashCheckTimer
@onready var _exhale_player: AudioStreamPlayer = $ExhalePlayer

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
	_kill_crack_player.bus = &"SFX"
	_kill_crack_player.stream = load("res://sounds/enemy_destroy.ogg")
	_kill_crack_player.volume_db = -6.0
	add_child(_kill_crack_player)

	# Dash whoosh (legacy, §1.4 spec note 2026-04-29). jump_b.ogg + pitch_scale
	# +200 cents — короткий, читается как whoosh. Создаётся здесь, играется в
	# _on_dash_started ниже.
	_dash_whoosh_player = AudioStreamPlayer.new()
	_dash_whoosh_player.name = "DashWhooshPlayer"
	_dash_whoosh_player.bus = &"SFX"
	_dash_whoosh_player.stream = load("res://sounds/jump_b.ogg")
	_dash_whoosh_player.pitch_scale = DASH_WHOOSH_PITCH
	_dash_whoosh_player.volume_db = 0.0
	add_child(_dash_whoosh_player)

	if not Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.connect(_on_enemy_killed)

	if not Events.dash_started.is_connected(_on_dash_started):
		Events.dash_started.connect(_on_dash_started)

	# Post-dash exhale check: 0.5с после dash_started, в Mode B играет audio только
	# если ratio к этому моменту > threshold (dash «спас»).
	if not _post_dash_check_timer.timeout.is_connected(_on_post_dash_check_timeout):
		_post_dash_check_timer.timeout.connect(_on_post_dash_check_timeout)

	# M7 Kill Chain: tier 1/2 per-kill kick + tier 7+ sustained streak entry/exit.
	if not Events.kill_chain_triggered.is_connected(_on_kill_chain_triggered):
		Events.kill_chain_triggered.connect(_on_kill_chain_triggered)
	if not Events.kill_chain_streak_entered.is_connected(_on_kill_chain_streak_entered):
		Events.kill_chain_streak_entered.connect(_on_kill_chain_streak_entered)
	if not Events.kill_chain_streak_exited.is_connected(_on_kill_chain_streak_exited):
		Events.kill_chain_streak_exited.connect(_on_kill_chain_streak_exited)

	# M9 reload state reset on new run / cancel on death (предыдущий run мог
	# окончиться mid-reload или с пустым magazine).
	if not Events.run_started.is_connected(_on_run_started):
		Events.run_started.connect(_on_run_started)
	if not Events.player_died.is_connected(_on_player_died):
		Events.player_died.connect(_on_player_died)

func _process(delta):
	# Handle functions
	handle_controls(delta)
	handle_gravity(delta)
	_tick_dash(delta)
	_tick_reload(delta)
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

	if _dash_time_remaining <= 0.0 and is_on_floor():
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
		input_mouse = event.relative / _effective_mouse_sensitivity()
		handle_rotation(event.relative.x, event.relative.y, false)


# Effective divisor: base 700 / multiplier(0.5..2.0). Multiplier=1.0 → 700 (legacy
# behavior), 2.0 → 350 (faster), 0.5 → 1400 (slower). Multiplier clamp'нут в
# AudioSettings к MIN..MAX (>0), divide-by-zero невозможен.
func _effective_mouse_sensitivity() -> float:
	return mouse_sensitivity / AudioSettings.get_mouse_sensitivity_multiplier()

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

	# Reload (manual). Auto-reload trigger живёт в action_shoot() при ammo==0.

	if Input.is_action_just_pressed("reload"):
		_try_reload()

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
		rotation_target += (Vector3(-yRot, -xRot, 0) / _effective_mouse_sensitivity())
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
	# CD gate ТОЛЬКО для double-jump (second jump в воздухе). First jump с земли
	# всегда instant и CD не ставит — bar HUD не появляется на первый jump.
	# JUMP_COOLDOWN ставится только после consume'а double-jump'а; persists across
	# landings (rate-limit на double-jump globally).
	var is_first_jump: bool = jumps_remaining == number_of_jumps
	if not is_first_jump and _jump_cooldown_remaining > 0.0:
		return
	Audio.play("sounds/jump_a.ogg, sounds/jump_b.ogg, sounds/jump_c.ogg")
	gravity = - jump_strength
	jumps_remaining -= 1
	if not is_first_jump:
		_jump_cooldown_remaining = JUMP_COOLDOWN

# Shooting

func action_shoot():
	if Input.is_action_pressed("shoot"):
		# M9: reload locks shoot. Cooldown check после, иначе Cooldown timer мог бы
		# истечь во время reload и первый shot пройти раньше времени reload-завершения.
		if _is_reloading: return
		# Empty magazine → попытка auto-reload (gated cap >= RELOAD_COST). Если cap'а
		# нет — weapon dry, игрок должен kill'ить чтобы accumулировать cap для reload'а.
		if _current_ammo <= 0:
			_try_reload()
			return
		if !blaster_cooldown.is_stopped(): return # Cooldown for shooting

		Audio.play(weapon.sound_shoot)
		
		# Set muzzle flash position, play animation
		
		muzzle.play("default")
		
		muzzle.rotation_degrees.z = randf_range(-45, 45)
		muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
		muzzle.position = container.position - weapon.muzzle_position
		
		blaster_cooldown.start(weapon.cooldown)
		_current_ammo = maxi(0, _current_ammo - 1)

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
	# M9: новое оружие — magazine full, отменяем активный reload (если был mid-reload
	# на старом weapon — switch'нул на новый, старый timer не имеет смысла).
	_current_ammo = weapon.max_ammo
	_is_reloading = false
	_reload_timer = 0.0

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
	# Jump CD ticks параллельно — reset'ится handle_gravity на ground touch.
	if _jump_cooldown_remaining > 0.0:
		_jump_cooldown_remaining = maxf(0.0, _jump_cooldown_remaining - delta)


# Читается DebugHud'ом. M2 уберём в HUD-проекте отдельным узлом.
func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_remaining


# Читается RunHud'ом для cooldown bar (под cap bar'ом). Только double-jump CD —
# первый jump с земли всегда instant, его нет смысла визуализировать.
func get_jump_cooldown_remaining() -> float:
	return _jump_cooldown_remaining


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
# forward → ease-out 200ms + audio whoosh (legacy jump_b.ogg + pitch +200 cents).
# Audio вернулся сюда 2026-04-29 после F5-плейтеста — M5 dash_whoosh.ogg в
# autoload/sfx.gd звучал артефактом, откатились к pre-M5 пути. Все слои
# срабатывают на один и тот же signal Events.dash_started.
func _on_dash_started() -> void:
	# No is_alive guard here: handle_controls() возвращает рано если is_alive=false,
	# поэтому _try_start_dash() не может вызваться и signal не эмитится на dead-кадре.
	if fov_controller != null:
		fov_controller.kick(12.0, 250, "ease_out_quart")
	# Camera push: instant offset, decay через _tick_feel.
	_camera_push_total = float(DASH_PUSH_MS) / 1000.0
	_camera_push_remaining = _camera_push_total
	camera.position.z = -DASH_PUSH_DISTANCE
	if _dash_whoosh_player != null:
		_dash_whoosh_player.play()

	# M7 Dash Relief (Mode B only — particle trails dropped 2026-04-30, invisible
	# в 1st-person). Если speed_ratio < threshold в момент старта dash'а, играем
	# FOV exhale + отложенный audio-puff через ExhalePlayer. >= threshold — no-op
	# (только базовый dash whoosh выше).
	var ratio_at_start: float = VelocityGate.speed_ratio()
	if ratio_at_start < DASH_RELIEF_THRESHOLD:
		_was_relief_dash = true
		# FOV exhale: signed kick — magnitude=-3 даёт мгновенное смещение −3° от
		# текущего FOV, ease_out возвращает к 0 за DASH_RELIEF_FOV_RETURN_MS. Это
		# поверх dash +12° stretch'а — двухтактный «вдох-выдох» ритм. [PIVOT]
		if fov_controller != null:
			fov_controller.kick(DASH_RELIEF_FOV_EXHALE, DASH_RELIEF_FOV_RETURN_MS, "ease_out")
		# Schedule post-dash exhale audio check.
		if _post_dash_check_timer != null:
			_post_dash_check_timer.start()
		# TODO M7 пакет 1: fade-out heavy breath audio (1.2s) если активен.
		# Сейчас heavy breath ещё не интегрирован — заглушка.
	else:
		_was_relief_dash = false


# M7 Kill Chain handler (tier 1/2 only). Tier 7+ обрабатывается через
# _on_kill_chain_streak_entered/exited ниже (sustained state, не per-kill jolt).
# Delay 50ms — kill burst (FOV +15°, hit-stop) уже отыграл, chain накладывается «вторым слоем».
func _on_kill_chain_triggered(tier: int, _hit_pos: Vector3) -> void:
	if not VelocityGate.is_alive:
		return
	# await чтобы kill burst frame отыграл первым. PROCESS pause-mode default —
	# на pause kill_chain не emit'ится (KillChain Timer pausable), так что safe.
	await get_tree().create_timer(CHAIN_DELAY_S).timeout
	if not is_instance_valid(self) or not VelocityGate.is_alive:
		return

	# FOV punch (additive — fov_controller суммирует все active kicks).
	var fov_mag: float
	var fov_ms: int
	match tier:
		1:
			fov_mag = CHAIN_FOV_T1
			fov_ms = CHAIN_FOV_RETURN_T1_MS
		2:
			fov_mag = CHAIN_FOV_T2
			fov_ms = CHAIN_FOV_RETURN_T2_MS
		_:
			return
	if fov_controller != null:
		fov_controller.kick(fov_mag, fov_ms, "ease_out_cubic")

	# Camera roll — ±direction рандомно, чтобы каждый chain trigger не выглядел идентично.
	var roll_mag: float = (CHAIN_ROLL_T1 if tier == 1 else CHAIN_ROLL_T2)
	var roll_return: float = (CHAIN_ROLL_RETURN_T1_S if tier == 1 else CHAIN_ROLL_RETURN_T2_S)
	var roll_dir: float = 1.0 if (randi() % 2) == 0 else -1.0
	_kick_camera_roll(deg_to_rad(roll_mag * roll_dir), CHAIN_ROLL_KICK_S, roll_return)


# M7 Kill Chain Tier 7+ streak entry/exit handlers. Sustained higher FOV +
# cap ceiling boost пока стрик активен. Идемпотентность entered/exited —
# kill_chain.gd флагом _streak_active.
func _on_kill_chain_streak_entered(_hit_pos: Vector3) -> void:
	if not VelocityGate.is_alive:
		return
	VelocityGate.set_ceiling_boost(STREAK_CEILING_BOOST)
	if fov_controller != null:
		fov_controller.set_sustained_offset(STREAK_FOV_OFFSET, STREAK_FOV_RAMP_IN_S)


func _on_kill_chain_streak_exited() -> void:
	# Не гардим is_alive: streak_exited может прилететь от player_died handler'а
	# в kill_chain.gd, и тогда мы должны очистить state даже если is_alive=false.
	VelocityGate.clear_ceiling_boost()
	if fov_controller != null:
		fov_controller.clear_sustained_offset(STREAK_FOV_RAMP_OUT_S)


# Camera roll kick: tween rotation.z до peak за kick_s, потом обратно к 0 за return_s.
# Существующая система не имеет roll'а — camera.rotation.z остаётся 0 в обычной игре,
# поэтому полный диапазон free для нас. На дёрганье от двух chain trigger'ов подряд
# второй tween затрёт первый — это OK (последний всегда побеждает, сохраняет
# тайминг возврата).
func _kick_camera_roll(peak_rad: float, kick_s: float, return_s: float) -> void:
	if camera == null:
		return
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(camera, "rotation:z", peak_rad, kick_s).set_ease(Tween.EASE_OUT)
	tw.tween_property(camera, "rotation:z", 0.0, return_s).set_ease(Tween.EASE_OUT)


func _on_post_dash_check_timeout() -> void:
	# Только Mode B расписывает таймер; защита на случай гонки если был перезапуск.
	if not _was_relief_dash:
		return
	if not VelocityGate.is_alive:
		return
	# Dash «спас» — текущий ratio выше threshold через 0.5с после старта. Играем
	# короткий выдох (jump_b.ogg, pitch -100 cents = 0.944, -6 dB — настроено в
	# .tscn). Если ratio остался ниже — облегчения нет, exhale не играет.
	if VelocityGate.speed_ratio() > DASH_RELIEF_THRESHOLD:
		if _exhale_player != null:
			_exhale_player.play()


# M9 reload: проверяет cap >= RELOAD_COST, списывает cost через VelocityGate (отдельный
# path от apply_hit — без vignette flash, без player_hit signal'а). Если cap'а нет —
# silent fail (одинаково для manual и auto pressed на empty).
func _try_reload() -> void:
	if not VelocityGate.is_alive:
		return
	if _is_reloading:
		return
	if _current_ammo >= weapon.max_ammo:
		return  # Magazine уже full — no-op (избегаем «бесплатной» trade-of cap'а)
	if VelocityGate.velocity_cap < float(VelocityGate.RELOAD_COST):
		return  # Reload запрещён — игрок должен killить чтобы накопить cap
	_is_reloading = true
	_reload_timer = RELOAD_DURATION


func _tick_reload(delta: float) -> void:
	if not _is_reloading:
		return
	# Death cancels reload — VelocityGate.is_alive флипает в false до того как mы
	# доберёмся до completion'а. Чистим state и выходим.
	if not VelocityGate.is_alive:
		_is_reloading = false
		_reload_timer = 0.0
		return
	_reload_timer = maxf(0.0, _reload_timer - delta)
	if _reload_timer <= 0.0:
		# Списать cap в момент завершения (а не старта) — чтобы хит во время reload
		# не комбинировался с reload-cost'ом и не убил игрока через cap=0. Если за
		# время reload'а cap упал ниже RELOAD_COST — refund'им magazine не на полный
		# (apply_reload_cost вернёт false), reload «провалился», ammo остаётся 0.
		var ok: bool = VelocityGate.apply_reload_cost()
		_is_reloading = false
		_reload_timer = 0.0
		if ok:
			_current_ammo = weapon.max_ammo


func _on_run_started() -> void:
	# Свежий run: magazine full, reload state cleared. Auto-reload не нужен (полный mag).
	if weapon != null:
		_current_ammo = weapon.max_ammo
	_is_reloading = false
	_reload_timer = 0.0


func _on_player_died() -> void:
	# Death во время reload — cancel сразу, не ждём _tick_reload (он guard'ит is_alive
	# но эмит weapon_reloaded мог бы пройти если death и timer expire совпали по кадрам).
	_is_reloading = false
	_reload_timer = 0.0


# HUD читает эти геттеры — ammo counter + reload progress. Method-based, чтобы HUD
# не залезал в private state напрямую (конвенция как get_dash_cooldown_remaining).
func get_current_ammo() -> int:
	return _current_ammo


func get_max_ammo() -> int:
	return weapon.max_ammo if weapon != null else 0


func is_reloading() -> bool:
	return _is_reloading


func get_reload_progress() -> float:
	# 0..1: 0 в начале reload'а, 1 в момент завершения.
	if not _is_reloading or RELOAD_DURATION <= 0.0:
		return 0.0
	return clampf(1.0 - _reload_timer / RELOAD_DURATION, 0.0, 1.0)


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
