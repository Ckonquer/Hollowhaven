extends Node
## Read-only lookup for data-driven definitions (items, recipes, structures, crops, creatures, enemies).
## Usage: ItemDB.item("wood").name, ItemDB.display_name("silk"), ItemDB.recipe("stone_axe")

const ItemsData := preload("res://data/items.gd")
const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const CreaturesData := preload("res://data/creatures.gd")
const EnemiesData := preload("res://data/enemies.gd")
# Chapter Two catalogue (docs/CHAPTER_TWO_SPEC.md section 4)
const AppearanceData := preload("res://data/appearance.gd")
const EquipmentData := preload("res://data/equipment.gd")
const CompanionSkillsData := preload("res://data/companion_skills.gd")
const MasteryData := preload("res://data/mastery.gd")
const SourcesData := preload("res://data/sources.gd")
const UnlocksData := preload("res://data/unlocks.gd")

const ITEM_DEFAULTS := {"name": "?", "desc": "", "cat": "resource", "stack": 99, "icon": "unknown", "color": Color.WHITE,
	"heal": 0.0, "damage": 0.0, "reach": 2.0, "tool": "", "power": 1.0, "place": "", "quest": false}
## Defaults of ItemDB.equipment(id) for armor / charm items (other items return {}).
const EQUIPMENT_DEFAULTS := {"slot": "", "tier": 1, "set": "", "reduction": 0.0, "effects": {}}
## Defaults of ItemDB.wand(id) for ranged wands (other items return {}).
const WAND_DEFAULTS := {"damage": 0.0, "range": 10.0, "stamina": 8.0, "cooldown": 0.8, "tier": 1,
	"projectile": {"speed": 16.0, "radius": 0.22, "color": Color.WHITE, "lifetime": 0.9}}
## Reward data of the Chapter Two quest layer / optional log (read lazily by reward_bundle(), never preloaded, so
## this autoload never depends on those files parsing).
const QUESTS_CH2_DATA := "res://data/quests_ch2.gd"
const OPTIONAL_GOALS_DATA := "res://data/optional_goals.gd"

var _items: Dictionary = {}
var _log_rewards: Dictionary = {}
var _log_rewards_built := false


func _ready() -> void:
	for id in ItemsData.ITEMS:
		var d: Dictionary = ITEM_DEFAULTS.duplicate()
		d.merge(ItemsData.ITEMS[id], true)
		d["id"] = id
		_items[id] = d


func has_item(id: String) -> bool:
	return _items.has(id)


## Full item definition with defaults filled in. Unknown ids return a placeholder (never null).
func item(id: String) -> Dictionary:
	if _items.has(id):
		return _items[id]
	push_warning("ItemDB: unknown item '%s'" % id)
	var d: Dictionary = ITEM_DEFAULTS.duplicate()
	d["id"] = id
	d["name"] = id
	return d


func all_item_ids() -> Array:
	return _items.keys()


## Name shown to the player (respects the arachnophobia option).
func display_name(id: String) -> String:
	var d := item(id)
	if _arachno() and d.has("alt_name"):
		return d["alt_name"]
	return d["name"]


func display_desc(id: String) -> String:
	var d := item(id)
	if _arachno() and d.has("alt_desc"):
		return d["alt_desc"]
	return d["desc"]


func stack_max(id: String) -> int:
	return int(item(id)["stack"])


func category(id: String) -> String:
	return item(id)["cat"]


func is_quest_item(id: String) -> bool:
	if not _items.has(id):
		return false
	var d: Dictionary = _items[id]
	return bool(d.get("quest", false)) or d["cat"] == "key"


func items_in_category(cat: String) -> Array:
	var out := []
	for id in _items:
		if _items[id]["cat"] == cat:
			out.append(id)
	return out


# --- Recipes -------------------------------------------------------------------

## Any recipe: item recipes (RECIPES) and Chapter Two special recipes (SPECIAL_RECIPES: apply / pattern).
func recipe(id: String) -> Dictionary:
	if RecipesData.RECIPES.has(id):
		return RecipesData.RECIPES[id]
	return RecipesData.SPECIAL_RECIPES.get(id, {})


## Item-producing recipes only (the legacy contract: every entry has a real `result` item).
func all_recipe_ids() -> Array:
	return RecipesData.RECIPES.keys()


## Recipes that apply an upgrade or grant a wardrobe pattern instead of an item.
func special_recipe_ids() -> Array:
	return RecipesData.SPECIAL_RECIPES.keys()


