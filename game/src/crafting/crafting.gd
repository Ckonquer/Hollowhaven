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
##
## Chapter Two (docs/CHAPTER_TWO_SPEC.md 4.3 / 9, MP 3 / 5.4 / 16):
##  * Recipe kinds (ItemDB.recipe_kind): "item" (instant), "timed" (furnace queue only: src/crafting/furnace.gd),
##    "apply" (backpack_40 / backpack_48 grow GameState capacity; chest_40 upgrades ONE chest in place, offered
##    from the storage panel: upgrade_chest(uid)), "pattern" (wardrobe ownership via GameState.unlock_pattern)
##    and "dye" (ids "dye:<palette>": data/appearance.gd DYE_PALETTES mixed once at the Loom).
##  * Optional crafting from nearby home chests: `sources` = chest uids from chest_sources_near(pos) (placed
##    storage chests within CHEST_RADIUS = 18 m in the SAME area, stable uid order). Ingredients come from the
##    backpack (and key pouch) first, then the chests in that order: plan() says exactly where from. One
##    transaction covers the backpack, the key pouch and every source chest (snapshot / restore); nothing is
##    consumed when the result can't be created (full backpack, capacity already reached, pattern owned...).
##  * Seasonal dishes cooked (optional goal "The Harvest Table"): counter ch2_seasonal_dishes (set_counter_max
##    of distinct dishes, remembered by flags ch2_cooked_<dish>); decorate_table() sets ch2_table_decorated.

const InventoryScript := preload("res://src/core/inventory.gd")

## Crafting stations (group "crafting_station", property `station_id`) count within this distance.
const STATION_RADIUS := 4.0
## Storage chests within this distance of Krystal (same area) may supply ingredients when enabled (18 m: the
## whole home workshop around her, never another area).
const CHEST_RADIUS := 18.0
const DYE_PREFIX := "dye:"
## Chest upgrade recipe (data/recipes.gd SPECIAL_RECIPES, apply "chest_40").
const CHEST_UPGRADE := "chest_upgrade_40"
## Chapter Two dishes that count for "The Harvest Table" (distinct dishes cooked). Same list as the goal text and
## the story tracker (src/world/story_ch2/story_ch2.gd SEASONAL_DISHES): candy is that goal's reward, not a dish.
const SEASONAL_DISHES := ["pumpkin_soup", "pumpkin_biscuit", "roseberry_tart", "moonpetal_tea", "lanternwake_platter"]
const SEASONAL_COUNTER := "ch2_seasonal_dishes"
## Festival table decorations (kitchen; optional goal "The Harvest Table"). Cosmetic choice only.
const TABLE_DECOR := {"candles": "Candles and autumn leaves", "pumpkins": "Little pumpkins and ribbons", "moonpetals": "A moonpetal posy"}
const TABLE_DECOR_ORDER := ["candles", "pumpkins", "moonpetals"]

## Reason of the last refused craft()/upgrade (UI feedback).
static var last_reason: String = ""


# --- Stations ----------------------------------------------------------------------------------------------

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


## The nearest placed station node of `station_id` within STATION_RADIUS (null if none). Panel refresh only.
static func nearest_station(pos: Vector3, station_id: String) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var best: Node3D = null
	var best_d := STATION_RADIUS + 0.001
	for n in tree.get_nodes_in_group("crafting_station"):
		if not is_instance_valid(n) or not (n is Node3D) or not (n as Node3D).is_inside_tree():
			continue
		if String(n.get("station_id") if n.get("station_id") != null else "") != station_id:
			continue
		var d := (n as Node3D).global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = n
	return best


## Structure uid of the nearest placed `station_id` ("" if none / not a saved structure).
static func nearest_station_uid(pos: Vector3, station_id: String) -> String:
	var n := nearest_station(pos, station_id)
	if n == null:
		return ""
	var u: Variant = n.get("uid")
	return String(u) if u is String else ""


# --- Recipe lookup -------------------------------------------------------------------------------------------

## Recipe ids the player knows (unlock flag empty or set), in data order. Item recipes only (legacy contract;
## timed furnace recipes included). Special recipes: known_special().
static func known_recipes() -> Array:
	var out: Array = []
	for rid in ItemDB.all_recipe_ids():
		if ItemDB.recipe_known(rid):
			out.append(rid)
	return out


