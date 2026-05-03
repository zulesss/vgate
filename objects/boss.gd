class_name EnemyBoss extends EnemyMelee

# Cathedral R-final boss — 3-phase HP-based encounter с разнообразием attack
# patterns сверх единственного default-swing. Identity сохраняется (golden HDR
# emissive + scale 1.6 + slower / heavier tempo чем regular melee), variety
# теперь читается через phase transitions.
#
# Phase tracking (Pkg A, this commit):
#   - Phase 1 (HP > 67%) — default swing + charge (territorial chase + occasional commit)
#   - Phase 2 (HP 67–34%) — transition cue (audio + emissive flash). Без summon
#     (swarmling reinforcement удалён playtest round 5 — fight ощущался hectic).
#   - Phase 3 (HP < 34%)  — transition cue + speed boost 4 → 5
# Transitions: audio cue (enemy_destroy reuse via _telegraph_audio) + bright
# cream emissive flash 300мс на body. Pattern variety per-фаза приходит в Pkg B/C/D.
#
# Stats (locked, unchanged):
#   - HP 800 (≈ 32s sustained repeater fire — bumped per playtest "too fast")
#   - move_speed 6.6 (Phase 1/2), 7.8 (Phase 3) — playtest M9 round 2 bump
#     (+20% over 5.5/6.5 — sustained chase теперь ловит игрока на high-cap walk
#     6.4 u/s; player dash 20u×0.2s=4u burst всё ещё escape, skill ceiling preserved)
#   - attack_range 2.5 (longer reach, narrow R4)
#   - attack_penalty 25, cooldown 2.5, windup 0.5, detection_radius 40
#   - lunge_speed 15.0 (2× melee default 7.5 — closes 4.5u в windup'е,
#     anti-walk-back на P3 high-cap; round 5 bump). lunge_window 0.30 inherited.
#
# Visual differentiation — золотой emissive HDR через override material'а после
# super._ready'я. Mesh scale 1.6 — transform на Visual node в boss.tscn.
# Collision shape остаётся melee-default (radius 0.5, height 1.7) — boss физически
# такого же радиуса, не толще, иначе застрянет в narrow R4 6u-corridor'е.

const BOSS_EMISSION_COLOR := Color(2.0, 0.8, 0.3)  # HDR golden — > 1.0 даёт bloom при tonemap'е
const BOSS_EMISSION_ENERGY := 1.5

# Phase thresholds (как доли max_hp). При HP=800: Phase 2 на ≤536, Phase 3 на ≤272.
const PHASE_2_HP_RATIO := 0.67
const PHASE_3_HP_RATIO := 0.34

# Phase 3 speed boost — финальная "свирепеет" фаза должна гнать сильнее.
const PHASE_3_MOVE_SPEED := 7.8

# ────────────────────────────────────────────────────────────────────
# Charge attack (Phase 1+) constants
# ────────────────────────────────────────────────────────────────────
# Mid-range gap-closer: telegraph 0.6/0.5/0.4s per phase → dash 0.6s × 32.4 u/s
# = 19.44u в captured direction → recovery 0.5s vulnerable. Cooldown 4s. Penalty
# 30 (выше swing 25 — higher commitment, higher punishment). Direction captured
# при dash start (реактивный per user lock — игрок может в telegraph'е сместиться).
# Skill ceiling note: telegraph + dash 0.6s = commit window. Telegraph escalates
# threat по фазам — позднее phase = меньше read-time (P1 0.6s, P2 0.5s, P3 0.4s).
const CHARGE_RANGE_MIN := 6.0
const CHARGE_RANGE_MAX := 12.0
const CHARGE_TELEGRAPH_PHASE_1 := 0.6
const CHARGE_TELEGRAPH_PHASE_2 := 0.5
const CHARGE_TELEGRAPH_PHASE_3 := 0.4
const CHARGE_DASH_DURATION := 0.6
const CHARGE_DASH_SPEED := 32.4
const CHARGE_RECOVERY := 0.5
const CHARGE_COOLDOWN := 4.0
const CHARGE_PENALTY := 30
const CHARGE_HIT_RADIUS := 1.5  # contact-radius во время dash'а
# Telegraph emission: bright white pulse на _material — отличается от phase
# transition flash (cream gold) и от regular telegraph (ярко-красный) — игрок
# должен читать "boss готовится к dash'у", не "phase change" / "regular swing".
const CHARGE_TELEGRAPH_EMISSION_COLOR := Color(2.0, 2.0, 2.0)
const CHARGE_TELEGRAPH_EMISSION_ENERGY := 3.0

