extends RefCounted
## Hushed Works, rooms 9-14 ("the deep Works", works module B; docs/CHAPTER_TWO_SPEC.md §7.4, §10).
## Pure data in the shared Builder room-table format of src/world/below/below_layout.gd, so the Works area
## script merges ROOMS with data/works_layout.gd (rooms 1-8) into one table for below_builder.gd and then
## calls res://src/world/works/rooms_deep.gd build(area, builder) BEFORE builder.finish().
## Coordinates: metres, x east, z south, y up. Rooms 9-14 live in x [40, 170], floors y in [-34, -6].
## Room 9 starts at the hub door centre HUB_DOOR (40, -18, 0) and opens toward +x (its west side is "all":
## the hub's east wall, x 40..41, carries the door; see the header of rooms_deep.gd for the hub contract).
## Walls: side "n" = the z0 wall, "s" = z1, "w" = x0, "e" = x1, built OUTSIDE the box (1 m thick). Openings
## are [from, to, height] along the wall (x for n/s, z for w/e), from the room floor. "all" = no wall.
## Adjacent boxes share their boundary coordinate; exactly one of the two builds the wall.
## Extra keys (read by rooms_deep.gd / the area, ignored by the Builder): "space" (design room 9..14),
## "zone" (spec §7.2 zone id), "safe" (whole room is a safe zone), "custom" (built by hand, not shell()),
## "ylo"/"yhi" (vertical detection range of sloped rooms), "slope" in the format of data/works_layout.gd:
## {"axis": "x"|"z", "y0": floor at x0/z0, "y1": floor at x1/z1} (+ "stairs": true: visual steps over a ramp).

const HUB_DOOR := Vector3(40.0, -18.0, 0.0)
const X_MIN := 40.0
const X_MAX := 170.0
const Y_MIN := -34.0
const Y_MAX := -6.0
const AREA_ID := "hushed_works"

## Seed of the deep rooms' own dressing RNG (the builder's rng is saved/restored around build()).
const DRESS_SEED := 91409