## Known special recipes (apply / pattern) followed by the dye palettes, in data order. The chest upgrade is
## left out (it is offered from the storage panel of the chosen chest). `station` filters ("" = all).
static func known_special(station: String = "") -> Array:
	var out: Array = []
	for rid in ItemDB.special_recipe_ids():
		var r := ItemDB.recipe(rid)
		if String(r.get("apply", "")) == "chest_40":
			continue
		if station != "" and String(r.get("station", "hand")) != station:
			continue
		if ItemDB.recipe_known(rid):
			out.append(rid)
	for pid in dye_ids():
		var rid2: String = DYE_PREFIX + String(pid)
		if station == "" or String(recipe_def(rid2).get("station", "loom")) == station:
			out.append(rid2)
	return out


## Known recipes usable with `stations` (for station-filtered lists).
static func recipes_for_stations(stations: Array) -> Array:
	var out: Array = []
	for rid in known_recipes():
		if stations.has(String(ItemDB.recipe(rid).get("station", "hand"))):
			out.append(rid)
	return out


## Recipe definition for any id (item / special / "dye:<palette>"). {} when unknown.
static func recipe_def(recipe_id: String) -> Dictionary:
	if recipe_id.begins_with(DYE_PREFIX):
		var pid := recipe_id.substr(DYE_PREFIX.length())
		var p := ItemDB.dye_palette(pid)
		if p.is_empty():
			return {}
		return {"result": "", "count": 0, "station": String(p.get("station", "loom")), "ingredients": p.get("cost", {}),
			"unlock": "", "dye": pid}
	return ItemDB.recipe(recipe_id)


## "item" | "timed" | "apply" | "pattern" | "dye" | "" (unknown).
static func kind(recipe_id: String) -> String:
	if recipe_id.begins_with(DYE_PREFIX):
		return "dye" if not recipe_def(recipe_id).is_empty() else ""
	return ItemDB.recipe_kind(recipe_id)


static func is_known(recipe_id: String) -> bool:
	if recipe_id.begins_with(DYE_PREFIX):
		return not recipe_def(recipe_id).is_empty()
	return ItemDB.recipe_known(recipe_id)


## Dye palette ids in data order.
static func dye_ids() -> Array:
	return ItemDB.appearance_table("dye_palettes").keys()


## Display name of what a recipe makes ("Copper Bar", "Bigger Backpack (40 slots)", "Ribbon Witch pattern"...).
static func display_name(recipe_id: String) -> String:
	var r := recipe_def(recipe_id)
	if r.is_empty():
		return recipe_id
	match kind(recipe_id):
		"apply":
			var ap := String(r.get("apply", ""))
			if ap.begins_with("backpack_"):
				return "Bigger Backpack (%d slots)" % ap.trim_prefix("backpack_").to_int()
			if ap == "chest_40":
				return "Chest Upgrade (40 slots)"
			return ap.capitalize()
		"pattern":
			return "%s pattern" % String(ItemDB.pattern(String(r["pattern"])).get("name", String(r["pattern"])))
		"dye":
			return String(ItemDB.dye_palette(String(r["dye"])).get("name", String(r["dye"])))
	return ItemDB.display_name(String(r.get("result", "")))


## One sentence describing what a special recipe does ("" for item recipes: use the item description).
static func effect_text(recipe_id: String) -> String:
	var r := recipe_def(recipe_id)
	match kind(recipe_id):
		"apply":
			var ap := String(r.get("apply", ""))
			if ap.begins_with("backpack_"):
				return "Your backpack grows from %d to %d slots. The hotbar and every item stay exactly where they are." \
					% [int(r.get("requires_capacity", GameState.INVENTORY_SIZE)), ap.trim_prefix("backpack_").to_int()]
			if ap == "chest_40":
				return "One chest grows to 40 slots in place. Everything inside stays where it is."
		"pattern":
			return "Sew it once and it's yours: wear it any time at a mirror or wardrobe (switching clothes is free)."
		"dye":
			var p := ItemDB.dye_palette(String(r.get("dye", "")))
			var names: PackedStringArray = []
			for sw in p.get("swatches", []):
				names.append(String(ItemDB.appearance_table("swatches").get(sw, {}).get("name", sw)))
			return "Mix it once: unlocks %s for clothes and a furniture tint, forever." % " & ".join(names)
		"timed":
			return "Smelts in the furnace queue (%s)." % _seconds_text(float(r.get("time", 0.0)))
	return ""


