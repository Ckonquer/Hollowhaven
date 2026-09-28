extends Node3D
## Hask's lamp beside the rail (room 3, "Hask's Last Knock"): the TRUE signal. A real lantern on a post: it
## has a Light3D, lights the rail and the floor around it, is in group "light_source" (Combat.light_at) and
## is NOT a "flicker_light" (a true light burns steady; the director never makes it stutter).
## knock_pulse(): the lantern swings, brightens for a moment and shakes a little dust off the bracket - the
## visible half of the answer, so the choice never depends on sound. reduce_flashing keeps the brightening
## gentle; high_visibility_cues adds a bold ring around the lantern for a few seconds.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const TIMBER := Color("7a5a40")
const IRON := Color("333a46")
const GLOW := Color("ffcf86")
const BASE_ENERGY := 1.7

var light_radius: float = 5.5          # read by Combat.light_at
var light: OmniLight3D
var pulses: int = 0                    # knock pulses shown (tests)

var _hang: Node3D
var _flame: Node3D
var _ring: Node3D
var _tween: Tween
var _t: float = 0.0


func _ready() -> void:
	add_to_group("light_source")
	var wood := Mat.outlined(Mat.toon(TIMBER), 0.016)
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.4}), 0.012)
	Kit.add(self, Kit.box(Vector3(0.18, 2.3, 0.18), wood), Vector3(0, 1.15, 0))
	Kit.add(self, Kit.box(Vector3(0.12, 0.12, 0.8), wood), Vector3(0, 2.2, 0.3))
	Kit.add(self, Kit.box(Vector3(0.36, 0.1, 0.36), iron), Vector3(0, 0.05, 0))
	_hang = Node3D.new()
	_hang.name = "Lantern"
	add_child(_hang)
	_hang.position = Vector3(0, 2.14, 0.62)
	Kit.add(_hang, Kit.cylinder(0.01, 0.01, 0.3, iron, 5), Vector3(0, -0.15, 0))
	var lan := Node3D.new()
	_hang.add_child(lan)
	lan.position = Vector3(0, -0.66, 0)
	Kit.add(lan, Kit.cylinder(0.13, 0.15, 0.05, iron, 10), Vector3.ZERO)
	Kit.add(lan, Kit.cone(0.15, 0.12, iron, 10), Vector3(0, 0.36, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + PI * 0.25
		Kit.add(lan, Kit.box(Vector3(0.025, 0.3, 0.025), iron), Vector3(cos(a) * 0.11, 0.17, sin(a) * 0.11))
	Kit.add(lan, Kit.cylinder(0.1, 0.1, 0.28, Mat.transparent(Color(1.0, 0.82, 0.55, 0.3), true), 10), Vector3(0, 0.17, 0))
	_flame = Node3D.new()
	lan.add_child(_flame)
	_flame.position = Vector3(0, 0.15, 0)
	Kit.add(_flame, Kit.sphere(0.055, Mat.glow(GLOW, 3.2), 6, 8), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.5, 1.0))
	light = OmniLight3D.new()
	light.name = "Light"
	light.light_color = GLOW
	light.light_energy = BASE_ENERGY
	light.omni_range = 7.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = true
	light.shadow_bias = 0.08
	light.distance_fade_enabled = true
	light.distance_fade_begin = 36.0
	light.distance_fade_length = 10.0
	light.distance_fade_shadow = 22.0
	light.light_volumetric_fog_energy = 0.5
	lan.add_child(light)
	light.position = Vector3(0, 0.2, 0)


func is_light_active() -> bool:
	return true


func _process(delta: float) -> void:
	_t += delta
	if _tween != null and _tween.is_running():
		return
	light.light_energy = BASE_ENERGY * (1.0 + sin(_t * 5.3) * 0.02)
	if _ring != null and _ring.visible:
		_ring.rotation.y += delta * 0.8


## The visible answer to a knock.
func knock_pulse() -> void:
	pulses += 1
	var gentle := bool(Settings.get_value("reduce_flashing"))
	var peak := BASE_ENERGY * (1.35 if gentle else 1.9)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(light, "light_energy", peak, 0.25).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_hang, "rotation", Vector3(0.0, 0.0, 0.32), 0.25).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_property(_hang, "rotation", Vector3(0.0, 0.0, -0.22), 0.5).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(light, "light_energy", BASE_ENERGY, 1.4).set_trans(Tween.TRANS_SINE)
	_tween.chain().tween_property(_hang, "rotation", Vector3.ZERO, 0.9).set_trans(Tween.TRANS_SINE)
	_dust()
	if bool(Settings.get_value("high_visibility_cues")):
		show_marker(6.0)


func show_marker(seconds: float) -> void:
	if _ring == null:
		_ring = Kit.add(self, Kit.torus(0.42, 0.52, Mat.glow(Color("fff1c4"), 2.2)), Vector3(0, 1.6, 0.62))
		_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring.visible = true
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(_ring):
			_ring.visible = false)


func _dust() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 18
	p.lifetime = 1.6
	p.explosiveness = 0.85
	p.direction = Vector3.DOWN
	p.spread = 35.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.7
	p.gravity = Vector3(0, -1.2, 0)
	p.scale_amount_min = 0.02
	p.scale_amount_max = 0.05
	var m := SphereMesh.new()
	m.radius = 0.5
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 3
	p.mesh = m
	p.material_override = Mat.toon(Color("c8bca6"))
	add_child(p)
	p.position = Vector3(0, 2.25, 0.4)
	p.emitting = true
	p.finished.connect(p.queue_free)
