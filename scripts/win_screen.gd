class_name WinScreen extends CanvasLayer

# M9 conquest: arena complete screen (parallel к DeathScreen, но show'ится на
# Events.run_won а не player_died). Layout зеркальный — header "ARENA COMPLETE",
# breakdown (kills, avg cap, time alive, score), best line, RESTART кнопка.
#
# Timing проще чем у death_screen — игрок ещё на ногах, без death animation.
# 0.0 — show + freeze input
# 0.0–0.5 — fade-in белого тонкого overlay'а (subtle, не black like death)
# 0.5+ — RESTART активна (anti-accidental delay 0.5 — палец мог быть на shoot
#        в момент 120-й секунды).

const FADE_IN_SECONDS := 0.5
const ANTI_ACCIDENTAL_DELAY := 0.5

@onready var bg: ColorRect = $Bg
@onready var box: VBoxContainer = $Box
@onready var header: Label = $Box/HeaderLabel
@onready var kills_label: Label = $Box/KillsLabel
@onready var avg_cap_label: Label = $Box/AvgCapLabel
@onready var time_label: Label = $Box/TimeLabel
@onready var sphere_label: Label = $Box/SphereLabel
@onready var score_label: Label = $Box/ScoreLabel
@onready var best_label: Label = $Box/BestLabel
@onready var restart_btn: Button = $Box/RestartButton


func _ready() -> void:
	visible = false
	bg.modulate.a = 0.0
	box.visible = false
	restart_btn.disabled = true
	restart_btn.pressed.connect(_on_restart)
	Events.run_won.connect(_on_run_won)


func _on_run_won() -> void:
	visible = true
	# UI mode: симметрично DeathScreen — отпускаем cursor чтобы игрок мог нажать
	# RESTART. RunLoop._won гард + VelocityGate.is_alive продолжают блокировать
	# spawn/score/AI пока RESTART не сработает.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Заполняем breakdown текущими value'ами из ScoreState (final_score фризится
	# в _on_run_won самого ScoreState'а — порядок connect'а не критичен, оба
	# подписаны до эмита).
	kills_label.text = "Kills: %d" % ScoreState.kills
	var avg_cap: float = VelocityGate.get_avg_cap_over_run()
	avg_cap_label.text = "Avg Cap: %d" % int(round(avg_cap))
	var t_alive: float = VelocityGate.get_alive_time()
	time_label.text = "Time: %.1f / 120" % t_alive
	# Active objective metric: sphere counter vs marked-kills counter. Один из
	# director'ов active (set'ится в run_started через group check'у).
	if MarkDirector._active:
		sphere_label.text = "Marked Kills: %d / %d" % [MarkDirector.kills, MarkDirector.KILL_TARGET]
	else:
		sphere_label.text = "Spheres: %d / %d" % [SphereDirector.captured_count, SphereDirector.TOTAL_SPHERES]
	score_label.text = "SCORE: %d" % ScoreState.final_score
	best_label.text = "BEST: %d" % ScoreState.best_score

	box.visible = true
	# Subtle fade-in: заметный, но не закрывает арену полностью (игрок видит
	# что пережил волну).
	var t1 := create_tween()
	t1.tween_property(bg, "modulate:a", 1.0, FADE_IN_SECONDS)
	await t1.finished

	await get_tree().create_timer(ANTI_ACCIDENTAL_DELAY).timeout
	restart_btn.disabled = false
	restart_btn.grab_focus()


func _on_restart() -> void:
	visible = false
	box.visible = false
	bg.modulate.a = 0.0
	restart_btn.disabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Тот же канал что и DeathScreen — RunLoop._on_restart подхватит и сделает
	# VelocityGate.reset_for_run() + player respawn.
	Events.run_restart_requested.emit()