static func _seconds_text(s: float) -> String:
	var n := int(ceilf(s))
	return "%d s" % n if n < 60 else "%dm %02ds" % [n / 60, n % 60]


# --- Checks ---------------------------------------------------------------------------------------------------

## {"ok": bool, "reason": String, "missing": {item_id: count_missing}}
## `sources`: chest uids that may supply ingredients (after the backpack). `target`: the chest uid of a chest
## upgrade. Timed (furnace) recipes are refused here: they are queued with src/crafting/furnace.gd.
static func check(recipe_id: String, stations: Array, sources: Array = [], target: String = "") -> Dictionary:
	return _check(recipe_id, stations, sources, target, false)


## Shared rule check. allow_timed = the furnace queue asking (no result room needed: the station buffers it).
static func _check(recipe_id: String, stations: Array, sources: Array, target: String, allow_timed: bool) -> Dictionary:
	var r := recipe_def(recipe_id)
	if r.is_empty():
		return {"ok": false, "reason": "Unknown recipe.", "missing": {}}
	if not is_known(recipe_id):
		return {"ok": false, "reason": "You haven't learned this recipe yet.", "missing": {}}
	var k := kind(recipe_id)
	var srcs := _source_invs(sources)
	var pl := _plan_items(r.get("ingredients", {}), srcs)
	var missing: Dictionary = pl["missing"]
	if k == "timed" and not allow_timed:
		return {"ok": false, "reason": "Add it to a Furnace queue.", "missing": missing}
	var block := _effect_block(recipe_id, r, target)
	if block != "":
		return {"ok": false, "reason": block, "missing": missing}
	var station: String = String(r.get("station", "hand"))
	if not stations.has(station):
		return {"ok": false, "reason": "Needs a %s nearby." % ItemDB.station_name(station), "missing": missing}
	if not missing.is_empty():
		return {"ok": false, "reason": "Missing " + describe_items(missing) + ".", "missing": missing}
	if k == "item" and not _result_fits(r, pl):
		return {"ok": false, "reason": "Your backpack is full. Make some room first.", "missing": {}}
	return {"ok": true, "reason": "", "missing": {}}


## Why a special recipe can't apply right now ("" = fine).
static func _effect_block(recipe_id: String, r: Dictionary, target: String) -> String:
	match kind(recipe_id):
		"apply":
			var ap := String(r.get("apply", ""))
			if ap.begins_with("backpack_"):
				var want := ap.trim_prefix("backpack_").to_int()
				var size: int = int(GameState.inventory.size)
				if size >= want:
					return "Your backpack already has %d slots." % size
				var req := int(r.get("requires_capacity", size))
				if size != req:
					return "Needs the %d-slot backpack first." % req
				return ""
			if ap == "chest_40":
				if target == "":
					return "Upgrade a chest from its storage panel."
				if not _is_storage(target):
					return "That isn't a storage chest."
				if int(GameState.get_storage(target).size) >= 40:
					return "This chest already has 40 slots."
				return ""
			return "This upgrade isn't available yet."
		"pattern":
			var pid := String(r.get("pattern", ""))
			if ItemDB.pattern(pid).is_empty():
				return "Unknown pattern."
			if _owned_list("owned").has(pid):
				return "You already own this pattern."
		"dye":
			if owns_palette(String(r.get("dye", ""))):
				return "You already mixed this dye."
	return ""


## How many times the recipe could be made right now from ingredients alone (ignores stations/space).
## With `sources`, chest contents count too.
static func max_craftable(recipe_id: String, sources: Array = []) -> int:
	var r := recipe_def(recipe_id)
	if r.is_empty():
		return 0
	var srcs := _source_invs(sources)
	var best := 9999
	var ings: Dictionary = r.get("ingredients", {})
	for id in ings:
		var need := int(ings[id])
		if need > 0:
			best = mini(best, _available(String(id), srcs) / need)
	return best if best != 9999 else 0


