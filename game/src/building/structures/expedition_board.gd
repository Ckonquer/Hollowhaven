extends "res://src/building/structure.gd"
## Expedition Board (data interact "board"): a pin board of optional discoveries. Interacting opens the
## journal on its Optional tab (optional discoveries, trials, crafting possibilities); nothing here is a daily
## chore. ("goals" would be the journal's Chapter One alias for the Story tab, so the tab is named exactly.)

const PANEL := "journal"
const TAB := "optional"


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Read the Expedition Board", "enabled": true}


## Arguments the board opens the journal with.
func panel_args() -> Dictionary:
	return {"tab": TAB, "source": structure_id}


func interact(_player: Node) -> void:
	Game.open_panel(PANEL, panel_args())
