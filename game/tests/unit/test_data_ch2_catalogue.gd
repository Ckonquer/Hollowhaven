extends "res://tests/test_case.gd"
## Chapter Two data catalogue (docs/CHAPTER_TWO_SPEC.md 4.2-4.5, MP 5 / 12 / 13 / 16): the binding ids exist with
## complete fields, the balance rules of the master prompt hold, and every recipe / structure / crop / enemy /
## icon cross reference is valid.

const ItemsData := preload("res://data/items.gd")
const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const EnemiesData := preload("res://data/enemies.gd")
const UnlocksData := preload("res://data/unlocks.gd")
const SourcesData := preload("res://data/sources.gd")
const EquipmentData := preload("res://data/equipment.gd")
const MasteryData := preload("res://data/mastery.gd")
const AppearanceData := preload("res://data/appearance.gd")
const IconFactory := preload("res://src/ui/icon_factory.gd")
const PlayerLogic := preload("res://src/player/player_logic.gd")

## Every item id named in spec 4.2 (placeables: one per SPEC_STRUCTURES entry).
const SPEC_ITEMS := ["sunflax", "roseberries", "resin", "iron_ore", "woven_cloth", "copper_bar", "iron_bar", "moon_crystal",
	"moonsteel_bar", "pumpkin", "sugarcap", "moonpetal", "lantern_wax", "candy", "sunflax_seeds", "roseberry_seeds",
	"pumpkin_seeds", "copper_axe", "copper_pickaxe", "ironwood_axe", "ironwood_pickaxe", "moonsteel_axe", "moonsteel_pickaxe",
	"ironwood_sword", "moonsteel_sword", "sparkseed_wand", "padded_hood", "padded_vest", "padded_boots", "copperwood_hood",
	"copperwood_vest", "copperwood_boots", "ironwood_helm", "ironwood_mail", "ironwood_boots", "moonsteel_helm",
	"moonsteel_mail", "moonsteel_boots", "gatherers_charm", "swiftstep_charm", "kindling_charm", "pumpkin_soup",
	"pumpkin_biscuit", "roseberry_tart", "moonpetal_tea", "lanternwake_platter", "comfort_ribbon", "garden_seal",
	"quarry_seal", "manor_seal", "velvet_scrap"]
const SPEC_STRUCTURES := ["wood_stairs", "upper_floor", "wood_railing", "half_wall", "porch_post", "arched_window", "gable_roof",
	"roof_corner", "flower_box", "curtain", "bookshelf", "wardrobe", "vanity_mirror", "kitchen_counter", "furnace", "loom",
	"companion_bed", "companion_perch", "sturdy_planter", "cottage_bench", "pumpkin_lantern", "pumpkin_lights", "bat_bunting",
	"ghost_lantern", "crescent_window", "candy_bowl", "scarecrow", "gothic_trim", "music_box", "expedition_board", "wardlight",
	"miner_lamp", "thread_veil", "lanternwake_table"]
## MP 12 / 13 starting ranges [hp_min, hp_max, dmg_min, dmg_max] (elites / Matron: no MP numbers -> sanity ranges).
const ENEMY_RANGES := {
	"brambleback": [55, 65, 12, 14], "lantern_moth": [30, 40, 8, 10], "hollow_drudge": [55, 70, 14, 16],
	"brood_skitter": [24, 32, 6, 8], "pumpkin_mimic": [65, 85, 12, 15], "patchwalker": [80, 100, 15, 18],
	"velvet_wing": [45, 60, 10, 13], "bellcap_sentry": [70, 90, 13, 17], "borrowed_wisp": [55, 75, 14, 18],
	"count_velour": [340, 420, 10, 22], "borrowed_choir": [480, 620, 10, 22],
	"knotted_elder": [150, 320, 14, 22], "quarry_warden": [200, 360, 14, 24], "crossing_matron": [240, 420, 14, 24],
}
const STRUCTURE_LAYERS := ["decor", "floor", "object", "edge", "roof", "stair"]
const STRUCTURE_SNAPS := ["cell", "floor2", "edge2", "roof2", "stair2"]
const INTERACTS := ["", "storage", "sleep", "farm", "station", "wardrobe", "nook", "board", "music", "face"]
const APPLY_KINDS := ["backpack_40", "backpack_48", "chest_40"]
const SPIDER_WORDS := ["spider", "weaver", "web", "silk", "arachn"]

