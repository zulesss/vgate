class_name PlayerSpawn extends RefCounted

# Per-arena player spawn helper. Активная арена кладёт Marker3D в группу
# "player_start" — мы находим первого, телепортируем Player + сбрасываем
# velocity + (если есть property `rotation_target`) пишем yaw, чтобы
# mouse-look не отыграл назад в дефолтную ориентацию.
#
# Fallback (нет PlayerStart в арене) — Vector3(0, 1, 0), rotation 0.
# Существующие arena_a/arena_b делали именно это — backwards-compat сохранён.
#
# Контракт callsite'а:
#   - Player в группе/ноде доступен Node3D'ом (для CharacterBody3D — даун-каст
#     внутри для velocity reset)
#   - SceneTree должен иметь хотя бы одну активную арену
# Два callsite'а: Main._ready() (initial spawn) и RunLoop._on_run_started()
# (restart loop). Логика общая — единая точка правды.

const FALLBACK_POSITION := Vector3(0, 1, 0)


static func teleport_to_start(player: Node, tree: SceneTree) -> void:
	if player == null or not (player is Node3D):
		return
	var target_pos: Vector3 = FALLBACK_POSITION
	var target_yaw: float = 0.0
	var has_yaw: bool = false
	var markers: Array = tree.get_nodes_in_group(&"player_start")
	if not markers.is_empty():
		var marker := markers[0] as Node3D
		if marker != null:
			target_pos = marker.global_position
			target_yaw = marker.global_rotation.y
			has_yaw = true
	var p3d := player as Node3D
	p3d.global_position = target_pos
	if has_yaw:
		p3d.rotation.y = target_yaw
		# Player.gd lerps rotation.y → rotation_target.y каждый кадр, так что без
		# обновления rotation_target snap отыграется обратно в стартовое 0.
		# Duck-type: проверяем существование property через `in` оператор.
		if "rotation_target" in player:
			var rt: Vector3 = player.rotation_target
			rt.y = target_yaw
			player.rotation_target = rt
	if player is CharacterBody3D:
		(player as CharacterBody3D).velocity = Vector3.ZERO
