extends Node
## Authoritative, serialisable game state for the current playthrough.
## Scene nodes read and mutate state through these methods; SaveSystem persists to_dict()/from_dict().
## This node holds DATA only. Behaviour lives in the systems (player, building, companions...).

const Inventory := preload("res://src/core/inventory.gd")
const QuestLog := preload("res://src/core/quest_log.gd")
const Layout := preload("res://data/world_layout.gd")

const HOTBAR_SIZE := 8
const INVENTORY_SIZE := 32
const MINUTES_PER_DAY := 1440.0

var player_name: String = "Krystal"
var active: bool = false                  # true while a playthrough is loaded (not on the title screen)

var inventory: RefCounted = Inventory.new(INVENTORY_SIZE)
var key_items: Dictionary = {}            # quest item id -> count (never dropped)
var hotbar_index: int = 0
var player: Dictionary = {}
var flags: Dictionary = {}
var counters: Dictionary = {}
var quests: RefCounted = QuestLog.new()
var companions: Dictionary = {}           # id -> {befriended, bond_xp, assignment, wait_area, wait_pos, last_pet_day, last_gift_day, last_fed_day}
var active_companion: String = ""         # id of the companion currently following ("" = none)
var structures: Dictionary = {}           # uid -> {id, area, pos:[x,y,z], rot: deg, data:{}}
var storages: Dictionary = {}             # uid -> Inventory
var crops: Dictionary = {}                # plot uid -> {crop, planted_at, tended_minutes}
var depleted: Dictionary = {}             # world node id -> respawn_at (total minutes); absent = available
var dropped: Array = []                   # [{uid, item, count, area, pos:[x,y,z]}]
var lore: Array = []                      # discovered lore ids
var total_minutes: float = 480.0          # in-game minutes since day 1 00:00
var stats: Dictionary = {}
var buffs: Dictionary = {}                # name -> {"mult": float, "remaining": seconds}
var next_uid: int = 1

var _eval_pending := false
var _minute_accum := 0.0


func _ready() -> void:
	inventory.changed.connect(_on_inventory_changed)
	Events.item_added.connect(request_quest_eval.unbind(2))
	Events.structure_placed.connect(request_quest_eval.unbind(2))
	Events.structure_removed.connect(request_quest_eval.unbind(2))
	Events.companion_befriended.connect(request_quest_eval.unbind(1))
	Events.crafted.connect(request_quest_eval.unbind(3))
	Events.flag_set.connect(request_quest_eval.unbind(2))
	Events.counter_changed.connect(request_quest_eval.unbind(2))
	Events.key_item_added.connect(request_quest_eval.unbind(1))
	reset()


func _process(delta: float) -> void:
	if not active:
		return
	# Buff timers tick in real seconds while playing (not while paused: autoload pauses with tree).
	for b in buffs.keys():
		buffs[b]["remaining"] = float(buffs[b]["remaining"]) - delta
		if buffs[b]["remaining"] <= 0.0:
			buffs.erase(b)


## Resets everything to a blank state (used by new_game and before loading).
func reset() -> void:
	inventory.from_array([])
	key_items = {}
	hotbar_index = 0
	player = {"hp": 100.0, "max_hp": 100.0, "stamina": 100.0, "max_stamina": 100.0,
		"area": "surface", "pos": null, "yaw": 0.0, "spawn": "haven_start",
		"respawn_area": "surface", "respawn_spawn": "haven_respawn", "lantern_on": false}
	flags = {}
	counters = {}
	quests = QuestLog.new()
	companions = {}
	for id in ItemDB.creature_ids():
		companions[id] = _new_companion_record()
	active_companion = ""
	structures = {}
	storages = {}
	crops = {}
	depleted = {}
	dropped = []
	lore = []
	total_minutes = float(Layout.CLOCK["new_game_hour"]) * 60.0
	stats = {"play_seconds": 0.0, "deaths": 0, "enemies_defeated": 0, "items_crafted": 0, "started_version": ProjectSettings.get_setting("application/config/version", "0")}
	buffs = {}
	next_uid = 1


func _new_companion_record() -> Dictionary:
	return {"befriended": false, "bond_xp": 0, "assignment": "wild", "wait_area": "", "wait_pos": null,
		"last_pet_day": -1, "last_gift_day": -1, "last_fed_day": -1}


func new_game() -> void:
	reset()
	active = true
	quests.start()


# --- Items -----------------------------------------------------------------------

