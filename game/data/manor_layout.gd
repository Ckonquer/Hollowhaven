extends RefCounted
## Moonveil Manor (docs/CHAPTER_TWO_SPEC.md §1, §7.3, §10; MP §9, §11 step 7, §13.1, §14, §15, §17).
## Pure data for BOTH halves of the manor, read by:
##   * the interior area  src/world/areas_ch2/moonveil_manor_world.gd  (area id "moonveil_manor")
##   * the Reach district src/world/reach/districts/manor_grounds.gd    (grounds, facade, front door)
##   * tests/unit/test_manor_*.gd
## Interior coordinates are the manor's own (x east, z south, y up, metres; forward/yaw 0 = -Z = north).
## Grounds coordinates are Hallowmere Reach coordinates (data/hallowmere_layout.gd).
##
## FLAGS (who sets what):
##   ch2_found_manor_lamp   grounds: first approach to the manor (also safety-set on entering the manor)
##   ch2_manor_lamp_lit     balcony: the Manor lantern is woken (ONLY this; the quest layer pays rw_ch2_manor)
##   ch2_velour_defeated    manor: Events.boss_defeated("count_velour") (or the fallback / debug hook)
##   ch2_velvet_scrap_1..3  manor: the three Count's Wardrobe scraps (optional goal opt_counts_wardrobe)
##   ch2_shortcut_manor     manor: balcony shortcut opened (optional goal opt_long_way_home)
##   mm_balcony_shortcut    manor: same moment, manor-local state (servants' stair + garden stair)
##   mm_ballroom_solved     manor: candle-routing puzzle solved (the gallery doors stay open)
##   mm_mirror_clue         manor: the Looking-Glass Hall's practice candle lit (true-light lesson seen)
##   ch2_moment_empty_waltz manor: "The Empty Waltz" authored moment played (once per save)
##   mm_waltz_revealed      manor: candle-light showed the dancing rail's wires (lore note found)
##   mm_cp_manor_ballroom, mm_cp_manor_balcony   manor: rest candles lit once (their five flames stay lit)
## Rewards: the manor grants NO ledger bundle itself (sources.gd has no "content" bundle for it). The Manor
## Seal + tailoring patterns are rw_ch2_manor (quest layer), the cape pattern is rw_opt_counts_wardrobe
## (optional log). The scraps are fixed one-time pickups (sources.gd "pickup").

const AREA_ID := "moonveil_manor"
const REACH_ID := "hallowmere_reach"

const FLAG_FOUND_LAMP := "ch2_found_manor_lamp"
const FLAG_LAMP_LIT := "ch2_manor_lamp_lit"
const FLAG_VELOUR_DEFEATED := "ch2_velour_defeated"
const FLAG_SCRAPS := ["ch2_velvet_scrap_1", "ch2_velvet_scrap_2", "ch2_velvet_scrap_3"]
const FLAG_SHORTCUT := "mm_balcony_shortcut"
const FLAG_SHORTCUT_GOAL := "ch2_shortcut_manor"
const FLAG_BALLROOM_SOLVED := "mm_ballroom_solved"
const FLAG_MIRROR_CLUE := "mm_mirror_clue"
const FLAG_WALTZ := "ch2_moment_empty_waltz"
const FLAG_WALTZ_REVEALED := "mm_waltz_revealed"

const BOSS_ID := "count_velour"
const WING_ID := "velvet_wing"
const SCRAP_ITEM := "velvet_scrap"

## The invitation note lives in the region module's lore file (data/lore_ch2_reach.gd); the text is MP §17
## verbatim and is shown from here too when that file is not present yet.
const LORE_INVITATION := "lore_ch2_manor_invitation"
const INVITATION_TITLE := "An Invitation"
const INVITATION_TEXT := "To the bearer of a proper light: you are expected. The house has practiced being welcoming."

