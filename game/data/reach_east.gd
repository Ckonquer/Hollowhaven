extends RefCounted
## Ashbell Quarry (Hallowmere Reach east district, module C3; MP §9 row "Ashbell Quarry", §11 step 6,
## §12 Bellcap Sentry / Quarry Warden, §16 iron / moon crystal). Every quarry coordinate, id, level, cost
## and line lives here; src/world/reach/districts/quarry.gd + src/world/reach/east/* read it.
##
## LOCAL FRAME. Positions are written as (U, V) metres in a frame centred on the hr_quarry landmark centre:
##   world(x, z) = CENTER + U * AXIS_U + V * AXIS_V
## AXIS_U points from the centre toward the layout's "moon_crystal_shelf" point (110, -26) (north-north-east),
## AXIS_V is perpendicular (east-south-east). The quarry is a terraced hillside rising along +U:
##   apron L0 (U < -12, the yard by the region's quarry arch) -> L1 bench -> L2 bench (the Warden's arena)
##   -> a 4.6 m cliff -> the upper Moon Crystal shelf (U >= U_CLIFF, V >= SHELF_WEST_V), reached ONLY by the
##   gangway the mineral winch lowers. Ramps (no jumps) join L0/L1/L2. The Bellhouse road from the region
##   (path "quarry_bellhouse", ends at NORTH_MOUTH) enters on L2 at the north-west.
## Layout-point notes (data/hallowmere_layout.gd): the winch crane stands at ~(100, 0) and the Warden arena is
## centred on (90, 10) exactly; the "moon_crystal_shelf" point (110, -26) is 50 m from the centre, OUTSIDE
## the 30 m landmark circle, so the shelf is built on the circle's north-north-east rim, facing that point.

const LANDMARK := "hr_quarry"
const CENTER := Vector2(86, 18)
const RADIUS := 30.0
const AXIS_U := Vector2(0.478851, -0.877893)
const AXIS_V := Vector2(0.877893, 0.478851)

## The region module's quarry arch (keep clear) and the Bellhouse road's end (the north mouth).
const ARCH := Vector2(62, 38)
const ARCH_CLEAR := 8.0                      # no district prop / node closer than this to the arch
const NORTH_MOUTH := Vector2(85, -14)        # data/hallowmere_layout.gd PATHS["quarry_bellhouse"] last point

# --- Terrain (shape_terrain) -----------------------------------------------------------------------------

## Heights above the quarry floor G (G = the region's quarry_arch plaza height, so the yard meets the arch).
const LEVELS := [0.0, 1.4, 2.8, 7.4]         # L0 apron, L1 bench, L2 bench (arena), L3 shelf
const STEP_U := [-12.0, -2.0]                # U of the L0|L1 and L1|L2 step edges
const U_CLIFF := 20.0                        # L2|shelf cliff line
const SHELF_WEST_V := -7.0                   # the shelf's west side cliff (west of it: L2 / the north mouth)
## Ramps: height runs linearly along U from h[0] at u[0] to h[1] at u[1], across v[0]..v[1].
const RAMPS := [
	{"id": "haul_low", "u": [-17.5, -12.0], "v": [-3.2, 3.2], "h": [0.0, 1.4]},
	{"id": "haul_high", "u": [-7.5, -2.0], "v": [-3.2, 3.2], "h": [1.4, 2.8]},
	{"id": "west_low", "u": [-17.5, -12.0], "v": [-19.0, -15.0], "h": [0.0, 1.4]},
	{"id": "west_high", "u": [-7.5, -2.0], "v": [-19.0, -15.0], "h": [1.4, 2.8]},
	{"id": "east_low", "u": [-17.5, -12.0], "v": [14.0, 18.0], "h": [0.0, 1.4]},
	{"id": "east_high", "u": [-7.5, -2.0], "v": [14.0, 18.0], "h": [1.4, 2.8]},
]
## Shaping weight: 1 inside RIM_FLAT, 0 from RIM_OUT on (strictly inside RADIUS); natural ground is kept
## within [inner, outer] of the arch and the north mouth (blend between).
const RIM_FLAT := 28.6
const RIM_OUT := 29.8
const ARCH_KEEP := [8.0, 11.5]
const NORTH_KEEP := [3.0, 8.5]

## Ground colour (applied by the region's colour pass through terrain.tint_disc) and dirt roads.
const TINTS := [
	# [U, V, r0, r1, Color, amount]
	[0.0, 0.0, 18.0, 28.0, Color("b0583a"), 0.5],
	[-20.0, 0.0, 5.0, 11.0, Color("c98a5e"), 0.35],
	[24.0, -3.0, 2.5, 5.0, Color("c7a7a2"), 0.6],
	[24.0, 4.0, 2.5, 5.0, Color("c7a7a2"), 0.6],
	[23.5, 11.0, 2.5, 5.0, Color("c7a7a2"), 0.6],
	[22.0, 16.0, 2.0, 4.0, Color("c7a7a2"), 0.55],
]
## Dirt roads painted into the terrain's path weight (U, V polylines, half width).
const ROADS := [
	{"points": [Vector2(-25.5, -8.5), Vector2(-19.0, -1.5), Vector2(-9.0, 0.0), Vector2(1.0, 0.0)], "half": 2.2},
	{"points": [Vector2(27.0, -15.5), Vector2(22.0, -12.5), Vector2(17.0, -9.5)], "half": 1.4},
]