## all_recipe_ids() + special_recipe_ids().
func every_recipe_id() -> Array:
	return RecipesData.RECIPES.keys() + RecipesData.SPECIAL_RECIPES.keys()


## "item" | "timed" (queued furnace job) | "apply" | "pattern" | "" (unknown id).
func recipe_kind(id: String) -> String:
	var r := recipe(id)
	if r.is_empty():
		return ""
	if String(r.get("apply", "")) != "":
		return "apply"
	if String(r.get("pattern", "")) != "":
		return "pattern"
	if float(r.get("time", 0.0)) > 0.0:
		return "timed"
	return "item"


## Recipe ids (item + special) crafted at `station`, in data order.
func recipes_for_station(station: String) -> Array:
	var out: Array = []
	for rid in every_recipe_id():
		if String(recipe(rid).get("station", "hand")) == station:
			out.append(rid)
	return out


func station_name(station: String) -> String:
	return RecipesData.STATIONS.get(station, station.capitalize())


## Structure id that provides a placeable station ("" for hand / campfire / unknown).
func station_structure(station: String) -> String:
	return String(RecipesData.STATION_STRUCTURES.get(station, ""))


## A recipe is known when its unlock flag is empty or set in GameState, and (Chapter Two only) its optional
## mastery gate is reached. Legacy recipes have no mastery field, so their behaviour is unchanged.
func recipe_known(id: String) -> bool:
	var r := recipe(id)
	if r.is_empty():
		return false
	var flag: String = r.get("unlock", "")
	if not (flag == "" or bool(GameState.get_flag(flag))):
		return false
	var gate: Variant = r.get("mastery", null)
	if gate is Dictionary:
		for track in gate:
			if mastery_rank(String(track)) < int(gate[track]):
				return false
	return true


## Every recipe unlock flag -> the system that sets it (data/unlocks.gd).
func unlock_flags() -> Dictionary:
	return UnlocksData.UNLOCK_FLAGS


func unlock_setter(flag: String) -> String:
	return String(UnlocksData.UNLOCK_FLAGS.get(flag, ""))


# --- Structures / crops / creatures / enemies ---------------------------------------

func structure(id: String) -> Dictionary:
	return StructuresData.STRUCTURES.get(id, {})


func all_structure_ids() -> Array:
	return StructuresData.STRUCTURES.keys()


func crop(id: String) -> Dictionary:
	return StructuresData.CROPS.get(id, {})


func creature(id: String) -> Dictionary:
	return CreaturesData.CREATURES.get(id, {})


func creature_ids() -> Array:
	return CreaturesData.CREATURES.keys()


## Random authored line for a companion context, with {name} filled in.
func creature_line(creature_id: String, context: String) -> String:
	var lines: Dictionary = CreaturesData.LINES.get(creature_id, {})
	var arr: Array = lines.get(context, [])
	if arr.is_empty():
		return ""
	var s: String = arr[randi() % arr.size()]
	return s.replace("{name}", GameState.player_name)


func enemy(id: String) -> Dictionary:
	return EnemiesData.ENEMIES.get(id, {})


func enemy_display_name(id: String) -> String:
	var e := enemy(id)
	if _arachno() and String(e.get("alt_name", "")) != "":
		return e["alt_name"]
	return e.get("name", id)


## Enemy description (respects the arachnophobia option via `alt_desc`).
func enemy_display_desc(id: String) -> String:
	var e := enemy(id)
	if _arachno() and String(e.get("alt_desc", "")) != "":
		return e["alt_desc"]
	return String(e.get("desc", ""))


## Structure name shown in build UI (respects the arachnophobia option via `alt_name`).
func structure_display_name(id: String) -> String:
	var s := structure(id)
	if _arachno() and String(s.get("alt_name", "")) != "":
		return s["alt_name"]
	return String(s.get("name", id))


func bond_level_for_xp(xp: int) -> int:
	var lvl := 0
	for i in CreaturesData.BOND_XP_PER_LEVEL.size():
		if xp >= CreaturesData.BOND_XP_PER_LEVEL[i]:
			lvl = i
	return lvl


# =============================== Chapter Two catalogue accessors ===============================

# --- Items: tiers, equipment, wands, food buffs ---------------------------------------------------------

