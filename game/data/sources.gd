extends RefCounted
## Where every item comes from (MP 5.2 / 16, docs/CHAPTER_TWO_SPEC.md 4). World-building modules place their
## harvestable nodes from NODES (kind -> where / how many / tool tier), story and optional modules grant the
## REWARDS bundles through GameState.grant_once, and tests prove every item is obtainable from renewable raw
## sources with no circular dependency. Read through ItemDB.sources(item_id), ItemDB.node_kind(kind),
## ItemDB.node_kinds_in(area_id), ItemDB.reward_bundle(reward_id), ItemDB.is_story_required(item_id).
##
## ITEM_SOURCES[item_id] = [source, ...]; source "kind":
##   gather     {"node": NODES kind}                    harvesting a world node (tool / tier / access in NODES)
##   crop       {"crop": CROPS id}                      harvesting a ripe crop plot or sturdy planter
##   recipe     {"recipe": id}                          crafting (hand / workbench / campfire / loom / kitchen)
##   station    {"station": "furnace", "recipe": id}    queued station processing (furnace jobs with `time`)
##   drop       {"enemy": id}                           enemy drop (never guaranteed, never the only source of a
##                                                      story-required item)
##   reward     {"reward": REWARDS id}                  story / optional reward, granted once through the ledger
##   pickup     {"where": {area: [zones]}, "desc"}      fixed one-time world pickup placed by an area module
##   companion  {"companion": id, "desc"}               a befriended companion brings it (bounded, renewable)
## Every source carries "guaranteed" (always obtainable on an accessible route, not random) and "renewable"
## (comes back: respawning nodes, crops, repeatable drops) except recipe / station sources, which inherit both
## from their ingredients. There is NO shop in this release (SHOPS is empty on purpose).

const SHOPS := {}

## World node id prefix per area for NEW nodes (spec section 2): ids are "<prefix>_<kind>_<n>".
const AREA_PREFIX := {"surface": "c1x", "below": "c1x", "tobin_annex": "ta", "hallowmere_reach": "hr",
	"moonveil_manor": "mm", "hushed_works": "hw"}