## Count Velour's lines (MP §17 verbatim where quoted). The area says the first bow when the gallery
## encounter begins (the boss module must not repeat it); the resident repeats RESIDENT_LINES in order.
const VELOUR_NAME := "Count Velour"
const VELOUR_FIRST_BOW := "Do come in. I have been expecting someone for a terribly long time."
const VELOUR_AFTER := "A dreadful host. I did not even offer you a chair."
const RESIDENT_LINES := [
	"A dreadful host. I did not even offer you a chair.",
	"I kept reading someone else's invitation aloud. Over and over. A dreadful habit, like humming a tune you never liked.",
	"The lantern on the balcony remembers proper light. Do wake it. I shall stand nearby and look as if I helped.",
	"Velvet should be worn, not hoarded. If you find my scraps, keep them. The Loom knows what to do.",
	"When the waltz stops, the rail stops. When the rail stops, the cloaks simply bow. Nobody told me that for years.",
]

# --- Interior -------------------------------------------------------------------------------------

## Walls are built OUTSIDE each room box (thickness WALL_T); neighbouring rooms leave exactly WALL_T
## between them and only ONE of the two builds the shared wall ("walls" lists the sides a room builds).
## Openings: [from, to, top, bottom=0] along the side (x for n/s, z for w/e), heights above the room floor.
## A floor-level opening gets a threshold slab under it (the wall gap is walkable).
const WALL_T := 0.5
const MIN_OPENING_W := 1.6
const MIN_OPENING_H := 2.4

const ROOMS := {
	"cloakroom": {"zone": "mm_cloakroom", "safe": true, "x0": -5.0, "x1": 5.0, "z0": -10.0, "z1": 0.0, "y": 0.0, "h": 3.6,
		"surface": "wood", "walls": {"s": [], "n": [[-1.3, 1.3, 3.0]], "w": [], "e": []}},
	"hall": {"zone": "mm_hall", "safe": false, "x0": -3.5, "x1": 3.5, "z0": -30.5, "z1": -10.5, "y": 0.0, "h": 5.5,
		"surface": "wood", "walls": {"w": [[-14.7, -12.9, 3.6, 0.9], [-17.9, -16.1, 3.6, 0.9], [-21.1, -19.3, 3.6, 0.9],
			[-24.3, -22.5, 3.6, 0.9], [-27.5, -25.7, 3.6, 0.9]], "e": [[-21.2, -19.2, 2.7]]}},
	"powder": {"zone": "mm_hall", "safe": false, "side_room": true, "x0": 4.0, "x1": 9.0, "z0": -23.0, "z1": -17.5, "y": 0.0, "h": 3.2,
		"surface": "wood", "walls": {"n": [], "s": [], "e": []}},
	"ballroom": {"zone": "mm_ballroom", "safe": false, "x0": -11.0, "x1": 11.0, "z0": -51.0, "z1": -31.0, "y": 0.0, "h": 8.0,
		"surface": "wood", "walls": {"s": [[-1.5, 1.5, 3.4]], "w": [[-49.2, -47.0, 3.3, 0.6]], "e": []}},
	"nook": {"zone": "mm_ballroom", "safe": false, "side_room": true, "x0": -16.5, "x1": -11.5, "z0": -50.5, "z1": -45.5, "y": 0.6, "h": 2.9,
		"surface": "wood", "walls": {"n": [], "s": [], "w": []}},
	"gallery": {"zone": "mm_gallery", "safe": false, "x0": -13.0, "x1": 13.0, "z0": -77.5, "z1": -51.5, "y": 0.0, "h": 9.0,
		"surface": "stone", "walls": {"s": [[-1.6, 1.6, 3.6]], "n": [[-1.6, 1.6, 3.6]], "e": [[-65.8, -63.8, 2.8]], "w": []}},
	"dressing": {"zone": "mm_gallery", "safe": false, "side_room": true, "x0": 13.5, "x1": 19.5, "z0": -67.5, "z1": -61.5, "y": 0.0, "h": 3.4,
		"surface": "wood", "walls": {"n": [], "s": [], "e": []}},
	"stair": {"zone": "mm_balcony", "safe": true, "x0": -2.0, "x1": 2.0, "z0": -83.0, "z1": -78.0, "y": 0.0, "h": 4.8,
		"surface": "stone", "ramp": {"from": Vector3(0.0, 0.0, -78.0), "to": Vector3(0.0, 1.8, -82.0)}, "top_y": 1.8,
		"walls": {"w": [], "e": []}},
	"balcony": {"zone": "mm_balcony", "safe": true, "x0": -9.0, "x1": 9.0, "z0": -97.0, "z1": -83.5, "y": 1.8, "h": 6.0,
		"surface": "stone", "open_sky": true, "parapet": ["w", "n", "e"],
		"walls": {"s": [[-2.0, 2.0, 3.4]], "w": [], "n": [], "e": [[-90.0, -88.0, 3.0]]}},
	"landing": {"zone": "mm_balcony", "safe": true, "x0": 9.5, "x1": 13.5, "z0": -91.5, "z1": -86.5, "y": 1.8, "h": 3.6,
		"surface": "stone", "open_sky": true, "parapet": ["s", "e"], "walls": {"n": [], "s": [], "e": [[-89.9, -88.1, 3.0]]}},
}
## Build order (also the order of the room nodes).
const ROOM_ORDER := ["cloakroom", "hall", "powder", "ballroom", "nook", "gallery", "dressing", "stair", "balcony", "landing"]
const ZONE_ORDER := ["mm_cloakroom", "mm_hall", "mm_ballroom", "mm_gallery", "mm_balcony"]
const PARAPET_H := 1.05          # visible balustrade height; its invisible collision goes up to PARAPET_COLLIDE
const PARAPET_COLLIDE := 3.2