const ROOMS := {
	# --- 9 Threaded Winch: a TALL iron-and-timber winch hall (12 m), recent Weaver trail, overhead gantry.
	"hw_winch_way": {"space": "winch", "zone": "hw_winch", "x0": 40.0, "x1": 44.0, "z0": -2.0, "z1": 2.0, "y": -18.0, "h": 3.6,
		"open": {"w": "all", "e": "all"}},
	"hw_winch": {"space": "winch", "zone": "hw_winch", "x0": 44.0, "x1": 62.0, "z0": -9.0, "z1": 9.0, "y": -18.0, "h": 12.0,
		"open": {"w": [[-1.6, 1.6, 3.6]], "e": [[-1.6, 1.6, 3.4]], "s": [[47.0, 51.0, 3.0]]}},
	"hw_winch_nook": {"space": "winch", "zone": "hw_winch", "x0": 46.6, "x1": 51.4, "z0": 9.0, "z1": 12.5, "y": -18.0, "h": 3.0,
		"open": {"n": "all"}},
	# Checkpoint `crossing_gate`, BEFORE the arena (low 4 m service gate room).
	"hw_crossing_gate": {"space": "crossing_gate", "zone": "hw_winch", "x0": 62.0, "x1": 68.0, "z0": -2.4, "z1": 2.4, "y": -18.0, "h": 4.0,
		"open": {"w": "all", "e": "all"}},
	# --- 10 Weaver's Crossing: a long cold slate hall (14 m) spanned by a broad railed service bridge over an
	# 8 m sluice pit (a catch floor with a stair back up: no bottomless drop).
	"hw_crossing": {"space": "crossing", "zone": "hw_crossing", "x0": 68.0, "x1": 108.0, "z0": -12.0, "z1": 12.0, "y": -18.0, "h": 14.0,
		"custom": true, "open": {"w": [[-1.6, 1.6, 3.4]], "e": [[-1.6, 1.6, 3.4]], "n": [[104.6, 107.4, 3.0]]}},
	"hw_crossing_pit": {"space": "crossing", "zone": "hw_crossing", "x0": 72.0, "x1": 104.0, "z0": -12.0, "z1": 12.0, "y": -26.0, "h": 8.0,
		"custom": true, "ylo": -27.0, "yhi": -17.5, "open": {}},
	"hw_matron_route": {"space": "crossing", "zone": "hw_crossing", "x0": 104.2, "x1": 107.8, "z0": -16.0, "z1": -12.0, "y": -18.0, "h": 3.0,
		"open": {"s": "all"}},
	"hw_crossing_exit": {"space": "wrong_landing", "zone": "hw_wrong_landing", "x0": 108.0, "x1": 118.0, "z0": -2.0, "z1": 2.0, "y": -22.0, "h": 8.0,
		"custom": true, "ylo": -23.0, "yhi": -13.5, "slope": {"axis": "x", "y0": -18.0, "y1": -22.0}, "stairs": true,
		"open": {"w": "all", "e": "all"}},
	# --- 11 The Wrong Landing: LOW (4.4 m) and wide, sickly green gas-light, two identical lift cages.
	"hw_wrong_landing": {"space": "wrong_landing", "zone": "hw_wrong_landing", "x0": 118.0, "x1": 140.0, "z0": -10.0, "z1": 10.0, "y": -22.0, "h": 4.4,
		"open": {"w": [[-1.6, 1.6, 3.4]], "n": [[121.4, 124.6, 3.4], [131.4, 134.6, 3.4]], "s": [[127.4, 130.6, 3.4]], "e": [[1.2, 3.6, 3.0]]}},
	"hw_lift_real": {"space": "wrong_landing", "zone": "hw_wrong_landing", "x0": 121.0, "x1": 125.0, "z0": -14.4, "z1": -10.0, "y": -22.0, "h": 4.4,
		"open": {"s": "all"}},
	"hw_lift_false": {"space": "wrong_landing", "zone": "hw_wrong_landing", "x0": 131.0, "x1": 135.0, "z0": -14.4, "z1": -10.0, "y": -22.0, "h": 4.4,
		"open": {"s": "all"}},
	# Where the false lift jams: a short service siding that walks straight back into the landing.
	"hw_wrong_siding": {"space": "wrong_landing", "zone": "hw_wrong_landing", "x0": 140.0, "x1": 148.0, "z0": -10.0, "z1": 4.0, "y": -22.0, "h": 3.2,
		"open": {"w": "all"}},
	# --- 12 The Borrowed Porch: a huge dark violet cavern (11 m) with a generic cottage facade standing in it.
	"hw_porch_way": {"space": "porch", "zone": "hw_porch", "x0": 127.0, "x1": 131.0, "z0": 10.0, "z1": 18.0, "y": -22.0, "h": 3.6,
		"open": {"n": "all", "s": "all"}},
	"hw_porch": {"space": "porch", "zone": "hw_porch", "x0": 108.0, "x1": 140.0, "z0": 18.0, "z1": 44.0, "y": -22.0, "h": 11.0,
		"open": {"n": [[127.4, 130.6, 3.4]], "e": [[31.6, 35.4, 3.6]]}},
	# The true stair (hidden by the illusion until ch2_false_home_revealed).
	"hw_true_stair": {"space": "throat", "zone": "hw_throat", "x0": 140.0, "x1": 152.0, "z0": 31.2, "z1": 35.8, "y": -28.0, "h": 9.4,
		"custom": true, "ylo": -29.0, "yhi": -18.0, "slope": {"axis": "x", "y0": -22.0, "y1": -28.0}, "stairs": true,
		"open": {"w": "all", "e": "all"}},
	# --- 13 Bell Throat: narrow and very tall (16 m), warm candle-gold, hanging bells. SAFE.
	"hw_throat": {"space": "throat", "zone": "hw_throat", "safe": true, "x0": 152.0, "x1": 162.0, "z0": 18.0, "z1": 44.0, "y": -28.0, "h": 16.0,
		"open": {"w": [[31.6, 35.4, 3.6]], "s": [[155.4, 158.6, 3.6]]}},
	"hw_vault_way": {"space": "vault", "zone": "hw_vault", "x0": 155.0, "x1": 159.0, "z0": 44.0, "z1": 52.0, "y": -32.0, "h": 7.6,
		"custom": true, "ylo": -33.0, "yhi": -24.0, "slope": {"axis": "z", "y0": -28.0, "y1": -32.0}, "stairs": true,
		"open": {"n": "all", "s": "all"}},
	# --- 14 Choir Vault: a large CIRCULAR pale vault (radius 12.4, 16 m high); the box only bounds it.
	"hw_vault": {"space": "vault", "zone": "hw_vault", "x0": 144.0, "x1": 170.0, "z0": 52.0, "z1": 78.0, "y": -32.0, "h": 16.0,
		"custom": true, "open": {"n": [[155.4, 158.6, 3.6]], "s": [[155.4, 158.6, 3.6]]}},
	"hw_vault_exit": {"space": "vault", "zone": "hw_vault", "x0": 155.0, "x1": 159.0, "z0": 78.0, "z1": 84.0, "y": -32.0, "h": 4.0,
		"open": {"n": "all"}},
}

