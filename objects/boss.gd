class_name EnemyBoss extends EnemyMelee

# Cathedral R-final boss — 3-phase HP-based encounter с разнообразием attack
# patterns сверх единственного default-swing. Identity сохраняется (golden HDR
# emissive + scale 1.6 + slower / heavier tempo чем regular melee), variety
# теперь читается через phase transitions.
#
# Phase tracking (Pkg A, this commit):
#   - Phase 1 (HP > 67%) — only default melee swing (как раньше)
#   - Phase 2 (HP 67–34%) — transition cue + spawn 1 swarmling reinforcement
#   - Phase 3 (HP < 34%)  — transition cue + speed boost 4 → 5
# Transitions: audio cue (enemy_destroy reuse via _telegraph_audio) + bright
# cream emissive flash 300мс на body. Pattern variety per-фаза приходит в Pkg B/C/D.
#
# Stats (locked, unchanged):
#   - HP 200 (≈ 8s sustained repeater fire)
#   - move_speed 4.0 (Phase 1/2), 5.0 (Phase 3)
#   - attack_range 2.5 (longer reach, narrow R4)
#   - attack_penalty 25, cooldown 2.5, windup 0.5, detection_radius 40
#
# Visual differentiation — золотой emissive HDR через override material'а после
# super._ready'я. Mesh scale 1.6 — transform на Visual node в boss.tscn.
# Collision shape остаётся melee-default (radius 0.5, height 1.7) — boss физически
# такого же радиуса, не толще, иначе застрянет в narrow R4 6u-corridor'е.

const BOSS_EMISSION_COLOR := Color(2.0, 0.8, 0.3)  # HDR golden — > 1.0 даёт bloom при tonemap'е
const BOSS_EMISSION_ENERGY := 1.5

# Phase thresholds (как доли max_hp). При HP=200: Phase 2 на ≤134, Phase 3 на ≤68.
const PHASE_2_HP_RATIO := 0.67
const PHASE_3_HP_RATIO := 0.34

# Phase 3 speed boost — финальная "свирепеет" фаза должна гнать сильнее.
const PHASE_3_MOVE_SPEED := 5.0

# ────────────────────────────────────────────────────────────────────
# Charge attack (Phase 2+) constants
# ────────────────────────────────────────────────────────────────────
# Mid-range gap-closer: telegraph 2s → dash 0.6s × 12 u/s = 7.2u в captured
# direction → recovery 0.5s vulnerable. Cooldown 4s. Penalty 30 (выше swing 25 —
# higher commitment, higher punishment). Direction captured при dash start
# (реактивный per user lock — игрок может в первые 2с telegraph'а сместиться).
const CHARGE_RANGE_MIN := 6.0
const CHARGE_RANGE_MAX := 12.0
const CHARGE_TELEGRAPH_DURATION := 2.0
const CHARGE_DASH_DURATION := 0.6
const CHARGE_DASH_SPEED := 12.0
const CHARGE_RECOVERY := 0.5
const CHARGE_COOLDOWN := 4.0
const CHARGE_PENALTY := 30
const CHARGE_HIT_RADIUS := 1.5  # contact-radius во время dash'а
# Telegraph emission: bright white pulse на _material — отличается от phase
# transition flash (cream gold) и от regular telegraph (ярко-красный) — игрок
# должен читать "boss готовится к dash'у", не "phase change" / "regular swing".
const CHARGE_TELEGRAPH_EMISSION_COLOR := Color(2.0, 2.0, 2.0)
const CHARGE_TELEGRAPH_EMISSION_ENERGY := 3.0

# Phase transition flash: bright cream HDR pulse 300мс на _material emission,
# потом возврат к golden. Заметно отличается от regular telegraph red flash
# (FLASH_EMISSION_COLOR=(1.0,0.2,0.1)) — читается как «фаза щёлкнула», не attack.
const PHASE_FLASH_COLOR := Color(3.0, 2.5, 1.5)
const PHASE_FLASH_ENERGY := 4.0
const PHASE_FLASH_DURATION := 0.30

