extends StaticBody3D
## Terrain collider (layer 1) with meta "surface" for footsteps. The terrain is ONE heightmap collider,
## so its meta is kept equal to the surface under the player ("grass" | "stone" | "water"), refreshed a
## few times per second: consumers that read collider.get_meta("surface") (the player's footsteps) get
## the right answer. Anyone else can ask get_surface_at(world_pos) for an exact point query.

const REFRESH := 0.12

var area: Node = null
var _t := 0.0


func _ready() -> void:
	if not has_meta("surface"):
		set_meta("surface", "grass")


func get_surface_at(pos: Vector3) -> String:
	if area != null and is_instance_valid(area) and area.has_method("surface_at"):
		return area.surface_at(pos)
	return String(get_meta("surface", "grass"))


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < REFRESH:
		return
	_t = 0.0
	var p: Node = Game.player
	if p == null or not is_instance_valid(p) or not (p is Node3D):
		return
	var s := get_surface_at((p as Node3D).global_position)
	if String(get_meta("surface", "")) != s:
		set_meta("surface", s)
