extends "res://tests/test_case.gd"
## Chapter Two crafting (MP 3 / 5.4 / 16, spec 4.3 / 9): every station recipe crafts transactionally, special
## recipes (backpack upgrades, patterns, dyes), crafting from nearby chests as ONE transaction with rollback,
## backpack 32 -> 40 -> 48 without truncation, seasonal dishes and the festival table.

const Crafting := preload("res://src/crafting/crafting.gd")
const Furnace := preload("res://src/crafting/furnace.gd")

const ALL_STATIONS := ["hand", "workbench", "campfire", "furnace", "loom", "kitchen"]

var _crafted: Array = []


func before_each() -> void:
	fresh_state()
	_crafted = []
	if not Events.crafted.is_connected(_on_crafted):
		Events.crafted.connect(_on_crafted)


func after_each() -> void:
	if Events.crafted.is_connected(_on_crafted):
		Events.crafted.disconnect(_on_crafted)
	Crafting.set_use_chests(false)


func _on_crafted(recipe_id: String, item_id: String, count: int) -> void:
	_crafted.append([recipe_id, item_id, count])


func _unlock(r: Dictionary) -> void:
	var f := String(r.get("unlock", ""))
	if f != "":
		GameState.set_flag(f, true)
	var gate: Variant = r.get("mastery", null)
	if gate is Dictionary:
		for track in gate:
			GameState.mastery[String(track)] = int(ItemDB.mastery_tables()["rank_xp"][int(gate[track])])


func _give_all(ings: Dictionary, mult: int = 1) -> void:
	for id in ings:
		GameState.give_item(String(id), int(ings[id]) * mult)


func _chest(pos: Vector3, area: String = "surface") -> String:
	return GameState.add_structure("storage_chest", pos, 0, area)


func _fill_bag_with_junk(leave_free: int = 0) -> void:
	var inv = GameState.inventory
	for i in inv.size:
		inv.set_slot(i, {"id": "berries", "count": 50} if i >= leave_free else null)


# --- Every station recipe ------------------------------------------------------------------------------

## Every instant recipe of the new stations (loom, kitchen) and every Chapter Two recipe of the old ones crafts
## exactly once: ingredients consumed exactly, result added exactly, one Events.crafted; with one ingredient
## short nothing changes; with a full backpack nothing changes.
func test_every_station_recipe_crafts_transactionally() -> void:
	var checked := 0
	for rid in ItemDB.all_recipe_ids():
		var r := ItemDB.recipe(rid)
		if ItemDB.recipe_kind(rid) != "item":
			continue
		fresh_state()
		_crafted = []
		_unlock(r)
		var ings: Dictionary = r["ingredients"]
		_give_all(ings)
		var result := String(r["result"])
		var before_result := GameState.count_item(result)
		assert_true(Crafting.craft(rid, ALL_STATIONS), "%s crafts: %s" % [rid, Crafting.last_reason])
		for id in ings:
			if String(id) != result:
				assert_eq(GameState.count_item(String(id)), 0, "%s consumed all %s" % [rid, id])
		assert_eq(GameState.count_item(result), before_result + int(r.get("count", 1)) - (int(ings.get(result, 0))), rid + " result count")
		assert_eq(_crafted.size(), 1, rid + " crafted emitted once")
		# One ingredient short: refused, nothing changes.
		var first: String = String(ings.keys()[0])
		_give_all(ings)
		GameState.take_item(first, 1)
		var snap: Array = GameState.inventory.to_array()
		assert_false(Crafting.craft(rid, ALL_STATIONS), rid + " refused when short")
		assert_eq(GameState.inventory.to_array(), snap, rid + " short: inventory untouched")
		checked += 1
	assert_true(checked >= 60, "checked %d item recipes" % checked)


func test_new_station_recipes_need_their_station() -> void:
	for rid in ["woven_cloth", "roseberry_tart", "padded_hood"]:
		var r := ItemDB.recipe(rid)
		_unlock(r)
		_give_all(r["ingredients"])
		var st := String(r["station"])
		var c := Crafting.check(rid, ["hand", "workbench"])
		assert_false(bool(c["ok"]), rid)
		assert_true(String(c["reason"]).contains(ItemDB.station_name(st)), "%s names the %s: %s" % [rid, st, c["reason"]])
		assert_true(Crafting.craft(rid, ["hand", st]), rid + " at its station")