## Design rooms (MP §10 numbering) -> their main room id (the zone id of the step targets, spec §7.2).
const DESIGN_ROOMS := {9: "hw_winch", 10: "hw_crossing", 11: "hw_wrong_landing", 12: "hw_porch", 13: "hw_throat", 14: "hw_vault"}

## Spawn points (position on the floor + facing yaw in degrees: 0 = north/-z, -90 = east, 180 = south).
## crossing_gate / bell_throat / vault_exit are contract spawns (spec §1); the others belong to this module.
const SPAWNS := {
	"crossing_gate": {"pos": Vector3(64.2, -18.0, 0.9), "yaw": -90.0},
	"bell_throat": {"pos": Vector3(154.9, -28.0, 33.5), "yaw": -90.0},
	"vault_exit": {"pos": Vector3(157.0, -32.0, 80.0), "yaw": 0.0},
	"hw_wrong_siding": {"pos": Vector3(146.0, -22.0, -7.5), "yaw": 180.0},
	"hw_lift_landing": {"pos": Vector3(123.0, -22.0, -7.6), "yaw": 180.0},
}

## Checkpoint lanterns (checkpoint_lantern.gd, area "hushed_works"): id -> lantern position, spawn, zone,
## lantern arm yaw (degrees; 0 = the lantern hangs toward +z).
const CHECKPOINTS := {
	"hw_crossing_gate": {"pos": Vector3(65.6, -18.0, -1.75), "spawn": "crossing_gate", "zone": "hw_winch", "yaw": 0.0},
	"hw_bell_throat": {"pos": Vector3(153.0, -28.0, 30.2), "spawn": "bell_throat", "zone": "hw_throat", "yaw": 90.0},
}
const SAFE_RADIUS := 4.0
## Bell Throat is safe as a whole (circle covering the room, |dy| < 3 like the Below).
const THROAT_SAFE := {"center": Vector3(157.0, -28.0, 31.0), "radius": 13.5}

## Winch threads (deep_thread.gd). "axis" = the direction the veil spans; burned state persists in "flag".
const THREADS := {
	"hw_thread_nook": {"pos": Vector3(49.0, -18.0, 9.3), "axis": "x", "width": 4.0, "height": 3.0, "flag": "hw_thread_nook_burned", "teach": true},
	"hw_thread_winch_exit": {"pos": Vector3(61.6, -18.0, 0.0), "axis": "z", "width": 3.2, "height": 3.4, "flag": "hw_thread_winch_exit_burned"},
}

