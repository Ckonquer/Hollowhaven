extends "res://tests/test_case.gd"
## Obtainability and dependency validation of the whole catalogue (MP 5.2 / 16, docs/CHAPTER_TWO_SPEC.md 4):
##  * data/sources.gd declares every item's sources and they match the real recipes / crops / nodes / drops /
##    rewards in both directions;
##  * a fixpoint simulation starting from raw sources (harvestable nodes with their tool tiers and access flags,
##    crops, companion gifts, enemy drops) proves every item is obtainable with NO circular dependency, stations
##    must themselves be buildable, recipes need their unlock flags;
##  * story-required items have guaranteed, non-drop sources reachable before the gate that needs them;
##  * the MP 16 tier chain: iron ore with the stone pick, Moon Crystal only with a tier-3 pick, Moonsteel from
##    iron + crystal + echo shard; basic building and Chapter One optional crafting need no Chapter Two story.

const ItemsData := preload("res://data/items.gd")
const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const EnemiesData := preload("res://data/enemies.gd")
const CreaturesData := preload("res://data/creatures.gd")
const UnlocksData := preload("res://data/unlocks.gd")
const SourcesData := preload("res://data/sources.gd")
const AppearanceData := preload("res://data/appearance.gd")

const KINDS := ["gather", "crop", "recipe", "station", "drop", "reward", "pickup", "companion"]
const TOOLS := ["hand", "axe", "pickaxe"]
## Flags that world / story systems set outside the reward bundles (spec flags and legacy ones).
const WORLD_FLAGS := ["ward_restored", "ch2_winch_repaired", "ch2_choir_defeated", "chapter_one_complete", "weaver_defeated"]
## "Already paid" markers a content bundle sets for its own module (never recipe unlocks, read by nobody else).
const CONTENT_MARKER_FLAGS := {"rw_hr_chime_trail": ["hr_chime_trail_done"], "rw_hw_throat_supplies": ["hw_throat_supplies"]}
const ZONE_PREFIX := {"hallowmere_reach": "hr_", "hushed_works": "hw_", "tobin_annex": "ta_", "moonveil_manor": "mm_"}
const CHAPTER_ONE_AREAS := ["surface", "below"]


func before_each() -> void:
	fresh_state()


# ================================== simulator ==================================

