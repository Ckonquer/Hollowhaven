extends RefCounted
## Hallowmere Reach layout (docs/CHAPTER_TWO_SPEC.md §7.2): the one place every Reach system reads
## coordinates from (area script, arches, map, music, quests). Metres on the XZ plane, x = east,
## z = south, y = up; forward (yaw 0) is -Z = north. The landmark table below is the spec table verbatim.
## Note: §7.2 says "origin = Commons centre" but its own table puts the Commons at (0, 60); the table
## wins (it is the concrete contract). The map origin sits just north of the Conservatory.
## Everything that is NOT in the spec table (spawn stand points, the Conservatory arch, the mirror
## waygate, the Bellhouse stair and the refuge exit) was decided by the flow module (wave A3) and is
## marked "decided here"; later waves build their content around these points so saves line up.

const AREA_ID := "hallowmere_reach"

## Playable extent: x in [-HALF_X, HALF_X], z in [-HALF_Z, HALF_Z] (soft boundary just inside).
const HALF_X := 140.0
const HALF_Z := 110.0

## Landmarks = zone ids (get_zone_at) = map landmark ids. Never reuse a legacy zone string.
const LANDMARKS := {
	"hr_commons": {"name": "Lanternwake Commons", "pos": Vector2(0, 60), "radius": 24.0, "safe": true},
	"hr_conservatory": {"name": "Ward-Keeper's Conservatory", "pos": Vector2(0, 6), "radius": 14.0, "safe": true},
	"hr_orchard": {"name": "Pumpkintide Orchard", "pos": Vector2(-82, 36), "radius": 30.0, "safe": false},
	"hr_pools": {"name": "Thimblebrook Pools", "pos": Vector2(-44, -8), "radius": 18.0, "safe": false},
	"hr_candleyard": {"name": "The Candleyard", "pos": Vector2(-86, -60), "radius": 22.0, "safe": false},
	"hr_quarry": {"name": "Ashbell Quarry", "pos": Vector2(86, 18), "radius": 30.0, "safe": false},
	"hr_manor_grounds": {"name": "Moonveil Manor", "pos": Vector2(18, -74), "radius": 26.0, "safe": false},
	"hr_bellhouse": {"name": "Sunken Bellhouse", "pos": Vector2(72, -74), "radius": 16.0, "safe": false},
}

## Named points from the notes column of the spec table.
const POINTS := {
	"waygate_arrival": Vector2(0, 98),       # arrival from the Woods, facing north
	"commons_arch": Vector2(0, 78),
	"orchard_arch": Vector2(-60, 50),
	"quarry_arch": Vector2(62, 38),
	"manor_arch": Vector2(10, -50),
	"outpost": Vector2(-16, 54),             # optional small outpost build area (r = 8)
	"winch": Vector2(100, 0),
	"moon_crystal_shelf": Vector2(110, -26),
	"warden_arena": Vector2(90, 10),
	"manor_door": Vector2(18, -86),          # -> moonveil_manor
	# decided here:
	"conservatory_arch": Vector2(0, 20),     # the Conservatory's Lantern Road arch (south entrance)
	"mirror_waygate": Vector2(0, 102),       # the Reach side of the Lanternwake waygate (behind the arrival)
	"bellhouse_stair": Vector2(72, -78),     # stair down -> hushed_works (revealed by ch2_lamps_linked)
	"refuge_hatch": Vector2(24, 2),          # where the Works refuge shortcut comes out
}

const OUTPOST_BUILD_AREA := {"center": Vector2(-16, 54), "radius": 8.0}

## Spawn stand points (all decided here; waygate_arrival stands just north of the spec point POINTS.waygate_arrival):
## id -> {pos: Vector2, look: Vector2 (the point she faces on arrival)}. Camera rule (visual QA T1): the follow
## camera hangs ~4.8 m behind her, so nothing it must not sit inside may stand within ~5 m behind a spawn.
## Arch spawns stand 4.6 m in front of their arch (inside its 5 m safe circle), toward the landmark they serve: the
## camera then comes to rest just in front of the arch's camera blocker (lantern_arch.gd), never behind the
## bunting and the lantern. The arrival stands 5.8 m in front of the mirror waygate: the first view of Chapter Two
## is the open festival road, with the gate behind the camera.
const SPAWNS := {
	"waygate_arrival": {"pos": Vector2(0, 96.2), "look": Vector2(0, 60)},
	"reach_respawn": {"pos": Vector2(6, 66), "look": Vector2(0, 60)},
	"commons_arch": {"pos": Vector2(0, 73.4), "look": Vector2(0, 60)},
	"orchard_arch": {"pos": Vector2(-63.88, 47.53), "look": Vector2(-82, 36)},
	"quarry_arch": {"pos": Vector2(65.53, 35.06), "look": Vector2(86, 18)},
	"manor_arch": {"pos": Vector2(11.45, -54.36), "look": Vector2(18, -74)},
	"conservatory": {"pos": Vector2(0, 15.4), "look": Vector2(0, 6)},
	"manor_door": {"pos": Vector2(18, -82), "look": Vector2(10, -50)},
	"bellhouse_stair": {"pos": Vector2(72, -72), "look": Vector2(40, -40)},
	"refuge_exit": {"pos": Vector2(20, 4), "look": Vector2(0, 6)},
}

