extends "res://tests/test_case.gd"
## Smoke tests for the foundation (autoloads, data, inventory, quests, saves).


func test_item_db_loads_all_items() -> void:
	assert_true(ItemDB.has_item("wood"), "wood exists")
	assert_eq(ItemDB.stack_max("stone_axe"), 1, "tools don't stack")
	for rid in ItemDB.all_recipe_ids():
		var r := ItemDB.recipe(rid)
		assert_true(ItemDB.has_item(r["result"]), "recipe %s result exists" % rid)
		for ing in r["ingredients"]:
			assert_true(ItemDB.has_item(ing), "recipe %s ingredient %s exists" % [rid, ing])
	for sid in ItemDB.all_structure_ids():
		assert_true(ItemDB.has_item(ItemDB.structure(sid)["item"]), "structure %s refund item exists" % sid)


func test_inventory_basic_stacking() -> void:
	fresh_state()
	var inv = GameState.inventory
	assert_eq(inv.add("wood", 150), 0, "150 wood fits")
	assert_eq(inv.count_of("wood"), 150)
	assert_true(inv.remove("wood", 100))
	assert_eq(inv.count_of("wood"), 50)
	assert_false(inv.remove("wood", 51), "cannot over-remove")
	assert_eq(inv.count_of("wood"), 50, "failed remove changes nothing")


func test_quest_chain_starts_and_advances() -> void:
	fresh_state()
	assert_eq(GameState.quests.current_id(), "wake")
	GameState.set_flag("read_ward_intro", true)
	GameState.quests.evaluate()
	assert_eq(GameState.quests.current_id(), "gather_basics")


func test_save_roundtrip() -> void:
	fresh_state()
	GameState.give_item("wood", 7)
	GameState.set_flag("read_ward_intro", true)
	GameState.quests.evaluate()
	assert_true(SaveSystem.save_game(), "save ok")
	GameState.reset()
	assert_eq(GameState.count_item("wood"), 0)
	assert_true(SaveSystem.load_game(), "load ok")
	assert_eq(GameState.count_item("wood"), 7, "wood restored")
	assert_eq(GameState.quests.current_id(), "gather_basics", "quest restored")
