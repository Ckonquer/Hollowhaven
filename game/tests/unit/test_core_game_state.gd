extends "res://tests/unit/test_core_base.gd"
## GameState (autoload/game_state.gd): items & overflow, key pouch, tools, flags/counters/lore,
## depletion timing, dropped items, structures/storages/crops, companions & bonds, clock, buffs, dye palettes.

const Layout := preload("res://data/world_layout.gd")
const CreaturesData := preload("res://data/creatures.gd")


func setup() -> void:
	fresh_state()


func _at(day: int, hour: float) -> void:
	GameState.total_minutes = float(day - 1) * 1440.0 + hour * 60.0


# --- new game ------------------------------------------------------------------------------------------

func test_new_game_starts_clean() -> void:
	GameState.give_item("wood", 5)
	GameState.set_flag("x")
	GameState.new_game()
	assert_true(GameState.active)
	assert_true(GameState.inventory.is_empty(), "no starting items: everything is gathered")
	assert_eq(GameState.key_items, {})
	assert_eq(GameState.flags, {})
	assert_eq(GameState.quests.current_id(), "wake")
	assert_almost(GameState.hour(), float(Layout.CLOCK["new_game_hour"]))
	assert_eq(GameState.day(), 1)
	assert_eq(GameState.companions.keys().size(), ItemDB.creature_ids().size())
	assert_eq(GameState.active_companion, "")
	assert_eq(GameState.next_uid, 1)


# --- give / take ---------------------------------------------------------------------------------------

func test_give_item_adds_and_signals() -> void:
	var added := record(Events.item_added, 2)
	assert_eq(GameState.give_item("wood", 120), 120)
	assert_eq(GameState.count_item("wood"), 120)
	assert_eq(added, [["wood", 120]])
	assert_eq(GameState.give_item("wood", 0), 0)
	assert_eq(GameState.give_item("no_such_item", 3), 0, "unknown ids give nothing")
	assert_eq(GameState.dropped.size(), 0)


func test_full_backpack_overflow_becomes_persistent_drop() -> void:
	fill_backpack("stone")
	var drops := record(Events.item_overflow_dropped, 3)
	var got := GameState.give_item("wood", 5, Vector3(1, 2, 3))
	assert_eq(got, 0, "nothing fit in the backpack")
	assert_eq(GameState.dropped.size(), 1, "the overflow was not destroyed")
	var d: Dictionary = GameState.dropped[0]
	assert_eq(d["item"], "wood")
	assert_eq(d["count"], 5, "with the right count")
	assert_eq(d["area"], "surface")
	assert_eq(d["pos"], [1.0, 2.0, 3.0])
	assert_true(String(d["uid"]).begins_with("d"))
	assert_eq(GameState.get_dropped(d["uid"]), d)
	assert_eq(drops, [["wood", 5, Vector3(1, 2, 3)]])
	# persists through a save round trip
	assert_true(SaveSystem.save_game())
	GameState.reset()
	assert_eq(GameState.dropped.size(), 0)
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.dropped.size(), 1)
	assert_deep_eq(GameState.dropped[0], d, "dropped")


func test_partial_overflow_splits_between_backpack_and_drop() -> void:
	fill_backpack("stone")
	GameState.inventory.set_slot(31, {"id": "wood", "count": 97})
	GameState.player["area"] = "below"
	GameState.player["pos"] = [4.0, 0.5, -2.0]
	assert_eq(GameState.give_item("wood", 5), 2, "2 topped up the last stack")
	assert_eq(GameState.inventory.count_of("wood"), 99)
	assert_eq(GameState.dropped.size(), 1)
	assert_eq(GameState.dropped[0]["count"], 3)
	assert_eq(GameState.dropped[0]["area"], "below", "dropped in the player's current area")
	assert_eq(GameState.dropped[0]["pos"], [4.0, 0.5, -2.0], "at the player's feet by default")
	assert_eq(GameState.count_item("wood") + int(GameState.dropped[0]["count"]), 102, "no item lost")


