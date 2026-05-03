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
# M10 Journey (Arena C "Дорога"): clear-and-escape objective.
#   Win   = alive AND all enemies dead AND reached goal AND alive_time < 120
#   Fail  = drain (cap → 0) OR timer expires before win condition met
# Group "objective_journey" gates the journey-specific path: 120с deadline
# применяется но без spike phase (давление от pre-placed defenders + pursuers,
# не env threshold step-up). Goal Area3D эмитит journey_complete; RunLoop
# вэлидирует "all enemies dead" group check + alive_time. Если игрок дошёл
# до goal но defenders ещё живы — НЕ win, продолжает играть до timer (может
# вернуться зачистить или сбежал слишком рано).
# Enemy count: get_tree().get_nodes_in_group("enemy") — EnemyBase.add_to_group("enemy")
# в _ready'е, decrement через queue_free. Pre-placed + dynamic pursuers
# одинаково counted.
#
# Cathedral arena (Arena C "Собор") win path:
#   Win   = alive AND boss_killed AND all 4 altars captured
#   Fail  = drain death only (no timer)
# AltarDirector эмитит Events.boss_killed на kill — RunLoop ловит, проверяет
# AltarDirector.captured_count == 4 + alive, эмитит run_won. Spike phase OFF
# (давление органическое от altar spawns + boss). Timer-fail OFF (drain — единственный
# fail mode, mirror journey без timer).

const SPIKE_TRIGGER_TIME := 90.0
const RUN_DURATION := 120.0
const ARENA_GROUP_JOURNEY := &"objective_journey"
const ARENA_GROUP_CATHEDRAL := &"objective_cathedral"
const ENEMY_GROUP := &"enemy"

@export var player_path: NodePath
@onready var player: Node = get_node_or_null(player_path)

var _spike_active: bool = false
var _won: bool = false
# Set per-run в _on_run_started через group check на current arena. Если активна
# journey arena — timer-fail активен но win triggers через Events.journey_complete +
# all_enemies_dead вместо t>=RUN_DURATION objective check.
var _is_journey: bool = false
# Cathedral arena: bossfight + altar capture run. Timer-fail OFF, spike OFF.
# Win triggered via Events.boss_killed + AltarDirector.captured_count check.
var _is_cathedral: bool = false
# Player вошёл в journey goal Area3D но territory ещё не cleared — ждём
# последнего kill'а который finalize'ит win. Reset на run_started.
var _journey_goal_reached: bool = false


func _ready() -> void:
	# Connect signals FIRST, then defer initial reset_for_run() to next idle frame.
	# reset_for_run() synchronously emits Events.run_started — на первом запуске
	# RunLoop._ready ранее эмитил его до того как _on_run_started был connect'нут,
	# из-за чего _is_cathedral оставался false и cathedral arena ловила 120s win.
	# Та же race касается других scene-script subscribers (RunHud, IntroText,
	# SpawnController) — defer спасает всех: их _ready'и успевают connect'нуться
	# до synchronous emit'а в idle frame.
	# До ca9e4e5 дефолт is_alive=true маскировал это, но теперь VelocityGate
	# dormant by default → нужен явный init.
	Events.run_restart_requested.connect(_on_restart)
	Events.run_started.connect(_on_run_started)
	Events.journey_complete.connect(_on_journey_complete)
	Events.boss_killed.connect(_on_boss_killed)
	call_deferred("_initial_run_start")


func _initial_run_start() -> void:
	VelocityGate.reset_for_run()