## Weaver's Crossing arena (crossing_arena.gd; the crossing_matron boss module reads these through the
## arena node's API, see src/world/works/deep/crossing_arena.gd).
const CROSSING := {
	"center": Vector3(88.0, -18.0, 0.0),
	"radius": 14.5,
	"bridge": Rect2(72.0, -5.0, 32.0, 10.0),      # walkable deck (x, z, w, d), top at y -18
	"rail": 4.8,                                   # |z| of the guardrails' inner face
	"deck_y": -18.0,
	"pit_y": -26.0,
	"ceiling_y": -4.0,
	"anchors": [Vector3(78.0, -5.6, -3.9), Vector3(88.0, -5.6, 3.9), Vector3(98.0, -5.6, -3.9),
		Vector3(83.0, -5.4, 0.0), Vector3(93.0, -5.4, 0.0)],
	"braziers": [Vector3(78.0, -18.0, -4.05), Vector3(88.0, -18.0, 4.05), Vector3(98.0, -18.0, -4.05)],
	"exit_veil": Vector3(107.6, -18.0, 0.0),        # thick threads across the east door until cleared
	"matron_gate": Vector3(106.0, -18.0, -12.5),     # the Matron's deeper route (closes after the fight)
	"crack": Vector3(106.0, -16.2, -14.5),
	"trigger_x": 73.0,                              # stepping onto the bridge past this starts the fight
	"pit_stair": [Vector3(72.0, -18.0, 10.5), Vector3(92.0, -26.0, 10.5)],
}

## Choir Vault arena (choir_arena.gd).
const VAULT := {
	"center": Vector3(157.0, -32.0, 65.0),
	"radius": 12.4,                                 # inner face of the ring wall
	"perimeter": 10.4,                              # the safe walkable ring is radius >= this
	"trigger_radius": 10.0,
	"anchors": [Vector3(150.94, -32.0, 61.5), Vector3(163.06, -32.0, 61.5), Vector3(157.0, -32.0, 72.0)],
	# the resonator frames (5.7 m wide) stand just INSIDE the perimeter walk (radius 9.3): the whole ring
	# radius 10.4..12.4 stays clear all the way round (>= 1.2 m wide everywhere, test_works_deep_arenas)
	"resonators": [Vector3(147.7, -32.0, 65.0), Vector3(166.3, -32.0, 65.0)],
	"entry_angle": -90.0,                           # degrees in the XZ plane (x = cos, z = sin): north
	"exit_angle": 90.0,                             # south, toward the exit alcove
	"door_half_angle": 8.5,
	"exit_gate": Vector3(157.0, -32.0, 78.3),
	"exit_lift": Vector3(157.0, -32.0, 82.6),
}
## Where the vault exit lift goes (after ch2_choir_defeated): straight up to the Reach's Sunken Bellhouse
## (the chapter continues with "Lanterns on Every Road" there). vault_exit stays the in-Works spawn.
const VAULT_EXIT_TARGET := {"area": "hallowmere_reach", "spawn": "bellhouse_stair"}
## Lifts back to the Pocket Conservatory (hub). "refuge" is registered by the hub module.
const REFUGE_SPAWN := "refuge"

## Bell Throat stations.
const THROAT := {
	"supplies": Vector3(160.7, -28.0, 36.5),
	"note": Vector3(160.8, -28.0, 28.4),         # lore_ch2_bell_throat_note (data/lore_ch2_works.gd)
	"inscription": Vector3(157.0, -28.0, 43.3),  # lore_ch2_before_choir, carved over the vault stair
	"lift": Vector3(160.6, -28.0, 40.6),         # the bell-rope lift (return / continue choice)
	"practice_anchor": Vector3(157.0, -28.0, 24.6),
	"practice_forms": [Vector3(154.3, -28.0, 20.4), Vector3(157.0, -28.0, 20.0), Vector3(159.7, -28.0, 20.4)],
	"practice_genuine": 2,
	"order_board": Vector3(161.9, -28.0, 31.75),  # the bellmakers' order, on the east wall between two pilasters
}
## Reward ledger id of the Bell Throat's final supplies (a data/sources.gd REWARDS "content" bundle; the
## fallback below is used until the integrator adds it).
const THROAT_SUPPLIES_ID := "rw_hw_throat_supplies"
const THROAT_SUPPLIES_FALLBACK := {"items": {"hearty_stew": 2, "berry_snack": 2}, "flags": ["hw_throat_supplies"]}
const LORE_THROAT_NOTE := "lore_ch2_bell_throat_note"
const LORE_BEFORE_CHOIR := "lore_ch2_before_choir"
## MP §17 "Before the Choir" (verbatim), shown if data/lore_ch2_works.gd is not in the build yet.
const BEFORE_CHOIR_LINE := "It has learned a welcome. It has not learned a home."

