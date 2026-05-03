class_name WinScreen extends CanvasLayer

# M9 conquest: arena complete screen (parallel к DeathScreen, но show'ится на
# Events.run_won а не player_died). Layout зеркальный — header "АРЕНА ПРОЙДЕНА",
# breakdown (kills, avg cap, time alive, score), best line, ДАЛЕЕ кнопка.
#
# M13 sequential campaign: кнопка repurposed:
#   - intermediate arenas (Плац / Камера) → label "ДАЛЕЕ", click →
#     LevelSequence.advance() + change_scene_to_file(MAIN_SCENE). main.gd._enter_tree
#     подхватит новый current_path() и проинстансит next arena.
#   - final arena (Собор) → header override "ВСЕ ПРИГОВОРЫ ИСПОЛНЕНЫ", label
#     "ГЛАВНОЕ МЕНЮ", click → LevelSequence.reset() + change_scene_to_file(MAIN_MENU_SCENE).
#
# Auto-advance timer убран (post-M12 polish): игрок ОБЯЗАН нажать кнопку, нет
# implicit advance'а через timeout — респект к pacing'у (некоторые хотят прочитать
# breakdown до конца, некоторые — выйти в туалет / посмотреть на счёт). Без
# гонки timer-vs-click и _advanced guard'а тоже не нужен.
#
# Timing проще чем у death_screen — игрок ещё на ногах, без death animation.
# 0.0 — show + freeze input
# 0.0–0.5 — fade-in белого тонкого overlay'а (subtle, не black like death)
# 0.5–1.0 — anti-accidental delay (палец мог быть на shoot в 120-й секунде)
# 1.0+ — кнопка активна, ждём click

const FADE_IN_SECONDS := 0.5
const ANTI_ACCIDENTAL_DELAY := 0.5
const MAIN_SCENE := "res://scenes/main.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const FINAL_HEADER := "ВСЕ ПРИГОВОРЫ ИСПОЛНЕНЫ"
const NEXT_BUTTON_LABEL := "ДАЛЕЕ"
const FINAL_BUTTON_LABEL := "ГЛАВНОЕ МЕНЮ"

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

# Запоминаем is_final на момент run_won — чтобы advance() сам не сместил state
# между проверкой и handler'ом (advance() меняет current_index → is_final()
# становится true для уже-финального arena, перепутав button label).
var _is_final_arena: bool = false


func _ready() -> void:
	visible = false
	bg.modulate.a = 0.0
	box.visible = false
	restart_btn.disabled = true
	restart_btn.pressed.connect(_on_button)
	Events.run_won.connect(_on_run_won)


