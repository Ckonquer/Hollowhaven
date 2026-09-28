extends Node
## Authoritative, serialisable game state for the current playthrough.
## Scene nodes read and mutate state through these methods; SaveSystem persists to_dict()/from_dict().
## This node holds DATA only. Behaviour lives in the systems (player, building, companions...).
## Save schema v2 (docs/CHAPTER_TWO_SPEC.md §3, docs/SAVE_MIGRATION.md): appearance, wardrobe, equipment,
## capacity, optional goals, the Chapter Two layer, the reward ledger, mastery, discovered landmarks,
## trials, orphans (unknown item ids, kept - never dropped), stations, and any unknown top-level keys
## (`extra`, written back unchanged so a later patch never loses data).

const Inventory := preload("res://src/core/inventory.gd")
const QuestLog := preload("res://src/core/quest_log.gd")
const ChapterLog := preload("res://src/core/chapter_log.gd")
const OptionalLog := preload("res://src/core/optional_log.gd")
const Layout := preload("res://data/world_layout.gd")
const CreaturesData := preload("res://data/creatures.gd")
const COMPANION_ASSIGNMENTS := ["wild", "home", "follow", "wait"]
const COMBAT_MODES := ["assist", "close"]

const HOTBAR_SIZE := 8
const INVENTORY_SIZE := 32                # base backpack size (upgrades: 40, 48 - GameState.capacity)
const MAX_BACKPACK := 64                  # sanity bound for a damaged save (stacks beyond it become orphans)
const MAX_STORAGE := 96
const MINUTES_PER_DAY := 1440.0
const SCHEMA := 2

const EQUIPMENT_SLOTS := ["head", "body", "boots", "charm"]
const ARMOR_SLOTS := ["head", "body", "boots"]
const MASTERY_TRACKS := ["gathering", "hearthcraft", "wayfinding"]
## The Chapter-One avatar as an appearance look (spec §8, verbatim). data/appearance.gd holds the same
## dictionary as LEGACY_LOOK; a test cross-checks the two, so change them together or not at all.
const LEGACY_LOOK_IDS := {"hair": "side_braid", "hair_color": "auburn", "skin": "skin_2",
	"eyes": "eye_1", "upper": "explorer_jacket", "lower": "explorer_trousers", "shoes": "explorer_boots",
	"hat": "", "hair_acc": "flower_clip", "back": "satchel", "palette": {"primary": "teal", "secondary":
	"sunflower", "accent": "plum"}, "outfit": "cozy_explorer"}
## Companion record keys added by schema v2 (defaults; older records gain them on load).
const COMPANION_V2_DEFAULTS := {"combat_mode": "assist", "skill_ready_at": 0.0, "home_spot": null,
	"ribbon": "", "home_task": ""}
## Every key to_dict() writes. Anything else found in a saved state goes to `extra` and is written back.
const STATE_KEYS := ["player_name", "inventory", "key_items", "hotbar_index", "player", "flags", "counters",
	"quests", "companions", "active_companion", "structures", "storages", "crops", "depleted", "dropped",
	"lore", "total_minutes", "stats", "buffs", "next_uid",
	"schema", "appearance", "wardrobe", "equipment", "capacity", "optional", "chapter2", "ledger", "mastery",
	"discovered", "trials", "orphans", "stations"]

var player_name: String = "Krystal"
var active: bool = false                  # true while a playthrough is loaded (not on the title screen)

var inventory: RefCounted = Inventory.new(INVENTORY_SIZE)   # never replaced (signals are connected once)
var key_items: Dictionary = {}            # quest item id -> count (never dropped)
var hotbar_index: int = 0
var player: Dictionary = {}
var flags: Dictionary = {}
var counters: Dictionary = {}
var quests: RefCounted = QuestLog.new()
var companions: Dictionary = {}           # id -> {befriended, bond_xp, assignment, wait_area, wait_pos, last_pet_day, last_gift_day, last_fed_day, combat_mode, skill_ready_at, home_spot, ribbon, home_task}
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

