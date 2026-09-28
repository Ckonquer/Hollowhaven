extends RefCounted
## THE HUSHED WORKS, rooms 1-8 (works module C7; docs/CHAPTER_TWO_SPEC.md §7.4, §10). Pure data shared by
## the area script (src/world/areas_ch2/hushed_works_world.gd), its room builders (src/world/works/*) and the
## tests. Rooms 9-14 live in data/works_layout_deep.gd (the deep module); the area merges both tables into
## ONE room table for the Below builder (src/world/below/below_builder.gd, Builder.new(root, seed, rooms)).
##
## Coordinates: metres, x = east, z = south, y = up. Rooms 1-8 stay inside x [-80, 40]; floors inside
## y [-34, -6]. The fixed connection to the deep rooms is the hub (room 7) EAST door: centre (40, -18, 0),
## floor y -18, opening z [-1.5, 1.5], 3.4 m tall, leading toward +x (deep rooms: x [40, 170]).
##
## ROOMS {id: {space, zone, x0, x1, z0, z1, y, h, open, [custom], [slope], [stairs], [cap], [ylo], [yhi]}}
##   space   the designed room number (1..8) the box belongs to (passages belong to the room they lead into)
##   zone    spec §7.2 zone id (hw_*): music, companion bond XP, map discovery and the horror director
##   open    wall openings like below_layout.gd: side n (z0) / s (z1) run along x, w (x0) / e (x1) along z,
##           [[from, to, height], ...] or "all". Both rooms of a connection open the same span.
##   custom  built by hand (sloped passages): slope {"axis": "x"|"z", "y0": floor at x0/z0, "y1": floor at
##           x1/z1}, stairs (visual steps over a ramp collider), cap (side closed by an end wall); y = the
##           lowest floor, ylo / yhi = the vertical detection range.
## Yaw convention (SPAWNS, props): degrees, 0 = facing north (-z), 90 = west, -90 = east, 180 = south.

const AREA_ID := "hushed_works"
const SEED := 7717

## The fixed hub -> deep connection (spec §10).
const HUB_EAST_DOOR := Vector3(40.0, -18.0, 0.0)
const HUB_EAST_DOOR_SPAN := [-1.5, 1.5]
const HUB_EAST_DOOR_HEIGHT := 3.4

