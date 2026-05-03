class_name NavBaker extends Node

# M3a Pkg A: bake NavigationMesh on scene load (runtime, headless-safe).
# Editor bake'ить нельзя (имп-агент работает без editor); NavigationServer3D.
# bake_from_source_geometry_data — async, но NavigationRegion3D.bake_navigation_mesh()
# делает sync bake под капотом и работает в headless. Зовётся один раз в _ready.
#
# Source geometry: parsed_geometry_type=MESH_INSTANCES + GROUPS_WITH_CHILDREN.
# Walls/cover — CSGBox3D с explicit MeshInstance3D mirror children (csg-bug-fix
# 357c9d1). CharacterBody3D'и не парсятся (нет mesh-mirror).
#
# Group "navmesh_excluded" — opt-out для visible-but-non-blocking geometry
# (e.g. cathedral altar beams: визуально cylinder, gameplay-wise проходим).
#
# Failed attempt #1 (07b7f88): visible=false toggle на excluded nodes. Не работает
# для CSGShape3D — Godot 4 nav source parser в MESH_INSTANCES mode дёргает CSG
# generated mesh напрямую, минуя visibility check (visibility honoured только
# для MeshInstance3D path). Реальный fix: temporarily remove_child() beam'ов
# на время bake, потом add_child() обратно — node не в tree = parser его не видит.

const EXCLUDE_GROUP := &"navmesh_excluded"

@export var region: NavigationRegion3D


func _ready() -> void:
	if region == null:
		push_warning("NavBaker: region не задан, skipping bake")
		return
	if region.navigation_mesh == null:
		push_warning("NavBaker: navigation_mesh не назначен в region'е")
		return
	# Defer bake one physics_frame: hedge against MeshInstance3D children not yet
	# being registered as parse targets on parent's _ready. Cheap insurance.
	await get_tree().physics_frame
	# Detach excluded nodes from tree: parser walks scene-tree descendants of the
	# nav-source group root, поэтому nodes вне tree не парсятся (works для CSG/Mesh
	# единообразно, без зависимости от visibility-honoured кодпасов).
	var detached: Array[Dictionary] = []
	for n in get_tree().get_nodes_in_group(EXCLUDE_GROUP):
		var n3d := n as Node3D
		if n3d == null:
			continue
		var parent := n3d.get_parent()
		if parent == null:
			continue
		var idx := n3d.get_index()
		parent.remove_child(n3d)
		detached.append({"node": n3d, "parent": parent, "index": idx})
	# Sync bake (headless-safe). Async вариант через NavigationServer3D — не нужен
	# на 40×40 арене, bake заканчивается за <100мс.
	region.bake_navigation_mesh(false)
	# Reattach в исходных индексах (restore display order).
	for d in detached:
		var p: Node = d.parent
		var n3d: Node3D = d.node
		p.add_child(n3d)
		p.move_child(n3d, d.index)
