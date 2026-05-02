class_name EnemyMelee extends EnemyBase

# M3a Melee — pure Chase + Attack (нет Reposition). Прямой rush к игроку
# через NavAgent, melee damage в attack_range. Identity: hot color (red),
# heavy/wide capsule (см. enemy_identity §1, telegraph "вздох замаха"
# через scale.y bump 1.0→1.15 + color flash к ярко-красному).

const TELEGRAPH_SCALE_BUMP := 1.15  # y-stretch на пике windup
const FLASH_EMISSION_COLOR := Color(1.0, 0.2, 0.1)  # ярко-красный (телеграф)
const FLASH_EMISSION_ENERGY := 1.5

var _telegraph_audio: AudioStreamPlayer3D
var _telegraph_tween: Tween
var _base_mesh_scale_y: float = 1.0


func _ready() -> void:
	# Числа (M3_enemy_numbers): Melee — HP 40 (×2 на 2026-05-02 user balance tweak,
	# было 20), speed 5.5, range 1.5, windup 450ms, cooldown 2.5s, penalty 20,
	# detection 35.
	max_hp = 40
	move_speed = 5.5
	attack_range = 1.5
	attack_windup = 0.45
	attack_cooldown = 2.5
	attack_penalty = VelocityGate.MELEE_PENALTY
	detection_radius = 35.0
	# Lunge: snap-rush в финальные 300мс windup'а (см. M3_identity §2 attack
	# telegraph — "small forward burst as visual tell"). Без него walk-back
	# (player_speed 1.6 u/s при cap=20) escape'ит attack_range за 450мс freeze
	# каждый цикл — петля без попаданий. С lunge'ем relative speed melee→player
	# в финальные 300мс = 7.5-1.6 = 5.9 u/s → закрывает 1.77u → HIT гарантирован
	# на walk при cap=20. При cap=80 (walk 6.4 u/s) sideways за 300мс = 1.92u
	# > attack_range 1.5u → kiteable escape работает. Dash (20 u/s × 0.2с = 4u
	# burst) всё ещё escape'ит при любом cap.
	lunge_speed = 7.5
	lunge_window = 0.30
	super._ready()

	if visual_root != null:
		_base_mesh_scale_y = visual_root.scale.y

	# Audio: enemy_attack.ogg (Kenney) — short windup grunt. 3D player чтобы
	# pan/distance attenuation работал — игрок должен слышать ближний windup
	# отчётливо, дальний тише.
	_telegraph_audio = AudioStreamPlayer3D.new()
	_telegraph_audio.name = "TelegraphAudio"
	_telegraph_audio.bus = &"SFX"
	_telegraph_audio.stream = load("res://sounds/enemy_attack.ogg")
	_telegraph_audio.unit_size = 5.0
	add_child(_telegraph_audio)


func _play_telegraph() -> void:
	# Visual: scale.y bump → ease-out за весь windup (450ms). Color flash на
	# emission, не albedo, чтобы базовый красный capsule идентификации не
	# терял (см. enemy_identity §3 — silhouette + color identity).
	if _material != null:
		_material.emission_enabled = true
		_material.emission = FLASH_EMISSION_COLOR
		_material.emission_energy_multiplier = FLASH_EMISSION_ENERGY

	if visual_root != null:
		# Tween на scale.y остаётся как третий слой telegraph-читаемости —
		# AnimationPlayer Charge изменяет skinned-mesh pose, но bump визуально
		# выделяется и через silhouette.
		if _telegraph_tween != null and _telegraph_tween.is_valid():
			_telegraph_tween.kill()
		_telegraph_tween = create_tween()
		_telegraph_tween.tween_property(
			visual_root, "scale:y", _base_mesh_scale_y * TELEGRAPH_SCALE_BUMP, attack_windup
		).set_ease(Tween.EASE_OUT)

	# Audio frame 0 — игрок имеет full window реагировать (см. brief Q3).
	if _telegraph_audio != null:
		_telegraph_audio.play()

	# Animation: Charge (one-shot) — windup pose. Длительность анимации может
	# отличаться от attack_windup (0.45с) — Godot обрежет на следующем play()
	# при resolve, не блокер.
	_play_oneshot(&"Charge")


func _resolve_attack() -> void:
	# Single damage source per spec: damage только в этой точке, после windup.
	# Если игрок успел уйти из range за 450ms — miss. ContactArea намеренно
	# убрана из melee.tscn (legacy EnemyDummy double-hit path).
	if not is_dying and _player != null:
		var dist := _distance_to_player()
		if dist <= attack_range:
			VelocityGate.apply_hit(attack_penalty)
	# Attack one-shot ДО super (super вызывает _end_telegraph, не трогает
	# анимацию). После Attack one-shot заканчивается → return к Idle/Run loop'у.
	_play_oneshot(&"Attack")
	super._resolve_attack()


func _end_telegraph() -> void:
	# Сброс visual в base state. Color/emission снимается мгновенно (snap),
	# scale возвращается tween'ом за 100мс — короткий relax после удара.
	if _material != null:
		_material.emission = _base_emission_color
		_material.emission_energy_multiplier = _base_emission_energy

	if visual_root != null:
		if _telegraph_tween != null and _telegraph_tween.is_valid():
			_telegraph_tween.kill()
		_telegraph_tween = create_tween()
		_telegraph_tween.tween_property(
			visual_root, "scale:y", _base_mesh_scale_y, 0.1
		).set_ease(Tween.EASE_OUT)


func _anim_for_state(s: int) -> StringName:
	# IDLE / ATTACK (idle pose в attack-cooldown'е) → Idle. CHASE → Run.
	# REPOSITION у melee не используется (override в Shooter), но возвращаем
	# Idle для безопасности.
	if s == State.CHASE:
		return &"Run"
	return &"Idle"


func _hit_anim_name() -> StringName:
	return &"Hit"


func _death_anim_name() -> StringName:
	return &"TurnOff"