## The Wrong Landing: two identical cages; only the real one's lamp lights its landing plate.
const LIFTS := {
	"hw_lift_real": {"pos": Vector3(123.0, -22.0, -12.3), "kind": "true"},
	"hw_lift_false": {"pos": Vector3(133.0, -22.0, -12.3), "kind": "false"},
}

## The Borrowed Porch.
const PORCH := {
	"facade": Vector3(122.0, -22.0, 32.0),       # centre of the porch deck front; the facade faces north (-z)
	"flame": Vector3(137.6, -22.0, 30.3),        # the anchored flame (a real light), beside the true stair
	"illusion": Vector3(139.2, -22.0, 33.5),     # the painted hedge-and-fence flat over the stair mouth
	"fragment_radius": 9.0,
	"fragment_seconds": 5.0,
}

## Scratching Above the Winch: the visible overhead route (a service gantry) the pale shape crosses.
const WINCH := {
	"gantry_y": -11.2,
	"gantry_z": -6.8,
	"gantry_x": [44.6, 61.4],
	"trigger_x": 47.5,
	"dust": [Vector3(49.0, -11.6, -6.8), Vector3(53.5, -11.6, -6.8), Vector3(57.5, -11.6, -6.8)],
	"drum": Vector3(53.0, -18.0, -4.6),
	"switch": Vector3(49.0, -18.0, 12.0),
}

## Room 9's winch cage: loop B the other way. Once a lift UP has been ridden (the Wrong Landing's real lift
## or the Bell Throat's bell-rope lift set "flag"), the cage beside the drum - one room from the hub door -
## rides back DOWN to the Wrong Landing, or (once she has been there, "throat_seen_flag") to the Bell Throat.
## The node faces south (its mouth and landing plate toward +z, into the hall).
const WINCH_CAGE := {"pos": Vector3(58.0, -18.0, -7.2), "flag": "hw_winch_cage_free", "throat_seen_flag": "hw_throat_seen",
	"landing_spawn": "hw_lift_landing", "throat_spawn": "bell_throat"}

## Anticipation / passes per horror intensity (0 Gentle, 1 Standard, 2 Intense).
const WINCH_TIMING := {
	0: {"anticipation": 2.5, "passes": 1, "approach": false},
	1: {"anticipation": 3.5, "passes": 2, "approach": false},
	2: {"anticipation": 6.0, "passes": 2, "approach": true},
}

## Light temperature per zone, in the Works area's mood format (area.register_mood(zone, mood, ambience):
## fog albedo, fog emission, ambient colour, fog density) - six clearly different places.
const MOODS := {
	"hw_winch": {"fog": Color(0.62, 0.5, 0.42), "emit": Color(0.022, 0.014, 0.01), "ambient": Color("3a2e2a"), "density": 0.014},
	"hw_crossing": {"fog": Color(0.42, 0.5, 0.66), "emit": Color(0.01, 0.014, 0.026), "ambient": Color("26303f"), "density": 0.017},
	"hw_wrong_landing": {"fog": Color(0.46, 0.62, 0.52), "emit": Color(0.012, 0.022, 0.016), "ambient": Color("25352d"), "density": 0.018},
	"hw_porch": {"fog": Color(0.48, 0.4, 0.62), "emit": Color(0.014, 0.01, 0.024), "ambient": Color("211b2a"), "density": 0.02},
	"hw_throat": {"fog": Color(0.7, 0.58, 0.42), "emit": Color(0.026, 0.02, 0.012), "ambient": Color("3e3224"), "density": 0.009},
	"hw_vault": {"fog": Color(0.6, 0.54, 0.7), "emit": Color(0.018, 0.014, 0.026), "ambient": Color("2e2a3a"), "density": 0.013},
}
## Ambience loops per zone (existing loops only).
const AMBIENCE := {"hw_winch": "amb_mine", "hw_crossing": "amb_silk", "hw_wrong_landing": "amb_ruins",
	"hw_porch": "amb_ruins", "hw_throat": "amb_stream", "hw_vault": "amb_boss"}

