extends "res://tests/unit/test_core_base.gd"
## Data-dependency simulation of Chapter One. Starting from a new game (empty backpack) every
## resource the quest chain needs must be obtainable WITHOUT already owning the thing being made
## (no circular requirement), using only the gathering rules of GAME_SPEC.md:
##   by hand (E): sticks (wood), stones, grass (fiber), berry bushes (berries)
##   trees need an axe; rocks and ore need a pickaxe; glowcaps/silk/echo shards exist only below;
##   enemies drop their data/enemies.gd drops once Krystal can fight (any tool or weapon);
##   crops grow from seeds in a placed crop plot; Pebble brings shiny pebbles once befriended.
## Part 1 is a pure data reachability walk; part 2 plays the chapter through GameState with the
## real recipes and a ledger that proves every quest reward arrives exactly once.

const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const CreaturesData := preload("res://data/creatures.gd")
const EnemiesData := preload("res://data/enemies.gd")

const HAND := ["wood", "stone", "fiber", "berries"]
const BY_TOOL := {"axe": ["wood"], "pickaxe": ["stone", "copper_ore"]}
const BELOW_ONLY := ["glowcap", "silk", "echo_shard"]


# =============================== part 1: data reachability ===============================

func _new_sim() -> Dictionary:
	return {"tools": {}, "armed": false, "stations": {"hand": true, "campfire": true}, "flags": {},
		"friends": {}, "placed": {}, "owned": {}, "keys": {}, "rewards": {}}


## Items obtainable right now without crafting.
func _raw(sim: Dictionary) -> Dictionary:
	var out := {}
	for it in HAND:
		out[it] = true
	for kind in BY_TOOL:
		if sim["tools"].has(kind):
			for it in BY_TOOL[kind]:
				out[it] = true
	var below: bool = sim["flags"].has("entered_below")
	if below:
		for it in BELOW_ONLY:
			out[it] = true
	for eid in EnemiesData.ENEMIES:
		var e: Dictionary = EnemiesData.ENEMIES[eid]
		if sim["armed"] and (e["area"] == "surface" or below):
			for drop in e.get("drops", []):
				out[drop["item"]] = true
	if sim["friends"].has("pebble"):
		out["shiny_pebble"] = true
	for it in sim["rewards"]:
		out[it] = true
	if sim["placed"].has("crop_plot"):
		for cid in StructuresData.CROPS:
			var c: Dictionary = StructuresData.CROPS[cid]
			if out.has(c["seed"]):
				for y in c["yield"]:
					out[y] = true
	return out


func _can_obtain(item: String, sim: Dictionary, visiting: Dictionary = {}) -> bool:
	if _raw(sim).has(item):
		return true
	if visiting.has(item):
		return false   # would need itself
	var v := visiting.duplicate()
	v[item] = true
	for rid in RecipesData.RECIPES:
		var r: Dictionary = RecipesData.RECIPES[rid]
		if r["result"] != item or not sim["stations"].has(r["station"]):
			continue
		if String(r["unlock"]) != "" and not sim["flags"].has(r["unlock"]):
			continue
		var ok := true
		for ing in r["ingredients"]:
			if not _can_obtain(ing, sim, v):
				ok = false
				break
		if ok:
			return true
	return false


## World rules for story flags (what the player must have to trigger them).
func _flag_reachable(flag: String, sim: Dictionary) -> bool:
	match flag:
		"read_ward_intro", "read_ward_warning":
			return true
		"ruin_cleared":
			return sim["armed"]
		"mine_opened":
			return sim["tools"].has("pickaxe")   # the rubble must be mined
		"entered_below":
			return sim["flags"].has("mine_opened")
		"reached_silk_hollows":
			return sim["keys"].has("foreman_key")   # the lower gate needs the key
		"ward_restored":
			return sim["keys"].has("heartseed")
	fail("no world rule for quest flag '%s' (add one to this test)" % flag)
	return false


