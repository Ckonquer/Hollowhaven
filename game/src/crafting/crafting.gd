extends RefCounted
## Crafting rules (static). Recipes live in data/recipes.gd and are looked up through ItemDB.
##   const Crafting := preload("res://src/crafting/crafting.gd")   (or load() from other modules)
##   var st := Crafting.stations_near(player.global_position)      -> ["hand", "workbench"]
##   var c := Crafting.check("stone_axe", st)                        -> {"ok", "reason", "missing": {item: n}}
##   if Crafting.craft("stone_axe", st): ...
##
## craft() is TRANSACTIONAL: every ingredient and the room for the result are verified on a copy of the
## backpack first (removing ingredients may free a slot for the result), then the real inventory is
## changed once. Any failure restores the snapshot, so items are never duplicated or lost - also when it
## is called many times in the same frame. The function never awaits.

const InventoryScript := preload("res://src/core/inventory.gd")

## Crafting stations (group "crafting_station", property `station_id`) count within this distance.
const STATION_RADIUS := 4.0


## Station ids available at `pos`. Always contains "hand".
static func stations_near(pos: Vector3) -> Array:
	var out: Array = ["hand"]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return out
	for n in tree.get_nodes_in_group("crafting_station"):
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		var sid: Variant = n.get("station_id")
		if sid == null or String(sid) == "":
			continue
		if (n as Node3D).global_position.distance_to(pos) <= STATION_RADIUS and not out.has(String(sid)):
			out.append(String(sid))
	return out


## Recipe ids the player knows (unlock flag empty or set), in data order.
static func known_recipes() -> Array:
	var out: Array = []
	for rid in ItemDB.all_recipe_ids():
		if ItemDB.recipe_known(rid):
			out.append(rid)
	return out


## Known recipes usable with `stations` (for station-filtered lists).
static func recipes_for_stations(stations: Array) -> Array:
	var out: Array = []
	for rid in known_recipes():
		if stations.has(String(ItemDB.recipe(rid).get("station", "hand"))):
			out.append(rid)
	return out


## {"ok": bool, "reason": String, "missing": {item_id: count_missing}}
static func check(recipe_id: String, stations: Array) -> Dictionary:
	var r := ItemDB.recipe(recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "Unknown recipe.", "missing": {}}
	if not ItemDB.recipe_known(recipe_id):
		return {"ok": false, "reason": "You haven't learned this recipe yet.", "missing": {}}
	var missing := _missing(r)
	var station: String = String(r.get("station", "hand"))
	if not stations.has(station):
		return {"ok": false, "reason": "Needs a %s nearby." % ItemDB.station_name(station), "missing": missing}
	if not missing.is_empty():
		return {"ok": false, "reason": "Missing " + describe_items(missing) + ".", "missing": missing}
	if not _result_fits(r):
		return {"ok": false, "reason": "Your backpack is full. Make some room first.", "missing": {}}
	return {"ok": true, "reason": "", "missing": {}}


## How many times the recipe could be crafted right now from ingredients alone (ignores stations/space).
static func max_craftable(recipe_id: String) -> int:
	var r := ItemDB.recipe(recipe_id)
	if r.is_empty():
		return 0
	var best := 9999
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		var need := int(ings[id])
		if need > 0:
			best = mini(best, GameState.count_item(String(id)) / need)
	return best if best != 9999 else 0


## Crafts once. Returns true on success. Never partially applies.
static func craft(recipe_id: String, stations: Array) -> bool:
	var c := check(recipe_id, stations)
	if not bool(c["ok"]):
		return false
	var r := ItemDB.recipe(recipe_id)
	var result: String = String(r["result"])
	var count: int = int(r.get("count", 1))
	var ings: Dictionary = r.get("ingredients", {})
	var inv: RefCounted = GameState.inventory
	var inv_snapshot: Array = inv.snapshot()
	var keys_snapshot: Dictionary = GameState.key_items.duplicate()
	var ok := true
	# 1. Consume every ingredient exactly once.
	for id in ings:
		var n := int(ings[id])
		if ItemDB.is_quest_item(String(id)):
			if int(GameState.key_items.get(id, 0)) < n:
				ok = false
				break
			GameState.key_items[id] = int(GameState.key_items[id]) - n
			if int(GameState.key_items[id]) <= 0:
				GameState.key_items.erase(id)
		elif not inv.remove(String(id), n):
			ok = false
			break
	# 2. Add the result exactly once.
	if ok:
		if ItemDB.is_quest_item(result):
			GameState.key_items[result] = int(GameState.key_items.get(result, 0)) + count
		else:
			var left: int = inv.add(result, count)
			if left > 0:
				ok = false
	if not ok:
		inv.restore(inv_snapshot)
		GameState.key_items = keys_snapshot
		push_warning("Crafting: %s failed after checks passed; inventory restored." % recipe_id)
		return false
	# 3. Notify (only after the transaction committed).
	for id in ings:
		Events.item_removed.emit(String(id), int(ings[id]))
	if ItemDB.is_quest_item(result):
		Events.key_item_added.emit(result)
		Events.inventory_changed.emit()
	Events.item_added.emit(result, count)
	GameState.stats["items_crafted"] = int(GameState.stats.get("items_crafted", 0)) + count
	Events.crafted.emit(recipe_id, result, count)
	Audio.play_ui("ui_craft")
	return true


## "2 Wood, 1 Stone" (display names respect the arachnophobia option).
static func describe_items(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in items:
		parts.append("%d %s" % [int(items[id]), ItemDB.display_name(String(id))])
	return ", ".join(parts)


# --- Internals ------------------------------------------------------------------------------

static func _missing(r: Dictionary) -> Dictionary:
	var missing := {}
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		var have := GameState.count_item(String(id))
		var need := int(ings[id])
		if have < need:
			missing[id] = need - have
	return missing


## Simulates the craft on a copy of the backpack: ingredients removed first, then the result added.
static func _result_fits(r: Dictionary) -> bool:
	var result: String = String(r.get("result", ""))
	if not ItemDB.has_item(result):
		return false
	if ItemDB.is_quest_item(result):
		return true
	var inv: RefCounted = GameState.inventory
	var sim: RefCounted = InventoryScript.new(inv.size)
	sim.from_array(inv.snapshot())
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		if not ItemDB.is_quest_item(String(id)):
			if not sim.remove(String(id), int(ings[id])):
				return false
	return sim.can_add(result, int(r.get("count", 1)))