# --- Save schema v2 (replaced on reset/load: never cache these objects) ---
var appearance: Dictionary = {}           # look dictionary (spec §4.1); default LEGACY_LOOK_IDS
var wardrobe: Dictionary = {}             # {owned: [ids], palettes: [ids], presets: [{name, look}], notice_shown, show_armor}
var equipment: Dictionary = {}            # slot -> item id ("" = empty); items are moved OUT of the backpack
var capacity: Dictionary = {}             # {"backpack": inventory.size}
var chapter2: RefCounted = ChapterLog.new()        # Chapter Two quest layer (data/quests_ch2.gd)
var optional_goals: RefCounted = OptionalLog.new() # optional tracker (data/optional_goals.gd)
var ledger: Dictionary = {}               # reward_id -> total_minutes when granted (grant_once)
var mastery: Dictionary = {}
var discovered: Dictionary = {}           # area_id -> [landmark ids]
var trials: Dictionary = {}               # trial_id -> {clears, best_seconds}
var orphans: Array = []                   # [{where, slot, stack:{id, count}}] unknown item ids, kept
var stations: Dictionary = {}             # reserved (station queues live in structures[uid].data)
var extra: Dictionary = {}                # unknown top-level state keys, written back verbatim
var last_equip_error: String = ""         # reason of the last refused equip()/unequip()

var _raw_storages: Dictionary = {}        # storages of structures this build doesn't know: kept verbatim
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
	# objectives are met even when no signal announced the change (e.g. state set directly). The same
	# holds for the Chapter Two layer and the optional goals.
	_quest_poll += delta
	if _quest_poll >= 1.0:
		_quest_poll = 0.0
		var cur: Dictionary = quests.current_step()
		if (not cur.is_empty() and quests.step_done(cur)) or chapter2.has_pending_completion() \
				or optional_goals.has_pending_completion():
			request_quest_eval()


## Resets everything to a blank state (used by new_game and before loading).
func reset() -> void:
	inventory.reset_to(INVENTORY_SIZE)
	key_items = {}
	hotbar_index = 0
	player = {"hp": 100.0, "max_hp": 100.0, "stamina": 100.0, "max_stamina": 100.0,
		"area": "surface", "pos": null, "yaw": 0.0, "spawn": "haven_start",
		"respawn_area": "surface", "respawn_spawn": "haven_respawn", "lantern_on": false,
		"below_respawn": ""}   # last Below return point (lantern); restored on re-entering the Below
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
	var v2 := v2_section_defaults()
	appearance = v2["appearance"]
	wardrobe = v2["wardrobe"]
	equipment = v2["equipment"]
	capacity = v2["capacity"]
	chapter2 = ChapterLog.new()
	optional_goals = OptionalLog.new()
	ledger = {}
	mastery = v2["mastery"]
	discovered = {}
	trials = {}
	orphans = []
	stations = {}
	extra = {}
	last_equip_error = ""
	_raw_storages = {}


## Defaults of every section save schema v2 adds (spec §3). Used by reset() and SaveSystem.migrate().
static func v2_section_defaults() -> Dictionary:
	return {
		"schema": SCHEMA,
		"appearance": LEGACY_LOOK_IDS.duplicate(true),
		"wardrobe": {"owned": [], "palettes": [], "presets": [], "notice_shown": false, "show_armor": false},
		"equipment": {"head": "", "body": "", "boots": "", "charm": ""},
		"capacity": {"backpack": INVENTORY_SIZE},
		"optional": {},
		"chapter2": {"accepted": false, "done": [], "baselines": {}},
		"ledger": {},
		"mastery": {"gathering": 0, "hearthcraft": 0, "wayfinding": 0,
			"seen": {"gathering": [], "hearthcraft": [], "wayfinding": []}, "legacy_credit": false},
		"discovered": {},
		"trials": {},
		"orphans": [],
		"stations": {},
	}


func _new_companion_record() -> Dictionary:
	var rec := {"befriended": false, "bond_xp": 0, "assignment": "wild", "wait_area": "", "wait_pos": null,
		"last_pet_day": -1, "last_gift_day": -1, "last_fed_day": -1}
	rec.merge(COMPANION_V2_DEFAULTS.duplicate(true))
	return rec


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
		if Game != null:
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
	if Game != null and Game.player != null and is_instance_valid(Game.player):
		return Game.player.global_position
	var p = player.get("pos")
	return Vector3(p[0], p[1], p[2]) if p is Array and p.size() == 3 else Vector3.ZERO


# --- Capacity (schema v2) ------------------------------------------------------------------