const ROOMS := {
	# --- 1 Service Landing (safe) ------------------------------------------------------------------------
	"landing": {"space": 1, "zone": "hw_landing", "x0": -76.0, "x1": -64.0, "z0": -6.0, "z1": 6.0, "y": -6.0, "h": 4.6,
		"open": {"w": [[-1.8, 1.8, 3.4]], "e": [[-1.6, 1.6, 3.2]]}},
	"landing_stair": {"space": 1, "zone": "hw_landing", "x0": -80.0, "x1": -76.0, "z0": -1.8, "z1": 1.8, "y": -6.0, "h": 5.0,
		"open": {"e": "all"}},
	"landing_way": {"space": 2, "zone": "hw_landing", "x0": -64.0, "x1": -56.0, "z0": -1.6, "z1": 1.6, "y": -7.0, "h": 3.2,
		"custom": true, "slope": {"axis": "x", "y0": -6.0, "y1": -7.0}, "stairs": false, "ylo": -8.0, "yhi": -2.3},
	# --- 2 Tool Lockers ----------------------------------------------------------------------------------
	"lockers": {"space": 2, "zone": "hw_lockers", "x0": -56.0, "x1": -38.0, "z0": -8.0, "z1": 8.0, "y": -7.0, "h": 5.0,
		"open": {"w": [[-1.6, 1.6, 3.2]], "e": [[-1.6, 1.6, 3.3]]}},
	"lockers_way": {"space": 3, "zone": "hw_rails", "x0": -38.0, "x1": -30.0, "z0": -1.6, "z1": 1.6, "y": -11.0, "h": 3.3,
		"custom": true, "slope": {"axis": "x", "y0": -7.0, "y1": -11.0}, "stairs": true, "ylo": -12.0, "yhi": -3.2},
	# --- 3 Humming Rails (+ two dark, sealed false corridors and the rail junction) -------------------------
	"rails": {"space": 3, "zone": "hw_rails", "x0": -30.0, "x1": -2.0, "z0": -6.0, "z1": 6.0, "y": -11.0, "h": 7.5,
		"open": {"w": [[-1.6, 1.6, 3.3]], "e": [[-2.2, 2.2, 4.2]], "n": [[-7.0, -4.0, 3.2]],
			"s": [[-16.0, -13.0, 3.2], [-7.0, -4.0, 3.2]]}},
	"rails_false_n": {"space": 3, "zone": "hw_rails", "x0": -7.0, "x1": -4.0, "z0": -14.0, "z1": -6.0, "y": -11.0, "h": 3.2,
		"open": {"s": "all"}},
	"rails_false_s": {"space": 3, "zone": "hw_rails", "x0": -7.0, "x1": -4.0, "z0": 6.0, "z1": 14.0, "y": -11.0, "h": 3.2,
		"open": {"n": "all"}},
	"junction": {"space": 3, "zone": "hw_rails", "x0": -2.0, "x1": 5.0, "z0": -4.5, "z1": 4.5, "y": -11.0, "h": 5.5,
		"open": {"w": [[-2.2, 2.2, 4.2]], "e": [[-1.6, 1.6, 3.4]]}},
	"junction_stair": {"space": 7, "zone": "hw_rails", "x0": 5.0, "x1": 18.0, "z0": -1.6, "z1": 1.6, "y": -18.0, "h": 3.4,
		"custom": true, "slope": {"axis": "x", "y0": -11.0, "y1": -18.0}, "stairs": true, "ylo": -19.0, "yhi": -7.1},
	# --- 6 Hall of Closed Eyes (loop A: 3 -> 6 -> 5 -> 7) -------------------------------------------------------
	"eyes_way": {"space": 6, "zone": "hw_eyes", "x0": -16.0, "x1": -13.0, "z0": 6.0, "z1": 12.0, "y": -13.0, "h": 3.2,
		"custom": true, "slope": {"axis": "z", "y0": -11.0, "y1": -13.0}, "stairs": false, "ylo": -14.0, "yhi": -7.3},
	"eyes": {"space": 6, "zone": "hw_eyes", "x0": -20.0, "x1": -9.0, "z0": 12.0, "z1": 38.0, "y": -13.0, "h": 6.0,
		"open": {"n": [[-16.0, -13.0, 3.2]], "e": [[20.0, 23.0, 3.0], [31.0, 34.5, 3.4]], "w": [[26.0, 29.0, 3.2]]}},
	"eyes_route": {"space": 6, "zone": "hw_eyes", "x0": -27.0, "x1": -20.0, "z0": 25.0, "z1": 30.0, "y": -13.0, "h": 3.4,
		"open": {"e": [[26.0, 29.0, 3.2]]}},
	"bells_way": {"space": 5, "zone": "hw_bells", "x0": -9.0, "x1": 2.0, "z0": 31.0, "z1": 34.5, "y": -16.0, "h": 3.4,
		"custom": true, "slope": {"axis": "x", "y0": -13.0, "y1": -16.0}, "stairs": false, "ylo": -17.0, "yhi": -9.1},
	# --- 5 Bellmaker's Floor ------------------------------------------------------------------------------
	"bells": {"space": 5, "zone": "hw_bells", "x0": 2.0, "x1": 24.0, "z0": 24.0, "z1": 42.0, "y": -16.0, "h": 11.0,
		"open": {"w": [[31.0, 34.5, 3.4]], "n": [[19.0, 22.5, 3.4]]}},
	"bells_hub_way": {"space": 7, "zone": "hw_bells", "x0": 19.0, "x1": 22.5, "z0": 13.0, "z1": 24.0, "y": -18.0, "h": 3.4,
		"custom": true, "slope": {"axis": "z", "y0": -18.0, "y1": -16.0}, "stairs": false, "ylo": -19.0, "yhi": -12.1},
	# --- 7 Pocket Conservatory (hub, safe) ------------------------------------------------------------------
	"refuge": {"space": 7, "zone": "hw_refuge", "x0": 18.0, "x1": 40.0, "z0": -13.0, "z1": 13.0, "y": -18.0, "h": 10.0,
		"open": {"w": [[-1.6, 1.6, 3.4]], "e": [[-1.5, 1.5, 3.4]], "n": [[19.5, 23.0, 3.4], [27.0, 30.5, 3.3]],
			"s": [[19.0, 22.5, 3.4], [33.0, 36.5, 3.3]]}},
	"refuge_stair": {"space": 7, "zone": "hw_refuge", "x0": 19.5, "x1": 23.0, "z0": -18.0, "z1": -13.0, "y": -18.0, "h": 3.4,
		"custom": true, "slope": {"axis": "z", "y0": -15.0, "y1": -18.0}, "stairs": true, "cap": "n", "ylo": -19.0, "yhi": -11.1},
	# --- 4 Sluice Gallery (water line) -----------------------------------------------------------------------
	"sluice_way": {"space": 4, "zone": "hw_sluice", "x0": 27.0, "x1": 30.5, "z0": -21.0, "z1": -13.0, "y": -20.0, "h": 3.3,
		"custom": true, "slope": {"axis": "z", "y0": -20.0, "y1": -18.0}, "stairs": false, "ylo": -21.0, "yhi": -14.2},
	"sluice": {"space": 4, "zone": "hw_sluice", "x0": 14.0, "x1": 38.0, "z0": -41.0, "z1": -21.0, "y": -20.0, "h": 7.0,
		"open": {"s": [[27.0, 30.5, 3.3]]}},
	# --- 8 Light Well (light line) + the outfit / decor alcove ---------------------------------------------------
	"lightwell_way": {"space": 8, "zone": "hw_lightwell", "x0": 33.0, "x1": 36.5, "z0": 13.0, "z1": 20.0, "y": -20.0, "h": 3.3,
		"custom": true, "slope": {"axis": "z", "y0": -18.0, "y1": -20.0}, "stairs": false, "ylo": -21.0, "yhi": -14.2},
	"lightwell": {"space": 8, "zone": "hw_lightwell", "x0": 26.0, "x1": 39.0, "z0": 20.0, "z1": 34.0, "y": -20.0, "h": 16.0,
		"open": {"n": [[33.0, 36.5, 3.3]], "s": [[30.0, 34.0, 3.2]]}},
	"lightwell_alcove": {"space": 8, "zone": "hw_lightwell", "x0": 30.0, "x1": 34.0, "z0": 34.0, "z1": 38.0, "y": -20.0, "h": 3.2,
		"open": {"n": "all"}},
}

