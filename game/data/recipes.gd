extends RefCounted
## Recipe definitions. Keys are stable recipe ids.
## station: "hand" (anywhere) | "workbench" (near a placed workbench) | "campfire" (near the Haven campfire)
## unlock: "" = known from the start; otherwise a GameState flag that must be true to show/craft.
## A recipe consumes every ingredient exactly once and produces `count` of `result` exactly once.
## Chapter Two (docs/CHAPTER_TWO_SPEC.md 4.3; entries are appended, legacy recipes never change):
##   stations  furnace | loom | kitchen (placed structures with that `station`), plus hand / workbench / campfire
##   time      furnace only: seconds per queued job (short, 15-45 s). Such recipes are QUEUED at the furnace,
##             never crafted instantly (the crafting module must refuse them outside the furnace queue).
##   mastery   optional {"hearthcraft": rank}: rank gate on a purely decorative recipe (never story-critical)
##   Every unlock flag used here is declared in data/unlocks.gd UNLOCK_FLAGS with the system that sets it.
## SPECIAL_RECIPES (below) produce no item: `apply` (backpack_40 / backpack_48 / chest_40 upgrades) or
## `pattern` (wardrobe ownership id, see data/appearance.gd PATTERNS). They are kept out of RECIPES so every
## RECIPES entry keeps the legacy contract "has a real item result"; ItemDB.recipe(id) finds both tables.

