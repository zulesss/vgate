class_name EnemyBase extends CharacterBody3D

# M3a base for Shooter / Melee — общий каркас:
#   - HP + damage()/die() + idempotency guard (наследие M1 dummy: blaster spread=3
#     даёт 3 hit'а в кадр, без is_dying получим 3× kill_restore; M2 review confirm)
#   - NavigationAgent3D pathing к player
#   - ContactArea: только Melee использует (отключаем у Shooter в shooter.tscn)
#   - Stagger: attack_delay_offset = randf(0..1.5) применяется при первой атаке.
#     Цель — разнести attacks при density 5+ (см. M3_enemy_numbers §5 risk callout).
#   - Attack state machine: Idle / Chase / Attack (+ Reposition у Shooter, override).
#
# Числа per-type — экспортируются и инициализируются default'ами для Melee. Shooter
# переопределяет в _ready(). Это компромисс: один base, одни поля, но конкретные
# значения per-class. Альтернатива (отдельные base'ы) — over-engineering под 2 типа.

enum State { IDLE, CHASE, ATTACK, REPOSITION }

# Числа берутся из docs/systems/M3_enemy_numbers.md. Переопределяются в подклассе.
@export var max_hp: int = 20
@export var move_speed: float = 5.5
@export var attack_range: float = 1.5
@export var attack_windup: float = 0.45  # секунды
@export var attack_cooldown: float = 2.5
@export var detection_radius: float = 35.0
@export var attack_penalty: int = 20  # default = MELEE_PENALTY

# Lunge на windup'е: финальные lunge_window секунд windup'а melee делает рывок
# к текущей позиции игрока на lunge_speed u/s (см. M3_identity §2). Default 0 =
# lunge выключен (shooter — frozen на windup'е, ему рваться вперёд незачем).
# Подкласс melee включает в _ready'е (lunge_speed=7.5, lunge_window=0.20).
@export var lunge_speed: float = 0.0
@export var lunge_window: float = 0.0

# Face-player rotation speed (rad/s). Применяется во всех движущихся state'ах
# и во время attack windup'а (telegraph должен смотреть на игрока). ~8 rad/s
# = полный оборот за ~0.78с — достаточно быстро для shooter-strafe-tracking,
# но не snap-щёлкает у melee при resposition'е игрока. IDLE/dying/spawning
# не крутятся (early-return в _physics_process).
const TURN_SPEED := 8.0
# Quaternius enemy rigs (melee, shooter) смотрят в -Z направлении — совпадает
# с Godot 3D convention (forward = -Z). atan2(to_player.x, to_player.z) даёт
# yaw, при котором локальный -Z указывает на игрока, без offset'а.
# (Изначально предположили +Z forward → добавили PI offset → F5 показал, что
#  враги смотрели спиной. Bbox-анализ был обманчив, ground-truth — playtest.)

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
# visual_root: контейнер визуала для transform-tween'ов (melee telegraph
# scale.y bump). Для GLB-инстансов (M5) — нода "Visual" (instance из tscn).
# Для placeholder fallback (subclass без "Visual" нода) — первый MeshInstance3D
# в subtree. Резолвится в _ready'е через find_children.
var visual_root: Node3D = null
@onready var contact_area: Area3D = $ContactArea if has_node("ContactArea") else null

# AnimationPlayer внутри GLB-инстанса (Quaternius rigged-mesh). Резолвится
# recursive find_child'ом — Godot кладёт AnimationPlayer глубоко в imported
# subtree (под armature root). owned=false: AnimationPlayer владеет imported
# scene root, не self. Если плеера нет (placeholder без GLB) — все
# _play_anim* вызовы становятся no-op (guard внутри).
var _anim_player: AnimationPlayer = null
# Кэш имени текущей loop-анимации, чтобы не дёргать play() каждый physics-кадр
# при том же state'е (idempotency для _update_state spam'а — _update_state может
# звать _set_loop_anim с тем же именем 60 раз/с).
var _current_loop_anim: StringName = &""