## Gives items to the player. Quest items go to the key pouch. If the backpack is full the
## remainder is dropped as a persistent pickup at `drop_pos` (or the player's feet) - never destroyed.
## Returns how many went into the backpack/pouch.
func give_item(id: String, count: int, drop_pos: Variant = null) -> int:
	if count <= 0 or not ItemDB.has_item(id):
		return 0
	if ItemDB.is_quest_item(id):
		key_items[id] = int(key_items.get(id, 0)) + count
		Events.key_item_added.emit(id)
		Events.item_added.emit(id, count)
		Events.notify.emit("Obtained: %s" % ItemDB.display_name(id), "item")
		return count
	var left: int = inventory.add(id, count)
	var added := count - left
	if added > 0:
		Events.item_added.emit(id, added)
	if left > 0:
		var pos: Vector3 = drop_pos if drop_pos is Vector3 else _player_feet()
		var uid := add_dropped(id, left, String(player.get("area", "surface")), pos)
		Game.spawn_dropped_item(uid)
		Events.item_overflow_dropped.emit(id, left, pos)
		Events.notify.emit("Backpack full! %d %s dropped nearby." % [left, ItemDB.display_name(id)], "warn")
	return added


## Removes items (backpack first, then key pouch). All-or-nothing.
func take_item(id: String, count: int) -> bool:
	if ItemDB.is_quest_item(id):
		if int(key_items.get(id, 0)) < count:
			return false
		key_items[id] = int(key_items[id]) - count
		if key_items[id] <= 0:
			key_items.erase(id)
		Events.item_removed.emit(id, count)
		Events.inventory_changed.emit()
		return true
	if inventory.remove(id, count):
		Events.item_removed.emit(id, count)
		return true
	return false


func count_item(id: String) -> int:
	return inventory.count_of(id) + int(key_items.get(id, 0))


func has_item(id: String, count: int = 1) -> bool:
	return count_item(id) >= count


## Best owned tool of a kind ("axe"/"pickaxe") or "" if none.
func best_tool(kind: String) -> String:
	var best := ""
	var best_power := -1.0
	for s in inventory.slots:
		if s != null:
			var d := ItemDB.item(s["id"])
			if d["tool"] == kind and float(d["power"]) > best_power:
				best = s["id"]
				best_power = float(d["power"])
	return best


## Best owned melee weapon (weapon category preferred, falls back to tools) or "" for bare hands.
func best_weapon() -> String:
	var best := ""
	var best_dmg := 0.0
	for s in inventory.slots:
		if s != null:
			var d := ItemDB.item(s["id"])
			if (d["cat"] == "weapon" or d["cat"] == "tool") and float(d["damage"]) > best_dmg:
				best = s["id"]
				best_dmg = float(d["damage"])
	return best


func selected_slot() -> Variant:
	return inventory.get_slot(hotbar_index)


func select_hotbar(i: int) -> void:
	hotbar_index = clampi(i, 0, HOTBAR_SIZE - 1)
	Events.hotbar_selected.emit(hotbar_index)


func _on_inventory_changed() -> void:
	Events.inventory_changed.emit()
	request_quest_eval()


func _player_feet() -> Vector3:
	if Game.player != null and is_instance_valid(Game.player):
		return Game.player.global_position
	var p = player.get("pos")
	return Vector3(p[0], p[1], p[2]) if p is Array and p.size() == 3 else Vector3.ZERO


# --- Flags, counters, lore ------------------------------------------------------------

func set_flag(name: String, value: Variant = true) -> void:
	if flags.get(name) == value:
		return
	flags[name] = value
	Events.flag_set.emit(name, value)


func get_flag(name: String) -> Variant:
	return flags.get(name, false)


func add_counter(name: String, amount: int = 1) -> int:
	counters[name] = int(counters.get(name, 0)) + amount
	Events.counter_changed.emit(name, counters[name])
	return counters[name]


func set_counter_max(name: String, value: int) -> void:
	if value > int(counters.get(name, 0)):
		counters[name] = value
		Events.counter_changed.emit(name, value)


func get_counter(name: String) -> int:
	return int(counters.get(name, 0))


func discover_lore(lore_id: String) -> bool:
	if lore.has(lore_id):
		return false
	lore.append(lore_id)
	Events.lore_discovered.emit(lore_id)
	return true


func new_uid(prefix: String = "u") -> String:
	var u := "%s%d" % [prefix, next_uid]
	next_uid += 1
	return u


# --- World nodes (harvestables) & dropped items -----------------------------------------

func is_depleted(node_id: String) -> bool:
	if not depleted.has(node_id):
		return false
	var at := float(depleted[node_id])
	if at >= 0.0 and total_minutes >= at:
		depleted.erase(node_id)
		return false
	return true


## Marks a world node as used up. respawn_minutes < 0 = never respawns (e.g. quest boulders).
func deplete(node_id: String, respawn_minutes: float) -> void:
	depleted[node_id] = -1.0 if respawn_minutes < 0.0 else total_minutes + respawn_minutes


