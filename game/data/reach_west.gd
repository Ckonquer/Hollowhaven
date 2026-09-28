extends RefCounted
## Hallowmere Reach - west districts (module C2): Pumpkintide Orchard, Thimblebrook Pools, The Candleyard.
## docs/CHAPTER_TWO_SPEC.md §7.2 / §10; MP §9, §11 (steps 4-5), §12, §14, §15, §16, §17.
## Every coordinate here is ABSOLUTE Reach metres on the XZ plane (x = east, z = south; Vector2(x, z)),
## inside the landmark circles of data/hallowmere_layout.gd. Heights always come from the region
## (area.height_at), so the same data works on the placeholder floor and on the real terrain.
## Built by src/world/reach/districts/{orchard,pools,candleyard}.gd (+ src/world/reach/west/*).
##
## Stable ids (saved state): harvest nodes hr_<kind>_<n> (GameState.depleted), spawners hr_sp_* (flags
## spawner_cleared_<id>, depleted spawner_<id>), flags below. NEVER renumber, reorder or reuse them.

const AREA_ID := "hallowmere_reach"
const Reach := preload("res://data/hallowmere_layout.gd")

const ORCHARD := "hr_orchard"
const POOLS := "hr_pools"
const CANDLEYARD := "hr_candleyard"

## The orchard Lantern Road arch belongs to the region module: nothing of ours stands this close to it.
const ORCHARD_ARCH := Vector2(-60, 50)
const ARCH_CLEARANCE := 7.0
## Nothing of ours may be closer than this to the optional Commons outpost build area (player crops).
const OUTPOST_CENTER := Vector2(-16, 54)
const OUTPOST_CLEARANCE := 20.0

# --- Flags --------------------------------------------------------------------------------------------
## Read by the Chapter Two quest layer (data/quests_ch2.gd header) - set here, rewards paid there.
const FLAG_FOUND_LAMP := "ch2_found_orchard_lamp"
const FLAG_LAMP_LIT := "ch2_garden_lamp_lit"
## Read by the optional log (data/optional_goals.gd table) - set here, rewards paid there.
const FLAG_NOTE_1 := "ch2_groundskeeper_note_1"
const FLAG_NOTE_2 := "ch2_groundskeeper_note_2"
const FLAG_LIGHT_PLACED := "ch2_groundskeeper_light_placed"
const FLAG_HAT := "ch2_witch_hat_found"
## Our own world-state flags (requested for the flag tables; nothing else needs to read them).
const FLAG_IRRIGATED := "ch2_orchard_irrigated"            # latched the first time water reaches the garden
const FLAG_MIMICS_CLEARED := "ch2_orchard_mimics_cleared"  # the taught mimic pocket was cleared (quest_flag_on_clear)
const FLAG_JUNCTION_GARDEN := "hr_sluice_junction_garden"  # lever 1: true = junction sends water toward the garden
const FLAG_GATE_OPEN := "hr_sluice_gate_open"              # lever 2: true = the garden sluice gate is raised
const FLAG_SEED_PLANTED := "hr_festival_seed_planted"      # the festival seed grew in the festival bed
const FLAG_GARDEN_NOTE := "hr_read_garden_note"
const FLAG_MOMENT_SEEN := "ch2_moment_pumpkin_seen"        # "The Pumpkin That Turned" (MP §14), once per save
const FLAG_MOMENT_TURNED := "ch2_moment_pumpkin_turned"
const FLAG_MOMENT_TWITCH := "ch2_moment_pumpkin_twitched"
const FLAG_CHIMES_FOUND := "hr_chime_trail_found"         # the last chime rang: the lost pouch is showing
const FLAG_CHIMES_DONE := "hr_chime_trail_done"            # set by the pouch reward bundle
const FLAG_BENCH_RESTED := "hr_candleyard_bench_rested"