const RECIPES := {
	# --- By hand -----------------------------------------------------------------
	"stone_axe": {"result": "stone_axe", "count": 1, "station": "hand", "ingredients": {"wood": 3, "stone": 2, "fiber": 2}, "unlock": ""},
	"stone_pickaxe": {"result": "stone_pickaxe", "count": 1, "station": "hand", "ingredients": {"wood": 3, "stone": 3, "fiber": 2}, "unlock": ""},
	"workbench": {"result": "workbench", "count": 1, "station": "hand", "ingredients": {"wood": 8, "stone": 2}, "unlock": ""},
	"berry_snack": {"result": "berry_snack", "count": 1, "station": "hand", "ingredients": {"berries": 4}, "unlock": ""},
	"crop_plot": {"result": "crop_plot", "count": 1, "station": "hand", "ingredients": {"wood": 3, "fiber": 3}, "unlock": ""},
	# --- Workbench -----------------------------------------------------------------
	"copper_sword": {"result": "copper_sword", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "copper_ore": 4, "fiber": 2}, "unlock": ""},
	"lantern": {"result": "lantern", "count": 1, "station": "workbench", "ingredients": {"copper_ore": 3, "fiber": 2, "wood": 2}, "unlock": ""},
	"storage_chest": {"result": "storage_chest", "count": 1, "station": "workbench", "ingredients": {"wood": 10, "copper_ore": 1}, "unlock": ""},
	"bed": {"result": "bed", "count": 1, "station": "workbench", "ingredients": {"wood": 8, "fiber": 6}, "unlock": ""},
	"wood_floor": {"result": "wood_floor", "count": 1, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"wood_wall": {"result": "wood_wall", "count": 1, "station": "workbench", "ingredients": {"wood": 3}, "unlock": ""},
	"wood_window": {"result": "wood_window", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "fiber": 1}, "unlock": ""},
	"wood_doorway": {"result": "wood_doorway", "count": 1, "station": "workbench", "ingredients": {"wood": 3}, "unlock": ""},
	"wood_roof": {"result": "wood_roof", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "fiber": 2}, "unlock": ""},
	"fence": {"result": "fence", "count": 2, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"lantern_post": {"result": "lantern_post", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "copper_ore": 1, "fiber": 1}, "unlock": ""},
	"flower_pot": {"result": "flower_pot", "count": 1, "station": "workbench", "ingredients": {"stone": 3, "fiber": 1}, "unlock": ""},
	"rug": {"result": "rug", "count": 1, "station": "workbench", "ingredients": {"fiber": 6, "berries": 2}, "unlock": ""},
	"table": {"result": "table", "count": 1, "station": "workbench", "ingredients": {"wood": 5}, "unlock": ""},
	"stool": {"result": "stool", "count": 1, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"pebble_cairn": {"result": "pebble_cairn", "count": 1, "station": "workbench", "ingredients": {"shiny_pebble": 3, "stone": 2}, "unlock": ""},
	"echo_chime": {"result": "echo_chime", "count": 1, "station": "workbench", "ingredients": {"echo_shard": 3, "wood": 1, "fiber": 1}, "unlock": ""},
	"heartbloom_lamp": {"result": "heartbloom_lamp", "count": 1, "station": "workbench", "ingredients": {"glowcap": 2, "silk": 2, "wood": 2}, "unlock": "ward_restored"},
	# --- Campfire (cooking) --------------------------------------------------------------
	"hearty_stew": {"result": "hearty_stew", "count": 1, "station": "campfire", "ingredients": {"sweetroot": 2, "berries": 3}, "unlock": ""},
	"glowcap_skewer": {"result": "glowcap_skewer", "count": 1, "station": "campfire", "ingredients": {"glowcap": 2, "wood": 1}, "unlock": ""},
	# ======================== Chapter Two (append only) ========================
	# --- Workshop stations & processing (MP 16) ------------------------------------------------------
	"furnace": {"result": "furnace", "count": 1, "station": "workbench", "ingredients": {"stone": 10, "wood": 4, "copper_ore": 2}, "unlock": ""},
	"loom": {"result": "loom", "count": 1, "station": "workbench", "ingredients": {"wood": 8, "fiber": 6}, "unlock": "c1x_tailor_cache"},
	"vanity_mirror": {"result": "vanity_mirror", "count": 1, "station": "workbench", "ingredients": {"wood": 4, "copper_ore": 2, "stone": 2}, "unlock": ""},
	"kitchen_counter": {"result": "kitchen_counter", "count": 1, "station": "workbench", "ingredients": {"stone": 8, "wood": 6, "copper_bar": 2}, "unlock": ""},
	"lantern_wax": {"result": "lantern_wax", "count": 2, "station": "workbench", "ingredients": {"resin": 1, "fiber": 1}, "unlock": ""},
	"woven_cloth": {"result": "woven_cloth", "count": 2, "station": "loom", "ingredients": {"sunflax": 3, "fiber": 2}, "unlock": ""},
	"copper_bar": {"result": "copper_bar", "count": 1, "station": "furnace", "ingredients": {"copper_ore": 2}, "unlock": "", "time": 20.0},
	"iron_bar": {"result": "iron_bar", "count": 1, "station": "furnace", "ingredients": {"iron_ore": 2}, "unlock": "", "time": 30.0},
	"moonsteel_bar": {"result": "moonsteel_bar", "count": 1, "station": "furnace", "ingredients": {"iron_bar": 2, "moon_crystal": 1, "echo_shard": 1}, "unlock": "ch2_winch_repaired", "time": 45.0},
	"comfort_ribbon": {"result": "comfort_ribbon", "count": 1, "station": "loom", "ingredients": {"woven_cloth": 2, "berries": 2}, "unlock": ""},
	# --- Tools & weapons (MP 16) -----------------------------------------------------------------------
	"copper_axe": {"result": "copper_axe", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "copper_bar": 3, "fiber": 2}, "unlock": ""},
	"copper_pickaxe": {"result": "copper_pickaxe", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "copper_bar": 3, "fiber": 2}, "unlock": ""},
	"ironwood_sword": {"result": "ironwood_sword", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 3, "wood": 2, "woven_cloth": 1}, "unlock": "ch2_quarry_restored"},
	"ironwood_axe": {"result": "ironwood_axe", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 3, "wood": 3, "resin": 1}, "unlock": "ch2_quarry_restored"},
	"ironwood_pickaxe": {"result": "ironwood_pickaxe", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 3, "wood": 3, "resin": 1}, "unlock": "ch2_quarry_restored"},
	"moonsteel_sword": {"result": "moonsteel_sword", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 4, "wood": 2, "echo_shard": 1}, "unlock": "ch2_winch_repaired"},
	"moonsteel_axe": {"result": "moonsteel_axe", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 3, "wood": 3, "resin": 1}, "unlock": "ch2_winch_repaired"},
	"moonsteel_pickaxe": {"result": "moonsteel_pickaxe", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 3, "wood": 3, "resin": 1}, "unlock": "ch2_winch_repaired"},
	"sparkseed_wand": {"result": "sparkseed_wand", "count": 1, "station": "workbench", "ingredients": {"wood": 4, "copper_bar": 2, "glowcap": 2}, "unlock": ""},
	# --- Armor (MP 16: padded at the loom, metal sets at the workbench) -----------------------------------
	"padded_hood": {"result": "padded_hood", "count": 1, "station": "loom", "ingredients": {"woven_cloth": 1, "fiber": 3}, "unlock": ""},
	"padded_vest": {"result": "padded_vest", "count": 1, "station": "loom", "ingredients": {"woven_cloth": 2, "fiber": 4}, "unlock": ""},
	"padded_boots": {"result": "padded_boots", "count": 1, "station": "loom", "ingredients": {"woven_cloth": 1, "fiber": 2}, "unlock": ""},
	"copperwood_hood": {"result": "copperwood_hood", "count": 1, "station": "workbench", "ingredients": {"woven_cloth": 2, "copper_bar": 1}, "unlock": ""},
	"copperwood_vest": {"result": "copperwood_vest", "count": 1, "station": "workbench", "ingredients": {"woven_cloth": 3, "copper_bar": 2}, "unlock": ""},
	"copperwood_boots": {"result": "copperwood_boots", "count": 1, "station": "workbench", "ingredients": {"woven_cloth": 2, "copper_bar": 1}, "unlock": ""},
	"ironwood_helm": {"result": "ironwood_helm", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 2, "woven_cloth": 2}, "unlock": "ch2_quarry_restored"},
	"ironwood_mail": {"result": "ironwood_mail", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 4, "woven_cloth": 3}, "unlock": "ch2_quarry_restored"},
	"ironwood_boots": {"result": "ironwood_boots", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 2, "woven_cloth": 2}, "unlock": "ch2_quarry_restored"},
	"moonsteel_helm": {"result": "moonsteel_helm", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 2, "woven_cloth": 2}, "unlock": "ch2_winch_repaired"},
	"moonsteel_mail": {"result": "moonsteel_mail", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 4, "woven_cloth": 3}, "unlock": "ch2_winch_repaired"},
	"moonsteel_boots": {"result": "moonsteel_boots", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 2, "woven_cloth": 2}, "unlock": "ch2_winch_repaired"},
	# --- Charms (MP 16) -----------------------------------------------------------------------------------
	"gatherers_charm": {"result": "gatherers_charm", "count": 1, "station": "workbench", "ingredients": {"resin": 2, "copper_bar": 2, "fiber": 2}, "unlock": ""},
	"swiftstep_charm": {"result": "swiftstep_charm", "count": 1, "station": "workbench", "ingredients": {"iron_bar": 2, "moonpetal": 2, "woven_cloth": 1}, "unlock": ""},
	"kindling_charm": {"result": "kindling_charm", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 1, "glowcap": 2, "woven_cloth": 2}, "unlock": ""},
	# --- Food (MP 16; the campfire keeps all its old recipes) -------------------------------------------------
	"pumpkin_soup": {"result": "pumpkin_soup", "count": 1, "station": "campfire", "ingredients": {"pumpkin": 1, "sweetroot": 1}, "unlock": "ch2_orchard_restored"},
	"pumpkin_biscuit": {"result": "pumpkin_biscuit", "count": 2, "station": "kitchen", "ingredients": {"pumpkin": 1, "sugarcap": 1}, "unlock": "ch2_orchard_restored"},
	"roseberry_tart": {"result": "roseberry_tart", "count": 1, "station": "kitchen", "ingredients": {"roseberries": 2, "sugarcap": 1}, "unlock": ""},
	"moonpetal_tea": {"result": "moonpetal_tea", "count": 1, "station": "campfire", "ingredients": {"moonpetal": 2, "sweetroot": 1}, "unlock": ""},
	"lanternwake_platter": {"result": "lanternwake_platter", "count": 1, "station": "kitchen", "ingredients": {"pumpkin": 1, "roseberries": 2, "sweetroot": 1}, "unlock": ""},
	"candy": {"result": "candy", "count": 3, "station": "kitchen", "ingredients": {"sugarcap": 2, "roseberries": 1}, "unlock": "ch2_harvest_table"},
	# --- Structural pieces (costs proportional to the legacy wood pieces; starter essentials known early) -----
	"wood_stairs": {"result": "wood_stairs", "count": 1, "station": "workbench", "ingredients": {"wood": 8}, "unlock": ""},
	"upper_floor": {"result": "upper_floor", "count": 1, "station": "workbench", "ingredients": {"wood": 3}, "unlock": ""},
	"wood_railing": {"result": "wood_railing", "count": 2, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"half_wall": {"result": "half_wall", "count": 1, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"porch_post": {"result": "porch_post", "count": 1, "station": "workbench", "ingredients": {"wood": 2}, "unlock": ""},
	"arched_window": {"result": "arched_window", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "fiber": 1}, "unlock": ""},
	"gable_roof": {"result": "gable_roof", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "fiber": 2}, "unlock": ""},
	"roof_corner": {"result": "roof_corner", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "fiber": 2}, "unlock": ""},
	# --- Furniture (wood / fiber; cloth furnishings at the loom) ---------------------------------------------
	"flower_box": {"result": "flower_box", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "fiber": 2}, "unlock": ""},
	"curtain": {"result": "curtain", "count": 1, "station": "loom", "ingredients": {"woven_cloth": 2, "wood": 1}, "unlock": ""},
	"bookshelf": {"result": "bookshelf", "count": 1, "station": "workbench", "ingredients": {"wood": 6}, "unlock": ""},
	"wardrobe": {"result": "wardrobe", "count": 1, "station": "workbench", "ingredients": {"wood": 8, "fiber": 2}, "unlock": ""},
	"companion_bed": {"result": "companion_bed", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "fiber": 4}, "unlock": ""},
	"companion_perch": {"result": "companion_perch", "count": 1, "station": "workbench", "ingredients": {"wood": 4, "fiber": 2}, "unlock": ""},
	"sturdy_planter": {"result": "sturdy_planter", "count": 1, "station": "workbench", "ingredients": {"wood": 5, "stone": 2, "resin": 1}, "unlock": "c1x_elder_defeated"},
	"cottage_bench": {"result": "cottage_bench", "count": 1, "station": "workbench", "ingredients": {"wood": 4}, "unlock": ""},
	"music_box": {"result": "music_box", "count": 1, "station": "workbench", "ingredients": {"wood": 6, "copper_bar": 2, "echo_shard": 1}, "unlock": ""},
	"expedition_board": {"result": "expedition_board", "count": 1, "station": "workbench", "ingredients": {"wood": 6, "woven_cloth": 1, "copper_bar": 1}, "unlock": "ch2_choir_defeated"},
	"miner_lamp": {"result": "miner_lamp", "count": 1, "station": "workbench", "ingredients": {"copper_bar": 1, "lantern_wax": 1, "wood": 2}, "unlock": "c1x_tobin_shift"},
	"wardlight": {"result": "wardlight", "count": 1, "station": "workbench", "ingredients": {"moonsteel_bar": 1, "moon_crystal": 2, "wood": 2}, "unlock": "ch2_homecoming"},
	"thread_veil": {"result": "thread_veil", "count": 1, "station": "loom", "ingredients": {"silk": 3, "woven_cloth": 2}, "unlock": "ch2_crossing_cleared"},
	"lanternwake_table": {"result": "lanternwake_table", "count": 1, "station": "workbench", "ingredients": {"wood": 6, "woven_cloth": 2, "lantern_wax": 2}, "unlock": "ch2_harvest_table"},
	# --- Halloween decor (lights: pumpkins / wax / wood; ornate pieces: a little iron) -------------------------
	"pumpkin_lantern": {"result": "pumpkin_lantern", "count": 1, "station": "workbench", "ingredients": {"pumpkin": 1, "lantern_wax": 1}, "unlock": "ch2_orchard_restored"},
	"pumpkin_lights": {"result": "pumpkin_lights", "count": 2, "station": "workbench", "ingredients": {"pumpkin": 1, "lantern_wax": 1, "wood": 1, "fiber": 1}, "unlock": "ch2_orchard_restored"},
	"scarecrow": {"result": "scarecrow", "count": 1, "station": "workbench", "ingredients": {"wood": 4, "fiber": 4, "pumpkin": 1}, "unlock": "ch2_orchard_restored"},
	"bat_bunting": {"result": "bat_bunting", "count": 2, "station": "loom", "ingredients": {"woven_cloth": 2, "fiber": 2}, "unlock": ""},
	"ghost_lantern": {"result": "ghost_lantern", "count": 1, "station": "workbench", "ingredients": {"lantern_wax": 2, "woven_cloth": 1, "wood": 1}, "unlock": "ch2_groundskeeper_candle"},
	"candy_bowl": {"result": "candy_bowl", "count": 1, "station": "workbench", "ingredients": {"wood": 2, "candy": 3}, "unlock": ""},
	"crescent_window": {"result": "crescent_window", "count": 1, "station": "workbench", "ingredients": {"wood": 3, "iron_bar": 1}, "unlock": "", "mastery": {"hearthcraft": 1}},
	"gothic_trim": {"result": "gothic_trim", "count": 2, "station": "workbench", "ingredients": {"wood": 2, "iron_bar": 1}, "unlock": "", "mastery": {"hearthcraft": 2}},
}

