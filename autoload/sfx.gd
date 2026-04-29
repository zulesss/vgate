class_name SfxBus extends Node

# M5 SFX bus + adaptive heartbeat. Источник чисел/тайминга — docs/feel/M5_audio_spec.md.
# Все per-sound параметры (volume_db, pitch_variance, attack/decay) — оттуда.
#
# Архитектура:
#   - 9 AudioStreamPlayer (или 3D) per slot — простой path, не pool. Pool у нас уже
#     есть в Audio autoload (Kenney legacy), но он рандомит pitch ±10% что ломает
#     спеку — здесь нужны детерминированные значения.
#   - Stream'ы загружаются on-demand с fallback на res://sounds/* если M5 файла нет.
#   - hit_impact + spawn'ы — 3D, остальные — 2D (HUD-уровень или player-position).
#   - Heartbeat: один loop-player, pitch_scale + volume_db обновляются в _process по
#     speed_ratio (lerp кривая в спеке §1).
#   - Kill-confirm duck: tween на AudioServer.set_bus_volume_db(Music/Ambient bus).
#     180мс / 120мс ease-out (см. §3 ducking).
#   - Player death: SFX bus immediate stop, Heartbeat fade 0.6с, Music/Ambient 1.8с
#     (handled здесь для SFX/Heartbeat, music_director.gd для Music).

const SFX_PATH := "res://assets/audio/sfx/"
const AMBIENT_PATH := "res://assets/audio/ambient/"

# Bus-volume duck-targets (см. spec §3). Применяются tween'ом, потом возвращаются.
const KILL_DUCK_MUSIC_DB := -6.0
const KILL_DUCK_MUSIC_MS := 180
const KILL_DUCK_AMBIENT_DB := -4.0
const KILL_DUCK_AMBIENT_MS := 120

const HEARTBEAT_FADE_DEATH_SECONDS := 0.6

# Heartbeat кривая. quadratic ease-in по cap_ratio (velocity_cap / CAP_CEILING):
#   cap_ratio ≥ 0.50 → mute (cap высокий, опасности нет)
#   cap_ratio ∈ (0.10, 0.50) → quadratic ease pitch ≈0.333 → 0.5, vol -80 → -12 dB
#   cap_ratio ≤ 0.10 → peak (0.5 / -12 dB) — критическая cap-эрозия (cap < 10)
# Updated 2026-04-28 (iter 1): speed_ratio mapping triggered max heartbeat at game start
# (player stationary, current_speed=0 → speed_ratio=0). Cap-based mapping correctly
# represents danger as cap erosion, not momentary stillness.
# Updated 2026-04-28 (iter 2): user playtest "режет уши на низком cap" — peak BPM
# понижен с 110 (1.833) до ~90 (1.5), peak vol с -8 до -12 dB, ramp window расширен
# 0.15-0.45 → 0.10-0.50, linear → quadratic ease для долгого плато на mid-cap.
# Heartbeat = pressure, не alarm.
# Updated 2026-04-29 (iter 4): /9 → ≈10 BPM peak, ≈2.5 октавы вниз — feel-эксперимент
# юзера, очень низкое гулкое сердце.
# Updated 2026-04-29 (iter 5): pitch /18 (≈5 BPM peak, ~3.5 октавы вниз — sub-bass
# rumble), linear ease вместо quadratic, floor -36 dB → heartbeat audible через весь
# cap 50→10 (плато t² на mid-cap делало звук неслышимым на 30-50).
# Updated 2026-04-29 (iter 6): +3 dB across (≈+30% perceived) — юзер просил
# heartbeat громче. Floor -36 → -33, peak -12 → -9.
const HEARTBEAT_CAP_HIGH := 0.50
const HEARTBEAT_CAP_LOW := 0.10
const HEARTBEAT_PITCH_LOW := 1.0 / 18.0
const HEARTBEAT_PITCH_HIGH := 1.5 / 18.0
const HEARTBEAT_VOL_HIGH_DB := -9.0
const HEARTBEAT_VOL_FLOOR_DB := -33.0  # in-range volume floor — audible plateau на cap=HIGH
const HEARTBEAT_MUTE_DB := -80.0
# tween smooth volume на дискретных hit/kill событиях (200мс по spec)
const HEARTBEAT_VOL_SMOOTH_S := 0.4