## Playable XZ rectangle (validate_position).
const BOUNDS := Rect2(-18.0, -99.0, 39.0, 100.5)

## Spawn stand points: {pos, look} (look = the XZ point she faces).
const SPAWNS := {
	"manor_entry": {"pos": Vector3(0.0, 0.0, -3.2), "look": Vector2(0.0, -20.0)},
	"manor_ballroom": {"pos": Vector3(5.0, 0.0, -33.9), "look": Vector2(0.0, -41.0)},
	"manor_balcony": {"pos": Vector3(3.8, 1.8, -87.0), "look": Vector2(0.0, -92.0)},
}
## Checkpoint candles (rest = respawn + save). Each also adds a safe circle of `safe_r`.
const CHECKPOINTS := {
	"manor_ballroom": {"pos": Vector3(7.0, 0.0, -33.2), "spawn": "manor_ballroom", "safe_r": 3.2},
	"manor_balcony": {"pos": Vector3(6.2, 1.8, -85.4), "spawn": "manor_balcony", "safe_r": 3.2},
}

## Exits. front_door / balcony_stair lead to the Reach; the servants' stair is an in-house shortcut.
## yaw_deg turns the door node so its local +Z ("front", where Krystal stands) faces into the room.
## Door nodes stand 0.3 m in front of the wall face they belong to.
const FRONT_DOOR := {"pos": Vector3(0.0, 0.0, -0.3), "yaw_deg": 180.0}
const GARDEN_STAIR := {"pos": Vector3(13.2, 1.8, -89.0), "yaw_deg": -90.0}
const SERVANTS_DOOR_CLOAK := {"pos": Vector3(4.7, 0.0, -6.5), "yaw_deg": -90.0}
const SERVANTS_DOOR_LANDING := {"pos": Vector3(11.5, 1.8, -91.2), "yaw_deg": 0.0}
## Cloakroom east-wall sconces (z): above the bench and above the candle table, clear of the servants' door.
const CLOAK_EAST_SCONCES := [-3.0, -8.6]
const SHORTCUT_GATE := {"pos": Vector3(9.25, 1.8, -89.0), "width": 2.0}