## Grows the backpack to `slots` (32 | 40 | 48). Never shrinks, never loses an item. True if it grew.
func set_backpack_capacity(slots: int) -> bool:
	if not inventory.resize(mini(slots, MAX_BACKPACK)):
		return false
	capacity["backpack"] = inventory.size
	Events.capacity_changed.emit("backpack", inventory.size)
	return true


## Upgrades a storage structure in place (keeps its uid and contents): records data.slots and grows the
## chest's Inventory. Never shrinks. True if it grew.
func set_storage_capacity(uid: String, slots: int) -> bool:
	if not structures.has(uid) or ItemDB.structure(String(structures[uid]["id"])).get("interact", "") != "storage":
		return false
	var inv: RefCounted = get_storage(uid)
	var n := mini(slots, MAX_STORAGE)
	if not inv.resize(n):
		return false
	structures[uid]["data"]["slots"] = inv.size
	Events.capacity_changed.emit("storage:" + uid, inv.size)
	return true


## Slot count for a storage: the largest of the structure default, the upgrade (data.slots) and the length
## of the saved array, so loading never truncates a chest.
func _storage_size(def: Dictionary, data: Dictionary, saved_len: int) -> int:
	var n: int = maxi(int(def.get("slots", 20)), saved_len)
	if _num(data.get("slots")):
		n = maxi(n, int(data["slots"]))
	return clampi(n, 1, MAX_STORAGE)


# --- Equipment (schema v2, spec §8) ------------------------------------------------------------

## Which equipment slot an item goes to ("" = not wearable): armor -> its `slot` (head/body/boots),
## charms -> "charm".
func equip_slot_for(item_id: String) -> String:
	if not ItemDB.has_item(item_id):
		return ""
	var d := ItemDB.item(item_id)
	var cat := String(d.get("cat", ""))
	if cat == "armor":
		var s := String(d.get("slot", ""))
		return s if ARMOR_SLOTS.has(s) else ""
	if cat == "charm":
		return "charm"
	return ""


func equipped(slot: String) -> String:
	return String(equipment.get(slot, ""))


## How many equipment slots hold `item_id`.
func equipped_count(item_id: String) -> int:
	var n := 0
	for s in EQUIPMENT_SLOTS:
		if String(equipment.get(s, "")) == item_id:
			n += 1
	return n


## Wears an item from the backpack (transactional). Whatever was in that slot goes back to the backpack -
## into the same slot when `from_slot` is given and that slot empties. Refused (false, with
## `last_equip_error`) when the item isn't wearable/owned or the old piece would not fit: nothing changes.
func equip(item_id: String, from_slot: int = -1) -> bool:
	last_equip_error = ""
	var slot := equip_slot_for(item_id)
	if slot == "":
		return _equip_refused("That can't be worn.", false)
	if String(equipment.get(slot, "")) == item_id:
		return true
	if inventory.count_of(item_id) < 1:
		return _equip_refused("You don't have that with you.", false)
	var snap: Array = inventory.snapshot()
	var prev := String(equipment.get(slot, ""))
	var src: Variant = inventory.get_slot(from_slot)
	if from_slot >= 0 and src is Dictionary and src["id"] == item_id:
		inventory.remove_from_slot(from_slot, 1)
		if prev != "" and inventory.get_slot(from_slot) == null:
			inventory.set_slot(from_slot, {"id": prev, "count": 1})
			prev = ""
	elif not inventory.remove(item_id, 1):
		return _equip_refused("You don't have that with you.", false)
	if prev != "" and inventory.add(prev, 1) > 0:
		inventory.restore(snap)
		return _equip_refused("Your backpack is full.", true)
	equipment[slot] = item_id
	Events.equipment_changed.emit(slot, item_id)
	Events.stats_changed.emit()
	request_quest_eval()
	return true


## Takes off whatever is in `slot` and puts it in the backpack. Refused when the backpack is full
## (the item stays equipped - it is never dropped or lost).
func unequip(slot: String) -> bool:
	last_equip_error = ""
	var id := String(equipment.get(slot, ""))
	if id == "" or not EQUIPMENT_SLOTS.has(slot):
		return _equip_refused("Nothing is worn there.", false)
	if not inventory.can_add(id, 1):
		return _equip_refused("Your backpack is full.", true)
	inventory.add(id, 1)
	equipment[slot] = ""
	Events.equipment_changed.emit(slot, "")
	Events.stats_changed.emit()
	request_quest_eval()
	return true