## Harvestable node kinds. tool hand | axe | pickaxe, min_tier = lowest tool tier that can harvest it (stone 1 ..
## moonsteel 4; ItemDB.item_tier), hits = hits at power 1 (each hit counts the tool's power), where = area ->
## zone / landmark ids, min_count = guaranteed nodes per area on accessible routes, access_flag = the flag that
## makes that pocket reachable ("" = reachable as soon as the area is). legacy = the kind already exists in
## src/world/common/resource_node.gd or src/world/below/below_resource.gd (those scripts own its numbers).
const NODES := {
	# --- legacy kinds (Chapter One nodes stay as they are; new areas may place more of them) ---
	"tree": {"name": "Tree", "tool": "axe", "min_tier": 1, "hits": 4, "drops": [{"item": "wood", "min": 3, "max": 5, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"surface": ["woods", "glade", "old_oak", "thicket"], "hallowmere_reach": ["hr_commons", "hr_orchard", "hr_candleyard", "hr_manor_grounds"]},
		"min_count": {"hallowmere_reach": 14}, "access_flag": "", "legacy": true},
	"stick": {"name": "Stick", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "wood", "min": 1, "max": 1, "chance": 1.0}], "respawn_minutes": 600.0,
		"where": {"surface": ["haven", "woods", "meadow"], "hallowmere_reach": ["hr_commons", "hr_orchard"]}, "min_count": {"hallowmere_reach": 8}, "access_flag": "", "legacy": true},
	"rock": {"name": "Boulder", "tool": "pickaxe", "min_tier": 1, "hits": 3, "drops": [{"item": "stone", "min": 2, "max": 4, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"surface": ["quarry", "woods"], "hallowmere_reach": ["hr_quarry", "hr_pools"]}, "min_count": {"hallowmere_reach": 8}, "access_flag": "", "legacy": true},
	"stone": {"name": "Stone", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "stone", "min": 1, "max": 1, "chance": 1.0}], "respawn_minutes": 600.0,
		"where": {"surface": ["haven", "woods", "quarry"], "hallowmere_reach": ["hr_commons", "hr_quarry"]}, "min_count": {"hallowmere_reach": 8}, "access_flag": "", "legacy": true},
	"ore": {"name": "Copper Vein", "tool": "pickaxe", "min_tier": 1, "hits": 4, "drops": [{"item": "copper_ore", "min": 2, "max": 3, "chance": 1.0}, {"item": "stone", "min": 1, "max": 1, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"surface": ["quarry"], "hallowmere_reach": ["hr_quarry"]}, "min_count": {"hallowmere_reach": 4}, "access_flag": "", "legacy": true},
	"grass": {"name": "Tall Grass", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "fiber", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 480.0,
		"where": {"surface": ["haven", "woods", "meadow", "glade"], "hallowmere_reach": ["hr_commons", "hr_orchard", "hr_pools", "hr_candleyard"]}, "min_count": {"hallowmere_reach": 16}, "access_flag": "", "legacy": true},
	"bush": {"name": "Berry Bush", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "berries", "min": 2, "max": 4, "chance": 1.0}, {"item": "sweetroot_seeds", "min": 1, "max": 1, "chance": 0.25}], "respawn_minutes": 720.0,
		"where": {"surface": ["glade", "woods", "meadow"]}, "min_count": {}, "access_flag": "", "legacy": true},
	"glowcap": {"name": "Glowcap Cluster", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "glowcap", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"below": ["mine", "ruins", "silk"], "hushed_works": ["hw_refuge", "hw_lightwell"]}, "min_count": {"hushed_works": 4}, "access_flag": "", "legacy": true},
	"silk": {"name": "Silk Clump", "alt_name": "Pale Thread Tangle", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "silk", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"below": ["silk"], "hushed_works": ["hw_winch"]}, "min_count": {"hushed_works": 3}, "access_flag": "ch2_crossing_cleared", "legacy": true,
		"note": "Renewable post-discovery pocket: the Threaded Winch, once Weaver's Crossing is cleared."},
	"crystal": {"name": "Echo Crystal", "tool": "pickaxe", "min_tier": 1, "hits": 3, "drops": [{"item": "echo_shard", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"below": ["ruins", "silk"], "tobin_annex": ["ta_sump"], "hushed_works": ["hw_refuge"]}, "min_count": {"tobin_annex": 2, "hushed_works": 3}, "access_flag": "", "legacy": true,
		"note": "Renewable post-discovery pockets: Tobin's sump and the Pocket Conservatory refuge."},
	# --- Chapter Two kinds ---
	# Reach ids placed so far (data/reach_west.gd NODES): sunflax hr_sunflax_0..5 are all in the orchard (the six
	# guaranteed Reach nodes); Commons sunflax, if a module adds some, would start at hr_sunflax_6.
	"sunflax_patch": {"name": "Wild Sunflax", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "sunflax", "min": 2, "max": 3, "chance": 1.0}, {"item": "sunflax_seeds", "min": 1, "max": 1, "chance": 0.35}], "respawn_minutes": 720.0,
		"where": {"surface": ["meadow"], "hallowmere_reach": ["hr_commons", "hr_orchard"]}, "min_count": {"surface": 4, "hallowmere_reach": 6}, "access_flag": "",
		"note": "Surface: the Sunny Meadow gardener's patch (A Gardener's Afternoon), outside the Haven build area."},
	"roseberry_bush": {"name": "Roseberry Bush", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "roseberries", "min": 2, "max": 4, "chance": 1.0}, {"item": "roseberry_seeds", "min": 1, "max": 1, "chance": 0.3}], "respawn_minutes": 720.0,
		"where": {"surface": ["meadow"], "hallowmere_reach": ["hr_orchard", "hr_candleyard"]}, "min_count": {"surface": 3, "hallowmere_reach": 6}, "access_flag": "",
		"note": "Surface: a roseberry cluster beside the meadow sunflax patch; Reach: orchard hedges and Candleyard edges."},
	# Reach sap stumps (data/reach_west.gd NODES): hr_resin_0/1 in the orchard, hr_resin_2/3 in the Candleyard.
	"sap_stump": {"name": "Sap Stump", "tool": "hand", "min_tier": 0, "hits": 1, "verb": "Tap", "drops": [{"item": "resin", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 900.0,
		"where": {"surface": ["woods", "glade", "old_oak", "thicket"], "hallowmere_reach": ["hr_orchard", "hr_candleyard"]}, "min_count": {"surface": 5, "hallowmere_reach": 4}, "access_flag": "",
		"note": "Tappable old stumps; never inside the Haven build area. No creature is ever harmed for resin."},
	"iron_vein": {"name": "Iron Vein", "tool": "pickaxe", "min_tier": 1, "hits": 6, "drops": [{"item": "iron_ore", "min": 2, "max": 3, "chance": 1.0}, {"item": "stone", "min": 1, "max": 1, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"hallowmere_reach": ["hr_quarry"]}, "min_count": {"hallowmere_reach": 8}, "access_flag": "",
		"note": "Lower Ashbell terraces. A stone pickaxe works (6 hits); copper and better tools are faster."},
	"moon_crystal_vein": {"name": "Moon Crystal Seam", "tool": "pickaxe", "min_tier": 3, "hits": 5, "drops": [{"item": "moon_crystal", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"hallowmere_reach": ["hr_quarry"]}, "min_count": {"hallowmere_reach": 5}, "access_flag": "ch2_winch_repaired",
		"note": "Upper Ashbell shelf, reached after the winch repair. Needs an Ironwood pickaxe or better."},
	"sugarcap_patch": {"name": "Sugarcap Patch", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "sugarcap", "min": 2, "max": 3, "chance": 1.0}], "respawn_minutes": 900.0,
		"where": {"hallowmere_reach": ["hr_pools"]}, "min_count": {"hallowmere_reach": 5}, "access_flag": ""},
	"moonpetal_patch": {"name": "Moonpetals", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "moonpetal", "min": 2, "max": 3, "chance": 1.0}], "respawn_minutes": 900.0,
		"where": {"hallowmere_reach": ["hr_pools", "hr_candleyard"]}, "min_count": {"hallowmere_reach": 8}, "access_flag": "",
		"note": "Pool and Candleyard edges; no fighting needed."},
	"pumpkin_vine": {"name": "Pumpkin Vine", "tool": "hand", "min_tier": 0, "hits": 1, "drops": [{"item": "pumpkin", "min": 1, "max": 1, "chance": 1.0}, {"item": "pumpkin_seeds", "min": 1, "max": 2, "chance": 1.0}], "respawn_minutes": 1440.0,
		"where": {"hallowmere_reach": ["hr_orchard"]}, "min_count": {"hallowmere_reach": 6}, "access_flag": "",
		"note": "Orchard beds (never in the mimic pockets). Harvest always gives replantable seeds."},
}