func test_quest_items_go_to_key_pouch_never_slots_never_dropped() -> void:
	fill_backpack("stone")
	var keys := record(Events.key_item_added, 1)
	assert_eq(GameState.give_item("foreman_key", 1, Vector3(9, 9, 9)), 1)
	assert_eq(GameState.give_item("heartseed", 1), 1)
	assert_eq(GameState.key_items, {"foreman_key": 1, "heartseed": 1})
	assert_eq(GameState.inventory.count_of("foreman_key"), 0, "never in slots")
	assert_eq(GameState.dropped.size(), 0, "never dropped, even with a full backpack")
	assert_eq(GameState.count_item("heartseed"), 1)
	assert_true(GameState.has_item("foreman_key"))
	assert_eq(keys, [["foreman_key"], ["heartseed"]])
	# also with an empty backpack
	GameState.inventory.from_array([])
	GameState.give_item("heartseed", 1)
	assert_true(GameState.inventory.is_empty())
	assert_eq(GameState.key_items["heartseed"], 2)


func test_take_item_regular_is_all_or_nothing() -> void:
	GameState.give_item("wood", 10)
	var removed := record(Events.item_removed, 2)
	assert_false(GameState.take_item("wood", 11))
	assert_eq(GameState.count_item("wood"), 10)
	assert_eq(removed.size(), 0)
	assert_true(GameState.take_item("wood", 10))
	assert_eq(GameState.count_item("wood"), 0)
	assert_eq(removed, [["wood", 10]])
	assert_false(GameState.take_item("stone", 1))


func test_take_item_quest_items() -> void:
	GameState.give_item("foreman_key", 1)
	var removed := record(Events.item_removed, 2)
	assert_false(GameState.take_item("foreman_key", 2), "cannot take more than held")
	assert_eq(GameState.key_items["foreman_key"], 1)
	assert_true(GameState.take_item("foreman_key", 1))
	assert_false(GameState.key_items.has("foreman_key"), "entry removed at zero")
	assert_eq(removed, [["foreman_key", 1]])
	assert_false(GameState.take_item("heartseed", 1), "missing quest item: clean false")


func test_take_zero_is_trivially_true_without_side_effects() -> void:
	var removed := record(Events.item_removed, 2)
	assert_true(GameState.take_item("heartseed", 0), "even for a quest item not held (used to be a script error)")
	assert_true(GameState.take_item("wood", 0))
	assert_true(GameState.take_item("wood", -2))
	assert_eq(removed.size(), 0)
	assert_eq(GameState.key_items, {})


func test_best_tool() -> void:
	assert_eq(GameState.best_tool("axe"), "")
	GameState.give_item("wood", 5)
	assert_eq(GameState.best_tool(""), "", "empty kind never matches plain items")
	GameState.give_item("stone_pickaxe", 1)
	assert_eq(GameState.best_tool("axe"), "")
	assert_eq(GameState.best_tool("pickaxe"), "stone_pickaxe")
	GameState.give_item("stone_axe", 1)
	assert_eq(GameState.best_tool("axe"), "stone_axe")
	assert_eq(GameState.best_tool("hand"), "", "hand harvesting needs no tool item")


func test_best_weapon() -> void:
	assert_eq(GameState.best_weapon(), "", "bare hands")
	GameState.give_item("wood", 5)
	GameState.give_item("lantern", 1)
	assert_eq(GameState.best_weapon(), "", "resources and equipment are not weapons")
	GameState.give_item("stone_axe", 1)
	assert_eq(GameState.best_weapon(), "stone_axe", "falls back to the best tool")
	GameState.give_item("copper_sword", 1)
	assert_eq(GameState.best_weapon(), "copper_sword", "a real weapon is preferred")
	assert_true(float(ItemDB.item("copper_sword")["damage"]) > float(ItemDB.item("stone_axe")["damage"]))