## The eight designed spaces of rooms 1-8, in critical-path order.
const SPACES := [1, 2, 3, 7, 6, 5, 4, 8]
const SPACE_NAMES := {1: "Service Landing", 2: "Tool Lockers", 3: "Humming Rails", 4: "Sluice Gallery",
	5: "Bellmaker's Floor", 6: "Hall of Closed Eyes", 7: "Pocket Conservatory", 8: "Light Well"}

## Rooms that are safe as a whole (spec §1: Landing and Refuge; the drainage stair belongs to the refuge).
const SAFE_ROOMS := ["landing", "landing_stair", "refuge", "refuge_stair"]

## Spawn points (spec §1): position (floor) + yaw (see the convention above). The last three belong to the
## deep module (rooms 9-14); these are the fallbacks used ONLY when it has not registered them (inside the
## safe hub, next to the lower ward door).
const SPAWNS := {
	"service_landing": {"pos": Vector3(-72.5, -6.0, 0.8), "yaw": -90.0},
	"works_lockers": {"pos": Vector3(-52.5, -7.0, -1.2), "yaw": -90.0},
	"refuge": {"pos": Vector3(23.2, -18.0, -8.0), "yaw": 180.0},
}
const DEEP_SPAWN_FALLBACKS := {
	"crossing_gate": {"pos": Vector3(36.6, -18.0, -3.4), "yaw": -90.0},
	"bell_throat": {"pos": Vector3(36.6, -18.0, 3.4), "yaw": -90.0},
	"vault_exit": {"pos": Vector3(35.2, -18.0, -6.4), "yaw": -90.0},
}
const REQUIRED_SPAWNS := ["service_landing", "works_lockers", "refuge", "crossing_gate", "bell_throat", "vault_exit"]

## Every Works zone (spec §7.2) in room order 1..14; the deep ones are registered even without the deep rooms.
const ZONES := ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge",
	"hw_lightwell", "hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]
## Nominal centres for deep zones that no merged room carries (zone registry only; never safe).
const DEEP_ZONE_FALLBACK_CENTRES := {
	"hw_winch": Vector3(55.0, -18.0, 0.0), "hw_crossing": Vector3(75.0, -20.0, 0.0),
	"hw_wrong_landing": Vector3(95.0, -22.0, 0.0), "hw_porch": Vector3(115.0, -24.0, 0.0),
	"hw_throat": Vector3(135.0, -26.0, 0.0), "hw_vault": Vector3(155.0, -28.0, 0.0),
}