# Bus indices кешируем, base_db больше не кешируем — читаем live из AudioSettings
# в момент duck'а. Пользователь может изменить volume slider'ом во время duck'а
# (M6 settings menu), и tween должен возвращаться к свежему base'у. Cache-инвалидация
# через signal — лишняя сложность ради того же результата.
var _music_bus_idx: int = -1
var _ambient_bus_idx: int = -1
var _sfx_bus_idx: int = -1

# Slot players. Gun не имеет своего player'а: он остаётся в legacy Audio pool
# (player.gd action_shoot), мы только готовим SFX bus + ассет blaster.ogg для
# будущего perehod. Если решим перевести gun сюда — добавим _gun_player +
# play_gun() методом + правкой player.gd.
var _hit_player: AudioStreamPlayer3D
var _kill_player: AudioStreamPlayer
var _heartbeat_player: AudioStreamPlayer
var _drain_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _melee_spawn_proto: AudioStream

# Smoothed heartbeat volume — чтобы не дёргалось от мгновенных hit/kill изменений sr.
var _heartbeat_vol_current: float = HEARTBEAT_MUTE_DB

# DEBUG (temporary, see commit message): track threshold crossings to print only on
# audible/inaudible transitions instead of every frame.
var _heartbeat_was_audible: bool = false

# Process_mode ALWAYS, чтобы pause-меню не ломало death-fade tween'ы. Heartbeat
# player'у явный PAUSABLE override ставим в _ready (юзер flip'нул feel-decision
# 2026-04-29: pause = full silence, в т.ч. heartbeat).
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_music_bus_idx = AudioServer.get_bus_index("Music")
	_ambient_bus_idx = AudioServer.get_bus_index("Ambient")
	_sfx_bus_idx = AudioServer.get_bus_index("SFX")

	# Слоты. Dash whoosh откатан в objects/player.gd (legacy jump_b.ogg + pitch
	# +200 cents) после F5-плейтеста 2026-04-29 — M5 dash_whoosh.ogg ассет звучал
	# артефактом. Файл оставлен на диске на случай будущей замены.
	_hit_player = _make_3d("hit_impact.ogg", -6.0, 8.0)
	_kill_player = _make_2d("kill_confirm.ogg", 0.0)
	_heartbeat_player = _make_2d("heartbeat_60bpm.ogg", HEARTBEAT_MUTE_DB)
	# pause замораживает heartbeat (юзер flip'нул feel-decision 2026-04-29 — pause =
	# full silence, including heartbeat). Явный PAUSABLE override т.к. родитель ALWAYS.
	_heartbeat_player.process_mode = Node.PROCESS_MODE_PAUSABLE
	if _heartbeat_player.stream != null:
		_loop_stream(_heartbeat_player.stream)
	_drain_player = _make_2d("drain_warning.ogg", -14.0)
	if _drain_player.stream != null:
		_loop_stream(_drain_player.stream)
	_ambient_player = _make_ambient("scifi_drone.ogg", -12.0)
	if _ambient_player.stream != null:
		_loop_stream(_ambient_player.stream)
	# Spawn audio через 3D-инстансы создаём per-spawn (positional). Только prototype'ы.
	_melee_spawn_proto = _load_or_null(SFX_PATH + "melee_spawn.ogg")

	# Heartbeat loop стартует только на Events.run_started — главное меню должно
	# быть тихим. См. _on_run_started ниже.

	# Events
	Events.player_hit.connect(_on_player_hit)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.drain_started.connect(_on_drain_started)
	Events.drain_stopped.connect(_on_drain_stopped)
	Events.player_died.connect(_on_player_died)
	Events.run_started.connect(_on_run_started)
	Events.enemy_spawned.connect(_on_enemy_spawned)


