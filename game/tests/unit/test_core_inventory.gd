extends "res://tests/unit/test_core_base.gd"
## Inventory (src/core/inventory.gd): stacking, limits, leftovers, removal, move/merge/swap,
## transfers, sorting, snapshots and persistence. Uses standalone inventories, so no global state.


func _inv(n: int = 32) -> RefCounted:
	return Inventory.new(n)


func _ids(inv: RefCounted) -> Array:
	var out := []
	for s in inv.slots:
		out.append(null if s == null else "%s:%d" % [s["id"], int(s["count"])])
	return out


# --- add / stacking ----------------------------------------------------------------------

func test_new_inventory_is_empty_with_null_slots() -> void:
	var inv := _inv(10)
	assert_eq(inv.size, 10)
	assert_eq(inv.slots.size(), 10)
	assert_true(inv.is_empty())
	assert_eq(inv.free_slots(), 10)
	for s in inv.slots:
		assert_null(s)


func test_add_stacks_across_slots_hotbar_first() -> void:
	var inv := _inv()
	assert_eq(inv.add("wood", 250), 0, "250 wood fits")
	assert_eq(_ids(inv).slice(0, 4), ["wood:99", "wood:99", "wood:52", null], "fills slot 0 first, 99 per stack")
	assert_eq(inv.count_of("wood"), 250)


func test_add_tops_up_existing_partial_stacks_before_empty_slots() -> void:
	var inv := _inv(6)
	inv.set_slot(3, {"id": "wood", "count": 90})
	inv.set_slot(5, {"id": "wood", "count": 95})
	assert_eq(inv.add("wood", 20), 0)
	assert_eq(_ids(inv), ["wood:7", null, null, "wood:99", null, "wood:99"], "partial stacks topped up first (9 + 4), the remaining 7 go to the first empty slot")


func test_stack_limits_are_per_item() -> void:
	var inv := _inv()
	assert_eq(inv.add("stone_axe", 3), 0)
	assert_eq(_ids(inv).slice(0, 3), ["stone_axe:1", "stone_axe:1", "stone_axe:1"], "tools never stack")
	inv = _inv()
	assert_eq(inv.add("berries", 120), 0)
	assert_eq(_ids(inv).slice(0, 3), ["berries:50", "berries:50", "berries:20"], "berries stack to 50")
	inv = _inv()
	assert_eq(inv.add("berry_snack", 25), 0)
	assert_eq(_ids(inv).slice(0, 2), ["berry_snack:20", "berry_snack:5"], "meals stack to 20")
	assert_eq(ItemDB.stack_max("berry_snack"), 20, "limit comes from the item data")


func test_add_returns_leftovers_when_full() -> void:
	var inv := _inv(2)
	assert_eq(inv.add("wood", 250), 52, "2 slots hold 198 wood")
	assert_eq(inv.count_of("wood"), 198)
	assert_eq(inv.add("stone", 5), 5, "no room for another item type")
	assert_eq(inv.add("wood", 1), 1, "full stacks accept nothing")
	assert_eq(inv.count_of("stone"), 0)


func test_add_partial_fill_of_last_stack_returns_exact_remainder() -> void:
	var inv := _inv(3)
	inv.set_slot(0, {"id": "stone", "count": 99})
	inv.set_slot(1, {"id": "stone", "count": 99})
	inv.set_slot(2, {"id": "wood", "count": 97})
	assert_eq(inv.add("wood", 5), 3, "only 2 fit on the 97 stack")
	assert_eq(inv.count_of("wood"), 99)


func test_add_zero_or_negative_is_noop_without_signal() -> void:
	var inv := _inv(4)
	var emits := record(inv.changed, 0)
	assert_eq(inv.add("wood", 0), 0)
	assert_eq(inv.add("wood", -5), 0)
	assert_true(inv.is_empty())
	assert_eq(emits.size(), 0, "no changed signal for a no-op")


func test_add_unknown_item_is_refused() -> void:
	var inv := _inv(4)
	assert_eq(inv.add("definitely_not_an_item", 3), 3, "unknown ids never enter an inventory")
	assert_true(inv.is_empty())
	assert_true(logged("refusing unknown item"), "warns")


func test_space_for_and_can_add() -> void:
	var inv := _inv(3)
	assert_eq(inv.space_for("wood"), 297)
	assert_eq(inv.space_for("stone_axe"), 3)
	inv.set_slot(0, {"id": "wood", "count": 90})
	inv.set_slot(1, {"id": "stone", "count": 10})
	assert_eq(inv.space_for("wood"), 9 + 99, "top-up of 9 plus one empty slot")
	assert_true(inv.can_add("wood", 108))
	assert_false(inv.can_add("wood", 109))
	assert_eq(inv.space_for("berries"), 50)