## Where the ingredients would come from: {"ok", "missing": {id: n}, "backpack": {id: n} (incl. key pouch),
## "chests": [{"uid", "items": {id: n}}] in source order (only chests that give something)}.
static func plan(recipe_id: String, sources: Array = []) -> Dictionary:
	return _plan_items(recipe_def(recipe_id).get("ingredients", {}), _source_invs(sources))


## Backpack + key pouch + source chests.
static func count_available(item_id: String, sources: Array = []) -> int:
	return _available(item_id, _source_invs(sources))


# --- Crafting ------------------------------------------------------------------------------------------------

## Crafts once. Returns true on success. Never partially applies. Special recipes apply their effect instead of
## adding an item (`target` = chest uid for the chest upgrade).
static func craft(recipe_id: String, stations: Array, sources: Array = [], target: String = "") -> bool:
	var c := check(recipe_id, stations, sources, target)
	if not bool(c["ok"]):
		last_reason = String(c["reason"])
		return false
	var r := recipe_def(recipe_id)
	var k := kind(recipe_id)
	var result: String = String(r.get("result", ""))
	var count: int = int(r.get("count", 1)) if k == "item" else 0
	var commit := func() -> bool:
		if k == "item":
			if ItemDB.is_quest_item(result):
				GameState.key_items[result] = int(GameState.key_items.get(result, 0)) + count
				return true
			return int(GameState.inventory.add(result, count)) == 0
		return _apply_effect(recipe_id, r, target)
	var used := transact(r.get("ingredients", {}), sources, commit)
	if used.is_empty():
		last_reason = "Something went wrong; nothing was used."
		push_warning("Crafting: %s failed after checks passed; everything restored." % recipe_id)
		return false
	last_reason = ""
	# Notify (only after the transaction committed).
	if k == "item":
		if ItemDB.is_quest_item(result):
			Events.key_item_added.emit(result)
			Events.inventory_changed.emit()
		Events.item_added.emit(result, count)
	GameState.stats["items_crafted"] = int(GameState.stats.get("items_crafted", 0)) + count
	Events.crafted.emit(recipe_id, result, count)
	Audio.play_ui("ui_craft")
	_after_craft(recipe_id, r, k, result)
	return true


## ONE transaction over the backpack, the key pouch and every source chest: takes `ingredients` (backpack
## first, then the chests in order), then runs `commit` (-> bool). Anything failing restores every snapshot.
## Returns the plan that was applied ({} on failure). Emits Events.item_removed for the backpack share only
## (chest changes are announced by their Inventory `changed` signal).
static func transact(ingredients: Dictionary, sources: Array, commit: Callable) -> Dictionary:
	var srcs := _source_invs(sources)
	var pl := _plan_items(ingredients, srcs)
	if not bool(pl["ok"]):
		return {}
	var snap := _snapshot(srcs)
	var ok := _take(pl, srcs)
	if ok:
		ok = bool(commit.call())
	if not ok:
		_restore(snap, srcs)
		return {}
	var bag: Dictionary = pl["backpack"]
	for id in bag:
		if int(bag[id]) > 0:
			Events.item_removed.emit(String(id), int(bag[id]))
	return pl


## Upgrades ONE chest in place to 40 slots (recipe chest_upgrade_40): same uid, same contents and slot order,
## data.slots = 40. Ingredients: backpack first, then (by default) this chest itself.
static func upgrade_chest(uid: String, sources: Variant = null) -> bool:
	var src: Array = [uid] if sources == null else (sources as Array)
	return craft(CHEST_UPGRADE, ["hand"], src, uid)


