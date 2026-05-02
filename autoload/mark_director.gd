class_name MarkDirectorNode extends Node

# Marked Enemy Hunt — Arena A "Камера" objective director (autoload).
#
# Параллельная axis к sphere objective: только один из двух director'ов активен
# per run. Активация по group root-арены:
#   - Group "objective_marked_hunt" → MarkDirector активен, SphereDirector dormant
#   - Group "objective_spheres"     → SphereDirector активен, MarkDirector dormant
# Group check выполняется в _on_run_started — current_scene уже загружена.
#
# Spec (locked):
#   - Каждые MARK_INTERVAL_MIN..MARK_INTERVAL_MAX (12..15с) jitter — pick random
#     живого enemy, apply visual mark.
#   - Mark visible через стены (emissive aura + no_depth_test). Реализация в
#     enemy_base.apply_mark() — сюда не лезем.
#   - Kill marked → +1 kills, reroll через REROLL_DELAY (5с).
#   - Mark не убит за MARK_LIFETIME (28с) → expires, reroll через REROLL_DELAY.
#   - Marked enemy ушёл из tree без player kill (despawn / другая причина) →
#     expires (clean reroll, не chain на нового — "no progress" per spec).
#   - Win-eligible at kills >= KILL_TARGET (15).
#
# Mark detection of player-kill: enemy_base.die() сам эмитит Events.mark_killed
# если _is_marked=true. Director просто слушает signal и инкрементит. Это
# чище чем track'ить позицию через enemy_killed signal — owner состояния (enemy)
# знает свой mark флаг, race conditions исключены.
#
# Edge cases:
#   - apply_mark прилетает но в группе "enemy" нет живых (rare mid-game) →
#     ставим _waiting_for_enemy=true, retry через _process когда появится враг.
#   - Marked enemy is_dying=true в момент tree_exiting (player kill) → Events.mark_killed
#     уже emit'ился из enemy_base.die() ДО queue_free → tree_exiting обработается
#     как "уже учтённый kill" (через _kill_handled guard, set'ится в _on_mark_killed).

const KILL_TARGET := 15
const MARK_INTERVAL_MIN := 12.0
const MARK_INTERVAL_MAX := 15.0
const MARK_LIFETIME := 28.0
const REROLL_DELAY := 5.0
# Group name на root-арене сигнализирует "этот объектив активен".
const ARENA_GROUP_HUNT := &"objective_marked_hunt"

var _active: bool = false
var kills: int = 0

# WeakRef'ом не пользуемся — _active_mark всегда проверяется через is_instance_valid.
# Direct ref выживает между кадрами; на queue_free Godot не нулирует, но
# is_instance_valid(_active_mark) вернёт false → guard срабатывает.
var _active_mark: Node = null
# True пока ждём появления enemy (нет живых на момент попытки assignment).
# В _process пробуем pick'нуть на каждом тике пока не получится.
var _waiting_for_enemy: bool = false
# Time until next assignment attempt (после kill / expire / startup). При assigned
# mark'е переходит на _mark_lifetime_remaining tick.
var _next_assign_in: float = 0.0
# Time until current mark expires (mark assigned, но игрок не убил его).
var _mark_lifetime_remaining: float = 0.0
# Idempotency: tree_exiting прилетает на любом queue_free (kill / despawn / scene
# unload). Если kill уже обработан через mark_killed flow, tree_exiting не должен
# trigger'нуть expire — иначе double-emit. Set'ится в _on_active_mark_killed.
var _kill_handled: bool = false


func _ready() -> void:
	Events.run_started.connect(_on_run_started)
	Events.player_died.connect(_on_player_died)
	Events.run_won.connect(_on_run_won)
	# mark_killed эмитится из enemy_base.die() когда _is_marked=true (т.е. player kill,
	# потому что die() вызывается только из damage()→hp<=0 path'а через player.shoot).
	Events.mark_killed.connect(_on_active_mark_killed_signal)


func _process(delta: float) -> void:
	if not _active:
		return
	if not VelocityGate.is_alive:
		return

	# Pending assignment: либо ждём начало нового assign-cycle'а, либо уже tick'аем
	# lifetime активного mark'а.
	if _active_mark != null and is_instance_valid(_active_mark):
		_mark_lifetime_remaining -= delta
		if _mark_lifetime_remaining <= 0.0:
			_expire_current_mark()
		return

	# Mark не assigned (или _active_mark освобождён). Тикаем countdown to next
	# assignment. _waiting_for_enemy=true означает что timer уже истёк, но в группе
	# не было живых на тот момент — пробуем снова каждый кадр.
	if _waiting_for_enemy:
		_try_assign_mark()
		return

	_next_assign_in -= delta
	if _next_assign_in <= 0.0:
		_try_assign_mark()


func _on_run_started() -> void:
	# Determine active director per arena group. Если current_scene содержит arena
	# в group ARENA_GROUP_HUNT — мы активны. Иначе dormant.
	# get_tree().current_scene = main scene (main.tscn), arena — её child. Нужен
	# recursive group check: get_nodes_in_group возвращает all matching, hit-test'им
	# на non-empty result.
	_active = not get_tree().get_nodes_in_group(ARENA_GROUP_HUNT).is_empty()

	# Full state reset (даже если не active — на случай переключения арен между run'ами).
	kills = 0
	_clear_mark_silent()
	_waiting_for_enemy = false
	_kill_handled = false
	# Initial delay перед первым mark'ом — randomized в окне MIN..MAX. Игрок успевает
	# оглядеться, не получает mark instantly при респавне.
	_next_assign_in = randf_range(MARK_INTERVAL_MIN, MARK_INTERVAL_MAX)
	_mark_lifetime_remaining = 0.0