func test_hotbar_selection_is_clamped() -> void:
	var sel := record(Events.hotbar_selected, 1)
	GameState.select_hotbar(12)
	assert_eq(GameState.hotbar_index, 7)
	GameState.select_hotbar(-3)
	assert_eq(GameState.hotbar_index, 0)
	assert_eq(sel, [[7], [0]])
	GameState.give_item("stone_axe", 1)
	assert_eq(GameState.selected_slot(), {"id": "stone_axe", "count": 1})


# --- flags / counters / lore / uids -----------------------------------------------------------------------

func test_flags() -> void:
	var sets := record(Events.flag_set, 2)
	assert_eq(GameState.get_flag("nope"), false, "unset flags read as false")
	GameState.set_flag("mine_opened")
	assert_eq(GameState.get_flag("mine_opened"), true)
	GameState.set_flag("mine_opened", true)
	assert_eq(sets.size(), 1, "setting the same value again does not re-emit")
	GameState.set_flag("mine_opened", false)
	assert_eq(sets.size(), 2)
	GameState.set_flag("note", "hello")
	GameState.set_flag("note", true)   # String -> bool used to be a script error
	assert_eq(GameState.get_flag("note"), true)
	assert_eq(sets.size(), 4)


func test_counters() -> void:
	var ch := record(Events.counter_changed, 2)
	assert_eq(GameState.get_counter("trees_felled"), 0)
	assert_eq(GameState.add_counter("trees_felled"), 1)
	assert_eq(GameState.add_counter("trees_felled", 4), 5)
	assert_eq(GameState.get_counter("trees_felled"), 5)
	assert_eq(ch, [["trees_felled", 1], ["trees_felled", 5]])


func test_set_counter_max_only_raises() -> void:
	var ch := record(Events.counter_changed, 2)
	GameState.set_counter_max("max_bond", 2)
	GameState.set_counter_max("max_bond", 1)
	GameState.set_counter_max("max_bond", 2)
	assert_eq(GameState.get_counter("max_bond"), 2)
	GameState.set_counter_max("max_bond", 4)
	assert_eq(GameState.get_counter("max_bond"), 4)
	assert_eq(ch, [["max_bond", 2], ["max_bond", 4]], "emits only when the value rises")
	GameState.set_counter_max("fresh", 0)
	assert_eq(GameState.counters.has("fresh"), false, "0 is not above the implicit 0")


func test_lore_and_uids() -> void:
	var found := record(Events.lore_discovered, 1)
	assert_true(GameState.discover_lore("foreman_note"))
	assert_false(GameState.discover_lore("foreman_note"))
	assert_eq(GameState.lore, ["foreman_note"])
	assert_eq(found.size(), 1)
	assert_eq(GameState.new_uid(), "u1")
	assert_eq(GameState.new_uid("s"), "s2")
	assert_eq(GameState.next_uid, 3)


# --- depletion ------------------------------------------------------------------------------------------------

func test_deplete_respawn_timing() -> void:
	var t0 := GameState.total_minutes
	GameState.deplete("tree_12", 60.0)
	assert_true(GameState.is_depleted("tree_12"))
	GameState.total_minutes = t0 + 59.9
	assert_true(GameState.is_depleted("tree_12"), "still gone just before the respawn time")
	GameState.total_minutes = t0 + 60.0
	assert_false(GameState.is_depleted("tree_12"), "back exactly at the respawn time")
	assert_false(GameState.depleted.has("tree_12"), "entry cleaned up once respawned")
	GameState.deplete("tree_12", 30.0)
	assert_true(GameState.is_depleted("tree_12"), "can be depleted again")
	assert_false(GameState.is_depleted("never_touched"))


func test_deplete_never_respawns_and_zero_is_instant() -> void:
	GameState.deplete("mine_rubble", -1.0)
	GameState.total_minutes += 1440.0 * 40.0
	assert_true(GameState.is_depleted("mine_rubble"), "never-respawn survives any amount of time")
	GameState.skip_to_morning()
	assert_true(GameState.is_depleted("mine_rubble"))
	GameState.deplete("bush_1", 0.0)
	assert_false(GameState.is_depleted("bush_1"))


