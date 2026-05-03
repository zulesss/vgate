class_name LevelSequenceNode extends Node

# Sequential campaign loader (Плац → Камера → Собор).
#
# Лежит autoload'ом — переживает change_scene_to_file (main → win → main → ...).
# Win screen вызывает advance() и затем change_scene_to_file("res://scenes/main.tscn"):
# main.gd._enter_tree() читает current_path() и подгружает соответствующую arena
# scene в себя. Arena scenes — subtrees (Node3D root + CSG + spawn-points), они
# не self-contained — их нельзя выставить как root scene напрямую, поэтому
# IntroState.target_scene остаётся "res://scenes/main.tscn".
#
# Death-restart loop arena НЕ переключает (RunLoop._on_restart in-place
# reset → reinstantiate_arena), так что current_index не трогается на смерти.
#
# Reset to 0 на:
#   - main_menu START (новая кампания)
#   - pause → MAIN MENU (выход в меню)
#   - финальный собор пройден (на main menu возвращается готовая кампания)

const ARENA_PATHS: Array[String] = [
	"res://scenes/arenas/arena_b_plac.tscn",
	"res://scenes/arenas/arena_a_camera.tscn",
	"res://scenes/arenas/arena_c_cathedral.tscn",
]

var current_index: int = 0


func current_path() -> String:
	# Clamp защита от out-of-bounds (теоретически advance после final без reset
	# мог бы убежать; clamp гарантирует non-empty path для main.gd._enter_tree).
	var i: int = clamp(current_index, 0, ARENA_PATHS.size() - 1)
	return ARENA_PATHS[i]


func next_path() -> String:
	# Возвращает path следующей арены или "" если уже на финале.
	# Win screen использует для preload'а и для discriminator'а финал/не-финал.
	var nxt: int = current_index + 1
	if nxt >= ARENA_PATHS.size():
		return ""
	return ARENA_PATHS[nxt]


func is_final() -> bool:
	return current_index >= ARENA_PATHS.size() - 1


func advance() -> void:
	# Идемпотентно clamp'нем — если игрок жмёт ДАЛЕЕ дважды (не должен — guard
	# во win_screen, но defense-in-depth), не уйдём за пределы массива.
	current_index = clamp(current_index + 1, 0, ARENA_PATHS.size() - 1)


func reset() -> void:
	current_index = 0
