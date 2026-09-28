extends RefCounted
## Small masteries (MP 5.3, docs/CHAPTER_TWO_SPEC.md 4.7): three persistent five-rank tracks earned through play.
## State (GameState.mastery): {"gathering": xp, "hearthcraft": xp, "wayfinding": xp,
##   "seen": {track: ["<rule>:<id>", ...]}, "legacy_credit": bool} (+ the mastery module's daily ledger).
## No rank is ever a main-story gate. Read through ItemDB.mastery_* accessors.
##
## Exploit resistance (data rules the mastery module enforces):
##  * "once_per" rules award XP only the FIRST time for each id (recorded in seen[track] as "<rule>:<id>"),
##    so dismantling and rebuilding, re-crafting, re-equipping or reloading never repeats them.
##  * repeatable rules ("daily_cap") count ordinary play (natural respawns, farming) up to a cap per in-game day.
##  * NO_XP lists actions that never give XP.
##  * legacy credit is applied once (legacy_credit = true), conservative, and capped below LEGACY_CAP_XP.

const TRACKS := ["gathering", "hearthcraft", "wayfinding"]
const MAX_RANK := 5
## Total XP needed for rank 0..5 (index = rank).
const RANK_XP := [0, 40, 110, 220, 380, 600]

const TRACK_NAMES := {
	"gathering": {"name": "Gathering", "desc": "Harvest different nodes, discover materials and keep gathering."},
	"hearthcraft": {"name": "Hearthcraft", "desc": "Craft new recipes, place distinct furnishings, harvest crops and grow your workshop."},
	"wayfinding": {"name": "Wayfinding", "desc": "Discover landmarks, open shortcuts, read lore and face varied encounters."},
}

## XP rules per track. once_per = the id kind that makes the award unique; daily_cap = most XP per in-game day.
const XP := {
	"gathering": {
		"first_node_kind": {"xp": 12, "once_per": "node_kind", "desc": "First harvest of each kind of node (tree, iron vein, sunflax patch...)"},
		"first_material": {"xp": 8, "once_per": "item", "desc": "First time a material enters the backpack from gathering"},
		"harvest": {"xp": 1, "daily_cap": 30, "desc": "Each fully harvested renewable node"},
	},
	"hearthcraft": {
		"first_recipe": {"xp": 10, "once_per": "recipe", "desc": "First craft of each recipe"},
		"first_structure": {"xp": 8, "once_per": "structure", "desc": "First placement of each DISTINCT structure id (re-placing gives nothing)"},
		"first_station_use": {"xp": 15, "once_per": "station", "desc": "First use of each workshop station (furnace, loom, kitchen)"},
		"crop_harvest": {"xp": 3, "daily_cap": 24, "desc": "Each real crop harvest (ripe plot)"},
		"craft": {"xp": 1, "daily_cap": 15, "desc": "Any further craft"},
	},
	"wayfinding": {
		"landmark": {"xp": 15, "once_per": "landmark", "desc": "Discovering a map landmark (GameState.discover)"},
		"shortcut": {"xp": 20, "once_per": "shortcut", "desc": "Opening a return shortcut"},
		"lore": {"xp": 10, "once_per": "lore", "desc": "Reading a new lore entry"},
		"arch": {"xp": 20, "once_per": "arch", "desc": "Lighting a Lantern Road arch"},
		"encounter": {"xp": 15, "once_per": "encounter", "desc": "First clear of each distinct authored encounter / spawner id"},
	},
}

## Never award XP for these (MP 5.3).
const NO_XP := ["dismantle", "rebuild_same_structure", "move_items_between_chests", "load_save", "equip_or_unequip",
	"restyle_appearance", "heal_self_inflicted_damage", "hit_invulnerable_target", "practice_dummy", "trial_repeat_clear"]

## Rewards reached at each rank. Values are the TOTAL from that rank on (not added to lower ranks).
##   gather_power        extra harvest power per hit (combined with charms, capped by GATHER_BONUS_CAP)
##   bonus_yield_chance  chance of +1 of the node's main drop
##   highlight_radius    nearby material highlight (metres)
##   recipes             mastery-gated recipe ids (data/recipes.gd `mastery`) that become known
##   furnace_queue_bonus (+jobs) / station_time_mult (x job time) / meal_buff_bonus (fraction longer food buffs)
##                       modest workshop conveniences
##   sprint_stamina_save fraction less sprint stamina; map_* map clarity options
##   map_resource_pins   the map pins recorded resource spots (SPOT_* below; Mastery.known_spots)
##   map_cache_hints     the map shows a soft "?" for unfound caches in discovered districts (MAP_CACHE_HINTS)
const REWARDS := {
	"gathering": {
		1: {"gather_power": 0.05, "text": "Gathering takes 5% less effort."},
		2: {"bonus_yield_chance": 0.05, "text": "5% chance of an extra material."},
		3: {"gather_power": 0.1, "text": "Gathering takes 10% less effort."},
		4: {"highlight_radius": 18.0, "text": "Nearby materials sparkle softly within 18 m."},
		5: {"bonus_yield_chance": 0.1, "text": "10% chance of an extra material."},
	},
	"hearthcraft": {
		1: {"recipes": ["crescent_window"], "text": "Recipe: Crescent Window."},
		2: {"recipes": ["gothic_trim"], "text": "Recipe: Gothic Porch Trim."},
		3: {"furnace_queue_bonus": 1, "text": "Furnaces hold one more job."},
		4: {"meal_buff_bonus": 0.15, "text": "Meal buffs last 15% longer."},
		5: {"station_time_mult": 0.85, "text": "Furnace jobs finish 15% sooner."},
	},
	"wayfinding": {
		1: {"sprint_stamina_save": 0.05, "text": "Sprinting costs 5% less stamina."},
		2: {"map_resource_pins": true, "text": "The map remembers where you gathered special materials."},
		3: {"sprint_stamina_save": 0.1, "text": "Sprinting costs 10% less stamina."},
		4: {"map_cache_hints": true, "text": "The map hints at hidden caches in places you have found."},
		5: {"sprint_stamina_save": 0.15, "text": "Sprinting costs 15% less stamina."},
	},
}