# --- Rewards (GameState.grant_once) -------------------------------------------------------------------
## data/sources.gd REWARDS bundle marked by:"content" that belongs to this module.
const REWARD_PATTERN := "rw_ch2_candleyard_pattern"
## The chime trail pouch. Not (yet) in data/sources.gd REWARDS (integrator request): until it is, the bundle
## below is used verbatim; once it is, ItemDB.reward_bundle(REWARD_CHIMES) wins.
const REWARD_CHIMES := "rw_hr_chime_trail"
const CHIME_REWARD_FALLBACK := {"items": {"moonpetal": 3, "sugarcap": 2, "candy": 2}, "flags": [FLAG_CHIMES_DONE],
	"by": "content", "who": "Thimblebrook Pools: the lost festival pouch at the end of the chime trail"}

# --- Lore (texts live in data/lore_ch2_reach.gd, region module; fallbacks until that file has them) ------
const LORE_GARDEN := "lore_ch2_garden_note"
const LORE_GROUNDSKEEPER_1 := "lore_ch2_groundskeeper_1"
const LORE_GROUNDSKEEPER_2 := "lore_ch2_groundskeeper_2"
const LORE_FALLBACK := {
	"lore_ch2_garden_note": {"title": "A Note in the Seed Box",
		"text": "Plant the round ones for supper. Carve the crooked ones for company. Do not feed the one that feeds itself."},
	"lore_ch2_groundskeeper_1": {"title": "Groundskeeper's Note",
		"text": "Swept the paths, trimmed the moonflowers, a candle on every stone. One stone has no candle. I keep meaning to."},
	"lore_ch2_groundskeeper_2": {"title": "Groundskeeper's Second Note",
		"text": "If I don't get round to it, would you? The empty dish by the west wall. A little light is all it wants."},
}

# --- Enemy spawners (EnemySpawner; spawned by id through EnemyFactory, guarded when a script is missing) ---
## story = the taught pocket that gates the garden lamp (never respawns, woken by inspecting a twitching
## pumpkin); the others are optional loops that come back after respawn_minutes (never in view: the
## spawner only acts beyond its own rules, see src/enemies/enemy_spawner.gd).
const SPAWNERS := {
	"hr_sp_orchard_mimics": {"enemy": "pumpkin_mimic", "district": ORCHARD, "pos": Vector2(-103.0, 31.0),
		"count": 2, "radius": 2.4, "respawn_minutes": -1.0, "story": true, "min_player_distance": 2.5,
		"quest_flag_on_clear": FLAG_MIMICS_CLEARED, "clear_message": "The crooked patch is quiet now."},
	"hr_sp_orchard_patchwalkers": {"enemy": "patchwalker", "district": ORCHARD, "pos": Vector2(-101.5, 53.0),
		"count": 2, "radius": 4.0, "respawn_minutes": 720.0, "story": false},
	"hr_sp_candleyard_drudges": {"enemy": "hollow_drudge", "district": CANDLEYARD, "pos": Vector2(-96.0, -70.0),
		"count": 2, "radius": 3.5, "respawn_minutes": 720.0, "story": false},
	"hr_sp_candleyard_patchwalkers": {"enemy": "patchwalker", "district": CANDLEYARD, "pos": Vector2(-76.5, -70.5),
		"count": 2, "radius": 3.5, "respawn_minutes": 720.0, "story": false},
}
const SPAWNER_ORDER := ["hr_sp_orchard_mimics", "hr_sp_orchard_patchwalkers", "hr_sp_candleyard_drudges",
	"hr_sp_candleyard_patchwalkers"]

