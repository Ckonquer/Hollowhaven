extends RefCounted
## Item definitions. Stable ids (keys) are used in saves: never rename an id.
## Fields:
##   name, desc          display text
##   cat                 resource | tool | weapon | food | placeable | seed | key | equipment | decor
##   stack               max stack size (1 for tools)
##   icon                icon shape id used by the icon renderer (see src/ui/icon_factory.gd)
##   color               base color for icon / pickup tint
##   tool                "axe" | "pickaxe" (for tools) ; power = hits multiplier
##   damage, reach       melee stats for tools/weapons
##   heal, buff          food healing and optional buff {"stamina_regen": 1.5, "seconds": 90}
##   place               structure id placed by this item (cat == placeable)
##   alt_name/alt_desc   used instead of name/desc when the arachnophobia option is ON
##   quest               true = quest-critical; stored in key pouch, never dropped or consumed by mistake
## Chapter Two fields (docs/CHAPTER_TWO_SPEC.md section 4.2; read them through ItemDB, never hard-code):
##   tier                tools / weapons / wands / armor / charms: stone 1, copper 2, ironwood 3, moonsteel 4
##                       (legacy items keep their entries untouched: see LEGACY_TIERS below)
##   slot                armor: "head" | "body" | "boots"   (charms always use the "charm" slot)
##   set                 armor set id in data/equipment.gd SETS
##   reduction           armor: physical damage reduction fraction of this piece (pieces add up within armor)
##   effects             charms: {"gather": 0.1, ...}  (effect ids and caps: data/equipment.gd EFFECTS)
##   ranged, range       wands: true + max range in metres (never needed for puzzles or required targets)
##   stamina, cooldown   wands: stamina per cast (shared stamina pool) and seconds between casts
##   projectile          wands: {"speed", "radius", "color", "lifetime"} of the readable spark
##   family              food buff family (see BUFF_FAMILIES): a stronger food of the same family replaces /
##                       refreshes the active buff instead of stacking. Legacy foods derive it from their buff key.
##   companion_gear      companion items (cat "companion"): true
## New categories (appended to CATEGORY_ORDER): wand, armor, charm, companion.