## Checkpoint lanterns (src/world/below/checkpoint_lantern.gd, flag "cp_lit_<id>", respawn area hushed_works).
## Each lantern keeps a small safe nook around it (lit or not: it is where Krystal wakes up).
const CHECKPOINTS := {
	"hw_landing": {"pos": Vector3(-70.2, -6.0, -4.6), "spawn": "service_landing", "zone": "hw_landing"},
	"hw_lockers": {"pos": Vector3(-54.0, -7.0, -3.8), "spawn": "works_lockers", "zone": "hw_lockers"},
	"hw_refuge": {"pos": Vector3(25.4, -18.0, -5.2), "spawn": "refuge", "zone": "hw_refuge"},
}
const CHECKPOINT_SAFE_RADIUS := 3.5

## Exits (Game.change_area). The refuge shortcut opens persistently with ch2_refuge_shortcut.
const EXITS := {
	"bellhouse_stair": {"pos": Vector3(-76.9, -6.0, 0.0), "yaw": 90.0, "text": "Climb the Bellhouse stair",
		"target_area": "hallowmere_reach", "target_spawn": "bellhouse_stair", "requires_flag": "", "style": "stair"},
	"refuge_shortcut": {"pos": Vector3(21.25, -15.4, -16.9), "yaw": 0.0, "text": "Take the drainage stair up",
		"target_area": "hallowmere_reach", "target_spawn": "refuge_exit", "requires_flag": "ch2_refuge_shortcut",
		"locked_text": "The drainage stair is barred from this side.", "style": "hatch"},
}

## Authored walkable routes (floor points, joined by straight segments). Tests sweep a player capsule
## along each: the critical path 1 -> 7, loop A (3 -> 6 -> 5 -> 7), the three line branches from the hub,
## the shortcut home and the lower ward door.
const PATHS := {
	"critical": [Vector3(-72.5, -6.0, 0.8), Vector3(-67.0, -6.0, 0.0), Vector3(-64.0, -6.0, 0.0), Vector3(-56.0, -7.0, 0.0),
		Vector3(-47.0, -7.0, 0.0), Vector3(-38.0, -7.0, 0.0), Vector3(-30.0, -11.0, 0.0), Vector3(-17.0, -11.0, 0.0),
		Vector3(-2.0, -11.0, 0.0), Vector3(5.0, -11.0, 0.0), Vector3(18.0, -18.0, 0.0), Vector3(22.0, -18.0, 0.0),
		Vector3(24.0, -18.0, 5.5)],
	"landing_exit": [Vector3(-72.5, -6.0, 0.8), Vector3(-75.0, -6.0, 0.0), Vector3(-76.4, -6.0, 0.0)],
	"loop_a": [Vector3(-17.0, -11.0, 0.0), Vector3(-14.5, -11.0, 3.0), Vector3(-14.5, -11.0, 6.0), Vector3(-14.5, -13.0, 12.0),
		Vector3(-14.5, -13.0, 20.0), Vector3(-14.5, -13.0, 32.75), Vector3(-9.0, -13.0, 32.75), Vector3(2.0, -16.0, 32.75),
		Vector3(12.0, -16.0, 33.5), Vector3(12.0, -16.0, 26.5), Vector3(20.75, -16.0, 26.0), Vector3(20.75, -16.0, 24.0), Vector3(20.75, -18.0, 13.0),
		Vector3(21.0, -18.0, 8.5), Vector3(24.0, -18.0, 5.5)],
	"to_sluice": [Vector3(24.0, -18.0, 5.5), Vector3(24.0, -18.0, -3.5), Vector3(28.75, -18.0, -6.0), Vector3(28.75, -18.0, -13.0),
		Vector3(28.75, -20.0, -21.0), Vector3(28.75, -20.0, -27.0), Vector3(24.5, -20.0, -33.0), Vector3(21.6, -20.0, -36.9)],
	"sluice_valve_b": [Vector3(28.75, -20.0, -27.0), Vector3(33.0, -20.0, -32.4), Vector3(34.9, -20.0, -33.4)],
	"to_bells": [Vector3(24.0, -18.0, 5.5), Vector3(21.0, -18.0, 8.5), Vector3(20.75, -18.0, 13.0), Vector3(20.75, -16.0, 24.0),
		Vector3(20.75, -16.0, 26.0), Vector3(12.0, -16.0, 26.5), Vector3(12.0, -16.0, 33.5)],
	"to_lightwell": [Vector3(24.0, -18.0, 5.5), Vector3(31.0, -18.0, 7.0), Vector3(34.75, -18.0, 9.0), Vector3(34.75, -18.0, 13.0),
		Vector3(34.75, -20.0, 20.0), Vector3(34.75, -20.0, 23.5), Vector3(32.2, -20.0, 26.2)],
	"lightwell_mirror_b": [Vector3(34.75, -20.0, 23.5), Vector3(34.6, -20.0, 26.4)],
	"lightwell_reset": [Vector3(34.75, -20.0, 23.5), Vector3(28.6, -20.0, 22.6)],
	"to_shortcut": [Vector3(24.0, -18.0, 5.5), Vector3(23.2, -18.0, -8.0), Vector3(21.25, -18.0, -11.0), Vector3(21.25, -18.0, -13.0),
		Vector3(21.25, -15.6, -17.0)],
	"to_east_door": [Vector3(24.0, -18.0, 5.5), Vector3(33.0, -18.0, 5.0), Vector3(38.0, -18.0, 1.0), Vector3(39.2, -18.0, 0.0)],
}
## Paths that only exist once something opened (flag -> path ids): tests set the flag first.
const PATH_GATES := {"to_shortcut": "ch2_refuge_shortcut"}

