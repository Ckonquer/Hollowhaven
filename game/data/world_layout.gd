extends RefCounted
## Shared surface-world layout so every system agrees on where things are.
## Coordinates are meters on the XZ plane (x = east, z = south, y = up). The origin is the
## centre of the Haven clearing. Heights come from the terrain (SurfaceTerrain.height_at).

const WORLD_HALF_EXTENT := 110.0          # playable area is roughly x,z in [-110, 110]
const KILL_Y := -40.0                     # below this the player is recovered to the last safe spot

## Haven clearing: flat, safe, buildable.
const HAVEN_CENTER := Vector2(0, 0)
const HAVEN_RADIUS := 20.0                # safe zone radius (no enemy spawns / director never runs on surface anyway)
const BUILD_AREA := {"center": Vector2(0, 0), "radius": 16.0, "grid": 1.0,
	"blocked": [ {"center": Vector2(0, -6), "radius": 3.5, "name": "Ward Stone"},
				 {"center": Vector2(4, 3), "radius": 2.2, "name": "campfire"},
				 {"center": Vector2(0, 7), "radius": 1.8} ],   # start path: generic "needs to stay clear" message
	# Chapter Two (append-only): extra buildable regions [{center: Vector2, radius, blocked?}] added by the
	# Haven expansion (spec 7.1). Empty = the legacy build circle only.
	# Chosen from the real terrain + Vegetation.plan() (tests/unit/test_building_haven_area.gd re-checks it all):
	# every circle stays >= 5 m from the stream centreline, off the paths leaving the Haven (and so off the
	# legacy start path), clear of the Ward Stone / campfire / start-path circles, the Haven sign and the Old
	# Oak radius, >= 2 m from every tree, rock, ore, berry bush, decorative bush and log, on ground that rises
	# less than 0.2 m per metre, and overlaps the legacy circle or another region (one connected home).
	# Legacy placements inside the 16 m circle keep exactly the legacy rules.
	"extra": [
		{"center": Vector2(-9, 19), "radius": 6.5},      # south-west lawn, west of the meadow path
		{"center": Vector2(-8, 24), "radius": 4.7},
		{"center": Vector2(-14, 21), "radius": 4.25},
		{"center": Vector2(-12, 10), "radius": 4.75},    # joins the south-west lawn to the clearing
		{"center": Vector2(-17, 10), "radius": 2.75},
		{"center": Vector2(-17, -4), "radius": 5.75},    # west lawn, between the glade and Old Oak paths
		{"center": Vector2(-23, 1), "radius": 2.75},
		{"center": Vector2(3, -19), "radius": 3.75},     # north, between the ruin and mine paths
		{"center": Vector2(4, -21), "radius": 3.5},
		{"center": Vector2(7, 15), "radius": 3.25},      # south-east, between the meadow and pond paths
		{"center": Vector2(12, -11), "radius": 2.25},    # north-east nook inside the fence, clear of the stream
	]}

## Named places (shown on the map and used for zone detection). radius = zone size.
const LANDMARKS := {
	"haven": {"name": "Krystal's Haven", "pos": Vector2(0, 0), "radius": 20.0},
	"glade": {"name": "Berry Glade", "pos": Vector2(-55, 12), "radius": 22.0},
	"quarry": {"name": "Pebble Quarry", "pos": Vector2(66, -12), "radius": 22.0},
	"ruin": {"name": "Moonlit Ruin", "pos": Vector2(-12, -66), "radius": 20.0},
	"mine_mouth": {"name": "Hollow Mine", "pos": Vector2(54, -74), "radius": 14.0},
	"pond": {"name": "Mirror Pond", "pos": Vector2(46, 52), "radius": 16.0},
	"meadow": {"name": "Sunny Meadow", "pos": Vector2(-8, 60), "radius": 22.0},
	"old_oak": {"name": "The Old Oak", "pos": Vector2(-34, -20), "radius": 10.0},
	"thicket": {"name": "Thornthicket", "pos": Vector2(-62, -46), "radius": 16.0},
}

## The stream flows north -> south through these XZ points and ends in Mirror Pond.
const STREAM_POINTS := [Vector2(30, -112), Vector2(27, -70), Vector2(22, -30), Vector2(20, -5), Vector2(27, 22), Vector2(38, 42)]
const STREAM_WIDTH := 4.0
## Crossings (bridges / stepping stones) so the stream never blocks progress.
const STREAM_CROSSINGS := [Vector2(22, -30), Vector2(21, -5), Vector2(28, 24)]

## Spawn points the surface world must provide (Marker3D named "Spawn_<id>"):
##   haven_start      - new game start, facing north toward the Ward Stone
##   haven_respawn    - fallback respawn at the Haven
##   mine_exit        - just outside the mine entrance (arriving from The Below)
##   companion_wild_mochi / companion_wild_pebble / companion_wild_lumi - where they wait before befriending
##   companion_home_mochi / companion_home_pebble / companion_home_lumi - home spots inside the Haven
##   mine_threshold   - where a companion that refuses the mine waits
const SPAWN_HINTS := {
	"haven_start": Vector2(0, 7),
	"haven_respawn": Vector2(-2, 5),
	"mine_exit": Vector2(48, -64),
	"companion_wild_mochi": Vector2(-60, 14),
	"companion_wild_pebble": Vector2(70, -18),
	"companion_wild_lumi": Vector2(-12, -70),
	"companion_home_mochi": Vector2(-7, 7),
	"companion_home_pebble": Vector2(8, -3),
	"companion_home_lumi": Vector2(-4, -6),
	"mine_threshold": Vector2(50, -66),
}

## World clock. 1 real second = MINUTES_PER_SECOND in-game minutes (daytime); nights run faster.
const CLOCK := {"minutes_per_second": 1.0, "night_speedup": 2.5, "day_start_hour": 6.0, "night_start_hour": 20.0, "new_game_hour": 8.0}

## --- Chapter Two additions (append-only; docs/CHAPTER_TWO_SPEC.md 7.1) ------------------------------------
## Validated sites of new Hollowhaven Woods content. Never inside the legacy Haven (>= 18 m from it),
## never on a legacy vegetation node (checked against Vegetation.plan() footprint + 2 m by
## tests/unit/test_flow_ch2_areas.gd). The waygate spawn "waygate" stands 3 m south of the gate.
##   waygate: the Lanternwake waygate, north of the Moonlit Ruin on its outer side (21 m from the ruin
##            centre, 25 m from the ruin_bramblings spawner; flat ground, no tree/rock within 6.5 m).
const CH2_POINTS := {
	"waygate": Vector2(-4, -86),
}