func _equip_refused(reason: String, tell: bool) -> bool:
	last_equip_error = reason
	if tell:
		Events.notify.emit(reason, "warn")
	return false


# --- Reward ledger (schema v2, spec §3.5) ----------------------------------------------------------

## Grants a reward exactly once per save. Returns false (and does nothing) when `reward_id` is already in
## the ledger. Otherwise records it FIRST, then sets `flags`, then gives `items` (a full backpack drops the
## rest as persistent pickups; an item id this build doesn't know is kept as an orphan), then notifies.
func grant_once(reward_id: String, items: Dictionary = {}, flag_list: Array = [], message: String = "") -> bool:
	if reward_id == "" or ledger.has(reward_id):
		return false
	ledger[reward_id] = float(total_minutes)
	for f in flag_list:
		set_flag(String(f), true)
	for id in items:
		var n: int = int(items[id]) if _num(items[id]) else 0
		if n <= 0:
			continue
		if ItemDB.has_item(String(id)):
			give_item(String(id), n)
		else:
			push_warning("GameState: reward %s names unknown item '%s'; kept as an orphan" % [reward_id, str(id)])
			orphans.append({"where": "inventory", "slot": -1, "stack": {"id": String(id), "count": n}})
	if message != "":
		Events.notify.emit(message, "success")
	Events.reward_granted.emit(reward_id)
	return true


func has_reward(reward_id: String) -> bool:
	return ledger.has(reward_id)


## Adds a wardrobe part/pattern id to `wardrobe.owned`. True if it was new.
func unlock_pattern(pattern_id: String) -> bool:
	var owned: Array = wardrobe.get("owned", [])
	if pattern_id == "" or owned.has(pattern_id):
		return false
	owned.append(pattern_id)
	wardrobe["owned"] = owned
	return true


## Adds a dye palette id to `wardrobe.palettes` (a crafted dye, a reward's furnishing finish). True when it is
## newly owned (then emits Events.appearance_changed so wardrobes, swatches and tinted pieces refresh); false for
## "" or a palette already owned. Ids are not checked against the catalogue (a newer build's palette is kept).
func unlock_palette(palette_id: String) -> bool:
	if palette_id == "":
		return false
	var cur: Variant = wardrobe.get("palettes", [])
	var palettes: Array = cur if cur is Array else []
	if palettes.has(palette_id):
		return false
	palettes.append(palette_id)
	wardrobe["palettes"] = palettes
	Events.appearance_changed.emit()
	return true


# --- Map landmarks (schema v2) -----------------------------------------------------------------------

## Records a discovered map landmark. True when it is new (emits Events.landmark_discovered).
func discover(area_id: String, landmark_id: String) -> bool:
	if area_id == "" or landmark_id == "":
		return false
	var list: Array = discovered.get(area_id, [])
	if list.has(landmark_id):
		return false
	list.append(landmark_id)
	discovered[area_id] = list
	Events.landmark_discovered.emit(area_id, landmark_id)
	request_quest_eval()
	return true


func is_discovered(area_id: String, landmark_id: String) -> bool:
	var list: Variant = discovered.get(area_id)
	return list is Array and (list as Array).has(landmark_id)


func discovered_in(area_id: String) -> Array:
	var list: Variant = discovered.get(area_id)
	return (list as Array).duplicate() if list is Array else []


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
		storages[uid] = Inventory.new(_storage_size(def, {}, 0))
	if def.get("interact", "") == "farm":
		crops[uid] = {"crop": "", "planted_at": 0.0, "tended_minutes": 0.0}
	request_quest_eval()   # "placed" objectives, even if the caller forgets Events.structure_placed
	return uid


func remove_structure(uid: String) -> void:
	structures.erase(uid)
	storages.erase(uid)
	crops.erase(uid)
	_raw_storages.erase(uid)
	request_quest_eval()


func count_structures(structure_id: String) -> int:
	var n := 0
	for uid in structures:
		if structures[uid]["id"] == structure_id:
			n += 1
	return n


func get_storage(uid: String) -> RefCounted:
	if not storages.has(uid):
		var rec: Dictionary = structures.get(uid, {})
		var def := ItemDB.structure(String(rec.get("id", "storage_chest")))
		var data: Variant = rec.get("data", {})
		storages[uid] = Inventory.new(_storage_size(def, data if data is Dictionary else {}, 0))
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

