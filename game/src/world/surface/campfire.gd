extends Node3D
## The Haven campfire: stone ring, crossed logs, toon flames, sparks and a flickering warm light
## (the only shadowed light besides the sun). Crafting station "campfire":
## group "crafting_station" (station_id), group "interactable" -> Game.open_panel("crafting", {"station": "campfire"}),
## group "light_source" (light_radius / is_light_active).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const FLAME_SHADER := preload("res://shaders/surface_flame.gdshader")

var station_id: String = "campfire"
var light_radius: float = 7.0
var light: OmniLight3D
var _flames: Array = []
var _t := 0.0
var _base_energy := 1.7


func _ready() -> void:
	name = "Campfire"
	add_to_group("crafting_station")
	add_to_group("interactable")
	add_to_group("light_source")
	_build()


func is_light_active() -> bool:
	return true


func get_interaction(_player: Node = null) -> Dictionary:
	return {"text": "Cook at the Campfire", "enabled": true}


func interact(_player: Node = null) -> void:
	Game.open_panel("crafting", {"station": "campfire"})


func _build() -> void:
	var stone_mat := NodeVisuals.rock_material(0.022)
	# Stone ring
	for i in 9:
		var a := TAU * float(i) / 9.0
		var st := Props.instance(Props.stone_block(40 + i % 4, Vector3(0.42, 0.3, 0.36), Palette.STONE.darkened(0.05 * float(i % 3)), 0.3), stone_mat, 90.0)
		st.position = Vector3(cos(a) * 0.78, -0.04, sin(a) * 0.78)
		st.rotation.y = -a
		add_child(st)
	# Ash bed + embers
	var ash := MeshInstance3D.new()
	ash.mesh = NodeVisuals._cyl(0.62, 0.66, 0.06, 14)
	ash.material_override = Mat.toon(Color("5a4a44"))
	ash.position = Vector3(0, 0.0, 0)
	add_child(ash)
	var embers := NodeVisuals.Merger.new()
	for i in 7:
		var a := float(i) * 2.4
		embers.add(Kit.blob_mesh(0.07, 9200 + i, 0.3, 0.6, 1), Transform3D(Basis(), Vector3(cos(a) * 0.3, 0.05, sin(a) * 0.3)), Color.WHITE)
	var em := MeshInstance3D.new()
	em.mesh = embers.commit()
	em.material_override = Mat.glow(Color("ff8a3c"), 2.2)
	em.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(em)
	# Logs in a little teepee
	var bark := NodeVisuals.bark_material()
	var logs := NodeVisuals.Merger.new()
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.4
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(62.0))
		var fn := func(p: Vector3, _n: Vector3) -> Color:
			return Color("3a2a24").lerp(Palette.BARK, clampf(0.9 - p.y * 1.4, 0.0, 1.0))
		logs.add(NodeVisuals._cyl(0.07, 0.085, 0.95, 8), Transform3D(b, b * Vector3(0, 0.1, 0) + Vector3(0, 0.3, 0)), fn)
	var lm := MeshInstance3D.new()
	lm.mesh = logs.commit()
	lm.material_override = bark
	add_child(lm)
	# Flames: billboarded toon flame quads (surface_flame.gdshader), gently scaled in _process.
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var fl: Array = [[Vector2(0.95, 1.35), Vector3(0.0, 0.0, 0.0), 0.0], [Vector2(0.62, 1.0), Vector3(0.14, 0.0, 0.08), 1.7], [Vector2(0.55, 0.85), Vector3(-0.13, 0.0, -0.06), 3.1]]
	for i in fl.size():
		var d: Array = fl[i]
		var sz: Vector2 = d[0]
		var mat := ShaderMaterial.new()
		mat.shader = FLAME_SHADER
		mat.set_shader_parameter("seed", float(d[2]))
		mat.set_shader_parameter("speed", 2.0 + float(i) * 0.35)
		mat.render_priority = i
		var f := MeshInstance3D.new()
		f.mesh = quad
		f.material_override = mat
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var base := Vector3(sz.x, sz.y, 1.0)
		f.scale = base
		f.position = (d[1] as Vector3) + Vector3(0, 0.18 + sz.y * 0.5, 0)
		add_child(f)
		_flames.append([f, base, float(d[2]), f.position])
	# Sparks drifting up
	var sparks := CPUParticles3D.new()
	sparks.amount = 14
	sparks.lifetime = 1.6
	sparks.randomness = 0.6
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.036
	sm.radial_segments = 4
	sm.rings = 2
	sm.surface_set_material(0, Mat.glow(Color("ffc46a"), 3.0))
	sparks.mesh = sm
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.2
	sparks.direction = Vector3.UP
	sparks.spread = 18.0
	sparks.initial_velocity_min = 0.7
	sparks.initial_velocity_max = 1.5
	sparks.gravity = Vector3(0.15, 0.25, 0.0)
	sparks.damping_min = 0.2
	sparks.damping_max = 0.5
	sparks.position = Vector3(0, 0.6, 0)
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sparks)
	# Smoke: a few soft puffs
	var smoke := CPUParticles3D.new()
	smoke.amount = 6
	smoke.lifetime = 3.5
	var pm := SphereMesh.new()
	pm.radius = 0.18
	pm.height = 0.36
	pm.radial_segments = 8
	pm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.85, 0.82, 0.8, 0.22)
	smat.vertex_color_use_as_albedo = true
	pm.surface_set_material(0, smat)
	smoke.mesh = pm
	smoke.direction = Vector3.UP
	smoke.spread = 10.0
	smoke.initial_velocity_min = 0.4
	smoke.initial_velocity_max = 0.6
	smoke.gravity = Vector3(0.1, 0.15, 0.05)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.2))
	smoke.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	smoke.color_ramp = fade
	smoke.position = Vector3(0, 1.1, 0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	# Light
	light = OmniLight3D.new()
	light.light_color = Color("ffb35c")
	light.light_energy = _base_energy
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.shadow_bias = 0.08
	light.position = Vector3(0, 1.0, 0)
	add_child(light)
	# Collision so nobody walks into the fire, and the interaction collider.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 0.5
	cs.shape = cyl
	cs.position = Vector3(0, 0.25, 0)
	body.add_child(cs)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.35
	ics.shape = sph
	ics.position = Vector3(0, 0.6, 0)
	ib.add_child(ics)
	add_child(ib)


func _process(delta: float) -> void:
	_t += delta
	for f in _flames:
		var mi: MeshInstance3D = f[0]
		var base: Vector3 = f[1]
		var ph: float = f[2]
		var home: Vector3 = f[3]
		var s := 1.0 + sin(_t * 7.0 + ph) * 0.06 + sin(_t * 11.3 + ph * 2.0) * 0.04
		mi.scale = Vector3(base.x * (2.0 - s), base.y * s, 1.0)
		mi.position = home + Vector3(0, (s - 1.0) * base.y * 0.5, 0)
	if light != null:
		var flick := sin(_t * 11.0) * 0.12 + sin(_t * 17.3) * 0.08 + sin(_t * 3.1) * 0.1
		light.light_energy = _base_energy * (1.0 + flick)
