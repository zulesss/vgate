class_name ScoreStateNode extends Node

# M4 ScoreState — autoload. Score formula:
#   score_per_kill = base * time_mult * bonus_mult
#     base = 100 melee / 150 shooter
#     time_mult = 1 + run_time / 300
#     bonus_mult = 1.25 при velocity_cap >= 80 ("in-form play"), иначе 1.0
# Числа из docs/systems/M4_spawn_numbers.md §3.
#
# Persistence: best_score в user://vgate_progress.cfg, читается на _ready'е.

const SAVE_PATH := "user://vgate_progress.cfg"
const BASE_MELEE := 100
const BASE_SHOOTER := 150
const BASE_SWARMLING := 50
const TIME_MULT_DENOMINATOR := 300.0
const IN_FORM_CAP_THRESHOLD := 80.0
const IN_FORM_BONUS := 1.25

var current_score: int = 0
var best_score: int = 0
var run_time: float = 0.0


func _ready() -> void:
	_load_best()
	Events.run_started.connect(_on_run_started)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_died.connect(_on_player_died)


func _process(delta: float) -> void:
	# Run timer тикает только пока игрок жив. Death sequence (1.8с death anim +
	# 0.6с fade) НЕ должен накачивать time_multiplier на kill'ах в эти секунды
	# (хотя kill'ов после смерти и быть не может — guard на is_alive в kill-listener'е
	# тоже стоит, defense in depth). Пауза по is_alive — простейший контракт.
	if VelocityGate.is_alive:
		run_time += delta


func _on_run_started() -> void:
	current_score = 0
	run_time = 0.0
	Events.score_changed.emit(0)


func _on_enemy_killed(_restore: int, _pos: Vector3, type: String) -> void:
	if not VelocityGate.is_alive:
		return
	var base: int = BASE_MELEE
	if type == "shooter":
		base = BASE_SHOOTER
	elif type == "swarmling":
		base = BASE_SWARMLING
	var time_mult: float = 1.0 + run_time / TIME_MULT_DENOMINATOR
	var bonus_mult: float = IN_FORM_BONUS if VelocityGate.velocity_cap >= IN_FORM_CAP_THRESHOLD else 1.0
	current_score += int(base * time_mult * bonus_mult)
	Events.score_changed.emit(current_score)


func _on_player_died() -> void:
	if current_score > best_score:
		best_score = current_score
		_save_best()


func _load_best() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best_score = int(cf.get_value("score", "best", 0))
	Events.high_score_loaded.emit(best_score)


func _save_best() -> void:
	var cf := ConfigFile.new()
	cf.set_value("score", "best", best_score)
	cf.save(SAVE_PATH)
