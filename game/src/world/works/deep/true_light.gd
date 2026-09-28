extends Node3D
## A plain light-source marker (group "light_source") for Combat.light_at: the anchored flame of the
## Borrowed Porch really lights the ground, so darkness-sensitive things treat it as light too.

var light_radius: float = 4.5
var light_strength: float = 1.0
var active: bool = true


func _ready() -> void:
	add_to_group("light_source")


func is_light_active() -> bool:
	return active
