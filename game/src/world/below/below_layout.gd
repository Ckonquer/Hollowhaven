extends RefCounted
## Authored layout data for The Below (pure data: the area, the moments and the tests share it).
## Coordinates in metres: x = east, z = south, y = up. North (-z) leads deeper.
## Rooms are axis-aligned boxes (the Heartseed Chamber is a circle). A "space" is one of the 11
## designed spaces from GAME_SPEC.md; several rooms (passages, alcoves) can belong to one space.
## Wall openings: side "n" = the z0 wall, "s" = z1, "w" = x0, "e" = x1. Each opening is
## [from, to, height] along the wall (x for n/s, z for w/e). "all" = no wall on that side.

const ROOMS := {
	"landing": {"space": "landing", "zone": "mine", "x0": -7.0, "x1": 7.0, "z0": -6.0, "z1": 6.0, "y": 0.0, "h": 5.0,
		"open": {"n": [[-2.2, 2.2, 3.6]], "e": [[-1.7, 1.7, 3.2]], "s": [[-1.6, 1.6, 5.0]]}},
	"tunnel": {"space": "tunnel", "zone": "mine", "x0": -2.2, "x1": 2.2, "z0": -36.0, "z1": -6.0, "y": 0.0, "h": 3.6,
		"open": {"n": "all", "s": "all", "w": [[-21.5, -18.5, 3.0]]}},
	"side_passage": {"space": "tunnel", "zone": "mine", "x0": -11.0, "x1": -2.2, "z0": -21.5, "z1": -18.5, "y": 0.0, "h": 3.0,
		"open": {"e": "all"}},
	"gallery": {"space": "gallery", "zone": "mine", "x0": -8.0, "x1": 8.0, "z0": -50.0, "z1": -36.0, "y": 0.0, "h": 6.0,
		"open": {"s": [[-2.2, 2.2, 3.6]], "e": [[-45.5, -42.0, 3.0]], "n": [[-2.0, 2.0, 4.0]]}},
	"office_way": {"space": "office", "zone": "mine", "x0": 8.0, "x1": 12.0, "z0": -45.5, "z1": -42.0, "y": 0.0, "h": 3.0,
		"open": {"w": "all", "e": "all"}},
	"office": {"space": "office", "zone": "mine", "x0": 12.0, "x1": 20.0, "z0": -48.0, "z1": -39.0, "y": 0.0, "h": 3.4,
		"open": {"w": [[-45.5, -42.0, 3.0]]}},
	"gate": {"space": "gate", "zone": "mine", "x0": -2.0, "x1": 2.0, "z0": -58.0, "z1": -50.0, "y": 0.0, "h": 4.0,
		"open": {"s": "all", "n": [[-1.3, 1.3, 3.2]]}},
	"stair": {"space": "stair", "zone": "ruins", "x0": -1.3, "x1": 8.7, "z0": -68.0, "z1": -58.0, "y": -6.0, "h": 10.0, "custom": true},
	"hall_way": {"space": "hall", "zone": "ruins", "x0": 8.7, "x1": 12.0, "z0": -60.6, "z1": -58.0, "y": -6.0, "h": 3.0,
		"open": {"w": "all", "e": "all"}},
	"hall": {"space": "hall", "zone": "ruins", "x0": 12.0, "x1": 42.0, "z0": -66.3, "z1": -52.3, "y": -6.0, "h": 7.0,
		"open": {"w": [[-60.6, -58.0, 3.0]], "e": [[-61.1, -57.5, 3.4]]}},
	"crossing": {"space": "hall", "zone": "ruins", "x0": 42.0, "x1": 46.5, "z0": -76.0, "z1": -50.0, "y": -6.0, "h": 4.2,
		"open": {"w": [[-61.1, -57.5, 3.4]], "n": "all"}},
	"shrine": {"space": "shrine", "zone": "ruins", "x0": 34.0, "x1": 56.0, "z0": -94.0, "z1": -76.0, "y": -6.0, "h": 8.0,
		"open": {"s": [[42.0, 46.5, 4.2]], "n": [[37.0, 40.5, 3.2]], "e": [[-87.5, -84.0, 3.2]]}},
	"wrong_way": {"space": "shrine", "zone": "ruins", "x0": 37.0, "x1": 40.5, "z0": -100.0, "z1": -94.0, "y": -6.0, "h": 3.2,
		"open": {"s": "all"}},
	"shrine_cp": {"space": "shrine", "zone": "ruins", "x0": 56.0, "x1": 64.0, "z0": -89.5, "z1": -82.0, "y": -6.0, "h": 3.6,
		"open": {"w": [[-87.5, -84.0, 3.2]], "e": [[-88.0, -83.5, 3.6]]}},
	# Sloped tunnel from the Ruins (-6) down into the Silk Hollows (-10); floor slopes between x 66 and 78.
	"descent_top": {"space": "webbed", "zone": "ruins", "x0": 64.0, "x1": 72.0, "z0": -88.0, "z1": -83.5, "y": -8.0, "h": 6.0, "ylo": -9.0, "yhi": -1.5, "custom": true},
	"descent_low": {"space": "webbed", "zone": "silk", "x0": 72.0, "x1": 80.0, "z0": -88.0, "z1": -83.5, "y": -10.0, "h": 6.0, "ylo": -11.0, "yhi": -3.5, "custom": true},
	"webbed": {"space": "webbed", "zone": "silk", "x0": 80.0, "x1": 100.0, "z0": -89.5, "z1": -82.0, "y": -10.0, "h": 7.0,
		"open": {"w": [[-88.0, -83.5, 4.0]], "e": "all"}},
	"junction": {"space": "webbed", "zone": "silk", "x0": 100.0, "x1": 110.0, "z0": -92.0, "z1": -80.0, "y": -10.0, "h": 7.0,
		"open": {"w": [[-89.5, -82.0, 7.0]], "n": [[101.5, 108.5, 7.0]], "s": [[103.0, 106.5, 3.2]]}},
	"webbed2": {"space": "webbed", "zone": "silk", "x0": 101.5, "x1": 108.5, "z0": -110.0, "z1": -92.0, "y": -10.0, "h": 7.0,
		"open": {"n": "all", "s": "all"}},
	"nursery_way": {"space": "nursery", "zone": "silk", "x0": 103.0, "x1": 106.5, "z0": -80.0, "z1": -76.0, "y": -10.0, "h": 3.2,
		"open": {"n": "all", "s": "all"}},
	"nursery": {"space": "nursery", "zone": "silk", "x0": 97.0, "x1": 113.0, "z0": -76.0, "z1": -64.0, "y": -10.0, "h": 5.0,
		"open": {"n": [[103.0, 106.5, 3.2]]}},
	"antechamber": {"space": "arena", "zone": "silk", "x0": 100.0, "x1": 110.0, "z0": -118.0, "z1": -110.0, "y": -10.0, "h": 5.0,
		"open": {"s": [[101.5, 108.5, 5.0]], "n": [[102.5, 107.5, 4.0]]}},
	# Ramp from the antechamber (-10) down to the arena floor (-12); slope between z -119 and -125.
	"arena_way": {"space": "arena", "zone": "boss", "x0": 102.5, "x1": 107.5, "z0": -127.0, "z1": -118.0, "y": -12.0, "h": 6.0, "ylo": -13.0, "yhi": -5.0, "custom": true},
	"arena": {"space": "arena", "zone": "boss", "x0": 94.0, "x1": 116.0, "z0": -148.5, "z1": -126.5, "y": -12.0, "h": 13.0, "custom": true},
	"lift_recess": {"space": "arena", "zone": "boss", "x0": 115.0, "x1": 118.6, "z0": -139.3, "z1": -135.7, "y": -12.0, "h": 4.0, "custom": true},
}