## Dismantling an upgraded chest gives the upgrade kit (chest_upgrade_40 ingredients) back once; BuildOps refunds
## the chest item itself. Works on the live record (call it only when the chest is being taken apart) or on one
## already removed from GameState.structures (the storage chest node does this itself when it is dismantled).
## Marks data.upgrade_refunded, so it never pays twice. Returns {item_id: count} given.
static func refund_chest_upgrade(rec: Dictionary, drop_pos: Variant = null) -> Dictionary:
	var data: Variant = rec.get("data")
	if not (data is Dictionary) or bool((data as Dictionary).get("upgrade_refunded", false)):
		return {}
	var def := ItemDB.structure(String(rec.get("id", "")))
	if String(def.get("interact", "")) != "storage":
		return {}
	var slots: Variant = (data as Dictionary).get("slots")
	if not ((slots is int or slots is float) and int(slots) > int(def.get("slots", 20))):
		return {}
	(data as Dictionary)["upgrade_refunded"] = true
	var given := {}
	var cost: Dictionary = recipe_def(CHEST_UPGRADE).get("ingredients", {})
	for id in cost:
		var n := int(cost[id])
		if n > 0 and ItemDB.has_item(String(id)):
			GameState.give_item(String(id), n, drop_pos)
			given[String(id)] = n
	return given


## Storage-panel preview of the chest upgrade: {"offer": bool (chest can grow), "ok", "reason", "from", "to",
## "cost": {id: n}, "plan": plan() (what comes from the backpack / this chest), "uid", "sources"}.
static func chest_upgrade_info(uid: String, sources: Variant = null) -> Dictionary:
	var src: Array = [uid] if sources == null else (sources as Array)
	var r := recipe_def(CHEST_UPGRADE)
	var out := {"offer": false, "ok": false, "reason": "", "from": 0, "to": 40, "cost": (r.get("ingredients", {}) as Dictionary).duplicate(),
		"plan": {}, "uid": uid, "sources": src}
	if r.is_empty() or not _is_storage(uid):
		return out
	var size: int = int(GameState.get_storage(uid).size)
	out["from"] = size
	out["offer"] = size < 40 and is_known(CHEST_UPGRADE)
	var c := check(CHEST_UPGRADE, ["hand"], src, uid)
	out["ok"] = bool(c["ok"])
	out["reason"] = String(c["reason"])
	out["plan"] = plan(CHEST_UPGRADE, src)
	return out


# --- Nearby chests --------------------------------------------------------------------------------------------

## Placed storage chests within `radius` of `pos` in the SAME area (never another area or outpost), in a
## stable order (placement order: uid number, then text). Uids only; contents via GameState.get_storage(uid).
static func chest_sources_near(pos: Vector3, area_id: String = "", radius: float = CHEST_RADIUS) -> Array:
	if area_id == "":
		area_id = current_area()
	var out: Array = []
	for uid in GameState.structures:
		var rec: Variant = GameState.structures[uid]
		if not (rec is Dictionary) or String(rec.get("area", "surface")) != area_id:
			continue
		if String(ItemDB.structure(String(rec.get("id", ""))).get("interact", "")) != "storage":
			continue
		var p: Variant = rec.get("pos")
		if not (p is Array) or (p as Array).size() != 3:
			continue
		if Vector3(float(p[0]), float(p[1]), float(p[2])).distance_to(pos) <= radius:
			out.append(String(uid))
	out.sort_custom(_uid_before)
	return out


static func _uid_before(a: String, b: String) -> bool:
	var na := _uid_num(a)
	var nb := _uid_num(b)
	if na != nb:
		return na < nb
	return a < b


static func _uid_num(u: String) -> int:
	var digits := ""
	for i in range(u.length() - 1, -1, -1):
		var ch := u[i]
		if ch >= "0" and ch <= "9":
			digits = ch + digits
		else:
			break
	return digits.to_int() if digits != "" else 1 << 30


## Area the player is in (Game.area_id, else the saved player area).
static func current_area() -> String:
	if Game != null and String(Game.area_id) != "":
		return String(Game.area_id)
	return String(GameState.player.get("area", "surface"))


## Player preference: also take ingredients from nearby chests (saved in GameState.stations["use_chests"]).
static func use_chests() -> bool:
	var v: Variant = GameState.stations.get("use_chests", false)
	return v is bool and v


static func set_use_chests(on: bool) -> void:
	GameState.stations["use_chests"] = on


## "Chest 2" style label for the n-th source (1-based) in the UI.
static func chest_label(index: int) -> String:
	return "Chest %d" % (index + 1)