## opts: flags (Dictionary of allowed flags), areas (Array; empty = all), drops (bool), rewards (bool, reward
## bundles + fixed pickups), companions (bool), guaranteed_only (bool: node drops with chance 1 only),
## exclude (Dictionary of recipe ids that may not be used), mastery (bool: mastery-gated recipes allowed).
func _reach(opts: Dictionary) -> Dictionary:
	var flags: Dictionary = opts.get("flags", {})
	var areas: Array = opts.get("areas", [])
	var exclude: Dictionary = opts.get("exclude", {})
	var got := {}
	var stations := {"hand": true, "campfire": true}
	var tier := {"hand": 99, "axe": 0, "pickaxe": 0}
	var armed := false
	var changed := true
	var guard := 0
	while changed and guard < 64:
		changed = false
		guard += 1
		for kind in SourcesData.NODES:
			var n: Dictionary = SourcesData.NODES[kind]
			var flag := String(n.get("access_flag", ""))
			if flag != "" and not flags.has(flag):
				continue
			if not _in_areas(n["where"].keys(), areas):
				continue
			if int(tier[String(n["tool"])]) < maxi(int(n["min_tier"]), 1):
				continue
			for d in n["drops"]:
				if bool(opts.get("guaranteed_only", false)) and float(d["chance"]) < 1.0:
					continue
				changed = _add(got, String(d["item"])) or changed
		if got.has("crop_plot") or got.has("sturdy_planter"):
			for cid in StructuresData.CROPS:
				var c: Dictionary = StructuresData.CROPS[cid]
				if got.has(c["seed"]):
					for y in c["yield"]:
						changed = _add(got, String(y)) or changed
		if bool(opts.get("drops", false)) and armed:
			for eid in EnemiesData.ENEMIES:
				var e: Dictionary = EnemiesData.ENEMIES[eid]
				if _in_areas(e.get("areas", [e["area"]]), areas):
					for d in e.get("drops", []):
						changed = _add(got, String(d["item"])) or changed
		if bool(opts.get("companions", false)):
			for s_item in SourcesData.ITEM_SOURCES:
				for s in SourcesData.ITEM_SOURCES[s_item]:
					if String(s["kind"]) == "companion":
						changed = _add(got, String(s_item)) or changed
		if bool(opts.get("rewards", false)):
			for rw in ItemDB.all_reward_ids():
				for it in ItemDB.reward_bundle(String(rw))["items"]:
					changed = _add(got, String(it)) or changed
			for s_item2 in SourcesData.ITEM_SOURCES:
				for s2 in SourcesData.ITEM_SOURCES[s_item2]:
					if String(s2["kind"]) == "pickup":
						changed = _add(got, String(s_item2)) or changed
		for rid in RecipesData.RECIPES:
			if exclude.has(rid):
				continue
			var r: Dictionary = RecipesData.RECIPES[rid]
			if got.has(r["result"]) or not stations.has(r["station"]):
				continue
			if String(r["unlock"]) != "" and not flags.has(r["unlock"]):
				continue
			if r.has("mastery") and not bool(opts.get("mastery", false)):
				continue
			var ok := true
			for ing in r["ingredients"]:
				if not got.has(ing):
					ok = false
					break
			if ok:
				changed = _add(got, String(r["result"])) or changed
		for it in got:
			var d2 := ItemDB.item(String(it))
			var t := String(d2["tool"])
			if t != "" and ItemDB.item_tier(String(it)) > int(tier[t]):
				tier[t] = ItemDB.item_tier(String(it))
				changed = true
			if (d2["cat"] == "tool" or d2["cat"] == "weapon") and not armed:
				armed = true
				changed = true
			if d2["cat"] == "placeable":
				var st: Dictionary = ItemDB.structure(String(d2["place"]))
				if String(st.get("interact", "")) == "station" and not stations.has(st["station"]):
					stations[st["station"]] = true
					changed = true
	assert_true(guard < 64, "simulation converged")
	return got


func _in_areas(list: Array, areas: Array) -> bool:
	if areas.is_empty():
		return true
	for a in list:
		if areas.has(a):
			return true
	return false


func _all_flags() -> Dictionary:
	var f := {}
	for flag in UnlocksData.UNLOCK_FLAGS:
		f[flag] = true
	return f


func _flags_with_prefix(prefix: String) -> Dictionary:
	var f := {}
	for flag in UnlocksData.UNLOCK_FLAGS:
		if String(flag).begins_with(prefix):
			f[flag] = true
	return f


## Items whose every source is a one-time reward or pickup.
func _reward_only(id: String) -> bool:
	for s in ItemDB.sources(id):
		if not (String(s["kind"]) in ["reward", "pickup"]):
			return false
	return true


# ================================== declarations ==================================

func test_simulator_is_not_vacuous() -> void:
	var none := _reach({"flags": {}, "areas": ["surface"]})
	assert_true(none.has("wood") and none.has("stone_pickaxe"), "hand gathering and stone tools")
	assert_false(none.has("iron_ore"), "no Reach materials on the surface")
	assert_false(none.has("woven_cloth"), "the loom needs the Tailor's Cache")
	assert_false(none.has("glowcap"), "glowcaps only below")
	var no_axe := _reach({"flags": {}, "areas": ["surface"], "exclude": {"stone_axe": true}})
	assert_true(no_axe.has("wood"), "sticks give wood by hand")
	var nothing := _reach({"flags": {}, "areas": ["nowhere"]})
	assert_false(nothing.has("wood"), "no areas, no materials")
	var no_furnace := _reach({"flags": _all_flags(), "exclude": {"furnace": true}})
	assert_false(no_furnace.has("copper_bar") or no_furnace.has("iron_bar"), "bars need a buildable furnace")
	assert_true(no_furnace.has("iron_ore"))


