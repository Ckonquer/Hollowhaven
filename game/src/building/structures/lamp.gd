extends "res://src/building/structure.gd"
## Lantern post / heartbloom lamp: a warm OmniLight3D (no shadows, distance-faded) in group
## "light_source" (light_radius + is_light_active() per the combat contract). Brighter at night,
## a gentle flame flicker for the lantern and a heartbeat pulse for the heartbloom.

var light_radius: float = 5.0
var light: OmniLight3D
var _base_energy := 1.5
var _night := 1.0
var _t := 0.0
var _heart := false


func _setup_behaviour() -> void:
	var ld: Dictionary = def.get("light", {})
	_base_energy = float(ld.get("energy", 1.5))
	_heart = structure_id == "heartbloom_lamp"
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = ld.get("color", Palette.LANTERN_GLOW)
	light.omni_range = float(ld.get("range", 6.0))
	light.omni_attenuation = 1.2
	light.light_energy = _base_energy
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 38.0
	light.distance_fade_length = 10.0
	light.position = parts.get("light_pos", Vector3(0, 1.5, 0))
	add_child(light)
	light_radius = light.omni_range * 0.7
	add_to_group("light_source")
	_t = randf() * 20.0
	Events.time_of_day_changed.connect(_on_time_changed)
	_on_time_changed(GameState.day(), GameState.time_of_day())


func is_light_active() -> bool:
	return not _removing


func _on_time_changed(_day: int, _tod: float) -> void:
	var h := GameState.hour()
	# 0 in full daylight, 1 at night, smooth over dusk and dawn.
	var dusk := smoothstep(16.5, 19.5, h)
	var dawn := 1.0 - smoothstep(5.0, 7.5, h)
	_night = maxf(dusk, dawn)


func _process(delta: float) -> void:
	if light == null:
		return
	_t += delta
	var wobble: float
	if _heart:
		var beat := pow(maxf(sin(_t * 2.4), 0.0), 6.0)
		wobble = 1.0 + beat * 0.18 + sin(_t * 0.7) * 0.05
		var bulb: Variant = parts.get("bulb")
		if bulb is Node3D:
			(bulb as Node3D).scale = Vector3.ONE * (1.0 + beat * 0.07)
	else:
		wobble = 1.0 + sin(_t * 7.3) * 0.035 + sin(_t * 12.9 + 1.3) * 0.025
		var flame: Variant = parts.get("flame")
		if flame is Node3D:
			(flame as Node3D).scale = Vector3(1.0, 1.25 + sin(_t * 9.0) * 0.05, 1.0)
	light.light_energy = _base_energy * lerpf(0.25, 0.85, _night) * wobble
