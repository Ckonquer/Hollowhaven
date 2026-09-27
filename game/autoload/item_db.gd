extends Node
## Read-only lookup for data-driven definitions (items, recipes, structures, crops, creatures, enemies).
## Usage: ItemDB.item("wood").name, ItemDB.display_name("silk"), ItemDB.recipe("stone_axe")

const ItemsData := preload("res://data/items.gd")
const RecipesData := preload("res://data/recipes.gd")
const StructuresData := preload("res://data/structures.gd")
const CreaturesData := preload("res://data/creatures.gd")
const EnemiesData := preload("res://data/enemies.gd")

const ITEM_DEFAULTS := {"name": "?", "desc": "", "cat": "resource", "stack": 99, "icon": "unknown", "color": Color.WHITE,
	"heal": 0.0, "damage": 0.0, "reach": 2.0, "tool": "", "power": 1.0, "place": "", "quest": false}

var _items: Dictionary = {}


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
	return bool(item(id).get("quest", false)) or item(id)["cat"] == "key"


func items_in_category(cat: String) -> Array:
	var out := []
	for id in _items:
		if _items[id]["cat"] == cat:
			out.append(id)
	return out


# --- Recipes -------------------------------------------------------------------

func recipe(id: String) -> Dictionary:
	return RecipesData.RECIPES.get(id, {})


func all_recipe_ids() -> Array:
	return RecipesData.RECIPES.keys()


func station_name(station: String) -> String:
	return RecipesData.STATIONS.get(station, station.capitalize())


## A recipe is known when its unlock flag is empty or set in GameState.
func recipe_known(id: String) -> bool:
	var r := recipe(id)
	if r.is_empty():
		return false
	var flag: String = r.get("unlock", "")
	return flag == "" or bool(GameState.get_flag(flag))


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


func bond_level_for_xp(xp: int) -> int:
	var lvl := 0
	for i in CreaturesData.BOND_XP_PER_LEVEL.size():
		if xp >= CreaturesData.BOND_XP_PER_LEVEL[i]:
			lvl = i
	return lvl


func _arachno() -> bool:
	return bool(Settings.get_value("arachnophobia"))