## MP 16 initial recipes, exactly: rid -> [station, count, ingredients].
const MP16 := {
	"furnace": ["workbench", 1, {"stone": 10, "wood": 4, "copper_ore": 2}],
	"loom": ["workbench", 1, {"wood": 8, "fiber": 6}],
	"vanity_mirror": ["workbench", 1, {"wood": 4, "copper_ore": 2, "stone": 2}],
	"kitchen_counter": ["workbench", 1, {"stone": 8, "wood": 6, "copper_bar": 2}],
	"woven_cloth": ["loom", 2, {"sunflax": 3, "fiber": 2}],
	"copper_bar": ["furnace", 1, {"copper_ore": 2}],
	"iron_bar": ["furnace", 1, {"iron_ore": 2}],
	"moonsteel_bar": ["furnace", 1, {"iron_bar": 2, "moon_crystal": 1, "echo_shard": 1}],
	"lantern_wax": ["workbench", 2, {"resin": 1, "fiber": 1}],
	"comfort_ribbon": ["loom", 1, {"woven_cloth": 2, "berries": 2}],
	"padded_hood": ["", 1, {"woven_cloth": 1, "fiber": 3}],
	"padded_vest": ["", 1, {"woven_cloth": 2, "fiber": 4}],
	"padded_boots": ["", 1, {"woven_cloth": 1, "fiber": 2}],
	"copper_axe": ["", 1, {"wood": 3, "copper_bar": 3, "fiber": 2}],
	"copper_pickaxe": ["", 1, {"wood": 3, "copper_bar": 3, "fiber": 2}],
	"copperwood_hood": ["", 1, {"woven_cloth": 2, "copper_bar": 1}],
	"copperwood_vest": ["", 1, {"woven_cloth": 3, "copper_bar": 2}],
	"copperwood_boots": ["", 1, {"woven_cloth": 2, "copper_bar": 1}],
	"ironwood_sword": ["", 1, {"iron_bar": 3, "wood": 2, "woven_cloth": 1}],
	"ironwood_axe": ["", 1, {"iron_bar": 3, "wood": 3, "resin": 1}],
	"ironwood_pickaxe": ["", 1, {"iron_bar": 3, "wood": 3, "resin": 1}],
	"ironwood_helm": ["", 1, {"iron_bar": 2, "woven_cloth": 2}],
	"ironwood_mail": ["", 1, {"iron_bar": 4, "woven_cloth": 3}],
	"ironwood_boots": ["", 1, {"iron_bar": 2, "woven_cloth": 2}],
	"moonsteel_sword": ["", 1, {"moonsteel_bar": 4, "wood": 2, "echo_shard": 1}],
	"moonsteel_axe": ["", 1, {"moonsteel_bar": 3, "wood": 3, "resin": 1}],
	"moonsteel_pickaxe": ["", 1, {"moonsteel_bar": 3, "wood": 3, "resin": 1}],
	"moonsteel_helm": ["", 1, {"moonsteel_bar": 2, "woven_cloth": 2}],
	"moonsteel_mail": ["", 1, {"moonsteel_bar": 4, "woven_cloth": 3}],
	"moonsteel_boots": ["", 1, {"moonsteel_bar": 2, "woven_cloth": 2}],
	"sparkseed_wand": ["", 1, {"wood": 4, "copper_bar": 2, "glowcap": 2}],
	"gatherers_charm": ["", 1, {"resin": 2, "copper_bar": 2, "fiber": 2}],
	"swiftstep_charm": ["", 1, {"iron_bar": 2, "moonpetal": 2, "woven_cloth": 1}],
	"kindling_charm": ["", 1, {"moonsteel_bar": 1, "glowcap": 2, "woven_cloth": 2}],
	"backpack_40": ["", 0, {"woven_cloth": 4, "copper_bar": 2}],
	"backpack_48": ["", 0, {"woven_cloth": 6, "iron_bar": 2}],
	"chest_upgrade_40": ["", 0, {"wood": 6, "iron_bar": 2}],
	"pumpkin_soup": ["", 1, {"pumpkin": 1, "sweetroot": 1}],
	"pumpkin_biscuit": ["", 2, {"pumpkin": 1, "sugarcap": 1}],
	"roseberry_tart": ["", 1, {"roseberries": 2, "sugarcap": 1}],
	"moonpetal_tea": ["", 1, {"moonpetal": 2, "sweetroot": 1}],
	"lanternwake_platter": ["kitchen", 1, {"pumpkin": 1, "roseberries": 2, "sweetroot": 1}],
	"music_box": ["", 1, {"wood": 6, "copper_bar": 2, "echo_shard": 1}],
}

var _arachno_before: Variant = false


func before_each() -> void:
	fresh_state()
	_arachno_before = Settings.get_value("arachnophobia")
	Settings.values["arachnophobia"] = false


func after_each() -> void:
	Settings.values["arachnophobia"] = _arachno_before


func _new_ids(table: Dictionary, legacy_count: int) -> Array:
	return table.keys().slice(legacy_count)


# --- items -----------------------------------------------------------------------------------------------------

func test_spec_item_ids_exist_with_complete_fields() -> void:
	var ids: Array = SPEC_ITEMS.duplicate()
	ids.append_array(SPEC_STRUCTURES)
	for id in ids:
		assert_true(ItemsData.ITEMS.has(id), "spec item %s exists" % id)
		if not ItemsData.ITEMS.has(id):
			continue
		var raw: Dictionary = ItemsData.ITEMS[id]
		for k in ["name", "desc", "cat", "stack", "icon", "color"]:
			assert_true(raw.has(k), "%s declares %s" % [id, k])
		assert_true(raw["color"] is Color, id + " colour")
		assert_true(ItemsData.CATEGORY_ORDER.has(raw["cat"]), id + " category sortable")
		assert_true(IconFactory.has_drawing(String(raw["icon"])), "%s icon '%s' has a drawing" % [id, raw["icon"]])
	assert_eq(ItemDB.category("sparkseed_wand"), "wand")
	assert_eq(ItemDB.category("padded_vest"), "armor")
	assert_eq(ItemDB.category("gatherers_charm"), "charm")
	for food in ["roseberries", "pumpkin", "candy"]:
		assert_eq(ItemDB.category(food), "food", food + " is food (spec 4.2)")


