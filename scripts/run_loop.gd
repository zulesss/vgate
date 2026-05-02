class_name RunLoop extends Node

# M4 in-place restart loop. Заменяет M1 reload_current_scene (run_manager.gd)
# полностью in-place reset:
#   1. VelocityGate.reset_for_run() — emit'ит Events.run_started
#   2. SpawnController._on_run_started — чистит врагов + state
#   3. ScoreState._on_run_started — обнуляет current_score, run_time
#   4. Здесь: возвращаем игрока на spawn-position, обнуляем velocity
#
# In-place вместо reload_current_scene выгоднее: сохраняет NavMesh, FOV controller,
# debug-hud connection'ы — экономим ~500мс перезагрузки + сохраняем feel'овую
# непрерывность (vignette material остаётся живым, GPU pipeline warm).
#
# M9 conquest: run теперь time-based (120с). RunLoop отвечает за:
#   - Spike phase trigger в t=90 (drain threshold step-up до 0.45)
#   - Win condition в t=120 (Events.run_won → WinScreen)
# Время читается из VelocityGate.get_alive_time() — single source of truth с
# accumulator'ом cap_avg в самом gate'е.
#
# M9 Hot Zones: win-eligibility теперь требует BOTH alive at 120s AND
# SphereDirector.captured_count >= CAPTURE_TARGET (15). Если игрок дожил с <15
# capture'ов — fail: эмитим Events.player_died напрямую (без force_kill, чтобы
# не зануливать velocity_cap — игрок survival'нул timer с легитимным cap'ом).
# DeathScreen показывает stats + sphere counter в "OBJECTIVE FAILED" виде —
# discriminator от drain death через VelocityGate.get_alive_time() >= 120
# (drain бы ударил раньше, alive_time < 120).
#
# M10 Journey (Arena C "Дорога"): третий objective type. Arena root в группе
# "objective_journey" → отключаем timer logic (нет 120с лимита, нет spike phase).
# Win-trigger — Area3D на финише уровня эмитит Events.journey_complete →
# RunLoop ставит is_alive=false + emit run_won. Failure mode только drain
# (cap → 0); никакого "objective failed" path'а — нет deadline'а. Score
# formula для journey тоже отличается (см. ScoreState).

const SPIKE_TRIGGER_TIME := 90.0
const RUN_DURATION := 120.0
const ARENA_GROUP_JOURNEY := &"objective_journey"

@export var player_path: NodePath
@onready var player: Node = get_node_or_null(player_path)

var _spike_active: bool = false
var _won: bool = false
# Set per-run в _on_run_started через group check на current arena. Если активна
# journey arena — _process пропускает timer-based win/fail, и win triggers через
# Events.journey_complete signal вместо t>=RUN_DURATION.
var _is_journey: bool = false


func _ready() -> void:
	# Первый старт run'а: reset_for_run() флипает VelocityGate.is_alive=true и
	# эмитит run_started — Player input разлоч'ивается, Sfx/MusicDirector
	# стартуют loop'ы. До ca9e4e5 дефолт is_alive=true маскировал это, но
	# теперь VelocityGate dormant by default → нужен явный init.
	VelocityGate.reset_for_run()
	Events.run_restart_requested.connect(_on_restart)
	Events.run_started.connect(_on_run_started)
	Events.journey_complete.connect(_on_journey_complete)