# --- Room 3: Hask's Last Knock (MP §14) ----------------------------------------------------------------------
## True signal: the lantern beside the rail at the junction (a real light). False signals: cold glints behind
## the grates at the ends of the two dark, sealed corridors (no light at all).
const SIGNAL_LAMP := Vector3(2.6, -11.0, -3.3)          # post foot
const KNOCK_TRUE := Vector3(2.6, -10.6, -2.4)           # the rail beside the lamp
const KNOCK_FALSE := [Vector3(-5.5, -10.2, -13.4), Vector3(-5.5, -10.2, 13.4)]
const FALSE_GRATES_Z := [-12.9, 12.9]
const KNOCK_ARM_DISTANCE := 5.0                         # metres walked in the rail hall before she can "stop"
const KNOCK_STILL_SECONDS := [1.5, 2.0, 3.5]            # Gentle / Standard / Intense: patience before the answer
const KNOCK_GAP := 2.2                                  # seconds between the three answers

# --- Room 6: the Companion at the Wrong Door (MP §14) ---------------------------------------------------------
const WRONG_DOOR_TRIGGER_Z := 15.5                      # Krystal walks this far into the hall (z grows southward)
const WRONG_DOOR_GRATE := Vector3(-9.0, -13.0, 21.5)    # east wall, behind bars nobody can pass
const FAKE_LUMI_POS := Vector3(-6.9, -13.0, 21.5)       # inside the sealed cell
const FAKE_STILL_SECONDS := [1.0, 2.5, 6.0]             # Intense: the illusion waits longer before moving
const FAKE_FOLD_DISTANCE := 4.0
const EYES_LANTERN_FLOOR := Vector3(-17.6, -13.0, 24.0) # the misplaced lantern (on the floor)
const EYES_LANTERN_HOOK := Vector3(-19.45, -10.3, 27.5) # its empty hook on the big face = the hidden door

# --- Puzzles ------------------------------------------------------------------------------------------------
const SLUICE := {
	"valve_a": Vector3(20.4, -20.0, -38.9), "valve_b": Vector3(36.3, -20.0, -32.9),
	"basin": Vector3(34.0, -20.0, -24.4), "plaque": Vector3(25.4, -20.0, -22.2),
}
## Bell strikers (symbol -> floor position) and the order the bellmaker's plaque shows. The deep module
## reuses BELL_ORDER for the Choir's "stolen rhythm" resonators (MP §13.3 "symbol sequence taught earlier").
const BELLS := {
	"moon": Vector3(6.5, -16.0, 29.5), "leaf": Vector3(17.5, -16.0, 29.5),
	"flame": Vector3(6.5, -16.0, 37.5), "key": Vector3(17.5, -16.0, 37.5),
}
const BELL_ORDER := ["leaf", "moon", "key", "flame"]
const BELL_NAMES := {"leaf": "Leaf", "moon": "Moon", "key": "Key", "flame": "Flame"}
const BELL_BOARD := Vector3(12.0, -16.0, 24.0)          # north wall plaque (floor point below it)
const LIGHTWELL := {
	"mirror_a": Vector3(30.5, -20.0, 28.0), "mirror_b": Vector3(36.0, -20.0, 28.0),
	"target": Vector3(36.0, -20.0, 32.6), "reset": Vector3(28.0, -20.0, 21.6), "plaque": Vector3(37.8, -20.0, 21.4),
	"trunk": Vector3(32.0, -20.0, 36.9),
}