## The 11 designed spaces (GAME_SPEC.md), in critical-path order (the Nursery is optional).
const SPACES := ["landing", "tunnel", "gallery", "office", "gate", "stair", "hall", "shrine", "webbed", "nursery", "arena"]

const ARENA_CENTER := Vector3(105.0, -12.0, -137.5)
const ARENA_RADIUS := 11.0
const ARENA_CEILING_Y := 1.0

## Stair shaft (square spiral of three flights around a central core).
const STAIR := {"x0": -1.3, "z1": -58.0, "size": 10.0, "w": 2.6, "top_y": 0.0, "drop": 2.0}

## Spawn points: position + facing yaw in degrees (0 = facing north/-z, 90 = west, -90 = east, 180 = south).
const SPAWNS := {
	"mine_entry": {"pos": Vector3(0.0, 0.0, 0.8), "yaw": 0.0},
	"lift_bottom": {"pos": Vector3(4.2, 0.0, 0.6), "yaw": 150.0},
	"cp_landing": {"pos": Vector3(-3.4, 0.0, -1.2), "yaw": 0.0},
	"cp_office": {"pos": Vector3(14.6, 0.0, -42.0), "yaw": -90.0},
	"cp_shrine": {"pos": Vector3(60.0, -6.0, -85.75), "yaw": -90.0},
	"cp_arena": {"pos": Vector3(103.0, -10.0, -114.0), "yaw": 0.0},
	"lift_chamber": {"pos": Vector3(110.6, -12.0, -137.5), "yaw": 90.0},
}

