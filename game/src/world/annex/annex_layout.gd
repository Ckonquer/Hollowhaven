extends RefCounted
## Authored layout of Tobin's Lost Shift (area "tobin_annex", docs/CHAPTER_TWO_SPEC.md §1, §7.2; MP §7):
## three compact spaces behind a side door off the Hollow Mine mouth. Pure data + static helpers, shared by
## the area script, the room builder and the tests (like src/world/below/below_layout.gd).
## Coordinates in metres: x = east, z = south, y = up; north (-z) leads deeper.
##   ta_entry   - Tobin's lamp room: low, square, timbered. SAFE. The side door (exit) is in its south wall.
##   ta_lockers - the shift lockers: a long, tall hall lined with lockers; the Hollow Drudge's teaching
##                encounter; the lantern niche (checkpoint "ta_lantern", always a safe spot) off its west side.
##   ta_sump    - a stair down to the sluice sump: wide, wet, low-lying; Tobin's service note by the sluice,
##                echo crystals, the scrawled lantern mark and the shortcut hatch up to the mine mouth.
## Rooms are axis-aligned boxes (keys like below_layout.gd, so below_builder.gd builds them unchanged):
## "open" side n = z0 wall, s = z1, w = x0, e = x1; each opening is [from, to, height] along the wall.
## "gap" rooms are the one-metre doorways through a wall (floor only; the neighbour's wall pieces flank
## them). "custom" rooms are built by hand (the stair). Openings are >= 1.6 m wide and >= 2.4 m tall.

const AREA_ID := "tobin_annex"
const ZONES := ["ta_entry", "ta_lockers", "ta_sump"]

const ROOMS := {
	"entry": {"space": "entry", "zone": "ta_entry", "x0": -4.0, "x1": 4.0, "z0": -7.0, "z1": 0.0, "y": 0.0, "h": 3.0,
		"open": {"n": "all"}},
	"entry_gap": {"space": "entry", "zone": "ta_entry", "x0": -1.1, "x1": 1.1, "z0": -8.0, "z1": -7.0, "y": 0.0, "h": 2.6, "gap": true},
	"lockers": {"space": "lockers", "zone": "ta_lockers", "x0": -4.5, "x1": 4.5, "z0": -23.0, "z1": -8.0, "y": 0.0, "h": 4.8,
		"open": {"s": [[-1.1, 1.1, 2.6]], "w": [[-20.5, -17.0, 2.6]], "n": [[-1.3, 1.3, 2.8]]}},
	"niche_gap": {"space": "lockers", "zone": "ta_lockers", "x0": -5.5, "x1": -4.5, "z0": -20.5, "z1": -17.0, "y": 0.0, "h": 2.6, "gap": true},
	"niche": {"space": "lockers", "zone": "ta_lockers", "x0": -8.0, "x1": -5.5, "z0": -20.5, "z1": -17.0, "y": 0.0, "h": 2.8,
		"open": {"e": "all"}},
	"stair_top": {"space": "stair", "zone": "ta_sump", "x0": -1.3, "x1": 1.3, "z0": -24.0, "z1": -23.0, "y": 0.0, "h": 2.8, "gap": true},
	# The stair floor slopes from y 0 (z -25) down to y -2 (z -30); flat landings at both ends.
	"stair": {"space": "stair", "zone": "ta_sump", "x0": -1.3, "x1": 1.3, "z0": -31.0, "z1": -24.0, "y": -2.0, "h": 4.8,
		"ylo": -3.0, "yhi": 3.3, "custom": true},
	"stair_foot": {"space": "sump", "zone": "ta_sump", "x0": -1.3, "x1": 1.3, "z0": -32.0, "z1": -31.0, "y": -2.0, "h": 4.8, "gap": true},
	"sump": {"space": "sump", "zone": "ta_sump", "x0": -6.0, "x1": 7.0, "z0": -42.0, "z1": -32.0, "y": -2.0, "h": 5.0,
		"open": {"s": [[-1.3, 1.3, 4.8]]}},
}

## The three designed spaces in walking order (the stair belongs to the sump's zone).
const SPACES := ["entry", "lockers", "stair", "sump"]

const STAIR_TOP_Z := -25.0          # floor y 0 north of the lockers down to here...
const STAIR_BOTTOM_Z := -30.0       # ...then a ramp (visual steps) down to y -2 here
const STAIR_DROP := 2.0

## The sluice channel: shallow running water across the sump (walkable, footsteps splash).
const CHANNEL := {"x0": -6.0, "x1": 7.0, "z0": -38.5, "z1": -36.0, "depth": 0.08}
## The shortcut hatch: a square hole in the sump ceiling above a ladder on the north wall.
const HATCH_HOLE := {"x0": 4.3, "x1": 5.7, "z0": -42.0, "z1": -40.6}
const SHAFT_HEIGHT := 2.6            # visual shaft above the hole, capped by the hatch lid