## Lantern Road arches (flags ch2_arch_<id>, spec §8). Order = order in the travel list.
const ARCH_ORDER := ["commons", "orchard", "quarry", "manor", "conservatory"]
const ARCHES := {
	"commons": {"name": "Lanternwake Commons", "pos": Vector2(0, 78), "spawn": "commons_arch", "landmark": "hr_commons"},
	"orchard": {"name": "Pumpkintide Orchard", "pos": Vector2(-60, 50), "spawn": "orchard_arch", "landmark": "hr_orchard"},
	"quarry": {"name": "Ashbell Quarry", "pos": Vector2(62, 38), "spawn": "quarry_arch", "landmark": "hr_quarry"},
	"manor": {"name": "Moonveil Manor", "pos": Vector2(10, -50), "spawn": "manor_arch", "landmark": "hr_manor_grounds"},
	"conservatory": {"name": "Ward-Keeper's Conservatory", "pos": Vector2(0, 20), "spawn": "conservatory", "landmark": "hr_conservatory"},
}
## Every arch (and the waygate arrival) is a small safe circle, even inside an unsafe landmark.
const ARCH_SAFE_RADIUS := 5.0
const ARRIVAL_SAFE_RADIUS := 7.0

## Default respawn in the Reach until an arch is lit (spec §1: last lit arch, default commons_arch).
const DEFAULT_RESPAWN := "commons_arch"


static func arch_flag(arch_id: String) -> String:
	return "ch2_arch_" + arch_id


## Arch id whose travel spawn is `spawn_id` ("" if none).
static func arch_for_spawn(spawn_id: String) -> String:
	for id in ARCHES:
		if String(ARCHES[id]["spawn"]) == spawn_id:
			return String(id)
	return ""


## Yaw (radians) that makes a node at `from` face `to` (forward = -Z), same as surface_world.
static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length() < 0.001:
		return 0.0
	return atan2(-d.x, -d.y)


static func is_inside(p: Vector2, margin: float = 0.0) -> bool:
	return absf(p.x) <= HALF_X - margin and absf(p.y) <= HALF_Z - margin


# ======================================================================================================
# Wave C additions (world module C1, the Reach base region). ADDITIVE ONLY: nothing above this line is
# changed. Everything below is read by src/world/reach/* (terrain, roads, water, set pieces), the map (road
# routes revealed by the festival board) and the tests. Coordinates follow the rules at the top of the file.
# ======================================================================================================

## Invisible boundary walls stand on this rounded rectangle (soft hills and dense trees rise behind it).
const WALL_HALF_X := 136.0
const WALL_HALF_Z := 106.5
const WALL_CORNER := 22.0