## Deferred (once per frame) quest evaluation: the legacy chain, the Chapter Two layer and optional goals.
func request_quest_eval() -> void:
	if not active or _eval_pending:
		return
	_eval_pending = true
	_do_eval.call_deferred()


func _do_eval() -> void:
	_eval_pending = false
	if active:
		quests.evaluate()
		chapter2.evaluate()
		optional_goals.evaluate()


## The chapter the journey is in: 2 once Chapter Two is active (accepted), else 1.
func chapter() -> int:
	return 2 if chapter2.is_active() else 1


## Combined objective for the tracker, journal, map, pause menu, save meta and telemetry (spec §8):
## the Chapter Two steps while that layer is active and unfinished, otherwise the legacy step.
## {"source": "chapter2"|"legacy", "chapter": 1|2, "id": first step id or "", "title": String,
##  "steps": [step dicts to display], "status": [{label, done, progress, target, step}], "optional": bool,
##  "group": String, "target": landmark id of the first step ("" = none), "target_area": the area that
##  landmark is in ("surface" for the legacy chain)}. Titles honour the arachnophobia option.
## Every step's "target" is a landmark id String in both layers (Chapter Two steps add "target_area").
func current_objective() -> Dictionary:
	var ch := chapter()
	if chapter2.is_active():
		var cur: Array = chapter2.current_steps()
		if not cur.is_empty():
			var rows: Array = []
			for s in cur:
				for st in chapter2.objective_status(s):
					st["step"] = String(s["id"])
					rows.append(st)
			return {"source": "chapter2", "chapter": ch, "id": String(cur[0]["id"]), "title": chapter2.display_title(cur),
				"steps": cur, "status": rows, "optional": false, "group": String(cur[0].get("group", "")),
				"target": _str(cur[0].get("target"), ""), "target_area": _str(cur[0].get("target_area"), "")}
	var step: Dictionary = quests.current_step()
	var legacy_rows: Array = []
	if not step.is_empty():
		for st in quests.objective_status(step):
			st["step"] = String(step["id"])
			legacy_rows.append(st)
	var legacy_target := _str(step.get("target"), "")
	return {"source": "legacy", "chapter": ch, "id": String(step.get("id", "")),
		"title": String(quests.step_string(step, "title")) if not step.is_empty() else "",
		"steps": [step] if not step.is_empty() else [], "status": legacy_rows,
		"optional": bool(step.get("optional", false)), "group": "",
		"target": legacy_target, "target_area": "surface" if legacy_target != "" else ""}


# --- Persistence -------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var st := {}
	for uid in storages:
		st[uid] = storages[uid].to_array()
	for uid in _raw_storages:
		if not st.has(uid):
			st[uid] = _copy(_raw_storages[uid])
	var cap: Dictionary = capacity.duplicate(true)
	cap["backpack"] = inventory.size
	var out := {
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
		"schema": SCHEMA,
		"appearance": appearance.duplicate(true),
		"wardrobe": wardrobe.duplicate(true),
		"equipment": equipment.duplicate(true),
		"capacity": cap,
		"optional": optional_goals.to_dict(),
		"chapter2": chapter2.to_dict(),
		"ledger": ledger.duplicate(),
		"mastery": mastery.duplicate(true),
		"discovered": discovered.duplicate(true),
		"trials": trials.duplicate(true),
		"orphans": orphans.duplicate(true),
		"stations": stations.duplicate(true),
	}
	for k in extra:
		if not out.has(k):
			out[k] = _copy(extra[k])
	return out


