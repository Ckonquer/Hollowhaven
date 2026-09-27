extends Node3D
## Base class for playable areas (surface, below). Area scripts extend this file:
##   extends "res://src/world/area_base.gd"
## Responsibilities: build the level in _ready(), register spawn points, answer zone/safety queries.
## Game adds the player, companions and UI after the scene is ready.

@export var area_id: String = ""

var spawns: Dictionary = {}          # spawn id -> Transform3D
var zones: Array = []                # [{id, center: Vector3, radius: float, safe: bool}] simple spherical zones


## Registers (or replaces) a named spawn point.
func register_spawn(spawn_id: String, xform: Transform3D) -> void:
	spawns[spawn_id] = xform


## Returns the spawn transform, falling back to the first registered spawn (never fails).
func get_spawn(spawn_id: String) -> Transform3D:
	if spawns.has(spawn_id):
		return spawns[spawn_id]
	for fallback in ["haven_respawn", "haven_start", "mine_entry"]:
		if spawns.has(fallback):
			push_warning("Area %s: unknown spawn '%s', using %s" % [area_id, spawn_id, fallback])
			return spawns[fallback]
	if not spawns.is_empty():
		return spawns.values()[0]
	return Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))


func add_zone(zone_id: String, center: Vector3, radius: float, safe: bool = false) -> void:
	zones.append({"id": zone_id, "center": center, "radius": radius, "safe": safe})


## Zone id at a position ("" if none). Smallest containing zone wins. Override for custom shapes.
func get_zone_at(pos: Vector3) -> String:
	var best := ""
	var best_r := INF
	for z in zones:
		var c: Vector3 = z["center"]
		var d := Vector2(pos.x - c.x, pos.z - c.z).length()
		if d <= float(z["radius"]) and float(z["radius"]) < best_r:
			best = z["id"]
			best_r = z["radius"]
	return best


func is_safe_zone(pos: Vector3) -> bool:
	for z in zones:
		if z["safe"]:
			var c: Vector3 = z["center"]
			if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(z["radius"]):
				return true
	return false


## Validates a saved position: returns a corrected Vector3 on solid ground, or null if unsafe.
func validate_position(pos: Vector3) -> Variant:
	if not is_inside_tree():
		return null
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 8.0)
	q.collision_mask = 1 | 32     # world + structures
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var p: Vector3 = hit["position"] + Vector3.UP * 0.1
	# Make sure we're not inside geometry: a short upward ray from the ground must be clear.
	var q2 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.UP * 1.8)
	q2.collision_mask = 1 | 32
	if not space.intersect_ray(q2).is_empty():
		return null
	return p


## Called by Game after the player has been placed. Override in area scripts.
func on_player_spawned(_player: Node3D) -> void:
	pass
