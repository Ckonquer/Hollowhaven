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

## Spawn stand points (all decided here, except waygate_arrival which is the spec point):
## id -> {pos: Vector2, look: Vector2 (the point she faces on arrival)}. Arch spawns stand 3 m in front
## of their arch, toward the landmark they serve.
const SPAWNS := {
	"waygate_arrival": {"pos": Vector2(0, 98), "look": Vector2(0, 60)},
	"reach_respawn": {"pos": Vector2(6, 66), "look": Vector2(0, 60)},
	"commons_arch": {"pos": Vector2(0, 75), "look": Vector2(0, 60)},
	"orchard_arch": {"pos": Vector2(-62.5, 48.4), "look": Vector2(-82, 36)},
	"quarry_arch": {"pos": Vector2(64.3, 36.1), "look": Vector2(86, 18)},
	"manor_arch": {"pos": Vector2(10.9, -52.8), "look": Vector2(18, -74)},
	"conservatory": {"pos": Vector2(0, 17), "look": Vector2(0, 6)},
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