# ────────────────────────────────────────────────────────────────────
# AOE swing (Phase 3+) constants
# ────────────────────────────────────────────────────────────────────
# Close-range radial: red ground decal pulses 1.0s → resolve damage если игрок
# в радиусе. Trigger когда player ≤7.5u (sub-charge range, overlap с default
# swing range 2.5 — но AOE проседает разовой 25 cap'а с radial coverage:
# back-step не escape'ит как от swing'а). Cooldown 6s.
const AOE_RANGE := 7.5
const AOE_TELEGRAPH_DURATION := 1.0
const AOE_PENALTY := 25
const AOE_COOLDOWN := 6.0
# Pulse: emission energy 0.5 → 2.0 за 0.75s, повторяется (pulse в обе стороны
# — telegraph length / 2). Mat_aoe_decal в .tscn задаёт base albedo / emission color.
const AOE_PULSE_LOW := 0.5
const AOE_PULSE_HIGH := 2.0
const AOE_PULSE_DURATION := 0.75

# ────────────────────────────────────────────────────────────────────
# Pattern selection (Pkg D)
# ────────────────────────────────────────────────────────────────────
# Probabilities per phase. Phase 1 в mid-range → 50% charge / иначе chase для default
# (territorial — ниже чем P2 aggressive). Phase 2 → 70% charge. Phase 3 close →
# 20% AOE / 55% charge / остальное default по range. Roll на каждой entry'е в
# _check_should_X. Если roll провалился — set re-roll timer чтобы не re-roll'ить
# 60Hz и не starve'ить opportunity.
const PHASE_1_CHARGE_PROB := 0.50
const PHASE_2_CHARGE_PROB := 0.70
const PHASE_3_CHARGE_PROB := 0.55
const PHASE_3_AOE_PROB := 0.20
const SPECIAL_REROLL_COOLDOWN := 1.0

# ────────────────────────────────────────────────────────────────────
# Boss kill polish (Pkg D)
# ────────────────────────────────────────────────────────────────────
const BOSS_KILL_FLASH_DURATION := 0.5
const BOSS_KILL_FLASH_EMISSION_COLOR := Color(4.0, 4.0, 4.0)
const BOSS_KILL_FLASH_EMISSION_ENERGY := 6.0

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

# AOE swing state (Pkg C). Telegraph → resolve. Cooldown отдельный от charge'а
# и regular cooldown'а — каждый attack-type имеет независимый refresh.
var _aoe_telegraph: bool = false
var _aoe_telegraph_timer: float = 0.0
var _aoe_cooldown_timer: float = 0.0
var _aoe_pulse_tween: Tween
@onready var _aoe_decal: CSGCylinder3D = $AOEDecal if has_node("AOEDecal") else null
@onready var _charge_beam: CSGBox3D = $ChargeBeam if has_node("ChargeBeam") else null

# Pattern selection re-roll timer (Pkg D). Когда probabilistic roll fail'ится,
# ставим этот timer, чтобы не re-roll'ить каждый physics-tick (иначе на 60Hz за
# секунду проигрывается ~60 roll'ов и шанс никогда не прокнуть).
var _special_reroll_timer: float = 0.0

# Anti-kite: если boss долго не enter'ил default-swing windup (например игрок
# kite'ит за attack_range 2.5u), через 3 секунды force'им charge — bypass
# probability roll и range gate (но cooldown respected). Reset на _start_attack
# (default windup) или на successful force-trigger. Charge / AOE НЕ resets timer
# — намеренно (special attacks ≠ default swing). Работает с P1+ (charge доступен
# с первой фазы) — на P1 cooldown 4s + 3s timer = 4-7s gap при постоянном kite'е.
const FORCED_CHARGE_TIMEOUT := 3.0
var _time_since_last_swing: float = 0.0