func _objective_reachable(o: Dictionary, sim: Dictionary) -> bool:
	match String(o["type"]):
		"flag":
			return _flag_reachable(o["flag"], sim)
		"item":
			var it: String = o["item"]
			if it == "foreman_key":
				return sim["flags"].has("entered_below")   # guaranteed pickup in the Foreman's Office
			if it == "heartseed":
				return sim["flags"].has("reached_silk_hollows") and sim["owned"].has("lantern")   # braziers need the lantern
			return _can_obtain(it, sim)
		"item_any":
			for it in o["items"]:
				if _can_obtain(it, sim):
					return true
			return false
		"placed":
			return _can_obtain(ItemDB.structure(o["structure"])["item"], sim)
		"befriended":
			var bf: Dictionary = ItemDB.creature(o["creature"])["befriend"]
			match String(bf["type"]):
				"offer_item":
					return _can_obtain(bf["item"], sim)
				"free_from_boulder":
					return sim["tools"].has("pickaxe")
				"rescue":
					return sim["flags"].has(bf["flag"])
			return false
		"counter":
			match String(o["counter"]):
				"trees_felled":
					return sim["tools"].has("axe")
				"crops_planted":
					return sim["placed"].has("crop_plot") and _can_obtain("sweetroot_seeds", sim)
				"max_bond":
					return not sim["friends"].is_empty()
			fail("no world rule for counter '%s'" % o["counter"])
	return false


func _apply(o: Dictionary, sim: Dictionary) -> void:
	match String(o["type"]):
		"flag":
			sim["flags"][o["flag"]] = true
		"item", "item_any":
			var it: String = o["item"] if o.has("item") else ""
			if it == "":
				for cand in o["items"]:
					if _can_obtain(cand, sim):
						it = cand
						break
			sim["owned"][it] = true
			if ItemDB.is_quest_item(it):
				sim["keys"][it] = true
			var d := ItemDB.item(it)
			if String(d["tool"]) != "":
				sim["tools"][d["tool"]] = true
			if d["cat"] == "tool" or d["cat"] == "weapon":
				sim["armed"] = true
		"placed":
			sim["placed"][o["structure"]] = true
			var st: Dictionary = ItemDB.structure(o["structure"])
			if st.get("interact", "") == "station":
				sim["stations"][st["station"]] = true
		"befriended":
			sim["friends"][o["creature"]] = true


## Walks the quest chain; objectives inside a step may be done in any order (fixpoint).
## Returns the id of the first blocked step, or "" if the whole chain is reachable.
func _walk_chain(sim: Dictionary, stop_before: String = "") -> String:
	for step in QuestsData.STEPS:
		if step["id"] == stop_before:
			return ""
		var pending: Array = step["objectives"].duplicate()
		var progress := true
		while not pending.is_empty() and progress:
			progress = false
			for o in pending.duplicate():
				if _objective_reachable(o, sim):
					_apply(o, sim)
					pending.erase(o)
					progress = true
		if not pending.is_empty():
			return String(step["id"])
		var oc: Dictionary = step.get("on_complete", {})
		for it in oc.get("give", {}):
			sim["rewards"][it] = true
		for f in oc.get("flags", []):
			sim["flags"][f] = true
	return ""


func test_simulator_is_not_vacuous() -> void:
	var sim := _new_sim()
	assert_false(_can_obtain("copper_ore", sim), "ore needs a pickaxe")
	assert_false(_can_obtain("lantern", sim), "lantern needs a workbench and copper")
	assert_false(_can_obtain("glowcap", sim), "glowcaps only grow below")
	assert_false(_can_obtain("heartbloom_lamp", sim), "locked recipe")
	assert_false(_can_obtain("sweetroot", sim), "no crops without a plot and seeds")
	assert_false(_flag_reachable("ruin_cleared", sim), "cannot fight empty-handed")
	assert_false(_objective_reachable({"type": "befriended", "creature": "pebble"}, sim))
	assert_true(_can_obtain("berry_snack", sim), "hand recipe from hand materials")
	assert_eq(_walk_chain(_new_sim(), "craft_axe"), "")
	var stuck := _new_sim()
	stuck["stations"].erase("hand")   # without hand crafting the chain must block at the axe
	assert_eq(_walk_chain(stuck), "craft_axe", "a missing capability is reported at the right step")


