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
}

## Display order for inventory sorting / crafting lists.
const CATEGORY_ORDER := ["tool", "weapon", "equipment", "food", "resource", "seed", "placeable", "key"]