func test_kitchen_recipe_full_backpack_changes_nothing() -> void:
	_fill_bag_with_junk()
	GameState.inventory.set_slot(30, {"id": "roseberries", "count": 5})   # partial stacks: no slot frees up
	GameState.inventory.set_slot(31, {"id": "sugarcap", "count": 3})
	var snap: Array = GameState.inventory.to_array()
	var c := Crafting.check("roseberry_tart", ["hand", "kitchen"])
	assert_false(bool(c["ok"]), "no room for the tart")
	assert_false(Crafting.craft("roseberry_tart", ["hand", "kitchen"]))
	assert_eq(GameState.inventory.to_array(), snap)
	assert_eq(GameState.dropped.size(), 0)


func test_campfire_legacy_recipes_unchanged() -> void:
	for rid in ["hearty_stew", "glowcap_skewer"]:
		assert_eq(String(ItemDB.recipe(rid)["station"]), "campfire")
		_give_all(ItemDB.recipe(rid)["ingredients"])
		assert_true(Crafting.craft(rid, ["hand", "campfire"]), rid)


func test_timed_recipes_are_refused_outside_the_furnace_queue() -> void:
	GameState.give_item("copper_ore", 4)
	var c := Crafting.check("copper_bar", ALL_STATIONS)
	assert_false(bool(c["ok"]))
	assert_true(String(c["reason"]).to_lower().contains("queue"), String(c["reason"]))
	assert_false(Crafting.craft("copper_bar", ALL_STATIONS))
	assert_eq(GameState.count_item("copper_ore"), 4)


# --- Backpack upgrades -----------------------------------------------------------------------------------

func test_backpack_32_40_48_never_truncates_and_keeps_the_hotbar() -> void:
	var inv = GameState.inventory
	assert_eq(int(inv.size), 32)
	for i in 32:
		inv.set_slot(i, {"id": "stone", "count": i + 1})
	inv.set_slot(0, {"id": "stone_axe", "count": 1})
	inv.set_slot(1, {"id": "woven_cloth", "count": 10})
	inv.set_slot(2, {"id": "copper_bar", "count": 2})
	inv.set_slot(3, {"id": "iron_bar", "count": 2})
	var hotbar_before: Array = inv.to_array().slice(4, 8)
	var rest_before: Array = inv.to_array().slice(8, 32)
	assert_false(bool(Crafting.check("backpack_48", ["hand", "loom"])["ok"]), "48 needs 40 first")
	assert_true(Crafting.craft("backpack_40", ["hand", "loom"]), Crafting.last_reason)
	assert_eq(int(inv.size), 40)
	assert_eq(int(GameState.capacity["backpack"]), 40)
	assert_eq(inv.to_array().slice(4, 8), hotbar_before, "hotbar untouched")
	assert_eq(inv.to_array().slice(8, 32), rest_before, "legacy slots untouched")
	assert_eq(GameState.count_item("woven_cloth"), 6)
	assert_eq(GameState.count_item("copper_bar"), 0)
	assert_eq(_crafted.back(), ["backpack_40", "", 0])
	assert_false(bool(Crafting.check("backpack_40", ["hand", "loom"])["ok"]), "can't grow to 40 twice")
	assert_true(Crafting.craft("backpack_48", ["hand", "loom"]), Crafting.last_reason)
	assert_eq(int(inv.size), 48)
	assert_eq(GameState.count_item("woven_cloth"), 0)
	inv.set_slot(47, {"id": "sunflax", "count": 7})
	# Save / load: capacity first, so slot 47 survives; loading twice changes nothing.
	var d := GameState.to_dict()
	var json: Dictionary = JSON.parse_string(JSON.stringify(d))
	GameState.from_dict(json)
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(int(GameState.inventory.size), 48)
	assert_eq(GameState.inventory.get_slot(47), {"id": "sunflax", "count": 7}, "extra slot kept")
	assert_eq(GameState.inventory.to_array().slice(4, 8), hotbar_before, "hotbar after load")
	assert_false(bool(Crafting.check("backpack_48", ["hand", "loom"])["ok"]))


