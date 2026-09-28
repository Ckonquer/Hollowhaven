extends "res://src/building/structure.gd"
## Thread Veil (the Weaver's Crossing keepsake). With the arachnophobia setting on it is a "Pale Veil Drape":
## soft sheer cloth, no strands or rosette (structure_models.gd builds the variant from the setting). The
## model is rebuilt when the setting changes while it is on screen.


func _setup_behaviour() -> void:
	Events.settings_changed.connect(_on_settings_changed)


func display_name() -> String:
	return ItemDB.structure_display_name(structure_id)


func _on_settings_changed(key: String) -> void:
	if key == "arachnophobia" or key == "":
		rebuild_model()