## Checkpoint lanterns: id -> lantern position, spawn id, zone. Flag "cp_lit_<id>" persists the lit state.
const CHECKPOINTS := {
	"landing": {"pos": Vector3(-5.6, 0.0, -1.6), "spawn": "cp_landing", "zone": "mine"},
	"office": {"pos": Vector3(13.2, 0.0, -40.0), "spawn": "cp_office", "zone": "mine"},
	"shrine": {"pos": Vector3(60.0, -6.0, -82.75), "spawn": "cp_shrine", "zone": "ruins"},
	"arena": {"pos": Vector3(100.9, -10.0, -115.5), "spawn": "cp_arena", "zone": "silk"},
}

const SAFE_RADIUS := 4.0

## Critical path (floor points) from the landing to the lift in the Heartseed Chamber, used by the
## clearance tests. Consecutive points are joined by straight segments.
const CRITICAL_PATH := [
	Vector3(0.0, 0.0, 0.8), Vector3(0.0, 0.0, -5.0), Vector3(-1.0, 0.0, -8.0), Vector3(-1.0, 0.0, -34.0),
	Vector3(0.0, 0.0, -37.5), Vector3(0.0, 0.0, -43.0), Vector3(0.0, 0.0, -49.0), Vector3(0.0, 0.0, -53.0),
	Vector3(0.0, 0.0, -57.2), Vector3(0.0, 0.0, -59.3),
	Vector3(0.0, 0.0, -60.6), Vector3(0.0, -2.0, -65.4), Vector3(0.0, -2.0, -66.7),
	Vector3(1.3, -2.0, -66.7), Vector3(6.1, -4.0, -66.7), Vector3(7.4, -4.0, -66.7),
	Vector3(7.4, -4.0, -65.4), Vector3(7.4, -6.0, -60.6), Vector3(7.4, -6.0, -59.3),
	Vector3(10.0, -6.0, -59.3), Vector3(13.0, -6.0, -59.3), Vector3(27.0, -6.0, -59.3), Vector3(41.0, -6.0, -59.3),
	Vector3(44.2, -6.0, -59.3), Vector3(44.2, -6.0, -70.0), Vector3(44.2, -6.0, -77.5),
	Vector3(50.0, -6.0, -80.0), Vector3(54.0, -6.0, -85.75), Vector3(57.0, -6.0, -85.75), Vector3(63.0, -6.0, -85.75),
	Vector3(66.0, -6.0, -85.75), Vector3(78.0, -10.0, -85.75), Vector3(81.0, -10.0, -85.75), Vector3(99.0, -10.0, -85.75),
	Vector3(105.0, -10.0, -86.0), Vector3(105.0, -10.0, -95.0), Vector3(105.0, -10.0, -109.0),
	Vector3(105.0, -10.0, -114.0), Vector3(105.0, -10.0, -119.0), Vector3(105.0, -12.0, -125.0),
	Vector3(105.0, -12.0, -131.0), Vector3(110.0, -12.0, -137.5), Vector3(113.0, -12.0, -137.5),
]