# --- Content (U, V) --------------------------------------------------------------------------------------

const ARENA := Vector2(90, 10)               # world; the Warden arena centre (layout point)
const ARENA_RADIUS := 10.0                   # open, flat, readable L2 floor
const PILLARS := [Vector2(12.6, -6.8), Vector2(12.3, 6.3), Vector2(3.3, -0.4)]
const PILLAR_RADIUS := 0.85
const PILLAR_HEIGHT := 3.3
const PILLAR_STUMP := 1.1
const PILLAR_REGROW := 25.0                  # seconds until a cracked pillar re-knits (recoverable reset)
const PILLAR_REGROW_ASSIST := 12.0           # Settings timing_assist
const PILLAR_REGROW_ALL := 8.0               # every pillar cracked and the Warden still up: faster re-knit

## Winch: a crane on the shelf (layout point ~(100, 0)), a hinged plank gangway along the cliff foot and the
## repairable winch drum at the gangway's foot.
const WINCH := {
	"crane": Vector2(22.6, 2.8),
	"station": Vector2(14.6, -15.6),
	"deck_u": [16.55, 21.3],
	"deck_v": [-1.2, 1.4],
	"gangway_u": 17.75,                      # centre line (U)
	"gangway_width": 2.4,
	"slope_deg": 19.0,
	"raised_deg": 12.0,                      # the broken winch holds it stiffly out, well above the bench
}
## Repair cost: familiar materials only (no bars, so it never waits for the furnace). Order = prompt order.
const WINCH_COST := [["wood", 6], ["stone", 6], ["iron_ore", 4]]
const LAMP := Vector2(22.8, -4.5)
const LAMP_FIND_RADIUS := 18.0               # ch2_found_quarry_lamp when Krystal comes this close (XZ)
const LOG_NOTE := Vector2(-21.8, 10.2)
const SHED := Vector2(-23.6, 11.8)
const SIGN := Vector2(-22.5, -5.5)
const BELL_GATE := [Vector2(-1.0, -4.6), Vector2(-1.0, 4.6)]
## The quarry's namesake: a huge old cracked bell, half sunk in the L2 bench (a landmark silhouette).
const ASHBELL := Vector2(5.5, -13.0)
## Bell-cap toadstools marking the Bellcap Sentry pocket (decor; a clearly marked pocket, MP §12). The pocket sits on
## the east end of the L1 bench (beside the east ramps, around an iron vein), far enough from the Warden's arena that
## no Bellcap can notice Krystal on the arena floor (the elite fight stays a one-on-one lesson; a layout test checks
## spawn radius + wander + data aggro_radius against the arena).
const BELLCAP_MARKERS := [Vector2(-10.5, 20.0), Vector2(-4.0, 19.5), Vector2(-4.5, 24.5), Vector2(-9.0, 24.8)]
const LANTERN_POSTS := [Vector2(-19.0, -4.2), Vector2(-19.0, 4.2), Vector2(-10.0, -4.2), Vector2(-10.0, 4.2)]

## Harvest nodes (data/sources.gd NODES; every one renewable). Ids "<prefix>%d" in table order.
const IRON := [Vector2(-20.5, -8.0), Vector2(-15.0, 10.0), Vector2(-8.5, -11.0), Vector2(-6.0, -22.5),
	Vector2(-9.5, 10.5), Vector2(-5.0, 22.0), Vector2(4.0, -19.5), Vector2(10.5, -21.0), Vector2(3.5, 21.5),
	Vector2(12.5, 19.5)]
const COPPER := [Vector2(-22.5, 2.5), Vector2(-21.0, -16.0), Vector2(-4.5, -8.0), Vector2(-7.5, 6.8)]
const ROCKS := [Vector2(-25.0, -1.5), Vector2(-18.5, 19.5), Vector2(-14.5, -22.5), Vector2(-10.0, -16.5),
	Vector2(-4.5, 12.0), Vector2(1.5, -24.0), Vector2(16.5, 14.0), Vector2(0.5, 13.5)]
const STONES := [Vector2(-19.5, -12.5), Vector2(-17.0, 6.5), Vector2(-25.0, 7.5), Vector2(-19.0, 14.5),
	Vector2(-10.5, -5.5), Vector2(-4.0, 8.5), Vector2(1.0, -10.0), Vector2(-0.5, 17.5)]
const MOON_CRYSTALS := [Vector2(25.8, -5.0), Vector2(26.3, -0.5), Vector2(25.9, 4.5), Vector2(24.9, 8.5),
	Vector2(23.1, 12.5), Vector2(22.2, 15.2)]

