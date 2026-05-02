class_name ScoreStateNode extends Node

# M9 conquest score formula (replace M4 kills × time_mult × bonus_mult):
#   score = floor(kills × avg_cap × time_alive_normalized)
#   where:
#     avg_cap = ∫(velocity_cap × dt) / alive_time   (0..100 диапазон)
#     time_alive_normalized = clamp(alive_time / 120, 0, 1)
#
# Score теперь чисто end-of-run / live derived value: kills × avg × tnorm зависит
# от three running aggregates (kills counter, cap accumulator в gate'е, alive_time
# в gate'е), поэтому считается заново каждый _process для HUD'а. На death/win
# фиксируется final_score для отображения. Old per-kill accumulation удалён.
#
# Persistence: high-score per arena в user://vgate_progress.cfg секция
# [high_scores], key = arena name. Поддержка multiple arena (M10 ready).

const SAVE_PATH := "user://vgate_progress.cfg"
const RUN_DURATION := 120.0
const DEFAULT_ARENA_KEY := "arena_b"

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
	# Score computed live: kills × avg_cap × time_norm. Death sequence (1.8с +
	# fade) — VelocityGate.is_alive=false, get_alive_time замораживается, score
	# зафризится на final_score (выставляется в _on_player_died/_on_run_won).
	if VelocityGate.is_alive:
		run_time = VelocityGate.get_alive_time()
		var new_score: int = _compute_live_score()
		if new_score != current_score:
			current_score = new_score
			Events.score_changed.emit(current_score)


# M9: floor(kills × avg_cap × time_norm). Pure function — testable.
func _compute_live_score() -> int:
	var avg_cap: float = VelocityGate.get_avg_cap_over_run()
	var t_alive: float = VelocityGate.get_alive_time()
	var t_norm: float = clampf(t_alive / RUN_DURATION, 0.0, 1.0)
	return int(floor(float(kills) * avg_cap * t_norm))


func _on_run_started() -> void:
	current_score = 0
	final_score = 0
	run_time = 0.0
	kills = 0
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
	# t_norm = 1.0 на победе → score = kills × avg_cap (full multiplier).
	# Final compute явный (а не последний _process): VelocityGate.is_alive ещё true в
	# момент эмита, _process успел бы посчитать, но мы хотим деterministic snapshot.
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