## Tool / weapon / wand / armor / charm tier (stone 1, copper 2, ironwood 3, moonsteel 4); 0 for other items.
## Legacy tools and the Copper Sword come from items.gd LEGACY_TIERS (their entries stay untouched).
func item_tier(id: String) -> int:
	if not _items.has(id):
		return 0
	var d: Dictionary = _items[id]
	if d.has("tier"):
		return int(d["tier"])
	if ItemsData.LEGACY_TIERS.has(id):
		return int(ItemsData.LEGACY_TIERS[id])
	if String(d["cat"]) in ["tool", "weapon", "wand", "armor", "charm"]:
		return 1
	return 0


## Best tier among the owned tools of `kind` ("axe" | "pickaxe") in the backpack; 0 when none.
func best_tool_tier(kind: String) -> int:
	var best := 0
	if kind == "":
		return 0
	for s in GameState.inventory.slots:
		if s != null and _items.has(s["id"]) and String(_items[s["id"]]["tool"]) == kind:
			best = maxi(best, item_tier(String(s["id"])))
	return best


## Equipment slot an item goes to: armor -> its `slot`, charm -> "charm", anything else -> "".
func equip_slot(id: String) -> String:
	if not _items.has(id):
		return ""
	var d: Dictionary = _items[id]
	match String(d["cat"]):
		"armor":
			return String(d.get("slot", ""))
		"charm":
			return "charm"
	return ""


## Armor / charm stats merged over EQUIPMENT_DEFAULTS: {slot, tier, set, reduction, effects}. {} otherwise.
func equipment(id: String) -> Dictionary:
	var slot := equip_slot(id)
	if slot == "":
		return {}
	var d: Dictionary = _items[id]
	var e: Dictionary = EQUIPMENT_DEFAULTS.duplicate(true)
	for k in EQUIPMENT_DEFAULTS:
		if d.has(k):
			e[k] = d[k]
	e["slot"] = slot
	e["tier"] = item_tier(id)
	e["id"] = id
	return e


## Rules and caps of data/equipment.gd (slots, sets, caps, effects, combination order).
func equipment_rules() -> Dictionary:
	return {"slots": EquipmentData.SLOTS, "armor_slots": EquipmentData.ARMOR_SLOTS, "sets": EquipmentData.SETS,
		"reduction_cap": EquipmentData.REDUCTION_CAP, "move_cap": EquipmentData.MOVE_CAP, "effects": EquipmentData.EFFECTS,
		"piece_share": EquipmentData.PIECE_SHARE, "bypass_armor": EquipmentData.BYPASS_ARMOR, "tiers": EquipmentData.TIERS}


func armor_set(set_id: String) -> Dictionary:
	return EquipmentData.SETS.get(set_id, {})


## Ranged wand stats merged over WAND_DEFAULTS ({} for anything that is not ranged).
func wand(id: String) -> Dictionary:
	if not _items.has(id) or not bool(_items[id].get("ranged", false)):
		return {}
	var d: Dictionary = _items[id]
	var w: Dictionary = WAND_DEFAULTS.duplicate(true)
	for k in WAND_DEFAULTS:
		if d.has(k):
			w[k] = d[k]
	w["tier"] = item_tier(id)
	w["id"] = id
	return w


## Food buff family ("" when the food has no buff). Legacy foods derive it from their buff effect key.
func buff_family(id: String) -> String:
	if not _items.has(id):
		return ""
	var d: Dictionary = _items[id]
	if d.has("family"):
		return String(d["family"])
	var b: Variant = d.get("buff", null)
	if not (b is Dictionary):
		return ""
	for k in b:
		if String(k) == "seconds":
			continue
		for fam in ItemsData.BUFF_FAMILIES:
			if String(ItemsData.BUFF_FAMILIES[fam]["effect"]) == String(k):
				return String(fam)
		return String(k)
	return ""


func buff_families() -> Dictionary:
	return ItemsData.BUFF_FAMILIES


# --- Appearance -----------------------------------------------------------------------------------------

## A copy of the Chapter One look (safe to modify).
func legacy_look() -> Dictionary:
	return AppearanceData.LEGACY_LOOK.duplicate(true)


