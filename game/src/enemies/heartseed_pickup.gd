extends Node3D
## The Heartseed, freed when the Weaver Matron / Hollow Mother retreats. A warm, glowing pink seed
## that floats and beats like a tiny heart. Interact: "Take the Heartseed" -> key item "heartseed".
## Group "heartseed_pickup" (the boss uses it to never create duplicates).

signal taken

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const FLOAT_Y := 1.15

var light_radius: float = 3.0
var light_strength: float = 0.5

var _t: float = 0.0
var _seed: Node3D
var _halo: MeshInstance3D
var _light: OmniLight3D
var _pulse_t: float = 1.0
var _taken := false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("heartseed_pickup")
	add_to_group("light_source")
	_build()


func is_light_active() -> bool:
	return not _taken


func get_interaction(_player: Node) -> Dictionary:
	if _taken:
		return {}
	return {"text": "Take the Heartseed", "enabled": true}


func interact(player: Node) -> void:
	if _taken:
		return
	_taken = true
	remove_from_group("heartseed_pickup")
	remove_from_group("interactable")
	GameState.give_item("heartseed", 1)
	Audio.play_sfx("heartseed_pulse", 0.0, 0.0)
	Events.screen_flash.emit(Color(Palette.HEART_GLOW, 0.35), 0.6)
	Events.caption.emit("[a warm heartbeat]")
	taken.emit()
	var dest := global_position + Vector3.UP * 0.5
	if player is Node3D:
		dest = (player as Node3D).global_position + Vector3.UP * 1.2
	HitFx.burst(_seed.global_position, Palette.HEART_GLOW, 16, 2.4, 1.0, -1.0, 0.9)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_seed, "global_position", dest, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_seed, "scale", Vector3.ONE * 0.05, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_property(_light, "light_energy", 0.0, 0.45)
	tw.tween_property(_halo, "scale", Vector3.ONE * 0.01, 0.3)
	tw.chain().tween_callback(queue_free)


func _build() -> void:
	var heart_mat := Mat.outlined(Mat.toon(Palette.HEART_GLOW, {"rim": 0.9, "emission": Palette.HEART_GLOW, "emission_energy": 1.1, "specular": 0.5}), 0.012, Color(0.45, 0.12, 0.25))
	_seed = Node3D.new()
	Kit.add(self, _seed, Vector3(0, FLOAT_Y, 0))
	# Heart = two lobes + a rounded point
	for sx in [-1.0, 1.0]:
		Kit.add(_seed, Kit.sphere(0.15, heart_mat, 14, 18), Vector3(sx * 0.1, 0.06, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8))
	Kit.add(_seed, Kit.cone(0.2, 0.28, heart_mat, 16), Vector3(0, -0.1, 0), Vector3(180, 0, 0), Vector3(1.0, 1.0, 0.72))
	# Tiny sprout: it's a seed
	var leaf_mat := Mat.outlined(Mat.toon(Palette.FOLIAGE_LIGHT, {"rim": 0.5, "emission": Palette.FOLIAGE_LIGHT, "emission_energy": 0.3}), 0.008)
	Kit.add(_seed, Kit.cylinder(0.012, 0.016, 0.12, Mat.toon(Palette.FOLIAGE), 6), Vector3(0, 0.22, 0))
	for s in [-1.0, 1.0]:
		Kit.add(_seed, Kit.sphere(0.06, leaf_mat, 8, 10), Vector3(s * 0.05, 0.29, 0), Vector3(0, 0, s * -35.0), Vector3(1.0, 0.25, 0.6))
	# Soft halo + light
	_halo = Kit.sphere(0.34, HitFx.additive(Color(0.2, 0.05, 0.1)), 12, 16)
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, _halo, Vector3(0, FLOAT_Y, 0))
	_light = OmniLight3D.new()
	_light.light_color = Palette.HEART_GLOW
	_light.light_energy = 1.4
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, FLOAT_Y, 0)
	add_child(_light)
	# A faint beam so it can be found in a dark chamber
	var beam := Kit.cylinder(0.25, 0.4, 6.0, HitFx.additive(Color(0.12, 0.03, 0.07)), 16)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Kit.add(self, beam, Vector3(0, 3.0, 0))
	# Interaction area (layer 16)
	var area := Area3D.new()
	area.collision_layer = 16
	area.collision_mask = 0
	area.monitoring = false
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.9
	cs.shape = sph
	area.add_child(cs)
	add_child(area)
	area.position = Vector3(0, FLOAT_Y, 0)


func _process(delta: float) -> void:
	if _taken:
		return
	_t += delta
	_seed.position.y = FLOAT_Y + sin(_t * 1.6) * 0.08
	_seed.rotation.y = _t * 0.6
	# Heartbeat: two quick pulses, then rest
	var beat := fmod(_t, 1.2)
	var s := 1.0 + 0.1 * exp(-pow((beat - 0.1) * 14.0, 2.0)) + 0.07 * exp(-pow((beat - 0.33) * 14.0, 2.0))
	_seed.scale = Vector3.ONE * s
	_halo.scale = Vector3.ONE * (0.9 + (s - 1.0) * 3.0)
	_light.light_energy = 1.2 + (s - 1.0) * 5.0
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = 2.4
		Audio.play_3d("heartseed_pulse", global_position + Vector3.UP * FLOAT_Y, -10.0, 0.0, 14.0)
