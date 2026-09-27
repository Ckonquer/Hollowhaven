extends "res://src/building/structure.gd"
## Echo chime: its crystal shards sway gently on their threads and shimmer softly.

var _t := 0.0
var _phases: Array = []


func _setup_behaviour() -> void:
	_t = randf() * 10.0
	for i in (parts.get("shards", []) as Array).size():
		_phases.append(randf() * TAU)


func _process(delta: float) -> void:
	_t += delta
	var shards: Array = parts.get("shards", [])
	var gust := 0.6 + 0.4 * sin(_t * 0.37)
	for i in shards.size():
		var s: Node3D = shards[i]
		var ph: float = _phases[i] if i < _phases.size() else 0.0
		s.rotation = Vector3(sin(_t * 1.25 + ph) * 0.12 * gust, sin(_t * 0.5 + ph) * 0.4, cos(_t * 1.05 + ph * 1.3) * 0.1 * gust)
	var mat: Variant = parts.get("shard_mat")
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("emission_energy", 0.3 + 0.2 * (0.5 + 0.5 * sin(_t * 1.7)))