func test_backpack_upgrade_refused_without_ingredients_changes_nothing() -> void:
	GameState.give_item("woven_cloth", 3)
	var snap: Array = GameState.inventory.to_array()
	assert_false(Crafting.craft("backpack_40", ["hand", "loom"]))
	assert_eq(int(GameState.inventory.size), 32)
	assert_eq(GameState.inventory.to_array(), snap)


# --- Patterns & dyes -------------------------------------------------------------------------------------

func test_pattern_recipe_grants_ownership_once() -> void:
	GameState.set_flag("c1x_tailor_cache", true)
	GameState.give_item("woven_cloth", 3)
	GameState.give_item("berries", 5)
	assert_true(Crafting.known_special("loom").has("pattern_ribbon_bow"))
	assert_true(Crafting.craft("pattern_ribbon_bow", ["hand", "loom"]), Crafting.last_reason)
	assert_true((GameState.wardrobe["owned"] as Array).has("pat_ribbon_bow"))
	assert_eq(GameState.count_item("woven_cloth"), 2)
	var c := Crafting.check("pattern_ribbon_bow", ["hand", "loom"])
	assert_false(bool(c["ok"]), "already owned")
	assert_true(String(c["reason"]).to_lower().contains("already"), String(c["reason"]))
	assert_false(Crafting.craft("pattern_ribbon_bow", ["hand", "loom"]))
	assert_eq(GameState.count_item("woven_cloth"), 2, "cloth never consumed twice")
	assert_eq(GameState.count_item("berries"), 3)


func test_dye_palette_mixed_once_at_the_loom() -> void:
	assert_true(Crafting.known_special("loom").has("dye:rose"))
	GameState.give_item("roseberries", 9)
	assert_false(Crafting.craft("dye:rose", ["hand"]), "needs the loom")
	assert_true(Crafting.craft("dye:rose", ["hand", "loom"]), Crafting.last_reason)
	assert_true(Crafting.owns_palette("rose"))
	assert_eq(GameState.count_item("roseberries"), 5)
	assert_false(Crafting.craft("dye:rose", ["hand", "loom"]), "only once")
	assert_eq(GameState.count_item("roseberries"), 5)
	assert_eq(Crafting.display_name("dye:rose"), "Rose Dye")
	assert_eq(Crafting.kind("dye:nope"), "")
	assert_false(Crafting.craft("dye:nope", ["hand", "loom"]))


func test_mastery_gated_recipes_are_decorative_only() -> void:
	for rid in ItemDB.every_recipe_id():
		var r := ItemDB.recipe(rid)
		if r.has("mastery"):
			assert_false(ItemDB.is_story_required(String(r.get("result", ""))), rid + " is never a story item")
			assert_eq(String(ItemDB.category(String(r["result"]))), "placeable", rid + " is a decorative piece")


# --- Crafting from nearby chests ----------------------------------------------------------------------------

func test_chest_sources_same_area_within_radius_in_stable_order() -> void:
	var c3 := _chest(Vector3(3, 0, 0))
	var c1 := _chest(Vector3(-2, 0, 1))
	var far := _chest(Vector3(20, 0, 0))
	var other := _chest(Vector3(1, 0, 0), "hallowmere_reach")
	var bench := GameState.add_structure("workbench", Vector3(0, 0, 2), 0)
	var near := Crafting.chest_sources_near(Vector3.ZERO, "surface")
	assert_eq(near, [c3, c1], "same area, within the radius, placement order")
	assert_false(near.has(far), "far chest excluded")
	assert_false(near.has(other), "another area is never a source")
	assert_false(near.has(bench), "only storage")
	assert_eq(Crafting.chest_sources_near(Vector3(1, 0, 0), "hallowmere_reach"), [other])


