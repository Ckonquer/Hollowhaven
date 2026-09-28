extends "res://tests/unit/test_core_base.gd"
## GameState schema v2 (docs/CHAPTER_TWO_SPEC.md §3, §8): defaults, tolerant loading of every new section,
## capacity (grow-only backpack and chests, capacity loaded BEFORE the slots), orphans, transactional
## equip/unequip, the reward ledger (grant_once), landmark discovery, companion v2 keys, unknown keys and
## the combined objective accessor + evaluation hooks. Item definitions used here are temporary fakes
## injected into ItemDB (removed after each test), so nothing depends on data/items.gd.

const ChapterLog := preload("res://src/core/chapter_log.gd")
const FAKES := {
	"t_hood_a": {"name": "Hood A", "cat": "armor", "slot": "head", "stack": 1},
	"t_hood_b": {"name": "Hood B", "cat": "armor", "slot": "head", "stack": 1},
	"t_vest": {"name": "Vest", "cat": "armor", "slot": "body", "stack": 1},
	"t_boots_pile": {"name": "Boots", "cat": "armor", "slot": "boots", "stack": 5},
	"t_charm": {"name": "Charm", "cat": "charm", "stack": 1},
	"t_bad_armor": {"name": "Odd", "cat": "armor", "slot": "tail", "stack": 1},
}


func setup() -> void:
	assert_true(SaveSystem.save_dir.begins_with("user://test_saves/"))
	SaveSystem.delete_test_saves()
	for id in FAKES:
		var d: Dictionary = ItemDB.ITEM_DEFAULTS.duplicate()
		d.merge(FAKES[id], true)
		d["id"] = id
		ItemDB._items[id] = d
	fresh_state()


func teardown() -> void:
	for id in FAKES:
		ItemDB._items.erase(id)
	SaveSystem.delete_test_saves()


func _reload() -> void:
	GameState.from_dict(json_norm(GameState.to_dict()))


# --- defaults --------------------------------------------------------------------------------------------------

func test_reset_gives_every_v2_section_its_default() -> void:
	var st := GameState.to_dict()
	var defaults := GameState.v2_section_defaults()
	for k in defaults:
		assert_deep_eq(st[k], defaults[k], "default " + k)
	assert_deep_eq(GameState.appearance, GameState.LEGACY_LOOK_IDS)
	assert_eq(GameState.LEGACY_LOOK_IDS["hair"], "side_braid")
	assert_eq(GameState.LEGACY_LOOK_IDS["palette"], {"primary": "teal", "secondary": "sunflower", "accent": "plum"})
	for id in GameState.companions:
		for k in GameState.COMPANION_V2_DEFAULTS:
			assert_deep_eq(GameState.companions[id][k], GameState.COMPANION_V2_DEFAULTS[k], "%s.%s" % [id, k])
	# Everything goes back to defaults on reset, including a grown backpack.
	GameState.set_backpack_capacity(48)
	GameState.grant_once("rw_a")
	GameState.discover("surface", "haven")
	GameState.orphans.append({"where": "inventory", "slot": 1, "stack": {"id": "x", "count": 1}})
	GameState.extra["k"] = 1
	GameState.reset()
	assert_eq(GameState.inventory.size, 32)
	assert_deep_eq(GameState.to_dict()["ledger"], {})
	assert_deep_eq(GameState.discovered, {})
	assert_deep_eq(GameState.orphans, [])
	assert_deep_eq(GameState.extra, {})


func test_legacy_look_matches_the_appearance_data() -> void:
	# spec §8: GameState.LEGACY_LOOK_IDS and data/appearance.gd LEGACY_LOOK are the same dictionary.
	if not ResourceLoader.exists("res://data/appearance.gd"):
		return   # the data module has not delivered it yet
	var data: Script = load("res://data/appearance.gd")
	var consts: Dictionary = data.get_script_constant_map()
	assert_true(consts.has("LEGACY_LOOK"))
	assert_deep_eq(GameState.LEGACY_LOOK_IDS, consts.get("LEGACY_LOOK", {}), "LEGACY_LOOK")


# --- Inventory ----------------------------------------------------------------------------------------------------

