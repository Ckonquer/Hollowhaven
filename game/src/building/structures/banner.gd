extends "res://src/building/structure.gd"
## Haven banner: the teal cloth sways gently in the breeze from its crossbar.

var _t := 0.0


func _setup_behaviour() -> void:
	_t = randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	var cloth: Variant = parts.get("cloth")
	if cloth is Node3D:
		(cloth as Node3D).rotation = Vector3(sin(_t * 0.9) * 0.07 + sin(_t * 2.3) * 0.02, 0.0, sin(_t * 0.6 + 1.0) * 0.025)