func _on_run_won() -> void:
	visible = true
	# UI mode: симметрично DeathScreen — отпускаем cursor чтобы игрок мог нажать
	# ДАЛЕЕ. RunLoop._won гард + VelocityGate.is_alive продолжают блокировать
	# spawn/score/AI пока handler не сработает.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Snapshot is_final ДО любых advance() в handler'е (defensive — если из-за
	# race connection эмит произойдёт после внешнего advance'а).
	_is_final_arena = LevelSequence.is_final()

	# Persist campaign progress — current_index идентифицирует пройденную арену.
	# mark_completed идемпотентен: повторные win'ы той же арены no-op (highest_unlocked
	# advance'ит только при new_unlocked > current). Делаем ДО button click — игрок
	# может exit'нуть в menu через ГЛАВНОЕ МЕНЮ кнопку и progress всё равно сохраняется.
	CampaignProgress.mark_completed(LevelSequence.current_index)

	# Journey detection — single source of truth с RunLoop / SpawnController через
	# group check. На journey арене header — clear-and-escape победа, time показываем
	# с deadline (now /120 актуально — есть timer-fail), sphere row скрываем.
	var is_journey: bool = not get_tree().get_nodes_in_group(&"objective_journey").is_empty()
	var is_cathedral: bool = not get_tree().get_nodes_in_group(&"objective_cathedral").is_empty()
	# Final-arena header override превалирует над per-arena variant — финал кампании
	# доминирует семантически "вы прошли всё".
	if _is_final_arena:
		header.text = FINAL_HEADER
	elif is_cathedral:
		header.text = "СОБОР ОЧИЩЕН"
	elif is_journey:
		header.text = "ЗОНА ЗАЧИЩЕНА"
	else:
		header.text = "АРЕНА ПРОЙДЕНА"
	# Button label по статусу — "ДАЛЕЕ" для intermediate / "ГЛАВНОЕ МЕНЮ" для финала.
	if _is_final_arena:
		restart_btn.text = FINAL_BUTTON_LABEL
	else:
		restart_btn.text = NEXT_BUTTON_LABEL

	# Заполняем breakdown текущими value'ами из ScoreState (final_score фризится
	# в _on_run_won самого ScoreState'а — порядок connect'а не критичен, оба
	# подписаны до эмита).
	kills_label.text = "Убийства: %d" % ScoreState.kills
	var avg_cap: float = VelocityGate.get_avg_cap_over_run()
	avg_cap_label.text = "Средний КАП: %d" % int(round(avg_cap))
	var t_alive: float = VelocityGate.get_alive_time()
	if is_cathedral:
		# Cathedral: no deadline. Time count-up без /120.
		time_label.text = "Время: %.1f" % t_alive
		sphere_label.visible = true
		sphere_label.text = "Алтари: %d / %d" % [AltarDirector.captured_count, AltarDirector.ALTAR_COUNT]
	elif is_journey:
		# Journey clear-and-escape: deadline активен (120s), показываем как
		# обычная арена — Time: t / 120. Sphere row скрыт, kills уже в KillsLabel'е.
		time_label.text = "Время: %.1f / 120" % t_alive
		sphere_label.visible = false
	else:
		time_label.text = "Время: %.1f / 120" % t_alive
		sphere_label.visible = true
		# Active objective metric: sphere counter vs marked-kills counter. Один из
		# director'ов active (set'ится в run_started через group check'у).
		if MarkDirector._active:
			sphere_label.text = "Метки: %d / %d" % [MarkDirector.kills, MarkDirector.KILL_TARGET]
		else:
			sphere_label.text = "Сферы: %d / %d" % [SphereDirector.captured_count, SphereDirector.CAPTURE_TARGET]
	score_label.text = "СЧЁТ: %d" % ScoreState.final_score
	best_label.text = "РЕКОРД: %d" % ScoreState.best_score

	box.visible = true
	# Subtle fade-in: заметный, но не закрывает арену полностью (игрок видит
	# что пережил волну).
	var t1 := create_tween()
	t1.tween_property(bg, "modulate:a", 1.0, FADE_IN_SECONDS)
	await t1.finished

	await get_tree().create_timer(ANTI_ACCIDENTAL_DELAY).timeout
	restart_btn.disabled = false
	restart_btn.grab_focus()


func _on_button() -> void:
	_advance_now()


func _advance_now() -> void:
	visible = false
	box.visible = false
	bg.modulate.a = 0.0
	restart_btn.disabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _is_final_arena:
		# Финал кампании: возвращаем в main menu. Reset() гарантирует следующий
		# START снова с Плаца (main_menu._on_start тоже делает reset(), это
		# defense-in-depth).
		LevelSequence.reset()
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	else:
		# Intermediate: advance + перезагружаем main scene. main.gd._enter_tree
		# подхватит новый LevelSequence.current_path() и проинстансит next arena.
		# Не используем Events.run_restart_requested — тот in-place reset'ит ту же
		# арену; здесь нужен полный scene swap чтобы Events/VelocityGate/директора
		# поймали свежие run_started signals на reload'е main.tscn.
		LevelSequence.advance()
		get_tree().change_scene_to_file(MAIN_SCENE)
