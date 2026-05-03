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
# CSGShape3D root contributes mesh to nav baker даже при use_collision=false
# (Godot 4.4+ parses CSG roots in MESH_INSTANCES mode), поэтому нужно прятать
# через visible=false на время bake.

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
	# Hide nav-excluded nodes: CSG/MeshInstance with visible=false не парсятся
	# baker'ом. Restore visibility сразу после bake — навмеш кэширован.
	var hidden: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group(EXCLUDE_GROUP):
		var n3d := n as Node3D
		if n3d != null and n3d.visible:
			n3d.visible = false
			hidden.append(n3d)
	# Sync bake (headless-safe). Async вариант через NavigationServer3D — не нужен
	# на 40×40 арене, bake заканчивается за <100мс.
	region.bake_navigation_mesh(false)
	for n3d in hidden:
		n3d.visible = true