func _on_player_died() -> void:
	# Run terminated — clear visual mark чтобы не остался light'ом на restart'е.
	# State (kills, timers) reset'нется на следующий run_started, но visual cleanup
	# нужен сейчас (DeathScreen показывает арену через fade, mark был бы виден).
	_clear_mark_silent()


func _on_run_won() -> void:
	_clear_mark_silent()


func _try_assign_mark() -> void:
	# Random alive enemy. Группа "enemy" заполняется в EnemyBase._ready().
	# Фильтруем dying ones — нет смысла mark'нуть труп.
	var enemies := get_tree().get_nodes_in_group("enemy")
	var alive: Array[Node] = []
	for e in enemies:
		if not is_instance_valid(e):
			continue
		# is_dying — публично доступен через has_method check'а (is_dying — поле,
		# не method) → читаем как property через get(). EnemyBase always has это поле.
		if e.get("is_dying"):
			continue
		if e.get("is_spawning"):
			continue
		alive.append(e)

	if alive.is_empty():
		# Нет живых на этот момент. Set wait-flag: _process будет пытаться каждый
		# кадр пока враг не появится. Не reset'аем _next_assign_in — он уже истёк,
		# spec'у "ждём пока появится" соответствует.
		_waiting_for_enemy = true
		return

	var picked := alive[randi() % alive.size()]
	_active_mark = picked
	_mark_lifetime_remaining = MARK_LIFETIME
	_waiting_for_enemy = false
	_kill_handled = false

	# Hook tree_exiting на picked enemy: на queue_free (любая причина) уведомление
	# в _on_active_mark_tree_exiting. _kill_handled guard разделит player kill vs
	# any other free.
	if not picked.tree_exiting.is_connected(_on_active_mark_tree_exiting):
		picked.tree_exiting.connect(_on_active_mark_tree_exiting)
	# Hook mark_killed_self из enemy_base.die() — спарсим через signal
	# Events.mark_killed (emit'ится самим enemy на смерть). Подписку держим
	# постоянно (см. _ready'е).

	# Apply visual mark. Метод объявлен на EnemyBase (mark_visible через стены).
	if picked.has_method("apply_mark"):
		picked.apply_mark()


func _expire_current_mark() -> void:
	# Lifetime истёк, kill не случился. Visual cleanup + reroll через REROLL_DELAY.
	if _active_mark != null and is_instance_valid(_active_mark):
		if _active_mark.tree_exiting.is_connected(_on_active_mark_tree_exiting):
			_active_mark.tree_exiting.disconnect(_on_active_mark_tree_exiting)
		if _active_mark.has_method("clear_mark"):
			_active_mark.clear_mark()
	_active_mark = null
	_mark_lifetime_remaining = 0.0
	_next_assign_in = REROLL_DELAY
	_waiting_for_enemy = false
	_kill_handled = false


func _clear_mark_silent() -> void:
	# Reset без emit'ов — для startup / death / win cleanup. Visual restore чтобы
	# enemy не остался с emissive aura если по какой-то причине доживает (theoretically
	# не должен — SpawnController на run_started всех queue_free'ит, но defensive).
	if _active_mark != null and is_instance_valid(_active_mark):
		if _active_mark.tree_exiting.is_connected(_on_active_mark_tree_exiting):
			_active_mark.tree_exiting.disconnect(_on_active_mark_tree_exiting)
		if _active_mark.has_method("clear_mark"):
			_active_mark.clear_mark()
	_active_mark = null
	_mark_lifetime_remaining = 0.0
	_next_assign_in = 0.0


func _on_active_mark_tree_exiting() -> void:
	# Любой free на marked enemy. Если уже обработали через mark_killed (player
	# убил) — guard. Иначе — это despawn / scene reload / death от не-player cause:
	# expire path (no progress, reroll).
	if _kill_handled:
		# Cleanup ref'а — actual handling уже сделан в _on_active_mark_killed.
		_active_mark = null
		_kill_handled = false
		return
	# Expire без progress: spec "no progress, reroll mark в 5с".
	_active_mark = null
	_mark_lifetime_remaining = 0.0
	_next_assign_in = REROLL_DELAY


# Зовётся самим enemy_base.die() через emit Events.mark_killed (см. enemy_base.gd).
# enemy.tree_exiting прилетит сразу после из queue_free → _kill_handled guard'ит.
# Подписка в _ready'е (один раз, persistent).
func _on_active_mark_killed_signal() -> void:
	if not _active:
		return
	# Безопасности ради — mark_killed может прилететь не от нашего active (race
	# или ошибка в enemy_base). Если нет active mark'а — ignore.
	if _active_mark == null or not is_instance_valid(_active_mark):
		return
	kills += 1
	_kill_handled = true
	# Mark cleared через _on_active_mark_tree_exiting когда queue_free завершится.
	# Здесь только counter и timer'ы.
	_mark_lifetime_remaining = 0.0
	_next_assign_in = REROLL_DELAY
	# Disconnect tree_exiting — не нужен для kill flow (mark_killed уже зарегил факт),
	# но _on_active_mark_tree_exiting прилетит при queue_free и проверит _kill_handled.
	# НЕ disconnect'аем здесь — нужен для cleanup _active_mark = null в tree_exiting handler'е.
