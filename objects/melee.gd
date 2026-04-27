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
	# Числа (M3_enemy_numbers): Melee — HP 20, speed 5.5, range 1.5, windup 450ms,
	# cooldown 2.5s, penalty 20, detection 35.
	max_hp = 20
	move_speed = 5.5
	attack_range = 1.5
	attack_windup = 0.45
	attack_cooldown = 2.5
	attack_penalty = VelocityGate.MELEE_PENALTY
	detection_radius = 35.0
	super._ready()

	if mesh_instance != null:
		_base_mesh_scale_y = mesh_instance.scale.y

	# Audio: enemy_attack.ogg (Kenney) — short windup grunt. 3D player чтобы
	# pan/distance attenuation работал — игрок должен слышать ближний windup
	# отчётливо, дальний тише.
	_telegraph_audio = AudioStreamPlayer3D.new()
	_telegraph_audio.name = "TelegraphAudio"
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

	if mesh_instance != null:
		# Tween node-API проще AnimationPlayer для placeholder M3a (M3b с rigged
		# меш-моделями — переход на AnimationPlayer).
		if _telegraph_tween != null and _telegraph_tween.is_valid():
			_telegraph_tween.kill()
		_telegraph_tween = create_tween()
		_telegraph_tween.tween_property(
			mesh_instance, "scale:y", _base_mesh_scale_y * TELEGRAPH_SCALE_BUMP, attack_windup
		).set_ease(Tween.EASE_OUT)

	# Audio frame 0 — игрок имеет full window реагировать (см. brief Q3).
	if _telegraph_audio != null:
		_telegraph_audio.play()


func _resolve_attack() -> void:
	# Single damage source per spec: damage только в этой точке, после windup.
	# Если игрок успел уйти из range за 450ms — miss. ContactArea намеренно
	# убрана из melee.tscn (legacy EnemyDummy double-hit path).
	if not is_dying and _player != null:
		var dist := _distance_to_player()
		if dist <= attack_range:
			VelocityGate.apply_hit(attack_penalty)
	super._resolve_attack()


func _end_telegraph() -> void:
	# Сброс visual в base state. Color/emission снимается мгновенно (snap),
	# scale возвращается tween'ом за 100мс — короткий relax после удара.
	if _material != null:
		_material.emission = _base_emission_color
		_material.emission_energy_multiplier = _base_emission_energy

	if mesh_instance != null:
		if _telegraph_tween != null and _telegraph_tween.is_valid():
			_telegraph_tween.kill()
		_telegraph_tween = create_tween()
		_telegraph_tween.tween_property(
			mesh_instance, "scale:y", _base_mesh_scale_y, 0.1
		).set_ease(Tween.EASE_OUT)