# --- Dyes, patterns, table -------------------------------------------------------------------------------------

static func owns_palette(palette_id: String) -> bool:
	return palette_id != "" and _owned_list("palettes").has(palette_id)


static func owns_pattern(pattern_id: String) -> bool:
	return pattern_id != "" and _owned_list("owned").has(pattern_id)


static func _owned_list(key: String) -> Array:
	var v: Variant = GameState.wardrobe.get(key, [])
	return v if v is Array else []


## Festival table decoration ("" = not chosen yet).
static func table_decor() -> String:
	var v: Variant = GameState.stations.get("table_decor", "")
	return String(v) if v is String else ""


## Dresses the festival table (cosmetic choice; sets ch2_table_decorated for "The Harvest Table").
static func decorate_table(choice: String) -> bool:
	if not TABLE_DECOR.has(choice):
		return false
	GameState.stations["table_decor"] = choice
	GameState.set_flag("ch2_table_decorated", true)
	Events.notify.emit("The festival table is dressed: %s." % String(TABLE_DECOR[choice]).to_lower(), "success")
	return true


## Distinct seasonal dishes cooked so far.
static func seasonal_dishes_cooked() -> int:
	var n := 0
	for d in SEASONAL_DISHES:
		if bool(GameState.get_flag("ch2_cooked_" + String(d))):
			n += 1
	return n


# --- Descriptions ------------------------------------------------------------------------------------------

## "2 Wood, 1 Stone", "3 Copper Bars" (plural names for counts above 1, COV-006: ItemDB.display_count; display
## names respect the arachnophobia option). Recipe costs, the furnace's prompt and toast, chest contents...
static func describe_items(items: Dictionary) -> String:
	var parts: PackedStringArray = []
	for id in items:
		parts.append(ItemDB.display_count(String(id), int(items[id])))
	return ", ".join(parts)


# --- Internals ------------------------------------------------------------------------------

static func _missing(r: Dictionary) -> Dictionary:
	return _plan_items(r.get("ingredients", {}), [])["missing"]


## [[uid, Inventory], ...] for valid, distinct storage uids (given order kept).
static func _source_invs(sources: Array) -> Array:
	var out: Array = []
	var seen := {}
	for s in sources:
		var uid := String(s) if s is String else ""
		if uid == "" or seen.has(uid) or not _is_storage(uid):
			continue
		seen[uid] = true
		out.append([uid, GameState.get_storage(uid)])
	return out


static func _is_storage(uid: String) -> bool:
	var rec: Variant = GameState.structures.get(uid)
	return rec is Dictionary and String(ItemDB.structure(String(rec.get("id", ""))).get("interact", "")) == "storage"


static func _available(item_id: String, srcs: Array) -> int:
	var n := GameState.count_item(item_id)
	if ItemDB.is_quest_item(item_id):
		return n
	for s in srcs:
		n += int(s[1].count_of(item_id))
	return n


static func _plan_items(ings: Dictionary, srcs: Array) -> Dictionary:
	var bag := {}
	var per := {}
	var missing := {}
	for id in ings:
		var need := int(ings[id])
		if need <= 0:
			continue
		var sid := String(id)
		var from_bag: int = mini(need, GameState.count_item(sid))
		if from_bag > 0:
			bag[sid] = from_bag
		var left := need - from_bag
		if not ItemDB.is_quest_item(sid):
			for s in srcs:
				if left <= 0:
					break
				var t: int = mini(int(s[1].count_of(sid)), left)
				if t > 0:
					if not per.has(s[0]):
						per[s[0]] = {}
					per[s[0]][sid] = t
					left -= t
		if left > 0:
			missing[sid] = left
	var chests: Array = []
	for s in srcs:
		if per.has(s[0]):
			chests.append({"uid": String(s[0]), "items": per[s[0]]})
	return {"ok": missing.is_empty(), "missing": missing, "backpack": bag, "chests": chests}


static func _snapshot(srcs: Array) -> Dictionary:
	var chests := {}
	for s in srcs:
		chests[s[0]] = s[1].snapshot()
	return {"bag": GameState.inventory.snapshot(), "keys": GameState.key_items.duplicate(), "chests": chests}