## Recipes that grant something other than an item (see the header). Ids never collide with RECIPES ids.
##   apply    "backpack_40" (32 -> 40 slots), "backpack_48" (40 -> 48, needs backpack_40 first: `requires_capacity`),
##            "chest_40" (upgrade ONE chosen chest 20 -> 40 in place, from the storage panel; station "hand")
##   pattern  wardrobe ownership id granted once (data/appearance.gd PATTERNS); crafting it again is refused
##            by the wardrobe module (already owned), so cloth is never consumed twice.
const SPECIAL_RECIPES := {
	"backpack_40": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 4, "copper_bar": 2}, "unlock": "", "apply": "backpack_40", "requires_capacity": 32},
	"backpack_48": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 6, "iron_bar": 2}, "unlock": "", "apply": "backpack_48", "requires_capacity": 40},
	"chest_upgrade_40": {"result": "", "count": 0, "station": "hand", "ingredients": {"wood": 6, "iron_bar": 2}, "unlock": "", "apply": "chest_40"},
	"pattern_ribbon_bow": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 1, "berries": 2}, "unlock": "c1x_tailor_cache", "pattern": "pat_ribbon_bow"},
	"pattern_leaf_cape": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 2, "resin": 1}, "unlock": "c1x_elder_defeated", "pattern": "pat_leaf_cape"},
	"pattern_pumpkin_patch": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 3, "pumpkin": 1}, "unlock": "ch2_pumpkin_face", "pattern": "pat_pumpkin_patch"},
	"pattern_ribbon_witch": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 3, "moonpetal": 1}, "unlock": "ch2_manor_restored", "pattern": "pat_ribbon_witch"},
	"pattern_velvet_vampire": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 3, "roseberries": 2}, "unlock": "ch2_manor_restored", "pattern": "pat_velvet_vampire"},
	"pattern_velvet_cape": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 2}, "unlock": "ch2_count_wardrobe", "pattern": "pat_velvet_cape"},
	"pattern_ghostlight_party": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 3, "lantern_wax": 1}, "unlock": "ch2_candleyard_pattern", "pattern": "pat_ghostlight_party"},
	"pattern_moon_moth": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 3, "moonpetal": 2}, "unlock": "ch2_trial_matron", "pattern": "pat_moon_moth"},
	"pattern_lanternwake": {"result": "", "count": 0, "station": "loom", "ingredients": {"woven_cloth": 3, "sunflax": 2}, "unlock": "ch2_feast", "pattern": "pat_lanternwake"},
}

## Human readable station names.
const STATIONS := {"hand": "By Hand", "workbench": "Workbench", "campfire": "Campfire", "furnace": "Furnace", "loom": "Loom & Dye Bench", "kitchen": "Kitchen"}

## Structure that provides each placeable station (the Haven campfire is part of the world, hand is anywhere).
const STATION_STRUCTURES := {"workbench": "workbench", "furnace": "furnace", "loom": "loom", "kitchen": "kitchen_counter"}