func test_new_game_starts_with_nothing() -> void:
	GameState.new_game()
	assert_true(GameState.inventory.is_empty())
	assert_eq(GameState.key_items, {})
	assert_eq(GameState.count_structures("workbench"), 0, "no free workbench either")


func test_whole_quest_chain_is_reachable_from_a_new_game() -> void:
	var blocked := _walk_chain(_new_sim())
	assert_eq(blocked, "", "every step reachable in order (blocked at '%s')" % blocked)


func test_first_tools_need_only_hand_materials() -> void:
	for rid in ["stone_axe", "stone_pickaxe"]:
		var r := ItemDB.recipe(rid)
		assert_eq(r["station"], "hand", rid + " is craftable anywhere")
		assert_eq(r["unlock"], "", rid + " is known from the start")
		for ing in r["ingredients"]:
			assert_true(HAND.has(ing), "%s needs %s, which must be hand-gatherable" % [rid, ing])
	assert_false(ItemDB.recipe("stone_pickaxe")["ingredients"].has("copper_ore"), "the pickaxe never needs the ore it mines")
	assert_true(_can_obtain("stone_pickaxe", _new_sim()), "pickaxe craftable on day one")
	assert_true(_can_obtain("workbench", _new_sim()), "workbench craftable on day one")


func test_mochi_befriend_item_is_hand_gatherable() -> void:
	var bf: Dictionary = CreaturesData.CREATURES["mochi"]["befriend"]
	assert_eq(bf["type"], "offer_item")
	assert_true(HAND.has(bf["item"]), "Mochi's %s can be picked by hand" % bf["item"])
	assert_true(int(bf["count"]) <= ItemDB.stack_max(bf["item"]))


func test_mine_rubble_needs_only_a_hand_craftable_pickaxe() -> void:
	var sim := _new_sim()
	assert_false(_flag_reachable("mine_opened", sim), "not without a pickaxe")
	assert_true(_can_obtain("stone_pickaxe", sim))
	_apply({"type": "item", "item": "stone_pickaxe"}, sim)
	assert_true(_flag_reachable("mine_opened", sim))


func test_sword_and_lantern_need_only_pre_mine_materials() -> void:
	var sim := _new_sim()
	assert_eq(_walk_chain(sim, "descend"), "", "chain reachable up to the mine")
	assert_false(sim["flags"].has("entered_below"))
	for rid in ["copper_sword", "lantern"]:
		assert_true(_can_obtain(rid, sim), rid + " obtainable before entering the mine")
		for ing in ItemDB.recipe(rid)["ingredients"]:
			assert_false(BELOW_ONLY.has(ing), "%s must not need below-only %s" % [rid, ing])
	for it in ["berry_snack", "hearty_stew"]:
		assert_true(_can_obtain(it, sim), it + " (healing food) obtainable before the mine")


func test_no_recipe_requires_itself_through_a_cycle() -> void:
	var graph := {}   # item -> [ingredients of every recipe producing it]
	for rid in RecipesData.RECIPES:
		var r: Dictionary = RecipesData.RECIPES[rid]
		if not graph.has(r["result"]):
			graph[r["result"]] = []
		for ing in r["ingredients"]:
			graph[r["result"]].append(ing)
	for start in graph:
		var stack: Array = [[start, []]]
		while not stack.is_empty():
			var cur: Array = stack.pop_back()
			for ing in graph.get(cur[0], []):
				var path: Array = cur[1] + [cur[0]]
				assert_false(ing == start, "recipe cycle: %s -> %s" % [" -> ".join(path), ing])
				if ing != start and not path.has(ing) and path.size() < 16:
					stack.append([ing, path])


func test_every_item_has_a_source() -> void:
	var sim := _new_sim()
	_walk_chain(sim)   # end of chapter: everything unlocked
	sim["flags"]["entered_below"] = true
	var quest_given := {"foreman_key": true, "heartseed": true}
	for id in ItemDB.all_item_ids():
		assert_true(_can_obtain(id, sim) or quest_given.has(id), id + " can be obtained somehow")