func test_tools_are_tiered_gathering_upgrades_not_weapons() -> void:
	var power_by_tier := {1: 1.0, 2: 1.5, 3: 2.0, 4: 2.5}
	var sword := float(ItemDB.item("copper_sword")["damage"])
	for id in ItemDB.items_in_category("tool"):
		var d := ItemDB.item(id)
		var tier := ItemDB.item_tier(id)
		assert_true(tier >= 1 and tier <= 4, id + " tier")
		assert_almost(float(d["power"]), float(power_by_tier[tier]), 0.001, id + " gathering power follows its tier")
		assert_true(float(d["damage"]) < sword, "%s (%.0f) never out-hits the Copper Sword" % [id, float(d["damage"])])
		assert_eq(int(d["stack"]), 1)
	assert_eq(float(ItemDB.item("stone_axe")["damage"]), 9.0, "legacy stone tools unchanged")
	# auto-selection keeps preferring swords over any harvesting tool, and never picks the wand
	GameState.give_item("moonsteel_pickaxe", 1)
	GameState.give_item("moonsteel_axe", 1)
	GameState.give_item("sparkseed_wand", 1)
	assert_true(GameState.best_weapon() in ["moonsteel_pickaxe", "moonsteel_axe"], "without a sword the best tool swings (legacy rule), never the wand")
	GameState.give_item("copper_sword", 1)
	assert_eq(GameState.best_weapon(), "copper_sword", "even the Copper Sword beats moonsteel tools")
	assert_eq(GameState.best_tool("pickaxe"), "moonsteel_pickaxe", "best pickaxe by power")
	assert_eq(ItemDB.best_tool_tier("pickaxe"), 4)
	assert_eq(ItemDB.best_tool_tier("hoe"), 0)


func test_swords_and_wand_follow_the_master_prompt() -> void:
	assert_eq(float(ItemDB.item("copper_sword")["damage"]), 18.0)
	assert_eq(float(ItemDB.item("ironwood_sword")["damage"]), 25.0)
	assert_eq(float(ItemDB.item("moonsteel_sword")["damage"]), 34.0)
	assert_eq(ItemDB.item_tier("ironwood_sword"), 3)
	assert_eq(ItemDB.item_tier("moonsteel_sword"), 4)
	var w := ItemDB.wand("sparkseed_wand")
	assert_false(w.is_empty(), "the wand is ranged")
	assert_true(float(w["range"]) > 4.0 and float(w["range"]) <= 20.0, "finite range")
	assert_true(float(w["stamina"]) > 0.0, "shares the stamina pool")
	assert_true(float(w["cooldown"]) > 0.0)
	assert_true(w["projectile"] is Dictionary and float(w["projectile"]["speed"]) > 0.0, "readable projectile")
	var wand_dps := float(w["damage"]) / float(w["cooldown"])
	var melee_dps := float(ItemDB.item("copper_sword")["damage"]) / PlayerLogic.SWING_TIME
	assert_true(wand_dps < melee_dps * 0.6, "wand sustained damage (%.1f/s) clearly below the same-tier sword (%.1f/s)" % [wand_dps, melee_dps])
	assert_eq(ItemDB.item_tier("sparkseed_wand"), ItemDB.item_tier("copper_sword"), "accessible tier")
	assert_eq(ItemDB.wand("copper_sword"), {}, "melee weapons are not wands")
	for rid in [RecipesData.RECIPES["sparkseed_wand"]]:
		for ing in rid["ingredients"]:
			assert_false(ItemDB.is_quest_item(ing), "no rare ammunition or key item")


func test_armor_pieces_split_the_set_totals_transparently() -> void:
	var totals := {"padded": 0.06, "copperwood": 0.12, "ironwood": 0.2, "moonsteel": 0.26}
	for set_id in totals:
		var s := ItemDB.armor_set(set_id)
		assert_almost(float(s["total"]), float(totals[set_id]), 0.0001, set_id + " full-set total (MP 5.1)")
		var sum := 0.0
		for slot in EquipmentData.ARMOR_SLOTS:
			var piece: String = s["pieces"][slot]
			var e := ItemDB.equipment(piece)
			assert_eq(String(e["slot"]), slot, piece + " slot")
			assert_eq(String(e["set"]), set_id, piece + " set")
			assert_eq(int(e["tier"]), int(s["tier"]), piece + " tier")
			assert_almost(float(e["reduction"]), float(totals[set_id]) * float(EquipmentData.PIECE_SHARE[slot]), 0.0001, piece + " share")
			assert_true(ItemDB.display_desc(piece).contains("%d%%" % roundi(float(totals[set_id]) * 100.0)), piece + " description states the set total")
			sum += float(e["reduction"])
		assert_almost(sum, float(totals[set_id]), 0.0001, set_id + " pieces add up to the total")
	var armor_count := 0
	for id in ItemDB.items_in_category("armor"):
		armor_count += 1
		assert_ne(ItemDB.equip_slot(id), "", id + " equips somewhere")
	assert_eq(armor_count, 12)
	assert_true(0.26 < EquipmentData.REDUCTION_CAP, "best armor stays under the cap on its own")


func test_charms_offer_capped_choices() -> void:
	var effects_seen := {}
	for id in ItemDB.items_in_category("charm"):
		assert_eq(ItemDB.equip_slot(id), "charm")
		var e := ItemDB.equipment(id)
		assert_false((e["effects"] as Dictionary).is_empty(), id + " has an effect")
		for k in e["effects"]:
			assert_true(EquipmentData.EFFECTS.has(k), "%s effect %s is defined" % [id, k])
			var v := float(e["effects"][k])
			assert_true(v > 0.0 and v <= float(EquipmentData.EFFECTS[k]["cap"]), "%s %s within its cap" % [id, k])
			effects_seen[k] = true
	for k in ["gather", "stamina_save", "heal_received", "lantern_radius"]:
		assert_true(effects_seen.has(k), "a charm offers " + k)
	assert_eq(ItemDB.equipment("wood"), {}, "non-equipment returns {}")
	assert_eq(ItemDB.equip_slot("lantern"), "", "the lantern is not wearable equipment")