## One of "hairstyles", "hair_colors", "skin_tones", "eye_colors", "parts", "outfits", "swatches",
## "dye_palettes", "patterns". Unknown names return {}.
func appearance_table(table_name: String) -> Dictionary:
	match table_name:
		"hairstyles":
			return AppearanceData.HAIRSTYLES
		"hair_colors":
			return AppearanceData.HAIR_COLORS
		"skin_tones":
			return AppearanceData.SKIN_TONES
		"eye_colors":
			return AppearanceData.EYE_COLORS
		"parts":
			return AppearanceData.PARTS
		"outfits":
			return AppearanceData.OUTFITS
		"swatches":
			return AppearanceData.SWATCHES
		"dye_palettes":
			return AppearanceData.DYE_PALETTES
		"patterns":
			return AppearanceData.PATTERNS
	return {}


func appearance_part(id: String) -> Dictionary:
	return AppearanceData.PARTS.get(id, {})


## Part ids for one slot ("upper", "lower", "shoes", "hat", "hair_acc", "back"), in data order.
func parts_for_slot(slot: String) -> Array:
	var out: Array = []
	for pid in AppearanceData.PARTS:
		if String(AppearanceData.PARTS[pid]["slot"]) == slot:
			out.append(pid)
	return out


func outfit(id: String) -> Dictionary:
	return AppearanceData.OUTFITS.get(id, {})


func pattern(id: String) -> Dictionary:
	return AppearanceData.PATTERNS.get(id, {})


func dye_palette(id: String) -> Dictionary:
	return AppearanceData.DYE_PALETTES.get(id, {})


## Colour of a clothing swatch id (fallback: the legacy colour of that channel is the caller's job; unknown -> WHITE).
func swatch_color(id: String) -> Color:
	var s: Dictionary = AppearanceData.SWATCHES.get(id, {})
	return s.get("color", Color.WHITE)


func preset_slots() -> int:
	return AppearanceData.PRESET_SLOTS


## Validates a look against the tables. Returns {"look": a complete look where every unknown / missing id is
## replaced by the LEGACY_LOOK value of that key (a safe visible default), "missing": ["key=id", ...]}.
## The caller keeps the original ids in the save (never erase unknown data); only the display uses "look".
## Values from a damaged or hand-edited save (null, numbers, arrays...) never raise an error: null in an optional
## slot means "nothing worn", anything else that is not an id string is reported and replaced.
func sanitize_look(look: Variant) -> Dictionary:
	var src: Dictionary = look if look is Dictionary else {}
	var legacy: Dictionary = AppearanceData.LEGACY_LOOK
	var out: Dictionary = legacy.duplicate(true)
	var missing: Array = []
	if not (look is Dictionary):
		missing.append("look=%s" % _look_id(look))
	var tables := {"hair": AppearanceData.HAIRSTYLES, "hair_color": AppearanceData.HAIR_COLORS,
		"skin": AppearanceData.SKIN_TONES, "eyes": AppearanceData.EYE_COLORS}
	for key in tables:
		if src.has(key):
			var v := _look_id(src[key])
			if (tables[key] as Dictionary).has(v):
				out[key] = v
			else:
				missing.append("%s=%s" % [key, v])
	for slot in AppearanceData.SLOTS:
		if not src.has(slot):
			continue
		var pid := _look_id(src[slot])
		if pid == "" and AppearanceData.OPTIONAL_SLOTS.has(slot):
			out[slot] = ""
		elif AppearanceData.PARTS.has(pid) and String(AppearanceData.PARTS[pid]["slot"]) == slot:
			out[slot] = pid
		else:
			missing.append("%s=%s" % [slot, pid])
	var pal: Variant = src.get("palette", null)
	if pal is Dictionary:
		for ch in AppearanceData.PALETTE_CHANNELS:
			if (pal as Dictionary).has(ch):
				var sw := _look_id(pal[ch])
				if AppearanceData.SWATCHES.has(sw):
					out["palette"][ch] = sw
				else:
					missing.append("palette.%s=%s" % [ch, sw])
	elif src.has("palette"):
		missing.append("palette=%s" % _look_id(pal))
	if src.has("outfit"):
		var oid := _look_id(src["outfit"])
		out["outfit"] = oid if AppearanceData.OUTFITS.has(oid) else ""
	return {"look": out, "missing": missing}


## A saved look value as an id: strings as they are, null as "" (nothing), anything else (a number, array or
## dictionary from a damaged save) as "<type>", which never matches a table id. Never raises an error.
static func _look_id(v: Variant) -> String:
	if v is String or v is StringName:
		return String(v)
	if typeof(v) == TYPE_NIL:
		return ""
	return "<%s>" % type_string(typeof(v))


# --- Companion combat -------------------------------------------------------------------------------------