## One-time reward bundles. Every one of them goes through the ONE reward ledger (GameState.grant_once(reward_id,
## items, flags)), so a bundle id is paid exactly once whoever calls it first. `by` says who grants it:
##  * "chapter_log" / "optional_log": the Chapter Two quest layer / the optional log grant "rw_" + step / goal id
##    with the on_complete / reward of data/quests_ch2.gd / data/optional_goals.gd. The entries below with such an
##    id MIRROR those files exactly (tests on both sides check it). Content modules never grant them: they only set
##    the objective flags and the log pays the reward. ItemDB.reward_bundle() also returns the log rewards that
##    are not mirrored here (read from those two files).
##  * "content": the named content module grants the bundle ITSELF at its event (a cache opened, a boss beaten, a
##    pickup found). A step / goal completed by one of its flags never gives one of its items again (tests), so
##    one activity never pays the same item twice. The content bundles and the module that grants each one:
##      rw_c1x_gardener, rw_c1x_tailor_cache, rw_c1x_elder (surface Chapter One additions), rw_c1x_tobin (Tobin's
##      annex), rw_ch2_candleyard_pattern, rw_hr_chime_trail (Reach west: Candleyard / Thimblebrook Pools),
##      rw_hw_lightwell_alcove (Works rooms 1-8: the Light Well keepsake trunk), rw_ch2_crossing,
##      rw_hw_throat_supplies (Works deep: Weaver's Crossing, Bell Throat), rw_trial_matron_first,
##      rw_trial_velour_first, rw_trial_choir_first (echo trial first clears; exact mirrors of data/trials.gd
##      FIRST_REWARDS, each setting only its trial's pattern-unlock flag).
##    Their flags are recipe unlock / world flags, or the module's own "already paid" marker (hr_chime_trail_done,
##    hw_throat_supplies) that nothing else reads.
##  * "legacy": how the Chapter One code grants its rewards today. Documentation for ITEM_SOURCES only: never pass
##    these to grant_once (the legacy code already gives them exactly as before).
## `patterns` are wardrobe ownership ids (data/appearance.gd PATTERNS) granted directly. `who` = the event.
const REWARDS := {
	"legacy_quest_mochi": {"items": {"sweetroot_seeds": 3}, "flags": [], "by": "legacy", "who": "legacy quest step 'mochi' (data/quests.gd)"},
	"legacy_quest_pebble": {"items": {"copper_ore": 2}, "flags": [], "by": "legacy", "who": "legacy quest step 'pebble' (data/quests.gd)"},
	"legacy_quest_return": {"items": {"haven_banner": 1}, "flags": ["chapter_one_complete"], "by": "legacy", "who": "legacy quest step 'return' (data/quests.gd)"},
	"legacy_weaver_matron": {"items": {"heartseed": 1}, "flags": ["weaver_defeated"], "by": "legacy", "who": "legacy boss: the Weaver Matron drops the Heartseed"},
	"rw_c1x_gardener": {"items": {"sunflax_seeds": 2, "roseberry_seeds": 2}, "flags": [], "by": "content", "who": "surface: 'A Gardener's Afternoon' starter packet (first harvest at the meadow patch)"},
	"rw_c1x_tailor_cache": {"items": {"sunflax_seeds": 2}, "flags": ["c1x_tailor_cache"], "by": "content", "who": "surface: the Tailor's Cache near the Old Oak"},
	"rw_c1x_elder": {"items": {"resin": 4}, "flags": ["c1x_elder_defeated"], "by": "content", "who": "surface: the Knotted Elder at Bramblewatch defeated"},
	"rw_c1x_tobin": {"items": {"miner_lamp": 1, "echo_shard": 2}, "flags": ["c1x_tobin_shift"], "by": "content", "who": "annex: Tobin's service note ('Tobin's Lost Shift')"},
	"rw_ch2_commons": {"items": {"pumpkin_seeds": 3, "sunflax_seeds": 2, "roseberry_seeds": 2}, "flags": [], "by": "chapter_log", "who": "ch2 step ch2_commons (Commons arrival arch lit)"},
	"rw_ch2_orchard": {"items": {"garden_seal": 1, "pumpkin_seeds": 3}, "flags": ["ch2_orchard_restored"], "by": "chapter_log", "who": "ch2 step ch2_orchard (garden lamp lit)"},
	"rw_ch2_quarry": {"items": {"quarry_seal": 1}, "flags": ["ch2_quarry_restored"], "by": "chapter_log", "who": "ch2 step ch2_quarry (Warden defeated, winch repaired, quarry lamp lit)"},
	"rw_ch2_manor": {"items": {"manor_seal": 1}, "flags": ["ch2_manor_restored"], "by": "chapter_log", "who": "ch2 step ch2_manor (Count Velour's enchantment broken)"},
	"rw_ch2_crossing": {"items": {}, "flags": ["ch2_crossing_cleared"], "by": "content", "who": "works: Weaver's Crossing cleared (the Thread Veil is the step reward rw_ch2_weaver_crossing)"},
	"rw_ch2_homecoming": {"items": {"wardlight": 1}, "flags": ["ch2_homecoming"], "by": "chapter_log", "who": "ch2 step ch2_homecoming (Haven Ward Stone)"},
	"rw_ch2_feast": {"items": {"candy": 6, "pumpkin": 4, "lantern_wax": 4, "sugarcap": 3, "moonpetal": 3}, "flags": ["ch2_feast"], "by": "chapter_log",
		"who": "ch2 step ch2_feast (The Lanternwake; Game.complete_chapter_two uses the same id and the same items: story_ch2.gd FEAST_EXTRAS)"},
	"rw_ch2_candleyard_pattern": {"items": {}, "flags": ["ch2_candleyard_pattern"], "by": "content", "who": "Candleyard: the hidden dress pattern"},
	"rw_hr_chime_trail": {"items": {"moonpetal": 3, "sugarcap": 2, "candy": 2}, "flags": ["hr_chime_trail_done"], "by": "content",
		"who": "Thimblebrook Pools: the lost festival pouch at the end of the chime trail"},
	"rw_hw_lightwell_alcove": {"items": {"bat_bunting": 2, "crescent_window": 1}, "flags": [], "patterns": [], "by": "content",
		"who": "works: the Light Well alcove keepsake trunk (room 8)"},
	"rw_hw_throat_supplies": {"items": {"hearty_stew": 2, "berry_snack": 2}, "flags": ["hw_throat_supplies"], "by": "content",
		"who": "works (deep): Bell Throat final supplies"},
	"rw_opt_pumpkin_face": {"items": {}, "flags": ["ch2_pumpkin_face"], "by": "optional_log", "who": "optional goal 'A Pumpkin With a Face'"},
	"rw_opt_counts_wardrobe": {"items": {}, "flags": ["ch2_count_wardrobe"], "by": "optional_log", "who": "optional goal 'The Count's Wardrobe'"},
	"rw_opt_hat_too_large": {"items": {}, "flags": [], "patterns": ["pat_witch_hat"], "by": "optional_log", "who": "optional goal 'A Hat Too Large'"},
	"rw_opt_groundskeeper": {"items": {"ghost_lantern": 1}, "flags": ["ch2_groundskeeper_candle"], "by": "optional_log", "who": "optional goal 'A Candle for the Groundskeeper'"},
	"rw_opt_harvest_table": {"items": {}, "flags": ["ch2_harvest_table"], "by": "optional_log", "who": "optional goal 'The Harvest Table'"},
	"rw_trial_matron_first": {"items": {}, "flags": ["ch2_trial_matron"], "by": "content", "who": "echo trial: first Matron clear (isolated trial reward state)"},
	"rw_trial_velour_first": {"items": {}, "flags": ["ch2_trial_velour"], "by": "content", "who": "echo trial: first Count Velour clear (isolated trial reward state)"},
	"rw_trial_choir_first": {"items": {}, "flags": ["ch2_trial_choir"], "by": "content", "who": "echo trial: first Borrowed Choir clear (isolated trial reward state)"},
}