## Looking-Glass Hall: the mirror plane is the inner face of the west wall; the mirror world (a dim,
## selective reflection that only shows TRUE light) is built behind it, mirrored across MIRROR_X.
const MIRROR_X := -3.5
const MIRROR_WORLD := {"x0": -10.8, "x1": -4.0, "z0": -30.5, "z1": -10.5}
const HALL_TRUE_CANDLES := [Vector3(3.2, 2.2, -12.4), Vector3(3.2, 2.2, -16.0), Vector3(3.2, 2.2, -24.4), Vector3(3.2, 2.2, -28.4)]
const HALL_FALSE_CANDLES := [Vector3(2.4, 1.05, -26.6), Vector3(2.9, 1.05, -26.6), Vector3(3.2, 1.05, -26.3)]
const PRACTICE_CANDLE := Vector3(-2.1, 0.0, -17.0)
const BAT_SIDEBOARD := Vector3(-3.2, 0.0, -23.4)
const BAT_FIGURES := [Vector3(-3.15, 0.88, -22.85), Vector3(-3.15, 0.88, -23.4), Vector3(-3.15, 0.88, -23.95)]
const TRUE_BAT := 2              # index into BAT_FIGURES wearing the golden collar (seen only in the mirror)
const HALL_CARD := Vector3(-1.6, 0.0, -14.0)
const FOLDING_SCREEN := Vector3(2.9, 0.0, -18.1)
const HALL_WINDOWS := [-14.2, -26.4]             # crescent windows high on the east wall (z)
## Rib arches across the hall's vault (z). Their wall posts stand only on plain wall: never in front of a
## looking-glass (west), the Powder Room door, a sconce or a crescent window (east). A test checks it.
const HALL_RIBS := [-11.7, -15.4, -18.6, -21.8, -25.0, -29.0]
const HALL_RIB_POST_W := 0.3
const GUEST_BOOK := Vector3(-3.0, 0.0, -8.4)
const COUNT_DIARY := Vector3(-10.6, 0.0, -75.6)

## Ballroom candle-routing puzzle: light the hearth candle, then turn the candelabra so the ward-light
## runs along the gilt runners to the crescent lock of the gallery doors. No timing; reset lever.
const PUZZLE := {
	"source": {"pos": Vector3(-3.6, 0.0, -34.2), "to": "c1"},
	"nodes": {
		"c1": {"pos": Vector3(-5.0, 0.0, -38.6), "arms": ["c3", "c2"]},
		"c2": {"pos": Vector3(5.0, 0.0, -38.6), "arms": ["c1", "c4"]},
		"c3": {"pos": Vector3(-4.5, 0.0, -44.6), "arms": ["c1", "c4"]},
		"c4": {"pos": Vector3(4.5, 0.0, -44.6), "arms": ["c3", "T", "c2"]},
	},
	"target": {"pos": Vector3(0.0, 0.0, -50.3), "lock_y": 4.3},
	"reset": {"pos": Vector3(-6.2, 0.0, -33.6)},
	"card": {"pos": Vector3(-7.4, 0.0, -34.8)},
}
const STAGE := {"x0": -11.0, "x1": -6.5, "z0": -51.0, "z1": -46.0, "top": 0.6, "steps": {"x0": -10.6, "x1": -7.0, "z_top": -46.0, "z_bottom": -44.6}}
const MUSIC_BOX := Vector3(-9.6, 0.6, -50.0)

## The Empty Waltz (MP §14): pairs of empty cloaks on a clockwork rail along the east wall.
const WALTZ := {
	"rail_x": 9.9, "rail_y": 6.2, "rail_z0": -47.5, "rail_z1": -36.5,
	"pairs": [Vector3(9.3, 0.0, -45.2), Vector3(9.3, 0.0, -42.0), Vector3(9.3, 0.0, -38.8)],
	"moving_pair": 1,
	"rail_candle": Vector3(7.7, 0.0, -41.3),
	# intensity -> {preview (s of sway before the stop), delay (s after the stop), turn (s)}. The stop also asks
	# the music director for an authored silence (its fade is 4 s), so every delay lets the waltz fade first.
	"timing": {0: {"preview": 12.0, "delay": 4.0, "turn": 3.6}, 1: {"preview": 4.0, "delay": 4.5, "turn": 2.6},
		2: {"preview": 0.0, "delay": 8.0, "turn": 2.0}},
	"waltz_seconds": {0: 28.0, 1: 22.0, 2: 22.0},  # music box winds down after this long in the ballroom
	"min_seconds": 6.0,                             # ...or when the waltz cue ends, once she has been here this long
	"reveal_light": 0.4,                            # Combat.light_at() at the pair that shows the wires
}