## The owner's choice: chests up to 18 m away (not 8) supply ingredients; farther ones never do.
func test_chest_radius_is_18_m() -> void:
	assert_almost(Crafting.CHEST_RADIUS, 18.0)
	var at_12 := _chest(Vector3(12, 0, 0))
	var at_17 := _chest(Vector3(0, 0, -17.5))
	var at_18 := _chest(Vector3(0, 0, 18))
	var past := _chest(Vector3(-18.5, 0, 0))
	var up_high := _chest(Vector3(17, 7, 0))   # 18.4 m away in 3D (an upper storey far off)
	var near := Crafting.chest_sources_near(Vector3.ZERO, "surface")
	assert_eq(near, [at_12, at_17, at_18], "12 m, 17.5 m and exactly 18 m count, in placement order")
	assert_false(near.has(past), "18.5 m is too far")
	assert_false(near.has(up_high), "distance is measured in 3D")
	# A chest 12 m away really supplies a craft.
	GameState.get_storage(at_12).add("wood", 8)
	GameState.get_storage(at_12).add("stone", 2)
	assert_true(Crafting.craft("workbench", ["hand"], near), Crafting.last_reason)
	assert_eq(GameState.count_item("workbench"), 1)
	assert_true(GameState.get_storage(at_12).is_empty())


func test_crafting_across_backpack_and_several_chests_is_one_transaction() -> void:
	var a := _chest(Vector3(2, 0, 0))
	var b := _chest(Vector3(-2, 0, 0))
	GameState.give_item("wood", 3)
	GameState.get_storage(a).add("wood", 2)
	GameState.get_storage(b).add("wood", 10)
	GameState.get_storage(b).add("stone", 5)
	var src := Crafting.chest_sources_near(Vector3.ZERO)
	assert_eq(src, [a, b])
	var pl := Crafting.plan("workbench", src)
	assert_true(bool(pl["ok"]))
	assert_eq(pl["backpack"], {"wood": 3}, "backpack first")
	assert_eq(pl["chests"], [{"uid": a, "items": {"wood": 2}}, {"uid": b, "items": {"wood": 3, "stone": 2}}], "then chests in order")
	assert_false(bool(Crafting.check("workbench", ["hand"])["ok"]), "without chests: missing")
	var removed: Array = []
	var cb := func(id: String, n: int) -> void: removed.append([id, n])
	Events.item_removed.connect(cb)
	assert_true(Crafting.craft("workbench", ["hand"], src), Crafting.last_reason)
	Events.item_removed.disconnect(cb)
	assert_eq(GameState.count_item("workbench"), 1)
	assert_eq(GameState.count_item("wood"), 0)
	assert_eq(GameState.get_storage(a).count_of("wood"), 0)
	assert_eq(GameState.get_storage(b).count_of("wood"), 7)
	assert_eq(GameState.get_storage(b).count_of("stone"), 3)
	assert_eq(removed, [["wood", 3]], "item_removed only for the backpack share")
	assert_eq(Crafting.max_craftable("workbench", src), 0)


func test_chest_crafting_rolls_back_every_inventory_on_failure() -> void:
	var a := _chest(Vector3(2, 0, 0))
	var b := _chest(Vector3(-2, 0, 0))
	GameState.get_storage(a).add("wood", 4)
	GameState.get_storage(b).add("wood", 4)
	GameState.get_storage(b).add("stone", 2)
	# Backpack full of junk: the workbench has nowhere to go -> refused before anything is taken.
	_fill_bag_with_junk()
	var bag: Array = GameState.inventory.to_array()
	var sa: Array = GameState.get_storage(a).to_array()
	var sb: Array = GameState.get_storage(b).to_array()
	var src := [a, b]
	assert_false(bool(Crafting.check("workbench", ["hand"], src)["ok"]), "no room for the result")
	assert_false(Crafting.craft("workbench", ["hand"], src))
	assert_eq(GameState.inventory.to_array(), bag)
	assert_eq(GameState.get_storage(a).to_array(), sa)
	assert_eq(GameState.get_storage(b).to_array(), sb)
	# A commit that fails after every ingredient was taken restores the backpack and ALL chests.
	GameState.inventory.set_slot(0, {"id": "wood", "count": 1})
	bag = GameState.inventory.to_array()
	var used := Crafting.transact({"wood": 7, "stone": 1}, src, func() -> bool: return false)
	assert_true(used.is_empty(), "transaction refused")
	assert_eq(GameState.inventory.to_array(), bag, "backpack restored")
	assert_eq(GameState.get_storage(a).to_array(), sa, "chest A restored")
	assert_eq(GameState.get_storage(b).to_array(), sb, "chest B restored")
	# Taking more than exists anywhere never starts.
	assert_true(Crafting.transact({"wood": 50}, src, func() -> bool: return true).is_empty())
	assert_eq(GameState.get_storage(b).to_array(), sb)