# --- Renewable harvest nodes (data/sources.gd NODES kinds; fixed order = stable ids) ------------------
const NODES := [
	# Pumpkintide Orchard: wild pumpkin beds (south field, never in a combat pocket) and roseberry hedges.
	{"id": "hr_pumpkin_0", "kind": "pumpkin_vine", "pos": Vector2(-88.0, 50.0), "district": ORCHARD},
	{"id": "hr_pumpkin_1", "kind": "pumpkin_vine", "pos": Vector2(-85.0, 51.5), "district": ORCHARD},
	{"id": "hr_pumpkin_2", "kind": "pumpkin_vine", "pos": Vector2(-82.0, 50.5), "district": ORCHARD},
	{"id": "hr_pumpkin_3", "kind": "pumpkin_vine", "pos": Vector2(-79.0, 52.0), "district": ORCHARD},
	{"id": "hr_pumpkin_4", "kind": "pumpkin_vine", "pos": Vector2(-87.0, 55.0), "district": ORCHARD},
	{"id": "hr_pumpkin_5", "kind": "pumpkin_vine", "pos": Vector2(-83.5, 56.0), "district": ORCHARD},
	{"id": "hr_pumpkin_6", "kind": "pumpkin_vine", "pos": Vector2(-80.0, 57.0), "district": ORCHARD},
	{"id": "hr_pumpkin_7", "kind": "pumpkin_vine", "pos": Vector2(-76.5, 54.5), "district": ORCHARD},
	{"id": "hr_roseberry_0", "kind": "roseberry_bush", "pos": Vector2(-73.2, 15.7), "district": ORCHARD},
	{"id": "hr_roseberry_1", "kind": "roseberry_bush", "pos": Vector2(-68.2, 15.7), "district": ORCHARD},
	{"id": "hr_roseberry_2", "kind": "roseberry_bush", "pos": Vector2(-64.0, 15.9), "district": ORCHARD},
	{"id": "hr_roseberry_3", "kind": "roseberry_bush", "pos": Vector2(-73.0, 22.4), "district": ORCHARD},
	{"id": "hr_roseberry_4", "kind": "roseberry_bush", "pos": Vector2(-68.0, 22.4), "district": ORCHARD},
	{"id": "hr_roseberry_5", "kind": "roseberry_bush", "pos": Vector2(-64.6, 22.4), "district": ORCHARD},
	# Thimblebrook Pools: moonpetals on the pool edges, a sugarcap bank south of the brook.
	{"id": "hr_moonpetal_0", "kind": "moonpetal_patch", "pos": Vector2(-54.8, -16.6), "district": POOLS},
	{"id": "hr_moonpetal_1", "kind": "moonpetal_patch", "pos": Vector2(-48.2, -18.0), "district": POOLS},
	{"id": "hr_moonpetal_2", "kind": "moonpetal_patch", "pos": Vector2(-38.4, -10.2), "district": POOLS},
	{"id": "hr_moonpetal_3", "kind": "moonpetal_patch", "pos": Vector2(-48.8, -3.8), "district": POOLS},
	{"id": "hr_moonpetal_4", "kind": "moonpetal_patch", "pos": Vector2(-33.0, -2.6), "district": POOLS},
	{"id": "hr_moonpetal_5", "kind": "moonpetal_patch", "pos": Vector2(-39.2, 4.0), "district": POOLS},
	{"id": "hr_sugarcap_0", "kind": "sugarcap_patch", "pos": Vector2(-45.0, 4.2), "district": POOLS},
	{"id": "hr_sugarcap_1", "kind": "sugarcap_patch", "pos": Vector2(-47.4, 6.0), "district": POOLS},
	{"id": "hr_sugarcap_2", "kind": "sugarcap_patch", "pos": Vector2(-43.0, 6.8), "district": POOLS},
	{"id": "hr_sugarcap_3", "kind": "sugarcap_patch", "pos": Vector2(-49.6, 3.0), "district": POOLS},
	{"id": "hr_sugarcap_4", "kind": "sugarcap_patch", "pos": Vector2(-45.8, 8.6), "district": POOLS},
	# The Candleyard: moonpetals and roseberries on its edges (quiet gathering, no fighting needed).
	{"id": "hr_moonpetal_6", "kind": "moonpetal_patch", "pos": Vector2(-69.5, -66.5), "district": CANDLEYARD},
	{"id": "hr_moonpetal_7", "kind": "moonpetal_patch", "pos": Vector2(-103.0, -63.5), "district": CANDLEYARD},
	{"id": "hr_moonpetal_8", "kind": "moonpetal_patch", "pos": Vector2(-87.0, -77.0), "district": CANDLEYARD},
	{"id": "hr_roseberry_6", "kind": "roseberry_bush", "pos": Vector2(-80.5, -43.8), "district": CANDLEYARD},
	{"id": "hr_roseberry_7", "kind": "roseberry_bush", "pos": Vector2(-92.8, -43.9), "district": CANDLEYARD},
	{"id": "hr_roseberry_8", "kind": "roseberry_bush", "pos": Vector2(-102.2, -54.6), "district": CANDLEYARD},
	# Marked tappable sap stumps (MP §16 resin; data/sources.gd lists the Reach's only in the orchard and the
	# Candleyard): old orchard stumps with a ribboned spout and pail. Tapping empties the pail; the stump stays.
	{"id": "hr_resin_0", "kind": "sap_stump", "pos": Vector2(-63.0, 36.0), "district": ORCHARD},
	{"id": "hr_resin_1", "kind": "sap_stump", "pos": Vector2(-57.5, 27.0), "district": ORCHARD},
	{"id": "hr_resin_2", "kind": "sap_stump", "pos": Vector2(-80.0, -40.5), "district": CANDLEYARD},
	{"id": "hr_resin_3", "kind": "sap_stump", "pos": Vector2(-92.0, -40.8), "district": CANDLEYARD},
	# Wild sunflax (MP §16: the orchard's golden fibre plants; data/sources.gd: Commons + orchard) on the orchard's
	# sunny east bank, two short rows between the arch lane and the pools lane.
	{"id": "hr_sunflax_0", "kind": "sunflax_patch", "pos": Vector2(-61.2, 31.0), "district": ORCHARD},
	{"id": "hr_sunflax_1", "kind": "sunflax_patch", "pos": Vector2(-59.6, 30.6), "district": ORCHARD},
	{"id": "hr_sunflax_2", "kind": "sunflax_patch", "pos": Vector2(-58.0, 31.2), "district": ORCHARD},
	{"id": "hr_sunflax_3", "kind": "sunflax_patch", "pos": Vector2(-62.0, 32.8), "district": ORCHARD},
	{"id": "hr_sunflax_4", "kind": "sunflax_patch", "pos": Vector2(-60.4, 33.0), "district": ORCHARD},
	{"id": "hr_sunflax_5", "kind": "sunflax_patch", "pos": Vector2(-58.8, 32.8), "district": ORCHARD},
]
## Harvest-node kinds -> the id token of hr_<token>_<n> (spec §2).
const NODE_TOKENS := {"pumpkin_vine": "pumpkin", "roseberry_bush": "roseberry", "moonpetal_patch": "moonpetal",
	"sugarcap_patch": "sugarcap", "sap_stump": "resin", "sunflax_patch": "sunflax"}