## Items the Chapter Two story cannot be finished without (each has a guaranteed, non-drop source reachable
## before the gate that needs it). Waygate repair: wood / stone / copper ore (MP 11 step 2).
const STORY_REQUIRED := {
	"foreman_key": "legacy lower gate; ch2 service gate (kept in the pouch)",
	"lantern": "lantern anchors, braziers and true-light reveals (Chapter One and Two)",
	"garden_seal": "ch2_lamps_linked (Conservatory)",
	"quarry_seal": "ch2_lamps_linked (Conservatory)",
	"manor_seal": "ch2_lamps_linked (Conservatory)",
	"wood": "ch2 waygate repair (8)",
	"stone": "ch2 waygate repair (4)",
	"copper_ore": "ch2 waygate repair (2)",
}

## The Chapter One item ids (their sources are also proven by tests/unit/test_core_economy.gd's chapter rules).
const CHAPTER_ONE_ITEMS := ["wood", "stone", "fiber", "berries", "copper_ore", "sweetroot_seeds", "sweetroot", "shiny_pebble",
	"glowcap", "silk", "echo_shard", "stone_axe", "stone_pickaxe", "copper_sword", "lantern", "berry_snack", "hearty_stew",
	"glowcap_skewer", "workbench", "storage_chest", "bed", "crop_plot", "wood_floor", "wood_wall", "wood_window",
	"wood_doorway", "wood_roof", "fence", "lantern_post", "flower_pot", "rug", "table", "stool", "pebble_cairn",
	"echo_chime", "heartbloom_lamp", "haven_banner", "foreman_key", "heartseed"]