func _ready() -> void:
	# Stat overrides ПОСЛЕ super._ready, иначе EnemyMelee._ready клоббит наши
	# values своими defaults (max_hp=40, move_speed=5.5, attack_range=1.5, ...) и
	# EnemyBase._ready ставит hp = max_hp = 40 — boss всегда жил на melee stats.
	# После super выставляем boss values + явный hp = max_hp re-init, чтобы
	# перетереть hp=40 которое base зафиксировал из melee'шного max_hp.
	# Lunge оставляем включённым из melee parent'а — boss тоже должен закрывать
	# gap в финальные 300мс windup'а, иначе walk-back escape'ит даже на slower
	# 4.0 (player walk ~6.4 u/s при cap=80).
	super._ready()
	max_hp = 800
	hp = max_hp
	move_speed = 6.6
	attack_range = 2.5
	attack_windup = 0.5
	attack_cooldown = 2.5
	attack_penalty = 25
	detection_radius = 40.0
	# Lunge override: melee default 7.5 × 0.30 = 2.25u closure; boss 15.0 × 0.30 = 4.5u
	# (2× distance). Anti-walk-back на P3 7.8 move_speed + cap=80 player walk 6.4u/s —
	# windup'овая 4.5u closure теперь покрывает 0.3s × (boss-player) relative speed gap.
	lunge_speed = 15.0

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

	# HUD boss bar (Pkg B): первичный emit чтобы bar нарисовался full сразу
	# после spawn'а. AltarDirector instance'ит boss'а из boss_phase_started и
	# add_child'ит в parent; hp re-init'нут вручную выше как max_hp = 800.
	Events.boss_hp_changed.emit(hp, max_hp)


func _kill_type() -> String:
	return "boss"


# Pkg D: hook на момент когда default swing windup стартует. Reset anti-kite
# timer — после этого момента боссу повторно копится таймер. Charge / AOE НЕ
# resets таймер (special attacks ≠ default swing).
func _start_attack() -> void:
	_time_since_last_swing = 0.0
	super._start_attack()


# Override: kill polish — bright white emission flash 0.5s до super.die() чтобы
# kill-моменat читался как climax. apply_kill_restore (внутри super.die()) идёт
# через type="boss" → BOSS_KILL_RESTORE (2× regular) — большой cap burst.
# Phase / charge / AOE active tween'ы убираем чтобы не лезли поверх flash'а.
func die() -> void:
	if _phase_flash_tween != null and _phase_flash_tween.is_valid():
		_phase_flash_tween.kill()
	if _aoe_pulse_tween != null and _aoe_pulse_tween.is_valid():
		_aoe_pulse_tween.kill()
	if _aoe_decal != null:
		_aoe_decal.visible = false
	if _charge_beam != null:
		_charge_beam.visible = false
	_time_since_last_swing = 0.0  # defensive cleanup (Pkg D anti-kite timer)
	if _material != null:
		_material.emission = BOSS_KILL_FLASH_EMISSION_COLOR
		_material.emission_energy_multiplier = BOSS_KILL_FLASH_EMISSION_ENERGY
		# Tween fade обратно к golden за 0.5s — но к этому моменту death animation
		# почти закончится и queue_free сработает. Tween всё равно ставим — feel'у
		# нужен видимый decay flash'а на старте death-animation'а.
		var t := create_tween()
		t.tween_property(
			_material, "emission_energy_multiplier", BOSS_EMISSION_ENERGY,
			BOSS_KILL_FLASH_DURATION
		).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(
			_material, "emission", BOSS_EMISSION_COLOR, BOSS_KILL_FLASH_DURATION
		).set_ease(Tween.EASE_OUT)
	super.die()


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
	# HUD bar refresh ПОСЛЕ super.damage(). Если boss умер — emit hp=0, HUD
	# скроет bar по boss_killed signal'у (RunLoop эмитит из enemy_killed type).
	Events.boss_hp_changed.emit(maxi(hp, 0), max_hp)
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
	# Phase 2: только cue (без summon — round 5 cut). Phase 3: speed boost.
	if phase == 3:
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
	# Cooldowns тикают всегда (даже на Phase 1 — но триггеры заблокированы phase-gate'ом).
	if _charge_cooldown_timer > 0.0:
		_charge_cooldown_timer = maxf(0.0, _charge_cooldown_timer - delta)
	if _aoe_cooldown_timer > 0.0:
		_aoe_cooldown_timer = maxf(0.0, _aoe_cooldown_timer - delta)
	if _special_reroll_timer > 0.0:
		_special_reroll_timer = maxf(0.0, _special_reroll_timer - delta)
	# Anti-kite timer (Pkg D). Tick БЕЗ guards на phase / state — таймер просто
	# движется, gate на trigger лежит в _update_state.
	_time_since_last_swing += delta
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
	if _aoe_telegraph:
		_aoe_telegraph_timer = maxf(0.0, _aoe_telegraph_timer - delta)
		if _aoe_telegraph_timer <= 0.0:
			_resolve_aoe()
	super._physics_process(delta)