func test_food_heals_and_buff_families() -> void:
	var heals := {"pumpkin_soup": 40.0, "roseberry_tart": 30.0}
	for id in heals:
		assert_eq(float(ItemDB.item(id)["heal"]), float(heals[id]), id + " heal (MP 16)")
	assert_true(float(ItemDB.item("lanternwake_platter")["heal"]) >= 60.0, "the platter is a strong restorative meal")
	assert_true(float(ItemDB.item("moonpetal_tea")["heal"]) < 20.0, "the tea is a small heal")
	assert_eq(int(RecipesData.RECIPES["pumpkin_biscuit"]["count"]), 2, "two small snacks")
	for id in ItemDB.items_in_category("food"):
		var d := ItemDB.item(id)
		assert_true(float(d["heal"]) > 0.0, id + " heals")
		if d.has("buff"):
			var fam := ItemDB.buff_family(id)
			assert_true(ItemsData.BUFF_FAMILIES.has(fam), "%s buff family '%s' is defined" % [id, fam])
			var effect := String(ItemsData.BUFF_FAMILIES[fam]["effect"])
			assert_true((d["buff"] as Dictionary).has(effect), "%s buff uses its family effect %s" % [id, effect])
	assert_eq(ItemDB.buff_family("roseberry_tart"), ItemDB.buff_family("hearty_stew"), "tart and stew share a family (no stacking)")
	assert_eq(ItemDB.buff_family("moonpetal_tea"), "steady")
	assert_eq(ItemDB.buff_family("pumpkin_soup"), "")


func test_key_items_and_companion_gear() -> void:
	for id in ["garden_seal", "quarry_seal", "manor_seal", "velvet_scrap"]:
		assert_true(ItemDB.is_quest_item(id), id + " goes to the key pouch")
		assert_eq(ItemDB.stack_max(id), 1)
	assert_eq(ItemDB.category("comfort_ribbon"), "companion")
	assert_true(bool(ItemDB.item("comfort_ribbon").get("companion_gear", false)))


func test_arachnophobia_alternatives() -> void:
	assert_eq(ItemDB.display_name("thread_veil"), "Thread Veil")
	assert_eq(ItemDB.enemy_display_name("brood_skitter"), "Brood Skitter")
	assert_eq(ItemDB.structure_display_name("thread_veil"), "Thread Veil")
	assert_true(ItemDB.enemy_display_desc("brood_skitter").contains("skittering"))
	assert_eq(ItemDB.structure_display_name("wardrobe"), "Wardrobe")
	Settings.values["arachnophobia"] = true
	assert_eq(ItemDB.structure_display_name("thread_veil"), "Pale Veil Drape")
	assert_true(ItemDB.enemy_display_desc("brood_skitter").contains("seed"), "alt description")
	assert_eq(ItemDB.enemy_display_desc("brambling"), String(ItemDB.enemy("brambling")["desc"]), "no alt -> normal text")
	assert_eq(ItemDB.display_name("thread_veil"), "Pale Veil Drape")
	assert_eq(ItemDB.enemy_display_name("brood_skitter"), "Pale Sprout")
	assert_eq(ItemDB.enemy_display_name("crossing_matron"), "The Hollow Mother")
	for id in ItemsData.ITEMS:
		var txt := (ItemDB.display_name(id) + " " + ItemDB.display_desc(id)).to_lower()
		for w in SPIDER_WORDS:
			assert_false(txt.contains(w), "%s shows '%s' with arachnophobia on" % [id, w])
	for eid in ["brood_skitter", "crossing_matron"]:
		var e := ItemDB.enemy(eid)
		assert_true(e.has("alt_sound") and e.has("alt_desc"), eid + " has alt sound and text")
		assert_false(String(e["alt_desc"]).to_lower().contains("spider") or String(e["alt_desc"]).to_lower().contains("web"))
		for a in e["attacks"]:
			var tell := String(a.get("alt_tell", a["tell"])).to_lower()
			for w in SPIDER_WORDS:
				assert_false(tell.contains(w) or tell.contains("thread"), "%s %s alt tell avoids '%s'" % [eid, a["id"], w])
	assert_eq(String(StructuresData.STRUCTURES["thread_veil"]["alt_name"]), "Pale Veil Drape")


# --- recipes ---------------------------------------------------------------------------------------------------