const ITEMS := {
	# --- Basic resources -------------------------------------------------
	"wood": {"name": "Wood", "desc": "Sturdy branches and logs. The backbone of every cozy home.", "cat": "resource", "stack": 99, "icon": "log", "color": Color("b07a4f")},
	"stone": {"name": "Stone", "desc": "Smooth grey stones. Good for tools and foundations.", "cat": "resource", "stack": 99, "icon": "stone", "color": Color("a9a39a")},
	"fiber": {"name": "Plant Fiber", "desc": "Tough grass fibers, easily twisted into cord.", "cat": "resource", "stack": 99, "icon": "fiber", "color": Color("8cc063")},
	"berries": {"name": "Berries", "desc": "Sweet redcap berries. Restores a little health. Mochi adores them.", "cat": "food", "stack": 50, "icon": "berries", "color": Color("e4665c"), "heal": 8.0},
	"copper_ore": {"name": "Copper Ore", "desc": "Warm, rust-streaked ore from the quarry.", "cat": "resource", "stack": 99, "icon": "ore", "color": Color("d98b4e")},
	"sweetroot_seeds": {"name": "Sweetroot Seeds", "desc": "Plant these in a crop plot. Sweetroot grows quickly with care.", "cat": "seed", "stack": 50, "icon": "seeds", "color": Color("d9b36a"), "crop": "sweetroot"},
	"sweetroot": {"name": "Sweetroot", "desc": "A crunchy, honey-sweet root. Restores health.", "cat": "food", "stack": 50, "icon": "root", "color": Color("f29a4a"), "heal": 15.0},
	"shiny_pebble": {"name": "Shiny Pebble", "desc": "A perfectly round, gleaming pebble. A gift from Pebble.", "cat": "resource", "stack": 50, "icon": "pebble", "color": Color("9fd3e6")},
	# --- Special dungeon materials -------------------------------------------
	"glowcap": {"name": "Glowcap", "desc": "A mushroom that glows softly in the dark. Found only below.", "cat": "resource", "stack": 50, "icon": "mushroom", "color": Color("9fe0c8")},
	"silk": {"name": "Weaver Silk", "desc": "Strong, pale silk from the Silk Hollows. Unsettlingly warm.", "cat": "resource", "stack": 50, "icon": "silk", "color": Color("e8e4f0"),
		"alt_name": "Pale Thread", "alt_desc": "Strong, pale thread from the deep hollows. Unsettlingly warm."},
	"echo_shard": {"name": "Echo Shard", "desc": "A crystal that hums with faraway sounds.", "cat": "resource", "stack": 50, "icon": "crystal", "color": Color("b9a3f0")},
	# --- Tools & weapons ------------------------------------------------------
	"stone_axe": {"name": "Stone Axe", "desc": "Fells trees. Can also defend you in a pinch.", "cat": "tool", "stack": 1, "icon": "axe", "color": Color("a9a39a"), "tool": "axe", "power": 1.0, "damage": 9.0, "reach": 2.2},
	"stone_pickaxe": {"name": "Stone Pickaxe", "desc": "Breaks rocks and ore veins.", "cat": "tool", "stack": 1, "icon": "pickaxe", "color": Color("a9a39a"), "tool": "pickaxe", "power": 1.0, "damage": 9.0, "reach": 2.2},
	"copper_sword": {"name": "Copper Sword", "desc": "A bright little blade. Swift and reliable.", "cat": "weapon", "stack": 1, "icon": "sword", "color": Color("e39a5a"), "damage": 18.0, "reach": 2.5},
	"lantern": {"name": "Lantern", "desc": "A warm light for dark places. Some things below dislike its glow.", "cat": "equipment", "stack": 1, "icon": "lantern", "color": Color("f7c35c")},
	# --- Food --------------------------------------------------------------------
	"berry_snack": {"name": "Berry Snack", "desc": "Mashed berries pressed into a chewy bar. Restores 30 health.", "cat": "food", "stack": 20, "icon": "snack", "color": Color("d9546a"), "heal": 30.0},
	"hearty_stew": {"name": "Hearty Stew", "desc": "Sweetroot and berry stew. Restores 60 health and speeds stamina recovery for a while.", "cat": "food", "stack": 20, "icon": "stew", "color": Color("d98b4e"), "heal": 60.0, "buff": {"stamina_regen": 1.6, "seconds": 120.0}},
	"glowcap_skewer": {"name": "Glowcap Skewer", "desc": "Toasted glowcaps. Restores 45 health.", "cat": "food", "stack": 20, "icon": "skewer", "color": Color("9fe0c8"), "heal": 45.0},
	# --- Placeables ---------------------------------------------------------------
	"workbench": {"name": "Workbench", "desc": "Unlocks sturdier recipes when you craft nearby.", "cat": "placeable", "stack": 5, "icon": "workbench", "color": Color("c48a55"), "place": "workbench"},
	"storage_chest": {"name": "Storage Chest", "desc": "Holds 20 stacks of your treasures.", "cat": "placeable", "stack": 5, "icon": "chest", "color": Color("b07a4f"), "place": "storage_chest"},
	"bed": {"name": "Cozy Bed", "desc": "Sleep until morning, restore health and save. You'll also wake here.", "cat": "placeable", "stack": 5, "icon": "bed", "color": Color("e4665c"), "place": "bed"},
	"crop_plot": {"name": "Crop Plot", "desc": "Tilled soil for planting seeds.", "cat": "placeable", "stack": 10, "icon": "plot", "color": Color("7a5236"), "place": "crop_plot"},
	"wood_floor": {"name": "Wooden Floor", "desc": "A 2x2 floor tile.", "cat": "placeable", "stack": 50, "icon": "floor", "color": Color("c48a55"), "place": "wood_floor"},
	"wood_wall": {"name": "Wooden Wall", "desc": "A 2m wall panel. Snaps to floor edges.", "cat": "placeable", "stack": 50, "icon": "wall", "color": Color("b07a4f"), "place": "wood_wall"},
	"wood_window": {"name": "Window Wall", "desc": "A wall panel with a round window.", "cat": "placeable", "stack": 50, "icon": "window", "color": Color("b07a4f"), "place": "wood_window"},
	"wood_doorway": {"name": "Doorway", "desc": "A wall panel with an open arch you can walk through.", "cat": "placeable", "stack": 50, "icon": "doorway", "color": Color("b07a4f"), "place": "wood_doorway"},
	"wood_roof": {"name": "Roof Tile", "desc": "A sloped thatch roof section.", "cat": "placeable", "stack": 50, "icon": "roof", "color": Color("d9a650"), "place": "wood_roof"},
	"fence": {"name": "Picket Fence", "desc": "A short decorative fence.", "cat": "placeable", "stack": 50, "icon": "fence", "color": Color("e8d7b5"), "place": "fence"},
	"lantern_post": {"name": "Lantern Post", "desc": "A warm light on a wooden post.", "cat": "placeable", "stack": 20, "icon": "lamppost", "color": Color("f7c35c"), "place": "lantern_post"},
	"flower_pot": {"name": "Flower Pot", "desc": "Cheerful flowers in a stone pot.", "cat": "placeable", "stack": 20, "icon": "flowerpot", "color": Color("f2a7c0"), "place": "flower_pot"},
	"rug": {"name": "Woven Rug", "desc": "A soft berry-dyed rug.", "cat": "placeable", "stack": 20, "icon": "rug", "color": Color("d9546a"), "place": "rug"},
	"table": {"name": "Table", "desc": "A small round wooden table.", "cat": "placeable", "stack": 20, "icon": "table", "color": Color("c48a55"), "place": "table"},
	"stool": {"name": "Stool", "desc": "A three-legged stool.", "cat": "placeable", "stack": 20, "icon": "stool", "color": Color("c48a55"), "place": "stool"},
	"pebble_cairn": {"name": "Pebble Cairn", "desc": "A tidy stack of Pebble's finest gifts.", "cat": "placeable", "stack": 20, "icon": "cairn", "color": Color("9fd3e6"), "place": "pebble_cairn"},
	"echo_chime": {"name": "Echo Chime", "desc": "A wind chime of echo shards. It sings softly in the breeze.", "cat": "placeable", "stack": 20, "icon": "chime", "color": Color("b9a3f0"), "place": "echo_chime"},
	"heartbloom_lamp": {"name": "Heartbloom Lamp", "desc": "A glowing flower lamp grown from the Heartseed's light.", "cat": "placeable", "stack": 20, "icon": "heartbloom", "color": Color("ffb3c7"), "place": "heartbloom_lamp"},
	"haven_banner": {"name": "Haven Banner", "desc": "A banner stitched with the Haven's sigil. For Krystal.", "cat": "placeable", "stack": 5, "icon": "banner", "color": Color("3fa7a0"), "place": "haven_banner"},
	# --- Quest (key) items: stored in the key pouch, never dropped ------------------
	"foreman_key": {"name": "Foreman's Key", "desc": "A heavy iron key stamped with a pickaxe. It opens the old mine's lower gate.", "cat": "key", "stack": 1, "icon": "key", "color": Color("c9b27a"), "quest": true},
	"heartseed": {"name": "The Heartseed", "desc": "A warm, glowing seed that beats like a tiny heart. It belongs in the Ward Stone.", "cat": "key", "stack": 1, "icon": "heartseed", "color": Color("ff8fa8"), "quest": true},
	# ================= Chapter Two (append only; ids are binding, see docs/CHAPTER_TWO_SPEC.md 4.2) =================
	# --- New resources ------------------------------------------------------------------------------
	"sunflax": {"name": "Sunflax", "desc": "Golden flax stalks that ripple like sunlight. Spun at a Loom into woven cloth.", "cat": "resource", "stack": 99, "icon": "flax", "color": Color("f2cf62")},
	"roseberries": {"name": "Roseberries", "desc": "Plump rosy berries that taste like jam. A little snack and a lovely rose dye.", "cat": "food", "stack": 50, "icon": "roseberries", "color": Color("e0607e"), "heal": 10.0},
	"resin": {"name": "Amber Resin", "desc": "Sticky golden sap tapped from old stumps. Seals tool hafts and melts into lantern wax.", "cat": "resource", "stack": 99, "icon": "resin", "color": Color("e8a33d")},
	"iron_ore": {"name": "Iron Ore", "desc": "Heavy grey-blue ore from Ashbell Quarry. Smelt it into bars at a Furnace.", "cat": "resource", "stack": 99, "icon": "iron_ore", "color": Color("8e9ab3")},
	"woven_cloth": {"name": "Woven Cloth", "desc": "Soft sunflax cloth from the Loom. For outfits, ribbons and cozy furnishings.", "cat": "resource", "stack": 99, "icon": "cloth", "color": Color("f0dcc0")},
	"copper_bar": {"name": "Copper Bar", "desc": "A warm, gleaming bar smelted from copper ore at a Furnace.", "cat": "resource", "stack": 50, "icon": "bar", "color": Color("d98b4e")},
	"iron_bar": {"name": "Iron Bar", "desc": "A sturdy bar of smelted iron. Tougher tools and armor start here.", "cat": "resource", "stack": 50, "icon": "bar", "color": Color("a3adbf")},
	"moon_crystal": {"name": "Moon Crystal", "desc": "A pale crystal from Ashbell's upper shelf that glows like moonlight. Only an Ironwood pickaxe or better can mine it.", "cat": "resource", "stack": 50, "icon": "moon_crystal", "color": Color("c9d8ff")},
	"moonsteel_bar": {"name": "Moonsteel Bar", "desc": "Iron, moon crystal and an echo shard fused into a softly shimmering bar.", "cat": "resource", "stack": 50, "icon": "bar_moon", "color": Color("c3c9f5")},
	"pumpkin": {"name": "Pumpkin", "desc": "A round, cheerful pumpkin. Cook it, carve it, or save its seeds. Restores a little health.", "cat": "food", "stack": 20, "icon": "pumpkin", "color": Color("f08a2e"), "heal": 12.0},
	"sugarcap": {"name": "Sugarcap", "desc": "A sweet pastel mushroom from the Thimblebrook pools. Perfect for desserts.", "cat": "resource", "stack": 50, "icon": "sugarcap", "color": Color("f5b8d0")},
	"moonpetal": {"name": "Moonpetal", "desc": "Pale blue petals that open by moonlight. Brewed into tea or pressed into lavender dye.", "cat": "resource", "stack": 50, "icon": "moonpetal", "color": Color("a9b8f2")},
	"lantern_wax": {"name": "Lantern Wax", "desc": "Honey-coloured wax for candles, ghost lanterns and pumpkin lights.", "cat": "resource", "stack": 50, "icon": "wax", "color": Color("f4d58a")},
	"candy": {"name": "Lanternwake Candy", "desc": "A twist of festival candy. A tiny treat that restores a little health.", "cat": "food", "stack": 50, "icon": "candy", "color": Color("f28bb0"), "heal": 5.0},
	# --- New seeds -----------------------------------------------------------------------------------
	"sunflax_seeds": {"name": "Sunflax Seeds", "desc": "Plant these in a crop plot. They grow into golden sunflax.", "cat": "seed", "stack": 50, "icon": "seeds_sunflax", "color": Color("e0bb5a"), "crop": "sunflax"},
	"roseberry_seeds": {"name": "Roseberry Seeds", "desc": "Plant these in a crop plot. They grow into a little roseberry bush.", "cat": "seed", "stack": 50, "icon": "seeds_roseberry", "color": Color("d9607a"), "crop": "roseberry"},
	"pumpkin_seeds": {"name": "Pumpkin Seeds", "desc": "Plant these in a crop plot. They grow into a round festival pumpkin.", "cat": "seed", "stack": 50, "icon": "seeds_pumpkin", "color": Color("f0c27a"), "crop": "pumpkin"},
	# --- Tools (gathering efficiency via power; modest damage: no tool ever out-hits the Copper Sword) -----
	"copper_axe": {"name": "Copper Axe", "desc": "A bright copper axe. Fells trees much faster than stone.", "cat": "tool", "stack": 1, "icon": "axe", "color": Color("d98b4e"), "tool": "axe", "power": 1.5, "damage": 10.0, "reach": 2.2, "tier": 2},
	"copper_pickaxe": {"name": "Copper Pickaxe", "desc": "A bright copper pickaxe. Breaks rock and ore faster than stone.", "cat": "tool", "stack": 1, "icon": "pickaxe", "color": Color("d98b4e"), "tool": "pickaxe", "power": 1.5, "damage": 10.0, "reach": 2.2, "tier": 2},
	"ironwood_axe": {"name": "Ironwood Axe", "desc": "An iron head on a resin-sealed ironwood haft. Chops quickly and cleanly.", "cat": "tool", "stack": 1, "icon": "axe", "color": Color("9aa6ba"), "tool": "axe", "power": 2.0, "damage": 12.0, "reach": 2.2, "tier": 3},
	"ironwood_pickaxe": {"name": "Ironwood Pickaxe", "desc": "An iron pick on an ironwood haft. Strong enough to mine Moon Crystal.", "cat": "tool", "stack": 1, "icon": "pickaxe", "color": Color("9aa6ba"), "tool": "pickaxe", "power": 2.0, "damage": 12.0, "reach": 2.2, "tier": 3},
	"moonsteel_axe": {"name": "Moonsteel Axe", "desc": "A moon-bright axe. The fastest woodcutting tool there is.", "cat": "tool", "stack": 1, "icon": "axe", "color": Color("c3c9f5"), "tool": "axe", "power": 2.5, "damage": 14.0, "reach": 2.2, "tier": 4},
	"moonsteel_pickaxe": {"name": "Moonsteel Pickaxe", "desc": "A moon-bright pickaxe. Crystal and ore give way in a few taps.", "cat": "tool", "stack": 1, "icon": "pickaxe", "color": Color("c3c9f5"), "tool": "pickaxe", "power": 2.5, "damage": 14.0, "reach": 2.2, "tier": 4},
	# --- Weapons ---------------------------------------------------------------------------------------
	"ironwood_sword": {"name": "Ironwood Sword", "desc": "A balanced iron blade on an ironwood grip. A real step up from copper.", "cat": "weapon", "stack": 1, "icon": "sword", "color": Color("9aa6ba"), "damage": 25.0, "reach": 2.5, "tier": 3},
	"moonsteel_sword": {"name": "Moonsteel Sword", "desc": "A moon-bright blade that hums faintly with far-off echoes.", "cat": "weapon", "stack": 1, "icon": "sword", "color": Color("c3c9f5"), "damage": 34.0, "reach": 2.6, "tier": 4},
	"sparkseed_wand": {"name": "Sparkseed Wand", "desc": "A copper wand tipped with a glowcap seed. It flicks a bright, slow spark at a foe up to 14 m away and shares your stamina. Handy, never required.", "cat": "wand", "stack": 1, "icon": "wand", "color": Color("f2c14e"),
		"damage": 9.0, "reach": 2.0, "tier": 2, "ranged": true, "range": 14.0, "stamina": 8.0, "cooldown": 0.8,
		"projectile": {"speed": 16.0, "radius": 0.22, "color": Color("ffe08a"), "lifetime": 0.9}},
	# --- Armor (full-set totals: padded 6%, copperwood 12%, ironwood 20%, moonsteel 26%; split 25/50/25) -----
	"padded_hood": {"name": "Padded Hood", "desc": "A quilted cloth hood (1.5% protection). Padded set: 6% with all three pieces.", "cat": "armor", "stack": 1, "icon": "hood", "color": Color("d9c49a"), "tier": 1, "set": "padded", "slot": "head", "reduction": 0.015},
	"padded_vest": {"name": "Padded Vest", "desc": "A quilted cloth vest (3% protection). Padded set: 6% with all three pieces.", "cat": "armor", "stack": 1, "icon": "vest", "color": Color("d9c49a"), "tier": 1, "set": "padded", "slot": "body", "reduction": 0.03},
	"padded_boots": {"name": "Padded Boots", "desc": "Quilted cloth boots (1.5% protection). Padded set: 6% with all three pieces.", "cat": "armor", "stack": 1, "icon": "armor_boots", "color": Color("d9c49a"), "tier": 1, "set": "padded", "slot": "boots", "reduction": 0.015},
	"copperwood_hood": {"name": "Copperwood Hood", "desc": "Cloth hood with copper rivets (3% protection). Copperwood set: 12% with all three pieces.", "cat": "armor", "stack": 1, "icon": "hood", "color": Color("c98a55"), "tier": 2, "set": "copperwood", "slot": "head", "reduction": 0.03},
	"copperwood_vest": {"name": "Copperwood Vest", "desc": "A cloth vest with copper plates (6% protection). Copperwood set: 12% with all three pieces.", "cat": "armor", "stack": 1, "icon": "vest", "color": Color("c98a55"), "tier": 2, "set": "copperwood", "slot": "body", "reduction": 0.06},
	"copperwood_boots": {"name": "Copperwood Boots", "desc": "Boots with copper toe caps (3% protection). Copperwood set: 12% with all three pieces.", "cat": "armor", "stack": 1, "icon": "armor_boots", "color": Color("c98a55"), "tier": 2, "set": "copperwood", "slot": "boots", "reduction": 0.03},
	"ironwood_helm": {"name": "Ironwood Helm", "desc": "A light iron helm lined with cloth (5% protection). Ironwood set: 20% with all three pieces.", "cat": "armor", "stack": 1, "icon": "helm", "color": Color("9aa6ba"), "tier": 3, "set": "ironwood", "slot": "head", "reduction": 0.05},
	"ironwood_mail": {"name": "Ironwood Mail", "desc": "Iron scales over quilted cloth (10% protection). Ironwood set: 20% with all three pieces.", "cat": "armor", "stack": 1, "icon": "mail", "color": Color("9aa6ba"), "tier": 3, "set": "ironwood", "slot": "body", "reduction": 0.1},
	"ironwood_boots": {"name": "Ironwood Boots", "desc": "Iron-shod travelling boots (5% protection). Ironwood set: 20% with all three pieces.", "cat": "armor", "stack": 1, "icon": "armor_boots", "color": Color("9aa6ba"), "tier": 3, "set": "ironwood", "slot": "boots", "reduction": 0.05},
	"moonsteel_helm": {"name": "Moonsteel Helm", "desc": "A moon-bright helm (6.5% protection). Moonsteel set: 26% with all three pieces.", "cat": "armor", "stack": 1, "icon": "helm", "color": Color("c3c9f5"), "tier": 4, "set": "moonsteel", "slot": "head", "reduction": 0.065},
	"moonsteel_mail": {"name": "Moonsteel Mail", "desc": "Shimmering moonsteel scales (13% protection). Moonsteel set: 26% with all three pieces.", "cat": "armor", "stack": 1, "icon": "mail", "color": Color("c3c9f5"), "tier": 4, "set": "moonsteel", "slot": "body", "reduction": 0.13},
	"moonsteel_boots": {"name": "Moonsteel Boots", "desc": "Light moonsteel boots (6.5% protection). Moonsteel set: 26% with all three pieces.", "cat": "armor", "stack": 1, "icon": "armor_boots", "color": Color("c3c9f5"), "tier": 4, "set": "moonsteel", "slot": "boots", "reduction": 0.065},
	# --- Charms (one charm slot; choices, not a required damage tier) -----------------------------------
	"gatherers_charm": {"name": "Gatherer's Charm", "desc": "A resin-bright leaf charm. Trees, rocks and ore need 10% less effort.", "cat": "charm", "stack": 1, "icon": "charm_leaf", "color": Color("8cc063"), "tier": 2, "effects": {"gather": 0.1}},
	"swiftstep_charm": {"name": "Swiftstep Charm", "desc": "A moonpetal feather charm. Sprinting and rolling cost 12% less stamina, and your step is a touch lighter (+4% speed, within the usual cap).", "cat": "charm", "stack": 1, "icon": "charm_feather", "color": Color("a9b8f2"), "tier": 3, "effects": {"stamina_save": 0.12, "move": 0.04}},
	"kindling_charm": {"name": "Kindling Charm", "desc": "A moonsteel flame charm. Healing is 10% stronger and your lantern glows a little wider.", "cat": "charm", "stack": 1, "icon": "charm_flame", "color": Color("ffb35c"), "tier": 4, "effects": {"heal_received": 0.1, "lantern_radius": 0.2}},
	# --- Food (timed buffs: one effect + seconds; "family" decides replacement, see BUFF_FAMILIES) --------
	"pumpkin_soup": {"name": "Pumpkin Soup", "desc": "Velvety pumpkin and sweetroot soup. Restores 40 health.", "cat": "food", "stack": 20, "icon": "soup", "color": Color("f08a2e"), "heal": 40.0},
	"pumpkin_biscuit": {"name": "Pumpkin Biscuit", "desc": "A small spiced snack (a batch makes two). Restores 18 health.", "cat": "food", "stack": 20, "icon": "biscuit", "color": Color("e8a860"), "heal": 18.0},
	"roseberry_tart": {"name": "Roseberry Tart", "desc": "A sweet little tart. Restores 30 health and helps stamina recover for a minute.", "cat": "food", "stack": 20, "icon": "tart", "color": Color("e0607e"), "heal": 30.0, "buff": {"stamina_regen": 1.3, "seconds": 60.0}, "family": "stamina"},
	"moonpetal_tea": {"name": "Moonpetal Tea", "desc": "A calming blue tea. Restores 12 health and halves slowing from mud and roots for 90 seconds.", "cat": "food", "stack": 20, "icon": "tea", "color": Color("a9b8f2"), "heal": 12.0, "buff": {"slow_resist": 0.5, "seconds": 90.0}, "family": "steady"},
	"lanternwake_platter": {"name": "Lanternwake Platter", "desc": "A festival feast of pumpkin, roseberries and sweetroot. Restores 80 health and speeds stamina recovery for a good while.", "cat": "food", "stack": 20, "icon": "platter", "color": Color("f2c14e"), "heal": 80.0, "buff": {"stamina_regen": 1.5, "seconds": 150.0}, "family": "stamina"},
	# --- Companion gear -------------------------------------------------------------------------------
	"comfort_ribbon": {"name": "Comfort Ribbon", "desc": "A soft ribbon tied with love. Give it to Mochi for a brave little walk to the mine's lit threshold.", "cat": "companion", "stack": 1, "icon": "ribbon", "color": Color("f4a0ab"), "companion_gear": true},
	# --- Key items (key pouch; guaranteed story/optional sources, never random drops) -------------------
	"garden_seal": {"name": "Garden Seal", "desc": "A lantern seal of pressed leaves and amber, returned by the Pumpkintide garden lamp.", "cat": "key", "stack": 1, "icon": "seal", "color": Color("8cc063"), "quest": true},
	"quarry_seal": {"name": "Quarry Seal", "desc": "A lantern seal cast in old bell bronze, returned by the Ashbell quarry lamp.", "cat": "key", "stack": 1, "icon": "seal", "color": Color("d98b4e"), "quest": true},
	"manor_seal": {"name": "Manor Seal", "desc": "A lantern seal of crescent-stamped velvet wax, returned by the Moonveil Manor lantern.", "cat": "key", "stack": 1, "icon": "seal", "color": Color("8a5a9e"), "quest": true},
	"velvet_scrap": {"name": "Velvet Scrap", "desc": "A scrap of the Count's velvet. Three together would make a proper pattern.", "cat": "key", "stack": 1, "icon": "scrap", "color": Color("9b3b5a"), "quest": true},
	# --- Placeables (one per new structure; each id places the structure with the same id) -------------
	"wood_stairs": {"name": "Wooden Stairs", "desc": "A sturdy 2x4 m staircase up to an upper floor. Add an Upper Floor at the top landing.", "cat": "placeable", "stack": 20, "icon": "stairs", "color": Color("c48a55"), "place": "wood_stairs"},
	"upper_floor": {"name": "Upper Floor", "desc": "A 2x2 floor tile for a second storey. It rests on walls, posts or other supported upper floor.", "cat": "placeable", "stack": 50, "icon": "upper_floor", "color": Color("c48a55"), "place": "upper_floor"},
	"wood_railing": {"name": "Railing", "desc": "A waist-high railing for landings, porches and balconies.", "cat": "placeable", "stack": 50, "icon": "railing", "color": Color("dcae78"), "place": "wood_railing"},
	"half_wall": {"name": "Half Wall", "desc": "A low 2 m wall panel. Lovely for porches and cozy nooks.", "cat": "placeable", "stack": 50, "icon": "half_wall", "color": Color("b07a4f"), "place": "half_wall"},
	"porch_post": {"name": "Porch Post", "desc": "A carved post that holds up porch roofs and upper floors.", "cat": "placeable", "stack": 50, "icon": "porch_post", "color": Color("8e5f3a"), "place": "porch_post"},
	"arched_window": {"name": "Arched Window", "desc": "A wall panel with a tall arched window.", "cat": "placeable", "stack": 50, "icon": "arched_window", "color": Color("b07a4f"), "place": "arched_window"},
	"gable_roof": {"name": "Gable Roof", "desc": "A steep gable-end roof section with a little round vent.", "cat": "placeable", "stack": 50, "icon": "gable_roof", "color": Color("d9a650"), "place": "gable_roof"},
	"roof_corner": {"name": "Roof Corner", "desc": "A hipped roof piece that neatly finishes corners.", "cat": "placeable", "stack": 50, "icon": "roof_corner", "color": Color("d9a650"), "place": "roof_corner"},
	"flower_box": {"name": "Window Flower Box", "desc": "A planter box of bright flowers to hang under a window.", "cat": "placeable", "stack": 20, "icon": "flower_box", "color": Color("f2a7c0"), "place": "flower_box"},
	"curtain": {"name": "Curtains", "desc": "Soft cloth curtains to frame a window.", "cat": "placeable", "stack": 20, "icon": "curtain", "color": Color("d9546a"), "place": "curtain"},
	"bookshelf": {"name": "Bookshelf", "desc": "A tall shelf of storybooks, jars and keepsakes.", "cat": "placeable", "stack": 20, "icon": "bookshelf", "color": Color("8e5f3a"), "place": "bookshelf"},
	"wardrobe": {"name": "Wardrobe", "desc": "Change outfits and save favourite looks at home. Styling is always free.", "cat": "placeable", "stack": 20, "icon": "wardrobe", "color": Color("c48a55"), "place": "wardrobe"},
	"vanity_mirror": {"name": "Vanity Mirror", "desc": "A pretty mirror for restyling hair and outfits whenever you like.", "cat": "placeable", "stack": 20, "icon": "mirror", "color": Color("e0b85a"), "place": "vanity_mirror"},
	"kitchen_counter": {"name": "Kitchen Counter", "desc": "An improved kitchen for new meals. The campfire still cooks everything it did before.", "cat": "placeable", "stack": 20, "icon": "kitchen", "color": Color("b8b2a7"), "place": "kitchen_counter"},
	"furnace": {"name": "Furnace", "desc": "Smelts ore into bars in short batches. Queue a few jobs and collect them when they're done.", "cat": "placeable", "stack": 5, "icon": "furnace", "color": Color("c9745a"), "place": "furnace"},
	"loom": {"name": "Loom & Dye Bench", "desc": "Weave sunflax into cloth, sew clothing patterns and mix dye palettes.", "cat": "placeable", "stack": 5, "icon": "loom", "color": Color("c48a55"), "place": "loom"},
	"companion_bed": {"name": "Companion Bed", "desc": "A snug little bed. Choose it as a friend's home spot.", "cat": "placeable", "stack": 20, "icon": "pet_bed", "color": Color("e4665c"), "place": "companion_bed"},
	"companion_perch": {"name": "Companion Perch", "desc": "A cozy perch with a lantern hook. Some friends love a high spot.", "cat": "placeable", "stack": 20, "icon": "perch", "color": Color("dcae78"), "place": "companion_perch"},
	"sturdy_planter": {"name": "Sturdy Planter", "desc": "A raised planter box that grows crops just like a crop plot.", "cat": "placeable", "stack": 10, "icon": "planter", "color": Color("8e5f3a"), "place": "sturdy_planter"},
	"cottage_bench": {"name": "Cottage Bench", "desc": "A painted bench for sitting and watching the Haven.", "cat": "placeable", "stack": 20, "icon": "bench", "color": Color("3fa7a0"), "place": "cottage_bench"},
	"pumpkin_lantern": {"name": "Carved Pumpkin", "desc": "A glowing carved pumpkin. Pick its face (friendly, sleepy, toothy, cat, moon or ghost) and change it any time.", "cat": "placeable", "stack": 20, "icon": "jack_lantern", "color": Color("f08a2e"), "place": "pumpkin_lantern"},
	"pumpkin_lights": {"name": "Pumpkin String Lights", "desc": "A string of tiny glowing pumpkins.", "cat": "placeable", "stack": 20, "icon": "string_lights", "color": Color("f5a142"), "place": "pumpkin_lights"},
	"bat_bunting": {"name": "Bat Bunting", "desc": "A cheerful garland of little felt bats.", "cat": "placeable", "stack": 20, "icon": "bunting", "color": Color("6b4a7a"), "place": "bat_bunting"},
	"ghost_lantern": {"name": "Ghost Lantern", "desc": "A friendly ghost-shaped lantern with a cool, soft glow.", "cat": "placeable", "stack": 20, "icon": "ghost_lantern", "color": Color("d8e8ff"), "place": "ghost_lantern"},
	"crescent_window": {"name": "Crescent Window", "desc": "A wall panel with a moon-shaped window, just like Moonveil Manor's.", "cat": "placeable", "stack": 50, "icon": "crescent_window", "color": Color("6b4a7a"), "place": "crescent_window"},
	"candy_bowl": {"name": "Candy Bowl", "desc": "A bowl of Lanternwake candy for visitors.", "cat": "placeable", "stack": 20, "icon": "candy_bowl", "color": Color("f28bb0"), "place": "candy_bowl"},
	"scarecrow": {"name": "Scarecrow", "desc": "A friendly straw scarecrow with a pumpkin head. Purely decorative: it never wakes up.", "cat": "placeable", "stack": 20, "icon": "scarecrow", "color": Color("d9a650"), "place": "scarecrow"},
	"gothic_trim": {"name": "Gothic Porch Trim", "desc": "Ornate iron-and-wood trim for porch eaves.", "cat": "placeable", "stack": 50, "icon": "gothic_trim", "color": Color("5a4a6e"), "place": "gothic_trim"},
	"music_box": {"name": "Music Box", "desc": "Plays the songs you have heard in safe places and keeps your favourites.", "cat": "placeable", "stack": 5, "icon": "music_box", "color": Color("c48a55"), "place": "music_box"},
	"expedition_board": {"name": "Expedition Board", "desc": "Choose an optional Lanternwake expedition and see its difficulty and rewards before you set out.", "cat": "placeable", "stack": 5, "icon": "board", "color": Color("8e5f3a"), "place": "expedition_board"},
	"wardlight": {"name": "Wardlight", "desc": "A small lamp of true ward-light, kindled from the restored lanterns of Hallowmere.", "cat": "placeable", "stack": 20, "icon": "wardlight", "color": Color("ffe2a0"), "place": "wardlight"},
	"miner_lamp": {"name": "Miner's Lamp", "desc": "Tobin's old brass mining lamp, polished and glowing again.", "cat": "placeable", "stack": 20, "icon": "miner_lamp", "color": Color("e0b85a"), "place": "miner_lamp"},
	"thread_veil": {"name": "Thread Veil", "desc": "A shimmering drape woven from the threads cleared at Weaver's Crossing.", "cat": "placeable", "stack": 20, "icon": "veil", "color": Color("e8e4f0"), "place": "thread_veil",
		"alt_name": "Pale Veil Drape", "alt_desc": "A shimmering pale drape woven from threads cleared deep in the Hushed Works."},
	"lanternwake_table": {"name": "Lanternwake Table", "desc": "A long festival table with candles and a table runner. Guests welcome.", "cat": "placeable", "stack": 20, "icon": "festival_table", "color": Color("c48a55"), "place": "lanternwake_table"},
}

