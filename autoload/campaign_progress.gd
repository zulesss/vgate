class_name CampaignProgressNode extends Node

# M13 campaign progress persistence — tracks highest unlocked arena index.
#
# Index map (mirrors LevelSequence.ARENA_PATHS order):
#   0 — Plac
#   1 — Камера
#   2 — Cathedral
#   3+ — все арены пройдены (final cathedral win)
#
# Save path делит file с ScoreState (high_scores секция) — сохраняем секцию
# отдельным namespace'ом [campaign]. ConfigFile.load() перед set_value()
# preservs cross-section data (high_scores не теряется на campaign save).
#
# API:
#   mark_completed(idx) — после win арены idx, advance highest_unlocked.
#   has_progress()      — есть ли что continue'ить.
#   all_completed()     — все 3 арены пройдены → next continue идёт в level_select.
#   reset()             — НОВАЯ ИГРА wipes campaign progress (но not high_scores).

const SAVE_PATH := "user://vgate_progress.cfg"
const SECTION := "campaign"
const KEY_HIGHEST_UNLOCKED := "highest_unlocked"
const ARENA_COUNT := 3  # Plac=0, Kamera=1, Cathedral=2, all_done=3+

var highest_unlocked: int = 0


func _ready() -> void:
	_load()


func mark_completed(arena_index: int) -> void:
	# Идемпотентно: повторные вызовы для уже-разблокированной арены ничего не
	# делают (multi-win одной арены OK — clamp + > guard).
	var new_unlocked: int = mini(arena_index + 1, ARENA_COUNT)
	if new_unlocked > highest_unlocked:
		highest_unlocked = new_unlocked
		_save()


func has_progress() -> bool:
	return highest_unlocked > 0


func all_completed() -> bool:
	return highest_unlocked >= ARENA_COUNT


func reset() -> void:
	highest_unlocked = 0
	_save()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		highest_unlocked = int(cf.get_value(SECTION, KEY_HIGHEST_UNLOCKED, 0))


func _save() -> void:
	var cf := ConfigFile.new()
	# Preserve other sections (high_scores) — read existing first, иначе save
	# wipes ScoreState's persisted best scores.
	cf.load(SAVE_PATH)  # OK если не существует — cf пустой
	cf.set_value(SECTION, KEY_HIGHEST_UNLOCKED, highest_unlocked)
	cf.save(SAVE_PATH)