func test_every_item_declares_valid_sources() -> void:
	for id in ItemDB.all_item_ids():
		assert_false(ItemDB.sources(String(id)).is_empty(), "%s has at least one source" % id)
	for id in SourcesData.ITEM_SOURCES:
		assert_true(ItemDB.has_item(id), "sources for a real item: " + String(id))
		for s in SourcesData.ITEM_SOURCES[id]:
			var kind := String(s["kind"])
			assert_true(KINDS.has(kind), "%s source kind %s" % [id, kind])
			if kind != "recipe" and kind != "station":
				assert_true(s.get("guaranteed") is bool and s.get("renewable") is bool, "%s %s source marks guaranteed / renewable" % [id, kind])
			match kind:
				"gather":
					var n := ItemDB.node_kind(String(s["node"]))
					assert_false(n.is_empty(), "%s node %s exists" % [id, s["node"]])
					var drops_it := false
					for d in n.get("drops", []):
						if String(d["item"]) == id:
							drops_it = true
							if bool(s["guaranteed"]):
								assert_eq(float(d["chance"]), 1.0, "%s guaranteed from %s only if it always drops" % [id, s["node"]])
					assert_true(drops_it, "%s node %s drops it" % [id, s["node"]])
				"crop":
					var c := ItemDB.crop(String(s["crop"]))
					assert_true(c.has("yield") and (c["yield"] as Dictionary).has(id), "%s crop %s yields it" % [id, s["crop"]])
				"recipe", "station":
					var r := ItemDB.recipe(String(s["recipe"]))
					assert_eq(String(r.get("result", "")), String(id), "%s recipe %s makes it" % [id, s["recipe"]])
					assert_eq(kind == "station", r.has("time"), "%s: queued station jobs are declared as kind 'station'" % id)
					if kind == "station":
						assert_eq(String(s["station"]), String(r["station"]))
				"drop":
					var e := ItemDB.enemy(String(s["enemy"]))
					var dropped := false
					for d2 in e.get("drops", []):
						dropped = dropped or String(d2["item"]) == id
					assert_true(dropped, "%s is dropped by %s" % [id, s["enemy"]])
					assert_false(bool(s["guaranteed"]), "%s: enemy drops are never counted as guaranteed" % id)
				"reward":
					var b := ItemDB.reward_bundle(String(s["reward"]))
					assert_true((b.get("items", {}) as Dictionary).has(id), "%s reward %s grants it" % [id, s["reward"]])
				"pickup":
					for a in s["where"]:
						assert_true(EnemiesData.AREA_IDS.has(a), "%s pickup area %s" % [id, a])
					assert_true(String(s["desc"]) != "")
				"companion":
					assert_true(CreaturesData.CREATURES.has(String(s["companion"])), "%s companion %s" % [id, s["companion"]])


func test_declared_sources_are_complete() -> void:
	var declared := func(item: String, kind: String, key: String, value: String) -> bool:
		for s in ItemDB.sources(item):
			if String(s["kind"]) == kind and String(s.get(key, "")) == value:
				return true
		return false
	for rid in RecipesData.RECIPES:
		var r: Dictionary = RecipesData.RECIPES[rid]
		var kind := "station" if r.has("time") else "recipe"
		assert_true(declared.call(String(r["result"]), kind, "recipe", String(rid)), "%s lists recipe %s" % [r["result"], rid])
	for cid in StructuresData.CROPS:
		for y in StructuresData.CROPS[cid]["yield"]:
			assert_true(declared.call(String(y), "crop", "crop", String(cid)), "%s lists crop %s" % [y, cid])
	for kind2 in SourcesData.NODES:
		for d in SourcesData.NODES[kind2]["drops"]:
			assert_true(declared.call(String(d["item"]), "gather", "node", String(kind2)), "%s lists node %s" % [d["item"], kind2])
	for eid in EnemiesData.ENEMIES:
		for d2 in EnemiesData.ENEMIES[eid].get("drops", []):
			assert_true(declared.call(String(d2["item"]), "drop", "enemy", String(eid)), "%s lists drop from %s" % [d2["item"], eid])
	# every reward the ledger can pay (this file's bundles AND the quest-layer / optional-log rewards)
	for rw in ItemDB.all_reward_ids():
		for it in ItemDB.reward_bundle(String(rw))["items"]:
			assert_true(declared.call(String(it), "reward", "reward", String(rw)), "%s lists reward %s" % [it, rw])