func test_depletion_survives_save_load() -> void:
	GameState.deplete("rock_3", 120.0)
	GameState.deplete("quarry_boulder", -1.0)
	var t := GameState.total_minutes
	assert_true(SaveSystem.save_game())
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_true(GameState.is_depleted("rock_3"))
	assert_true(GameState.is_depleted("quarry_boulder"))
	GameState.total_minutes = t + 120.0
	assert_false(GameState.is_depleted("rock_3"))
	assert_true(GameState.is_depleted("quarry_boulder"))


# --- dropped items ----------------------------------------------------------------------------------------------

func test_dropped_add_get_remove_filter() -> void:
	var a := GameState.add_dropped("wood", 3, "surface", Vector3(1, 0, 1))
	var b := GameState.add_dropped("glowcap", 1, "below", Vector3(0, -5, 2))
	var c := GameState.add_dropped("stone", 7, "surface", Vector3(-3, 0, 0))
	assert_ne(a, b)
	assert_eq(GameState.get_dropped(b)["item"], "glowcap")
	assert_eq(GameState.get_dropped("d999"), {})
	var surf := GameState.dropped_in_area("surface")
	assert_eq(surf.size(), 2)
	assert_eq([surf[0]["uid"], surf[1]["uid"]], [a, c])
	assert_eq(GameState.dropped_in_area("below").size(), 1)
	assert_eq(GameState.dropped_in_area("arena").size(), 0)
	GameState.remove_dropped(a)
	GameState.remove_dropped("d999")   # unknown: no error
	assert_eq(GameState.dropped.size(), 2)
	assert_eq(GameState.get_dropped(a), {})


# --- structures -------------------------------------------------------------------------------------------------

func test_structures_create_storages_and_crops() -> void:
	var chest := GameState.add_structure("storage_chest", Vector3(2, 0, 3), 90.0)
	var plot := GameState.add_structure("crop_plot", Vector3(-4, 0, 2), 0.0)
	var bench := GameState.add_structure("workbench", Vector3(5, 0, -1), 180.0, "surface")
	assert_eq(GameState.structures[chest], {"id": "storage_chest", "area": "surface", "pos": [2.0, 0.0, 3.0], "rot": 90.0, "data": {}})
	assert_true(GameState.storages.has(chest), "chest gets a storage")
	assert_eq(GameState.get_storage(chest).size, int(ItemDB.structure("storage_chest")["slots"]))
	assert_true(GameState.get_storage(chest) == GameState.storages[chest], "same object every time")
	assert_false(GameState.crops.has(chest))
	assert_eq(GameState.crops[plot], {"crop": "", "planted_at": 0.0, "tended_minutes": 0.0}, "plot gets a crop record")
	assert_false(GameState.storages.has(plot))
	assert_false(GameState.storages.has(bench))
	assert_false(GameState.crops.has(bench))
	assert_eq(GameState.count_structures("workbench"), 1)
	assert_eq(GameState.count_structures("bed"), 0)
	GameState.remove_structure(chest)
	GameState.remove_structure(plot)
	assert_false(GameState.structures.has(chest))
	assert_false(GameState.storages.has(chest), "storage removed with its chest")
	assert_false(GameState.crops.has(plot), "crop removed with its plot")
	assert_eq(GameState.structures.keys(), [bench])


func test_storage_contents_are_independent_per_chest() -> void:
	var a := GameState.add_structure("storage_chest", Vector3.ZERO, 0.0)
	var b := GameState.add_structure("storage_chest", Vector3(2, 0, 0), 0.0)
	GameState.get_storage(a).add("wood", 30)
	assert_eq(GameState.get_storage(b).count_of("wood"), 0)
	assert_eq(GameState.count_item("wood"), 0, "chest contents are not in the backpack")