func add_dropped(item: String, count: int, area: String, pos: Vector3) -> String:
	var uid := new_uid("d")
	dropped.append({"uid": uid, "item": item, "count": count, "area": area, "pos": [pos.x, pos.y, pos.z]})
	return uid


func get_dropped(uid: String) -> Dictionary:
	for d in dropped:
		if d["uid"] == uid:
			return d
	return {}


func remove_dropped(uid: String) -> void:
	for i in dropped.size():
		if dropped[i]["uid"] == uid:
			dropped.remove_at(i)
			return


func dropped_in_area(area: String) -> Array:
	return dropped.filter(func(d): return d["area"] == area)


# --- Structures, storage & crops ----------------------------------------------------------

func add_structure(structure_id: String, pos: Vector3, rot_deg: float, area: String = "surface") -> String:
	var uid := new_uid("s")
	structures[uid] = {"id": structure_id, "area": area, "pos": [pos.x, pos.y, pos.z], "rot": rot_deg, "data": {}}
	var def := ItemDB.structure(structure_id)
	if def.get("interact", "") == "storage":
		storages[uid] = Inventory.new(int(def.get("slots", 20)))
	if def.get("interact", "") == "farm":
		crops[uid] = {"crop": "", "planted_at": 0.0, "tended_minutes": 0.0}
	return uid


func remove_structure(uid: String) -> void:
	structures.erase(uid)
	storages.erase(uid)
	crops.erase(uid)


func count_structures(structure_id: String) -> int:
	var n := 0
	for uid in structures:
		if structures[uid]["id"] == structure_id:
			n += 1
	return n


func get_storage(uid: String) -> RefCounted:
	if not storages.has(uid):
		var def := ItemDB.structure(String(structures.get(uid, {}).get("id", "storage_chest")))
		storages[uid] = Inventory.new(int(def.get("slots", 20)))
	return storages[uid]


# --- Companions ------------------------------------------------------------------------------

func companion(id: String) -> Dictionary:
	if not companions.has(id):
		companions[id] = _new_companion_record()
	return companions[id]


func is_befriended(id: String) -> bool:
	return bool(companion(id)["befriended"])


func befriend(id: String) -> void:
	var c := companion(id)
	if c["befriended"]:
		return
	c["befriended"] = true
	set_companion_assignment(id, "follow")
	Events.companion_befriended.emit(id)


## assignment: "home" | "follow" | "wait" | "wild". Only one companion follows at a time;
## a previous follower is sent home safely.
func set_companion_assignment(id: String, assignment: String, wait_area: String = "", wait_pos: Variant = null) -> void:
	var c := companion(id)
	if assignment == "follow":
		if active_companion != "" and active_companion != id:
			var prev := companion(active_companion)
			prev["assignment"] = "home"
			Events.companion_assignment_changed.emit(active_companion, "home")
		active_companion = id
	elif active_companion == id:
		active_companion = ""
	c["assignment"] = assignment
	if assignment == "wait":
		c["wait_area"] = wait_area
		c["wait_pos"] = [wait_pos.x, wait_pos.y, wait_pos.z] if wait_pos is Vector3 else null
	Events.companion_assignment_changed.emit(id, assignment)


func bond_level(id: String) -> int:
	return ItemDB.bond_level_for_xp(int(companion(id)["bond_xp"]))


func add_bond(id: String, xp: int) -> void:
	var c := companion(id)
	var before := bond_level(id)
	c["bond_xp"] = min(int(c["bond_xp"]) + xp, 100)
	var after := bond_level(id)
	if after > before:
		Events.companion_bond_changed.emit(id, after)
		Events.notify.emit("%s's bond grew! (%d/5)" % [ItemDB.creature(id).get("name", id), after], "bond")
		set_counter_max("max_bond", after)


# --- Clock --------------------------------------------------------------------------------------

func day() -> int:
	return int(floor(total_minutes / MINUTES_PER_DAY)) + 1


func hour() -> float:
	return fmod(total_minutes, MINUTES_PER_DAY) / 60.0


## 0..1 through the day (0 = midnight, 0.5 = noon).
func time_of_day() -> float:
	return fmod(total_minutes, MINUTES_PER_DAY) / MINUTES_PER_DAY


func is_night() -> bool:
	var h := hour()
	return h >= float(Layout.CLOCK["night_start_hour"]) or h < float(Layout.CLOCK["day_start_hour"])


## Advances the clock by real seconds (called by Game while playing).
func advance_clock(real_seconds: float) -> void:
	var rate := float(Layout.CLOCK["minutes_per_second"])
	if is_night():
		rate *= float(Layout.CLOCK["night_speedup"])
	var before_day := day()
	total_minutes += real_seconds * rate
	stats["play_seconds"] = float(stats.get("play_seconds", 0.0)) + real_seconds
	_minute_accum += real_seconds * rate
	if _minute_accum >= 1.0:
		_minute_accum = 0.0
		Events.time_of_day_changed.emit(day(), time_of_day())
	if day() != before_day:
		Events.day_started.emit(day())