func test_nodes_are_placeable_data() -> void:
	for kind in SourcesData.NODES:
		var n: Dictionary = SourcesData.NODES[kind]
		assert_true(TOOLS.has(n["tool"]), kind + " tool")
		if n["tool"] == "hand":
			assert_eq(int(n["min_tier"]), 0, kind + " hand nodes need no tier")
		else:
			assert_true(int(n["min_tier"]) >= 1 and int(n["min_tier"]) <= 4, kind + " tool tier")
		assert_true(int(n["hits"]) >= 1, kind + " hits")
		assert_true(float(n["respawn_minutes"]) > 0.0, kind + " is renewable")
		assert_false((n["drops"] as Array).is_empty(), kind + " drops something")
		var flag := String(n["access_flag"])
		assert_true(flag == "" or UnlocksData.UNLOCK_FLAGS.has(flag) or WORLD_FLAGS.has(flag), kind + " access flag is known")
		for area in n["where"]:
			assert_true(EnemiesData.AREA_IDS.has(area), "%s area %s" % [kind, area])
			for zone in n["where"][area]:
				assert_true(String(zone) != "", kind + " zone")
				if ZONE_PREFIX.has(area):
					assert_true(String(zone).begins_with(ZONE_PREFIX[area]), "%s zone %s uses the %s prefix (spec 7.2)" % [kind, zone, ZONE_PREFIX[area]])
			if not bool(n.get("legacy", false)) or area != "surface" and area != "below":
				assert_true(int((n["min_count"] as Dictionary).get(area, 0)) >= 1, "%s: guaranteed node count in %s" % [kind, area])
	for area in SourcesData.AREA_PREFIX:
		assert_true(EnemiesData.AREA_IDS.has(area), "prefix area " + area)


func test_world_builders_get_the_requested_pockets() -> void:
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_quarry").has("iron_vein"), "iron in Ashbell Quarry")
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_quarry").has("moon_crystal_vein"), "moon crystal on the quarry shelf")
	assert_eq(String(ItemDB.node_kind("moon_crystal_vein")["access_flag"]), "ch2_winch_repaired", "upper shelf after the winch")
	assert_eq(int(ItemDB.node_kind("moon_crystal_vein")["min_tier"]), 3, "needs an Ironwood pick")
	assert_true(ItemDB.node_kinds_in("surface", "meadow").has("sunflax_patch"), "wild sunflax in the Sunny Meadow")
	assert_true(ItemDB.node_kinds_in("surface", "meadow").has("roseberry_bush"), "roseberries in the surface garden")
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_orchard").has("roseberry_bush"), "roseberry hedges in the Reach")
	assert_true(ItemDB.node_kinds_in("surface").has("sap_stump") and ItemDB.node_kinds_in("hallowmere_reach").has("sap_stump"), "resin stumps surface + Reach")
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_pools").has("sugarcap_patch"), "sugarcap in the pools")
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_pools").has("moonpetal_patch"), "moonpetals in the pools")
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_candleyard").has("moonpetal_patch"), "moonpetals in the Candleyard")
	assert_true(ItemDB.node_kinds_in("hallowmere_reach", "hr_orchard").has("pumpkin_vine"), "pumpkins in the orchard")
	assert_false(ItemDB.node_kinds_in("hushed_works", "hw_refuge").is_empty())
	assert_true(ItemDB.node_kinds_in("hushed_works", "hw_refuge").has("crystal"), "renewable echo shards in the refuge pocket")
	assert_true(ItemDB.node_kinds_in("tobin_annex", "ta_sump").has("crystal"), "renewable echo shards in Tobin's sump")
	assert_true(ItemDB.node_kinds_in("hushed_works", "hw_winch").has("silk"), "renewable silk after the Crossing")
	assert_false(ItemDB.node_kinds_in("surface", "haven").has("sap_stump"), "nothing new inside the Haven build area")
	assert_eq(ItemDB.node_kinds_in("nowhere"), [])
	for kind in ["sunflax_patch", "roseberry_bush", "pumpkin_vine"]:
		assert_eq(String(ItemDB.node_kind(kind)["tool"]), "hand", kind + " is picked by hand")