func test_every_recipe_references_real_things() -> void:
	var all := {}
	for rid in RecipesData.RECIPES:
		all[rid] = RecipesData.RECIPES[rid]
	for rid in RecipesData.SPECIAL_RECIPES:
		assert_false(all.has(rid), rid + " id is unique across RECIPES and SPECIAL_RECIPES")
		all[rid] = RecipesData.SPECIAL_RECIPES[rid]
	var used_flags := {}
	for rid in all:
		var r: Dictionary = all[rid]
		assert_true(RecipesData.STATIONS.has(r["station"]), rid + " station exists")
		var flag := String(r["unlock"])
		if flag != "":
			used_flags[flag] = true
			assert_true(UnlocksData.UNLOCK_FLAGS.has(flag), "%s unlock flag %s is declared in data/unlocks.gd" % [rid, flag])
		for ing in r["ingredients"]:
			assert_true(ItemDB.has_item(ing), "%s ingredient %s exists" % [rid, ing])
			assert_true(int(r["ingredients"][ing]) > 0)
			assert_false(ItemDB.is_quest_item(ing), rid + " never consumes a key item")
		var kind := ItemDB.recipe_kind(rid)
		if RecipesData.SPECIAL_RECIPES.has(rid):
			assert_true(kind == "apply" or kind == "pattern", rid + " special recipe applies or grants a pattern")
			if kind == "apply":
				assert_true(APPLY_KINDS.has(r["apply"]), rid + " apply kind")
			else:
				var pat := ItemDB.pattern(String(r["pattern"]))
				assert_false(pat.is_empty(), rid + " grants a real pattern")
				assert_eq(String(pat.get("recipe", "")), rid, rid + " pattern links back to its recipe")
				assert_eq(String(pat.get("flag", "")), flag, rid + " pattern and recipe share the unlock flag")
		else:
			assert_true(ItemDB.has_item(r["result"]), rid + " result exists")
			assert_true(int(r["count"]) >= 1 and int(r["count"]) <= ItemDB.stack_max(r["result"]), rid + " count")
		if r.has("time"):
			assert_eq(String(r["station"]), "furnace", rid + " timed recipes are furnace jobs")
			assert_true(float(r["time"]) >= 15.0 and float(r["time"]) <= 45.0, rid + " short job (15-45 s)")
			assert_eq(kind, "timed")
		elif String(r["station"]) == "furnace":
			fail(rid + " furnace recipe without a time")
		if r.has("mastery"):
			for track in r["mastery"]:
				assert_true(MasteryData.TRACKS.has(track), rid + " mastery track")
				assert_true(int(r["mastery"][track]) >= 1 and int(r["mastery"][track]) <= MasteryData.MAX_RANK, rid + " mastery rank")
			assert_false(SourcesData.STORY_REQUIRED.has(String(r["result"])), rid + " mastery gate is never story-critical")
	for flag in UnlocksData.UNLOCK_FLAGS:
		assert_true(used_flags.has(flag), "unlock flag %s is used by a recipe" % flag)
		assert_true(String(UnlocksData.UNLOCK_FLAGS[flag]).length() > 10, flag + " says who sets it")
	assert_eq(ItemDB.every_recipe_id().size(), all.size())
	assert_eq(ItemDB.recipe_kind("stone_axe"), "item")
	assert_eq(ItemDB.recipe_kind("nope"), "")
	assert_eq(ItemDB.station_structure("furnace"), "furnace")
	assert_eq(ItemDB.station_structure("kitchen"), "kitchen_counter")
	assert_eq(ItemDB.station_structure("hand"), "")


func test_master_prompt_recipe_quantities() -> void:
	for rid in MP16:
		var r := ItemDB.recipe(rid)
		assert_false(r.is_empty(), rid + " exists")
		if r.is_empty():
			continue
		var spec: Array = MP16[rid]
		if String(spec[0]) != "":
			assert_eq(String(r["station"]), String(spec[0]), rid + " station (MP 16)")
		if int(spec[1]) > 0:
			assert_eq(int(r["count"]), int(spec[1]), rid + " output count (MP 16)")
		assert_eq(r["ingredients"], spec[2], rid + " ingredients (MP 16)")
	assert_eq(String(ItemDB.recipe("backpack_40")["apply"]), "backpack_40")
	assert_eq(String(ItemDB.recipe("backpack_48")["apply"]), "backpack_48")
	assert_eq(String(ItemDB.recipe("chest_upgrade_40")["apply"]), "chest_40")
	assert_eq(int(ItemDB.recipe("backpack_48")["requires_capacity"]), 40, "40 -> 48 needs the first upgrade")


func test_every_structure_has_an_item_and_a_recipe() -> void:
	var produced := {}
	for rid in RecipesData.RECIPES:
		produced[String(RecipesData.RECIPES[rid]["result"])] = true
	for sid in StructuresData.STRUCTURES:
		var s: Dictionary = StructuresData.STRUCTURES[sid]
		var item: String = s["item"]
		assert_true(ItemDB.has_item(item), sid + " refund item")
		assert_eq(String(ItemDB.item(item)["place"]), sid, sid + " item places it")
		assert_eq(ItemDB.category(item), "placeable")
		if item != "haven_banner":   # the banner is the Chapter One ending reward
			assert_true(produced.has(item), sid + " has a recipe")
	for sid in SPEC_STRUCTURES:
		assert_true(StructuresData.STRUCTURES.has(sid), "spec structure %s exists" % sid)
		assert_true(produced.has(sid), sid + " is craftable")