func test_chest_share_never_frees_backpack_room() -> void:
	var a := _chest(Vector3(2, 0, 0))
	GameState.get_storage(a).add("wood", 8)
	GameState.get_storage(a).add("stone", 2)
	_fill_bag_with_junk()
	assert_false(bool(Crafting.check("workbench", ["hand"], [a])["ok"]), "all ingredients in the chest: no backpack slot frees up")
	GameState.inventory.set_slot(31, null)
	assert_true(Crafting.craft("workbench", ["hand"], [a]))
	assert_eq(GameState.get_storage(a).is_empty(), true)


func test_invalid_sources_are_ignored() -> void:
	var bench := GameState.add_structure("workbench", Vector3(1, 0, 0), 0)
	GameState.give_item("berries", 4)
	assert_true(Crafting.craft("berry_snack", ["hand"], [bench, "nope", ""]))


func test_use_chests_preference_is_saved() -> void:
	assert_false(Crafting.use_chests())
	Crafting.set_use_chests(true)
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_true(Crafting.use_chests(), "saved with the journey")


# --- Seasonal dishes & festival table -------------------------------------------------------------------------

func test_seasonal_dishes_counter_counts_distinct_dishes() -> void:
	GameState.give_item("roseberries", 10)
	GameState.give_item("sugarcap", 10)
	GameState.give_item("moonpetal", 4)
	GameState.give_item("sweetroot", 4)
	assert_true(Crafting.craft("roseberry_tart", ["hand", "kitchen"]))
	assert_true(Crafting.craft("roseberry_tart", ["hand", "kitchen"]))
	assert_eq(GameState.get_counter("ch2_seasonal_dishes"), 1, "the same dish twice counts once")
	assert_true(Crafting.craft("moonpetal_tea", ["hand", "campfire"]))
	assert_eq(GameState.get_counter("ch2_seasonal_dishes"), 2)
	GameState.give_item("berries", 4)
	assert_true(Crafting.craft("berry_snack", ["hand"]))
	assert_eq(GameState.get_counter("ch2_seasonal_dishes"), 2, "legacy food doesn't count")
	# Candy is the goal's reward (unlocked by ch2_harvest_table), not one of its dishes (same list as the story tracker).
	GameState.set_flag("ch2_harvest_table", true)
	assert_true(Crafting.craft("candy", ["hand", "kitchen"]), Crafting.last_reason)
	assert_eq(GameState.get_counter("ch2_seasonal_dishes"), 2, "candy doesn't count")
	var story: Script = load("res://src/world/story_ch2/story_ch2.gd")
	if story != null:
		assert_eq(Crafting.SEASONAL_DISHES, story.get_script_constant_map().get("SEASONAL_DISHES"), "same dishes as the story tracker")


func test_festival_table_decoration_sets_the_goal_flag() -> void:
	assert_eq(Crafting.table_decor(), "")
	assert_false(Crafting.decorate_table("glitter"))
	assert_false(bool(GameState.get_flag("ch2_table_decorated")))
	assert_true(Crafting.decorate_table("pumpkins"))
	assert_true(bool(GameState.get_flag("ch2_table_decorated")))
	assert_eq(Crafting.table_decor(), "pumpkins")
	GameState.from_dict(JSON.parse_string(JSON.stringify(GameState.to_dict())))
	assert_eq(Crafting.table_decor(), "pumpkins")


func test_special_recipes_listed_per_station() -> void:
	var loom := Crafting.known_special("loom")
	assert_true(loom.has("backpack_40") and loom.has("backpack_48"))
	assert_false(loom.has("pattern_velvet_cape"), "locked patterns hidden")
	assert_false(Crafting.known_special().has("chest_upgrade_40"), "the chest upgrade lives in the storage panel")
	for pid in Crafting.dye_ids():
		assert_true(loom.has("dye:" + String(pid)))
	assert_eq(Crafting.known_special("kitchen"), [])
	assert_true(Crafting.display_name("backpack_40").contains("40"))
	assert_true(Crafting.effect_text("copper_bar").contains("furnace"))