## Side paths that must also be walkable (office detour, the Threshold passage, the Nursery,
## the wrong exit of the shrine, the crossing's dead end).
const SIDE_PATHS := [
	[Vector3(0.0, 0.0, -43.75), Vector3(7.0, 0.0, -43.75), Vector3(12.5, 0.0, -43.75), Vector3(16.5, 0.0, -43.75)],
	[Vector3(0.0, 0.0, -20.0), Vector3(-9.0, 0.0, -20.0)],
	[Vector3(105.0, -10.0, -86.0), Vector3(104.75, -10.0, -81.0), Vector3(104.75, -10.0, -77.0), Vector3(104.75, -10.0, -70.0)],
	[Vector3(44.2, -6.0, -77.5), Vector3(41.0, -6.0, -88.0), Vector3(38.75, -6.0, -93.0), Vector3(38.75, -6.0, -97.0)],
	[Vector3(44.2, -6.0, -59.3), Vector3(44.2, -6.0, -53.5)],
]

## Where the rubble and the gate block the critical path while closed.
const RUBBLE_CENTER := Vector3(10.0, 0.0, -43.75)
const GATE_CENTER := Vector3(0.0, 0.0, -55.0)

## Authored-moment reference points.
const THRESHOLD_POINT := Vector3(-8.5, 1.0, -20.0)
const CROSSING_DOORWAY := Vector3(42.0, -6.0, -59.3)
const FAKE_LUMI_POS := Vector3(38.75, -6.0, -92.6)
const SILK_INTRO_POS := Vector3(95.5, -3.35, -86.0)
const SILK_INTRO_HIDE := Vector3(99.0, -2.8, -83.2)

## Stalker ceiling route in the Webbed Passage (ceiling at y = -3) and its ambush points. One
## connected chain (every hop < 14 m with nothing in between) from the passage, through the junction,
## down to the chamber approach, so director passes work wherever Krystal is in the Silk Hollows.
const STALKER_ROUTE := [
	Vector3(86.0, -3.4, -85.0), Vector3(92.0, -3.4, -86.5), Vector3(98.0, -3.4, -85.2),
	Vector3(104.0, -3.4, -84.0), Vector3(106.5, -3.4, -90.0), Vector3(104.0, -3.4, -96.0),
	Vector3(106.0, -3.4, -102.0), Vector3(103.5, -3.4, -107.5),
]
const STALKER_AMBUSH := [Vector3(103.2, -10.0, -99.0), Vector3(106.4, -10.0, -104.5)]

## Boss arena: ceiling anchors (4-5) and brazier spots (three, 120 degrees apart).
## Three braziers sit below the first three anchors (SE, SW, N); none blocks the entrance (south).
const ARENA_ANCHORS := [
	Vector3(111.1, -4.4, -134.0), Vector3(98.9, -4.4, -134.0), Vector3(105.0, -4.2, -144.5),
	Vector3(105.0, -2.4, -138.5), Vector3(110.6, -4.4, -141.8),
]
const BRAZIERS := [Vector3(111.1, -12.0, -134.0), Vector3(98.9, -12.0, -134.0), Vector3(105.0, -12.0, -144.5)]

