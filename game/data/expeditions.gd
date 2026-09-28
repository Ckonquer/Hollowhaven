extends RefCounted
## Lanternwake Expeditions (MP §15 "Post-story sandbox"; module D2). Three HAND-AUTHORED replay routes through
## Hallowmere Reach, chosen at the Expedition Board (the board's recipe unlocks with ch2_choir_defeated,
## data/unlocks.gd). Not procedural dungeons: every stop, spawn point and cache below is a fixed, validated
## place in the Reach (tests/unit/test_expeditions_templates.gd builds the Reach and checks each one). A small
## saved random seed (1..SEED_MAX) only picks WHICH authored group waits at each stop, the order of the spawn
## points and the amounts of the renewable rewards (src/expeditions/expeditions.gd plan()).
## Coordinates: ABSOLUTE Reach metres on the XZ plane, Vector2(x, z) (x = east, z = south), like
## data/hallowmere_layout.gd. Heights always come from the region (area.height_at + a ground ray).
##
## Template fields:
##   name, blurb           shown on the board before starting
##   difficulty            key of DIFFICULTIES (label + lantern pips + one-line expectation)
##   requires              a flag that must already be true (read only; expeditions never WRITE flags)
##   requires_text         why a template is not offered yet
##   arch                  the Lantern Road arch (data/hallowmere_layout.gd ARCHES) nearest the first stop
##   minutes               rough length, shown before starting
##   stops                 2..4 ordered stops: {id, name, pos (the ribbon lantern), points [spawn points],
##                         groups [alternative groups: [[enemy id, count], ...]]} - the seed picks one group
##   cache                 {id, name, pos}: opened once every stop is quiet; pays the run's rewards once
##   rewards               {base: {item: [min, max]}, picks: {count, from: {item: [min, max]}},
##                         keepsake_chance, keepsakes: [{kind: "dye", id} | {kind: "decor", item, count}]}
##   reward_types          the reward TYPES shown before starting (never the exact roll)
## Rewards are renewable materials, candy and, sometimes (always on a route's first completion), a keepsake:
## a new dye colour (its Loom palette, data/appearance.gd DYE_PALETTES, unlocked directly as a gift - no Loom
## cost; it colours clothes and furniture) or a festival decoration. Never a story item, never a flag, never
## anything only an expedition can give (every keepsake is also made at the Loom / workbench), no daily limit,
## no timer. A route's first completion also gives FIRST_ROUTE_WAYFINDING_XP Wayfinding mastery xp (once per route).
## Rules the tests enforce: enemy ids exist (data/enemies.gd + EnemyFactory), group sizes respect the enemy's
## max_group, no spider-like enemy (no alt_name) so nothing needs an arachnophobia swap, spawn points are
## walkable, dry, outside every safe zone and at least ARCH_CLEARANCE from every Lantern Road arch and the
## arrival, and at least SPAWNER_CLEARANCE from the districts' own renewable spawner pockets.

const AREA_ID := "hallowmere_reach"
## GameState.extra key holding the expedition state (see src/expeditions/expeditions.gd header).
const STATE_KEY := "expeditions"
const STATE_VERSION := 1
const SEED_MAX := 9999

const ORDER := ["orchard_patrol", "quarry_circuit", "manor_afterglow"]

## Spawning rules (src/expeditions/expedition_runner.gd).
const SPAWN_RADIUS := 34.0          # Krystal within this of the stop's lantern -> the group may appear
const DESPAWN_RADIUS := 80.0        # farther than this -> the living ones go home (defeats are remembered)
const MIN_SPAWN_DISTANCE := 5.0     # never closer than this to Krystal (the points ring the lantern at 3-9 m)
const VIEW_DISTANCE := 95.0         # a point farther than this from the camera is never "in view"
const ENEMY_WANDER := 4.0
## Layout rules (tests).
const ARCH_CLEARANCE := 14.0
const SPAWNER_CLEARANCE := 16.0
const POINT_SPREAD := 9.0           # every spawn point within this of its stop's lantern
const MIN_STOPS := 2
const MAX_STOPS := 4
## Wayfinding mastery xp for a route's FIRST completion (Mastery.award "expedition:<route>", deduped per route;
## the size of the other first-time Wayfinding rules such as "shortcut" / "arch").
const FIRST_ROUTE_WAYFINDING_XP := 20

const DIFFICULTIES := {
	"gentle": {"name": "Gentle", "pips": 1,
		"text": "Small groups of garden troublemakers. A good first outing."},
	"brisk": {"name": "Brisk", "pips": 2,
		"text": "Sturdier quarry folk in twos and threes. Bring a good tool and a snack."},
	"bold": {"name": "Bold", "pips": 3,
		"text": "Quick fliers and heavy hitters together. The richest cache, for when you feel ready."},
}