## Count's Gallery = the Count Velour arena (MP §13.1).
const ARENA := {
	"center": Vector3(0.0, 0.0, -64.5), "radius": 12.0, "entry_z": -53.6,
	"candles": {"north": Vector3(0.0, 0.0, -72.0), "southwest": Vector3(-6.5, 0.0, -60.75), "southeast": Vector3(6.5, 0.0, -60.75)},
	"candle_order": ["north", "southwest", "southeast"],
	# MP §13.1 "Teach one candle before combat": with the Count present this one waits dark; the encounter
	# begins once Krystal lights it (the other two already burn). Nearest the entry, left of the doors.
	"teach_candle": "southwest",
	"cover": [Vector3(-8.5, 0.0, -70.5), Vector3(8.5, 0.0, -70.5), Vector3(-9.2, 0.0, -57.4), Vector3(9.2, 0.0, -57.4)],
	"fixture": Vector3(0.0, 7.1, -64.5),
	"resident": Vector3(-3.4, 0.0, -73.6),
	"curtains": [[Vector3(-12.95, 0.0, -57.0), 90.0], [Vector3(-12.95, 0.0, -64.5), 90.0], [Vector3(-12.95, 0.0, -72.0), 90.0],
		[Vector3(12.95, 0.0, -57.0), -90.0], [Vector3(12.95, 0.0, -72.0), -90.0]],
	"helper_points": [Vector3(-10.0, 1.4, -54.5), Vector3(10.0, 1.4, -54.5)],
	"tapestry": {"pos": Vector3(13.25, 0.0, -64.8), "width": 2.0},
}
## Sealed doors: the gallery doors open with mm_ballroom_solved, the balcony doors with ch2_velour_defeated.
const GALLERY_DOOR := {"pos": Vector3(0.0, 0.0, -51.25), "width": 3.2, "height": 3.6, "flag": "mm_ballroom_solved"}
const BALCONY_DOOR := {"pos": Vector3(0.0, 0.0, -77.75), "width": 3.2, "height": 3.6, "flag": "ch2_velour_defeated"}

## Conservatory Balcony.
const LANTERN := Vector3(0.0, 1.8, -92.2)
## Marker only (Pipkin is a later wave; MP §15): on the cap of the north balustrade (floor 1.8 + PARAPET_H +
## cap), between the fern urn and the pumpkins, where a ribbon is tangled round the rail.
const PIPKIN_SPOT := Vector3(-7.3, 2.97, -97.25)
const BALCONY_PLAQUE := Vector3(-2.2, 1.8, -91.2)

## The Count's Wardrobe (MP §15): three guaranteed scraps, each in an optional side room with a visual clue.
const SCRAPS := [
	{"id": "mm_scrap_1", "flag": "ch2_velvet_scrap_1", "room": "powder", "pos": Vector3(8.2, 0.92, -19.2),
		"approach": Vector3(7.0, 0.0, -19.6), "clue": "a velvet ribbon trail behind the folding screen, and a crimson glint in the looking-glass"},
	{"id": "mm_scrap_2", "flag": "ch2_velvet_scrap_2", "room": "nook", "pos": Vector3(-15.2, 1.72, -48.0),
		"approach": Vector3(-13.8, 0.6, -48.0), "clue": "rose petals up the stage steps to a curtain with a velvet tassel"},
	{"id": "mm_scrap_3", "flag": "ch2_velvet_scrap_3", "room": "dressing", "pos": Vector3(18.0, 0.62, -66.2),
		"approach": Vector3(16.6, 0.0, -65.6), "clue": "the Count's portrait points at a tapestry; paper bats flutter toward it"},
]
const TAILOR_NOTE := Vector3(15.0, 0.0, -62.4)

## Enemies inside (spawned only when EnemyFactory knows the id; spec §10).
const SPAWNERS := [
	{"id": "mm_sp_hall_wing", "enemy": "velvet_wing", "pos": Vector3(0.0, 0.0, -27.2), "count": 1, "radius": 1.6, "respawn_minutes": 1440.0},
]

## Lights: at most 3 shadow casters (ballroom chandelier, gallery fixture, balcony moon).
const MAX_SHADOW_LIGHTS := 3

## Ambience per zone (existing loops only). The house itself is quiet (the music director's manor waltz and
## the candles carry it); only the open-air balcony hears the night outside. "" = fade the ambience out.
const AMBIENCE := {"mm_cloakroom": "", "mm_hall": "", "mm_ballroom": "", "mm_gallery": "", "mm_balcony": "amb_forest_night"}

## Echo Trial hook (spec §1: Velour's trial is entered from the ballroom checkpoint). Shown only after the
## Count is freed AND src/world/areas_ch2/echo_trial.gd offers a trial with this id (a later wave).
const ECHO_TRIAL_ID := "velour"
const ECHO_ENTRY := Vector3(8.6, 0.0, -34.6)

