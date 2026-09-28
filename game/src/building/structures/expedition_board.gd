extends "res://src/building/structure.gd"
## Expedition Board (data interact "board"; recipe unlocked by ch2_choir_defeated). Interacting opens the
## Lanternwake Expeditions panel ("expedition", src/ui/panels/expedition_panel.gd: three hand-authored replay
## routes, difficulty and reward types shown before starting, MP §15). Its second option - the journal on its
## Optional tab (optional discoveries, trials, crafting possibilities) - is the panel's "Optional journal"
## button; while the UI root has no "expedition" panel registered the board opens that journal page directly
## (the pre-expedition behaviour). Nothing here is a daily chore. ("goals" would be the journal's Chapter One
## alias for the Story tab, so the tab is named exactly.)

const PANEL := "journal"
const TAB := "optional"
const EXPEDITION_PANEL := "expedition"
const Ex := preload("res://src/expeditions/expeditions.gd")


func get_interaction(_player: Node) -> Dictionary:
	if Ex.is_active():
		return {"text": "Check the Expedition Board (expedition under way)", "enabled": true}
	return {"text": "Read the Expedition Board", "enabled": true}


## Arguments of the board's Optional-journal option (the journal on its Optional tab).
func panel_args() -> Dictionary:
	return {"tab": TAB, "source": structure_id}


## Arguments the board opens the expedition panel with.
func expedition_args() -> Dictionary:
	var a := Ex.active()
	return {"source": structure_id, "template": String(a.get("template", "")) if not a.is_empty() else ""}


## The panel the board opens right now: "expedition" when the UI root offers it, else the journal.
func target_panel() -> String:
	var ui: Node = Game.ui
	if ui != null and is_instance_valid(ui) and ui.has_method("has_panel") and bool(ui.call("has_panel", EXPEDITION_PANEL)):
		return EXPEDITION_PANEL
	return PANEL


func interact(_player: Node) -> void:
	# Until Game wires Expeditions.init() at start-up, reading the board wires it (the Reach then gets its runner).
	Ex.init()
	if target_panel() == EXPEDITION_PANEL:
		Game.open_panel(EXPEDITION_PANEL, expedition_args())
	else:
		Game.open_panel(PANEL, panel_args())