func test_new_structure_fields() -> void:
	for sid in _new_ids(StructuresData.STRUCTURES, 19):
		var s: Dictionary = StructuresData.STRUCTURES[sid]
		assert_true(STRUCTURE_LAYERS.has(s["layer"]), sid + " layer")
		assert_true(STRUCTURE_SNAPS.has(s["snap"]), sid + " snap")
		assert_true(INTERACTS.has(s["interact"]), sid + " interact")
		assert_true(s["size"] is Vector2i and (s["size"] as Vector2i).x >= 1 and (s["size"] as Vector2i).y >= 1, sid + " size")
		assert_true(float(s["height"]) > 0.0 and s["solid"] is bool, sid + " height / solid")
		for flag_key in ["level_ok", "stairs", "support", "tintable", "upper"]:
			if s.has(flag_key):
				assert_true(s[flag_key] is bool, "%s %s is a bool" % [sid, flag_key])
		if s["interact"] == "station":
			assert_true(RecipesData.STATIONS.has(String(s["station"])), sid + " station")
			assert_eq(ItemDB.station_structure(String(s["station"])), sid, sid + " is the station's structure")
		if s.has("light"):
			assert_true(s["light"]["color"] is Color and float(s["light"]["range"]) > 0.0, sid + " light")
		if s.has("mount"):
			assert_eq(String(s["mount"]), "wall")
			assert_eq(String(s["snap"]), "cell", sid + " wall-mounted decor sits in a cell")
			assert_false(bool(s["solid"]), sid + " thin wall decor never blocks movement")
	var stairs: Dictionary = StructuresData.STRUCTURES["wood_stairs"]
	assert_true(bool(stairs["stairs"]))
	assert_eq(stairs["size"], Vector2i(2, 4), "a stairwell is exactly two floor tiles")
	assert_true(bool(StructuresData.STRUCTURES["upper_floor"]["upper"]))
	assert_true(bool(StructuresData.STRUCTURES["porch_post"]["support"]))
	assert_eq(String(StructuresData.STRUCTURES["pumpkin_lantern"]["interact"]), "face")
	assert_eq(StructuresData.STRUCTURES["pumpkin_lantern"]["faces"], StructuresData.PUMPKIN_FACES)
	assert_eq(StructuresData.PUMPKIN_FACES, ["friendly", "sleepy", "toothy", "cat", "moon", "ghost"], "MP 9 faces")
	assert_eq(String(StructuresData.STRUCTURES["wardrobe"]["interact"]), "wardrobe")
	assert_eq(String(StructuresData.STRUCTURES["vanity_mirror"]["interact"]), "wardrobe")
	assert_eq(String(StructuresData.STRUCTURES["companion_bed"]["interact"]), "nook")
	assert_eq(String(StructuresData.STRUCTURES["expedition_board"]["interact"]), "board")
	assert_eq(String(StructuresData.STRUCTURES["music_box"]["interact"]), "music")
	assert_eq(String(StructuresData.STRUCTURES["sturdy_planter"]["interact"]), "farm")
	assert_true(int(StructuresData.STRUCTURES["furnace"]["queue"]) >= 1, "finite furnace queue")


func test_basic_building_is_known_early_and_costs_like_legacy_pieces() -> void:
	# MP 3 / 16: starter structural essentials are unlocked early; costs proportional to the legacy wood pieces.
	var essentials := ["wood_stairs", "upper_floor", "wood_railing", "half_wall", "porch_post", "arched_window",
		"gable_roof", "roof_corner", "wardrobe", "vanity_mirror", "furnace", "bookshelf", "flower_box", "cottage_bench",
		"companion_bed", "companion_perch"]
	var basics := ["wood", "stone", "fiber", "copper_ore"]
	for rid in essentials:
		var r := ItemDB.recipe(rid)
		assert_eq(String(r["unlock"]), "", rid + " known from the start")
		assert_false(r.has("mastery"), rid + " no mastery gate")
		assert_eq(String(r["station"]), "workbench", rid + " at the workbench")
		var total := 0
		for ing in r["ingredients"]:
			assert_true(basics.has(ing), "%s needs only basic Chapter One materials (%s)" % [rid, ing])
			total += int(r["ingredients"][ing])
		assert_true(total <= 16, "%s costs %d, in line with legacy pieces" % [rid, total])
	# per-tile structural costs stay within 2x of the legacy wall / floor / roof
	for pair in [["wood_railing", 2], ["half_wall", 3], ["arched_window", 4], ["gable_roof", 4], ["roof_corner", 4], ["upper_floor", 4]]:
		var r2 := ItemDB.recipe(String(pair[0]))
		var t := 0
		for ing in r2["ingredients"]:
			t += int(r2["ingredients"][ing])
		assert_true(float(t) / float(r2["count"]) <= float(pair[1]) * 2.0, "%s is not ten times a legacy piece" % pair[0])


func test_ornate_and_halloween_costs_follow_the_material_rules() -> void:
	for rid in ["pumpkin_lantern", "pumpkin_lights", "ghost_lantern"]:
		var ings: Dictionary = ItemDB.recipe(rid)["ingredients"]
		assert_true(ings.has("lantern_wax"), rid + " uses lantern wax")
		for ing in ings:
			assert_true(ing in ["pumpkin", "lantern_wax", "wood", "fiber", "woven_cloth"], "%s uses %s" % [rid, ing])
	for rid in ["crescent_window", "gothic_trim"]:
		var ings2: Dictionary = ItemDB.recipe(rid)["ingredients"]
		assert_true(int(ings2.get("iron_bar", 0)) + int(ings2.get("moonsteel_bar", 0)) in [1, 2], rid + " uses a small amount of iron / moonsteel")
	for rid in ["curtain", "bat_bunting", "thread_veil"]:
		assert_true((ItemDB.recipe(rid)["ingredients"] as Dictionary).has("woven_cloth"), rid + " is a cloth furnishing")


# --- crops ---------------------------------------------------------------------------------------------------