## Loads from a dictionary produced by to_dict(). Missing keys fall back to defaults (every schema-v2
## section is optional, so a version-1 state loads as is). Saves arrive through JSON, so every number is a
## float and any section may be damaged: values are type-checked and normalised back to their runtime types
## (ints stay ints), malformed entries are skipped (never a script error) and invariants are repaired
## (one follower, a crop record for every plot, no orphan crops, next_uid above every used uid).
## Player-owned stacks with item ids this build doesn't know are never dropped: they go to `orphans`
## (with their slot) and are written back; orphans whose id is known again are put back where they were.
## Grants nothing and emits no flag/counter signals (react to Events.game_loaded).
func from_dict(d: Dictionary) -> void:
	reset()
	player_name = _str(d.get("player_name"), "Krystal")
	var cap_src := _dict(d.get("capacity"))
	var inv_arr := _arr(d.get("inventory"))
	var cap_n: int = maxi(_int(cap_src.get("backpack"), INVENTORY_SIZE), INVENTORY_SIZE)
	inventory.resize(clampi(maxi(cap_n, inv_arr.size()), INVENTORY_SIZE, MAX_BACKPACK))   # BEFORE from_array
	for r in inventory.from_array_collect(inv_arr):
		orphans.append({"where": "inventory", "slot": int(r["slot"]), "stack": r["stack"]})
	for k in cap_src:
		if str(k) != "backpack":
			capacity[str(k)] = _copy(cap_src[k])
	capacity["backpack"] = inventory.size
	var ki := _dict(d.get("key_items"))
	for k in ki:
		if not (k is String) or not _num(ki[k]) or int(ki[k]) <= 0:
			continue
		if ItemDB.has_item(k):
			key_items[k] = int(ki[k])
		elif String(k) != "":
			orphans.append({"where": "key_items", "slot": -1, "stack": {"id": String(k), "count": int(ki[k])}})
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
		for extra_key in e:
			if not rec.has(extra_key):
				rec[extra_key] = _copy(e[extra_key])
		structures[str(uid)] = rec
		var def := ItemDB.structure(rec["id"])
		var saved_arr := _arr(saved_storages.get(uid))
		if def.get("interact", "") == "storage":
			var inv := Inventory.new(_storage_size(def, rec["data"], saved_arr.size()))   # capacity BEFORE from_array
			for r in inv.from_array_collect(saved_arr):
				orphans.append({"where": "storage:" + str(uid), "slot": int(r["slot"]), "stack": r["stack"]})
			storages[str(uid)] = inv
		elif saved_storages.get(uid) is Array:
			# A chest this build does not treat as storage (unknown id, or a later build made it a storage):
			# keep its contents verbatim so they are written back, never dropped.
			_raw_storages[str(uid)] = _copy(saved_storages[uid])
	for uid in saved_storages:
		# Contents saved under a uid whose structure record is missing or damaged: kept verbatim as well
		# (never discard player items; nothing spawns for them).
		if not structures.has(str(uid)) and saved_storages[uid] is Array \
				and (saved_storages[uid] as Array).any(func(s: Variant) -> bool: return s != null):
			_raw_storages[str(uid)] = _copy(saved_storages[uid])
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
		var rec := _dropped_record(it)
		if rec.is_empty():
			continue
		if not ItemDB.has_item(rec["item"]):
			orphans.append({"where": "dropped", "slot": -1, "stack": {"id": rec["item"], "count": rec["count"]}, "record": rec})
			continue
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
			var rec: Dictionary = (b as Dictionary).duplicate(true)   # extra keys (e.g. a food "family", spec §9) are kept
			rec["mult"] = float(b["mult"])
			rec["remaining"] = float(b["remaining"])
			buffs[str(k)] = rec
	# --- schema v2 sections (all optional) ---
	_load_appearance(_dict(d.get("appearance")))
	_load_wardrobe(_dict(d.get("wardrobe")))
	_load_equipment(_dict(d.get("equipment")))
	ledger = {}
	var lg := _dict(d.get("ledger"))
	for k in lg:
		ledger[str(k)] = float(lg[k]) if _num(lg[k]) else 0.0   # a granted reward is never forgotten
	_load_mastery(_dict(d.get("mastery")))
	discovered = {}
	var dc := _dict(d.get("discovered"))
	for a in dc:
		var ids: Array = []
		for x in _arr(dc[a]):
			if x is String and x != "" and not ids.has(x):
				ids.append(x)
		discovered[str(a)] = ids
	trials = {}
	var tr := _dict(d.get("trials"))
	for k in tr:
		if tr[k] is Dictionary:
			var t: Dictionary = (tr[k] as Dictionary).duplicate(true)
			t["clears"] = maxi(_int(t.get("clears"), 0), 0)
			t["best_seconds"] = maxf(_float(t.get("best_seconds"), 0.0), 0.0)
			trials[str(k)] = t
	stations = _dict(d.get("stations")).duplicate(true)
	_load_orphans(_arr(d.get("orphans")), needs_uid, seen_drop_uids)
	next_uid = maxi(maxi(_int(d.get("next_uid"), 1), 1), _max_uid_suffix() + 1)
	for rec in needs_uid:
		rec["uid"] = new_uid("d")
		dropped.append(rec)
	quests.from_dict(_dict(d.get("quests")))
	var ch2 := _dict(d.get("chapter2"))
	if ch2.get("accepted") is bool and ch2["accepted"] and not ChapterLog._truthy(flags.get("ch2_accepted", false)):
		flags["ch2_accepted"] = true   # written together: restore an acceptance flag the section still records
	chapter2.from_dict(ch2)
	optional_goals.from_dict(_dict(d.get("optional")))
	optional_goals.apply_legacy(quests)
	extra = {}
	for k in d:
		if not STATE_KEYS.has(k):
			extra[str(k)] = _copy(d[k])
	active = true


