extends "res://tests/test_case.gd"
## Chapter Two must never change Chapter One data (docs/CHAPTER_TWO_SPEC.md section 0): every legacy item,
## recipe, structure, crop and enemy keeps exactly the fields it had in the Chapter One release, the legacy ids
## keep their order at the front of each table, and the legacy categories / stations are still there.
## The LEGACY_* constants below are a verbatim snapshot of `git show HEAD:game/data/*.gd` taken before the
## Chapter Two catalogue was added (commit d199b89).

const ItemsData := preload("res://data/items.gd")
const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const EnemiesData := preload("res://data/enemies.gd")
const SourcesData := preload("res://data/sources.gd")

const LEGACY_ITEMS := {
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

const LEGACY_CATEGORY_ORDER := ["tool", "weapon", "equipment", "food", "resource", "seed", "placeable", "key"]

const LEGACY_RECIPES := {
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
}

const LEGACY_STATIONS := {"hand": "By Hand", "workbench": "Workbench", "campfire": "Campfire"}

const LEGACY_STRUCTURES := {
	"workbench": {"name": "Workbench", "item": "workbench", "layer": "object", "snap": "cell", "size": Vector2i(2, 1), "height": 1.0, "solid": true, "interact": "station", "station": "workbench"},
	"storage_chest": {"name": "Storage Chest", "item": "storage_chest", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": true, "interact": "storage", "slots": 20},
	"bed": {"name": "Cozy Bed", "item": "bed", "layer": "object", "snap": "cell", "size": Vector2i(1, 2), "height": 0.7, "solid": true, "interact": "sleep"},
	"crop_plot": {"name": "Crop Plot", "item": "crop_plot", "layer": "object", "snap": "cell", "size": Vector2i(2, 2), "height": 0.25, "solid": false, "interact": "farm"},
	"wood_floor": {"name": "Wooden Floor", "item": "wood_floor", "layer": "floor", "snap": "floor2", "size": Vector2i(2, 2), "height": 0.15, "solid": true, "interact": ""},
	"wood_wall": {"name": "Wooden Wall", "item": "wood_wall", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": ""},
	"wood_window": {"name": "Window Wall", "item": "wood_window", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": ""},
	"wood_doorway": {"name": "Doorway", "item": "wood_doorway", "layer": "edge", "snap": "edge2", "size": Vector2i(2, 1), "height": 3.0, "solid": true, "interact": "", "passable": true},
	"wood_roof": {"name": "Roof Tile", "item": "wood_roof", "layer": "roof", "snap": "roof2", "size": Vector2i(2, 2), "height": 1.2, "solid": true, "interact": ""},
	"fence": {"name": "Picket Fence", "item": "fence", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.9, "solid": true, "interact": ""},
	"lantern_post": {"name": "Lantern Post", "item": "lantern_post", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.2, "solid": true, "interact": "", "light": {"color": Color("ffc978"), "energy": 1.6, "range": 7.0}},
	"flower_pot": {"name": "Flower Pot", "item": "flower_pot", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": false, "interact": ""},
	"rug": {"name": "Woven Rug", "item": "rug", "layer": "decor", "snap": "cell", "size": Vector2i(2, 2), "height": 0.03, "solid": false, "interact": ""},
	"table": {"name": "Table", "item": "table", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.8, "solid": true, "interact": ""},
	"stool": {"name": "Stool", "item": "stool", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.5, "solid": false, "interact": ""},
	"pebble_cairn": {"name": "Pebble Cairn", "item": "pebble_cairn", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 0.7, "solid": false, "interact": ""},
	"echo_chime": {"name": "Echo Chime", "item": "echo_chime", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.0, "solid": false, "interact": ""},
	"heartbloom_lamp": {"name": "Heartbloom Lamp", "item": "heartbloom_lamp", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 1.6, "solid": false, "interact": "", "light": {"color": Color("ffb3c7"), "energy": 1.4, "range": 6.0}},
	"haven_banner": {"name": "Haven Banner", "item": "haven_banner", "layer": "object", "snap": "cell", "size": Vector2i(1, 1), "height": 2.6, "solid": true, "interact": ""},
}

const LEGACY_CROPS := {
	"sweetroot": {"name": "Sweetroot", "seed": "sweetroot_seeds", "grow_minutes": 360.0, "stages": 4, "yield": {"sweetroot": [2, 3], "sweetroot_seeds": [1, 2]}},
}

const LEGACY_ENEMIES := {
	"brambling": {
		"name": "Brambling", "alt_name": "",
		"hp": 30.0, "damage": 10.0, "speed": 3.2, "chase_speed": 4.4,
		"aggro_radius": 9.0, "leash_radius": 22.0, "attack_range": 1.8,
		"telegraph": 0.7, "recover": 1.1, "cooldown": 1.6, "knockback": 5.0,
		"drops": [{"item": "fiber", "min": 1, "max": 3, "chance": 1.0}, {"item": "berries", "min": 1, "max": 2, "chance": 0.5}],
		"sound": "brambling", "area": "surface",
		"desc": "A grumpy walking thornball. It wiggles before it pounces.",
	},
	"gloomling": {
		"name": "Gloomling", "alt_name": "",
		"hp": 40.0, "damage": 12.0, "speed": 3.0, "chase_speed": 4.8,
		"aggro_radius": 11.0, "leash_radius": 26.0, "attack_range": 1.9,
		"telegraph": 0.8, "recover": 1.2, "cooldown": 1.8, "knockback": 5.5,
		"light_fear": true,                # hesitates in lantern light and takes double damage while "exposed"
		"drops": [{"item": "glowcap", "min": 0, "max": 1, "chance": 0.6}, {"item": "echo_shard", "min": 1, "max": 1, "chance": 0.25}],
		"sound": "gloomling", "area": "below",
		"desc": "A shadow with glowing eyes. Its eyes flare before it swipes. It hates bright light.",
	},
	"weaver": {
		"name": "The Weaver", "alt_name": "The Hollow Shade",
		"hp": 999.0, "damage": 18.0, "speed": 5.0, "chase_speed": 6.0,
		"telegraph": 1.0, "recover": 1.6, "cooldown": 4.0, "knockback": 6.0,
		"light_fear": true, "stalker": true,
		"sound": "weaver", "alt_sound": "shade", "area": "below",
		"desc": "Something that lives in the Silk Hollows. It rattles before it strikes and flees from strong light.",
	},
	"weaver_matron": {
		"name": "The Weaver Matron", "alt_name": "The Hollow Mother",
		"hp": 240.0, "damage": 20.0, "speed": 5.0,
		"telegraph": 1.2, "recover": 2.5, "cooldown": 3.0, "knockback": 7.0,
		"light_fear": true, "boss": true,
		"sound": "weaver", "alt_sound": "shade", "area": "below",
		"desc": "The guardian that took the Heartseed. Light the braziers to drive it from the ceiling.",
	},
}


# ------------------------------------------------------------------------------------------------------------

func _check_table(live: Dictionary, legacy: Dictionary, what: String) -> void:
	var live_keys: Array = live.keys()
	assert_true(live_keys.size() >= legacy.size(), what + " lost entries")
	assert_eq(live_keys.slice(0, legacy.size()), legacy.keys(), what + ": legacy ids first, in their original order")
	for id in legacy:
		assert_true(live.has(id), "%s %s still exists" % [what, id])
		if not live.has(id):
			continue
		var a: Dictionary = live[id]
		var b: Dictionary = legacy[id]
		assert_eq(a.keys(), b.keys(), "%s %s has exactly its legacy fields" % [what, id])
		for k in b:
			assert_true(a.get(k) == b[k] and typeof(a.get(k)) == typeof(b[k]), "%s %s.%s unchanged (%s -> %s)" % [what, id, k, str(b[k]), str(a.get(k))])


func test_legacy_items_are_byte_identical() -> void:
	_check_table(ItemsData.ITEMS, LEGACY_ITEMS, "item")
	assert_eq(LEGACY_ITEMS.size(), 39, "snapshot covers all 39 Chapter One items")


func test_legacy_recipes_are_byte_identical() -> void:
	_check_table(RecipesData.RECIPES, LEGACY_RECIPES, "recipe")
	assert_eq(LEGACY_RECIPES.size(), 25)
	for rid in RecipesData.SPECIAL_RECIPES:
		assert_false(LEGACY_RECIPES.has(rid), rid + " special recipe never shadows a legacy id")


func test_legacy_structures_and_crops_are_byte_identical() -> void:
	_check_table(StructuresData.STRUCTURES, LEGACY_STRUCTURES, "structure")
	_check_table(StructuresData.CROPS, LEGACY_CROPS, "crop")
	assert_eq(LEGACY_STRUCTURES.size(), 19)
	assert_eq(int(StructuresData.STRUCTURES["storage_chest"]["slots"]), 20, "legacy chests keep 20 slots (upgrades live in data.slots)")


func test_legacy_enemies_are_byte_identical() -> void:
	_check_table(EnemiesData.ENEMIES, LEGACY_ENEMIES, "enemy")
	assert_eq(float(EnemiesData.ENEMIES["brambling"]["hp"]), 30.0)
	assert_eq(float(EnemiesData.ENEMIES["weaver_matron"]["hp"]), 240.0)


func test_legacy_categories_and_stations_are_kept() -> void:
	var order: Array = ItemsData.CATEGORY_ORDER
	assert_eq(order.slice(0, LEGACY_CATEGORY_ORDER.size()), LEGACY_CATEGORY_ORDER, "legacy categories first, same order")
	for cat in ["wand", "armor", "charm", "companion"]:
		assert_true(order.has(cat), "new category %s appended" % cat)
	for st in LEGACY_STATIONS:
		assert_eq(RecipesData.STATIONS.get(st, ""), LEGACY_STATIONS[st], "station %s keeps its name" % st)
	for st in ["furnace", "loom", "kitchen"]:
		assert_true(RecipesData.STATIONS.has(st), "new station " + st)


func test_chapter_one_item_list_matches_the_snapshot() -> void:
	assert_eq(SourcesData.CHAPTER_ONE_ITEMS, LEGACY_ITEMS.keys(), "data/sources.gd CHAPTER_ONE_ITEMS = the legacy ids")


func test_legacy_lookups_behave_as_before() -> void:
	# ItemDB returns the same merged dictionaries for legacy ids (no new default keys leak into them).
	for id in LEGACY_ITEMS:
		var d := ItemDB.item(id)
		var expect: Dictionary = ItemDB.ITEM_DEFAULTS.duplicate()
		expect.merge(LEGACY_ITEMS[id], true)
		expect["id"] = id
		assert_eq(d.keys().size(), expect.keys().size(), id + " item() keys unchanged")
		for k in expect:
			assert_true(d.get(k) == expect[k], "%s item().%s unchanged" % [id, k])
	for rid in LEGACY_RECIPES:
		assert_true(ItemDB.recipe(rid) == LEGACY_RECIPES[rid], rid + " recipe() unchanged")
	for sid in LEGACY_STRUCTURES:
		assert_true(ItemDB.structure(sid) == LEGACY_STRUCTURES[sid], sid + " structure() unchanged")
	for eid in LEGACY_ENEMIES:
		assert_true(ItemDB.enemy(eid) == LEGACY_ENEMIES[eid], eid + " enemy() unchanged")
	assert_eq(ItemDB.all_recipe_ids().slice(0, LEGACY_RECIPES.size()), LEGACY_RECIPES.keys())
	assert_eq(ItemDB.item_tier("stone_axe"), 1)
	assert_eq(ItemDB.item_tier("stone_pickaxe"), 1)
	assert_eq(ItemDB.item_tier("copper_sword"), 2)
	assert_eq(ItemDB.item_tier("wood"), 0)
	assert_eq(ItemDB.buff_family("hearty_stew"), "stamina", "legacy stew belongs to the stamina family by its buff key")
	assert_eq(ItemDB.buff_family("berries"), "")
