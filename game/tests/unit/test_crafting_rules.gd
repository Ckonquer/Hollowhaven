extends "res://tests/test_case.gd"
## Crafting: validity, missing ingredients/stations, locked recipes, transactional safety.

const Crafting := preload("res://src/crafting/crafting.gd")
const Factory := preload("res://src/building/structure_factory.gd")

var _crafted: Array = []


func before_each() -> void:
	fresh_state()
	_crafted = []
	if not Events.crafted.is_connected(_on_crafted):
		Events.crafted.connect(_on_crafted)


func after_each() -> void:
	if Events.crafted.is_connected(_on_crafted):
		Events.crafted.disconnect(_on_crafted)


func _on_crafted(recipe_id: String, item_id: String, count: int) -> void:
	_crafted.append([recipe_id, item_id, count])


func _fill(slots: Array) -> void:
	var inv = GameState.inventory
	for i in inv.size:
		inv.set_slot(i, slots[i] if i < slots.size() else null)


func test_valid_craft_consumes_and_produces_exactly_once() -> void:
	GameState.give_item("wood", 5)
	GameState.give_item("stone", 4)
	GameState.give_item("fiber", 3)
	assert_true(Crafting.craft("stone_axe", ["hand"]), "axe crafted")
	assert_eq(GameState.count_item("wood"), 2, "3 wood used")
	assert_eq(GameState.count_item("stone"), 2, "2 stone used")
	assert_eq(GameState.count_item("fiber"), 1, "2 fiber used")
	assert_eq(GameState.count_item("stone_axe"), 1, "one axe")
	assert_eq(_crafted.size(), 1, "crafted emitted once")
	assert_eq(_crafted[0], ["stone_axe", "stone_axe", 1])
	assert_eq(int(GameState.stats["items_crafted"]), 1, "stat incremented")


func test_multi_count_recipe_adds_full_count() -> void:
	GameState.give_item("wood", 2)
	assert_true(Crafting.craft("fence", ["hand", "workbench"]))
	assert_eq(GameState.count_item("fence"), 2, "fence recipe gives 2")
	assert_eq(GameState.count_item("wood"), 0)
	assert_eq(int(GameState.stats["items_crafted"]), 2)


func test_missing_ingredients_are_reported_and_nothing_changes() -> void:
	GameState.give_item("wood", 1)
	GameState.give_item("stone", 2)
	var before: Array = GameState.inventory.to_array()
	var c := Crafting.check("stone_axe", ["hand"])
	assert_false(bool(c["ok"]))
	assert_eq(c["missing"], {"wood": 2, "fiber": 2}, "exact missing counts")
	assert_true(String(c["reason"]).contains("Wood"), "reason names the item: " + String(c["reason"]))
	assert_false(Crafting.craft("stone_axe", ["hand"]))
	assert_eq(GameState.inventory.to_array(), before, "inventory untouched")
	assert_eq(_crafted.size(), 0)


func test_unknown_and_locked_recipes() -> void:
	assert_false(bool(Crafting.check("does_not_exist", ["hand"])["ok"]))
	assert_false(Crafting.craft("does_not_exist", ["hand"]))
	GameState.give_item("glowcap", 2)
	GameState.give_item("silk", 2)
	GameState.give_item("wood", 2)
	assert_false(Crafting.known_recipes().has("heartbloom_lamp"), "locked until the ward is restored")
	assert_false(Crafting.craft("heartbloom_lamp", ["hand", "workbench"]), "locked recipe refuses")
	assert_eq(GameState.count_item("glowcap"), 2, "nothing consumed")
	GameState.set_flag("ward_restored", true)
	assert_true(Crafting.known_recipes().has("heartbloom_lamp"))
	assert_true(Crafting.craft("heartbloom_lamp", ["hand", "workbench"]), "unlocked")
	assert_eq(GameState.count_item("heartbloom_lamp"), 1)


func test_missing_station_refuses() -> void:
	GameState.give_item("copper_ore", 4)
	GameState.give_item("wood", 2)
	GameState.give_item("fiber", 2)
	var before: Array = GameState.inventory.to_array()
	var c := Crafting.check("copper_sword", ["hand"])
	assert_false(bool(c["ok"]))
	assert_true(String(c["reason"]).contains("Workbench"), "reason mentions the station: " + String(c["reason"]))
	assert_false(Crafting.craft("copper_sword", ["hand"]))
	assert_eq(GameState.inventory.to_array(), before)
	assert_true(Crafting.craft("copper_sword", ["hand", "workbench"]), "works at a workbench")
	assert_eq(GameState.count_item("copper_sword"), 1)


func test_rapid_repeated_crafting_never_duplicates_or_loses_items() -> void:
	GameState.give_item("wood", 26)
	GameState.give_item("stone", 7)
	var ok := 0
	for i in 25:
		if Crafting.craft("workbench", ["hand"]):
			ok += 1
	assert_eq(ok, 3, "exactly 3 workbenches affordable")
	assert_eq(GameState.count_item("workbench"), 3)
	assert_eq(GameState.count_item("wood"), 2, "26 - 3*8")
	assert_eq(GameState.count_item("stone"), 1, "7 - 3*2")
	assert_eq(_crafted.size(), 3)


func test_result_that_does_not_fit_restores_everything() -> void:
	var slots: Array = []
	for i in 29:
		slots.append({"id": "berries", "count": 50})
	slots.append({"id": "wood", "count": 10})
	slots.append({"id": "stone", "count": 10})
	slots.append({"id": "fiber", "count": 10})
	_fill(slots)
	var before: Array = GameState.inventory.to_array()
	var c := Crafting.check("stone_axe", ["hand"])
	assert_false(bool(c["ok"]), "backpack full")
	assert_true(String(c["reason"]).to_lower().contains("full"), String(c["reason"]))
	assert_false(Crafting.craft("stone_axe", ["hand"]))
	assert_eq(GameState.inventory.to_array(), before, "nothing consumed when the result can't fit")
	assert_eq(GameState.dropped.size(), 0, "nothing dropped either")