static func _restore(snap: Dictionary, srcs: Array) -> void:
	GameState.inventory.restore(snap["bag"])
	GameState.key_items = snap["keys"]
	for s in srcs:
		if (snap["chests"] as Dictionary).has(s[0]):
			s[1].restore(snap["chests"][s[0]])


## Removes exactly the planned amounts (all-or-nothing per inventory; the caller restores on false).
static func _take(pl: Dictionary, srcs: Array) -> bool:
	var bag: Dictionary = pl["backpack"]
	for id in bag:
		var n := int(bag[id])
		if ItemDB.is_quest_item(String(id)):
			if int(GameState.key_items.get(id, 0)) < n:
				return false
			GameState.key_items[id] = int(GameState.key_items[id]) - n
			if int(GameState.key_items[id]) <= 0:
				GameState.key_items.erase(id)
		elif not GameState.inventory.remove(String(id), n):
			return false
	var by_uid := {}
	for s in srcs:
		by_uid[s[0]] = s[1]
	for c in pl["chests"]:
		var inv: Variant = by_uid.get(c["uid"])
		if inv == null:
			return false
		var items: Dictionary = c["items"]
		for id in items:
			if not inv.remove(String(id), int(items[id])):
				return false
	return true


## Simulates the craft on a copy of the backpack: the backpack share of the ingredients removed first, then
## the result added (chest shares never free backpack room).
static func _result_fits(r: Dictionary, pl: Dictionary = {}) -> bool:
	var result: String = String(r.get("result", ""))
	if not ItemDB.has_item(result):
		return false
	if ItemDB.is_quest_item(result):
		return true
	var inv: RefCounted = GameState.inventory
	var sim: RefCounted = InventoryScript.new(inv.size)
	sim.from_array(inv.snapshot())
	var bag: Dictionary = pl.get("backpack", r.get("ingredients", {}))
	for id in bag:
		if not ItemDB.is_quest_item(String(id)):
			if not sim.remove(String(id), int(bag[id])):
				return false
	return sim.can_add(result, int(r.get("count", 1)))


## Applies a special recipe's effect (inside the transaction). False = refused (everything is restored).
static func _apply_effect(recipe_id: String, r: Dictionary, target: String) -> bool:
	match kind(recipe_id):
		"apply":
			var ap := String(r.get("apply", ""))
			if ap.begins_with("backpack_"):
				return GameState.set_backpack_capacity(ap.trim_prefix("backpack_").to_int())
			if ap == "chest_40":
				return GameState.set_storage_capacity(target, 40)
		"pattern":
			return GameState.unlock_pattern(String(r.get("pattern", "")))
		"dye":
			var pid := String(r.get("dye", ""))
			if owns_palette(pid):
				return false
			if GameState.has_method("unlock_palette"):
				return bool(GameState.call("unlock_palette", pid))
			var list := _owned_list("palettes").duplicate()
			list.append(pid)
			GameState.wardrobe["palettes"] = list
			return true
	return false


## Friendly feedback and optional-goal bookkeeping after a committed craft.
static func _after_craft(recipe_id: String, r: Dictionary, k: String, result: String) -> void:
	match k:
		"apply":
			var ap := String(r.get("apply", ""))
			if ap.begins_with("backpack_"):
				Events.notify.emit("Your backpack now has %d slots." % int(GameState.inventory.size), "success")
			elif ap == "chest_40":
				Events.notify.emit("The chest now holds 40 stacks. Everything inside stayed put.", "success")
		"pattern":
			Events.notify.emit("New pattern: %s! Wear it at a mirror or wardrobe." % String(ItemDB.pattern(String(r["pattern"])).get("name", "")), "success")
			Events.appearance_changed.emit()
		"dye":
			Events.notify.emit("%s mixed! New colours for clothes and furniture." % display_name(recipe_id), "success")
			Events.appearance_changed.emit()
	if SEASONAL_DISHES.has(result):
		GameState.set_flag("ch2_cooked_" + result, true)
		GameState.set_counter_max(SEASONAL_COUNTER, seasonal_dishes_cooked())