# ================================== reachability ==================================

func test_everything_is_obtainable_from_renewable_raw_sources() -> void:
	var got := _reach({"flags": _all_flags(), "drops": true, "companions": true, "mastery": true})
	for id in ItemDB.all_item_ids():
		if _reward_only(String(id)):
			continue
		assert_true(got.has(id), "%s is obtainable from renewable sources (nodes, crops, drops, recipes)" % id)
	var full := _reach({"flags": _all_flags(), "drops": true, "companions": true, "rewards": true, "mastery": true})
	for id2 in ItemDB.all_item_ids():
		assert_true(full.has(id2), "%s obtainable in a complete playthrough" % id2)
	# no special recipe needs anything unobtainable
	for rid in RecipesData.SPECIAL_RECIPES:
		for ing in RecipesData.SPECIAL_RECIPES[rid]["ingredients"]:
			assert_true(full.has(ing), "%s ingredient %s obtainable" % [rid, ing])
	for pal in AppearanceData.DYE_PALETTES:
		for ing2 in AppearanceData.DYE_PALETTES[pal]["cost"]:
			assert_true(full.has(ing2), "dye %s ingredient %s obtainable" % [pal, ing2])


func test_important_materials_are_renewable() -> void:
	for id in ["sunflax", "roseberries", "resin", "iron_ore", "moon_crystal", "pumpkin", "sugarcap", "moonpetal", "echo_shard",
			"silk", "glowcap", "copper_ore", "sunflax_seeds", "roseberry_seeds", "pumpkin_seeds"]:
		var renewable_guaranteed := false
		for s in ItemDB.sources(id):
			if bool(s.get("renewable", false)) and bool(s.get("guaranteed", false)) and String(s["kind"]) != "drop":
				renewable_guaranteed = true
		assert_true(renewable_guaranteed, id + " has a guaranteed renewable source (not only enemy drops)")


func test_story_required_items_have_guaranteed_sources_before_their_gate() -> void:
	# Chapter Two starts from Chapter One: surface + below, Chapter One optional flags are not required.
	var early := _reach({"flags": {"ward_restored": true}, "areas": CHAPTER_ONE_AREAS, "guaranteed_only": true})
	for id in SourcesData.STORY_REQUIRED:
		assert_true(ItemDB.has_item(id), id + " exists")
		var ok := false
		for s in ItemDB.sources(id):
			if bool(s.get("guaranteed", true)) and String(s["kind"]) != "drop":
				ok = true
		assert_true(ok, id + " has a guaranteed, non-drop source")
		if not ItemDB.is_quest_item(id):
			assert_true(early.has(id), "%s is obtainable from guaranteed Chapter One sources before any Chapter Two gate" % id)
	for seal in ["garden_seal", "quarry_seal", "manor_seal"]:
		assert_true(_reward_only(seal), seal + " is a guaranteed story reward, never random")


func test_chapter_one_building_and_crafting_need_no_story() -> void:
	# No flags at all, surface only, guaranteed nodes only: basic building and the copper workshop.
	var bare := _reach({"flags": {}, "areas": ["surface"], "guaranteed_only": true})
	for id in ["wood_stairs", "upper_floor", "wood_railing", "half_wall", "porch_post", "arched_window", "gable_roof",
			"roof_corner", "wardrobe", "vanity_mirror", "furnace", "kitchen_counter", "bookshelf", "flower_box", "cottage_bench",
			"companion_bed", "companion_perch", "copper_bar", "copper_axe", "copper_pickaxe", "lantern_wax",
			"resin", "sunflax", "roseberries"]:
		assert_true(bare.has(id), "%s needs no story progress (surface only)" % id)
	# Chapter One optional content (c1x flags) is enough for tailoring, Mochi's ribbon and the copperwood set.
	var c1x := _reach({"flags": _flags_with_prefix("c1x_"), "areas": ["surface"], "guaranteed_only": true})
	for id2 in ["loom", "woven_cloth", "comfort_ribbon", "padded_hood", "padded_vest", "padded_boots", "copperwood_hood",
			"copperwood_vest", "copperwood_boots", "gatherers_charm", "curtain", "bat_bunting", "sturdy_planter", "miner_lamp"]:
		assert_true(c1x.has(id2), "%s is craftable in the original woods with Chapter One optional content" % id2)
	assert_false(c1x.has("iron_bar"), "iron needs the Reach")