# --- Pumpkintide Orchard -----------------------------------------------------------------------------------
const ORCHARD_ENTRY := Vector2(-62.5, 48.4)       # the region's orchard_arch spawn (where she arrives)
## Irrigation: a stone cistern feeds a wooden flume south to a junction. Lever 1 at the junction sends the water
## west (the drain pond, where it starts) or south-east toward the festival garden; lever 2 raises the garden
## sluice gate. Water reaches the garden only when both are set (src/world/reach/west/irrigation.gd).
const IRRIGATION := {
	"cistern": Vector2(-88.0, 10.5),
	"junction": Vector2(-84.0, 24.0),
	"drain_pond": Vector2(-96.5, 27.0), "drain_pond_radius": 2.6,
	"gate": Vector2(-79.5, 37.5),
	"bed_inlet": Vector2(-77.4, 43.6),
	"spill": Vector2(-80.9, 38.8), "spill_radius": 1.3,
	"lever_junction": Vector2(-82.1, 22.9),
	"lever_gate": Vector2(-77.9, 36.6),
}
## Flume segments [id, from, to] (the water in each is shown by irrigation state).
const FLUME_SEGMENTS := [
	["trunk", Vector2(-88.0, 12.0), Vector2(-84.0, 24.0)],
	["drain", Vector2(-84.0, 24.0), Vector2(-94.2, 26.4)],
	["garden_a", Vector2(-84.0, 24.0), Vector2(-79.5, 37.5)],
	["garden_b", Vector2(-79.5, 37.5), Vector2(-77.4, 43.6)],
]
const GARDEN := {
	"bed": Vector2(-76.5, 45.2), "bed_size": Vector2(3.4, 2.0),
	"seed_box": Vector2(-74.1, 46.2),
	"sign": Vector2(-79.2, 46.8),              # the painted garden sign (the note itself is in the seed box)
	"lamp": Vector2(-73.6, 42.2),
	"lights_post": Vector2(-79.6, 42.4),
}
const LAMP_FOUND_NEAR := 16.0      # she "finds" the lamp within this distance...
const LAMP_FOUND_SEEN := 30.0      # ...or when it is on screen within this distance