# --- companions --------------------------------------------------------------------------------------------------

func _followers() -> Array:
	var out := []
	for id in GameState.companions:
		if GameState.companions[id]["assignment"] == "follow":
			out.append(id)
	return out


func test_befriend_makes_follower() -> void:
	var bf := record(Events.companion_befriended, 1)
	assert_false(GameState.is_befriended("mochi"))
	assert_eq(GameState.companion("mochi")["assignment"], "wild")
	GameState.befriend("mochi")
	assert_true(GameState.is_befriended("mochi"))
	assert_eq(GameState.active_companion, "mochi")
	assert_eq(GameState.companion("mochi")["assignment"], "follow")
	GameState.befriend("mochi")
	assert_eq(bf, [["mochi"]], "befriending twice emits once")


func test_one_follower_rule() -> void:
	var ch := record(Events.companion_assignment_changed, 2)
	GameState.befriend("mochi")
	GameState.befriend("pebble")
	assert_eq(GameState.active_companion, "pebble")
	assert_eq(GameState.companion("mochi")["assignment"], "home", "previous follower sent home")
	assert_true(ch.has(["mochi", "home"]))
	GameState.befriend("lumi")
	GameState.set_companion_assignment("mochi", "follow")
	assert_eq(_followers(), ["mochi"], "exactly one follower")
	assert_eq(GameState.companion("lumi")["assignment"], "home")
	assert_eq(GameState.companion("pebble")["assignment"], "home")
	GameState.set_companion_assignment("mochi", "home")
	assert_eq(GameState.active_companion, "", "no follower after sending it home")
	assert_eq(_followers(), [])


func test_wait_assignment_stores_area_and_position() -> void:
	GameState.befriend("pebble")
	GameState.set_companion_assignment("pebble", "wait", "below", Vector3(1.5, -2, 3))
	var c := GameState.companion("pebble")
	assert_eq(c["assignment"], "wait")
	assert_eq(c["wait_area"], "below")
	assert_eq(c["wait_pos"], [1.5, -2.0, 3.0], "stored as a JSON-friendly array")
	assert_eq(GameState.active_companion, "", "a waiting companion is not following")
	GameState.befriend("lumi")
	assert_eq(GameState.companion("pebble")["assignment"], "wait", "a new follower does not disturb a waiting one")
	GameState.set_companion_assignment("pebble", "wait", "surface")
	assert_null(GameState.companion("pebble")["wait_pos"], "no position given")


func test_bond_levels_from_xp_thresholds() -> void:
	var th: Array = CreaturesData.BOND_XP_PER_LEVEL
	assert_eq(th.size(), 6, "levels 0..5")
	for lvl in th.size():
		GameState.companion("mochi")["bond_xp"] = int(th[lvl])
		assert_eq(GameState.bond_level("mochi"), lvl, "xp %d" % int(th[lvl]))
		if lvl > 0:
			GameState.companion("mochi")["bond_xp"] = int(th[lvl]) - 1
			assert_eq(GameState.bond_level("mochi"), lvl - 1, "xp %d" % (int(th[lvl]) - 1))


func test_add_bond_levels_caps_and_max_bond_counter() -> void:
	GameState.befriend("mochi")
	GameState.befriend("pebble")
	var lv := record(Events.companion_bond_changed, 2)
	GameState.add_bond("mochi", 9)
	assert_eq(lv.size(), 0, "no level-up below 10 xp")
	GameState.add_bond("mochi", 1)
	assert_eq(lv, [["mochi", 1]])
	assert_eq(GameState.get_counter("max_bond"), 1)
	GameState.add_bond("mochi", 40)   # 50 xp -> level 3 (skips 2)
	assert_eq(GameState.bond_level("mochi"), 3)
	assert_eq(lv.back(), ["mochi", 3])
	GameState.add_bond("pebble", 30)   # level 2
	assert_eq(GameState.get_counter("max_bond"), 3, "max over all companions")
	GameState.add_bond("mochi", 500)
	assert_eq(GameState.companion("mochi")["bond_xp"], GameState.max_bond_xp(), "xp capped")
	assert_eq(GameState.max_bond_xp(), 100)
	assert_eq(GameState.bond_level("mochi"), 5)
	assert_eq(GameState.get_counter("max_bond"), 5)
	var n := lv.size()
	GameState.add_bond("mochi", 10)
	assert_eq(lv.size(), n, "no signal at the cap")
	GameState.add_bond("pebble", -1000)
	assert_eq(GameState.companion("pebble")["bond_xp"], 0, "never negative")
	assert_eq(GameState.get_counter("max_bond"), 5, "max_bond never decreases")