func test_changed_signal_on_every_mutation() -> void:
	var inv := _inv(4)
	var emits := record(inv.changed, 0)
	inv.add("wood", 5)
	inv.remove("wood", 1)
	inv.remove_from_slot(0, 1)
	inv.set_slot(1, {"id": "stone", "count": 2})
	inv.move(1, 2)
	inv.sort_items(false)
	inv.from_array([])
	assert_eq(emits.size(), 7)


# --- remove -----------------------------------------------------------------------------------

func test_remove_is_all_or_nothing() -> void:
	var inv := _inv(4)
	inv.add("wood", 30)
	var emits := record(inv.changed, 0)
	assert_false(inv.remove("wood", 31), "cannot remove more than held")
	assert_eq(inv.count_of("wood"), 30, "failed remove changes nothing")
	assert_eq(emits.size(), 0, "failed remove emits nothing")
	assert_false(inv.remove("stone", 1))
	assert_true(inv.remove("wood", 30))
	assert_true(inv.is_empty(), "stack cleared at zero")


func test_remove_takes_from_last_stacks_first() -> void:
	var inv := _inv(6)
	inv.set_slot(0, {"id": "wood", "count": 99})
	inv.set_slot(2, {"id": "stone", "count": 5})
	inv.set_slot(4, {"id": "wood", "count": 10})
	assert_true(inv.remove("wood", 15))
	assert_eq(_ids(inv), ["wood:94", null, "stone:5", null, null, null], "backpack stack emptied before the hotbar stack")


func test_remove_zero_succeeds_trivially() -> void:
	var inv := _inv(2)
	assert_true(inv.remove("wood", 0))
	assert_true(inv.remove("wood", -3))


func test_remove_from_slot() -> void:
	var inv := _inv(4)
	inv.set_slot(1, {"id": "berries", "count": 12})
	assert_eq(inv.remove_from_slot(1, 5), 5)
	assert_eq(inv.get_slot(1)["count"], 7)
	assert_eq(inv.remove_from_slot(1, 50), 7, "returns only what was there")
	assert_null(inv.get_slot(1), "slot cleared")
	assert_eq(inv.remove_from_slot(1, 1), 0, "empty slot")
	assert_eq(inv.remove_from_slot(-1, 1), 0, "negative index")
	assert_eq(inv.remove_from_slot(99, 1), 0, "index past the end")
	inv.set_slot(0, {"id": "wood", "count": 3})
	assert_eq(inv.remove_from_slot(0, 0), 0, "zero count")
	assert_eq(inv.get_slot(0)["count"], 3)


# --- move / merge / swap ---------------------------------------------------------------------------

func test_move_into_empty_slot() -> void:
	var inv := _inv(10)
	inv.set_slot(0, {"id": "wood", "count": 5})
	inv.move(0, 9)
	assert_null(inv.get_slot(0))
	assert_eq(inv.get_slot(9), {"id": "wood", "count": 5})


func test_move_merges_same_item_with_overflow_left_behind() -> void:
	var inv := _inv(4)
	inv.set_slot(0, {"id": "wood", "count": 60})
	inv.set_slot(1, {"id": "wood", "count": 50})
	inv.move(0, 1)
	assert_eq(inv.get_slot(1)["count"], 99, "target filled to the stack limit")
	assert_eq(inv.get_slot(0)["count"], 11, "remainder stays in the source slot")
	inv.move(0, 2)
	assert_eq(inv.get_slot(2)["count"], 11)
	inv.set_slot(3, {"id": "wood", "count": 5})
	inv.move(3, 2)
	assert_null(inv.get_slot(3), "fully merged source becomes empty")
	assert_eq(inv.get_slot(2)["count"], 16)
	assert_eq(inv.count_of("wood"), 115, "merging never creates or destroys items")


func test_move_swaps_different_items() -> void:
	var inv := _inv(4)
	inv.set_slot(0, {"id": "wood", "count": 5})
	inv.set_slot(3, {"id": "stone_axe", "count": 1})
	inv.move(0, 3)
	assert_eq(inv.get_slot(0), {"id": "stone_axe", "count": 1})
	assert_eq(inv.get_slot(3), {"id": "wood", "count": 5})


