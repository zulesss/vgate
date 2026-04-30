class_name MusicDirectorBus extends Node

# M5 adaptive music — 2 layers (base + intensity), enemy-density pressure metric.
# Источник чисел: docs/feel/M5_audio_spec.md §2.
#
# pressure = clamp(live_enemy_count / 20, 0, 1)
# tween 2.5с smoothing → intensity volume mapping ease-in (квадратичная)
# −80 dB (silent) → 0 dB через quadratic curve. Crossfade: base ramp'ится вниз
# симметрично с intensity вверх — слои не звучат параллельно, плавная подмена.
# Speed_ratio из формулы убран — низкоскоростной tension покрыт heartbeat'ом
# (sfx.gd, см. spec §1.5), музыка не дублирует.

const MUSIC_PATH := "res://assets/audio/music/"
const SMOOTH_TIME_S := 2.5
const ENEMY_DENSITY_NORMALIZER := 20.0
const INTENSITY_MAX_DB := 0.0
const INTENSITY_MIN_DB := -80.0
const DEATH_FADE_SECONDS := 1.8

var _base: AudioStreamPlayer
var _intensity: AudioStreamPlayer
var _pressure_smooth: float = 0.0
var _live_enemy_count: int = 0
var _death_tween_base: Tween = null
var _death_tween_intensity: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_base = _setup_player("dos88_base.ogg", INTENSITY_MAX_DB)
	_intensity = _setup_player("dos88_intensity.ogg", INTENSITY_MIN_DB)

	# Music starts on Events.run_started — autoload init только готовит players,
	# boot тишина для главного меню.

	Events.run_started.connect(_on_run_started)
	Events.player_died.connect(_on_player_died)
	Events.enemy_spawned.connect(_on_enemy_spawned)
	Events.enemy_killed.connect(_on_enemy_killed)


func _process(delta: float) -> void:
	# Если стрим не загрузился (asset gate fallback не сработал) — _intensity всё
	# равно создан, но stream==null. Гард на stream=null не нужен — set volume_db
	# в кадр на player'е без stream'а — no-op.
	if _intensity == null or _intensity.stream == null:
		return
	if not VelocityGate.is_alive:
		return
	# Pause guard: замораживаем текущие volume_db обоих слоёв до un-pause —
	# pressure не должна дрейфовать пока игра на pause.
	if get_tree().paused:
		return

	# Pressure = только плотность врагов. Низкоскоростной tension покрыт heartbeat'ом
	# (sfx.gd) — музыка не дублирует. Без safety gate'а — intensity строго от
	# количества живых врагов.
	var pressure_target: float = clampf(float(_live_enemy_count) / ENEMY_DENSITY_NORMALIZER, 0.0, 1.0)

	# Tween smooth: linear interpolation per-frame (delta / SMOOTH_TIME). Не используем
	# create_tween() per-кадр — lerpf достаточно. ease-in-out не критично для медленного
	# 2.5с smoothing'а — на таком окне разница не воспринимается.
	var alpha: float = clampf(delta / SMOOTH_TIME_S, 0.0, 1.0)
	_pressure_smooth = lerpf(_pressure_smooth, pressure_target, alpha)

	# Quadratic ease-in mapping. Crossfade: intensity ↑ + base ↓ симметрично, чтобы
	# слои не звучали параллельно — плавная подмена.
	var eased: float = _pressure_smooth * _pressure_smooth
	_intensity.volume_db = lerpf(INTENSITY_MIN_DB, INTENSITY_MAX_DB, eased)
	_base.volume_db = lerpf(INTENSITY_MAX_DB, INTENSITY_MIN_DB, eased)


func _on_run_started() -> void:
	# Reset state на новый run. Останавливаем death-fade'ы если были.
	_pressure_smooth = 0.0
	_live_enemy_count = 0
	if _death_tween_base != null and _death_tween_base.is_valid():
		_death_tween_base.kill()
	if _death_tween_intensity != null and _death_tween_intensity.is_valid():
		_death_tween_intensity.kill()
	if _base != null:
		_base.volume_db = INTENSITY_MAX_DB
		if not _base.playing and _base.stream != null:
			_base.play()
	if _intensity != null:
		_intensity.volume_db = INTENSITY_MIN_DB
		if not _intensity.playing and _intensity.stream != null:
			_intensity.play()


func stop_all() -> void:
	# Используется main_menu при возврате из gameplay'а — тушит обе layer'а
	# сразу, без death-fade'а. Tween'ы убиваем чтобы не оставались висящие.
	if _death_tween_base != null and _death_tween_base.is_valid():
		_death_tween_base.kill()
	if _death_tween_intensity != null and _death_tween_intensity.is_valid():
		_death_tween_intensity.kill()
	if _base != null and _base.playing:
		_base.stop()
	if _intensity != null and _intensity.playing:
		_intensity.stop()


func _on_player_died() -> void:
	# Music fade-out 1.8с до -80 dB. Не останавливаем — просто mute.
	if _base != null:
		_death_tween_base = create_tween()
		_death_tween_base.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_death_tween_base.tween_property(_base, "volume_db", INTENSITY_MIN_DB, DEATH_FADE_SECONDS)
	if _intensity != null:
		_death_tween_intensity = create_tween()
		_death_tween_intensity.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_death_tween_intensity.tween_property(_intensity, "volume_db", INTENSITY_MIN_DB, DEATH_FADE_SECONDS)


func _on_enemy_spawned(_enemy: Node) -> void:
	_live_enemy_count += 1


func _on_enemy_killed(_restore: int, _pos: Vector3, _type: String) -> void:
	_live_enemy_count = maxi(0, _live_enemy_count - 1)


func _setup_player(file_name: String, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.volume_db = vol_db
	var path := MUSIC_PATH + file_name
	if ResourceLoader.exists(path):
		p.stream = load(path)
		if p.stream != null and "loop" in p.stream:
			p.stream.loop = true
	add_child(p)
	return p