# --- clock ------------------------------------------------------------------------------------------------------------

func test_day_hour_time_of_day() -> void:
	_at(1, 0.0)
	assert_eq(GameState.day(), 1)
	assert_almost(GameState.hour(), 0.0)
	_at(3, 18.5)
	assert_eq(GameState.day(), 3)
	assert_almost(GameState.hour(), 18.5)
	assert_almost(GameState.time_of_day(), 18.5 / 24.0)
	GameState.total_minutes = 1439.99
	assert_eq(GameState.day(), 1)
	GameState.total_minutes = 1440.0
	assert_eq(GameState.day(), 2)
	assert_almost(GameState.time_of_day(), 0.0)
	_at(2, 12.0)
	assert_almost(GameState.time_of_day(), 0.5, 0.0001, "noon")


func test_is_night_boundaries() -> void:
	var start := float(Layout.CLOCK["night_start_hour"])
	var end := float(Layout.CLOCK["day_start_hour"])
	_at(1, start - 0.01)
	assert_false(GameState.is_night())
	_at(1, start)
	assert_true(GameState.is_night())
	_at(2, end - 0.01)
	assert_true(GameState.is_night())
	_at(2, end)
	assert_false(GameState.is_night())


func test_advance_clock_day_and_night_rates() -> void:
	var rate := float(Layout.CLOCK["minutes_per_second"])
	var night := float(Layout.CLOCK["night_speedup"])
	_at(1, 12.0)
	var t := GameState.total_minutes
	var ps := float(GameState.stats["play_seconds"])
	GameState.advance_clock(10.0)
	assert_almost(GameState.total_minutes - t, 10.0 * rate, 0.0001, "daytime rate")
	assert_almost(float(GameState.stats["play_seconds"]) - ps, 10.0, 0.0001, "play time counts real seconds")
	_at(1, 21.0)
	t = GameState.total_minutes
	GameState.advance_clock(10.0)
	assert_almost(GameState.total_minutes - t, 10.0 * rate * night, 0.0001, "nights run faster")
	assert_true(night > 1.0, "night speedup shortens nights")


func test_advance_clock_day_rollover_signals() -> void:
	var days := record(Events.day_started, 1)
	var ticks := record(Events.time_of_day_changed, 2)
	_at(1, 23.0 + 59.0 / 60.0)   # 23:59, night rate
	GameState.advance_clock(0.2)   # +0.5 min, still day 1
	assert_eq(days.size(), 0)
	assert_eq(ticks.size(), 0, "less than one in-game minute: no tick yet")
	GameState.advance_clock(0.4)   # +1 min -> 00:00.5 day 2
	assert_eq(GameState.day(), 2)
	assert_eq(days, [[2]], "day_started once with the new day")
	assert_eq(ticks.size(), 1, "tick after a full in-game minute")
	assert_eq(ticks[0][0], 2)
	GameState.advance_clock(0.1)
	assert_eq(days.size(), 1, "no duplicate day_started")


func test_skip_to_morning_after_wake_hour() -> void:
	var days := record(Events.day_started, 1)
	_at(1, 22.0)
	var skipped := GameState.skip_to_morning()
	assert_almost(skipped, 9.0 * 60.0)
	assert_eq(GameState.day(), 2)
	assert_almost(GameState.hour(), 7.0)
	assert_eq(days, [[2]])