## Director anchors: [space, zone, kind, position]. 3-6 per space; ceiling anchors in the Silk Hollows.
const ANCHORS := [
	["landing", "mine", "sound", Vector3(0.0, 2.0, -5.5)], ["landing", "mine", "doorway", Vector3(0.0, 0.2, -6.5)],
	["landing", "mine", "floor", Vector3(-4.0, 0.0, -3.0)],
	["tunnel", "mine", "sound", Vector3(-9.5, 1.5, -20.0)], ["tunnel", "mine", "doorway", Vector3(-3.0, 0.2, -20.0)],
	["tunnel", "mine", "doorway", Vector3(0.0, 0.2, -35.5)], ["tunnel", "mine", "floor", Vector3(-1.0, 0.0, -14.0)],
	["tunnel", "mine", "spawn", Vector3(-9.0, 0.0, -20.0)], ["tunnel", "mine", "sound", Vector3(0.0, 3.0, -30.0)],
	["gallery", "mine", "sound", Vector3(-6.0, 3.5, -48.0)], ["gallery", "mine", "doorway", Vector3(0.0, 0.2, -50.5)],
	["gallery", "mine", "spawn", Vector3(-6.7, 0.0, -43.6)], ["gallery", "mine", "spawn", Vector3(5.6, 0.0, -41.2)],
	["gallery", "mine", "floor", Vector3(3.0, 0.0, -41.0)], ["gallery", "mine", "doorway", Vector3(8.5, 0.2, -43.75)],
	["office", "mine", "sound", Vector3(19.0, 1.5, -47.0)], ["office", "mine", "doorway", Vector3(11.0, 0.2, -43.75)],
	["office", "mine", "floor", Vector3(15.0, 0.0, -46.0)],
	["gate", "mine", "sound", Vector3(0.0, 1.5, -57.5)], ["gate", "mine", "doorway", Vector3(0.0, 0.2, -57.8)],
	["gate", "mine", "floor", Vector3(0.0, 0.0, -51.5)],
	["stair", "ruins", "ceiling", Vector3(3.7, 3.6, -63.0)], ["stair", "ruins", "sound", Vector3(0.0, 2.5, -67.0)],
	["stair", "ruins", "doorway", Vector3(9.5, -5.8, -59.3)], ["stair", "ruins", "ceiling", Vector3(7.4, 3.6, -66.7)],
	["hall", "ruins", "doorway", Vector3(42.5, -5.8, -59.3)], ["hall", "ruins", "sound", Vector3(38.0, -3.0, -65.0)],
	["hall", "ruins", "spawn", Vector3(38.0, -6.0, -54.0)], ["hall", "ruins", "spawn", Vector3(44.2, -6.0, -53.0)],
	["hall", "ruins", "floor", Vector3(27.0, -6.0, -59.3)], ["hall", "ruins", "ceiling", Vector3(27.0, 0.5, -59.3)],
	["hall", "ruins", "doorway", Vector3(44.2, -5.8, -72.0)],
	["shrine", "ruins", "doorway", Vector3(38.75, -5.8, -94.5)], ["shrine", "ruins", "sound", Vector3(45.0, -3.0, -92.0)],
	["shrine", "ruins", "spawn", Vector3(38.75, -6.0, -98.0)], ["shrine", "ruins", "floor", Vector3(45.0, -6.0, -85.0)],
	["shrine", "ruins", "doorway", Vector3(56.5, -5.8, -85.75)], ["shrine", "ruins", "ceiling", Vector3(45.0, 1.5, -85.0)],
	["webbed", "silk", "ceiling", Vector3(88.0, -3.3, -85.75)], ["webbed", "silk", "ceiling", Vector3(96.0, -3.3, -86.5)],
	["webbed", "silk", "ceiling", Vector3(105.0, -3.3, -97.0)], ["webbed", "silk", "ceiling", Vector3(105.0, -3.3, -106.0)],
	["webbed", "silk", "sound", Vector3(105.0, -8.0, -108.0)], ["webbed", "silk", "doorway", Vector3(105.0, -9.8, -92.5)],
	["webbed", "silk", "spawn", Vector3(108.0, -10.0, -82.0)], ["webbed", "silk", "floor", Vector3(90.0, -10.0, -85.75)],
	["nursery", "silk", "sound", Vector3(110.0, -8.0, -68.0)], ["nursery", "silk", "ceiling", Vector3(105.0, -5.4, -70.0)],
	["nursery", "silk", "floor", Vector3(100.0, -10.0, -67.0)],
	["arena", "silk", "ceiling", Vector3(105.0, -5.4, -114.0)], ["arena", "silk", "sound", Vector3(105.0, -8.0, -122.0)],
	["arena", "silk", "doorway", Vector3(105.0, -9.8, -118.5)],
]