func test_inventory_resize_only_grows() -> void:
	var inv := Inventory.new(4)
	inv.set_slot(3, {"id": "wood", "count": 5})
	var changes := [0]
	inv.changed.connect(func() -> void: changes[0] += 1)
	assert_false(inv.resize(2), "never shrinks")
	assert_false(inv.resize(4))
	assert_eq(inv.size, 4)
	assert_eq(inv.get_slot(3), {"id": "wood", "count": 5})
	assert_eq(changes[0], 0)
	assert_true(inv.resize(6))
	assert_eq(inv.size, 6)
	assert_eq(inv.slots.size(), 6)
	assert_null(inv.get_slot(5))
	assert_eq(changes[0], 1)
	assert_eq(inv.add("stone", 250), 0, "the new slots are usable")
	assert_eq(inv.count_of("stone"), 250)
	inv.reset_to(3)
	assert_eq(inv.size, 3)
	assert_true(inv.is_empty())


func test_from_array_collect_reports_what_it_cannot_place() -> void:
	var inv := Inventory.new(3)
	var rej := inv.from_array_collect([{"id": "wood", "count": 2}, {"id": "ghost", "count": 4}, null,
		{"id": "stone", "count": 1}, {"id": "wood", "count": 0}, "junk", {"id": "moon", "count": 1.0}])
	assert_eq(inv.to_array(), [{"id": "wood", "count": 2}, null, null])
	assert_eq(rej, [{"slot": 1, "stack": {"id": "ghost", "count": 4}}, {"slot": 3, "stack": {"id": "stone", "count": 1}},
		{"slot": 6, "stack": {"id": "moon", "count": 1}}])


# --- capacity -------------------------------------------------------------------------------------------------------

func test_backpack_upgrade_survives_saving_and_loading() -> void:
	var sizes := record(Events.capacity_changed, 2)
	assert_true(GameState.set_backpack_capacity(40))
	assert_false(GameState.set_backpack_capacity(32), "never shrinks")
	assert_eq(sizes, [["backpack", 40]])
	GameState.inventory.set_slot(39, {"id": "wood", "count": 9})
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.inventory.size, 40)
	assert_eq(GameState.inventory.get_slot(39), {"id": "wood", "count": 9})
	assert_eq(GameState.capacity["backpack"], 40)
	assert_true(GameState.set_backpack_capacity(48))
	assert_eq(GameState.to_dict()["inventory"].size(), 48)


func test_loading_never_truncates_the_backpack() -> void:
	var inv := []
	for i in 44:
		inv.append(null)
	inv[43] = {"id": "stone", "count": 3}
	GameState.from_dict(json_norm({"inventory": inv, "capacity": {"backpack": 32, "quiver": 3}}))
	assert_eq(GameState.inventory.size, 44, "grows to hold the saved slots")
	assert_eq(GameState.inventory.get_slot(43), {"id": "stone", "count": 3})
	assert_eq(GameState.capacity, {"backpack": 44, "quiver": 3.0}, "unknown capacity keys kept")
	var huge := []
	for i in 70:
		huge.append({"id": "wood", "count": 1})
	GameState.from_dict({"inventory": huge, "capacity": {"backpack": 1.0e9}})
	assert_eq(GameState.inventory.size, GameState.MAX_BACKPACK, "a damaged capacity is bounded")
	assert_eq(GameState.orphans.size(), 70 - GameState.MAX_BACKPACK, "stacks beyond it are kept as orphans")
	assert_eq(GameState.orphans[0], {"where": "inventory", "slot": GameState.MAX_BACKPACK, "stack": {"id": "wood", "count": 1}})


func test_upgraded_chest_uses_data_slots() -> void:
	var uid := GameState.add_structure("storage_chest", Vector3(1, 0, 1), 0.0)
	assert_eq(GameState.get_storage(uid).size, 20)
	assert_true(GameState.set_storage_capacity(uid, 40))
	assert_false(GameState.set_storage_capacity(uid, 20), "never shrinks")
	assert_false(GameState.set_storage_capacity("nope", 40))
	assert_eq(GameState.structures[uid]["data"]["slots"], 40)
	GameState.get_storage(uid).set_slot(35, {"id": "glowcap", "count": 2})
	_reload()
	assert_eq(GameState.get_storage(uid).size, 40)
	assert_eq(GameState.get_storage(uid).get_slot(35), {"id": "glowcap", "count": 2})
	# A storage created lazily for an upgraded chest has the upgraded size too.
	GameState.storages.erase(uid)
	assert_eq(GameState.get_storage(uid).size, 40)
	GameState.get_storage(uid).set_slot(35, {"id": "glowcap", "count": 2})
	# A saved chest longer than its definition is never truncated.
	var d := GameState.to_dict()
	d["structures"][uid]["data"].erase("slots")
	GameState.from_dict(json_norm(d))
	assert_eq(GameState.get_storage(uid).size, 40)
	assert_eq(GameState.get_storage(uid).get_slot(35), {"id": "glowcap", "count": 2})