# --- Rewards (ledger) ---------------------------------------------------------------------------------------------
## The Light Well alcove's keepsake trunk. Granted through GameState.grant_once with the data/sources.gd
## REWARDS bundle of this id (by: "content"); until the integrator adds that bundle the trunk only records
## that it was found (flag below) and grants nothing, so a later bundle is still paid exactly once.
const ALCOVE_REWARD_ID := "rw_hw_lightwell_alcove"
const ALCOVE_FOUND_FLAG := "hw_lightwell_alcove"

# --- Persistent world flags of this module (besides the spec / quest flags) ----------------------------------------
const FLAG_EYES_ROUTE := "hw_eyes_route_open"           # the misplaced lantern is back on its hook
const FLAG_LOCKERS_CLEARED := "hw_lockers_cleared"      # the taught Hollow Drudge fight (spawner quest flag)
const MOMENT_KNOCK := "moment_hw_knock"
const MOMENT_WRONG_DOOR := "moment_hw_wrong_door"
const MOMENT_WRONG_DOOR_FOLDED := "moment_hw_wrong_door_folded"

# --- Resource nodes (data/sources.gd NODES: glowcap in hw_refuge / hw_lightwell >= 4, crystal in hw_refuge >= 3) --
const RESOURCES := [
	{"id": "hw_crystal_1", "kind": "crystal", "pos": Vector3(39.1, -18.0, -7.6)},
	{"id": "hw_crystal_2", "kind": "crystal", "pos": Vector3(38.6, -18.0, 4.6)},
	{"id": "hw_crystal_3", "kind": "crystal", "pos": Vector3(32.3, -18.0, -11.9)},
	{"id": "hw_glowcap_1", "kind": "glowcap", "pos": Vector3(26.8, -18.0, 12.0)},
	{"id": "hw_glowcap_2", "kind": "glowcap", "pos": Vector3(34.6, -18.0, -12.0)},
	{"id": "hw_glowcap_3", "kind": "glowcap", "pos": Vector3(26.9, -20.0, 33.1)},
	{"id": "hw_glowcap_4", "kind": "glowcap", "pos": Vector3(38.2, -20.0, 24.6)},
]

# --- Enemy spawners (spawned by id through EnemySpawner/EnemyFactory; skipped while a script is missing) -----------
const SPAWNERS := {
	"hw_sp_lockers": {"enemy": "hollow_drudge", "count": 1, "radius": 1.2, "respawn_minutes": -1.0,
		"quest_flag_on_clear": "hw_lockers_cleared", "wander_radius": 3.5, "pos": Vector3(-43.5, -7.0, 1.5),
		"clear_message": "The empty coat slumps back into its locker."},
	"hw_sp_bells": {"enemy": "bellcap_sentry", "count": 2, "radius": 2.5, "respawn_minutes": 1440.0,
		"quest_flag_on_clear": "", "wander_radius": 4.0, "pos": Vector3(12.0, -16.0, 34.0), "clear_message": ""},
}