# Override: в charge-active state'е regular attack pipeline заморожен, иначе
# super._update_state мог бы стартануть swing поверх dash'а. Charge entry —
# P1+ (с первой фазы), cooldown ready, distance в 6-12u range.
func _update_state() -> void:
	if (
		_charging_telegraph or _charging_dash or _charge_recovery_timer > 0.0
		or _aoe_telegraph
	):
		# Special-attack active → state.IDLE чтобы _apply_movement в base не лез к NavAgent.
		# Movement override ниже перехватывает velocity сам.
		state = State.IDLE
		return
	# Forced charge: anti-kite. После 3s без default swing → commit charge regardless
	# of probability / range. Cooldown respected (если на cd — нет force'а, ждём).
	# P1+ — charge доступен с первой фазы, anti-kite tоже.
	if (_time_since_last_swing >= FORCED_CHARGE_TIMEOUT
			and _charge_cooldown_timer <= 0.0
			and not _is_winding_up and _attack_cooldown_remaining <= 0.0):
		_start_charge_telegraph()
		_time_since_last_swing = 0.0  # consume timer to prevent re-fire next frame
		return
	# Phase 3+ только: AOE до charge до regular swing если в close range.
	if _current_phase >= 3 and _check_should_aoe():
		_start_aoe_telegraph()
		return
	# Charge доступен с P1+ — пытаемся до regular swing если в mid-range.
	if _check_should_charge():
		_start_charge_telegraph()
		return
	super._update_state()


# Override: во время charge state'а перехватываем movement. Telegraph — frozen
# (velocity 0), dash — captured direction × CHARGE_DASH_SPEED, recovery —
# frozen vulnerable. Outside charge'а — fallback к base.
func _apply_movement(delta: float) -> void:
	if _charging_telegraph or _charge_recovery_timer > 0.0 or _aoe_telegraph:
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
	if _special_reroll_timer > 0.0:
		return false
	var dist := _distance_to_player()
	if dist < CHARGE_RANGE_MIN or dist > CHARGE_RANGE_MAX:
		return false
	# Probability gate per phase. Roll fail → set reroll cooldown, boss продолжает
	# chase. Phase 1: 50% (territorial). Phase 2: 70% (aggressive mid-range).
	# Phase 3: 55% (плюс AOE 20% — суммарно 75% special / 25% default per spec).
	var prob: float
	match _current_phase:
		1: prob = PHASE_1_CHARGE_PROB
		2: prob = PHASE_2_CHARGE_PROB
		_: prob = PHASE_3_CHARGE_PROB
	if randf() < prob:
		return true
	_special_reroll_timer = SPECIAL_REROLL_COOLDOWN
	return false


func _charge_telegraph_duration() -> float:
	match _current_phase:
		1: return CHARGE_TELEGRAPH_PHASE_1
		2: return CHARGE_TELEGRAPH_PHASE_2
		_: return CHARGE_TELEGRAPH_PHASE_3