# --- orphans ------------------------------------------------------------------------------------------------------

func test_unknown_item_ids_become_orphans_and_are_written_back() -> void:
	var chest := GameState.add_structure("storage_chest", Vector3(1, 0, 1), 0.0)
	var d := GameState.to_dict()
	d["inventory"][4] = {"id": "moon_harp", "count": 2}
	d["storages"][chest][7] = {"id": "star_jelly", "count": 5}
	d["equipment"]["charm"] = "lost_charm"
	d["key_items"]["sky_key"] = 1
	d["dropped"] = [{"uid": "d77", "item": "meteor", "count": 3, "area": "surface", "pos": [1, 2, 3]}]
	GameState.from_dict(json_norm(d))
	assert_null(GameState.inventory.get_slot(4))
	var got := {}
	for o in GameState.orphans:
		got[String(o["stack"]["id"])] = [o["where"], o["slot"], o["stack"]["count"]]
	assert_eq(got["moon_harp"], ["inventory", 4, 2])
	assert_eq(got["star_jelly"], ["storage:" + chest, 7, 5])
	assert_eq(got["lost_charm"], ["equipment", 3, 1])
	assert_eq(got["sky_key"], ["key_items", -1, 1])
	assert_eq(got["meteor"], ["dropped", -1, 3])
	assert_true(GameState.next_uid > 77, "an orphaned drop's uid stays reserved")
	var again: Dictionary = json_norm(GameState.to_dict())
	GameState.from_dict(again)
	assert_deep_eq(json_norm(GameState.to_dict()), again, "stable: nothing duplicated, nothing lost")


## Chest contents saved under a structure this build does not treat as storage, or under a uid whose structure
## record is missing, are written back verbatim (never dropped) and their uids stay reserved.
func test_chest_contents_without_a_usable_structure_are_kept() -> void:
	var d := GameState.to_dict()
	d["structures"]["s40"] = {"id": "table", "area": "surface", "pos": [1, 0, 1], "rot": 0.0, "data": {}}
	d["storages"]["s40"] = [{"id": "wood", "count": 3}, null]
	d["storages"]["s41"] = [null, {"id": "stone", "count": 2}]
	d["storages"]["s42"] = [null, null]
	GameState.from_dict(json_norm(d))
	var out: Dictionary = json_norm(GameState.to_dict())
	assert_eq(out["storages"].get("s40"), json_norm(d["storages"]["s40"]), "a known non-storage structure's saved chest")
	assert_eq(out["storages"].get("s41"), json_norm(d["storages"]["s41"]), "contents without a structure record")
	assert_false(out["storages"].has("s42"), "an empty leftover is not carried around")
	assert_true(GameState.next_uid > 41, "their uids stay reserved")
	assert_ne(GameState.add_structure("storage_chest", Vector3(3, 0, 3), 0.0), "s41")
	GameState.from_dict(out)
	assert_deep_eq(json_norm(GameState.to_dict())["storages"]["s41"], out["storages"]["s41"], "stable")


# --- equipment -------------------------------------------------------------------------------------------------

