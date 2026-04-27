class_name RunManagerNode extends Node

# Orchestrator restart-loop'а. M1 — простейший вариант: игрок умер → 2.8 сек wait → reload current_scene.
# Полный визуальный разбив (1.8 death anim / 0.6 score / 0.4 fade-in) — M2 feel pass.

const RESTART_DELAY := 2.8


func _ready() -> void:
	Events.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	# Wait c ignore_time_scale=true чтобы будущий time-dilation на death (M2) не растягивал паузу.
	var timer := get_tree().create_timer(RESTART_DELAY, true, false, true)
	await timer.timeout
	_restart_run()


func _restart_run() -> void:
	VelocityGate.reset_for_run()
	get_tree().reload_current_scene()