## The roadside pumpkin of "The Pumpkin That Turned": on a show bale beside the arch lane, carved with a
## friendly face, clearly nobody's crop (a festival prize tag hangs from it).
const MOMENT := {"pos": Vector2(-66.8, 42.6), "face_to": Vector2(-60.0, 50.0), "turned_to": Vector2(-103.0, 31.0)}
const MOMENT_SEE_DIST := 28.0
const MOMENT_LEAVE_DIST := 34.0     # she has "left" once this far (the mimic patch and cistern both qualify)
const MOMENT_RETURN_DIST := 30.0
const MOMENT_INTENSE_MIN := 16.0   # Intense: the face turns only while she watches from at least this far
const MOMENT_NOTICE_DIST := 22.0
const MOMENT_TWITCH_DIST := 7.5

const MIMIC_POCKET := {
	"center": Vector2(-103.0, 31.0), "radius": 6.0,
	"dormant": [Vector2(-1.5, 0.9), Vector2(1.4, -1.1)],       # offsets of the dormant (twitching) mimics
	"plain": [Vector2(0.7, 2.3), Vector2(-2.3, -1.7)],        # ordinary, harmless, never-twitching pumpkins
	"sign": Vector2(-97.2, 33.8),
	"stakes": 10,
}
const MIMIC_WAKE_NEAR := 2.0        # walking this close to a dormant mimic wakes the pocket too
const PATCH_POCKET := {"center": Vector2(-101.5, 53.0), "radius": 6.5, "marker": Vector2(-96.4, 49.6)}

const ORCHARD_DECOR := {
	"giant_pumpkins": [[Vector2(-91.0, 43.0), 1.5], [Vector2(-71.5, 57.5), 1.2], [Vector2(-95.5, 17.0), 1.3],
		[Vector2(-68.0, 31.5), 1.1], [Vector2(-86.0, 63.5), 1.4]],
	"scarecrows": [Vector2(-72.8, 25.0), Vector2(-67.5, 10.2), Vector2(-84.0, 60.2), Vector2(-92.0, 21.0)],
	"puddles": [[Vector2(-70.5, 35.0), 1.1], [Vector2(-75.5, 30.5), 0.8], [Vector2(-89.0, 38.5), 1.0],
		[Vector2(-93.5, 47.0), 0.9], [Vector2(-79.5, 62.0), 1.2], [Vector2(-87.0, 17.5), 0.9],
		[Vector2(-65.5, 37.5), 0.7], [Vector2(-97.5, 41.0), 1.0]],
	"bales": [Vector2(-90.5, 58.5), Vector2(-73.0, 33.0), Vector2(-97.0, 23.5)],
	## crooked fence runs [from, to] along the roseberry rows (gaps between runs are the openings)
	"fences": [[Vector2(-75.0, 12.6), Vector2(-70.8, 12.6)], [Vector2(-68.4, 12.6), Vector2(-64.0, 12.6)],
		[Vector2(-74.4, 18.8), Vector2(-71.2, 18.8)], [Vector2(-68.8, 18.8), Vector2(-62.8, 18.8)],
		[Vector2(-74.0, 26.4), Vector2(-70.6, 26.4)], [Vector2(-68.0, 26.4), Vector2(-64.4, 26.4)]],
}

