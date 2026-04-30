class_name KillChainTracker extends Node

# M7 Kill Chain (docs/feel/M7_polish_spec.md §Эффект 3, revised 2026-04-30).
# 3+ kills за 3 сек → tier-based реакция:
#   - Tier 1/2 (≥3 / ≥5): per-kill kick через Events.kill_chain_triggered.
#   - Tier 7+: sustained state. Entry signal один раз при первом достижении counter≥7;
#     subsequent kills продолжают подтверждать стрик (refresh window timer) но
#     kill_chain_triggered НЕ эмитится. Exit signal на window timeout / death / run_started.
#
# Pivot после плейтеста: per-kill jolts (FOV punch +15°, camera shake, warm flash) на
# tier 7+ читались как «дёрганые». Sustained FOV +10° + cap ceiling +10 = больше «in
# the zone» меньше «вибрация».
#
# Архитектура:
#   - Counter инкрементируется на каждый Events.enemy_killed
#   - Timer (3 сек, one-shot, restart per kill) — когда истекает, counter=0
#   - _streak_active: idempotent flag для tier 7+ entry/exit emit'а
#
# Edge cases:
#   - Pause: Timer pausable (default process_mode), chain паузится с игрой
#   - Death: counter=0, Timer.stop, streak_exited если был active
#   - Run started: reset, streak_exited если был active

const CHAIN_WINDOW_SEC := 3.0
const TIER_1_THRESHOLD := 3
const TIER_2_THRESHOLD := 5
const TIER_3_THRESHOLD := 7

var _kill_count: int = 0
var _window_timer: Timer
# Sustained streak (tier 7+) — true пока counter ≥ 7 в активном окне. Idempotent
# guard для одноразового entry-emit'а: повторные kill'ы при ≥7 не реэмитят entered.
var _streak_active: bool = false


# Peek для listener'ов которым нужно ЗНАТЬ предстоящий tier ДО того как сам KillChain
# обработал enemy_killed (Sfx использует это чтобы оверрайд'ить kill_confirm.pitch_scale
# СИНХРОННО с тем же kill'ом). Учитывая возможный timeout: если current_count > 0 но
# Timer истёк (race-edge между tick'ами) — peek = 1, как бы первый в новой chain.
func peek_tier_after_next_kill() -> int:
	# Если timer истёк или не запущен — следующий kill стартует свежий счёт = 1.
	var base: int = _kill_count
	if _window_timer == null or _window_timer.is_stopped() or _window_timer.time_left <= 0.0:
		base = 0
	return _calculate_tier(base + 1)


func _ready() -> void:
	_window_timer = Timer.new()
	_window_timer.one_shot = true
	_window_timer.wait_time = CHAIN_WINDOW_SEC
	# default process_mode (PAUSABLE) — pause замораживает chain, корректно по spec
	add_child(_window_timer)
	_window_timer.timeout.connect(_on_window_timeout)

	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_died.connect(_on_player_died)
	Events.run_started.connect(_on_run_started)


func _on_enemy_killed(_restore: int, pos: Vector3, _type: String) -> void:
	# Death-frame guard: kill burst уже не должен играть (sfx/player проверяют is_alive),
	# chain тоже nope. Защищает от race с force_kill→enemy_killed одного кадра.
	if not VelocityGate.is_alive:
		return
	# Window-expiry race: если timer истёк, но _on_window_timeout ещё не отработал
	# (signal ordering — emit enemy_killed может попасть раньше timeout callback'а
	# в том же frame'е), reset counter тут же. Иначе stale count → ложный tier
	# trigger на изолированном kill'е после долгого простоя.
	if _window_timer.is_stopped() or _window_timer.time_left <= 0.0:
		_kill_count = 0
	_kill_count += 1
	_window_timer.start()  # restart на каждый kill — окно "от последнего kill"

	var tier: int = _calculate_tier(_kill_count)
	# Tier 7+: sustained semantics. Не эмитим kill_chain_triggered (listeners
	# tier 1/2 only), вместо этого entry-signal один раз. Subsequent kills при
	# counter ≥ 7 просто рефрешат окно и держат стрик.
	if tier == 3:
		if not _streak_active:
			_streak_active = true
			Events.kill_chain_streak_entered.emit(pos)
	elif tier > 0:
		Events.kill_chain_triggered.emit(tier, pos)


func _on_window_timeout() -> void:
	_kill_count = 0
	_end_streak_if_active()


func _on_player_died() -> void:
	_kill_count = 0
	_window_timer.stop()
	_end_streak_if_active()


func _on_run_started() -> void:
	_kill_count = 0
	_window_timer.stop()
	_end_streak_if_active()


# Idempotent: повторные вызовы no-op'нутся. Используется на window timeout / death /
# run_started — одна точка управления streak_exited emit'ом.
func _end_streak_if_active() -> void:
	if _streak_active:
		_streak_active = false
		Events.kill_chain_streak_exited.emit()


# Tier mapping. Tier 3 (7+) повторно "регистрируется" на каждый kill пока counter ≥ 7,
# но per-kill emit идёт только для tier 1/2 — tier 3 обрабатывается через streak
# entry/exit semantics в _on_enemy_killed.
static func _calculate_tier(count: int) -> int:
	if count >= TIER_3_THRESHOLD:
		return 3
	if count == TIER_2_THRESHOLD:
		return 2
	if count == TIER_1_THRESHOLD:
		return 1
	return 0