## Bell symbols: room 5 (Bellmaker's Floor, works module C7) teaches the set - data/works_layout.gd
## BELL_ORDER (+ BELL_NAMES), or a BELL_SYMBOLS list ([{"id", "name", "caption"}] or [ids]). These defaults
## are only used when that file is missing.
const SYMBOLS_SOURCE := "res://data/works_layout.gd"
const DEFAULT_SYMBOLS := [
	{"id": "leaf", "name": "Leaf", "caption": "[the Leaf plate rings softly]"},
	{"id": "moon", "name": "Moon", "caption": "[the Moon plate hums low and round]"},
	{"id": "key", "name": "Key", "caption": "[the Key plate clinks bright and small]"},
	{"id": "flame", "name": "Flame", "caption": "[the Flame plate rings warm]"},
]

## Critical path (floor points) from the hub door to the Choir Vault centre. The porch point needs the
## illusion revealed (ch2_false_home_revealed); the crossing points need the crossing cleared for the exit.
const CRITICAL_PATH := [
	Vector3(40.3, -18.0, 0.0), Vector3(42.0, -18.0, 0.0), Vector3(45.0, -18.0, 0.0), Vector3(52.0, -18.0, 2.0),
	Vector3(60.4, -18.0, 0.0), Vector3(63.5, -18.0, 0.0), Vector3(66.5, -18.0, 0.0), Vector3(69.0, -18.0, 0.0),
	Vector3(74.0, -18.0, 0.0), Vector3(88.0, -18.0, 0.0), Vector3(102.0, -18.0, 0.0), Vector3(106.0, -18.0, 0.0),
	Vector3(107.9, -18.0, 0.0), Vector3(113.0, -20.0, 0.0), Vector3(117.8, -21.9, 0.0), Vector3(120.0, -22.0, 0.0),
	Vector3(126.0, -22.0, 3.0), Vector3(129.0, -22.0, 8.0), Vector3(129.0, -22.0, 12.0), Vector3(129.0, -22.0, 17.0),
	Vector3(129.0, -22.0, 20.0), Vector3(133.0, -22.0, 27.0), Vector3(136.5, -22.0, 33.5), Vector3(139.8, -22.0, 33.5),
	Vector3(146.0, -25.0, 33.5), Vector3(151.8, -27.9, 33.5), Vector3(154.0, -28.0, 33.5), Vector3(157.0, -28.0, 37.0),
	Vector3(157.0, -28.0, 43.8), Vector3(157.0, -30.0, 48.0), Vector3(157.0, -32.0, 52.3), Vector3(157.0, -32.0, 58.0),
	Vector3(157.0, -32.0, 65.0),
]