## Orchard lanes painted on the region terrain (shape_terrain -> terrain.mark_path): from the west road's
## end at the arch into the orchard, on to the Candleyard road start (-76, 8) and the pools road (-58, 16).
const ORCHARD_LANES := [
	[Vector2(-63.5, 47.7), Vector2(-69.5, 44.5), Vector2(-76.5, 40.5), Vector2(-83.0, 33.5), Vector2(-85.5, 27.0),
		Vector2(-83.0, 17.0), Vector2(-78.5, 11.0), Vector2(-76.0, 8.0)],
	[Vector2(-76.5, 40.5), Vector2(-70.0, 31.0), Vector2(-61.5, 26.0), Vector2(-60.0, 19.5), Vector2(-58.0, 16.0)],
	[Vector2(-83.0, 33.5), Vector2(-92.0, 33.5), Vector2(-97.5, 33.5)],
	[Vector2(-81.0, 44.0), Vector2(-86.0, 46.0), Vector2(-92.0, 47.5), Vector2(-95.5, 49.5)],
]

## Vegetation / grass stay clear of these circles (spec §10 footprints) [Vector2 centre, radius].
const ORCHARD_FOOTPRINTS := [
	[Vector2(-88.0, 11.0), 3.5], [Vector2(-86.0, 17.5), 4.5], [Vector2(-84.0, 24.0), 3.5],
	[Vector2(-91.0, 25.5), 4.5], [Vector2(-96.5, 27.0), 3.8], [Vector2(-82.0, 30.5), 4.5],
	[Vector2(-77.0, 41.5), 6.5], [Vector2(-103.0, 31.0), 7.5], [Vector2(-101.5, 53.0), 8.0],
	[Vector2(-82.0, 53.5), 8.0], [Vector2(-70.0, 16.0), 8.0], [Vector2(-70.0, 24.0), 8.0], [Vector2(-66.8, 42.6), 2.8],
	[Vector2(-91.0, 43.0), 2.5], [Vector2(-71.5, 57.5), 2.2], [Vector2(-95.5, 17.0), 2.3],
	[Vector2(-68.0, 31.5), 2.1], [Vector2(-86.0, 63.5), 2.4], [Vector2(-84.0, 60.2), 1.5],
	[Vector2(-92.0, 21.0), 1.5], [Vector2(-90.5, 58.5), 1.8], [Vector2(-73.0, 33.0), 1.8],
	[Vector2(-97.0, 23.5), 1.8],
	[Vector2(-63.0, 36.0), 1.8], [Vector2(-57.5, 27.0), 1.8], [Vector2(-60.0, 31.9), 3.4],
]

# --- Thimblebrook Pools ------------------------------------------------------------------------------------
const POOLS_ENTRIES := [Vector2(-28.5, -6.0), Vector2(-45.0, 9.5)]    # from the Conservatory side / the orchard side
## A little brook from a spring stone (north-west) down to reeds (south-east), widening into three pools.
const BROOK := [Vector2(-56.5, -19.5), Vector2(-54.0, -17.0), Vector2(-50.5, -14.5), Vector2(-47.5, -11.0),
	Vector2(-44.0, -7.5), Vector2(-40.0, -3.0), Vector2(-36.5, 0.5), Vector2(-33.5, 2.2), Vector2(-31.0, 3.0)]
const BROOK_WIDTH := 1.8
const POOL_DISCS := [[Vector2(-51.0, -15.0), 3.2], [Vector2(-43.5, -7.0), 4.6], [Vector2(-36.5, 0.5), 3.0]]
const WATER_LIFT := 0.05            # shallow water surface above the ground (walkable, no swimming)
const STEPPING_STONES := [Vector2(-45.6, -12.8), Vector2(-46.55, -11.9), Vector2(-47.5, -11.0),
	Vector2(-48.45, -10.1), Vector2(-49.4, -9.2)]
