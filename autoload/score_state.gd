class_name ScoreStateNode extends Node

# M13 per-arena scoring (replaces M9 single formula):
#   Plac (objective_spheres)      → score = floor(avg_cap × kills)
#   Камера (objective_marked_hunt) → score = floor(avg_cap × kills)
#   Собор (objective_cathedral)   → score = floor(avg_cap × speed_factor × 50)
#       speed_factor = clamp(CATHEDRAL_BENCHMARK_TIME / max(t_alive, 1.0), 0.3, 3.0)
#       par-time anchor: 180с — faster=better, slower=worse, bounded.
#
# Score теперь чисто end-of-run / live derived value: считается заново каждый _process
# для HUD'а, основанные на arena_key (Plac/Камера/Cathedral). На death/win
# фиксируется final_score для отображения. Old per-kill accumulation удалён.
#
# Arena key ставится в _on_run_started через group lookup (objective_spheres →
# "plac", objective_marked_hunt → "kamera", objective_cathedral → "cathedral").
# Legacy journey arena → "arena_b" fallback (compat с прошлыми save'ами).
#
# Persistence: high-score per arena в user://vgate_progress.cfg секция
# [high_scores], key = arena name. Поддержка multiple arena (per-arena best).

const SAVE_PATH := "user://vgate_progress.cfg"
const DEFAULT_ARENA_KEY := "arena_b"
const ARENA_KEY_PLAC := "plac"
const ARENA_KEY_KAMERA := "kamera"
const ARENA_KEY_CATHEDRAL := "cathedral"
const ARENA_GROUP_SPHERES := &"objective_spheres"
const ARENA_GROUP_MARKED_HUNT := &"objective_marked_hunt"
const ARENA_GROUP_CATHEDRAL := &"objective_cathedral"
# Cathedral par-time anchor (sec). Игрок прошёл за 180с → speed_factor = 1.0;
# 90с → 2.0 (cap'ed by clamp); 360с → 0.5. Boss-fight pacing reference.
const CATHEDRAL_BENCHMARK_TIME := 180.0
const CATHEDRAL_SCORE_MULTIPLIER := 50.0
const CATHEDRAL_SPEED_FACTOR_MIN := 0.3
const CATHEDRAL_SPEED_FACTOR_MAX := 3.0

var current_score: int = 0          # live derived value, обновляется каждый _process
var best_score: int = 0             # best для текущей арены, читается из save
var run_time: float = 0.0           # alive-time mirror VelocityGate.get_alive_time() — для HUD timer'а
var kills: int = 0                  # M9 простой counter (raw)
var final_score: int = 0            # frozen score на момент death/win — для DeathScreen/WinScreen
var current_arena_key: String = DEFAULT_ARENA_KEY


func _ready() -> void:
	_load_best()
	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_died.connect(_on_player_died)
	Events.run_won.connect(_on_run_won)


func _process(_delta: float) -> void:
	# Run timer mirror'ит VelocityGate.get_alive_time() — для HUD label'а.
	# Score computed live per-arena formula. Death sequence (1.8с +
	# fade) — VelocityGate.is_alive=false, get_alive_time замораживается, score
	# зафризится на final_score (выставляется в _on_player_died/_on_run_won).
	if VelocityGate.is_alive:
		run_time = VelocityGate.get_alive_time()
		var new_score: int = _compute_live_score()
		if new_score != current_score:
			current_score = new_score
			Events.score_changed.emit(current_score)


# Per-arena score formula. Pure function — testable.
# - Plac/Kamera: floor(avg_cap × kills) — pure efficiency, no time component.
# - Cathedral: floor(avg_cap × speed_factor × 50) — par-time anchored.
func _compute_live_score() -> int:
	var avg_cap: float = VelocityGate.get_avg_cap_over_run()
	if current_arena_key == ARENA_KEY_CATHEDRAL:
		var t_alive: float = VelocityGate.get_alive_time()
		var speed_factor: float = clampf(
			CATHEDRAL_BENCHMARK_TIME / maxf(t_alive, 1.0),
			CATHEDRAL_SPEED_FACTOR_MIN,
			CATHEDRAL_SPEED_FACTOR_MAX
		)
		return int(floor(avg_cap * speed_factor * CATHEDRAL_SCORE_MULTIPLIER))
	# Plac / Kamera / legacy fallback — pure kills × avg_cap
	return int(floor(float(kills) * avg_cap))


func _detect_arena_key() -> String:
	# Group lookup для определения текущей арены. Per-arena keys persist в save'е
	# отдельно — best score не cross-pollinates между ареной.
	var tree := get_tree()
	if not tree.get_nodes_in_group(ARENA_GROUP_CATHEDRAL).is_empty():
		return ARENA_KEY_CATHEDRAL
	if not tree.get_nodes_in_group(ARENA_GROUP_MARKED_HUNT).is_empty():
		return ARENA_KEY_KAMERA
	if not tree.get_nodes_in_group(ARENA_GROUP_SPHERES).is_empty():
		return ARENA_KEY_PLAC
	return DEFAULT_ARENA_KEY


func _on_run_started() -> void:
	current_score = 0
	final_score = 0
	run_time = 0.0
	kills = 0
	# Detect arena key (per-arena scoring + per-arena best score persistence).
	current_arena_key = _detect_arena_key()
	# Re-load best для текущей арены (на случай arena swap'а через main.gd).
	# Cheap: ConfigFile read раз в run_started, не каждый кадр.
	_load_best()
	Events.score_changed.emit(0)


func _on_enemy_killed(_restore: int, _pos: Vector3, _type: String) -> void:
	if not VelocityGate.is_alive:
		return
	# Все типы (melee/shooter/swarmling) считаются 1 kill — score derives from
	# avg_cap × time, не от type weight. Identity типов остаётся в spawn weights /
	# enemy stats, не в score formula. Проще читается + меньше под dust под
	# конkretные числа в M9 conquest balance pass.
	kills += 1


func _on_player_died() -> void:
	# Freeze final score на момент смерти. _process больше не тикает (VelocityGate.is_alive=false).
	final_score = current_score
	if final_score > best_score:
		best_score = final_score
		_save_best()


func _on_run_won() -> void:
	# RunLoop set'ит is_alive=false ДО emit'а (freeze spawn/player), поэтому _process
	# больше не пересчитает. Computed snapshot здесь — deterministic final value.
	# get_alive_time / get_avg_cap_over_run читают accumulator'ы (не зависят от is_alive).
	final_score = _compute_live_score()
	current_score = final_score
	Events.score_changed.emit(current_score)
	if final_score > best_score:
		best_score = final_score
		_save_best()


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_score = int(cf.get_value("high_scores", current_arena_key, 0))
	else:
		best_score = 0
	Events.high_score_loaded.emit(best_score)


func _save_best() -> void:
	var cf := ConfigFile.new()
	# Read existing данные (не перезаписать другие arena keys / settings секции если они тут).
	cf.load(SAVE_PATH)  # OK если не существует — cf останется пустым
	cf.set_value("high_scores", current_arena_key, best_score)
	cf.save(SAVE_PATH)