func _process(delta: float) -> void:
	# Heartbeat обновляем каждый кадр — кривая по cap_ratio. Pitch применяется
	# мгновенно (это и есть BPM), volume smoothed чтобы не дёрганье на hit/kill.
	if not VelocityGate.is_alive:
		return
	var cap_ratio: float = VelocityGate.velocity_cap / VelocityGate.CAP_CEILING
	var target_pitch: float
	var target_vol: float
	if cap_ratio >= HEARTBEAT_CAP_HIGH:
		target_pitch = HEARTBEAT_PITCH_LOW
		target_vol = HEARTBEAT_MUTE_DB
	else:
		# Linear lerp в-range — heartbeat слышен через весь диапазон cap 50→10,
		# нарастает плавно. Floor -36 dB на cap=50 (just audible), peak -12 dB на cap=10.
		var t: float = clampf((HEARTBEAT_CAP_HIGH - cap_ratio) / (HEARTBEAT_CAP_HIGH - HEARTBEAT_CAP_LOW), 0.0, 1.0)
		target_pitch = lerpf(HEARTBEAT_PITCH_LOW, HEARTBEAT_PITCH_HIGH, t)
		target_vol = lerpf(HEARTBEAT_VOL_FLOOR_DB, HEARTBEAT_VOL_HIGH_DB, t)
	_heartbeat_player.pitch_scale = target_pitch
	# Smooth volume через move_toward — никаких tween'ов на каждый кадр (perf-ловушка).
	# Шаг = доля диапазона (HEARTBEAT_MUTE..HEARTBEAT_VOL_HIGH ≈ 72 dB) per smooth-time.
	var step: float = delta / HEARTBEAT_VOL_SMOOTH_S * absf(HEARTBEAT_VOL_HIGH_DB - HEARTBEAT_MUTE_DB)
	_heartbeat_vol_current = move_toward(_heartbeat_vol_current, target_vol, step)
	_heartbeat_player.volume_db = _heartbeat_vol_current

	# DEBUG: only print on threshold crossings (audible↔inaudible).
	var is_audible: bool = cap_ratio < HEARTBEAT_CAP_HIGH
	if is_audible != _heartbeat_was_audible:
		_heartbeat_was_audible = is_audible
		var state_str: String = "on" if is_audible else "off"
		print("[AUDIO] sfx.gd | heartbeat AUDIBLE %s (cap_ratio=%.2f, pitch=%.3f, vol=%.1f)" % [state_str, cap_ratio, target_pitch, _heartbeat_vol_current])


# ────── Event listeners

func _on_player_hit(_penalty: int) -> void:
	if _hit_player == null or _hit_player.stream == null:
		return
	_hit_player.pitch_scale = randf_range(0.9, 1.1)  # ±10%
	# 3D player'у нужна позиция. Игрок сам кидает hit-feedback из своей головы —
	# это субъективное "по мне попали". Берём player.global_position если найдём.
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null:
		_hit_player.global_position = p.global_position
	print("[AUDIO] sfx.gd | player_hit | hit_impact.ogg")
	_hit_player.play()


func _on_enemy_killed(_restore: int, _pos: Vector3, _type: String) -> void:
	if not VelocityGate.is_alive:
		return
	if _kill_player != null and _kill_player.stream != null:
		_kill_player.pitch_scale = randf_range(0.96, 1.04)  # ±4%
		print("[AUDIO] sfx.gd | enemy_killed | kill_confirm.ogg + duck Music/Ambient")
		_kill_player.play()
	# Duck Music/Ambient bus — independent tween'ы. Base_db читаем live из
	# AudioSettings: если юзер выкрутил slider — duck вернётся к свежему base'у,
	# а не к тому, что было на старте сцены.
	_duck_bus(_music_bus_idx, AudioSettings.get_volume_db("Music"), KILL_DUCK_MUSIC_DB, KILL_DUCK_MUSIC_MS)
	_duck_bus(_ambient_bus_idx, AudioSettings.get_volume_db("Ambient"), KILL_DUCK_AMBIENT_DB, KILL_DUCK_AMBIENT_MS)


func _on_drain_started() -> void:
	if _drain_player != null and _drain_player.stream != null and not _drain_player.playing:
		print("[AUDIO] sfx.gd | drain_started | drain_warning.ogg LOOP START")
		_drain_player.play()


func _on_drain_stopped() -> void:
	if _drain_player != null and _drain_player.playing:
		print("[AUDIO] sfx.gd | drain_stopped | drain_warning.ogg LOOP STOP")
		_drain_player.stop()


func _on_player_died() -> void:
	print("[AUDIO] sfx.gd | player_died | SFX bus mute, heartbeat fade")
	# Глушим SFX bus немедленно — gun/hit decay не должен болтаться поверх death-state.
	# Bus-mute через AudioServer chunk'ает все SFX players разом (cleaner чем per-player stop).
	if _sfx_bus_idx >= 0:
		AudioServer.set_bus_mute(_sfx_bus_idx, true)
	# Drain stop сразу.
	if _drain_player != null and _drain_player.playing:
		_drain_player.stop()
	# Heartbeat fade 0.6с (быстрее чем music — "сердце останавливается").
	# Tween volume_db до -80, потом stop. process_mode ALWAYS на player'е → tween
	# работает даже если tree.paused = true (защита от ситуации pause→death edge).
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(_heartbeat_player, "volume_db", HEARTBEAT_MUTE_DB, HEARTBEAT_FADE_DEATH_SECONDS)
	tw.tween_callback(_heartbeat_player.stop)