## A normalised dropped-item record from a save entry ({} when unusable: no item id or no positive count).
func _dropped_record(it: Variant) -> Dictionary:
	if not (it is Dictionary) or not (it.get("item") is String) or String(it["item"]) == "":
		return {}
	var cnt := _int(it.get("count"), 0)
	if cnt <= 0:
		return {}
	var rec: Dictionary = (it as Dictionary).duplicate(true)
	rec["uid"] = _str(it.get("uid"), "")
	rec["count"] = cnt
	rec["area"] = _str(it.get("area"), "surface")
	rec["pos"] = _vec_arr(it.get("pos"), [0.0, 0.0, 0.0])
	return rec


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
	# schema v2 keys (defaults for older records)
	var cm := _str(src.get("combat_mode"), "assist")
	rec["combat_mode"] = cm if COMBAT_MODES.has(cm) else "assist"
	rec["skill_ready_at"] = maxf(_float(src.get("skill_ready_at"), 0.0), 0.0)
	rec["home_spot"] = _vec_arr(src.get("home_spot"), null)
	rec["ribbon"] = _str(src.get("ribbon"), "")
	rec["home_task"] = _str(src.get("home_task"), "")
	return rec


func _load_appearance(src: Dictionary) -> void:
	for k in src:
		var v: Variant = src[k]
		if k == "palette":
			if v is Dictionary:
				for pk in v:
					if v[pk] is String:
						appearance["palette"][str(pk)] = v[pk]
		elif appearance.has(k):
			if v is String:
				appearance[k] = v
		else:
			appearance[str(k)] = _copy(v)   # a key a newer build added: kept


func _load_wardrobe(src: Dictionary) -> void:
	for k in src:
		if not wardrobe.has(k):
			wardrobe[str(k)] = _copy(src[k])
	wardrobe["owned"] = _str_list(src.get("owned"))
	wardrobe["palettes"] = _str_list(src.get("palettes"))
	var presets: Array = []
	for p in _arr(src.get("presets")):
		if p is Dictionary and p.get("look") is Dictionary:
			var rec: Dictionary = (p as Dictionary).duplicate(true)
			rec["name"] = _str(p.get("name"), "")
			presets.append(rec)
	wardrobe["presets"] = presets
	for k in ["notice_shown", "show_armor"]:
		if src.get(k) is bool:
			wardrobe[k] = src[k]


func _load_equipment(src: Dictionary) -> void:
	for k in src:
		var v: Variant = src[k]
		if not (v is String):
			continue
		var slot := String(k)
		if not EQUIPMENT_SLOTS.has(slot):
			equipment[slot] = v   # a slot a newer build added: kept verbatim
		elif v == "":
			continue
		elif ItemDB.has_item(v):
			equipment[slot] = v
		else:
			orphans.append({"where": "equipment", "slot": EQUIPMENT_SLOTS.find(slot), "stack": {"id": String(v), "count": 1}})


func _load_mastery(src: Dictionary) -> void:
	for k in src:
		if not mastery.has(k):
			mastery[str(k)] = _copy(src[k])
	for t in MASTERY_TRACKS:
		mastery[t] = maxi(_int(src.get(t), 0), 0)
	var seen := {}
	for t in MASTERY_TRACKS:
		seen[t] = []
	var ss := _dict(src.get("seen"))
	for t in ss:
		seen[str(t)] = _str_list(ss[t])
	mastery["seen"] = seen
	# Never reset a recorded legacy credit (that would apply it again, MP §2.3): keep whatever value was
	# recorded (bool, number, text, dictionary...). Only a missing/null value means "not applied yet".
	var lc: Variant = src.get("legacy_credit")
	if lc is float and not is_finite(lc):
		mastery["legacy_credit"] = true   # recorded, but the value itself is unusable (JSON INF)
	elif typeof(lc) != TYPE_NIL:
		mastery["legacy_credit"] = _copy(lc)