func _process(_delta: float) -> void:
	if not VelocityGate.is_alive or _won:
		return
	# Cathedral arena: drain death = единственный fail. Win — через Events.boss_killed
	# (см. _on_boss_killed). Timer-fail OFF, spike OFF — sequence pacing уже задаётся
	# AltarDirector'ом (4 altars * dwell + boss phase). Early-return: ни spike-step,
	# ни 120с win/fail check не применимы.
	if _is_cathedral:
		return
	var t: float = VelocityGate.get_alive_time()
	# Journey arena: spike phase OFF (давление от pre-placed enemies + pursuers
	# которое уже шкалируется milestone'ами). Только timer-fail path активен:
	# t≥120 без win → OBJECTIVE FAILED (player_died emit). Win триггерится из
	# _on_journey_complete по факту goal entry, не здесь.
	if _is_journey:
		# Win check polled per-frame (вместо broken signal-based path): goal entry
		# set'ит _journey_goal_reached, а последний enemy queue_free's только после
		# 0.6с death animation — signal на enemy_killed эмитится ДО free и видит
		# умирающего как "ещё в группе". Polling в _process ловит exact frame
		# когда последний queue_free отработал и группа реально пуста.
		if _journey_goal_reached and _all_enemies_dead():
			_won = true
			VelocityGate.is_alive = false
			Events.run_won.emit()
			return
		if t >= RUN_DURATION:
			_won = true
			VelocityGate.is_alive = false
			Events.player_died.emit()
		return
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
# Clear-and-escape: goal entry alone недостаточно — требуем all_enemies_dead().
# Если игрок дошёл до goal но defenders ещё живы → silently no-op (играет
# дальше, может вернуться зачистить или ждать timer'а). Идея: goal — финиш,
# но финиш засчитывается только если территория зачищена.
#
# Just-in-time check (вместо чтения cached _is_journey из _on_run_started): если
# Events.run_started ещё не fire'нул на initial load (только на restart) — кэш
# stays false и win silently no-op'ит. Group-lookup на момент signal'а robust
# к timing — если уж journey_complete пришёл, journey arena живёт в дереве.
func _on_journey_complete() -> void:
	var is_journey: bool = not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty()
	if not is_journey or _won or not VelocityGate.is_alive:
		return
	if not _all_enemies_dead():
		# Player reached goal но territory не cleared — продолжает играть. Goal
		# trigger у себя guard'ит против double-fire (_triggered=true), что значит
		# повторный pass-through уже не выстрелит. Если игрок выйдет/войдёт после
		# зачистки — _on_journey_complete не повторится. Поэтому запоминаем что
		# goal уже посещён, и polling в _process ловит момент когда последний
		# enemy queue_free's (после 0.6с death anim) и группа реально пуста.
		_journey_goal_reached = true
		return
	_won = true
	VelocityGate.is_alive = false
	Events.run_won.emit()


# Helper: все враги в группе "enemy" мертвы. EnemyBase.add_to_group("enemy") в
# _ready'е, queue_free на death decrement'ит группу автоматически. Pre-placed
# defenders + dynamic pursuers все одинаково counted.
func _all_enemies_dead() -> bool:
	return get_tree().get_nodes_in_group(ENEMY_GROUP).is_empty()


func _on_run_started() -> void:
	# Reset state на каждый new run: spike может тригернуться заново, win-flag
	# сбрасывается чтобы restart после победы стартовал чистый.
	_spike_active = false
	_won = false
	_journey_goal_reached = false
	# Journey arena detection (cached): _process читает _is_journey для timer-fail
	# и polling win check (goal_reached + all_enemies_dead). _on_journey_complete
	# делает свой own just-in-time group lookup для robustness — кэш может быть
	# stale если signal не пришёл (initial load до первого run_started).
	_is_journey = not get_tree().get_nodes_in_group(ARENA_GROUP_JOURNEY).is_empty()
	_is_cathedral = not get_tree().get_nodes_in_group(ARENA_GROUP_CATHEDRAL).is_empty()


# Cathedral win path: AltarDirector эмитит boss_killed когда type="boss" enemy
# убит. Validate: alive AND captured_count == 4 AND boss really killed (signal
# фильтр в AltarDirector). Если ещё не все 4 altars captured (boss spawn
# случился через cathedral_phase_complete т.е. требовал 4/4 — но defensive guard
# на случай rebalance в будущем) — silently no-op (drain или продолжение).
func _on_boss_killed() -> void:
	if not _is_cathedral or _won or not VelocityGate.is_alive:
		return
	if AltarDirector.captured_count < AltarDirector.ALTAR_COUNT:
		return
	_won = true
	VelocityGate.is_alive = false
	Events.run_won.emit()


func _on_restart() -> void:
	# Re-instantiate arena ДО reset_for_run(): pre-placed defenders в arena scene
	# (Defenders/ под journey arena) на первом run'е queue_free'ятся при kill'ах.
	# Без re-instantiate ringpa restart даёт пустую арену. Synchronous remove_child
	# в Main.reinstantiate_arena() выкидывает старый arena root из дерева до того,
	# как run_started listener'ы (SpawnController, директора) запросят группы —
	# они увидят свежие Marker3D'ы / Defenders, не старые.
	# Sphere/Mark арены не имеют pre-placed enemies, но re-instantiate всё равно
	# безопасен: NavBaker внутри арены делает sync rebake в _ready (см. nav_baker.gd),
	# spawn-points refresh'аются в SpawnController на run_started (см. _on_run_started).
	var main: Node = get_parent()
	if main != null and main.has_method("reinstantiate_arena"):
		main.reinstantiate_arena()
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