func test_new_crops_grow_in_the_target_window_and_return_seeds() -> void:
	var minutes := {"sunflax": 420.0, "roseberry": 480.0, "pumpkin": 600.0}
	for cid in minutes:
		var c := ItemDB.crop(cid)
		assert_false(c.is_empty(), cid + " crop exists")
		assert_eq(float(c["grow_minutes"]), float(minutes[cid]), cid + " growth (spec 4.4)")
		assert_eq(int(c["stages"]), 4)
		var seed: String = c["seed"]
		assert_eq(ItemDB.category(seed), "seed")
		assert_eq(String(ItemDB.item(seed)["crop"]), cid)
		var ret: Array = c["yield"][seed]
		assert_true(int(ret[0]) >= 1, cid + " every harvest returns at least one seed (sustainable)")
		assert_true(float(c["grow_minutes"]) >= 300.0 and float(c["grow_minutes"]) <= 600.0, cid + " 5-10 active minutes")


# --- enemies -------------------------------------------------------------------------------------------------

func test_new_enemies_follow_the_master_prompt_ranges() -> void:
	for eid in ENEMY_RANGES:
		var e := ItemDB.enemy(eid)
		assert_false(e.is_empty(), eid + " exists")
		if e.is_empty():
			continue
		var rg: Array = ENEMY_RANGES[eid]
		assert_true(float(e["hp"]) >= float(rg[0]) and float(e["hp"]) <= float(rg[1]), "%s hp %.0f in [%d, %d]" % [eid, float(e["hp"]), rg[0], rg[1]])
		assert_true(float(e["damage"]) >= float(rg[2]) and float(e["damage"]) <= float(rg[3]), "%s damage %.0f in [%d, %d]" % [eid, float(e["damage"]), rg[2], rg[3]])
		assert_true(float(e["telegraph"]) >= 0.5 and float(e["recover"]) > 0.0 and float(e["cooldown"]) > 0.0, eid + " telegraph / recover / cooldown")
		assert_true(EnemiesData.AREA_IDS.has(e["area"]), eid + " area")
		assert_true((e["areas"] as Array).has(e["area"]), eid + " areas include its home area")
		for a in e["areas"]:
			assert_true(EnemiesData.AREA_IDS.has(a), "%s area %s" % [eid, a])
		assert_true(String(e["desc"]) != "", eid + " desc")
		assert_true(e.has("alt_name"), eid + " alt_name key")
		assert_true(Audio.has_sound(String(e["sound"])), eid + " is audible with today's sound set")
		if e.has("alt_sound"):
			assert_true(Audio.has_sound(String(e["alt_sound"])), eid + " arachnophobia sound resolves")
		assert_true(String(e.get("voice", "")) != "", eid + " names its planned dedicated voice")
		assert_false((e["attacks"] as Array).is_empty(), eid + " describes its attacks")
		for a in e["attacks"]:
			assert_true(float(a["telegraph"]) >= 0.5, "%s %s readable wind-up" % [eid, a["id"]])
			assert_true(String(a["tell"]).length() > 20, "%s %s has a visual tell (works with sound muted)" % [eid, a["id"]])
		for drop in e.get("drops", []):
			assert_true(ItemDB.has_item(drop["item"]), eid + " drop exists")
			assert_false(ItemDB.is_quest_item(drop["item"]), eid + " never drops key items")
			assert_true(float(drop["chance"]) > 0.0 and float(drop["chance"]) <= 1.0)
		if bool(e.get("boss", false)):
			assert_eq((e["drops"] as Array).size(), 0, eid + " boss rewards come from the ledger, not drops")
	for eid in ["knotted_elder", "quarry_warden"]:
		assert_true(bool(ItemDB.enemy(eid).get("elite", false)), eid + " elite")
	for eid in ["count_velour", "crossing_matron", "borrowed_choir"]:
		assert_true(bool(ItemDB.enemy(eid).get("boss", false)), eid + " boss")
	assert_eq(String(ItemDB.enemy("brood_skitter")["alt_name"]), "Pale Sprout")
	assert_eq(String(ItemDB.enemy("crossing_matron")["alt_name"]), "The Hollow Mother")
	assert_true(int(ItemDB.enemy("brood_skitter")["max_group"]) <= 2, "max two skitters in a teaching encounter")
	var clod: Dictionary = ItemDB.enemy("patchwalker")["attacks"][1]
	assert_true(float(clod["slow_immunity"]) > float(clod["slow_seconds"]), "the patchwalker slow cannot chain")


## Integration R83-R85: enemy data agrees with the runtime rules and with the real ids it names.
func test_enemy_data_matches_runtime_rules_and_real_ids() -> void:
	const Base := preload("res://src/enemies/enemy_base.gd")
	const C1x := preload("res://data/c1x_layout.gd")
	# R83: the Brood Skitter's leap is a committed attack; its data wind-up is the enforced 1.0 s floor (what
	# players get and what bestiary / tells read). Only the legacy Brambling keeps its pinned 0.7 s.
	assert_almost(float(EnemiesData.ENEMIES["brambling"]["telegraph"]), 0.7, 0.001, "legacy Brambling unchanged")
	var sk: Dictionary = EnemiesData.ENEMIES["brood_skitter"]
	assert_almost(float(sk["telegraph"]), Base.MIN_COMMITTED_TELEGRAPH, 0.001, "skitter base telegraph = the floor")
	for a in sk["attacks"]:
		assert_true(float(a["telegraph"]) >= Base.MIN_COMMITTED_TELEGRAPH, "skitter %s wind-up >= the enforced floor" % a["id"])
	assert_almost(float(sk["attacks"][0]["telegraph"]), 1.0, 0.001, "leap 1.0 s")
	# R84: zone ids are the real ones (Bramblewatch's zone is c1x_bramblewatch); no Lantern Moth lives in the annex.
	for eid in ["brambleback", "knotted_elder"]:
		assert_eq(EnemiesData.ENEMIES[eid]["zones"], [C1x.BRAMBLEWATCH_ZONE], "%s zone is the real Bramblewatch zone id" % eid)
	var moth: Dictionary = EnemiesData.ENEMIES["lantern_moth"]
	assert_false((moth["areas"] as Array).has("tobin_annex"), "no annex moth")
	assert_false((moth["zones"] as Array).has("ta_lockers"), "no annex moth zone")
	assert_eq(moth["areas"], ["surface"])
	# R85: the Quarry Warden's fallback arena matches the quarry (which passes 10 m itself).
	assert_almost(float(EnemiesData.ENEMIES["quarry_warden"]["arena_radius"]), 10.0, 0.001, "warden fallback arena 10 m")


