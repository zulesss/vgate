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

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var contact_area: Area3D = $ContactArea if has_node("ContactArea") else null

var hp: int
var is_dying: bool = false
var state: int = State.IDLE
var _attack_cooldown_remaining: float = 0.0
var _attack_windup_remaining: float = 0.0
var _is_winding_up: bool = false
var _player: Node3D = null

# Iter 2 diagnostic trace (M3a fix) — printed once per 0.5s when state==CHASE.
# Cleanup TODO: remove after Iter 2 confirms movement on Windows playtest.
var _trace_timer: float = 0.0
var _was_chase_last_tick: bool = false
var _logged_no_player: bool = false

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
	print("[ENEMY ", name, "] _ready: player=", _player, " group_count=", players.size())

	# Material instance для telegraph: clone из mesh override чтобы не делить
	# материал между всеми экземплярами (иначе telegraph мигнёт всех сразу).
	if mesh_instance != null and mesh_instance.get_surface_override_material(0) != null:
		var src := mesh_instance.get_surface_override_material(0) as StandardMaterial3D
		if src != null:
			_material = src.duplicate() as StandardMaterial3D
			mesh_instance.set_surface_override_material(0, _material)
			_base_emission_color = _material.emission
			_base_emission_energy = _material.emission_energy_multiplier

	# Stagger: первая атака разнесена 0..1.5с от базового cooldown'а.
	# Применяем как initial cooldown — first attack откладывается.
	_attack_cooldown_remaining = randf_range(0.0, 1.5)


func _physics_process(delta: float) -> void:
	if is_dying:
		return
	if _player == null:
		if not _logged_no_player:
			print("[ENEMY ", name, "] _player == null — early return")
			_logged_no_player = true
		return

	if _attack_cooldown_remaining > 0.0:
		_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)

	# Telegraph windup tick: считаем до 0, потом resolve_attack(). Если игрок выйдет
	# из range/sightline во время windup — _resolve_attack делает abort без damage'а.
	if _is_winding_up:
		_attack_windup_remaining = maxf(0.0, _attack_windup_remaining - delta)
		if _attack_windup_remaining <= 0.0:
			_is_winding_up = false
			_resolve_attack()

	_update_state()
	_apply_movement(delta)

	# Iter 2 diagnostic trace: throttled per-enemy 0.5s, печатаем когда враг ДОЛЖЕН
	# двигаться (CHASE сейчас или был на прошлом тике — ловим переходы CHASE→ATTACK).
	_trace_timer += delta
	var is_chase: bool = (state == State.CHASE)
	if (is_chase or _was_chase_last_tick) and _trace_timer >= 0.5:
		_trace_timer = 0.0
		var nf: bool = nav_agent != null and nav_agent.is_navigation_finished()
		var tgt: Vector3 = nav_agent.target_position if nav_agent != null else Vector3.ZERO
		var nxt: Vector3 = nav_agent.get_next_path_position() if nav_agent != null else Vector3.ZERO
		print("[ENEMY ", name, "] CHASE dist=", "%.2f" % _distance_to_player(),
			" nav_finished=", nf, " target=", tgt, " next_path=", nxt,
			" velocity=", velocity, " self=", global_position, " player=", _player.global_position)
	_was_chase_last_tick = is_chase


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
	# Idle / windup → стоп. Chase → к player через NavAgent. Attack — windup тоже стоп.
	if state == State.IDLE or _is_winding_up:
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


# Зовётся player.gd → action_shoot → raycast collider.damage(weapon.damage).
# Имя метода + untyped amount — Starter Kit convention (damage у них float).
func damage(amount) -> void:
	if is_dying:
		return
	hp -= int(amount)
	if hp <= 0:
		is_dying = true
		die()


func die() -> void:
	VelocityGate.apply_kill_restore(global_position)
	queue_free()


# Только Melee. Shooter не имеет ContactArea node — connect не вызывается.
func _on_contact_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	# i-frames гасятся внутри VelocityGate.apply_hit — здесь просто шлём.
	VelocityGate.apply_hit(attack_penalty)
