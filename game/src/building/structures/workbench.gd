extends "res://src/building/structure.gd"
## Workbench: a crafting station (group "crafting_station", station_id "workbench").
## Interacting opens the crafting panel filtered to this station.

var station_id: String = "workbench"


func _setup_behaviour() -> void:
	station_id = String(def.get("station", "workbench"))
	add_to_group("crafting_station")


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Use %s" % display_name(), "enabled": true}


func interact(_player: Node) -> void:
	Game.open_panel("crafting", {"station": station_id})
	Events.hint.emit("workbench_crafting", "Recipes that need a Workbench can be crafted while you stand near one. Press {craft} any time.")