## Resource nodes (stable ids). kind: glowcap (hand) / silk (hand) / crystal (pickaxe -> echo_shard).
const RESOURCES := [
	{"id": "below_glowcap_1", "kind": "glowcap", "pos": Vector3(-5.8, 0.0, -4.6)},
	{"id": "below_glowcap_2", "kind": "glowcap", "pos": Vector3(1.6, 0.0, -24.5)},
	{"id": "below_glowcap_3", "kind": "glowcap", "pos": Vector3(-6.7, 0.0, -38.2)},
	{"id": "below_glowcap_4", "kind": "glowcap", "pos": Vector3(18.8, 0.0, -39.9)},
	{"id": "below_glowcap_5", "kind": "glowcap", "pos": Vector3(34.5, -6.0, -53.3)},
	{"id": "below_glowcap_6", "kind": "glowcap", "pos": Vector3(55.0, -6.0, -80.0)},
	{"id": "below_glowcap_7", "kind": "glowcap", "pos": Vector3(99.2, -10.0, -83.0)},
	{"id": "below_glowcap_8", "kind": "glowcap", "pos": Vector3(98.4, -10.0, -65.2)},
	{"id": "below_silk_1", "kind": "silk", "pos": Vector3(86.0, -10.0, -88.7)},
	{"id": "below_silk_2", "kind": "silk", "pos": Vector3(109.2, -10.0, -90.8)},
	{"id": "below_silk_3", "kind": "silk", "pos": Vector3(107.7, -10.0, -100.0)},
	{"id": "below_silk_4", "kind": "silk", "pos": Vector3(99.0, -10.0, -73.8)},
	{"id": "below_silk_5", "kind": "silk", "pos": Vector3(111.8, -10.0, -71.0)},
	{"id": "below_silk_6", "kind": "silk", "pos": Vector3(106.0, -10.0, -65.0)},
	{"id": "below_crystal_1", "kind": "crystal", "pos": Vector3(6.9, 0.0, -48.9)},
	{"id": "below_crystal_2", "kind": "crystal", "pos": Vector3(12.8, -6.0, -65.4)},
	{"id": "below_crystal_3", "kind": "crystal", "pos": Vector3(35.2, -6.0, -79.6)},
	{"id": "below_crystal_4", "kind": "crystal", "pos": Vector3(111.9, -10.0, -65.0)},
	{"id": "below_crystal_5", "kind": "crystal", "pos": Vector3(98.0, -10.0, -75.0)},
	{"id": "below_crystal_6", "kind": "crystal", "pos": Vector3(109.3, -10.0, -111.0)},
]

## Lore notes placed in the world: id -> position (the text lives in lore.gd).
const LORE_SPOTS := {
	"landing_notice": Vector3(3.6, 0.0, -5.7),
	"miner_journal_1": Vector3(-1.85, 0.0, -27.9),
	"foreman_order": Vector3(18.6, 0.0, -44.6),
	"miner_journal_2": Vector3(43.2, -6.0, -61.6),
	"ward_keeper": Vector3(49.0, -6.0, -87.1),
	"hollows_page": Vector3(108.9, -10.0, -115.8),
}


## Spawn transform: player faces along -Z rotated by yaw.
static func spawn_xform(id: String) -> Transform3D:
	var s: Dictionary = SPAWNS.get(id, SPAWNS["mine_entry"])
	var p: Vector3 = s["pos"]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"]))), p + Vector3(0.0, 0.05, 0.0))


## Room vertical range used for detection.
static func room_y_range(r: Dictionary) -> Vector2:
	var y: float = float(r["y"])
	var lo: float = float(r.get("ylo", y - 1.0))
	var hi: float = float(r.get("yhi", y + float(r["h"]) + 0.5))
	return Vector2(lo, hi)


## Room id containing a position ("" if none). Arena is a circle.
static func room_at(pos: Vector3) -> String:
	for id in ROOMS:
		var r: Dictionary = ROOMS[id]
		var yr := room_y_range(r)
		if pos.y < yr.x or pos.y > yr.y:
			continue
		if id == "arena":
			if Vector2(pos.x - ARENA_CENTER.x, pos.z - ARENA_CENTER.z).length() <= ARENA_RADIUS + 0.2:
				return id
			continue
		if pos.x >= float(r["x0"]) and pos.x <= float(r["x1"]) and pos.z >= float(r["z0"]) and pos.z <= float(r["z1"]):
			return id
	return ""


## Nearest room by horizontal distance to its box (used when a point is slightly outside every room).
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
			best = id
	return best


static func space_of(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("space", ""))


static func zone_of_room(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("zone", ""))
