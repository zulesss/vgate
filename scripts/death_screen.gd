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

# M12 narrative — drain death header variants (terminal-style verdict). RNG pick
# weighted: default 60% / variant-2 25% / variant-3 10%. Fast-death (alive_time
# < 30s) overrides RNG → fixed self-irony variant.
const DRAIN_FAST_DEATH_THRESHOLD := 30.0
const DRAIN_HEADER_DEFAULT := "ПРЕВЫШЕН ПОРОГ СКОРОСТИ\nПРИГОВОР ПРИВЕДЁН В ИСПОЛНЕНИЕ"
const DRAIN_HEADER_VARIANT_2 := "ДВИЖЕНИЕ НЕДОСТАТОЧНО\nВЕРДИКТ: ПОДТВЕРЖДЁН"
const DRAIN_HEADER_VARIANT_3 := "КИНЕТИЧЕСКАЯ СИГНАТУРА ПОТЕРЯНА\nИНИЦИАЛИЗАЦИЯ ПРОТОКОЛА ЗАВЕРШЕНИЯ"
const DRAIN_HEADER_FAST := "ВЫ ОСТАНОВИЛИСЬ.\nИМ И НЕ ПОНАДОБИЛОСЬ."
const OBJECTIVE_FAIL_HEADER := "ЗАДАЧА ПРОВАЛЕНА"

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
	# Active objective metric — sphere counter vs marked kills, в зависимости
	# от arena. Сохраняем same shape: progress, optional "objective met" tint,
	# objective_fail discriminator.
	#
	# M10 Journey clear-and-escape: 2 failure modes по alive_time discriminator'у:
	#   - drain (cap → 0 при alive_time < RUN_DURATION) → "VELOCITY DRAINED"
	#   - timer expired без win (alive_time >= RUN_DURATION, RunLoop эмитнул
	#     player_died через timer-fail path) → "OBJECTIVE FAILED" — territory
	#     не зачищена ИЛИ goal не достигнут вовремя.
	# Sphere/Hunt counter row скрываем (не релевантно journey).
	var is_journey: bool = not get_tree().get_nodes_in_group(&"objective_journey").is_empty()
	var is_cathedral: bool = not get_tree().get_nodes_in_group(&"objective_cathedral").is_empty()
	var alive_time: float = VelocityGate.get_alive_time()
	if is_cathedral:
		# Cathedral: drain death — единственный fail mode (no timer). Always
		# drain header. Altar progress показываем для context'а — игрок
		# мог зацепить 2 altars прежде чем умер от drain, это полезный feedback.
		header_label.text = _pick_drain_header(alive_time)
		header_label.modulate = Color(0.95, 0.30, 0.25, 1)
		sphere_label.visible = true
		var c: int = AltarDirector.captured_count
		var target: int = AltarDirector.ALTAR_COUNT
		if c >= target:
			sphere_label.text = "Алтари: %d / %d (босс выжил)" % [c, target]
			sphere_label.modulate = Color(1.0, 0.8, 0.2, 1)  # gold — captured altars
		else:
			sphere_label.text = "Алтари: %d / %d" % [c, target]
			sphere_label.modulate = Color(1.0, 0.5, 0.3, 1)  # orange — incomplete
	elif is_journey:
		if alive_time >= RunLoop.RUN_DURATION:
			header_label.text = OBJECTIVE_FAIL_HEADER
			header_label.modulate = Color(0.95, 0.65, 0.30, 1)  # warning amber
		else:
			header_label.text = _pick_drain_header(alive_time)
			header_label.modulate = Color(0.95, 0.30, 0.25, 1)  # drain red
		sphere_label.visible = false
	else:
		var progress: int = 0
		var target: int = 1
		var total_pool: int = 1  # Default fallback
		var metric_label: String = "Сферы"
		if MarkDirector._active:
			progress = MarkDirector.kills
			target = MarkDirector.KILL_TARGET
			total_pool = MarkDirector.KILL_TARGET  # Mark hunt не имеет отдельного "TOTAL" — KILL_TARGET и есть pool
			metric_label = "Метки"
		else:
			progress = SphereDirector.captured_count
			target = SphereDirector.CAPTURE_TARGET
			total_pool = SphereDirector.TOTAL_SPHERES
			metric_label = "Сферы"
		# Failure mode discriminator: alive_time >= RUN_DURATION → объект fail
		# (игрок дожил, но objective не выполнен). Иначе — drain death.
		var objective_fail: bool = alive_time >= RunLoop.RUN_DURATION and progress < target
		if objective_fail:
			header_label.text = OBJECTIVE_FAIL_HEADER
			header_label.modulate = Color(0.95, 0.65, 0.30, 1)  # warning amber
		else:
			header_label.text = _pick_drain_header(alive_time)
			header_label.modulate = Color(0.95, 0.30, 0.25, 1)  # drain red
		# Objective progress line: green tint если objective met (almost-win), иначе cyan/magenta.
		sphere_label.visible = true
		if progress >= target:
			sphere_label.text = "%s: %d / %d (задача выполнена)" % [metric_label, progress, total_pool]
			sphere_label.modulate = Color(0.30, 0.85, 0.40, 1)
		else:
			sphere_label.text = "%s: %d / %d" % [metric_label, progress, target]
			sphere_label.modulate = Color(0.478, 0.906, 0.906, 1)
	score_label.text = "Счёт: %d" % ScoreState.final_score
	best_label.text = "Рекорд: %d" % ScoreState.best_score
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


func _pick_drain_header(alive_time: float) -> String:
	# Fast-death override (alive_time < 30s) — fixed self-irony variant. Иначе
	# weighted RNG pick (per spec): 65% default / 25% variant-2 / 10% variant-3.
	# Default catches +5% bias по сравнению со spec'ом 60% — сознательно, чтобы
	# verdict-line чаще была канонической и игрок узнавал её.
	if alive_time < DRAIN_FAST_DEATH_THRESHOLD:
		return DRAIN_HEADER_FAST
	var roll: int = randi() % 100
	if roll < 65:
		return DRAIN_HEADER_DEFAULT
	elif roll < 90:  # 65..89 = 25%
		return DRAIN_HEADER_VARIANT_2
	return DRAIN_HEADER_VARIANT_3  # 90..99 = 10%


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
