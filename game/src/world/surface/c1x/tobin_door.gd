extends RefCounted
## Surface end of Tobin's Lost Shift (docs/CHAPTER_TWO_SPEC.md §1, §7.1): run by src/world/surface/annexes.gd
## after every legacy step of surface_world._ready() (ANNEX_SCRIPTS slot "tobin_door.gd").
##   * Tobin's side door: a small timbered adit set into the mine cliff 6.8 m east of the legacy mine mouth
##     (between two of the legacy cliff-foot boulders, its front 2.2 m out on the apron) -> tobin_annex /
##     annex_entry. Jammed until the mine mouth's rubble is cleared (flag mine_opened). Spawn "annex_door"
##     2.2 m in front of it, facing out onto the apron.
##   * The surface end of the annex shortcut hatch: an iron hatch in the ground on the west side of the apron
##     (bolted from below until ta_hatch_open; then it leads down to annex_hatch_below). Spawn "annex_hatch"
##     beside it, facing the mine path.
## Everything is placed relative to the legacy mine entrance frame (SL.MINE_MOUTH / SL.MINE_FACING, the same
## transform landmarks.gd gives mine_entrance.gd), in its local axes: +x = mine_entrance local +X (east-south-
## east, the cart's side), +z = out onto the apron. Nothing legacy is moved or removed: the mine
## entrance, its rubble, mine_exit / mine_threshold, the terrain and the vegetation plan are untouched (the
## sites were chosen clear of every legacy node; tests/unit/test_annex_surface.gd proves it). No new zone.

const SL := preload("res://src/world/surface/surface_layout.gd")
const DoorScript := preload("res://src/world/annex/annex_door.gd")
const HatchScript := preload("res://src/world/annex/annex_hatch.gd")

const DOOR_SPAWN := "annex_door"
const HATCH_SPAWN := "annex_hatch"
## Sites in the mine entrance frame's local (x, z): see the header.
const DOOR_LOCAL := Vector2(6.8, 2.2)
const DOOR_SPAWN_LOCAL := Vector2(6.8, 4.4)
const HATCH_LOCAL := Vector2(-7.8, 3.6)
const HATCH_SPAWN_LOCAL := Vector2(-6.1, 4.9)
const DOOR_CLEAR_RADIUS := 2.6      # grass cleared in front of the door
const HATCH_CLEAR_RADIUS := 1.6
const SPAWN_LIFT := 0.08


## The mine entrance frame's origin on the XZ plane (landmarks.gd _build_mine).
static func mine_origin() -> Vector2:
	return SL.MINE_MOUTH + SL.MINE_FACING.normalized() * 0.4


## Yaw of the mine entrance frame (its local -Z points into the mountain).
static func mine_yaw() -> float:
	var f := SL.MINE_FACING.normalized()
	return atan2(f.x, f.y)


## Mine-frame local (x, z) -> world (x, z).
static func to_world(local: Vector2) -> Vector2:
	var f := SL.MINE_FACING.normalized()
	var yaw := mine_yaw()
	var right := Vector2(cos(yaw), -sin(yaw))
	return mine_origin() + right * local.x + f * local.y


static func door_site() -> Vector2:
	return to_world(DOOR_LOCAL)


static func hatch_site() -> Vector2:
	return to_world(HATCH_LOCAL)


## Called by Annexes.clear_grass BEFORE the grass is built (legacy ids are unaffected).
static func grass_clearings() -> Array:
	return [[door_site(), DOOR_CLEAR_RADIUS], [hatch_site(), HATCH_CLEAR_RADIUS]]


static func _height(area: Node, p: Vector2) -> float:
	if area.has_method("height_at"):
		return float(area.height_at(p.x, p.y))
	return 0.0


static func build(area: Node3D) -> void:
	if area == null:
		return
	var yaw := mine_yaw()
	# The side door (faces out onto the apron, like the mine mouth itself).
	var ds := door_site()
	var door: Node3D = DoorScript.new()
	door.setup({"variant": "surface", "target_area": "tobin_annex", "target_spawn": "annex_entry", "requires_flag": "mine_opened"})
	area.add_child(door)
	door.position = Vector3(ds.x, _height(area, ds) - 0.02, ds.y)
	door.rotation.y = yaw
	_register(area, DOOR_SPAWN, DOOR_SPAWN_LOCAL, yaw + PI)
	# The hatch top (the shortcut from the sump comes out here).
	var hs := hatch_site()
	var hatch: Node3D = HatchScript.new()
	hatch.setup({"variant": "ground", "target_area": "tobin_annex", "target_spawn": "annex_hatch_below"})
	area.add_child(hatch)
	hatch.position = Vector3(hs.x, _height(area, hs), hs.y)
	hatch.rotation.y = yaw
	_register(area, HATCH_SPAWN, HATCH_SPAWN_LOCAL, yaw + PI)


## Registers a spawn standing on the terrain at a mine-frame local point, facing `yaw` (forward = -Z).
static func _register(area: Node3D, spawn_id: String, local: Vector2, yaw: float) -> void:
	var p := to_world(local)
	var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, _height(area, p) + SPAWN_LIFT, p.y))
	area.register_spawn(spawn_id, xf)
	var markers := area.get_node_or_null("SpawnPoints")
	if markers != null:
		var m := Marker3D.new()
		m.name = "Spawn_" + spawn_id
		markers.add_child(m)
		m.transform = xf