func test_move_onto_full_stack_changes_nothing() -> void:
	var inv := _inv(4)
	inv.set_slot(0, {"id": "wood", "count": 10})
	inv.set_slot(1, {"id": "wood", "count": 99})
	inv.move(0, 1)
	assert_eq(_ids(inv), ["wood:10", "wood:99", null, null])


func test_move_invalid_or_empty_is_noop() -> void:
	var inv := _inv(4)
	inv.set_slot(0, {"id": "wood", "count": 10})
	var emits := record(inv.changed, 0)
	inv.move(0, 0)
	inv.move(-1, 2)
	inv.move(0, 4)
	inv.move(2, 0)
	assert_eq(_ids(inv), ["wood:10", null, null, null])
	assert_eq(emits.size(), 0)


# --- transfer between inventories -------------------------------------------------------------------------

func test_transfer_whole_stack() -> void:
	var bag := _inv(4)
	var chest := _inv(20)
	bag.set_slot(2, {"id": "copper_ore", "count": 12})
	assert_eq(bag.transfer_slot_to(chest, 2), 12)
	assert_null(bag.get_slot(2))
	assert_eq(chest.count_of("copper_ore"), 12)


func test_transfer_partial_when_target_nearly_full() -> void:
	var bag := _inv(4)
	var chest := _inv(2)
	chest.set_slot(0, {"id": "stone", "count": 99})
	chest.set_slot(1, {"id": "wood", "count": 90})
	bag.set_slot(0, {"id": "wood", "count": 20})
	assert_eq(bag.transfer_slot_to(chest, 0), 9, "only 9 fit")
	assert_eq(bag.get_slot(0)["count"], 11, "the rest stays in the bag")
	assert_eq(chest.count_of("wood"), 99)
	assert_eq(bag.count_of("wood") + chest.count_of("wood"), 110, "nothing lost")


func test_transfer_into_full_target_moves_nothing() -> void:
	var bag := _inv(2)
	var chest := _inv(1)
	chest.set_slot(0, {"id": "stone", "count": 99})
	bag.set_slot(0, {"id": "wood", "count": 5})
	assert_eq(bag.transfer_slot_to(chest, 0), 0)
	assert_eq(bag.get_slot(0)["count"], 5)


func test_transfer_edge_cases() -> void:
	var bag := _inv(3)
	bag.set_slot(0, {"id": "wood", "count": 10})
	assert_eq(bag.transfer_slot_to(bag, 0), 0, "to itself is a no-op")
	assert_eq(bag.get_slot(0)["count"], 10)
	assert_eq(bag.transfer_slot_to(_inv(3), 1), 0, "empty slot")
	assert_eq(bag.transfer_slot_to(_inv(3), 7), 0, "out of range")
	assert_eq(bag.transfer_slot_to(null, 0), 0, "null target")


# --- sorting -------------------------------------------------------------------------------------------------

func test_sort_keeps_hotbar_and_merges_backpack() -> void:
	var inv := _inv(32)
	inv.set_slot(0, {"id": "wood", "count": 7})
	inv.set_slot(3, {"id": "stone_axe", "count": 1})
	inv.set_slot(7, {"id": "berries", "count": 2})
	inv.set_slot(9, {"id": "wood", "count": 60})
	inv.set_slot(12, {"id": "berries", "count": 30})
	inv.set_slot(20, {"id": "wood", "count": 60})
	inv.set_slot(25, {"id": "copper_sword", "count": 1})
	inv.set_slot(31, {"id": "berries", "count": 30})
	var hotbar_before := _ids(inv).slice(0, 8)
	inv.sort_items()
	assert_eq(_ids(inv).slice(0, 8), hotbar_before, "hotbar untouched")
	# weapon < food < resource (CATEGORY_ORDER), stacks merged to their limits
	assert_eq(_ids(inv).slice(8, 14), ["copper_sword:1", "berries:50", "berries:10", "wood:99", "wood:21", null])
	assert_eq(inv.count_of("wood"), 127)
	assert_eq(inv.count_of("berries"), 62)


func test_sort_category_then_name_order_is_deterministic() -> void:
	var inv := _inv(16)
	var items := ["sweetroot_seeds", "fiber", "stone", "wood", "lantern", "stone_pickaxe", "stone_axe", "berry_snack", "berries", "workbench"]
	for i in items.size():
		inv.set_slot(8 + (i % 8) if i < 8 else i - 8, {"id": items[i], "count": 1})
	inv.sort_items(false)
	var got := []
	for s in inv.slots:
		if s != null:
			got.append(s["id"])
	# tool (Stone Axe < Stone Pickaxe), equipment, food (Berries < Berry Snack), resource (Plant Fiber < Stone < Wood), seed, placeable
	assert_eq(got, ["stone_axe", "stone_pickaxe", "lantern", "berries", "berry_snack", "fiber", "stone", "wood", "sweetroot_seeds", "workbench"])