func test_tier_chain_iron_crystal_moonsteel() -> void:
	# Iron ore: reachable with nothing better than the stone pickaxe.
	var stone_only := {"copper_pickaxe": true, "ironwood_pickaxe": true, "moonsteel_pickaxe": true}
	var s1 := _reach({"flags": _all_flags(), "exclude": stone_only})
	assert_true(s1.has("iron_ore") and s1.has("iron_bar"), "iron with the stone pickaxe")
	assert_eq(int(ItemDB.node_kind("iron_vein")["min_tier"]), ItemDB.item_tier("stone_pickaxe"))
	assert_false(s1.has("moon_crystal"), "moon crystal needs more than stone")
	# Moon Crystal: not with a copper (tier 2) pick, yes with ironwood (tier 3).
	var copper_only := {"ironwood_pickaxe": true, "moonsteel_pickaxe": true}
	var s2 := _reach({"flags": _all_flags(), "exclude": copper_only})
	assert_true(s2.has("copper_pickaxe"))
	assert_false(s2.has("moon_crystal"), "a tier-2 pick cannot mine Moon Crystal")
	assert_false(s2.has("moonsteel_bar"), "so no moonsteel either")
	var s3 := _reach({"flags": _all_flags()})
	assert_true(s3.has("ironwood_pickaxe") and s3.has("moon_crystal") and s3.has("moonsteel_bar"), "tier 3 opens the crystal and moonsteel")
	# ... but only after the winch: without its flag the shelf is closed.
	var flags_no_winch := _all_flags()
	flags_no_winch.erase("ch2_winch_repaired")
	var s4 := _reach({"flags": flags_no_winch})
	assert_false(s4.has("moon_crystal"), "the upper shelf needs the winch repair")
	var ms: Dictionary = RecipesData.RECIPES["moonsteel_bar"]["ingredients"]
	assert_true(ms.has("iron_bar") and ms.has("moon_crystal") and ms.has("echo_shard"), "moonsteel = iron + crystal + echo shard")
	assert_eq(ItemDB.item_tier("ironwood_pickaxe"), 3)
	assert_eq(ItemDB.item_tier("copper_pickaxe"), 2)
	# the ironwood pick itself never needs moon crystal (no circular gate)
	for ing in RecipesData.RECIPES["ironwood_pickaxe"]["ingredients"]:
		assert_ne(ing, "moon_crystal")
		assert_ne(ing, "moonsteel_bar")


func test_no_recipe_depends_on_itself() -> void:
	var graph := {}
	var tables := [RecipesData.RECIPES, RecipesData.SPECIAL_RECIPES]
	for t in tables:
		for rid in t:
			var r: Dictionary = t[rid]
			var res := String(r["result"])
			if res == "":
				continue
			if not graph.has(res):
				graph[res] = []
			for ing in r["ingredients"]:
				graph[res].append(String(ing))
	# the station a recipe needs is also a dependency
	for rid2 in RecipesData.RECIPES:
		var st := ItemDB.station_structure(String(RecipesData.RECIPES[rid2]["station"]))
		if st != "":
			graph[String(RecipesData.RECIPES[rid2]["result"])].append(ItemDB.structure(st)["item"])
	assert_eq(_find_cycle(graph), [], "no recipe depends on itself (stations included)")
	assert_eq(_find_cycle({"a": ["b"], "b": ["c"], "c": ["a"]}), ["a", "b", "c", "a"], "the cycle finder is not vacuous")


