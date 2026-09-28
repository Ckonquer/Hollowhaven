extends "res://src/building/structure.gd"
## Crafting station structure (group "crafting_station", station_id from the structure data `station`).
## Used by the workbench and, through structure_factory LAZY_SCRIPTS, by the Loom & Dye Bench (station "loom")
## and the Kitchen Counter (station "kitchen"). The furnace extends this script (structures/furnace.gd).
## Interacting opens the crafting panel filtered to this station.

const STATION_HINTS := {
	"workbench": ["workbench_crafting", "Recipes that need a Workbench can be crafted while you stand near one. Press {craft} any time."],
	"loom": ["loom_crafting", "Weave cloth, sew clothing patterns and mix dyes at the Loom. A pattern or dye is yours forever once made."],
	"kitchen": ["kitchen_crafting", "The kitchen cooks festival dishes. The campfire still cooks all its old recipes."],
}

var station_id: String = "workbench"


func _setup_behaviour() -> void:
	station_id = String(def.get("station", "workbench"))
	add_to_group("crafting_station")


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Use %s" % display_name(), "enabled": true}


func interact(_player: Node) -> void:
	Game.open_panel("crafting", {"station": station_id})
	var h: Array = STATION_HINTS.get(station_id, STATION_HINTS["workbench"])
	Events.hint.emit(String(h[0]), String(h[1]))