## Roads: Catmull-Rom centrelines (metres). Half widths in PATH_WIDTHS. The three BRANCH roads leave the
## Lantern Crossroads (CROSSROADS) and the Conservatory and are visible from the arrival.
const PATHS := {
	"arrival_road": [Vector2(0, 101.5), Vector2(0, 94), Vector2(0, 86), Vector2(0, 78), Vector2(0, 70)],
	"main_road": [Vector2(0, 50), Vector2(0, 44), Vector2(0, 38), Vector2(-0.8, 30), Vector2(0, 22), Vector2(0, 15.5)],
	"west_road": [Vector2(0, 38), Vector2(-12, 41), Vector2(-22, 45), Vector2(-28.5, 48.3), Vector2(-34, 48.3), Vector2(-39.5, 48.3), Vector2(-46, 51.5),
		Vector2(-54.9, 53.2), Vector2(-60, 50), Vector2(-63.5, 47.7)],
	"east_road": [Vector2(0, 38), Vector2(12, 40), Vector2(26, 42.5), Vector2(40, 44), Vector2(50, 43.5),
		Vector2(57.4, 41.8), Vector2(62, 38), Vector2(64.7, 35.8)],
	"north_road": [Vector2(0, -3.5), Vector2(0.5, -12), Vector2(2.5, -24), Vector2(5, -34), Vector2(8.1, -44.3),
		Vector2(10, -50), Vector2(11.2, -53.6)],
	"refuge_spur": [Vector2(7.5, 6), Vector2(14, 5), Vector2(21, 3)],
	"pools_road": [Vector2(-7.5, 6), Vector2(-17, 2.5), Vector2(-24, -2.5), Vector2(-28.5, -6)],
	"brook_steps_road": [Vector2(-9, 14.5), Vector2(-20, 15.3), Vector2(-28.5, 15.0), Vector2(-32.8, 15.0), Vector2(-37, 15.0), Vector2(-41.5, 12.0), Vector2(-45, 9.5)],
	"orchard_pools": [Vector2(-58, 16), Vector2(-51, 12), Vector2(-45, 9.5)],
	"orchard_candleyard": [Vector2(-76, 8), Vector2(-80, -4), Vector2(-84, -18), Vector2(-86, -30), Vector2(-86, -39.2)],
	"pools_candleyard": [Vector2(-60, -24), Vector2(-66, -33), Vector2(-72.6, -43.4)],
	"bellhouse_road": [Vector2(6.5, -38), Vector2(20, -44), Vector2(34, -50), Vector2(46, -58), Vector2(58, -66),
		Vector2(66, -70), Vector2(70, -71)],
	"quarry_bellhouse": [Vector2(74, -70), Vector2(78, -58), Vector2(82, -44), Vector2(84, -30), Vector2(85, -14)],
}
const PATH_WIDTHS := {
	"arrival_road": 2.0, "main_road": 1.8, "west_road": 1.7, "east_road": 1.7, "north_road": 1.7,
	"refuge_spur": 1.1, "pools_road": 1.3, "brook_steps_road": 1.1, "orchard_pools": 1.2,
	"orchard_candleyard": 1.3, "pools_candleyard": 1.2, "bellhouse_road": 1.4, "quarry_bellhouse": 1.3,
}
## Soft packed-earth patches (festival ground, crossroads): [centre, radius, strength 0..1].
const DIRT_PATCHES := [
	[Vector2(0, 60), 15.0, 0.42], [Vector2(0, 38), 5.5, 0.75], [Vector2(0, 98), 5.0, 0.55],
	[Vector2(0, 17), 4.0, 0.5], [Vector2(-60, 50), 3.0, 0.5], [Vector2(62, 38), 3.0, 0.5], [Vector2(10, -50), 3.0, 0.5],
]
## The Lantern Crossroads: the west (orchard) and east (quarry) roads leave the main road here; the north road
## (manor) leaves the Conservatory's north door. A tall signpost stands here, visible from the arrival.
const CROSSROADS := Vector2(0, 38)
## The festival board reveals these on the map (flag ch2_read_festival_map): road ids -> branch landmark.
const MAP_ROUTES := {
	"flag": "ch2_read_festival_map",
	"branches": {"hr_orchard": ["main_road", "west_road"], "hr_quarry": ["main_road", "east_road"],
		"hr_manor_grounds": ["main_road", "north_road"]},
	"roads": ["arrival_road", "main_road", "west_road", "east_road", "north_road"],
}

## Thimblebrook: the brook leaves the Thimblebrook Pools (the pools district draws its own spring brook and
## pools inside hr_pools) at the reeds and runs south past the Commons' west side, out through the south hills.
const BROOK_POINTS := [Vector2(-31.2, 4.0), Vector2(-31.8, 8.0), Vector2(-32.5, 14.0), Vector2(-34.0, 26.0),
	Vector2(-34.5, 38.0), Vector2(-34.0, 48.0), Vector2(-34.0, 60.0), Vector2(-33.5, 74.0), Vector2(-32.0, 88.0),
	Vector2(-32.5, 102.0), Vector2(-36.0, 124.0)]
const BROOK_HALF_WIDTH := 1.45
## Dry crossings (the brook is shallow and never blocks progress anyway): style "bridge" | "stones".
const BROOK_CROSSINGS := [
	{"id": "west_bridge", "pos": Vector2(-34.0, 48.3), "style": "bridge"},
	{"id": "brook_steps", "pos": Vector2(-32.8, 15.0), "style": "stones"},
]