const ITEM_SOURCES := {
	# ============================ Chapter One items ============================
	"wood": [{"kind": "gather", "node": "tree", "guaranteed": true, "renewable": true}, {"kind": "gather", "node": "stick", "guaranteed": true, "renewable": true},
		{"kind": "drop", "enemy": "knotted_elder", "guaranteed": false, "renewable": false}],
	"stone": [{"kind": "gather", "node": "stone", "guaranteed": true, "renewable": true}, {"kind": "gather", "node": "rock", "guaranteed": true, "renewable": true},
		{"kind": "gather", "node": "ore", "guaranteed": true, "renewable": true}, {"kind": "gather", "node": "iron_vein", "guaranteed": true, "renewable": true},
		{"kind": "drop", "enemy": "hollow_drudge", "guaranteed": false, "renewable": true}, {"kind": "drop", "enemy": "quarry_warden", "guaranteed": false, "renewable": false}],
	"fiber": [{"kind": "gather", "node": "grass", "guaranteed": true, "renewable": true},
		{"kind": "companion", "companion": "mochi", "desc": "Mochi forages fiber while following", "guaranteed": false, "renewable": true},
		{"kind": "drop", "enemy": "brambling", "guaranteed": false, "renewable": true}, {"kind": "drop", "enemy": "brambleback", "guaranteed": false, "renewable": true},
		{"kind": "drop", "enemy": "lantern_moth", "guaranteed": false, "renewable": true}, {"kind": "drop", "enemy": "patchwalker", "guaranteed": false, "renewable": true}],
	"berries": [{"kind": "gather", "node": "bush", "guaranteed": true, "renewable": true},
		{"kind": "companion", "companion": "mochi", "desc": "Mochi forages berries while following", "guaranteed": false, "renewable": true},
		{"kind": "drop", "enemy": "brambling", "guaranteed": false, "renewable": true}],
	"copper_ore": [{"kind": "gather", "node": "ore", "guaranteed": true, "renewable": true}, {"kind": "reward", "reward": "legacy_quest_pebble", "guaranteed": true, "renewable": false},
		{"kind": "drop", "enemy": "hollow_drudge", "guaranteed": false, "renewable": true}],
	"sweetroot_seeds": [{"kind": "reward", "reward": "legacy_quest_mochi", "guaranteed": true, "renewable": false}, {"kind": "gather", "node": "bush", "guaranteed": false, "renewable": true},
		{"kind": "crop", "crop": "sweetroot", "guaranteed": true, "renewable": true}],
	"sweetroot": [{"kind": "crop", "crop": "sweetroot", "guaranteed": true, "renewable": true}],
	"shiny_pebble": [{"kind": "companion", "companion": "pebble", "desc": "Pebble brings shiny pebbles once befriended", "guaranteed": true, "renewable": true}],
	"glowcap": [{"kind": "gather", "node": "glowcap", "guaranteed": true, "renewable": true}, {"kind": "drop", "enemy": "gloomling", "guaranteed": false, "renewable": true}],
	"silk": [{"kind": "gather", "node": "silk", "guaranteed": true, "renewable": true}, {"kind": "drop", "enemy": "brood_skitter", "guaranteed": false, "renewable": true}],
	"echo_shard": [{"kind": "gather", "node": "crystal", "guaranteed": true, "renewable": true}, {"kind": "reward", "reward": "rw_c1x_tobin", "guaranteed": true, "renewable": false},
		{"kind": "drop", "enemy": "gloomling", "guaranteed": false, "renewable": true}, {"kind": "drop", "enemy": "hollow_drudge", "guaranteed": false, "renewable": true},
		{"kind": "drop", "enemy": "borrowed_wisp", "guaranteed": false, "renewable": true}],
	"stone_axe": [{"kind": "recipe", "recipe": "stone_axe"}],
	"stone_pickaxe": [{"kind": "recipe", "recipe": "stone_pickaxe"}],
	"copper_sword": [{"kind": "recipe", "recipe": "copper_sword"}],
	"lantern": [{"kind": "recipe", "recipe": "lantern"}],
	"berry_snack": [{"kind": "recipe", "recipe": "berry_snack"}, {"kind": "reward", "reward": "rw_hw_throat_supplies", "guaranteed": true, "renewable": false}],
	"hearty_stew": [{"kind": "recipe", "recipe": "hearty_stew"}, {"kind": "reward", "reward": "rw_hw_throat_supplies", "guaranteed": true, "renewable": false}],
	"glowcap_skewer": [{"kind": "recipe", "recipe": "glowcap_skewer"}],
	"workbench": [{"kind": "recipe", "recipe": "workbench"}],
	"storage_chest": [{"kind": "recipe", "recipe": "storage_chest"}],
	"bed": [{"kind": "recipe", "recipe": "bed"}],
	"crop_plot": [{"kind": "recipe", "recipe": "crop_plot"}],
	"wood_floor": [{"kind": "recipe", "recipe": "wood_floor"}],
	"wood_wall": [{"kind": "recipe", "recipe": "wood_wall"}],
	"wood_window": [{"kind": "recipe", "recipe": "wood_window"}],
	"wood_doorway": [{"kind": "recipe", "recipe": "wood_doorway"}],
	"wood_roof": [{"kind": "recipe", "recipe": "wood_roof"}],
	"fence": [{"kind": "recipe", "recipe": "fence"}],
	"lantern_post": [{"kind": "recipe", "recipe": "lantern_post"}],
	"flower_pot": [{"kind": "recipe", "recipe": "flower_pot"}],
	"rug": [{"kind": "recipe", "recipe": "rug"}],
	"table": [{"kind": "recipe", "recipe": "table"}],
	"stool": [{"kind": "recipe", "recipe": "stool"}],
	"pebble_cairn": [{"kind": "recipe", "recipe": "pebble_cairn"}],
	"echo_chime": [{"kind": "recipe", "recipe": "echo_chime"}],
	"heartbloom_lamp": [{"kind": "recipe", "recipe": "heartbloom_lamp"}],
	"haven_banner": [{"kind": "reward", "reward": "legacy_quest_return", "guaranteed": true, "renewable": false}],
	"foreman_key": [{"kind": "pickup", "where": {"below": ["mine"]}, "desc": "The Foreman's Office in the Old Mine (legacy, guaranteed)", "guaranteed": true, "renewable": false}],
	"heartseed": [{"kind": "reward", "reward": "legacy_weaver_matron", "guaranteed": true, "renewable": false}],
	# ============================ Chapter Two resources ============================
	"sunflax": [{"kind": "gather", "node": "sunflax_patch", "guaranteed": true, "renewable": true}, {"kind": "crop", "crop": "sunflax", "guaranteed": true, "renewable": true},
		{"kind": "drop", "enemy": "patchwalker", "guaranteed": false, "renewable": true}],
	"roseberries": [{"kind": "gather", "node": "roseberry_bush", "guaranteed": true, "renewable": true}, {"kind": "crop", "crop": "roseberry", "guaranteed": true, "renewable": true},
		{"kind": "drop", "enemy": "velvet_wing", "guaranteed": false, "renewable": true}],
	"resin": [{"kind": "gather", "node": "sap_stump", "guaranteed": true, "renewable": true}, {"kind": "reward", "reward": "rw_c1x_elder", "guaranteed": true, "renewable": false},
		{"kind": "drop", "enemy": "brambleback", "guaranteed": false, "renewable": true}, {"kind": "drop", "enemy": "knotted_elder", "guaranteed": false, "renewable": false}],
	"iron_ore": [{"kind": "gather", "node": "iron_vein", "guaranteed": true, "renewable": true}, {"kind": "drop", "enemy": "bellcap_sentry", "guaranteed": false, "renewable": true},
		{"kind": "drop", "enemy": "quarry_warden", "guaranteed": false, "renewable": false}],
	"woven_cloth": [{"kind": "recipe", "recipe": "woven_cloth"}, {"kind": "drop", "enemy": "velvet_wing", "guaranteed": false, "renewable": true},
		{"kind": "reward", "reward": "rw_opt_tailors_cache", "guaranteed": true, "renewable": false}],
	"copper_bar": [{"kind": "station", "station": "furnace", "recipe": "copper_bar"}, {"kind": "reward", "reward": "rw_opt_copper_courage", "guaranteed": true, "renewable": false}],
	"iron_bar": [{"kind": "station", "station": "furnace", "recipe": "iron_bar"}],
	"moon_crystal": [{"kind": "gather", "node": "moon_crystal_vein", "guaranteed": true, "renewable": true}],
	"moonsteel_bar": [{"kind": "station", "station": "furnace", "recipe": "moonsteel_bar"}],
	"pumpkin": [{"kind": "gather", "node": "pumpkin_vine", "guaranteed": true, "renewable": true}, {"kind": "crop", "crop": "pumpkin", "guaranteed": true, "renewable": true},
		{"kind": "drop", "enemy": "pumpkin_mimic", "guaranteed": false, "renewable": true}, {"kind": "reward", "reward": "rw_ch2_feast", "guaranteed": true, "renewable": false}],
	"sugarcap": [{"kind": "gather", "node": "sugarcap_patch", "guaranteed": true, "renewable": true}, {"kind": "drop", "enemy": "bellcap_sentry", "guaranteed": false, "renewable": true},
		{"kind": "reward", "reward": "rw_hr_chime_trail", "guaranteed": true, "renewable": false}, {"kind": "reward", "reward": "rw_ch2_feast", "guaranteed": true, "renewable": false}],
	"moonpetal": [{"kind": "gather", "node": "moonpetal_patch", "guaranteed": true, "renewable": true},
		{"kind": "reward", "reward": "rw_hr_chime_trail", "guaranteed": true, "renewable": false}, {"kind": "reward", "reward": "rw_ch2_feast", "guaranteed": true, "renewable": false}],
	"lantern_wax": [{"kind": "recipe", "recipe": "lantern_wax"}, {"kind": "drop", "enemy": "lantern_moth", "guaranteed": false, "renewable": true},
		{"kind": "drop", "enemy": "borrowed_wisp", "guaranteed": false, "renewable": true}, {"kind": "reward", "reward": "rw_ch2_feast", "guaranteed": true, "renewable": false}],
	"candy": [{"kind": "recipe", "recipe": "candy"}, {"kind": "reward", "reward": "rw_ch2_feast", "guaranteed": true, "renewable": false},
		{"kind": "reward", "reward": "rw_hr_chime_trail", "guaranteed": true, "renewable": false}],
	"sunflax_seeds": [{"kind": "gather", "node": "sunflax_patch", "guaranteed": false, "renewable": true}, {"kind": "crop", "crop": "sunflax", "guaranteed": true, "renewable": true},
		{"kind": "reward", "reward": "rw_c1x_gardener", "guaranteed": true, "renewable": false}, {"kind": "reward", "reward": "rw_c1x_tailor_cache", "guaranteed": true, "renewable": false},
		{"kind": "reward", "reward": "rw_ch2_commons", "guaranteed": true, "renewable": false}, {"kind": "reward", "reward": "rw_opt_gardeners_afternoon", "guaranteed": true, "renewable": false}],
	"roseberry_seeds": [{"kind": "gather", "node": "roseberry_bush", "guaranteed": false, "renewable": true}, {"kind": "crop", "crop": "roseberry", "guaranteed": true, "renewable": true},
		{"kind": "reward", "reward": "rw_c1x_gardener", "guaranteed": true, "renewable": false}, {"kind": "reward", "reward": "rw_ch2_commons", "guaranteed": true, "renewable": false},
		{"kind": "reward", "reward": "rw_opt_gardeners_afternoon", "guaranteed": true, "renewable": false}],
	"pumpkin_seeds": [{"kind": "gather", "node": "pumpkin_vine", "guaranteed": true, "renewable": true}, {"kind": "crop", "crop": "pumpkin", "guaranteed": true, "renewable": true},
		{"kind": "reward", "reward": "rw_ch2_commons", "guaranteed": true, "renewable": false}, {"kind": "reward", "reward": "rw_ch2_orchard", "guaranteed": true, "renewable": false},
		{"kind": "drop", "enemy": "pumpkin_mimic", "guaranteed": false, "renewable": true}],
	# ============================ Chapter Two equipment ============================
	"copper_axe": [{"kind": "recipe", "recipe": "copper_axe"}],
	"copper_pickaxe": [{"kind": "recipe", "recipe": "copper_pickaxe"}],
	"ironwood_axe": [{"kind": "recipe", "recipe": "ironwood_axe"}],
	"ironwood_pickaxe": [{"kind": "recipe", "recipe": "ironwood_pickaxe"}],
	"moonsteel_axe": [{"kind": "recipe", "recipe": "moonsteel_axe"}],
	"moonsteel_pickaxe": [{"kind": "recipe", "recipe": "moonsteel_pickaxe"}],
	"ironwood_sword": [{"kind": "recipe", "recipe": "ironwood_sword"}],
	"moonsteel_sword": [{"kind": "recipe", "recipe": "moonsteel_sword"}],
	"sparkseed_wand": [{"kind": "recipe", "recipe": "sparkseed_wand"}],
	"padded_hood": [{"kind": "recipe", "recipe": "padded_hood"}],
	"padded_vest": [{"kind": "recipe", "recipe": "padded_vest"}],
	"padded_boots": [{"kind": "recipe", "recipe": "padded_boots"}],
	"copperwood_hood": [{"kind": "recipe", "recipe": "copperwood_hood"}],
	"copperwood_vest": [{"kind": "recipe", "recipe": "copperwood_vest"}],
	"copperwood_boots": [{"kind": "recipe", "recipe": "copperwood_boots"}],
	"ironwood_helm": [{"kind": "recipe", "recipe": "ironwood_helm"}],
	"ironwood_mail": [{"kind": "recipe", "recipe": "ironwood_mail"}],
	"ironwood_boots": [{"kind": "recipe", "recipe": "ironwood_boots"}],
	"moonsteel_helm": [{"kind": "recipe", "recipe": "moonsteel_helm"}],
	"moonsteel_mail": [{"kind": "recipe", "recipe": "moonsteel_mail"}],
	"moonsteel_boots": [{"kind": "recipe", "recipe": "moonsteel_boots"}],
	"gatherers_charm": [{"kind": "recipe", "recipe": "gatherers_charm"}],
	"swiftstep_charm": [{"kind": "recipe", "recipe": "swiftstep_charm"}],
	"kindling_charm": [{"kind": "recipe", "recipe": "kindling_charm"}],
	# ============================ Chapter Two food & companion gear ============================
	"pumpkin_soup": [{"kind": "recipe", "recipe": "pumpkin_soup"}],
	"pumpkin_biscuit": [{"kind": "recipe", "recipe": "pumpkin_biscuit"}],
	"roseberry_tart": [{"kind": "recipe", "recipe": "roseberry_tart"}],
	"moonpetal_tea": [{"kind": "recipe", "recipe": "moonpetal_tea"}],
	"lanternwake_platter": [{"kind": "recipe", "recipe": "lanternwake_platter"}],
	"comfort_ribbon": [{"kind": "recipe", "recipe": "comfort_ribbon"}],
	# ============================ Chapter Two key items ============================
	"garden_seal": [{"kind": "reward", "reward": "rw_ch2_orchard", "guaranteed": true, "renewable": false}],
	"quarry_seal": [{"kind": "reward", "reward": "rw_ch2_quarry", "guaranteed": true, "renewable": false}],
	"manor_seal": [{"kind": "reward", "reward": "rw_ch2_manor", "guaranteed": true, "renewable": false}],
	"velvet_scrap": [{"kind": "pickup", "where": {"moonveil_manor": ["mm_hall", "mm_ballroom", "mm_gallery"]}, "desc": "Three fixed scraps in the manor's optional side rooms, each with a visual clue (The Count's Wardrobe)", "guaranteed": true, "renewable": false}],
	# ============================ Chapter Two placeables ============================
	"wood_stairs": [{"kind": "recipe", "recipe": "wood_stairs"}],
	"upper_floor": [{"kind": "recipe", "recipe": "upper_floor"}],
	"wood_railing": [{"kind": "recipe", "recipe": "wood_railing"}, {"kind": "reward", "reward": "rw_opt_upstairs", "guaranteed": true, "renewable": false}],
	"half_wall": [{"kind": "recipe", "recipe": "half_wall"}],
	"porch_post": [{"kind": "recipe", "recipe": "porch_post"}],
	"arched_window": [{"kind": "recipe", "recipe": "arched_window"}],
	"gable_roof": [{"kind": "recipe", "recipe": "gable_roof"}],
	"roof_corner": [{"kind": "recipe", "recipe": "roof_corner"}],
	"flower_box": [{"kind": "recipe", "recipe": "flower_box"}],
	"curtain": [{"kind": "recipe", "recipe": "curtain"}],
	"bookshelf": [{"kind": "recipe", "recipe": "bookshelf"}],
	"wardrobe": [{"kind": "recipe", "recipe": "wardrobe"}],
	"vanity_mirror": [{"kind": "recipe", "recipe": "vanity_mirror"}],
	"kitchen_counter": [{"kind": "recipe", "recipe": "kitchen_counter"}],
	"furnace": [{"kind": "recipe", "recipe": "furnace"}],
	"loom": [{"kind": "recipe", "recipe": "loom"}],
	"companion_bed": [{"kind": "recipe", "recipe": "companion_bed"}],
	"companion_perch": [{"kind": "recipe", "recipe": "companion_perch"}],
	"sturdy_planter": [{"kind": "recipe", "recipe": "sturdy_planter"}, {"kind": "reward", "reward": "rw_opt_bramblewatch", "guaranteed": true, "renewable": false}],
	"cottage_bench": [{"kind": "recipe", "recipe": "cottage_bench"}],
	"pumpkin_lantern": [{"kind": "recipe", "recipe": "pumpkin_lantern"}],
	"pumpkin_lights": [{"kind": "recipe", "recipe": "pumpkin_lights"}],
	"bat_bunting": [{"kind": "recipe", "recipe": "bat_bunting"}, {"kind": "reward", "reward": "rw_hw_lightwell_alcove", "guaranteed": true, "renewable": false}],
	"ghost_lantern": [{"kind": "recipe", "recipe": "ghost_lantern"}, {"kind": "reward", "reward": "rw_opt_groundskeeper", "guaranteed": true, "renewable": false}],
	"crescent_window": [{"kind": "recipe", "recipe": "crescent_window"}, {"kind": "reward", "reward": "rw_hw_lightwell_alcove", "guaranteed": true, "renewable": false}],
	"candy_bowl": [{"kind": "recipe", "recipe": "candy_bowl"}],
	"scarecrow": [{"kind": "recipe", "recipe": "scarecrow"}],
	"gothic_trim": [{"kind": "recipe", "recipe": "gothic_trim"}],
	"music_box": [{"kind": "recipe", "recipe": "music_box"}],
	"expedition_board": [{"kind": "recipe", "recipe": "expedition_board"}],
	"wardlight": [{"kind": "recipe", "recipe": "wardlight"}, {"kind": "reward", "reward": "rw_ch2_homecoming", "guaranteed": true, "renewable": false}],
	"miner_lamp": [{"kind": "recipe", "recipe": "miner_lamp"}, {"kind": "reward", "reward": "rw_c1x_tobin", "guaranteed": true, "renewable": false},
		{"kind": "reward", "reward": "rw_opt_miner_came_back", "guaranteed": true, "renewable": false}],
	"thread_veil": [{"kind": "recipe", "recipe": "thread_veil"}, {"kind": "reward", "reward": "rw_ch2_weaver_crossing", "guaranteed": true, "renewable": false}],
	"lanternwake_table": [{"kind": "recipe", "recipe": "lanternwake_table"}],
}