## Walkable probe routes used by tests (floor points; consecutive points are connected on foot).
## "gate" names the flag that must be set for that route to be open ("" = always).
const ROUTES := [
	{"gate": "", "points": [Vector3(0, 0, -3.2), Vector3(0, 0, -9.0), Vector3(0, 0, -11.5), Vector3(0, 0, -20.2), Vector3(0, 0, -29.5),
		Vector3(0, 0, -32.2), Vector3(0, 0, -41.0), Vector3(0, 0, -49.8)]},
	{"gate": "", "points": [Vector3(0, 0, -20.2), Vector3(3.0, 0, -20.2), Vector3(5.2, 0, -20.2), Vector3(7.0, 0, -19.6)]},
	{"gate": "", "points": [Vector3(-2.0, 0, -41.0), Vector3(-8.8, 0, -43.8), Vector3(-8.8, 0.6, -47.0), Vector3(-10.4, 0.6, -48.1),
		Vector3(-12.2, 0.6, -48.1), Vector3(-13.8, 0.6, -48.0)]},
	{"gate": "mm_ballroom_solved", "points": [Vector3(0, 0, -49.8), Vector3(0, 0, -52.6), Vector3(0, 0, -64.5), Vector3(8.0, 0, -64.8),
		Vector3(12.3, 0, -64.8), Vector3(14.4, 0, -64.8), Vector3(16.6, 0, -65.6)]},
	{"gate": "ch2_velour_defeated", "points": [Vector3(0, 0, -64.5), Vector3(2.2, 0, -67.0), Vector3(2.2, 0, -75.8), Vector3(0, 0, -76.8),
		Vector3(0, 0, -78.6), Vector3(0, 0.9, -80.0), Vector3(0, 1.8, -82.5), Vector3(0, 1.8, -84.5), Vector3(0, 1.8, -89.0),
		Vector3(0, 1.8, -90.9), Vector3(3.8, 1.8, -87.0)]},
	{"gate": "mm_balcony_shortcut", "points": [Vector3(6.0, 1.8, -89.0), Vector3(8.4, 1.8, -89.0), Vector3(10.2, 1.8, -89.0), Vector3(11.6, 1.8, -89.0)]},
]

# --- Grounds (Hallowmere Reach coordinates) ---------------------------------------------------------

## hr_manor_grounds landmark (18, -74) r 26 (spec §7.2); manor door (18, -86); spawn manor_door (18, -82)
## is registered by the Reach itself (data/hallowmere_layout.gd SPAWNS) and stays outside.
const GROUNDS := {
	"landmark": Vector2(18.0, -74.0), "landmark_r": 26.0,
	"door": Vector2(18.0, -86.0), "door_plane_z": -86.25, "spawn": Vector2(18.0, -82.0),
	"house": {"x0": 7.0, "x1": 29.0, "z0": -98.0, "z1": -87.0, "h": 7.2},
	"tower": {"x0": 14.6, "x1": 21.4, "z0": -89.0, "z1": -86.25, "h": 11.5},
	"turret": {"pos": Vector2(30.2, -89.2), "r": 2.1, "h": 9.5},
	"steps": {"z_bottom": -84.7, "z_top": -86.25, "width": 3.4, "rise": 0.36},
	"path": [Vector2(10.9, -52.8), Vector2(12.4, -59.5), Vector2(14.8, -66.5), Vector2(16.9, -73.5), Vector2(17.9, -79.5), Vector2(18.0, -84.4)],
	"path_w": 2.6,
	"gate": {"pos": Vector2(15.4, -69.0), "width": 4.2},
	"invitation": Vector2(21.6, -85.3),
	"porch_columns": [Vector2(15.9, -85.1), Vector2(20.1, -85.1)],
	"crest_y": 5.5, "lamp_y": 11.5,
	"topiaries": [Vector2(34.2, -70.2), Vector2(29.0, -68.8), Vector2(28.4, -74.2)],
	"birdbath": Vector2(32.2, -73.6),
	"bat_sign": Vector2(27.2, -70.8),
	"found_point": Vector2(17.0, -76.0), "found_r": 16.0,
	"wing_pocket": Vector2(31.0, -71.5), "wing_r": 3.4,
	"flatten": {"center": Vector2(18.0, -90.5), "radius": 11.0, "blend": 15.0},
	"footprints": [[Vector2(18.0, -92.5), 16.5], [Vector2(18.0, -79.5), 6.5], [Vector2(15.4, -69.0), 4.5],
		[Vector2(13.4, -61.5), 3.5], [Vector2(11.6, -56.0), 3.0], [Vector2(16.2, -73.5), 3.0], [Vector2(31.0, -71.5), 6.5]],
}
const GROUNDS_SPAWNER := {"id": "hr_sp_manor_wings", "enemy": "velvet_wing", "count": 2, "radius": 3.4, "respawn_minutes": 1440.0}