# Phase tracking. Стартовая фаза = 1, transition в _check_phase_transition()
# при падении hp под threshold (вызывается после damage()).
var _current_phase: int = 1
var _phase_flash_tween: Tween

# Charge attack state. Telegraph → dash → recovery. Cooldown отдельно от regular
# attack_cooldown (boss может swing'нуть пока charge cooling, и наоборот).
# Hit-once flag: одно попадание per dash (multi-frame overlap не должен 3× drain'ить cap).
var _charging_telegraph: bool = false
var _charging_telegraph_timer: float = 0.0
var _charging_dash: bool = false
var _charging_dash_timer: float = 0.0
var _charge_recovery_timer: float = 0.0
var _charge_cooldown_timer: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_hit_applied: bool = false
var _charge_telegraph_tween: Tween


func _ready() -> void:
	# Stat overrides ДО super._ready (base скопирует hp = max_hp + начальный
	# stagger cooldown). Lunge оставляем включённым из melee parent'а — boss
	# тоже должен закрывать gap в финальные 300мс windup'а, иначе walk-back
	# escape'ит даже на slower 4.0 (player walk ~6.4 u/s при cap=80).
	max_hp = 200
	move_speed = 4.0
	attack_range = 2.5
	attack_windup = 0.5
	attack_cooldown = 2.5
	attack_penalty = 25
	detection_radius = 40.0
	super._ready()

	# Material override: super._ready клонировал base material из mesh'а (telegraph
	# flash работает на _material из base'а). Перезаписываем emission на golden HDR
	# и обновляем _base_emission_*, чтобы _end_telegraph (в melee.gd) возвращал именно
	# к boss-золоту, а не к стандартному melee-черному base'у.
	if _material != null:
		_material.emission_enabled = true
		_material.emission = BOSS_EMISSION_COLOR
		_material.emission_energy_multiplier = BOSS_EMISSION_ENERGY
		_base_emission_color = BOSS_EMISSION_COLOR
		_base_emission_energy = BOSS_EMISSION_ENERGY


func _kill_type() -> String:
	return "boss"


# ────────────────────────────────────────────────────────────────────
# Phase machine (Pkg A)
# ────────────────────────────────────────────────────────────────────

# Перехватываем damage() чтобы после hp-- проверить phase transition. super.damage
# делает is_dying guard / hp-- / die() / hit-anim — мы только хвостом смотрим
# на phase. Если super.die() флипает is_dying, transition skipped (boss мёртв).
func damage(amount) -> void:
	if is_dying:
		return
	super.damage(amount)
	if not is_dying:
		_check_phase_transition()


func _check_phase_transition() -> void:
	var hp_ratio: float = float(hp) / float(max_hp)
	var new_phase: int = 1
	if hp_ratio <= PHASE_3_HP_RATIO:
		new_phase = 3
	elif hp_ratio <= PHASE_2_HP_RATIO:
		new_phase = 2
	# Skip-phase scenario не покрываем: max single-hit (charged_blaster Tier 3 ~25dmg)
	# << HP gap между фазами (200×0.33 = 66hp). YAGNI.
	if new_phase > _current_phase:
		_current_phase = new_phase
		_apply_phase_transition(new_phase)