const STONE_TOP := 0.2
## The chime trail: follow the one glinting chime; each rings and hands the glint on. The last one reveals
## the lost festival pouch under the willow.
const CHIMES := [Vector2(-30.5, -5.0), Vector2(-35.0, -10.8), Vector2(-41.0, -14.6), Vector2(-50.4, -8.2),
	Vector2(-54.4, -5.6), Vector2(-56.0, -1.0)]
const CHIME_REACH := 2.4
const POUCH := Vector2(-53.4, 2.6)
const WILLOW := Vector2(-54.6, 4.4)
const MOSSY_LOG := Vector2(-51.5, 6.5)
const SPRING_STONE := Vector2(-56.4, -19.4)
const POOLS_FOOTPRINTS := [
	[Vector2(-55.0, -18.0), 4.0], [Vector2(-51.0, -15.0), 4.8], [Vector2(-47.5, -11.0), 4.0],
	[Vector2(-43.5, -7.0), 6.2], [Vector2(-40.0, -3.0), 3.6], [Vector2(-36.5, 0.5), 4.6],
	[Vector2(-32.5, 2.6), 3.0], [Vector2(-46.0, 5.8), 5.0], [Vector2(-55.0, 3.5), 4.0], [Vector2(-51.5, 6.5), 2.4],
	[Vector2(-50.4, -8.2), 1.6], [Vector2(-56.0, -1.0), 1.6],
	[Vector2(-30.5, -5.0), 1.6], [Vector2(-35.0, -10.8), 1.6], [Vector2(-41.0, -14.6), 1.6],
	[Vector2(-54.4, -5.6), 1.6], [Vector2(-38.4, -10.2), 1.4], [Vector2(-48.8, -3.8), 1.4],
	[Vector2(-33.0, -2.6), 1.4], [Vector2(-39.2, 4.0), 1.4], [Vector2(-48.2, -18.0), 1.4],
]

# --- The Candleyard ------------------------------------------------------------------------------------------
const CANDLEYARD_CENTER := Vector2(-86.0, -60.0)
const CANDLEYARD_ENTRIES := [Vector2(-86.0, -39.2), Vector2(-72.6, -43.4)]   # south (orchard) and south-east (pools)
## A low, broken memory wall (0.7 m) of lilac stone; gates are the wide openings (angles in degrees from the
## centre, atan2(z, x): 90 = south toward the orchard, 51 = south-east toward the pools, -8 = east to the bench).
const WALL_RADIUS := 19.0
const WALL_HEIGHT := 0.7
const WALL_GATES := [90.0, 51.0, -8.0, 180.0, 270.0]
const WALL_GATE_HALF_DEG := 8.0
const CANDLE_TREE := Vector2(-86.0, -62.0)
const SHED := {"pos": Vector2(-72.5, -57.0), "size": Vector2(2.8, 2.4), "note": Vector2(-74.8, -54.9),
	"tools": Vector2(-71.6, -55.4), "barrow": Vector2(-73.2, -53.2)}
const PATTERN_SPOT := Vector2(-70.2, -57.8)        # behind the shed, under a loose stone (a pale ribbon peeks out)
const NOTE_2 := Vector2(-100.2, -57.6)             # a tin box on a leaning stone by the west wall
const MARKER := Vector2(-95.5, -50.2)              # the fixed empty candle dish
const NOOK := Vector2(-98.0, -48.6)                # the calm moonflower nook it reveals
const BENCH := {"pos": Vector2(-65.2, -62.8), "look": Vector2(-40.0, -62.8)}
## "A Hat Too Large": fluttering ribbons from the south-east gate to the Candle Tree, where the hat is stuck
## on a low branch (reachable from the ground: no jumping).
const HAT_RIBBONS := [Vector2(-75.2, -47.2), Vector2(-77.3, -50.0), Vector2(-79.4, -52.8), Vector2(-81.4, -55.4),
	Vector2(-83.1, -57.8)]