## Saved orphans: stacks whose item id is known again are put back where they were (same slot when it is
## free, else anywhere in that inventory); everything else stays an orphan. Nothing is ever discarded.
func _load_orphans(src: Array, needs_uid: Array, seen_drop_uids: Dictionary) -> void:
	for o in src:
		if not (o is Dictionary) or not (o.get("stack") is Dictionary):
			continue
		var where := _str(o.get("where"), "")
		var s: Dictionary = o["stack"]
		if where == "" or not (s.get("id") is String) or String(s["id"]) == "":
			continue
		var entry: Dictionary = (o as Dictionary).duplicate(true)
		entry["where"] = where
		entry["slot"] = _int(o.get("slot"), -1)
		entry["stack"] = {"id": String(s["id"]), "count": maxi(_int(s.get("count"), 1), 1)}
		var id: String = entry["stack"]["id"]
		if not ItemDB.has_item(id):
			orphans.append(entry)
			continue
		var left := _restore_orphan(entry, needs_uid, seen_drop_uids)
		if left > 0:
			entry["stack"]["count"] = left
			orphans.append(entry)


## Puts a known-again orphan back. Returns how many could not be placed (they stay orphans).
func _restore_orphan(o: Dictionary, needs_uid: Array, seen_drop_uids: Dictionary) -> int:
	var where: String = o["where"]
	var id: String = o["stack"]["id"]
	var n: int = o["stack"]["count"]
	var slot: int = o["slot"]
	if where == "key_items" and ItemDB.is_quest_item(id):
		key_items[id] = int(key_items.get(id, 0)) + n
		return 0
	if where == "dropped":
		var rec := _dropped_record(o.get("record", {}))
		if rec.is_empty():
			rec = {"uid": "", "item": id, "count": n, "area": "surface", "pos": [0.0, 0.0, 0.0]}
		if rec["uid"] == "" or seen_drop_uids.has(rec["uid"]):
			needs_uid.append(rec)
		else:
			seen_drop_uids[rec["uid"]] = true
			dropped.append(rec)
		return 0
	if where == "equipment" and slot >= 0 and slot < EQUIPMENT_SLOTS.size():
		var sname: String = EQUIPMENT_SLOTS[slot]
		if String(equipment.get(sname, "")) == "" and equip_slot_for(id) == sname:
			equipment[sname] = id
			return n - 1
	var inv: RefCounted = null
	if where.begins_with("storage:"):
		inv = storages.get(where.substr(8))
		if inv == null:
			return n   # its chest isn't here (unknown or removed structure): keep it as an orphan
	elif where == "inventory" or where == "equipment" or where == "key_items":
		inv = inventory
	else:
		return n
	if ItemDB.is_quest_item(id):
		key_items[id] = int(key_items.get(id, 0)) + n
		return 0
	if where != "equipment" and slot >= 0 and slot < inv.size and inv.get_slot(slot) == null:
		inv.set_slot(slot, {"id": id, "count": n})
		return 0
	return inv.add(id, n)


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
	var uids: Array = structures.keys() + _raw_storages.keys()
	for it in dropped:
		uids.append(it["uid"])
	for o in orphans:
		if o.get("record") is Dictionary:
			uids.append(_str(o["record"].get("uid"), ""))
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


## Unique non-empty Strings of a saved list (anything else is skipped).
static func _str_list(v: Variant) -> Array:
	var out: Array = []
	for x in _arr(v):
		if (x is String or x is StringName) and String(x) != "" and not out.has(String(x)):
			out.append(String(x))
	return out


## [x, y, z] as floats, or `def` when `v` is not a list of three numbers.
static func _vec_arr(v: Variant, def: Variant) -> Variant:
	if v is Array and v.size() == 3 and _num(v[0]) and _num(v[1]) and _num(v[2]):
		return [float(v[0]), float(v[1]), float(v[2])]
	return def
