extends Node
## Authoritative, serialisable game state for the current playthrough.
## Scene nodes read and mutate state through these methods; SaveSystem persists to_dict()/from_dict().
## This node holds DATA only. Behaviour lives in the systems (player, building, companions...).

const Inventory := preload("res://src/core/inventory.gd")
const QuestLog := preload("res://src/core/quest_log.gd")
const Layout := preload("res://data/world_layout.gd")
const CreaturesData := preload("res://data/creatures.gd")
const COMPANION_ASSIGNMENTS := ["wild", "home", "follow", "wait"]

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
var _quest_poll := 0.0


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
	if not buffs.is_empty():   # keys() allocates: skip the per-frame copy when there is nothing to tick
		for b in buffs.keys():
			buffs[b]["remaining"] = float(buffs[b]["remaining"]) - delta
			if buffs[b]["remaining"] <= 0.0:
				buffs.erase(b)
	# Safety net (documented in quest_log.gd): once per second, complete the current step if its
	# objectives are met even when no signal announced the change (e.g. state set directly).
	_quest_poll += delta
	if _quest_poll >= 1.0:
		_quest_poll = 0.0
		var cur: Dictionary = quests.current_step()
		if not cur.is_empty() and quests.step_done(cur):
			request_quest_eval()


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
## Taking zero (or a negative amount) trivially succeeds and changes nothing.
func take_item(id: String, count: int) -> bool:
	if count <= 0:
		return true
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
	if kind == "":
		return ""   # "" would otherwise match every non-tool item (their tool field is "")
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
	# Compare types first: Godot 4.7 raises a script error for e.g. String == bool.
	var cur: Variant = flags.get(name)
	if flags.has(name) and typeof(cur) == typeof(value) and cur == value:
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
	request_quest_eval()   # "placed" objectives, even if the caller forgets Events.structure_placed
	return uid


func remove_structure(uid: String) -> void:
	structures.erase(uid)
	storages.erase(uid)
	crops.erase(uid)
	request_quest_eval()


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


## Bond xp cap (xp needed for the last bond level, data/creatures.gd).
func max_bond_xp() -> int:
	return int(CreaturesData.BOND_XP_PER_LEVEL[CreaturesData.BOND_XP_PER_LEVEL.size() - 1])


func add_bond(id: String, xp: int) -> void:
	var c := companion(id)
	var before := bond_level(id)
	c["bond_xp"] = clampi(int(c["bond_xp"]) + xp, 0, max_bond_xp())
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
		"stats": stats.duplicate(true),
		"buffs": buffs.duplicate(true),
		"next_uid": next_uid,
	}