const TEMPLATES := {
	"orchard_patrol": {
		"name": "Orchard Patrol",
		"blurb": "Walk the Pumpkintide Orchard's quiet edges and send the restless patches back to sleep.",
		"difficulty": "gentle",
		"requires": "ch2_orchard_restored",
		"requires_text": "Opens once the Pumpkintide Orchard's lamp is lit again.",
		"arch": "orchard",
		"minutes": "10-15",
		"stops": [
			{"id": "exp_op_meadow", "name": "Scarecrow Meadow", "pos": Vector2(-76.0, 70.0),
				"points": [Vector2(-81.0, 66.0), Vector2(-71.0, 66.0), Vector2(-82.0, 74.5), Vector2(-69.5, 72.0), Vector2(-76.0, 77.0)],
				"groups": [[["patchwalker", 1], ["brambling", 2]], [["pumpkin_mimic", 1], ["brambling", 1]], [["brambling", 3]]]},
			{"id": "exp_op_hedgerow", "name": "Western Hedgerow", "pos": Vector2(-123.0, 28.0),
				"points": [Vector2(-126.0, 23.0), Vector2(-120.0, 23.5), Vector2(-127.5, 30.5), Vector2(-119.5, 30.5), Vector2(-124.0, 35.0)],
				"groups": [[["pumpkin_mimic", 2]], [["patchwalker", 1], ["pumpkin_mimic", 1]], [["brambleback", 1], ["brambling", 1]]]},
			{"id": "exp_op_cistern", "name": "Old Cistern Field", "pos": Vector2(-106.0, -6.0),
				"points": [Vector2(-111.0, -9.5), Vector2(-100.5, -10.0), Vector2(-111.0, -1.0), Vector2(-100.0, -1.5), Vector2(-106.0, -13.0)],
				"groups": [[["patchwalker", 2]], [["brambleback", 1], ["pumpkin_mimic", 1]], [["patchwalker", 1], ["brambling", 2]]]},
		],
		"cache": {"id": "exp_op_cache", "name": "the harvest crate", "pos": Vector2(-90.0, -2.0)},
		"rewards": {
			"base": {"candy": [2, 3], "pumpkin": [2, 3]},
			"picks": {"count": 2, "from": {"roseberries": [2, 4], "sunflax": [2, 3], "resin": [1, 2], "pumpkin_seeds": [1, 2],
				"roseberry_seeds": [1, 2], "fiber": [3, 5]}},
			"keepsake_chance": 0.34,
			"keepsakes": [{"kind": "dye", "id": "pumpkin"}, {"kind": "dye", "id": "rose"},
				{"kind": "decor", "item": "pumpkin_lights", "count": 2}, {"kind": "decor", "item": "candy_bowl", "count": 1}],
		},
		"reward_types": ["Orchard produce: pumpkins, roseberries, sunflax, resin, seeds", "Lanternwake candy",
			"Sometimes: a new dye colour (Pumpkin or Rose) for clothes and furniture, or a festival decoration"],
	},
	"quarry_circuit": {
		"name": "Quarry Circuit",
		"blurb": "A loop around Ashbell Quarry's spoil fields and cuttings, where the stubborn diggers wander back at night.",
		"difficulty": "brisk",
		"requires": "ch2_quarry_restored",
		"requires_text": "Opens once the quarry lamp burns again.",
		"arch": "quarry",
		"minutes": "15-20",
		"stops": [
			{"id": "exp_qc_haul", "name": "Haul Road Meadow", "pos": Vector2(78.0, 53.0),
				"points": [Vector2(73.5, 51.0), Vector2(83.0, 50.5), Vector2(74.0, 56.0), Vector2(82.5, 57.0), Vector2(78.0, 60.0)],
				"groups": [[["brambleback", 1], ["brambling", 2]], [["hollow_drudge", 1], ["brambling", 2]], [["brambleback", 2]]]},
			{"id": "exp_qc_tailings", "name": "Tailings Meadow", "pos": Vector2(55.0, 1.0),
				"points": [Vector2(51.0, -2.0), Vector2(59.0, -3.5), Vector2(50.5, 5.0), Vector2(55.0, 7.0), Vector2(55.0, -7.0)],
				"groups": [[["hollow_drudge", 2]], [["bellcap_sentry", 1], ["hollow_drudge", 1]], [["brambleback", 1], ["hollow_drudge", 1]]]},
			{"id": "exp_qc_cutting", "name": "The North Cutting", "pos": Vector2(92.0, -30.0),
				"points": [Vector2(87.0, -33.0), Vector2(97.0, -33.0), Vector2(87.0, -26.0), Vector2(97.0, -26.0), Vector2(92.0, -36.0)],
				"groups": [[["bellcap_sentry", 2]], [["bellcap_sentry", 1], ["brambleback", 1]], [["hollow_drudge", 1], ["bellcap_sentry", 1]]]},
			{"id": "exp_qc_rise", "name": "Bellfoot Rise", "pos": Vector2(114.0, -20.0),
				"points": [Vector2(109.0, -23.0), Vector2(119.0, -23.0), Vector2(109.0, -16.0), Vector2(119.0, -15.5), Vector2(114.0, -26.0)],
				"groups": [[["hollow_drudge", 2], ["brambleback", 1]], [["bellcap_sentry", 2], ["brambling", 1]], [["brambleback", 2], ["hollow_drudge", 1]]]},
		],
		"cache": {"id": "exp_qc_cache", "name": "the old ore cart", "pos": Vector2(102.0, -12.0)},
		"rewards": {
			"base": {"candy": [2, 3], "iron_ore": [3, 5]},
			"picks": {"count": 2, "from": {"copper_bar": [1, 2], "iron_bar": [1, 2], "moon_crystal": [1, 1], "echo_shard": [1, 1],
				"resin": [1, 2], "glowcap": [1, 2]}},
			"keepsake_chance": 0.34,
			"keepsakes": [{"kind": "dye", "id": "ember"}, {"kind": "dye", "id": "cream"},
				{"kind": "decor", "item": "crescent_window", "count": 1}, {"kind": "decor", "item": "gothic_trim", "count": 2}],
		},
		"reward_types": ["Quarry materials: iron ore, copper and iron bars, resin, sometimes moon crystal or an echo shard",
			"Lanternwake candy", "Sometimes: a new dye colour (Ember or Cream) for clothes and furniture, or a festival decoration"],
	},
	"manor_afterglow": {
		"name": "Manor Afterglow",
		"blurb": "After the Count's ball, a few guests never went home. Walk Moonveil's lawns and the Bell Road by lantern light.",
		"difficulty": "bold",
		"requires": "ch2_manor_restored",
		"requires_text": "Opens once Moonveil Manor's lamp is lit again.",
		"arch": "manor",
		"minutes": "15-20",
		"stops": [
			{"id": "exp_ma_lawn", "name": "The Moonlit Lawn", "pos": Vector2(-6.0, -74.0),
				"points": [Vector2(-11.0, -78.0), Vector2(-1.0, -79.0), Vector2(-12.0, -70.0), Vector2(-1.0, -69.0), Vector2(-6.0, -82.0)],
				"groups": [[["velvet_wing", 2], ["patchwalker", 1]], [["lantern_moth", 2], ["patchwalker", 1]],
					[["velvet_wing", 1], ["lantern_moth", 1], ["pumpkin_mimic", 1]]]},
			{"id": "exp_ma_bend", "name": "The Bell Road Bend", "pos": Vector2(44.0, -54.0),
				"points": [Vector2(39.0, -50.0), Vector2(49.0, -50.0), Vector2(48.0, -58.0), Vector2(41.0, -57.5), Vector2(44.0, -47.0)],
				"groups": [[["hollow_drudge", 2], ["velvet_wing", 1]], [["patchwalker", 2], ["lantern_moth", 1]],
					[["velvet_wing", 2], ["hollow_drudge", 1]]]},
			{"id": "exp_ma_garden", "name": "The Sunken Garden", "pos": Vector2(48.0, -92.0),
				"points": [Vector2(43.0, -96.0), Vector2(52.5, -97.0), Vector2(42.0, -88.5), Vector2(54.0, -89.0), Vector2(48.0, -99.0)],
				"groups": [[["velvet_wing", 2], ["lantern_moth", 2]], [["patchwalker", 2], ["velvet_wing", 2]],
					[["hollow_drudge", 2], ["lantern_moth", 1], ["velvet_wing", 1]]]},
		],
		"cache": {"id": "exp_ma_cache", "name": "the afterglow chest", "pos": Vector2(37.0, -94.0)},
		"rewards": {
			"base": {"candy": [3, 4], "lantern_wax": [2, 3]},
			"picks": {"count": 2, "from": {"moonpetal": [2, 3], "woven_cloth": [1, 2], "sugarcap": [2, 3], "roseberries": [2, 3],
				"echo_shard": [1, 1], "glowcap": [1, 2]}},
			"keepsake_chance": 0.34,
			"keepsakes": [{"kind": "dye", "id": "lavender"}, {"kind": "dye", "id": "midnight"},
				{"kind": "decor", "item": "bat_bunting", "count": 2}, {"kind": "decor", "item": "crescent_window", "count": 1}],
		},
		"reward_types": ["Festival supplies: lantern wax, moonpetals, cloth, sugarcaps, sometimes an echo shard",
			"Lanternwake candy", "Sometimes: a new dye colour (Lavender or Midnight) for clothes and furniture, or a festival decoration"],
	},
}

## Board / tracker / map text. {name} {stop} {n} {total} {cache} {colour} are filled in by the logic.
const TEXT := {
	"started": "Expedition begun: {name}. Follow the ribbon lantern to {stop}.",
	"stop_clear": "{stop} is quiet again ({n}/{total}). Next: {next}.",
	"route_clear": "The route is clear! A Lanternwake cache waits at {cache}.",
	"complete": "Expedition complete: {name}.",
	"dye_keepsake": "a new dye colour ({colour})",
	"abandoned": "Expedition set aside. Nothing is lost; start again whenever you like.",
	"abandoned_cache": "Expedition set aside. Its cache stays closed, but nothing you carry is lost; start again whenever you like.",
	"abandon_confirm": "Really set it aside? (nothing is lost)",
	"abandon_confirm_cache": "Really set it aside? Its cache stays closed",
	"hint": "Expeditions are optional: go when you like, stop when you like. A ribbon lantern marks each stop, and nothing is lost if you set one aside.",
	"cache_prompt": "Open {cache}",
	"lantern_name": "Expedition lantern",
}
