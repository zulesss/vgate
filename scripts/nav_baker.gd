class_name NavBaker extends Node

# M3a Pkg A: bake NavigationMesh on scene load (runtime, headless-safe).
# Editor bake'ить нельзя (имп-агент работает без editor); NavigationServer3D.
# bake_from_source_geometry_data — async, но NavigationRegion3D.bake_navigation_mesh()
# делает sync bake под капотом и работает в headless. Зовётся один раз в _ready.
#
# Source geometry: STATIC_COLLIDERS + ROOT_NODE_CHILDREN. Floor + Walls + Cover —
# CSGBox3D с use_collision=true, попадают в источник. CharacterBody3D'и (Player,
# enemies) исключаются физически — они placed in main scene но collision_mask их
# не лезет в navigation_mesh (filter по type STATIC).

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
	# Sync bake (headless-safe). Async вариант через NavigationServer3D — не нужен
	# на 40×40 арене, bake заканчивается за <100мс.
	region.bake_navigation_mesh(false)
	var nm := region.navigation_mesh
	print("[NAV] bake done — polygons=", nm.get_polygon_count(), " vertices=", nm.get_vertices().size())