func test_every_item_category_is_sortable() -> void:
	var order: Array = preload("res://data/items.gd").CATEGORY_ORDER
	for id in ItemDB.all_item_ids():
		assert_true(order.has(ItemDB.category(id)), "category of %s is in CATEGORY_ORDER" % id)


# --- persistence ----------------------------------------------------------------------------------------------

func test_snapshot_restore_is_a_deep_copy() -> void:
	var inv := _inv(8)
	inv.add("wood", 120)
	inv.set_slot(5, {"id": "stone_axe", "count": 1})
	var snap: Array = inv.snapshot()
	inv.remove("wood", 100)
	inv.clear_slot(5)
	inv.add("berries", 3)
	assert_eq(snap[0], {"id": "wood", "count": 99}, "snapshot unaffected by later changes")
	inv.restore(snap)
	assert_eq(inv.to_array(), snap)
	assert_eq(inv.count_of("wood"), 120)
	assert_eq(inv.count_of("berries"), 0)


func test_from_array_drops_unknown_and_malformed_entries() -> void:
	var inv := _inv(8)
	inv.add("wood", 5)
	inv.from_array([{"id": "no_such_item", "count": 3}, {"id": "stone", "count": 2}, "garbage", null,
		{"id": "fiber", "count": 0}, {"count": 5}, {"id": "berries", "count": "lots"}, {"id": 42, "count": 1},
		{"id": "berries", "count": {}}])
	assert_eq(_ids(inv), [null, "stone:2", null, null, null, null, null, null], "only the valid entry survives, at its index")
	assert_eq(inv.count_of("wood"), 0, "previous contents replaced")


func test_from_array_normalises_json_floats_and_truncates() -> void:
	var inv := _inv(2)
	inv.from_array([{"id": "wood", "count": 12.0}, null, {"id": "stone", "count": 4}])
	assert_eq(typeof(inv.get_slot(0)["count"]), TYPE_INT, "count is an int again")
	assert_eq(inv.get_slot(0)["count"], 12)
	assert_eq(inv.count_of("stone"), 0, "entries beyond the size are ignored")


func test_to_array_round_trip_through_json() -> void:
	var inv := _inv(6)
	inv.add("wood", 150)
	inv.set_slot(4, {"id": "lantern", "count": 1})
	var copy := _inv(6)
	copy.from_array(json_norm(inv.to_array()))
	assert_deep_eq(copy.to_array(), inv.to_array(), "inventory")


func test_set_slot_validation() -> void:
	var inv := _inv(3)
	inv.set_slot(0, {"id": "wood", "count": 4})
	inv.set_slot(0, {"id": "wood", "count": 0})
	assert_null(inv.get_slot(0), "count 0 clears")
	inv.set_slot(1, {"id": "nope", "count": 4})
	assert_null(inv.get_slot(1), "unknown id ignored")
	inv.set_slot(1, {"count": 4})
	assert_null(inv.get_slot(1), "missing id ignored")
	inv.set_slot(1, "junk")
	assert_null(inv.get_slot(1), "non-dictionary ignored")
	inv.set_slot(5, {"id": "wood", "count": 4})
	assert_true(inv.is_empty(), "out-of-range index ignored")
	inv.set_slot(2, {"id": "wood", "count": 4.0})
	assert_eq(typeof(inv.get_slot(2)["count"]), TYPE_INT)
	var stored: Dictionary = inv.get_slot(2)
	var src := {"id": "stone", "count": 3}
	inv.set_slot(2, src)
	src["count"] = 50
	assert_eq(inv.get_slot(2)["count"], 3, "set_slot copies the stack")
	assert_eq(stored["count"], 4)


func test_totals_and_queries() -> void:
	var inv := _inv(6)
	inv.add("wood", 120)
	inv.add("berries", 3)
	assert_eq(inv.totals(), {"wood": 120, "berries": 3})
	assert_true(inv.has("wood", 120))
	assert_false(inv.has("wood", 121))
	assert_true(inv.has("stone", 0))
	assert_eq(inv.free_slots(), 3)
	assert_null(inv.get_slot(-1))
	assert_null(inv.get_slot(6))
