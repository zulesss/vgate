class_name DeathScreen extends CanvasLayer

# M4 death sequence (LOCKED timing из docs/systems/M4_spawn_numbers.md §4):
#   0.0–1.8с : death animation (TODO M5 feel pass — пока просто await)
#   1.8–2.4с : fade to black (0.6с)
#   2.4с     : score visible на чёрном
#   2.4–2.8с : fade-in арены (0.4с) — score остаётся overlay
#   2.8–3.3с : anti-accidental delay (0.5с) — кнопка disabled
#   3.3с+    : RESTART активна
# Phase ordering важно — кнопка не должна быть нажимаема до 3.3с (LOCKED rule).

const FADE_TO_BLACK_SECONDS := 0.6
const FADE_FROM_BLACK_SECONDS := 0.4
const ANTI_ACCIDENTAL_DELAY_SECONDS := 0.5
const PRE_FADE_DEATH_DELAY := 1.8

# M9 Hot Zones playtest tweak (2026-05-02): two distinct failure modes.
#   - Drain death (cap → 0 при t<RunLoop.RUN_DURATION) → "VELOCITY DRAINED"
#   - Objective fail (alive at t>=RunLoop.RUN_DURATION + <20 captures) → "OBJECTIVE FAILED"
# Discriminator — VelocityGate.get_alive_time() читается на _on_player_died:
# RunLoop set'ит is_alive=false ПОСЛЕ accumulator update, так что значение
# фризится точно. RUN_DURATION читается из RunLoop через class_name (single
# source of truth — балансировщик меняет timer в одном месте).
# Edge: cap=0 ровно на t=RUN_DURATION — drain путь стреляет в _physics_process
# первым (frame ordering), классифицируется как drain. Корректно semantically.

@onready var black: ColorRect = $Black
@onready var score_box: VBoxContainer = $ScoreBox
@onready var header_label: Label = $ScoreBox/HeaderLabel
@onready var score_label: Label = $ScoreBox/ScoreLabel
@onready var sphere_label: Label = $ScoreBox/SphereLabel
@onready var best_label: Label = $ScoreBox/BestLabel
@onready var restart_btn: Button = $ScoreBox/RestartButton


func _ready() -> void:
	visible = false
	black.modulate.a = 0.0
	score_box.visible = false
	restart_btn.disabled = true
	restart_btn.pressed.connect(_on_restart)
	Events.player_died.connect(_on_player_died)


func _on_player_died() -> void:
	visible = true
	# Release mouse cursor: игроку нужна возможность кликнуть RESTART.
	# DeathScreen — owner UI mode'а во время death sequence; restart восстанавливает.
	# player.gd set'ит CAPTURED только в _ready() и на mouse_capture action — не hot loop,
	# так что VISIBLE здесь не перебивается per-frame.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Phase 1: 1.8s freeze. Camera drift / ragdoll — feel-engineer M5 territory;
	# здесь просто wait. Если M5 решит что drift нужен в этом окне — добавит свой
	# subscriber на player_died, не правя этот файл.
	await get_tree().create_timer(PRE_FADE_DEATH_DELAY).timeout

	# Phase 2: fade-to-black 0.6s
	var t1 := create_tween()
	t1.tween_property(black, "modulate:a", 1.0, FADE_TO_BLACK_SECONDS)
	await t1.finished

	# Phase 3: показываем score (на чёрном). M9: final_score фризится в
	# ScoreState._on_player_died перед death sequence — current_score после
	# смерти теоретически мог бы остаться valid (process gated by is_alive)
	# но final_score deterministic.
	var captured: int = SphereDirector.captured_count
	var target: int = SphereDirector.CAPTURE_TARGET
	# Failure mode discriminator: alive_time >= RUN_DURATION → объект fail
	# (игрок дожил, но <20 captures). Иначе — drain death (cap→0 раньше времени).
	var alive_time: float = VelocityGate.get_alive_time()
	var objective_fail: bool = alive_time >= RunLoop.RUN_DURATION and captured < target
	if objective_fail:
		header_label.text = "OBJECTIVE FAILED"
		header_label.modulate = Color(0.95, 0.65, 0.30, 1)  # warning amber
	else:
		header_label.text = "VELOCITY DRAINED"
		header_label.modulate = Color(0.95, 0.30, 0.25, 1)  # drain red
	score_label.text = "Score: %d" % ScoreState.final_score
	# Sphere line: progress даже на death. Если игрок дошёл до target (>=20)
	# но всё равно умер до t=120 — almost-win, label tint'ится в зелёный.
	# Иначе — обычный "X / 20" cyan.
	if captured >= target:
		sphere_label.text = "Spheres: %d / %d (objective met)" % [captured, SphereDirector.TOTAL_SPHERES]
		sphere_label.modulate = Color(0.30, 0.85, 0.40, 1)
	else:
		sphere_label.text = "Spheres: %d / %d" % [captured, target]
		sphere_label.modulate = Color(0.478, 0.906, 0.906, 1)
	best_label.text = "Best: %d" % ScoreState.best_score
	score_box.visible = true

	# Phase 4: fade-in арены (0.4s) — score остаётся overlay
	var t2 := create_tween()
	t2.tween_property(black, "modulate:a", 0.0, FADE_FROM_BLACK_SECONDS)
	await t2.finished

	# Phase 5: 0.5s anti-accidental delay — игрок физически не может нажать
	# RESTART сразу при появлении (палец на ЛКМ от последнего выстрела).
	await get_tree().create_timer(ANTI_ACCIDENTAL_DELAY_SECONDS).timeout
	restart_btn.disabled = false
	restart_btn.grab_focus()


func _on_restart() -> void:
	# Hide UI ДО emit'а — иначе frame с visible death-screen + new run state.
	visible = false
	score_box.visible = false
	black.modulate.a = 0.0
	restart_btn.disabled = true
	# Симметрично _on_player_died: восстанавливаем CAPTURED перед emit'ом
	# (run_started → player снова активен, ему нужен locked cursor для FPS-mouselook).
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.run_restart_requested.emit()