func test_mandatory_crafting_budget_is_reasonable() -> void:
	# Raw materials for everything the chain requires to be crafted (not counting optional décor).
	var needs := {}
	for rid in ["stone_axe", "stone_pickaxe", "workbench", "bed", "crop_plot", "lantern", "berry_snack", "berry_snack"]:
		var r := ItemDB.recipe(rid)
		for ing in r["ingredients"]:
			needs[ing] = int(needs.get(ing, 0)) + int(r["ingredients"][ing])
	needs["berries"] = int(needs.get("berries", 0)) + int(CreaturesData.CREATURES["mochi"]["befriend"]["count"])
	var total := 0
	for it in needs:
		total += int(needs[it])
		assert_true(HAND.has(it) or it == "copper_ore", "%s is a basic surface material" % it)
	assert_true(total <= 120, "mandatory gathering stays cozy (%d items)" % total)
	assert_true(int(needs.get("copper_ore", 0)) <= 8, "little copper needed before the mine")


# =============================== part 2: GameState playthrough ===============================

var _ledger: Dictionary = {}


func _book(item: String, n: int) -> void:
	_ledger[item] = int(_ledger.get(item, 0)) + n


func _legal_source(item: String) -> bool:
	if HAND.has(item):
		return true
	if item == "copper_ore":
		return GameState.best_tool("pickaxe") != ""
	if BELOW_ONLY.has(item):
		return bool(GameState.get_flag("entered_below"))
	if item == "shiny_pebble":
		return GameState.is_befriended("pebble")
	if item == "sweetroot":
		for uid in GameState.crops:
			if String(GameState.crops[uid]["crop"]) == "sweetroot":
				var ripe_at: float = float(GameState.crops[uid]["planted_at"]) + float(ItemDB.crop("sweetroot")["grow_minutes"])
				if GameState.total_minutes >= ripe_at:
					return true
	return false


func _gather(item: String, n: int) -> void:
	assert_true(_legal_source(item), "can gather %s at step %s" % [item, GameState.quests.current_id()])
	GameState.give_item(item, n)
	_book(item, n)


func _ensure(item: String, n: int) -> void:
	var short := n - GameState.count_item(item)
	if short > 0:
		_gather(item, short)


func _craft(rid: String, times: int = 1) -> void:
	var r := ItemDB.recipe(rid)
	for t in times:
		var station: String = r["station"]
		var here: bool = station == "hand" or station == "campfire" or GameState.count_structures(station) > 0
		assert_true(here, "%s: station %s available" % [rid, station])
		assert_true(ItemDB.recipe_known(rid), rid + " known")
		for ing in r["ingredients"]:
			_ensure(ing, int(r["ingredients"][ing]))
		for ing in r["ingredients"]:
			assert_true(GameState.take_item(ing, int(r["ingredients"][ing])), "%s consumes %s" % [rid, ing])
			_book(ing, -int(r["ingredients"][ing]))
		assert_eq(GameState.give_item(r["result"], int(r["count"])), int(r["count"]), rid + " result fits")
		_book(r["result"], int(r["count"]))
		Events.crafted.emit(rid, r["result"], int(r["count"]))


func _place(item: String, pos: Vector3) -> String:
	assert_true(GameState.take_item(item, 1), "have a %s to place" % item)
	_book(item, -1)
	var sid: String = ItemDB.item(item)["place"]
	var uid := GameState.add_structure(sid, pos, 0.0)
	Events.structure_placed.emit(uid, sid)
	return uid


func _step_should_be(id: String) -> void:
	await wait_frames(2)   # deferred, signal-driven evaluation (as in the game)
	assert_eq(GameState.quests.current_id(), id)