func test_skip_to_morning_before_wake_hour_stays_same_day() -> void:
	var days := record(Events.day_started, 1)
	var ticks := record(Events.time_of_day_changed, 2)
	_at(2, 3.0)
	var skipped := GameState.skip_to_morning()
	assert_almost(skipped, 4.0 * 60.0)
	assert_eq(GameState.day(), 2)
	assert_almost(GameState.hour(), 7.0)
	assert_eq(days.size(), 0, "no new day when sleeping after midnight")
	assert_eq(ticks.size(), 1)


func test_skip_to_morning_exactly_at_wake_and_custom_hour() -> void:
	_at(1, 7.0)
	assert_almost(GameState.skip_to_morning(), 1440.0, 0.001, "at exactly the wake hour: the next morning")
	assert_eq(GameState.day(), 2)
	_at(3, 5.0)
	assert_almost(GameState.skip_to_morning(6.0), 60.0)
	assert_almost(GameState.hour(), 6.0)
	assert_eq(GameState.day(), 3)


# --- buffs -----------------------------------------------------------------------------------------------------------

func test_buffs_expire() -> void:
	assert_eq(GameState.buff_mult("stamina_regen"), 1.0, "no buff = 1.0")
	GameState.add_buff("stamina_regen", 1.6, 2.0)
	assert_almost(GameState.buff_mult("stamina_regen"), 1.6)
	GameState._process(1.5)
	assert_almost(GameState.buff_mult("stamina_regen"), 1.6, 0.0001, "still active")
	GameState._process(0.6)
	assert_eq(GameState.buff_mult("stamina_regen"), 1.0, "expired")
	assert_false(GameState.buffs.has("stamina_regen"))


func test_buffs_do_not_tick_when_inactive_and_refresh() -> void:
	GameState.add_buff("stamina_regen", 1.6, 2.0)
	GameState.active = false
	GameState._process(5.0)
	assert_true(GameState.buffs.has("stamina_regen"), "no ticking on the title screen")
	GameState.active = true
	GameState._process(1.9)
	GameState.add_buff("stamina_regen", 1.2, 2.0)   # eating again refreshes
	GameState._process(1.0)
	assert_almost(GameState.buff_mult("stamina_regen"), 1.2)


# --- wardrobe: dye palettes -------------------------------------------------------------------------------

## GameState.unlock_palette (crafting dyes, reward finishes): owned once, announced once, saved and loaded.
func test_unlock_palette_once_and_announced() -> void:
	var changed := record(Events.appearance_changed, 0)
	assert_eq(GameState.wardrobe["palettes"], [], "a new journey owns no dye palettes")
	assert_true(GameState.unlock_palette("rose"), "newly owned")
	assert_eq(GameState.wardrobe["palettes"], ["rose"])
	assert_eq(changed.size(), 1, "Events.appearance_changed when a palette is new")
	assert_false(GameState.unlock_palette("rose"), "already owned")
	assert_false(GameState.unlock_palette(""), "no id")
	assert_eq(changed.size(), 1, "nothing announced for a palette already owned")
	assert_true(GameState.unlock_palette("midnight"))
	assert_eq(GameState.wardrobe["palettes"], ["rose", "midnight"], "kept in the order unlocked")
	var d: Dictionary = json_norm(GameState.to_dict())
	GameState.reset()
	assert_eq(GameState.wardrobe["palettes"], [], "reset clears them")
	GameState.from_dict(d)
	assert_eq(GameState.wardrobe["palettes"], ["rose", "midnight"], "palettes survive save / load")
	assert_false(GameState.unlock_palette("midnight"), "still owned after loading")
	# A damaged save without a palette list: the first unlock repairs it.
	GameState.wardrobe.erase("palettes")
	assert_true(GameState.unlock_palette("cream"))
	assert_eq(GameState.wardrobe["palettes"], ["cream"])