## Loads from a dictionary produced by to_dict(). Missing keys fall back to defaults.
## Saves arrive through JSON, so every number is a float and any section may be damaged:
## values are type-checked and normalised back to their runtime types (ints stay ints),
## malformed entries are skipped (never a script error) and invariants are repaired
## (one follower, a crop record for every plot, no orphan crops, next_uid above every used uid).
func from_dict(d: Dictionary) -> void:
	reset()
	player_name = _str(d.get("player_name"), "Krystal")
	inventory.from_array(_arr(d.get("inventory")))
	var ki := _dict(d.get("key_items"))
	for k in ki:
		if k is String and ItemDB.has_item(k) and _num(ki[k]) and int(ki[k]) > 0:
			key_items[k] = int(ki[k])
	hotbar_index = clampi(_int(d.get("hotbar_index"), 0), 0, HOTBAR_SIZE - 1)
	_load_player(_dict(d.get("player")))
	flags = {}
	var fl := _dict(d.get("flags"))
	for k in fl:
		flags[str(k)] = _copy(fl[k])
	var cn := _dict(d.get("counters"))
	for k in cn:
		if _num(cn[k]):
			counters[str(k)] = int(cn[k])
	var comps := _dict(d.get("companions"))
	for id in comps:
		if comps[id] is Dictionary:
			companions[str(id)] = _load_companion(comps[id])
	active_companion = _str(d.get("active_companion"), "")
	_repair_followers()
	structures = {}
	var sts := _dict(d.get("structures"))
	var saved_storages := _dict(d.get("storages"))
	for uid in sts:
		var e = sts[uid]
		if not (e is Dictionary) or not (e.get("id") is String) or String(e["id"]) == "":
			continue
		var rec := {"id": String(e["id"]), "area": _str(e.get("area"), "surface"),
			"pos": _vec_arr(e.get("pos"), [0.0, 0.0, 0.0]), "rot": _float(e.get("rot"), 0.0),
			"data": _dict(e.get("data")).duplicate(true)}
		for extra in e:
			if not rec.has(extra):
				rec[extra] = _copy(e[extra])
		structures[str(uid)] = rec
		var def := ItemDB.structure(rec["id"])
		if def.get("interact", "") == "storage":
			var inv := Inventory.new(int(def.get("slots", 20)))
			inv.from_array(_arr(saved_storages.get(uid)))
			storages[str(uid)] = inv
	crops = {}
	var cr := _dict(d.get("crops"))
	for uid in structures:
		if ItemDB.structure(String(structures[uid]["id"])).get("interact", "") != "farm":
			continue
		var c: Dictionary = _dict(cr.get(uid)).duplicate(true)
		c["crop"] = _str(c.get("crop"), "")
		c["planted_at"] = _float(c.get("planted_at"), 0.0)
		c["tended_minutes"] = _float(c.get("tended_minutes"), 0.0)
		crops[uid] = c
	var dep := _dict(d.get("depleted"))
	for k in dep:
		if _num(dep[k]):
			depleted[str(k)] = float(dep[k])
	dropped = []
	var needs_uid: Array = []   # dropped items with a missing/duplicate uid: re-labelled, never discarded
	var seen_drop_uids := {}
	for it in _arr(d.get("dropped")):
		if not (it is Dictionary) or not (it.get("item") is String) or not ItemDB.has_item(it["item"]):
			continue
		var cnt := _int(it.get("count"), 0)
		if cnt <= 0:
			continue
		var rec: Dictionary = it.duplicate(true)
		rec["uid"] = _str(it.get("uid"), "")
		rec["count"] = cnt
		rec["area"] = _str(it.get("area"), "surface")
		rec["pos"] = _vec_arr(it.get("pos"), [0.0, 0.0, 0.0])
		if rec["uid"] == "" or seen_drop_uids.has(rec["uid"]):
			needs_uid.append(rec)
			continue
		seen_drop_uids[rec["uid"]] = true
		dropped.append(rec)
	lore = []
	for l in _arr(d.get("lore")):
		if l is String and not lore.has(l):
			lore.append(l)
	total_minutes = maxf(_float(d.get("total_minutes"), total_minutes), 0.0)
	var st := _dict(d.get("stats"))
	for k in st:
		var def_v: Variant = stats.get(k)
		if def_v is int and _num(st[k]):
			stats[k] = int(st[k])
		elif def_v is float and _num(st[k]):
			stats[k] = float(st[k])
		elif def_v is int or def_v is float:
			pass   # not a usable number (wrong type or INF): keep the default
		elif def_v == null or typeof(def_v) == typeof(st[k]):
			stats[k] = _copy(st[k])
	buffs = {}
	var bf := _dict(d.get("buffs"))
	for k in bf:
		var b = bf[k]
		if b is Dictionary and _num(b.get("mult")) and _num(b.get("remaining")) and float(b["remaining"]) > 0.0:
			buffs[str(k)] = {"mult": float(b["mult"]), "remaining": float(b["remaining"])}
	next_uid = maxi(maxi(_int(d.get("next_uid"), 1), 1), _max_uid_suffix() + 1)
	for rec in needs_uid:
		rec["uid"] = new_uid("d")
		dropped.append(rec)
	quests.from_dict(_dict(d.get("quests")))
	active = true