const HAT := {"pos": Vector2(-84.7, -60.9), "height": 1.55, "stand": Vector2(-83.9, -59.4)}
const LEANING_STONES := [
	[Vector2(-79.9, -59.8), 12.0], [Vector2(-88.75, -56.1), -9.0], [Vector2(-92.1, -59.8), 7.0],
	[Vector2(-91.9, -64.75), -11.0], [Vector2(-88.75, -67.9), 10.0], [Vector2(-83.8, -68.1), -7.0],
	[Vector2(-80.1, -64.7), 9.0], [Vector2(-82.07, -49.19), -8.0], [Vector2(-90.86, -49.58), 11.0],
	[Vector2(-95.42, -53.4), -10.0], [Vector2(-96.8, -63.9), 8.0], [Vector2(-94.13, -68.13), -12.0],
	[Vector2(-89.93, -70.8), 9.0], [Vector2(-82.07, -70.8), -9.0], [Vector2(-77.19, -67.39), 10.0],
	[Vector2(-75.19, -63.93), -8.0], [Vector2(-99.5, -68.5), 11.0], [Vector2(-93.0, -73.2), -10.0],
	[Vector2(-97.6, -73.6), 8.0], [Vector2(-78.0, -75.2), -11.0], [Vector2(-74.5, -72.2), 9.0],
	[Vector2(-72.6, -69.8), -7.0], [Vector2(-101.0, -57.3), 6.0],
]
const VIOLET_LIGHTS := [[Vector2(-86.0, -62.0), 3.4, 14.0, 1.3], [Vector2(-75.5, -53.5), 2.2, 8.0, 0.9],
	[Vector2(-95.5, -66.0), 2.2, 8.0, 0.9]]         # [pos, height, range, energy (night)]
const CANDLEYARD_FOOTPRINTS := [
	[Vector2(-86.0, -60.0), 19.9], [Vector2(-65.2, -62.8), 2.8], [Vector2(-80.5, -43.8), 1.6],
	[Vector2(-92.8, -43.9), 1.6], [Vector2(-86.0, -41.0), 3.0], [Vector2(-74.0, -45.2), 3.0],
	[Vector2(-80.0, -40.5), 1.8], [Vector2(-92.0, -40.8), 1.8],
]


## Landmark centre / radius (data/hallowmere_layout.gd, spec §7.2).
static func center_of(district: String) -> Vector2:
	return Reach.LANDMARKS[district]["pos"]


static func radius_of(district: String) -> float:
	return float(Reach.LANDMARKS[district]["radius"])


## All district footprints for a landmark id.
static func footprints_for(district: String) -> Array:
	match district:
		ORCHARD:
			return ORCHARD_FOOTPRINTS
		POOLS:
			return POOLS_FOOTPRINTS
		CANDLEYARD:
			return CANDLEYARD_FOOTPRINTS
	return []


## Harvest node entries of one district, in id order.
static func nodes_in(district: String) -> Array:
	var out: Array = []
	for n in NODES:
		if String(n["district"]) == district:
			out.append(n)
	return out


static func spawners_in(district: String) -> Array:
	var out: Array = []
	for id in SPAWNER_ORDER:
		if String(SPAWNERS[id]["district"]) == district:
			out.append(String(id))
	return out


## Candleyard wall: true when the angle (degrees, atan2(z, x) from the centre) lies in a gate.
static func in_wall_gate(angle_deg: float) -> bool:
	for g in WALL_GATES:
		var d := absf(wrapf(angle_deg - float(g), -180.0, 180.0))
		if d <= WALL_GATE_HALF_DEG:
			return true
	return false


static func gate_point(angle_deg: float) -> Vector2:
	var a := deg_to_rad(angle_deg)
	return CANDLEYARD_CENTER + Vector2(cos(a), sin(a)) * WALL_RADIUS