## Spawn points: position (floor) + facing yaw in degrees (0 = facing north/-z, 90 = west, -90 = east, 180 = south).
const SPAWNS := {
	"annex_entry": {"pos": Vector3(0.0, 0.0, -2.8), "yaw": 0.0},
	"annex_lantern": {"pos": Vector3(-5.9, 0.0, -18.75), "yaw": -90.0},
	"annex_hatch_below": {"pos": Vector3(4.2, -2.0, -39.4), "yaw": 180.0},
}
const SPAWN_LIFT := 0.08

## Safe places: the whole lamp room, and the lantern niche (always, lit or not: it is where Krystal wakes).
## The niche circle ends at the hall's wall line (x -4.5): it never reaches into the Drudge's hall, so
## Krystal cannot stand "safe" (ignored by the Drudge) while striking it on the open floor.
const SAFE_ROOMS := ["entry", "entry_gap"]
const SAFE_SPOTS := [{"center": Vector3(-6.4, 0.0, -18.75), "radius": 1.9}]
const SAFE_DY := 3.0

## The checkpoint lantern (src/world/below/checkpoint_lantern.gd; flag "cp_lit_ta_lantern").
const CHECKPOINT := {"id": "ta_lantern", "pos": Vector3(-7.2, 0.0, -18.75), "spawn": "annex_lantern", "zone": "ta_lockers"}

## The Hollow Drudge's teaching encounter (enemy id from data/enemies.gd, spawned through EnemySpawner).
const DRUDGE := {"spawner_id": "ta_sp_drudge", "enemy": "hollow_drudge", "pos": Vector3(0.6, 0.0, -16.0), "count": 1,
	"radius": 1.0, "respawn_minutes": -1.0, "flag": "c1x_drudge_defeated"}

## Echo materials (data/sources.gd NODES "crystal": tobin_annex / ta_sump, min_count 2). Stable ids.
const RESOURCES := [
	{"id": "ta_crystal_1", "kind": "crystal", "pos": Vector3(-4.7, -2.0, -34.2)},
	{"id": "ta_crystal_2", "kind": "crystal", "pos": Vector3(-4.8, -2.0, -40.6)},
	{"id": "ta_crystal_3", "kind": "crystal", "pos": Vector3(-2.9, -2.0, -40.9)},
]

## Authored spots.
const POINTS := {
	"door": Vector3(0.0, 0.0, 0.0),                 # the side door, in the entry's south wall (faces north)
	"shift_board": Vector3(-3.94, 1.55, -3.6),      # chalk board on the entry's west wall (faces east)
	"letter": Vector3(3.9, 0.0, -19.6),             # Tobin's locker, east wall of the lockers (faces west)
	"note": Vector3(6.05, -2.0, -34.6),             # service note on a ledge by the sluice
	"dropped_lamp": Vector3(5.35, -2.0, -35.25),    # the lantern Tobin dropped (becomes Krystal's Miner's Lamp)
	"sluice": Vector3(7.0, -2.0, -37.25),           # sluice gate in the east wall, where the channel enters
	"mark": Vector3(-0.8, -0.3, -41.97),            # scrawled lantern mark on the north wall (faces south)
	"ladder": Vector3(5.0, -2.0, -41.72),           # foot of the hatch ladder
	"echo": Vector3(-5.6, -1.2, -37.25),            # where the passage "answers" (dark west end of the channel)
}

## Floor points from the side door to the hatch (walkability tests) and the side trips.
const CRITICAL_PATH := [
	Vector3(0.0, 0.0, -2.8), Vector3(0.0, 0.0, -6.5), Vector3(0.0, 0.0, -7.5), Vector3(0.0, 0.0, -9.0),
	Vector3(-2.0, 0.0, -13.0), Vector3(-1.5, 0.0, -20.0), Vector3(0.0, 0.0, -22.5), Vector3(0.0, 0.0, -24.5),
	Vector3(0.0, -2.0, -30.5), Vector3(0.0, -2.0, -32.5), Vector3(1.5, -2.0, -34.5), Vector3(3.2, -2.0, -37.0),
	Vector3(4.2, -2.0, -39.4),
]
const SIDE_PATHS := [
	[Vector3(-2.0, 0.0, -18.75), Vector3(-4.2, 0.0, -18.75), Vector3(-5.9, 0.0, -18.75)],   # lantern niche
	[Vector3(1.5, 0.0, -19.6), Vector3(3.0, 0.0, -19.6)],                                 # Tobin's locker
	[Vector3(1.5, -2.0, -34.5), Vector3(4.6, -2.0, -34.6)],                               # the note by the sluice
	[Vector3(1.5, -2.0, -34.5), Vector3(-3.1, -2.0, -34.6), Vector3(-2.3, -2.0, -39.5)],   # crystals
	[Vector3(0.0, -2.0, -37.0), Vector3(-0.8, -2.0, -40.9)],                              # the mark
	[Vector3(0.0, 0.0, -2.8), Vector3(-3.0, 0.0, -3.6)],                                  # the shift board
]