## Skips to the next morning at `wake_hour`. Returns minutes skipped.
func skip_to_morning(wake_hour: float = 7.0) -> float:
	var h := hour()
	var target_today: float = floorf(total_minutes / MINUTES_PER_DAY) * MINUTES_PER_DAY + wake_hour * 60.0
	var target: float = target_today if h < wake_hour else target_today + MINUTES_PER_DAY
	var skipped: float = target - total_minutes
	var before_day := day()
	total_minutes = target
	Events.time_of_day_changed.emit(day(), time_of_day())
	if day() != before_day:
		Events.day_started.emit(day())
	return skipped


# --- Buffs ---------------------------------------------------------------------------------------

func add_buff(name: String, mult: float, seconds: float) -> void:
	buffs[name] = {"mult": mult, "remaining": seconds}


func buff_mult(name: String) -> float:
	return float(buffs[name]["mult"]) if buffs.has(name) else 1.0


# --- Quests ----------------------------------------------------------------------------------------

## Deferred (once per frame) quest evaluation.
func request_quest_eval() -> void:
	if not active or _eval_pending:
		return
	_eval_pending = true
	_do_eval.call_deferred()


func _do_eval() -> void:
	_eval_pending = false
	if active:
		quests.evaluate()


# --- Persistence -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var st := {}
	for uid in storages:
		st[uid] = storages[uid].to_array()
	return {
		"player_name": player_name,
		"inventory": inventory.to_array(),
		"key_items": key_items.duplicate(),
		"hotbar_index": hotbar_index,
		"player": player.duplicate(true),
		"flags": flags.duplicate(true),
		"counters": counters.duplicate(),
		"quests": quests.to_dict(),
		"companions": companions.duplicate(true),
		"active_companion": active_companion,
		"structures": structures.duplicate(true),
		"storages": st,
		"crops": crops.duplicate(true),
		"depleted": depleted.duplicate(),
		"dropped": dropped.duplicate(true),
		"lore": lore.duplicate(),
		"total_minutes": total_minutes,
		"stats": stats.duplicate(),
		"buffs": buffs.duplicate(true),
		"next_uid": next_uid,
	}


## Loads from a dictionary produced by to_dict(). Missing keys fall back to defaults.
func from_dict(d: Dictionary) -> void:
	reset()
	player_name = String(d.get("player_name", "Krystal"))
	inventory.from_array(d.get("inventory", []))
	for k in d.get("key_items", {}):
		if ItemDB.has_item(k):
			key_items[k] = int(d["key_items"][k])
	hotbar_index = clampi(int(d.get("hotbar_index", 0)), 0, HOTBAR_SIZE - 1)
	var p: Dictionary = d.get("player", {})
	for k in p:
		player[k] = p[k]
	flags = d.get("flags", {}).duplicate(true)
	for k in d.get("counters", {}):
		counters[k] = int(d["counters"][k])
	for id in d.get("companions", {}):
		var rec := _new_companion_record()
		rec.merge(d["companions"][id], true)
		rec["bond_xp"] = int(rec["bond_xp"])
		companions[id] = rec
	active_companion = String(d.get("active_companion", ""))
	if active_companion != "" and companion(active_companion)["assignment"] != "follow":
		active_companion = ""
	structures = d.get("structures", {}).duplicate(true)
	for uid in structures:
		var def := ItemDB.structure(String(structures[uid].get("id", "")))
		if def.get("interact", "") == "storage":
			var inv := Inventory.new(int(def.get("slots", 20)))
			inv.from_array(d.get("storages", {}).get(uid, []))
			storages[uid] = inv
	crops = d.get("crops", {}).duplicate(true)
	for uid in structures:
		if ItemDB.structure(String(structures[uid]["id"])).get("interact", "") == "farm" and not crops.has(uid):
			crops[uid] = {"crop": "", "planted_at": 0.0, "tended_minutes": 0.0}
	for k in d.get("depleted", {}):
		depleted[k] = float(d["depleted"][k])
	dropped = []
	for it in d.get("dropped", []):
		if it is Dictionary and ItemDB.has_item(String(it.get("item", ""))):
			dropped.append(it.duplicate(true))
	lore = d.get("lore", []).duplicate()
	total_minutes = float(d.get("total_minutes", 480.0))
	stats.merge(d.get("stats", {}), true)
	buffs = d.get("buffs", {}).duplicate(true)
	next_uid = max(int(d.get("next_uid", 1)), 1)
	quests.from_dict(d.get("quests", {}))
	active = true