func _on_run_started() -> void:
	print("[AUDIO] sfx.gd | run_started | heartbeat LOOP RESTART, ambient LOOP RESTART")
	# Un-mute SFX bus, рестартанём heartbeat loop, перезапустим ambient.
	if _sfx_bus_idx >= 0:
		AudioServer.set_bus_mute(_sfx_bus_idx, false)
	_heartbeat_vol_current = HEARTBEAT_MUTE_DB
	_heartbeat_was_audible = false
	if _heartbeat_player != null and not _heartbeat_player.playing:
		_heartbeat_player.volume_db = HEARTBEAT_MUTE_DB
		_heartbeat_player.play()
	if _ambient_player != null and not _ambient_player.playing:
		_ambient_player.play()


func stop_all_loops() -> void:
	# Используется main_menu при возврате из gameplay'а. Тушим heartbeat,
	# drain_warning, ambient — все loop'ы. One-shot'ы (hit, kill, dash)
	# сами отыграют и остановятся.
	if _heartbeat_player != null and _heartbeat_player.playing:
		_heartbeat_player.stop()
	if _drain_player != null and _drain_player.playing:
		_drain_player.stop()
	if _ambient_player != null and _ambient_player.playing:
		_ambient_player.stop()
	_heartbeat_vol_current = HEARTBEAT_MUTE_DB
	print("[AUDIO] sfx.gd | stop_all_loops | heartbeat/drain/ambient stopped")


func _on_enemy_spawned(enemy: Node) -> void:
	# 3D positional — проигрываем prototype-stream через временный AudioStreamPlayer3D
	# на позиции врага. После finished — удаляем.
	if not is_instance_valid(enemy):
		return
	if _melee_spawn_proto == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _melee_spawn_proto
	player.bus = "SFX"
	player.unit_size = 16.0
	player.volume_db = -2.0
	player.pitch_scale = randf_range(0.95, 1.05)
	# Add как child enemy чтобы освобождался при queue_free вместе с врагом
	# (обычно spawn-звук < 200мс — успевает сыграть до того, как игрок убил спавнящегося).
	enemy.add_child(player)
	if enemy is Node3D:
		player.global_position = (enemy as Node3D).global_position
	player.finished.connect(player.queue_free)
	print("[AUDIO] sfx.gd | enemy_spawned | melee_spawn.ogg")
	player.play()


# ────── Helpers

func _make_2d(file_name: String, vol_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "SFX"
	p.volume_db = vol_db
	p.stream = _load_or_null(SFX_PATH + file_name)
	add_child(p)
	return p


func _make_3d(file_name: String, vol_db: float, unit_size: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.bus = "SFX"
	p.volume_db = vol_db
	p.unit_size = unit_size
	p.stream = _load_or_null(SFX_PATH + file_name)
	add_child(p)
	return p


func _make_ambient(file_name: String, vol_db: float) -> AudioStreamPlayer:
	# Не стартуем play() здесь — ambient запускается из _on_run_started вместе с
	# heartbeat'ом (после press START в главном меню). См. рефакторинг
	# "silent main menu" 2026-04-29.
	var p := AudioStreamPlayer.new()
	p.bus = "Ambient"
	p.volume_db = vol_db
	p.stream = _load_or_null(AMBIENT_PATH + file_name)
	add_child(p)
	return p


func _load_or_null(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _loop_stream(stream: AudioStream) -> void:
	# Включаем loop на загруженном OGG/WAV. Streams in Godot have a loop bool but
	# сигнатура per-class: AudioStreamOggVorbis.loop, AudioStreamWAV.loop_mode и т.д.
	# Простейший path: проверить has_method/property через `in`.
	if "loop" in stream:
		stream.loop = true


func _duck_bus(bus_idx: int, base_db: float, duck_db: float, duration_ms: int) -> void:
	if bus_idx < 0:
		return
	# Tween: instant attack (set к duck_db), потом ease-out tween обратно к base_db.
	# Вместо create_tween() со sleep мы просто set + tween 1 шага back.
	AudioServer.set_bus_volume_db(bus_idx, duck_db)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_bus_db.bind(bus_idx), duck_db, base_db, float(duration_ms) / 1000.0)


func _set_bus_db(value: float, bus_idx: int) -> void:
	if bus_idx < 0:
		return
	AudioServer.set_bus_volume_db(bus_idx, value)