## Side paths that must be walkable too (nook, both lift fronts, the siding loop back, the pit stair,
## the Bell Throat stations, the vault exit after victory, the winch cage plate, the bellmakers' order board).
## Append only: tests index the siding walk-back as SIDE_PATHS[3].
const SIDE_PATHS := [
	[Vector3(49.0, -18.0, 4.0), Vector3(49.0, -18.0, 8.0), Vector3(49.0, -18.0, 11.2)],
	[Vector3(123.0, -22.0, -2.0), Vector3(123.0, -22.0, -8.2)],
	[Vector3(133.0, -22.0, -2.0), Vector3(133.0, -22.0, -8.2)],
	[Vector3(146.0, -22.0, -7.5), Vector3(146.0, -22.0, 2.4), Vector3(142.0, -22.0, 2.4), Vector3(139.0, -22.0, 2.4), Vector3(134.0, -22.0, 2.0)],
	[Vector3(69.5, -18.0, 10.5), Vector3(72.5, -18.2, 10.5), Vector3(82.0, -22.0, 10.5), Vector3(91.8, -25.9, 10.5), Vector3(95.0, -26.0, 10.5), Vector3(88.0, -26.0, 0.0)],
	[Vector3(154.0, -28.0, 33.5), Vector3(157.0, -28.0, 27.0), Vector3(157.0, -28.0, 25.6)],
	[Vector3(157.0, -28.0, 33.5), Vector3(159.4, -28.0, 36.5)],
	[Vector3(157.0, -32.0, 65.0), Vector3(155.3, -32.0, 69.5), Vector3(155.3, -32.0, 74.5), Vector3(157.0, -32.0, 77.6), Vector3(157.0, -32.0, 80.0)],
	[Vector3(55.0, -18.0, 1.0), Vector3(58.0, -18.0, -1.5), Vector3(58.0, -18.0, -5.4)],
	[Vector3(157.0, -28.0, 33.5), Vector3(160.4, -28.0, 31.75)],
]

## Director anchors for the Works director (data/horror_events.gd WORKS_EVENTS): hw_winch "hw_winch_dust"
## needs ceiling anchors (0.3 m under the ceiling, >= 3 m clear sideways), hw_wrong_landing "hw_wisp_drift"
## needs spawn anchors (floor, clear, off the critical sightlines). The porch / crossing / throat / vault are
## quiet zones (no events): their anchors are sound/doorway only. [room, zone, kind, position].
const ANCHORS := [
	["hw_winch", "hw_winch", "ceiling", Vector3(48.5, -6.3, 3.0)], ["hw_winch", "hw_winch", "ceiling", Vector3(57.5, -6.3, 1.0)],
	["hw_winch", "hw_winch", "sound", Vector3(58.0, -15.5, 6.0)], ["hw_winch", "hw_winch", "doorway", Vector3(61.0, -17.8, 0.0)],
	["hw_wrong_landing", "hw_wrong_landing", "sound", Vector3(128.0, -20.0, -8.0)],
	["hw_wrong_landing", "hw_wrong_landing", "doorway", Vector3(129.0, -21.8, 9.0)],
	["hw_wrong_landing", "hw_wrong_landing", "spawn", Vector3(137.4, -22.0, -6.8)],
	["hw_wrong_landing", "hw_wrong_landing", "spawn", Vector3(120.4, -22.0, -7.2)],
	["hw_porch", "hw_porch", "sound", Vector3(114.0, -19.0, 40.0)], ["hw_porch", "hw_porch", "doorway", Vector3(129.0, -21.8, 19.0)],
]


# --- Static helpers (bind to this script's ROOMS) ------------------------------------------------------

static func spawn_xform(id: String) -> Transform3D:
	var s: Dictionary = SPAWNS.get(id, SPAWNS["crossing_gate"])
	var p: Vector3 = s["pos"]
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(s["yaw"]))), p + Vector3(0.0, 0.05, 0.0))


static func room_y_range(r: Dictionary) -> Vector2:
	var y: float = float(r["y"])
	var lo: float = float(r.get("ylo", y - 1.0))
	var hi: float = float(r.get("yhi", y + float(r["h"]) + 0.5))
	return Vector2(lo, hi)


## Room id containing a position ("" if none). The vault is a circle.
static func room_at(pos: Vector3) -> String:
	for id in ROOMS:
		var r: Dictionary = ROOMS[id]
		var yr := room_y_range(r)
		if pos.y < yr.x or pos.y > yr.y:
			continue
		if id == "hw_vault":
			var c: Vector3 = VAULT["center"]
			if Vector2(pos.x - c.x, pos.z - c.z).length() <= float(VAULT["radius"]) + 1.0:
				return id
			continue
		if pos.x >= float(r["x0"]) and pos.x <= float(r["x1"]) and pos.z >= float(r["z0"]) and pos.z <= float(r["z1"]):
			return id
	return ""