## Integration pass 2 (P20 / P22): the boss rows describe what the fights really do (descriptive data; the rules
## files stay the source of truth for timings, the bosses read only the damage of each row).
func test_boss_rows_describe_their_rules() -> void:
	const ChoirRules := preload("res://src/enemies/choir/choir_rules.gd")
	const CrossingRules := preload("res://src/enemies/crossing/crossing_rules.gd")
	const Deep := preload("res://data/works_layout_deep.gd")
	# P22: the Borrowed Choir - the vault's radius, each warning = the rules' Standard value, strikes get their row.
	var ch: Dictionary = EnemiesData.ENEMIES["borrowed_choir"]
	assert_almost(float(ch["arena_radius"]), float(Deep.VAULT["radius"]), 0.001, "Choir arena_radius = the vault (12.4)")
	var want := {"false_welcome": float(ChoirRules.T_SWEEP_TELE[1]), "rings": float(ChoirRules.T_RING_TELE[1]),
		"strikes": float(ChoirRules.T_STRIKE_DELAY[1]), "kept_flame": float(ChoirRules.T_HUSH_TELE[1])}
	var rows := {}
	for a in ch["attacks"]:
		rows[String(a["id"])] = a
	for id in want:
		assert_true(rows.has(id), "Choir row %s" % id)
		if rows.has(id):
			assert_almost(float(rows[id]["telegraph"]), float(want[id]), 0.001, "Choir %s warning = choir_rules Standard" % id)
	if rows.has("strikes"):
		var st: Dictionary = rows["strikes"]
		assert_eq(String(st["kind"]), "zone", "strike zones are their own kind")
		assert_almost(float(st["damage"]), 16.0, 0.001, "strike damage (as before, when they read the rings row)")
		assert_almost(float(st["radius"]), float(ChoirRules.STRIKE_RADIUS), 0.001, "marked radius = rules radius")
		assert_eq(String(st["tell"]), "Short delayed strike zones are marked on the floor; step out before they chime.")
	# P20: the Crossing Matron's delayed pounce - the Standard warning, a tell that names both final cues, an
	# arachnophobia tell without silk / spider words, and the "burned twice" floor in the bestiary text.
	var mt: Dictionary = EnemiesData.ENEMIES["crossing_matron"]
	var dp: Dictionary = {}
	var pn: Dictionary = {}
	for a in mt["attacks"]:
		if String(a["id"]) == "delayed_pounce":
			dp = a
		elif String(a["id"]) == "pounce":
			pn = a
	assert_almost(float(dp["telegraph"]), float(CrossingRules.T_DELAYED_TELE[1]), 0.001, "delayed pounce = rules Standard 1.9 s")
	assert_almost(float(pn["telegraph"]), float(CrossingRules.T_POUNCE_TELE[1]), 0.001, "pounce = rules Standard 1.3 s")
	assert_true(String(dp["tell"]).contains("double ring") and String(dp["tell"]).contains("rattle") and String(dp["tell"]).contains("strand"))
	var alt := String(dp["alt_tell"]).to_lower()
	assert_true(alt.contains("whisper") and alt.contains("pale root"), "alt tell: whisper + pale root")
	for word in ["silk", "spider", "web", "strand", "thread", "rattle"]:
		assert_false(alt.contains(word), "arachnophobia tell avoids '%s'" % word)
	# R3-06: the rules need one exposure per phase (three), so the bestiary must not say "twice".
	var burned := "burned her three times, once in each phase"
	assert_true(String(mt["desc"]).contains(burned) and String(mt["alt_desc"]).contains(burned), "desc / alt_desc: " + burned)
	assert_false(String(mt["desc"]).contains("twice") or String(mt["alt_desc"]).contains("twice"), "no stale 'twice'")
	assert_eq(CrossingRules.EXPOSURES_TARGET, 3, "the wording matches the rules' exposure count")
	assert_eq(CrossingRules.HP_FLOOR.size(), 3, "one exposure floor per phase")


# --- icons ---------------------------------------------------------------------------------------------------

func test_every_icon_id_has_a_real_drawing() -> void:
	var fallback := IconFactory.render("definitely_not_an_icon", Color.WHITE, 48).get_data()
	var seen := {}
	for id in ItemsData.ITEMS:
		var icon := String(ItemsData.ITEMS[id]["icon"])
		assert_true(IconFactory.has_drawing(icon), "%s icon %s" % [id, icon])
		if seen.has(icon):
			continue
		seen[icon] = true
		assert_ne(IconFactory.render(icon, ItemDB.item(id)["color"], 48).get_data(), fallback, icon + " is not the fallback")
	for icon in IconFactory.ITEM_ICONS:
		assert_true(seen.has(icon), "ITEM_ICONS %s is used by an item" % icon)