func _apply_phase_transition(phase: int) -> void:
	# Audio cue — переиспользуем enemy_destroy.ogg через _telegraph_audio (3D
	# spatial player добавлен в melee._ready). Heavier impact чем enemy_attack
	# и читается как «фаза щёлкнула», но из той же 3D-позиции — игрок
	# локализует boss'а на слух.
	if _telegraph_audio != null:
		_telegraph_audio.stream = load("res://sounds/enemy_destroy.ogg")
		_telegraph_audio.play()
		# Возвращаем default stream — regular telegraph'и снова стреляют enemy_attack'ом.
		_telegraph_audio.stream = load("res://sounds/enemy_attack.ogg")

	# Emissive flash на body — bright cream pulse 300ms, потом возврат к golden.
	# Tween parallel'ит emission color и energy multiplier — оба плавно возвращаются.
	if _material != null:
		if _phase_flash_tween != null and _phase_flash_tween.is_valid():
			_phase_flash_tween.kill()
		_material.emission = PHASE_FLASH_COLOR
		_material.emission_energy_multiplier = PHASE_FLASH_ENERGY
		_phase_flash_tween = create_tween()
		_phase_flash_tween.tween_property(
			_material, "emission_energy_multiplier", BOSS_EMISSION_ENERGY, PHASE_FLASH_DURATION
		).set_ease(Tween.EASE_OUT)
		_phase_flash_tween.parallel().tween_property(
			_material, "emission", BOSS_EMISSION_COLOR, PHASE_FLASH_DURATION
		).set_ease(Tween.EASE_OUT)

	# Per-phase side-effects.
	if phase == 2:
		_summon_swarmling()
	elif phase == 3:
		move_speed = PHASE_3_MOVE_SPEED


# ────────────────────────────────────────────────────────────────────
# Charge attack (Pkg B)
# ────────────────────────────────────────────────────────────────────

# Tick charge state machine + cooldown perевычитание. Зовётся ПЕРЕД super
# чтобы charge state мог преэмптить regular attack pipeline (если active —
# super._physics_process читает _is_winding_up=false, обычный flow skip'нется
# через override _update_state / _apply_movement ниже).
func _physics_process(delta: float) -> void:
	if is_dying or is_spawning or not VelocityGate.is_alive:
		super._physics_process(delta)
		return
	# Cooldown тикает всегда (даже на Phase 1 — но триггер заблокирован отдельно).
	if _charge_cooldown_timer > 0.0:
		_charge_cooldown_timer = maxf(0.0, _charge_cooldown_timer - delta)
	if _charging_telegraph:
		_charging_telegraph_timer = maxf(0.0, _charging_telegraph_timer - delta)
		if _charging_telegraph_timer <= 0.0:
			_start_charge_dash()
	elif _charging_dash:
		_charging_dash_timer = maxf(0.0, _charging_dash_timer - delta)
		_check_charge_hit()
		if _charging_dash_timer <= 0.0:
			_end_charge_dash()
	elif _charge_recovery_timer > 0.0:
		_charge_recovery_timer = maxf(0.0, _charge_recovery_timer - delta)
	super._physics_process(delta)


# Override: в charge-active state'е regular attack pipeline заморожен, иначе
# super._update_state мог бы стартануть swing поверх dash'а. Charge entry —
# Phase 2+, cooldown ready, distance в 6-12u range.
func _update_state() -> void:
	if _charging_telegraph or _charging_dash or _charge_recovery_timer > 0.0:
		# Charge active → state.IDLE чтобы _apply_movement в base не лез к NavAgent.
		# Movement override ниже перехватывает velocity сам.
		state = State.IDLE
		return
	# Phase 2+ только: пытаемся charge до regular swing если в mid-range.
	if _current_phase >= 2 and _check_should_charge():
		_start_charge_telegraph()
		return
	super._update_state()


# Override: во время charge state'а перехватываем movement. Telegraph — frozen
# (velocity 0), dash — captured direction × CHARGE_DASH_SPEED, recovery —
# frozen vulnerable. Outside charge'а — fallback к base.
func _apply_movement(delta: float) -> void:
	if _charging_telegraph or _charge_recovery_timer > 0.0:
		_set_planar_velocity(Vector3.ZERO, delta)
		move_and_slide()
		return
	if _charging_dash:
		_set_planar_velocity(_charge_dir * CHARGE_DASH_SPEED, delta)
		move_and_slide()
		return
	super._apply_movement(delta)