## Base combat / support table of a companion (data/companion_skills.gd SKILLS[id]); {} if unknown.
func companion_skill(id: String) -> Dictionary:
	return CompanionSkillsData.SKILLS.get(id, {})


## The companion's numbers at `bond_level` hearts: every perk of a level <= bond_level applied in order
## (perk values replace base values of the same key). Adds "perks_active": [levels] and "ribbon": bool.
func companion_skill_at(id: String, bond_level: int) -> Dictionary:
	var base := companion_skill(id)
	if base.is_empty():
		return {}
	var out: Dictionary = base.duplicate(true)
	out.erase("perks")
	var active: Array = []
	var ribbon := false
	var perks: Dictionary = base.get("perks", {})
	for lvl in CompanionSkillsData.PERK_LEVELS:
		if bond_level < int(lvl) or not perks.has(lvl):
			continue
		var p: Dictionary = perks[lvl]
		for section in ["passive", "basic", "signature"]:
			if p.has(section):
				var sec: Dictionary = out[section]
				sec.merge(p[section], true)
		if bool(p.get("ribbon", false)):
			ribbon = true
		active.append(lvl)
	out["perks_active"] = active
	out["ribbon"] = ribbon
	return out


## Caps and shared constants: {"move_buff_cap", "reduction_cap", "presence_range", "perk_levels",
## "gear_tier_damage", "modes"}.
func companion_rules() -> Dictionary:
	return {"move_buff_cap": CompanionSkillsData.MOVE_BUFF_CAP, "reduction_cap": CompanionSkillsData.REDUCTION_CAP,
		"presence_range": CompanionSkillsData.PRESENCE_RANGE, "perk_levels": CompanionSkillsData.PERK_LEVELS,
		"gear_tier_damage": CompanionSkillsData.GEAR_TIER_DAMAGE, "modes": CompanionSkillsData.COMBAT_MODES}


# --- Mastery -------------------------------------------------------------------------------------------

func mastery_tracks() -> Array:
	return MasteryData.TRACKS


## Rank (0..MAX_RANK) reached with `xp` total experience.
func mastery_rank_for_xp(xp: int) -> int:
	var rank := 0
	for r in MasteryData.RANK_XP.size():
		if xp >= int(MasteryData.RANK_XP[r]):
			rank = r
	return mini(rank, MasteryData.MAX_RANK)


## Current rank of a track from GameState.mastery (0 when the state has no mastery section yet, or when the
## saved xp is not a number: a damaged value never raises an error). JSON floats (120.0) count as ints.
func mastery_rank(track: String) -> int:
	var m: Variant = GameState.get("mastery")
	if not (m is Dictionary):
		return 0
	var xp: Variant = (m as Dictionary).get(track, 0)
	if not (xp is int or xp is float):
		return 0
	return mastery_rank_for_xp(int(xp))


## Display name and description of a track: {"name", "desc"} (data/mastery.gd TRACK_NAMES). An unknown track
## gets its capitalised id and an empty description (never an error).
func mastery_track_info(track: String) -> Dictionary:
	var t: Variant = MasteryData.TRACK_NAMES.get(track, {})
	var d: Dictionary = t if t is Dictionary else {}
	return {"name": String(d.get("name", track.capitalize())), "desc": String(d.get("desc", ""))}


## XP rules of a track ({rule: {xp, once_per | daily_cap, desc}}).
func mastery_xp_rules(track: String) -> Dictionary:
	return MasteryData.XP.get(track, {})


## Reward of one rank of a track ({} when none).
func mastery_reward(track: String, rank: int) -> Dictionary:
	return MasteryData.REWARDS.get(track, {}).get(rank, {})


## Whole mastery table: {"tracks", "rank_xp", "max_rank", "xp", "rewards", "no_xp", "legacy_credit",
## "legacy_cap_xp", "gather_bonus_cap", "yield_chance_cap"}.
func mastery_tables() -> Dictionary:
	return {"tracks": MasteryData.TRACKS, "rank_xp": MasteryData.RANK_XP, "max_rank": MasteryData.MAX_RANK,
		"xp": MasteryData.XP, "rewards": MasteryData.REWARDS, "no_xp": MasteryData.NO_XP,
		"legacy_credit": MasteryData.LEGACY_CREDIT, "legacy_cap_xp": MasteryData.LEGACY_CAP_XP,
		"gather_bonus_cap": MasteryData.GATHER_BONUS_CAP, "yield_chance_cap": MasteryData.YIELD_CHANCE_CAP}