## Nearest room by horizontal distance to its box (a point slightly outside every room).
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


static func zone_of_room(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("zone", ""))


static func space_of(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("space", ""))


## Every zone id of the deep rooms (spec §7.2: hw_winch, hw_crossing, hw_wrong_landing, hw_porch, hw_throat, hw_vault).
static func zone_ids() -> Array:
	var out: Array = []
	for id in ROOMS:
		var z := String(ROOMS[id]["zone"])
		if not out.has(z):
			out.append(z)
	return out


## Floor height of a room at `pos`: sloped rooms interpolate their "slope" {axis, y0, y1}, else the floor y.
static func floor_y_at(room_id: String, pos: Vector3) -> float:
	var r: Dictionary = ROOMS.get(room_id, {})
	if r.is_empty():
		return pos.y
	var s: Variant = r.get("slope")
	if not (s is Dictionary):
		return float(r["y"])
	var sd: Dictionary = s
	var t: float
	if String(sd.get("axis", "x")) == "x":
		t = inverse_lerp(float(r["x0"]), float(r["x1"]), pos.x)
	else:
		t = inverse_lerp(float(r["z0"]), float(r["z1"]), pos.z)
	return lerpf(float(sd["y0"]), float(sd["y1"]), clampf(t, 0.0, 1.0))


## The two floor end points (centre line) of a sloped room: [start at x0/z0, end at x1/z1].
static func slope_ends(room_id: String) -> Array:
	var r: Dictionary = ROOMS[room_id]
	var sd: Dictionary = r["slope"]
	var cx := (float(r["x0"]) + float(r["x1"])) * 0.5
	var cz := (float(r["z0"]) + float(r["z1"])) * 0.5
	if String(sd.get("axis", "x")) == "x":
		return [Vector3(float(r["x0"]), float(sd["y0"]), cz), Vector3(float(r["x1"]), float(sd["y1"]), cz)]
	return [Vector3(cx, float(sd["y0"]), float(r["z0"])), Vector3(cx, float(sd["y1"]), float(r["z1"]))]


## The bell symbol set taught in room 5, normalised to [{"id", "name", "caption"}] in the taught order:
## data/works_layout.gd BELL_SYMBOLS, else its BELL_ORDER + BELL_NAMES, else DEFAULT_SYMBOLS.
static func bell_symbols() -> Array:
	var out: Array = []
	var consts: Dictionary = {}
	if ResourceLoader.exists(SYMBOLS_SOURCE):
		var s: Script = load(SYMBOLS_SOURCE)
		if s != null:
			consts = s.get_script_constant_map()
	var src: Variant = consts.get("BELL_SYMBOLS", consts.get("BELL_ORDER", null))
	var names: Variant = consts.get("BELL_NAMES", {})
	if src is Array:
		for e in src:
			if e is Dictionary and (e as Dictionary).has("id"):
				var d: Dictionary = e
				var nm := String(d.get("name", String(d["id"]).capitalize()))
				out.append({"id": String(d["id"]), "name": nm, "caption": String(d.get("caption", _caption_for(String(d["id"]), nm)))})
			elif e is String or e is StringName:
				var id := String(e)
				var nm2 := String((names as Dictionary).get(id, id.capitalize())) if names is Dictionary else id.capitalize()
				out.append({"id": id, "name": nm2, "caption": _caption_for(id, nm2)})
	if out.size() < 2:
		out = DEFAULT_SYMBOLS.duplicate(true)
	return out


static func _caption_for(id: String, display: String) -> String:
	for d in DEFAULT_SYMBOLS:
		if String(d["id"]) == id:
			return String(d["caption"])
	return "[the %s plate rings]" % display