## Depth-first colouring (1 = on the current path, 2 = finished). Returns the first cycle found as a path, or [].
func _find_cycle(graph: Dictionary) -> Array:
	var colour := {}
	for start in graph:
		if int(colour.get(start, 0)) != 0:
			continue
		var stack: Array = [[start, 0]]
		colour[start] = 1
		var path: Array = [start]
		while not stack.is_empty():
			var top: Array = stack.back()
			var deps: Array = graph.get(top[0], [])
			if int(top[1]) >= deps.size():
				colour[top[0]] = 2
				stack.pop_back()
				path.pop_back()
				continue
			var nxt: String = deps[int(top[1])]
			top[1] = int(top[1]) + 1
			var c := int(colour.get(nxt, 0))
			if c == 1:
				return path.slice(path.find(nxt)) + [nxt]
			if c == 0:
				colour[nxt] = 1
				stack.append([nxt, 0])
				path.append(nxt)
	return []


func test_reward_bundles_set_every_story_unlock_once() -> void:
	var set_by_reward := {}
	for rw in ItemDB.all_reward_ids():
		var b := ItemDB.reward_bundle(String(rw))
		var own := SourcesData.REWARDS.has(rw)
		assert_true(String(b["who"]) != "", String(rw) + " says who grants it")
		assert_true(String(b.get("by", "")) in ["legacy", "content", "chapter_log", "optional_log"], String(rw) + " says how it is granted")
		for it in b["items"]:
			assert_true(ItemDB.has_item(it) and int(b["items"][it]) > 0, "%s item %s" % [rw, it])
		for f in b["flags"]:
			if own:   # the quest layer / optional log may also set their own non-recipe flags (e.g. map pins)
				var marker: bool = String(b.get("by", "")) == "content" and (CONTENT_MARKER_FLAGS.get(rw, []) as Array).has(f)
				assert_true(UnlocksData.UNLOCK_FLAGS.has(f) or WORLD_FLAGS.has(f) or marker, "%s flag %s is known" % [rw, f])
			set_by_reward[f] = true
		for p in b.get("patterns", []):
			assert_false(ItemDB.pattern(String(p)).is_empty(), "%s pattern %s" % [rw, p])
	for flag in UnlocksData.UNLOCK_FLAGS:
		if WORLD_FLAGS.has(flag):
			continue
		assert_true(set_by_reward.has(flag), "unlock flag %s is set by a reward bundle" % flag)
	# Echo Trial first clears (lead decision L09): each trial's pattern-unlock flag is set by its own content bundle
	# only, so the pattern stays unique to that trial (MP 15).
	for tf in ["ch2_trial_matron", "ch2_trial_velour", "ch2_trial_choir"]:
		var setters: Array = []
		for rw2 in ItemDB.all_reward_ids():
			if (ItemDB.reward_bundle(String(rw2))["flags"] as Array).has(tf):
				setters.append(String(rw2))
		var own_rw: String = "rw_" + String(tf).trim_prefix("ch2_") + "_first"
		assert_eq(setters, [own_rw], "%s is set only by %s" % [tf, own_rw])
		assert_eq(String((SourcesData.REWARDS.get(own_rw, {}) as Dictionary).get("by", "")), "content", own_rw + " is granted by the echo trial module")
		assert_true((ItemDB.reward_bundle(own_rw).get("items", {"missing": 1}) as Dictionary).is_empty(), own_rw + ": a pattern, not loot")
	assert_eq(ItemDB.reward_bundle("rw_ch2_orchard")["items"]["garden_seal"], 1)
	assert_eq(ItemDB.reward_bundle("nope"), {})
	assert_true(ItemDB.is_story_required("manor_seal"))
	assert_false(ItemDB.is_story_required("candy"))
	assert_eq(ItemDB.story_required_items().size(), SourcesData.STORY_REQUIRED.size())
	assert_true(SourcesData.SHOPS.is_empty(), "no shop in this release")


func _add(got: Dictionary, item: String) -> bool:
	if got.has(item):
		return false
	got[item] = true
	return true
