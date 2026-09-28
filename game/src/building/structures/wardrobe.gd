extends "res://src/building/structure.gd"
## Wardrobe and Vanity Mirror (data/structures.gd interact "wardrobe"): "Change your look" opens the
## wardrobe panel (Game.open_panel("wardrobe")). Styling there is always free and cosmetic only.
## Mapped by structure_factory.gd for the ids `wardrobe` and `vanity_mirror` (spec §9 LAZY_SCRIPTS).

const PANEL := "wardrobe"


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Change your look", "enabled": true}


func interact(_player: Node) -> void:
	Game.open_panel(PANEL, {"source": structure_id})