func test_equip_moves_items_out_of_the_backpack_and_swaps() -> void:
	var changed := record(Events.equipment_changed, 2)
	assert_eq(GameState.equip_slot_for("t_hood_a"), "head")
	assert_eq(GameState.equip_slot_for("t_charm"), "charm")
	assert_eq(GameState.equip_slot_for("wood"), "")
	assert_eq(GameState.equip_slot_for("t_bad_armor"), "")
	assert_false(GameState.equip("t_hood_a"), "not owned")
	assert_eq(GameState.last_equip_error, "You don't have that with you.")
	GameState.give_item("t_hood_a", 1)
	GameState.give_item("t_hood_b", 1)
	GameState.give_item("wood", 5)
	assert_false(GameState.equip("wood"))
	assert_eq(GameState.last_equip_error, "That can't be worn.")
	assert_true(GameState.equip("t_hood_a"))
	assert_eq(GameState.equipped("head"), "t_hood_a")
	assert_eq(GameState.count_item("t_hood_a"), 0, "moved OUT of the backpack")
	assert_eq(GameState.equipped_count("t_hood_a"), 1)
	assert_true(GameState.equip("t_hood_a"), "already worn: nothing to do")
	var b_slot := -1
	for i in GameState.inventory.size:
		var s: Variant = GameState.inventory.get_slot(i)
		if s is Dictionary and s["id"] == "t_hood_b":
			b_slot = i
	assert_true(GameState.equip("t_hood_b", b_slot))
	assert_eq(GameState.equipped("head"), "t_hood_b")
	assert_eq(GameState.inventory.get_slot(b_slot), {"id": "t_hood_a", "count": 1}, "the old piece takes its place")
	assert_eq(changed, [["head", "t_hood_a"], ["head", "t_hood_b"]])
	var obj := ChapterLog.check_objective({"type": "item", "item": "t_hood_b", "count": 1})
	assert_true(obj["done"], "worn items still count as owned for objectives")
	assert_true(ChapterLog.check_objective({"type": "equipped", "slots": ["head", "body", "boots"], "count": 1})["done"])


func test_unequip_with_a_full_backpack_is_refused_and_nothing_is_lost() -> void:
	GameState.give_item("t_vest", 1)
	assert_true(GameState.equip("t_vest"))
	fill_backpack("stone")
	var notes := record(Events.notify, 2)
	assert_false(GameState.unequip("body"))
	assert_eq(GameState.last_equip_error, "Your backpack is full.")
	assert_true(notes.has(["Your backpack is full.", "warn"]), "the player is told")
	assert_eq(GameState.equipped("body"), "t_vest", "still worn")
	assert_eq(GameState.dropped, [], "never dropped")
	GameState.inventory.set_slot(10, null)
	assert_true(GameState.unequip("body"))
	assert_eq(GameState.equipped("body"), "")
	assert_eq(GameState.inventory.get_slot(10), {"id": "t_vest", "count": 1})
	assert_false(GameState.unequip("body"), "nothing worn there")
	assert_false(GameState.unequip("tail"))


func test_equip_swap_that_would_not_fit_changes_nothing() -> void:
	var d: Dictionary = ItemDB.ITEM_DEFAULTS.duplicate()
	d.merge({"id": "t_boots_other", "name": "Other", "cat": "armor", "slot": "boots", "stack": 5}, true)
	ItemDB._items["t_boots_other"] = d
	GameState.give_item("t_boots_pile", 1)
	assert_true(GameState.equip("t_boots_pile"))
	fill_backpack("stone")
	GameState.inventory.set_slot(5, {"id": "t_boots_other", "count": 2})   # taking one does not free the slot
	var before: Array = GameState.inventory.to_array()
	assert_false(GameState.equip("t_boots_other"), "the worn pair would have nowhere to go")
	assert_eq(GameState.last_equip_error, "Your backpack is full.")
	assert_eq(GameState.inventory.to_array(), before, "transactional: the backpack is exactly as it was")
	assert_eq(GameState.equipped("boots"), "t_boots_pile")
	GameState.inventory.set_slot(5, {"id": "t_boots_other", "count": 1})
	assert_true(GameState.equip("t_boots_other"), "a single piece frees its own slot for the swap")
	assert_eq(GameState.inventory.get_slot(5), {"id": "t_boots_pile", "count": 1})
	ItemDB._items.erase("t_boots_other")


func test_equipment_round_trips_and_is_type_checked() -> void:
	GameState.give_item("t_charm", 1)
	assert_true(GameState.equip("t_charm"))
	_reload()
	assert_eq(GameState.equipped("charm"), "t_charm")
	GameState.from_dict({"equipment": {"head": 5, "body": "", "boots": "t_boots_pile", "cape": "future_cape"}})
	assert_eq(GameState.equipment, {"head": "", "body": "", "boots": "t_boots_pile", "charm": "", "cape": "future_cape"})


# --- ledger ------------------------------------------------------------------------------------------------------

