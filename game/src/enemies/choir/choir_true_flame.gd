extends Node3D
## The kept flame's light-source marker (group "light_source", read by Combat.light_at): the ONE true light in
## Phase C really lights the floor of its sector, so everything that trusts real light (Borrowed Wisps, the
## Gloomling rule, companions) treats it as light. The false cozy lights never join this group.

var light_radius: float = 3.6
var light_strength: float = 1.0
var lit: bool = false


func _ready() -> void:
	add_to_group("light_source")


func is_light_active() -> bool:
	return lit and is_visible_in_tree()