## Flat walkable ground: [centre, flat radius, blend radius]. Heights are chosen by the terrain.
const PLAZAS := {
	"arrival": [Vector2(0, 98), 6.5, 13.0],
	"commons": [Vector2(0, 60), 19.0, 27.0],
	"outpost": [Vector2(-16, 54), 9.0, 13.0],
	"crossroads": [Vector2(0, 38), 4.0, 9.0],
	"conservatory": [Vector2(0, 6), 14.0, 21.0],
	"refuge_hatch": [Vector2(23, 2.5), 3.5, 7.0],
	"orchard_arch": [Vector2(-60, 50), 4.0, 8.5],
	"quarry_arch": [Vector2(62, 38), 4.0, 8.5],
	"manor_arch": [Vector2(10, -50), 4.0, 8.5],
	"manor_door": [Vector2(18, -83), 3.5, 7.0],
	"bellhouse": [Vector2(72, -71), 6.0, 11.0],
}
## Arch plazas are re-levelled after the districts shaped their terrain (the arches belong to the region).
const PROTECTED_PLAZAS := ["orchard_arch", "quarry_arch", "manor_arch"]

## Lanternwake Commons set piece (festival ground around the Commons centre).
const COMMONS := {
	"pole": Vector2(0, 60),
	"light_posts": [Vector2(7.36, 64.25), Vector2(-7.36, 64.25), Vector2(-7.36, 55.75), Vector2(7.36, 55.75)],
	## [position, kind] - every stall's counter faces the pole.
	"stalls": [[Vector2(-7.0, 72.1), "costumes"], [Vector2(7.0, 72.1), "pumpkins"], [Vector2(13.2, 64.8), "lanterns"],
		[Vector2(13.5, 56.4), "sweets"], [Vector2(9.0, 49.3), "candles"], [Vector2(-5.9, 47.3), "ribbons"],
		[Vector2(-13.2, 64.8), "roseberries"]],
	"board": Vector2(3.9, 74.6),
	"mirror": Vector2(-10.2, 69.9),
	"pumpkin_arch": Vector2(0, 88),
	"tables": [[Vector2(10.6, 60.0), 0.0], [Vector2(-10.4, 61.8), 0.35]],
	"bales": [Vector2(3.9, 82.5), Vector2(-3.9, 82.5), Vector2(-4.6, 34.3)],
	"lot_sign": Vector2(-24.5, 50.0),
}

## Ward-Keeper's Conservatory (octagonal glasshouse around the landmark centre).
const CONSERVATORY := {
	"center": Vector2(0, 6), "radius": 6.5,
	"pedestal": Vector2(0, 6),
	"lectern": Vector2(3.25, 9.25),        # preparations note (SE, inside)
	"ledger": Vector2(3.96, 2.04),          # workshop ledger board (NE, inside)
	"plaque": Vector2(-3.96, 2.04),         # the Ward-Keeper's words (NW, inside)
	"bench": Vector2(-3.7, 9.7),            # the safe corner (SW, inside)
	"true_light": Vector2(-2.6, 13.4),      # worn festival plaque beside the south door (outside)
	"practice_seam": Vector2(11.5, 16.0),   # iron seam beside the Conservatory (hr_practice_seam)
	"seam_sign": Vector2(9.2, 13.6),
}
const PRACTICE_SEAM_ID := "hr_practice_seam"

## Sunken Bellhouse (half-sunken tower, still water, the stair to the Hushed Works).
const BELLHOUSE := {
	"forecourt": Vector2(72, -71),
	"stair_x": 72.0, "stair_half": 1.45, "wall_outer": 3.1,
	"ramp_top_z": -77.0, "ramp_bottom_z": -83.5, "depth": 3.5, "bottom_end_z": -88.5,
	"gate_z": -84.6, "descent_z": -87.2,
	"tower": Rect2(68.5, -92.5, 7.0, 7.0),
	"pond": Vector2(72, -92), "pond_radius": 11.5,
	"sign": Vector2(67.2, -67.6),
	"plaque": Vector2(76.9, -74.6),
	"slab_pile": Vector2(66.3, -76.4),
}
## Road lights along the three branches (dark until ch2_lamps_linked, then lit for good).
const ROAD_LIGHT_ROADS := ["main_road", "west_road", "east_road", "north_road"]
const ROAD_LIGHT_SPACING := 10.0