func test_grant_once_records_first_then_flags_then_items() -> void:
	var order: Array = []
	listen(Events.flag_set, func(f: String, _v: Variant) -> void: order.append(["flag", f, GameState.ledger.has("rw_first")]))
	listen(Events.item_added, func(id: String, _n: int) -> void: order.append(["item", id, GameState.ledger.has("rw_first")]))
	var granted := record(Events.reward_granted, 1)
	var notes := record(Events.notify, 2)
	GameState.total_minutes = 1234.5
	assert_true(GameState.grant_once("rw_first", {"wood": 5, "stone": 2}, ["got_it"], "A gift!"))
	assert_eq(order, [["flag", "got_it", true], ["item", "wood", true], ["item", "stone", true]])
	assert_eq(GameState.ledger["rw_first"], 1234.5)
	assert_eq(GameState.count_item("wood"), 5)
	assert_true(notes.has(["A gift!", "success"]))
	assert_eq(granted, [["rw_first"]])
	assert_false(GameState.grant_once("rw_first", {"wood": 5}, ["other"], "again"), "exactly once")
	assert_eq(GameState.count_item("wood"), 5)
	assert_false(GameState.flags.has("other"))
	assert_false(GameState.grant_once("", {"wood": 1}))
	assert_true(GameState.has_reward("rw_first"))


func test_grant_once_overflow_drops_persistently_and_unknown_ids_are_kept() -> void:
	fill_backpack("stone")
	assert_true(GameState.grant_once("rw_full", {"wood": 12, "not_an_item_yet": 2}))
	assert_eq(GameState.dropped.size(), 1)
	assert_eq(GameState.dropped[0]["item"], "wood")
	assert_eq(GameState.dropped[0]["count"], 12)
	assert_eq(GameState.orphans, [{"where": "inventory", "slot": -1, "stack": {"id": "not_an_item_yet", "count": 2}}])
	assert_true(SaveSystem.save_game(true))
	GameState.reset()
	assert_true(SaveSystem.load_game())
	assert_eq(GameState.dropped.size(), 1, "the overflow survives saving")
	assert_eq(GameState.orphans.size(), 1)
	assert_false(GameState.grant_once("rw_full", {"wood": 12}), "the ledger survives saving")
	var d := GameState.to_dict()
	d["ledger"] = {"rw_odd": "a string", "rw_inf": INF}
	GameState.from_dict(json_norm(d))
	assert_eq(GameState.ledger, {"rw_odd": 0.0, "rw_inf": 0.0}, "a recorded reward is never forgotten")


# --- discovery, companions, tolerant sections --------------------------------------------------------------------

func test_discover_landmarks() -> void:
	var ev := record(Events.landmark_discovered, 2)
	assert_true(GameState.discover("hallowmere_reach", "orchard"))
	assert_false(GameState.discover("hallowmere_reach", "orchard"))
	assert_false(GameState.discover("", "x"))
	assert_true(GameState.discover("hallowmere_reach", "quarry"))
	assert_eq(ev, [["hallowmere_reach", "orchard"], ["hallowmere_reach", "quarry"]])
	assert_true(GameState.is_discovered("hallowmere_reach", "quarry"))
	assert_false(GameState.is_discovered("surface", "quarry"))
	assert_eq(GameState.discovered_in("hallowmere_reach"), ["orchard", "quarry"])
	_reload()
	assert_eq(GameState.discovered_in("hallowmere_reach"), ["orchard", "quarry"])


func test_companion_v2_keys_are_kept_and_repaired() -> void:
	var d := GameState.to_dict()
	d["companions"]["mochi"].merge({"combat_mode": "close", "skill_ready_at": 42.5, "home_spot": [1, 2, 3],
		"ribbon": "comfort_ribbon", "home_task": "garden", "mood": "sleepy"}, true)
	d["companions"]["pebble"].merge({"combat_mode": "berserk", "skill_ready_at": "soon", "home_spot": [1, 2],
		"ribbon": 5, "home_task": null}, true)
	d["companions"]["lumi"].erase("combat_mode")
	GameState.from_dict(json_norm(d))
	var m := GameState.companion("mochi")
	assert_eq([m["combat_mode"], m["skill_ready_at"], m["home_spot"], m["ribbon"], m["home_task"], m["mood"]],
		["close", 42.5, [1.0, 2.0, 3.0], "comfort_ribbon", "garden", "sleepy"])
	var p := GameState.companion("pebble")
	assert_eq([p["combat_mode"], p["skill_ready_at"], p["home_spot"], p["ribbon"], p["home_task"]], ["assist", 0.0, null, "", ""])
	assert_eq(GameState.companion("lumi")["combat_mode"], "assist")