## --- Map clarity (Wayfinding 2 / 4) and the material sparkle (Gathering 4), MP 5.3 / 16 -------------------------
## Resource spots: Mastery records where Krystal fully harvested a node (Events.harvested) in GameState.mastery
## ["spots"][area][kind] = [[x, z], ...] (JSON-safe), only in SPOT_AREAS (the painted outdoor maps), never for the
## everyday SPOT_SKIP_KINDS (they grow everywhere: pinning them would drown the map in identical marks), a spot
## closer than SPOT_MIN_DIST to a known one of the same kind is the same spot, and at most SPOT_MAX_PER_KIND per
## kind and area are kept (the oldest is forgotten first). Recorded from the start (small and bounded), so reaching
## Wayfinding 2 shows what she already gathered; the map draws them only while map_resource_pins is in effect.
const SPOT_AREAS := ["surface", "hallowmere_reach"]
const SPOT_SKIP_KINDS := ["tree", "rock", "stick", "stone", "grass", "rubble"]
const SPOT_MIN_DIST := 6.0
const SPOT_MAX_PER_KIND := 24

## Optional caches the map hints at once map_cache_hints is in effect: a soft, steady "?" at the cache once its
## `district` (landmark id of `area`) is discovered, gone for good once the owner module's `flag` is set. Positions
## are read (never copied) from the owner's layout constant: script `layout`, constant `const`, and `key` when the
## constant is a Dictionary. A missing file / constant simply shows no hint.
const MAP_CACHE_HINTS := [
	{"id": "tailor_cache", "area": "surface", "district": "old_oak", "flag": "c1x_tailor_cache",
		"layout": "res://data/c1x_layout.gd", "const": "TAILOR_CACHE", "key": "pos"},
	{"id": "witch_hat", "area": "hallowmere_reach", "district": "hr_candleyard", "flag": "ch2_witch_hat_found",
		"layout": "res://data/reach_west.gd", "const": "HAT", "key": "pos"},
	{"id": "festival_pouch", "area": "hallowmere_reach", "district": "hr_pools", "flag": "hr_chime_trail_done",
		"layout": "res://data/reach_west.gd", "const": "POUCH"},
	{"id": "candleyard_pattern", "area": "hallowmere_reach", "district": "hr_candleyard", "flag": "ch2_candleyard_pattern",
		"layout": "res://data/reach_west.gd", "const": "PATTERN_SPOT"},
]

## Gathering 4 (highlight_radius): a steady sparkle (never blinking) over the nearest non-depleted harvestables,
## at most HIGHLIGHT_MAX, refreshed every HIGHLIGHT_REFRESH seconds from a registry (never a per-frame group scan).
## Special materials come first; trees (big and obvious) and quest rubble never sparkle.
const HIGHLIGHT_MAX := 12
const HIGHLIGHT_REFRESH := 0.5
const HIGHLIGHT_SKIP_KINDS := ["tree", "rubble"]

## Combined non-combat caps (mastery + charms), kept modest and visible.
const GATHER_BONUS_CAP := 0.25
const YIELD_CHANCE_CAP := 0.15

## One-time conservative credit for saves that already have Chapter One progress (applied once, recorded in
## mastery.legacy_credit). Each source: counter / stat / flag / list size from the saved state x xp_each, capped.
## A track's total legacy credit never exceeds LEGACY_CAP_XP (below rank 2).
const LEGACY_CAP_XP := 100
const LEGACY_CREDIT := {
	"gathering": [
		{"source": "counter", "key": "trees_felled", "xp_each": 2, "cap": 40},
		{"source": "flag", "key": "mine_opened", "xp": 12},
		{"source": "flag", "key": "entered_below", "xp": 12},
	],
	"hearthcraft": [
		{"source": "counter", "key": "structures_built", "xp_each": 1, "cap": 30},
		{"source": "counter", "key": "crops_harvested", "xp_each": 2, "cap": 20},
		{"source": "stat", "key": "items_crafted", "xp_each": 1, "cap": 20},
	],
	"wayfinding": [
		{"source": "lore_count", "key": "lore", "xp_each": 10, "cap": 40},
		{"source": "flag", "key": "reached_silk_hollows", "xp": 20},
		{"source": "flag", "key": "chapter_one_complete", "xp": 30},
	],
}