func test_result_fits_when_ingredients_free_a_slot() -> void:
	var slots: Array = []
	for i in 29:
		slots.append({"id": "berries", "count": 50})
	slots.append({"id": "wood", "count": 3})
	slots.append({"id": "stone", "count": 2})
	slots.append({"id": "fiber", "count": 2})
	_fill(slots)
	assert_true(bool(Crafting.check("stone_axe", ["hand"])["ok"]), "consumed stacks free a slot")
	assert_true(Crafting.craft("stone_axe", ["hand"]))
	assert_eq(GameState.count_item("stone_axe"), 1)
	assert_eq(GameState.count_item("wood") + GameState.count_item("stone") + GameState.count_item("fiber"), 0)
	assert_eq(GameState.count_item("berries"), 29 * 50, "other items untouched")


func test_result_merges_into_existing_stack_in_a_full_backpack() -> void:
	var slots: Array = []
	for i in 30:
		slots.append({"id": "wood", "count": 99})
	slots.append({"id": "berries", "count": 8})
	slots.append({"id": "berry_snack", "count": 5})
	_fill(slots)
	assert_true(Crafting.craft("berry_snack", ["hand"]), "stacks onto the existing snacks")
	assert_eq(GameState.count_item("berry_snack"), 6)
	assert_eq(GameState.count_item("berries"), 4)


func test_max_craftable_and_describe() -> void:
	GameState.give_item("berries", 13)
	assert_eq(Crafting.max_craftable("berry_snack"), 3)
	assert_eq(Crafting.describe_items({"wood": 2, "stone": 1}), "2 Wood, 1 Stone")


## COV-006: counts above 1 use the plural name (countable items), mass nouns and names already plural stay, one
## stays singular; the arachnophobia alt names follow the same rules.
func test_describe_items_uses_plurals_for_counts_above_one() -> void:
	assert_eq(Crafting.describe_items({"copper_bar": 3}), "3 Copper Bars")
	assert_eq(Crafting.describe_items({"copper_bar": 1}), "1 Copper Bar")
	assert_eq(Crafting.describe_items({"copper_ore": 2, "wood": 6, "fiber": 3}), "2 Copper Ore, 6 Wood, 3 Plant Fiber")
	assert_eq(Crafting.describe_items({"moon_crystal": 2, "berries": 4, "wood_stairs": 2}), "2 Moon Crystals, 4 Berries, 2 Wooden Stairs")
	var cases := {"Copper Bar": "Copper Bars", "Music Box": "Music Boxes", "Cottage Bench": "Cottage Benches",
		"Stone Pickaxe": "Stone Pickaxes", "Bookshelf": "Bookshelves", "Doorway": "Doorways", "Echo Shard": "Echo Shards",
		"Padded Boots": "Padded Boots", "Iron Ore": "Iron Ore", "Weaver Silk": "Weaver Silk", "Lanternwake Candy": "Lanternwake Candy",
		"The Heartseed": "The Heartseed", "Foreman's Key": "Foreman's Keys", "Pumpkin": "Pumpkins", "Pale Thread": "Pale Thread"}
	for k in cases:
		assert_eq(ItemDB.plural_of(String(k)), String(cases[k]), String(k))
	var was: Variant = Settings.get_value("arachnophobia")
	Settings.set_value("arachnophobia", true)
	assert_eq(Crafting.describe_items({"silk": 2}), "2 Pale Thread", "the alt name, a mass noun")
	Settings.set_value("arachnophobia", false)
	assert_eq(Crafting.describe_items({"silk": 2}), "2 Weaver Silk")
	Settings.set_value("arachnophobia", was)
	# Every item has a readable plural (never empty, never a doubled s).
	for id in ItemDB.all_item_ids():
		var pl := ItemDB.display_name_count(String(id), 2)
		assert_true(pl != "" and not pl.ends_with("ss"), "%s -> %s" % [id, pl])


func test_stations_near_always_has_hand_and_respects_distance() -> void:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar station_id: String = \"campfire\"\n"
	s.reload()
	var near: Node3D = s.new()
	var far: Node3D = s.new()
	far.set("station_id", "workbench")
	add_child(near)
	add_child(far)
	near.add_to_group("crafting_station")
	far.add_to_group("crafting_station")
	near.global_position = Vector3(3.0, 0, 0)
	far.global_position = Vector3(0, 0, 6.0)
	var st := Crafting.stations_near(Vector3.ZERO)
	assert_true(st.has("hand"), "hand always available")
	assert_true(st.has("campfire"), "campfire within 4 m")
	assert_false(st.has("workbench"), "workbench 6 m away is too far")
	assert_eq(Crafting.stations_near(Vector3(100, 0, 100)), ["hand"])
	near.free()
	far.free()


func test_placed_workbench_structure_is_a_station() -> void:
	var wb := Factory.create("workbench", "wb_test")
	add_child(wb)
	wb.global_position = Vector3(1.5, 0, 0)
	assert_true(wb.is_in_group("crafting_station"))
	assert_eq(String(wb.get("station_id")), "workbench")
	assert_true(Crafting.stations_near(Vector3.ZERO).has("workbench"))
	assert_eq(Crafting.recipes_for_stations(["hand"]).has("copper_sword"), false)
	assert_true(Crafting.recipes_for_stations(["hand", "workbench"]).has("copper_sword"))
	wb.free()