func test_every_v2_section_tolerates_wrong_types() -> void:
	GameState.from_dict({"schema": "x", "appearance": 5, "wardrobe": [], "equipment": "x", "capacity": "y",
		"optional": [], "chapter2": 7, "ledger": [], "mastery": {"gathering": "lots", "seen": {"gathering": [1, "oak", "oak"]}, "legacy_credit": "yes"},
		"discovered": {"a": "b", "c": ["x", 5, "x"]}, "trials": {"t": 5, "u": {"clears": -3, "best_seconds": "fast"}},
		"orphans": [1, {"where": 5}, {"where": "inventory", "stack": {"id": 7}}, {"where": "inventory", "slot": "2", "stack": {"id": "q", "count": "many"}}],
		"stations": 3})
	var defaults := GameState.v2_section_defaults()
	for k in ["appearance", "wardrobe", "equipment", "capacity", "optional", "chapter2", "ledger", "stations"]:
		assert_deep_eq(GameState.to_dict()[k], defaults[k], k)
	assert_eq(GameState.mastery["gathering"], 0)
	assert_eq(GameState.mastery["seen"]["gathering"], ["oak"])
	assert_eq(GameState.mastery["legacy_credit"], "yes", "any recorded credit is kept, so it is never applied twice")
	assert_eq(GameState.discovered, {"a": [], "c": ["x"]})
	assert_eq(GameState.trials, {"u": {"clears": 0, "best_seconds": 0.0}})
	assert_eq(GameState.orphans, [{"where": "inventory", "slot": -1, "stack": {"id": "q", "count": 1}}])


func test_wardrobe_appearance_and_mastery_keep_unknown_keys() -> void:
	GameState.from_dict(json_norm({"appearance": {"hair": "bob", "eyes": 3, "palette": {"primary": "rose", "accent": 1}, "tail": "fox"},
		"wardrobe": {"owned": ["a", "a", "b"], "presets": [{"name": "P", "look": {"hair": "bob"}}, {"name": "bad"}], "notice_shown": true, "shelf": 2},
		"mastery": {"hearthcraft": 7, "fishing": 3, "legacy_credit": {"applied_at": 5}}}))
	assert_eq(GameState.appearance["hair"], "bob")
	assert_eq(GameState.appearance["eyes"], "eye_1", "a wrong type keeps the default")
	assert_eq(GameState.appearance["palette"], {"primary": "rose", "secondary": "sunflower", "accent": "plum"})
	assert_eq(GameState.appearance["tail"], "fox")
	assert_eq(GameState.wardrobe["owned"], ["a", "b"])
	assert_eq(GameState.wardrobe["presets"], [{"name": "P", "look": {"hair": "bob"}}])
	assert_eq(GameState.wardrobe["notice_shown"], true)
	assert_eq(GameState.wardrobe["shelf"], 2.0)
	assert_eq(GameState.mastery["hearthcraft"], 7)
	assert_eq(GameState.mastery["fishing"], 3.0)
	assert_eq(GameState.mastery["legacy_credit"], {"applied_at": 5.0}, "a recorded legacy credit is never reset")
	assert_true(GameState.unlock_pattern("c"))
	assert_false(GameState.unlock_pattern("c"))


## MP §2.3: loading again must never re-apply a one-time bonus. Only a missing/null legacy_credit means
## "not applied yet"; every recorded value survives, whatever its shape.
func test_mastery_legacy_credit_is_never_forgotten() -> void:
	var cases := [[null, false], [false, false], [true, true], [0, 0.0], [12.5, 12.5], ["applied", "applied"],
		[{"applied_at": 5}, {"applied_at": 5.0}], [[1], [1.0]]]
	for c in cases:
		GameState.from_dict(json_norm({"mastery": {"legacy_credit": c[0]}}))
		assert_deep_eq(GameState.mastery["legacy_credit"], c[1], "legacy_credit %s" % str(c[0]))
		GameState.from_dict(json_norm(GameState.to_dict()))
		assert_deep_eq(GameState.mastery["legacy_credit"], c[1], "legacy_credit %s after a round trip" % str(c[0]))
	GameState.from_dict({"mastery": {"legacy_credit": INF}})
	assert_eq(GameState.mastery["legacy_credit"], true, "an unusable recorded value still counts as applied")
	GameState.from_dict({"mastery": {}})
	assert_eq(GameState.mastery["legacy_credit"], false)


