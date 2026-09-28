extends Node3D
## Root of the Ashbell Quarry district content (built by quarry_builder.gd under the Reach area, at the area
## origin, everything in area coordinates). Holds the references other code and tests use:
##   winch, lamp, arena, note           the interactive set pieces
##   nodes: {node_id: harvest node}     every renewable harvest node (hr_iron_*, hr_mooncrystal_*, ...)
##   spawners: {spawner_id: node}       hr_sp_quarry_warden (inside the arena), hr_sp_bellcaps
##   floor_y, shaped, build_ms          ground level, whether the terrain was shaped, build time
##   node_ids() -> Array, debug_state() -> Dictionary, debug_clear_warden() -> bool (debug builds only)

var winch: Node3D = null
var lamp: Node3D = null
var arena: Node3D = null
var note: Node3D = null
var nodes: Dictionary = {}
var spawners: Dictionary = {}
var floor_y: float = 0.0
var shaped: bool = false
var build_ms: float = 0.0


func _ready() -> void:
	add_to_group("reach_district")
	add_to_group("ashbell_quarry")


func node_ids() -> Array:
	var ids: Array = nodes.keys()
	ids.sort()
	return ids


## Debug / test hook: clears the Warden encounter exactly like a defeat (no-op in release builds).
func debug_clear_warden() -> bool:
	if arena == null or not is_instance_valid(arena):
		return false
	return bool(arena.debug_clear_encounter())


func debug_state() -> Dictionary:
	return {
		"shaped": shaped, "floor_y": floor_y, "build_ms": build_ms, "nodes": nodes.size(),
		"winch_repaired": winch != null and bool(winch.is_repaired()),
		"gangway": winch != null and bool(winch.gangway_enabled()),
		"lamp": lamp.state() if lamp != null else "",
		"warden_cleared": arena != null and bool(arena.is_cleared()),
		"pillars_intact": arena.intact_pillars() if arena != null else 0,
	}