# --- Sources ------------------------------------------------------------------------------------------

## Acquisition sources of an item (data/sources.gd ITEM_SOURCES); [] when none are declared.
func sources(item_id: String) -> Array:
	return SourcesData.ITEM_SOURCES.get(item_id, [])


## A harvestable node kind (tool, min_tier, hits, drops, respawn_minutes, where, min_count, access_flag).
func node_kind(kind: String) -> Dictionary:
	return SourcesData.NODES.get(kind, {})


func all_node_kinds() -> Array:
	return SourcesData.NODES.keys()


## Node kinds that appear in `area_id` (optionally only in `zone`), in data order.
func node_kinds_in(area_id: String, zone: String = "") -> Array:
	var out: Array = []
	for kind in SourcesData.NODES:
		var where: Dictionary = SourcesData.NODES[kind]["where"]
		if where.has(area_id) and (zone == "" or (where[area_id] as Array).has(zone)):
			out.append(kind)
	return out


## One-time reward bundle {"items", "flags", "patterns"?, "by", "who"} ({} if unknown). Two sources, one ledger:
##  * data/sources.gd REWARDS: "content" bundles a content module grants itself at its event, and "legacy"
##    descriptions of the Chapter One grants (documentation only, never passed to grant_once);
##  * the rewards the Chapter Two quest layer / optional log grant as "rw_" + step / goal id, read from
##    data/quests_ch2.gd (on_complete) and data/optional_goals.gd (reward), their single source of truth
##    ("by": "chapter_log" / "optional_log"). Content modules never grant those: they only set the flags.
func reward_bundle(reward_id: String) -> Dictionary:
	if SourcesData.REWARDS.has(reward_id):
		return SourcesData.REWARDS[reward_id]
	return _log_reward_table().get(reward_id, {})


## Every reward id reward_bundle() knows (data/sources.gd REWARDS first, then the quest-layer / optional-log ones).
func all_reward_ids() -> Array:
	var out: Array = SourcesData.REWARDS.keys()
	for rid in _log_reward_table():
		if not out.has(rid):
			out.append(rid)
	return out


## {"rw_<id>": bundle} for every Chapter Two step / optional goal whose reward gives items, flags or patterns.
## Built once, lazily; missing or damaged data files simply contribute nothing.
func _log_reward_table() -> Dictionary:
	if _log_rewards_built:
		return _log_rewards
	_log_rewards_built = true
	var steps: Variant = _data_const(QUESTS_CH2_DATA, "STEPS")
	if steps is Array:
		for st in steps:
			if st is Dictionary:
				_add_log_reward("chapter_log", "step", st.get("id", ""), st.get("on_complete", {}))
	var goals: Variant = _data_const(OPTIONAL_GOALS_DATA, "GOALS")
	if goals is Array:
		for g in goals:
			if g is Dictionary:
				_add_log_reward("optional_log", "goal", g.get("id", ""), g.get("reward", {}))
	return _log_rewards


func _add_log_reward(by: String, what: String, id: Variant, rw: Variant) -> void:
	if not (id is String) or String(id) == "" or not (rw is Dictionary):
		return
	var give: Variant = (rw as Dictionary).get("give", {})
	var flag_list: Variant = (rw as Dictionary).get("flags", [])
	var pats: Variant = (rw as Dictionary).get("patterns", [])
	var items: Dictionary = (give as Dictionary).duplicate(true) if give is Dictionary else {}
	var fl: Array = (flag_list as Array).duplicate() if flag_list is Array else []
	var pl: Array = (pats as Array).duplicate() if pats is Array else []
	if items.is_empty() and fl.is_empty() and pl.is_empty():
		return
	_log_rewards["rw_" + String(id)] = {"items": items, "flags": fl, "patterns": pl, "by": by,
		"who": "%s %s %s" % [by, what, String(id)]}


func _data_const(path: String, const_name: String) -> Variant:
	if not ResourceLoader.exists(path):
		return null
	var s: Variant = load(path)
	if not (s is Script):
		return null
	return (s as Script).get_script_constant_map().get(const_name, null)


func is_story_required(item_id: String) -> bool:
	return SourcesData.STORY_REQUIRED.has(item_id)


func story_required_items() -> Array:
	return SourcesData.STORY_REQUIRED.keys()


func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))