## Display order for inventory sorting / crafting lists (legacy entries first, Chapter Two categories appended).
const CATEGORY_ORDER := ["tool", "weapon", "equipment", "food", "resource", "seed", "placeable", "key", "wand", "armor", "charm", "companion"]

## Tiers of legacy items (their ITEMS entries stay byte-identical): stone tools are tier 1, the Copper Sword
## belongs to the copper tier. ItemDB.item_tier() reads this, then the item's own "tier".
const LEGACY_TIERS := {"stone_axe": 1, "stone_pickaxe": 1, "copper_sword": 2}

## Food buff families. Rule (implemented by the stats/food module): eating a food whose buff belongs to a family
## that is already active REPLACES the active buff when the new one is stronger (by `stronger`), otherwise only
## refreshes the remaining time up to the new food's duration; buffs of one family never stack.
## Legacy foods have no "family" field: their family comes from their buff key via `effect`.
## Effect keys are the timed-buff keys of docs/CHAPTER_TWO_SPEC.md section 9 (GameState.add_buff(key, mult, s)):
##   stamina_regen  stamina recovery multiplier (> 1; legacy)
##   slow_resist    multiplier on the strength of incoming slows while active (0.5 = slows are half as strong;
##                  GameState.buff_mult's 1.0 when absent = normal slows), so a LOWER value is stronger
const BUFF_FAMILIES := {
	"stamina": {"effect": "stamina_regen", "stronger": "higher", "name": "Warm stamina"},
	"steady": {"effect": "slow_resist", "stronger": "lower", "name": "Steady feet"},
}