## Buff records keep extra keys (spec §9: food buffs carry a "family"), numbers normalised.
func test_buff_records_keep_extra_keys() -> void:
	GameState.add_buff("food_warm", 1.2, 90.0)
	GameState.buffs["food_warm"]["family"] = "soup"
	GameState.from_dict(json_norm(GameState.to_dict()))
	assert_eq(GameState.buffs["food_warm"], {"mult": 1.2, "remaining": 90.0, "family": "soup"})
	assert_eq(typeof(GameState.buffs["food_warm"]["remaining"]), TYPE_FLOAT)
	GameState.from_dict({"buffs": {"a": {"mult": 1, "remaining": 5, "family": "x"}, "b": {"mult": 1.0, "remaining": 0.0}}})
	assert_eq(GameState.buffs, {"a": {"mult": 1.0, "remaining": 5.0, "family": "x"}}, "expired buffs are still dropped")


func test_unknown_top_level_keys_round_trip() -> void:
	GameState.from_dict(json_norm({"future_section": {"a": [1, 2]}, "player_name": "K"}))
	assert_eq(GameState.extra, {"future_section": {"a": [1.0, 2.0]}})
	var d := GameState.to_dict()
	assert_eq(d["future_section"], {"a": [1.0, 2.0]})
	assert_eq(d["player_name"], "K")


# --- combined objective & evaluation hooks ------------------------------------------------------------------------

func test_current_objective_combines_both_layers() -> void:
	var o := GameState.current_objective()
	assert_eq([o["source"], o["chapter"], o["id"], o["title"]], ["legacy", 1, "wake", "A Dim Haven"])
	assert_eq(o["status"][0]["step"], "wake")
	assert_eq([o["target"], o["target_area"]], ["haven", "surface"])
	for s in o["steps"]:
		assert_true(s.get("target", "") is String, "legacy steps: target is a landmark id String")
	GameState.set_flag("chapter_one_complete")
	assert_eq(GameState.current_objective()["source"], "legacy", "available is not accepted")
	GameState.set_flag("ch2_accepted")
	GameState.chapter2.evaluate()
	o = GameState.current_objective()
	assert_eq([o["source"], o["chapter"], o["id"], o["title"]], ["chapter2", 2, "ch2_waygate", "The Hallowmere Way"])
	assert_eq([o["target"], o["target_area"]], ["ruin", "surface"])
	for s in o["steps"]:
		assert_true(s.get("target", "") is String, "Chapter Two steps: the same target shape as the legacy steps")
	for f in ["ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map", "ch2_found_orchard_lamp",
			"ch2_found_quarry_lamp", "ch2_found_manor_lamp"]:
		GameState.set_flag(f)
	GameState.chapter2.evaluate()
	o = GameState.current_objective()
	assert_eq(o["group"], "lamps")
	assert_eq(o["title"], "Three Roads, Three Lamps")
	assert_eq(o["steps"].size(), 3)
	assert_eq([o["target"], o["target_area"]], ["hr_orchard", "hallowmere_reach"])
	var step_ids: Array = []
	for row in o["status"]:
		step_ids.append(row["step"])
	assert_eq(step_ids, ["ch2_orchard", "ch2_quarry", "ch2_manor"])


func test_quest_evaluation_includes_chapter_two_and_optional_goals() -> void:
	GameState.set_flag("chapter_one_complete")
	GameState.set_flag("ch2_accepted")
	GameState.set_flag("c1x_look_chosen")
	GameState.request_quest_eval()
	await wait_frames(2)
	assert_true(GameState.chapter2.is_done("ch2_light_beyond"))
	assert_true(GameState.optional_goals.is_done("opt_look_of_your_own"))
	# State set directly (no signal): the 1 s poll catches it.
	GameState.flags["ch2_waygate_repaired"] = true
	GameState.flags["c1x_tailor_cache"] = true
	GameState._process(1.1)
	await wait_frames(2)
	assert_true(GameState.chapter2.is_done("ch2_waygate"))
	assert_true(GameState.optional_goals.is_done("opt_tailors_cache"))