func _load_player(p: Dictionary) -> void:
	for k in p:
		var def_v: Variant = player.get(k)
		var v: Variant = p[k]
		if k == "pos":
			player["pos"] = _vec_arr(v, null)
		elif def_v is float:
			if _num(v):
				player[k] = float(v)
		elif def_v is String or def_v is bool:
			if typeof(v) == typeof(def_v):
				player[k] = v
		else:
			player[k] = _copy(v)
	# A save never legitimately holds a dead/negative player: wake up healthy (spec: no-loss recovery).
	player["max_hp"] = maxf(float(player["max_hp"]), 1.0)
	player["max_stamina"] = maxf(float(player["max_stamina"]), 1.0)
	if float(player["hp"]) <= 0.0 or float(player["hp"]) > float(player["max_hp"]):
		player["hp"] = float(player["max_hp"])
	player["stamina"] = clampf(float(player["stamina"]), 0.0, float(player["max_stamina"]))


func _load_companion(src: Dictionary) -> Dictionary:
	var rec := _new_companion_record()
	for k in src:
		if not rec.has(k):
			rec[k] = _copy(src[k])   # keep extra fields other modules may store
	rec["befriended"] = bool(src.get("befriended")) if (src.get("befriended") is bool or _num(src.get("befriended"))) else false
	rec["bond_xp"] = clampi(_int(src.get("bond_xp"), 0), 0, max_bond_xp())
	var a := _str(src.get("assignment"), "")
	if not COMPANION_ASSIGNMENTS.has(a):
		a = "home" if rec["befriended"] else "wild"
	rec["assignment"] = a
	rec["wait_area"] = _str(src.get("wait_area"), "")
	rec["wait_pos"] = _vec_arr(src.get("wait_pos"), null)
	for k in ["last_pet_day", "last_gift_day", "last_fed_day"]:
		rec[k] = _int(src.get(k), -1)
	return rec


## One-follower rule after loading: active_companion must be following; any other "follow"
## record either becomes the follower (if none) or is sent home.
func _repair_followers() -> void:
	if active_companion != "" and (not companions.has(active_companion) or companions[active_companion]["assignment"] != "follow"):
		active_companion = ""
	for id in companions:
		if companions[id]["assignment"] == "follow" and id != active_companion:
			if active_companion == "":
				active_companion = id
			else:
				companions[id]["assignment"] = "home"


## Highest numeric suffix among the uids in use (structures "s12", dropped "d7", ...).
func _max_uid_suffix() -> int:
	var m := 0
	var uids: Array = structures.keys()
	for it in dropped:
		uids.append(it["uid"])
	for u in uids:
		var digits := ""
		for ch in String(u):
			if ch >= "0" and ch <= "9":
				digits += ch
			else:
				digits = ""
		if digits != "" and digits.length() < 10:
			m = maxi(m, digits.to_int())
	return m


## A usable number from a save. Non-finite floats are rejected: JSON writes INF as 1e99999 and reads it
## back as INF, so one runtime glitch (e.g. an INF position or clock) would otherwise persist forever.
static func _num(v: Variant) -> bool:
	return v is int or (v is float and is_finite(v))


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


static func _arr(v: Variant) -> Array:
	return v if v is Array else []


static func _str(v: Variant, def: String) -> String:
	return String(v) if (v is String or v is StringName) else def


static func _copy(v: Variant) -> Variant:
	return v.duplicate(true) if (v is Dictionary or v is Array) else v


static func _int(v: Variant, def: int) -> int:
	return int(v) if _num(v) else def


static func _float(v: Variant, def: float) -> float:
	return float(v) if _num(v) else def


## [x, y, z] as floats, or `def` when `v` is not a list of three numbers.
static func _vec_arr(v: Variant, def: Variant) -> Variant:
	if v is Array and v.size() == 3 and _num(v[0]) and _num(v[1]) and _num(v[2]):
		return [float(v[0]), float(v[1]), float(v[2])]
	return def