func test_play_the_chapter_economically_with_game_state() -> void:
	GameState.new_game()
	_ledger = {}
	var completed := record(Events.quest_step_completed, 1)
	await _step_should_be("wake")
	GameState.set_flag("read_ward_intro")
	await _step_should_be("gather_basics")
	_gather("wood", 3)
	_gather("stone", 2)
	_gather("fiber", 2)
	await _step_should_be("craft_axe")
	_craft("stone_axe")
	await _step_should_be("chop")
	for tree in 2:
		assert_ne(GameState.best_tool("axe"), "", "felling needs the axe")
		GameState.add_counter("trees_felled")
		_gather("wood", 4)
	_ensure("wood", 10)
	await _step_should_be("workbench")
	_craft("workbench")
	_place("workbench", Vector3(4, 0, -2))
	await _step_should_be("mochi")
	_ensure("berries", 3)
	assert_true(GameState.take_item("berries", 3), "offer Mochi 3 berries")
	_book("berries", -3)
	GameState.befriend("mochi")
	await _step_should_be("pebble")
	_craft("stone_pickaxe")
	assert_ne(GameState.best_tool("pickaxe"), "", "the boulder needs the pickaxe")
	GameState.befriend("pebble")
	await _step_should_be("home")
	_craft("bed")
	_craft("crop_plot")
	_place("bed", Vector3(-6, 0, 4))
	var plot := _place("crop_plot", Vector3(6, 0, 6))
	assert_true(GameState.take_item("sweetroot_seeds", 1), "plant a seed from Mochi's gift")
	_book("sweetroot_seeds", -1)
	GameState.crops[plot] = {"crop": "sweetroot", "planted_at": GameState.total_minutes, "tended_minutes": 0.0}
	GameState.add_counter("crops_planted")
	await _step_should_be("lumi")
	assert_ne(GameState.best_weapon(), "", "something to fight the Bramblings with")
	_gather("fiber", 2)   # brambling drop
	GameState.set_flag("ruin_cleared")
	GameState.befriend("lumi")
	await _step_should_be("prepare")
	GameState.set_flag("read_ward_warning")
	_craft("lantern")
	_craft("copper_sword")   # optional, but must be possible before the mine
	_craft("berry_snack", 2)
	await _step_should_be("descend")
	assert_ne(GameState.best_tool("pickaxe"), "")
	GameState.deplete("mine_rubble", -1.0)
	GameState.set_flag("mine_opened")
	GameState.set_flag("entered_below")
	await _step_should_be("old_mine")
	GameState.give_item("foreman_key", 1)
	_book("foreman_key", 1)
	await _step_should_be("deeper")
	GameState.set_flag("reached_silk_hollows")
	await _step_should_be("silk")
	assert_true(GameState.has_item("lantern"), "the braziers need the lantern")
	GameState.give_item("heartseed", 1)
	_book("heartseed", 1)
	await _step_should_be("return")
	assert_true(GameState.take_item("heartseed", 1))
	_book("heartseed", -1)
	GameState.set_flag("ward_restored")
	await _step_should_be("free_play")
	assert_true(GameState.quests.is_chapter_complete())
	assert_eq(GameState.get_flag("chapter_one_complete"), true)
	assert_eq(GameState.count_item("haven_banner"), 1, "banner granted once")
	assert_eq(GameState.count_item("sweetroot_seeds"), 2, "3 seeds from Mochi, 1 planted")
	# the harvest feeds the campfire recipes
	GameState.skip_to_morning()
	_gather("sweetroot", 2)
	_craft("hearty_stew")
	# free play: the new recipe and max bond
	assert_true(ItemDB.recipe_known("heartbloom_lamp"))
	_craft("heartbloom_lamp")
	_place("heartbloom_lamp", Vector3(-3, 0, -3))
	GameState.add_bond("mochi", 100)
	await wait_frames(2)
	assert_eq(GameState.quests.index, QuestsData.STEPS.size(), "optional goals done too")
	assert_eq(completed.size(), QuestsData.STEPS.size(), "each step completed once")
	# Ledger: backpack/pouch = everything gathered/crafted + each quest reward exactly once.
	for c in completed:
		var give: Dictionary = QuestLog.new().step_by_id(c[0]).get("on_complete", {}).get("give", {})
		for it in give:
			_book(it, int(give[it]))
	for id in ItemDB.all_item_ids():
		assert_eq(GameState.count_item(id), int(_ledger.get(id, 0)), "ledger for " + id)
	assert_eq(GameState.dropped.size(), 0, "the chapter never overflows a 32-slot backpack")
	# and a reload changes nothing
	assert_true(SaveSystem.save_game())
	GameState.reset()
	assert_true(SaveSystem.load_game())
	await wait_frames(2)
	for id in ItemDB.all_item_ids():
		assert_eq(GameState.count_item(id), int(_ledger.get(id, 0)), "after reload: " + id)