# --- Helpers ----------------------------------------------------------------------------------------

## Yaw (radians) that makes a node at `from` face `to` on the XZ plane (forward = -Z).
static func yaw_towards(from: Vector2, to: Vector2) -> float:
	var d := to - from
	if d.length() < 0.001:
		return 0.0
	return atan2(-d.x, -d.y)


static func spawn_xform(id: String) -> Transform3D:
	var s: Dictionary = SPAWNS[id]
	var p: Vector3 = s["pos"]
	return Transform3D(Basis(Vector3.UP, yaw_towards(Vector2(p.x, p.z), s["look"])), p)


static func room_rect(id: String) -> Rect2:
	var r: Dictionary = ROOMS[id]
	return Rect2(float(r["x0"]), float(r["z0"]), float(r["x1"]) - float(r["x0"]), float(r["z1"]) - float(r["z0"]))


## Room id containing the XZ point (rooms never overlap), else "".
static func room_at(pos: Vector3) -> String:
	var p := Vector2(pos.x, pos.z)
	for id in ROOM_ORDER:
		if room_rect(String(id)).has_point(p):
			return String(id)
	return ""


## Floor height of a room at (x, z) (ramps interpolate along their run).
static func floor_y(room_id: String, x: float, z: float) -> float:
	var r: Dictionary = ROOMS.get(room_id, {})
	if r.is_empty():
		return 0.0
	if r.has("ramp"):
		var a: Vector3 = r["ramp"]["from"]
		var b: Vector3 = r["ramp"]["to"]
		var run := Vector2(b.x - a.x, b.z - a.z)
		var t := clampf(Vector2(x - a.x, z - a.z).dot(run) / maxf(run.length_squared(), 0.0001), 0.0, 1.0)
		return lerpf(a.y, b.y, t)
	if room_id == "ballroom" and x >= float(STAGE["x0"]) and x <= float(STAGE["x1"]) and z >= float(STAGE["z0"]) and z <= float(STAGE["z1"]):
		return float(STAGE["top"])
	return float(r["y"])


## Every opening as {room, side, from, to, top, bottom, width, height, center: Vector3} (tests, thresholds).
static func openings() -> Array:
	var out: Array = []
	for id in ROOM_ORDER:
		var r: Dictionary = ROOMS[id]
		var walls: Dictionary = r.get("walls", {})
		for side in walls:
			for o in walls[side]:
				var a := float(o[0])
				var b := float(o[1])
				var top := float(o[2])
				var bottom := float(o[3]) if (o as Array).size() > 3 else 0.0
				var y := float(r["y"])
				var c := Vector3.ZERO
				var mid := (a + b) * 0.5
				match String(side):
					"n": c = Vector3(mid, y + bottom, float(r["z0"]) - WALL_T * 0.5)
					"s": c = Vector3(mid, y + bottom, float(r["z1"]) + WALL_T * 0.5)
					"w": c = Vector3(float(r["x0"]) - WALL_T * 0.5, y + bottom, mid)
					"e": c = Vector3(float(r["x1"]) + WALL_T * 0.5, y + bottom, mid)
				out.append({"room": String(id), "side": String(side), "from": a, "to": b, "top": top, "bottom": bottom,
					"width": b - a, "height": top - bottom, "center": c, "mirror": id == "hall" and side == "w",
					"blocked": id == "landing" and side == "e"})   # the garden stair exit fills that gap
	return out


static func zone_of(room_id: String) -> String:
	return String(ROOMS.get(room_id, {}).get("zone", ""))