func _check_should_charge() -> bool:
	if _charge_cooldown_timer > 0.0:
		return false
	if _player == null:
		return false
	# Skip charge если regular attack уже windup'ится (telegraph race) или
	# мы только что resolve'нули и cooldown ещё не отгорел.
	if _is_winding_up or _attack_cooldown_remaining > 0.0:
		return false
	var dist := _distance_to_player()
	return dist >= CHARGE_RANGE_MIN and dist <= CHARGE_RANGE_MAX


func _start_charge_telegraph() -> void:
	_charging_telegraph = true
	_charging_telegraph_timer = CHARGE_TELEGRAPH_DURATION
	_charge_hit_applied = false
	# Audio cue (reuse enemy_attack stream — единственный 3D audio под рукой).
	# Heavier impact чем regular swing telegraph за счёт длинного 2с pulse'а.
	if _telegraph_audio != null:
		_telegraph_audio.play()
	# Bright white pulse на emission. Tween'им energy 3.0 → BOSS_EMISSION_ENERGY
	# за весь telegraph — растёт натяжение, на пике dash'а snap-возврат к
	# golden (в _start_charge_dash). Одновременно держим color на белом.
	if _material != null:
		if _charge_telegraph_tween != null and _charge_telegraph_tween.is_valid():
			_charge_telegraph_tween.kill()
		_material.emission = CHARGE_TELEGRAPH_EMISSION_COLOR
		_material.emission_energy_multiplier = CHARGE_TELEGRAPH_EMISSION_ENERGY
		# Лёгкий pulse'инг energy ↔ peak — ритмичный «зарядка»: tween до
		# 1.5× back-and-forth не делаем (overengineering под 2с), просто hold.


func _start_charge_dash() -> void:
	_charging_telegraph = false
	# Capture direction только сейчас — реактивный lock per spec (не frozen в
	# момент telegraph start'а). Игрок должен иметь смысл двигаться во время
	# 2с telegraph'а, но не быть unkillable: capture в dash start.
	if _player != null:
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.001:
			_charge_dir = to_player.normalized()
		else:
			_charge_dir = -global_transform.basis.z  # fallback forward
	else:
		_charge_dir = -global_transform.basis.z
	_charging_dash = true
	_charging_dash_timer = CHARGE_DASH_DURATION
	# Snap emission обратно к golden — telegraph закончен, dash в moving phase.
	if _material != null:
		if _charge_telegraph_tween != null and _charge_telegraph_tween.is_valid():
			_charge_telegraph_tween.kill()
		_material.emission = BOSS_EMISSION_COLOR
		_material.emission_energy_multiplier = BOSS_EMISSION_ENERGY


func _check_charge_hit() -> void:
	if _charge_hit_applied or _player == null:
		return
	if _distance_to_player() <= CHARGE_HIT_RADIUS:
		VelocityGate.apply_hit(CHARGE_PENALTY)
		_charge_hit_applied = true


func _end_charge_dash() -> void:
	_charging_dash = false
	_charge_recovery_timer = CHARGE_RECOVERY
	_charge_cooldown_timer = CHARGE_COOLDOWN


func _summon_swarmling() -> void:
	# Single mid-fight reinforcement (per locked spec — Phase 2 only, exactly один).
	# Spawn 1.5u в сторону игрока (или forward fallback) — рой должен сразу быть в
	# активной зоне. add_child перед global_position set: enemy._ready() стреляет
	# синхронно из add_child, position нужен resolved'ным к моменту _ready'я;
	# pattern mirror'ит altar_director._instantiate_enemy_at.
	var swarm_scene: PackedScene = load("res://objects/swarmling.tscn")
	if swarm_scene == null:
		return
	var swarm := swarm_scene.instantiate() as Node3D
	if swarm == null:
		return
	var dir := Vector3.FORWARD
	if _player != null:
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.001:
			dir = to_player.normalized()
	if "is_spawning" in swarm:
		swarm.is_spawning = true
	get_parent().add_child(swarm)
	swarm.global_position = global_position + dir * 1.5
	if "is_spawning" in swarm:
		swarm.is_spawning = false
	Events.enemy_spawned.emit(swarm)