# --- Lore notes placed in rooms 1-8 (texts: data/lore_ch2_works.gd) -----------------------------------------------
## id -> {pos (floor), text (prompt), offset (interact box centre), flag (set when read, "" = none)}
const LORE_SPOTS := {
	"lore_ch2_service_notice": {"pos": Vector3(-67.4, -6.0, 3.6), "text": "Read the notice", "offset": Vector3(0, 1.4, 0), "flag": ""},
	"lore_ch2_service_diagram": {"pos": Vector3(-39.0, -7.0, -5.0), "text": "Study the service diagram", "offset": Vector3(0, 1.4, 0), "flag": ""},
	"lore_ch2_lockers_note": {"pos": Vector3(-45.55, -7.0, 7.1), "text": "Read the note in the locker", "offset": Vector3(0, 1.1, 0), "flag": ""},
	"lore_ch2_hask_note": {"pos": Vector3(3.3, -11.0, -3.1), "text": "Read the note on the lamp post", "offset": Vector3(0, 1.3, 0), "flag": ""},
	"lore_ch2_closed_eyes": {"pos": Vector3(-19.3, -13.0, 14.4), "text": "Read the carving", "offset": Vector3(0, 1.3, 0), "flag": ""},
	"lore_ch2_eyes_route": {"pos": Vector3(-25.6, -13.0, 27.5), "text": "Read the carvers' note", "offset": Vector3(0, 0.9, 0), "flag": ""},
	"lore_ch2_bell_order": {"pos": Vector3(12.0, -16.0, 24.9), "text": "Read the bellmaker's plaque", "offset": Vector3(0, 1.3, 0), "flag": ""},
	"lore_ch2_sluice_chalk": {"pos": Vector3(14.75, -20.0, -26.4), "text": "Read the chalk on the slate", "offset": Vector3(0, 0.9, 0), "flag": ""},
	"lore_ch2_sluice_plaque": {"pos": Vector3(25.4, -20.0, -22.2), "text": "Read the sluice plaque", "offset": Vector3(0, 1.3, 0), "flag": ""},
	"lore_ch2_lightwell_plaque": {"pos": Vector3(37.8, -20.0, 21.4), "text": "Read the plaque", "offset": Vector3(0, 1.3, 0), "flag": ""},
	"lore_ch2_hask_refuge_note": {"pos": Vector3(37.8, -18.0, -10.9), "text": "Read the note tucked in the planter", "offset": Vector3(0, 0.8, 0), "flag": "ch2_hask_note_found"},
}
const REFUGE_RECORD := Vector3(19.2, -18.0, -5.6)       # the Foreman's refuge record (lectern)
const SHORTCUT_LEVER := Vector3(24.6, -18.0, -12.2)     # unbars the drainage stair (ch2_refuge_shortcut)
const WORKBENCH := Vector3(37.6, -18.0, 9.6)            # the miners' workbench (crafting_station "workbench")

# --- Horror director anchors: [room, zone, kind, position] (kinds: data/horror_events.gd WORKS_EVENTS anchors) ------
const ANCHORS := [
	["rails", "hw_rails", "sound", Vector3(-16.0, -8.0, -5.0)], ["rails", "hw_rails", "sound", Vector3(-25.0, -7.5, 4.6)],
	["rails", "hw_rails", "doorway", Vector3(-5.5, -10.8, -5.6)], ["rails", "hw_rails", "doorway", Vector3(-14.5, -10.8, 5.6)],
	["rails", "hw_rails", "doorway", Vector3(-29.4, -10.8, 0.0)], ["rails", "hw_rails", "floor", Vector3(-21.0, -11.0, 0.0)],
	["sluice", "hw_sluice", "sound", Vector3(16.0, -17.0, -39.4)], ["sluice", "hw_sluice", "sound", Vector3(37.0, -17.5, -37.0)],
	["sluice", "hw_sluice", "doorway", Vector3(28.75, -19.8, -21.6)], ["sluice", "hw_sluice", "floor", Vector3(19.0, -20.0, -31.0)],
	["bells", "hw_bells", "sound", Vector3(4.0, -12.0, 40.5)], ["bells", "hw_bells", "sound", Vector3(22.5, -12.0, 25.5)],
	["bells", "hw_bells", "doorway", Vector3(2.6, -15.8, 32.75)], ["bells", "hw_bells", "floor", Vector3(12.0, -16.0, 40.0)],
	["lightwell", "hw_lightwell", "sound", Vector3(27.0, -14.0, 33.0)], ["lightwell", "hw_lightwell", "doorway", Vector3(34.75, -19.8, 20.6)],
	["lightwell", "hw_lightwell", "floor", Vector3(33.0, -20.0, 31.0)],
]


## Spawn transform (floor + 0.05) facing along -Z rotated by yaw.
static func spawn_xform(id: String) -> Transform3D:
	var s: Dictionary = SPAWNS.get(id, DEEP_SPAWN_FALLBACKS.get(id, SPAWNS["service_landing"]))
	var p: Vector3 = s["pos"]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"]))), p + Vector3(0.0, 0.05, 0.0))
