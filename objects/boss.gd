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