const ID_IRON := "hr_iron_%d"
const ID_MOON := "hr_mooncrystal_%d"
const ID_COPPER := "hr_copper_%d"
const ID_ROCK := "hr_qrock_%d"
const ID_STONE := "hr_qstone_%d"
## node table -> [positions, id format, data/sources.gd NODES kind (= the resource_node.gd kind; the node takes
## tool / min_tier / hits / drops / respawn from the data), minimum tier this table asks for (never lower than the
## data's min_tier)]. NODE_ORDER = build / id order.
const NODE_ORDER := ["iron", "moon_crystal", "copper", "rock", "stone"]
const NODE_TABLES := {
	"iron": [IRON, ID_IRON, "iron_vein", 1],
	"moon_crystal": [MOON_CRYSTALS, ID_MOON, "moon_crystal_vein", 3],
	"copper": [COPPER, ID_COPPER, "ore", 1],
	"rock": [ROCKS, ID_ROCK, "rock", 1],
	"stone": [STONES, ID_STONE, "stone", 0],
}

## Enemy spawners (ids spec §2). The Warden never respawns; the Bellcap pocket is renewable. "wander" = the spawned
## enemies' wander radius around their spawn point.
const SPAWNERS := {
	"hr_sp_quarry_warden": {"enemy": "quarry_warden", "count": 1, "radius": 0.5, "respawn_minutes": -1.0,
		"quest_flag_on_clear": "hr_warden_defeated", "at": Vector2(8.938, -0.319), "wander": 3.0},
	"hr_sp_bellcaps": {"enemy": "bellcap_sentry", "count": 2, "radius": 3.5, "respawn_minutes": 1440.0,
		"quest_flag_on_clear": "", "at": Vector2(-7.0, 21.5), "wander": 2.0},
}
const WARDEN_ID := "quarry_warden"
const WARDEN_SPAWNER := "hr_sp_quarry_warden"

# --- Flags, lore, text -------------------------------------------------------------------------------------

const FLAG_WINCH := "ch2_winch_repaired"             # data/unlocks.gd (Moonsteel knowledge)
const FLAG_WARDEN := "hr_warden_defeated"            # the Warden spawner's quest_flag_on_clear
const FLAG_LAMP_FOUND := "ch2_found_quarry_lamp"     # data/quests_ch2.gd step ch2_outer_lamps
const FLAG_LAMP_LIT := "ch2_quarry_lamp_lit"         # data/quests_ch2.gd step ch2_quarry (the log pays rw_ch2_quarry)
const LORE_LOG := "lore_ch2_quarry_log"              # text owned by the region module (data/lore_ch2_reach.gd)

const TEXT := {
	"winch_repair": "Repair the mineral winch (%s)",
	"winch_look": "Look over the mineral winch",
	"winch_broken": "A cracked gear, a jammed pawl and a slack chain. With a little wood, stone and iron ore the old winch could lower its gangway again.",
	"winch_done": "The winch holds the gangway steady. The upper shelf is open.",
	"winch_repaired": "The winch clanks, the chain runs, and the gangway lowers to the terrace.",
	"winch_caption": "A winch clanks; a gangway lowers.",
	"lamp_name": "Light the quarry lamp",
	"lamp_look": "The quarry lamp",
	"lamp_need_warden": "The Warden's pulse still shakes its wick. Calm the Warden first.",
	"lamp_need_winch": "The gangway up to the lamp is still hoisted.",
	"lamp_lit_prompt": "The quarry lamp burns warm",
	"lamp_found": "High on the upper shelf, a festival lamp sleeps under the quarry's slow pulse.",
	"lamp_lit": "The quarry lamp wakes, warm as a hearth. Far off, a bell answers.",
	"lamp_caption": "The quarry lamp catches with a soft, bright hum.",
	"lamp_lumi": "Lumi's light answers the lantern, warm and gold.",   # MP §17, verbatim
	"lamp_dormant": "A festival lamp on a copper post, cold and quiet. It waits for a calmer quarry.",
	"pillar_caption": "A mineral pillar cracks!",
	"pillar_restored_caption": "Crystal knits a cracked pillar whole again.",
	"warden_quiet": "The quarry's slow pulse falls quiet.",
	"warden_clear": "The Quarry Warden settles into stillness. The quarry's pulse falls quiet.",
	"log_read": "Read the quarry log",
	"log_missing_title": "Ashbell Quarry Log",
	"log_missing_text": "A weathered tally of carts, bells and shifts. The last page is too rain-soft to read.",
	"tier_needs": "%s needs %s or better.",
}

## Quarry colours (copper-red stone, pale crystal, bell bronze), built on src/art/palette.gd hues.
const COL_ROCK := Color("b8674a")
const COL_ROCK_DARK := Color("8a4a36")
const COL_ROCK_LIGHT := Color("d08a62")
const COL_SHELF := Color("c7a7a2")
const COL_CRYSTAL := Color("cfe0ff")
const COL_CRYSTAL_DEEP := Color("9fb4e8")
const COL_IRON := Color("5d6a80")
const COL_BRONZE := Color("c9933e")
const COL_RIBBON_A := Color("e9a15b")
const COL_RIBBON_B := Color("7a4a8a")
const LAMP_GLOW := Color("ffc978")