## Spawn transform: forward (-Z) rotated by yaw, lifted a little like the surface spawns.
static func spawn_xform(id: String) -> Transform3D:
	var s: Dictionary = SPAWNS.get(id, SPAWNS["annex_entry"])
	var p: Vector3 = s["pos"]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"]))), p + Vector3(0.0, SPAWN_LIFT, 0.0))


## Room vertical range used for detection.
static func room_y_range(r: Dictionary) -> Vector2:
	var y: float = float(r["y"])
	return Vector2(float(r.get("ylo", y - 1.0)), float(r.get("yhi", y + float(r["h"]) + 0.5)))


## Room id containing a position ("" if none).
static func room_at(pos: Vector3) -> String:
	for id in ROOMS:
		var r: Dictionary = ROOMS[id]
		var yr := room_y_range(r)
		if pos.y < yr.x or pos.y > yr.y:
			continue
		if pos.x >= float(r["x0"]) and pos.x <= float(r["x1"]) and pos.z >= float(r["z0"]) and pos.z <= float(r["z1"]):
			return String(id)
	return ""


## Nearest room by horizontal distance to its box (height counts double), for points just outside every room.
static func nearest_room(pos: Vector3) -> String:
	var best := ""
	var best_d := INF
	for id in ROOMS:
		var r: Dictionary = ROOMS[id]
		var yr := room_y_range(r)
		var dy: float = 0.0
		if pos.y < yr.x:
			dy = yr.x - pos.y
		elif pos.y > yr.y:
			dy = pos.y - yr.y
		var dx: float = maxf(maxf(float(r["x0"]) - pos.x, 0.0), pos.x - float(r["x1"]))
		var dz: float = maxf(maxf(float(r["z0"]) - pos.z, 0.0), pos.z - float(r["z1"]))
		var d := Vector3(dx, dy * 2.0, dz).length()
		if d < best_d:
			best_d = d
			best = String(id)
	return best


static func zone_of_room(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("zone", ""))


static func space_of(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("space", ""))


## Zone at a position (never "" inside or near the annex).
static func zone_at(pos: Vector3) -> String:
	var r := room_at(pos)
	if r == "":
		r = nearest_room(pos)
	return zone_of_room(r)


## Walkable floor height at (x, z): the stair slope is interpolated, other rooms are flat. The levels never
## overlap on the XZ plane, so the answer is unique.
static func floor_at(x: float, z: float) -> float:
	var r := stair_floor(x, z)
	if not is_nan(r):
		return r
	for id in ROOMS:
		var rr: Dictionary = ROOMS[id]
		if x >= float(rr["x0"]) and x <= float(rr["x1"]) and z >= float(rr["z0"]) and z <= float(rr["z1"]):
			return float(rr["y"])
	var n: Dictionary = ROOMS[nearest_room(Vector3(x, 0.0, z))]
	return float(n["y"])


## Stair floor height at (x, z), or NAN outside the stair box.
static func stair_floor(x: float, z: float) -> float:
	var r: Dictionary = ROOMS["stair"]
	if x < float(r["x0"]) or x > float(r["x1"]) or z < float(r["z0"]) or z > float(r["z1"]):
		return NAN
	if z >= STAIR_TOP_Z:
		return 0.0
	if z <= STAIR_BOTTOM_Z:
		return -STAIR_DROP
	return -STAIR_DROP * (STAIR_TOP_Z - z) / (STAIR_TOP_Z - STAIR_BOTTOM_Z)


## True where Krystal is safe: the lamp room, or the lantern niche (height-checked).
static func is_safe_point(pos: Vector3) -> bool:
	if SAFE_ROOMS.has(room_at(pos)):
		return true
	for s in SAFE_SPOTS:
		var c: Vector3 = s["center"]
		if absf(pos.y - c.y) < SAFE_DY and Vector2(pos.x - c.x, pos.z - c.z).length() <= float(s["radius"]):
			return true
	return false


## Centre (floor) of a room box.
static func room_center(room_id: String) -> Vector3:
	var r: Dictionary = ROOMS[room_id]
	return Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, float(r["y"]), (float(r["z0"]) + float(r["z1"])) * 0.5)