func _start_charge_telegraph() -> void:
	_charging_telegraph = true
	_charging_telegraph_timer = _charge_telegraph_duration()
	_charge_hit_applied = false
	# Audio cue (reuse enemy_attack stream — единственный 3D audio под рукой).
	# Heavier impact чем regular swing telegraph за счёт длинного telegraph window'а.
	if _telegraph_audio != null:
		_telegraph_audio.play()
	# Bright white emission hold на весь telegraph. Snap-возврат к golden в
	# _start_charge_dash. Без pulsing-tween'а (overengineering под 2с — статичный
	# bright контраст к golden idle сам по себе читается).
	if _material != null:
		_material.emission = CHARGE_TELEGRAPH_EMISSION_COLOR
		_material.emission_energy_multiplier = CHARGE_TELEGRAPH_EMISSION_ENERGY
	# Aim indicator beam — child of body, rotates with _face_player. Игрок видит
	# куда полетит dash в реальном времени за telegraph window. Скрыт в
	# _start_charge_dash и die() defensive.
	if _charge_beam != null:
		_charge_beam.visible = true


func _start_charge_dash() -> void:
	_charging_telegraph = false
	# Capture direction только сейчас — реактивный lock per spec (не frozen в
	# момент telegraph start'а). Игрок должен иметь смысл двигаться во время
	# telegraph'а, но не быть unkillable: capture в dash start.
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
		_material.emission = BOSS_EMISSION_COLOR
		_material.emission_energy_multiplier = BOSS_EMISSION_ENERGY
	if _charge_beam != null:
		_charge_beam.visible = false


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


# ────────────────────────────────────────────────────────────────────
# AOE swing (Pkg C)
# ────────────────────────────────────────────────────────────────────

func _check_should_aoe() -> bool:
	if _aoe_cooldown_timer > 0.0:
		return false
	if _player == null:
		return false
	# Skip если regular attack или charge in-flight (пусть отрезолвится).
	if _is_winding_up or _attack_cooldown_remaining > 0.0:
		return false
	if _special_reroll_timer > 0.0:
		return false
	if _distance_to_player() > AOE_RANGE:
		return false
	# Phase 3 only (caller'ы это уже фильтруют, но guard на случай прямого вызова).
	# 20% AOE / иначе reroll.
	if randf() < PHASE_3_AOE_PROB:
		return true
	_special_reroll_timer = SPECIAL_REROLL_COOLDOWN
	return false


func _start_aoe_telegraph() -> void:
	_aoe_telegraph = true
	_aoe_telegraph_timer = AOE_TELEGRAPH_DURATION
	if _aoe_decal != null:
		_aoe_decal.visible = true
		# Pulse: emission_energy 0.5 ↔ 2.0 за 0.75s, ping-pong через TWEEN_LOOPS.
		# Material — sub_resource на decal'е, тянем emission_energy_multiplier.
		var mat := _aoe_decal.material as StandardMaterial3D
		if mat != null:
			if _aoe_pulse_tween != null and _aoe_pulse_tween.is_valid():
				_aoe_pulse_tween.kill()
			mat.emission_energy_multiplier = AOE_PULSE_LOW
			_aoe_pulse_tween = create_tween().set_loops()
			_aoe_pulse_tween.tween_property(
				mat, "emission_energy_multiplier", AOE_PULSE_HIGH, AOE_PULSE_DURATION
			).set_trans(Tween.TRANS_SINE)
			_aoe_pulse_tween.tween_property(
				mat, "emission_energy_multiplier", AOE_PULSE_LOW, AOE_PULSE_DURATION
			).set_trans(Tween.TRANS_SINE)


func _resolve_aoe() -> void:
	_aoe_telegraph = false
	_aoe_cooldown_timer = AOE_COOLDOWN
	if _aoe_pulse_tween != null and _aoe_pulse_tween.is_valid():
		_aoe_pulse_tween.kill()
	if _aoe_decal != null:
		_aoe_decal.visible = false
	if _player != null and _distance_to_player() <= AOE_RANGE:
		VelocityGate.apply_hit(AOE_PENALTY)