func _process(_delta: float) -> void:
	if not VelocityGate.is_alive or _won:
		return
	# Journey arena: нет timer'а вообще. Win triggered via journey_complete
	# (player walked into goal Area3D), failure — только drain death (cap=0)
	# который рутится через VelocityGate.player_died. Spike phase тоже отсутствует —
	# давление только от pre-placed defenders + drain если игрок встанет.
	if _is_journey:
		return
	var t: float = VelocityGate.get_alive_time()
	# Spike phase step-up: t≥90 → threshold 0.30 → 0.45. Idempotent через
	# _spike_active гард. Чистый data change, без player_hit emit'а — это
	# environmental/wave change, не damage event.
	if not _spike_active and t >= SPIKE_TRIGGER_TIME:
		_spike_active = true
		VelocityGate.current_drain_threshold = VelocityGate.SPIKE_THRESHOLD
	# Win/loss eligibility в t≥120. Two parallel objectives (mutually exclusive
	# per arena, see directors' _on_run_started routing):
	#   - SphereDirector active → win = alive AND captured >= CAPTURE_TARGET
	#   - MarkDirector active   → win = alive AND kills >= KILL_TARGET
	# Иначе — OBJECTIVE FAILED (alive до 120с но objective не выполнен).
	# В обоих случаях is_alive=false фризит state. Через _won гард — один раз.
	if t >= RUN_DURATION:
		_won = true
		VelocityGate.is_alive = false
		if _objective_met():
			Events.run_won.emit()
		else:
			# Objective fail: timer вышел но objective не выполнен. Эмитим player_died
			# напрямую (VelocityGate.force_kill бы тоже работал но он set'ит
			# velocity_cap=0 что нечестно для stats — игрок дожил, cap может быть
			# legit высоким). DeathScreen дискриминирует по alive_time + active director.
			Events.player_died.emit()


# Текущий objective — кто active director, тот и судит. Если оба dormant
# (theoretically — арена не в одной из групп; defensive) — объективом
# считается "просто доживи". В практике такая арена ошибочна: должна иметь
# objective_spheres ИЛИ objective_marked_hunt. Логирование через push_warning
# в run_started level — здесь просто fallback "win если дожил".
func _objective_met() -> bool:
	if SphereDirector._active:
		return SphereDirector.captured_count >= SphereDirector.CAPTURE_TARGET
	if MarkDirector._active:
		return MarkDirector.kills >= MarkDirector.KILL_TARGET
	return true


# Journey win path: GoalTrigger Area3D в arena scene'е эмитит journey_complete
# когда player_body вошёл в trigger volume. Mirror'ит timer-based win path: гард
# _won + just-in-time journey-detection, freeze is_alive, emit run_won.
#
# Just-in-time check (вместо чтения cached _is_journey из _on_run_started): если
# Events.run_started ещё не fire'нул на initial load (только на restart) — кэш
# stays false и win silently no-op'ит. Group-lookup на момент signal'а robust
# к timing — если уж journey_complete пришёл, journey arena живёт в дереве.
func _on_journey_complete() -> void:
	var is_journey: bool = not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty()
	if not is_journey or _won or not VelocityGate.is_alive:
		return
	_won = true
	VelocityGate.is_alive = false
	Events.run_won.emit()


func _on_run_started() -> void:
	# Reset state на каждый new run: spike может тригернуться заново, win-flag
	# сбрасывается чтобы restart после победы стартовал чистый.
	_spike_active = false
	_won = false
	# Journey arena detection (cached): _process читает _is_journey чтобы
	# skip'нуть timer-logic. _on_journey_complete делает свой own just-in-time
	# group lookup для robustness — кэш может быть stale если signal не пришёл.
	_is_journey = not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty()


func _on_restart() -> void:
	# Reset gate state и emit run_started — все listener'ы (spawn, score) подхватят.
	VelocityGate.reset_for_run()
	# Player: respawn() если есть метод (расширяемая convention), иначе fallback —
	# PlayerSpawn helper читает PlayerStart Marker3D активной арены и телепортирует.
	# До f0fe... (M10 journey fix) был хардкод (0,1,10) — поломка для arena_c_journey
	# где z=10 уже мимо start corridor wall и игрок застревал.
	if player == null:
		push_warning("RunLoop: player_path не указывает на существующую ноду — restart без player reset")
		return
	if player.has_method("respawn"):
		player.respawn()
		return
	PlayerSpawn.teleport_to_start(player, get_tree())