var hp: int
# True пока играется one-shot анимация поверх loop'а (Charge/Attack/Hit/death).
# _set_loop_anim() уважает этот флаг — не перебивает one-shot loop'ом.
var _oneshot_active: bool = false
var is_dying: bool = false
# Spawn telegraph (M4): пока true — _physics_process выходит сразу, AI/attack/movement
# заморожены. SpawnController снимает флаг по окончании 250мс fade-tween. Default
# false (для существующих врагов / редактора), SpawnController выставляет true сразу
# после instantiate перед add_child.
var is_spawning: bool = false
var state: int = State.IDLE
var _attack_cooldown_remaining: float = 0.0
var _attack_windup_remaining: float = 0.0
var _is_winding_up: bool = false
var _player: Node3D = null

# Cached material (instanced per-enemy), для telegraph flash. Базовый цвет
# фиксируется в _ready'е (читается из mesh material override) — telegraph меняет
# emission, не albedo, чтобы не терять идентификацию типа.
var _base_emission_color: Color = Color.BLACK
var _base_emission_energy: float = 0.0
var _material: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp

	# NavigationAgent3D: per-frame pathing достаточно дёшево на 4 enemies. Меняем
	# только если spawn-controller M4 вырастет до 30+ — тогда throttle до 5 Hz.
	# Параметры path/target_desired_distance заданы в enemy_base.tscn (0.5/0.5).

	# ContactArea — только Melee. Shooter physically не контачит для damage'а
	# (он ranged), но scene-файл shooter'а просто не имеет ContactArea node.
	if contact_area != null:
		contact_area.body_entered.connect(_on_contact_body_entered)

	# Player — single instance в группе. Группа добавляется в player.gd._ready().
	# Если не нашли — Idle до конца жизни (защита от race условия инициализации).
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as Node3D

	# Резолв визуала: GLB-инстансы (M5) кладут MeshInstance3D'ы глубоко в
	# armature subtree (Quaternius rig, 1-2 skinned meshes на enemy). Direct
	# $MeshInstance3D path не работает; используем recursive find_children с
	# owned=false (владелец imported nodes = imported root, не self).
	var meshes := find_children("*", "MeshInstance3D", true, false)
	if has_node("Visual"):
		visual_root = $Visual as Node3D
	elif meshes.size() > 0:
		visual_root = meshes[0] as Node3D

	# Material instance для telegraph: clone из mesh material'а чтобы не делить
	# материал между всеми экземплярами (иначе telegraph мигнёт всех сразу).
	# get_active_material покрывает оба случая: surface_override (placeholder)
	# и mesh-baked (GLB, материал внутри ImporterMesh). Duplicate'нутый material
	# затем ставится как surface_override на ВСЕ MeshInstance3D в subtree —
	# Quaternius models имеют 1-2 mesh'а на одном материале (MI_Enemies/Large),
	# uniform flash требует override на каждом.
	if meshes.size() > 0:
		var src := (meshes[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if src != null:
			_material = src.duplicate() as StandardMaterial3D
			for m in meshes:
				(m as MeshInstance3D).set_surface_override_material(0, _material)
			_base_emission_color = _material.emission
			_base_emission_energy = _material.emission_energy_multiplier

	# Stagger: первая атака разнесена 0..1.5с от базового cooldown'а.
	# Применяем как initial cooldown — first attack откладывается.
	_attack_cooldown_remaining = randf_range(0.0, 1.5)

	# AnimationPlayer внутри GLB-instance (под armature). owned=false — узел
	# принадлежит imported scene root'у, не self'у. Если placeholder без GLB —
	# плеера нет, все _play_anim* — no-op.
	_anim_player = find_child("AnimationPlayer", true, false) as AnimationPlayer
	# Idle сразу при spawn'е — пусть враг "оживает" даже во время 250мс fade-in.
	# AnimationPlayer независим от _physics_process, is_spawning его не блокирует.
	var idle_anim := _anim_for_state(State.IDLE)
	if idle_anim != &"":
		_set_loop_anim(idle_anim)


func _physics_process(delta: float) -> void:
	if is_dying:
		return
	if is_spawning:
		return
	# Death-pause: игрок мёртв → freeze AI/attack/movement. Без guard'а windup
	# дотикает и _resolve_attack() ударит уже в dead-state'е (cap drain ниже нуля).
	# SpawnController на run_started всё равно queue_free'нет всех — здесь только
	# заморозка, не cleanup. velocity=ZERO + move_and_slide() гасит инерцию падения.
	if not VelocityGate.is_alive:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _player == null:
		return

	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	# Telegraph windup tick: считаем до 0, потом resolve_attack(). Если игрок выйдет
	# из range/sightline во время windup — _resolve_attack делает abort без damage'а.
	# Guard is_dying ВНУТРИ windup-блока: damage()→die() в кадре когда _is_winding_up,
	# без guard'а _attack_windup_remaining дотикает до 0 и _resolve_attack() ударит
	# игрока уже от queue_freed enemy. Обнуляем lunge-движение и attack-resolve.
	if _is_winding_up:
		if is_dying:
			return
		_attack_windup_remaining = maxf(0.0, _attack_windup_remaining - delta)
		if _attack_windup_remaining <= 0.0:
			_is_winding_up = false
			_resolve_attack()

	_update_state()
	# Синхронизация loop-анимации со state'ом ПОСЛЕ _update_state. Подкласс
	# override'ит _anim_for_state — мапинг state→имя. Не трогаем во время
	# windup'а (telegraph one-shot уже играет: Charge/Charging) и if mid-Hit
	# one-shot — _set_loop_anim проверит активность one-shot через
	# _oneshot_active.
	if not _is_winding_up:
		var loop_name := _anim_for_state(state)
		if loop_name != &"":
			_set_loop_anim(loop_name)
	# Face-player ДО _apply_movement: rotation независим от velocity. Крутим
	# во время CHASE / REPOSITION / ATTACK-windup (telegraph должен смотреть
	# на игрока). IDLE намеренно тоже крутится — "стоит как стоял" работает
	# плохо когда враг детектит игрока за спиной (detection_radius 35) и
	# должен повернуться чтобы начать chase. Cost: ~ничего, lerp-cheap.
	_face_player(delta)
	_apply_movement(delta)


# Smooth-rotate тело CharacterBody3D вокруг Y-axis к игроку. Visual ребёнок
# крутится вместе. Анимации Run/Idle проигрываются в local-space модели —
# rotation.y body не ломает skinned-mesh pose. Обнуляем Y компонент vector'а
# чтобы враг не наклонял голову при разной высоте игрока.
func _face_player(delta: float) -> void:
	if _player == null:
		return
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(to_player.x, to_player.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * TURN_SPEED)


# Подклассы переопределяют для добавления Reposition state. По дефолту: Idle / Chase / Attack.
func _update_state() -> void:
	if _is_winding_up:
		return  # frozen во время telegraph
	var dist := _distance_to_player()
	if dist > detection_radius:
		state = State.IDLE
		return
	if dist <= attack_range:
		# В range. Если cooldown готов — атакуем. Иначе остаёмся в Chase (но физически
		# не двигаемся ближе — _apply_movement учтёт это).
		if _attack_cooldown_remaining <= 0.0:
			_start_attack()
			return
		state = State.CHASE
		return
	state = State.CHASE


func _apply_movement(_delta: float) -> void:
	# Idle → стоп. Chase → к player через NavAgent. Windup: melee делает snap-lunge
	# в финальные lunge_window секунд (direct direction к player.global_position,
	# не через NavAgent — на 200мс пересчитывать path дорого, а в attack_range
	# игрок почти всегда в LOS). Shooter имеет lunge_speed=0 → frozen как раньше.
	if state == State.IDLE:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _is_winding_up:
		if (
			lunge_speed > 0.0
			and _attack_windup_remaining < lunge_window
			and _player != null
		):
			var lunge_dir: Vector3 = _player.global_position - global_position
			lunge_dir.y = 0.0
			if lunge_dir.length() > 0.001:
				lunge_dir = lunge_dir.normalized()
				velocity = lunge_dir * lunge_speed
			else:
				velocity = Vector3.ZERO
		else:
			velocity = Vector3.ZERO
		move_and_slide()
		return
	if state != State.CHASE:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	if _player == null or nav_agent == null:
		return

	# Если уже в attack_range — не лезем ближе (особенно для shooter'а).
	if _distance_to_player() <= attack_range:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	nav_agent.target_position = _player.global_position
	if nav_agent.is_navigation_finished():
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var dir: Vector3 = (next_pos - global_position)
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
	velocity = dir * move_speed
	move_and_slide()


func _distance_to_player() -> float:
	if _player == null:
		return INF
	return global_position.distance_to(_player.global_position)


func _start_attack() -> void:
	state = State.ATTACK
	_is_winding_up = true
	_attack_windup_remaining = attack_windup
	_play_telegraph()


# Подклассы override — Melee делает melee damage, Shooter делает raycast attack.
func _resolve_attack() -> void:
	_end_telegraph()
	_attack_cooldown_remaining = attack_cooldown


# Подкласс заполняет visual+audio. Base — пустой (защита от crash если override забыли).
func _play_telegraph() -> void:
	pass


func _end_telegraph() -> void:
	pass


# Подкласс override'ит для маппинга state→имя loop-анимации. Возвращает &""
# когда нет анимации (placeholder без GLB / state без подходящей animации
# в rig'е). Default: пусто — base не знает имена анимаций конкретного rig'а.
func _anim_for_state(_s: int) -> StringName:
	return &""


# Idempotent loop-анимация: если уже играет с таким именем — no-op. Не перебивает
# активный one-shot (Charge/Attack/Hit/death) — loop вернётся когда one-shot закончится.
func _set_loop_anim(anim_name: StringName) -> void:
	if _anim_player == null:
		return
	if _oneshot_active:
		return
	if _current_loop_anim == anim_name and _anim_player.is_playing():
		return
	if not _anim_player.has_animation(anim_name):
		return
	# Loop-флаг настраиваем на самой Animation-resource'е. Quaternius анимации
	# могут идти как ONCE — для Idle/Run нужен LOOP_LINEAR.
	var anim := _anim_player.get_animation(anim_name)
	if anim != null and anim.loop_mode != Animation.LOOP_LINEAR:
		anim.loop_mode = Animation.LOOP_LINEAR
	_anim_player.play(anim_name)
	_current_loop_anim = anim_name


# One-shot поверх loop'а. После окончания — возвращаемся к loop-анимации
# текущего state'а. Прерывает текущий one-shot если уже играет (последний
# trigger выигрывает: Hit поверх Charge, Attack поверх Charge — обычный flow).
func _play_oneshot(anim_name: StringName) -> void:
	if _anim_player == null:
		return
	if not _anim_player.has_animation(anim_name):
		return
	var anim := _anim_player.get_animation(anim_name)
	if anim != null and anim.loop_mode != Animation.LOOP_NONE:
		anim.loop_mode = Animation.LOOP_NONE
	# Disconnect старый animation_finished listener чтобы не получить double-fire
	# на back-to-back one-shot'ах. Используем connect с CONNECT_ONE_SHOT.
	if _anim_player.animation_finished.is_connected(_on_oneshot_finished):
		_anim_player.animation_finished.disconnect(_on_oneshot_finished)
	_anim_player.animation_finished.connect(_on_oneshot_finished, CONNECT_ONE_SHOT)
	_anim_player.play(anim_name)
	_oneshot_active = true
	_current_loop_anim = &""  # инвалидируем кэш — после one-shot'а _set_loop_anim
	# должен заново play() loop-анимацию даже с тем же именем.


func _on_oneshot_finished(_anim_name: StringName) -> void:
	_oneshot_active = false
	# Loop-анимация вернётся на следующем _physics_process'е через _set_loop_anim
	# из main loop'а. Если is_dying — не возвращаемся ни к чему: queue_free скоро.


# Зовётся player.gd → action_shoot → raycast collider.damage(weapon.damage).
# Имя метода + untyped amount — Starter Kit convention (damage у них float).
func damage(amount) -> void:
	if is_dying:
		return
	hp -= int(amount)
	# Audible feedback per hit (включая killing blow — legacy enemy.gd:31 поведение).
	# Pool в scripts/audio.gd сидит на SFX bus (commit 9bca5e5) — слайдер SFX покрывает.
	Audio.play("sounds/enemy_hurt.ogg")
	if hp <= 0:
		is_dying = true
		die()
		return
	# Hit reaction: short one-shot поверх state-loop'а. Edge case: если
	# _is_winding_up — не пускаем Hit, оставляем Charge/Charging играть до
	# конца. Telegraph emission flash + audio cue остаются как сигнал —
	# обрывать визуальный wind-up на 0.1с до удара читается хуже.
	# (Игрок видит windup, успевает уклониться — это feel-приоритет.)
	if not _is_winding_up:
		_play_oneshot(_hit_anim_name())


# Подкласс возвращает имя hit-анимации в своём rig'е. Default пусто — база
# без знания rig'а не пускает hit (одинаково для placeholder и для unknown rig'а).
func _hit_anim_name() -> StringName:
	return &""


func die() -> void:
	# Type tag в kill-сигнал нужен ScoreState (base score 100/150) и SpawnController
	# (live_shooters счётчик). Подкласс override _kill_type если новый тип появится.
	# apply_kill_restore — gameplay-impact (cap restore + counter), вызываем СРАЗУ.
	# queue_free отложен до конца death-анимации (max 0.6s — чтобы труп не блокировал
	# geometry дольше). collision_layer=0: отключаем дальнейшие raycast'ы / contact'ы
	# (player может стрелять в умирающего, ловить на body collision'е — нечестно).
	VelocityGate.apply_kill_restore(global_position, _kill_type())
	collision_layer = 0
	collision_mask = 0
	_play_death_animation_then_free()


func _play_death_animation_then_free() -> void:
	var death_name := _death_anim_name()
	var wait_time: float = 0.0
	if _anim_player != null and death_name != &"" and _anim_player.has_animation(death_name):
		var anim := _anim_player.get_animation(death_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_NONE
			# Cap = 0.6с (per brief): достаточно для большинства Quaternius rig-death'ов
			# (TurnOff ≈ 0.5с, BackFlip ≈ 0.7с — обрежем). Дольше — труп блокирует geometry.
			wait_time = minf(anim.length, 0.6)
		# Disconnect oneshot listener — death игнорирует _oneshot_active flow,
		# у нас свой timer-based wait.
		if _anim_player.animation_finished.is_connected(_on_oneshot_finished):
			_anim_player.animation_finished.disconnect(_on_oneshot_finished)
		_anim_player.play(death_name)
	if wait_time > 0.0:
		await get_tree().create_timer(wait_time).timeout
	queue_free()


# Подкласс возвращает имя death-анимации в своём rig'е. Default пусто — без
# анимации queue_free сразу (для placeholder/dummy без GLB).
func _death_anim_name() -> StringName:
	return &""


# Default: melee. Shooter переопределит "shooter". Расширяемая convention для будущих
# типов вместо if/else в base'е по `is EnemyShooter` (избегаем cycle import'ов).
func _kill_type() -> String:
	return "melee"


# Только Melee. Shooter не имеет ContactArea node — connect не вызывается.
func _on_contact_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# i-frames гасятся внутри VelocityGate.apply_hit — здесь просто шлём.
	VelocityGate.apply_hit(attack_penalty)
