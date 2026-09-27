extends Node3D
## Gentle ambient life for the surface: fireflies at night (Haven, meadow, pond, glade, ruin),
## butterflies by day, a few falling leaves around the Old Oak and the forest edge, and the warm
## firefly swirl around the Ward Stone (restoration; stays on at night once the Ward is restored).
## set_daylight(0..1) is called by the area a few times per second.

const Layout := preload("res://data/world_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")

var terrain: RefCounted
var fireflies: Array = []
var leaves: Array = []
var swirl: GPUParticles3D
var swirl_on := false
var butterflies: Array = []           # [node, home: Vector3, phase, wings: [l, r], radius]
var _daylight := 1.0
var _t := 0.0
var _cam_check := 0.0
var _cam_pos := Vector3.ZERO
var _swirl_forced := false


func _ready() -> void:
	name = "AmbientLife"
	var spots: Array = [[Vector2(0, 0), 15.0, 34], [Layout.LANDMARKS["meadow"]["pos"], 20.0, 40], [Vector2(46, 52), 14.0, 28],
		[Layout.LANDMARKS["glade"]["pos"], 14.0, 26], [Layout.LANDMARKS["ruin"]["pos"], 10.0, 18], [Layout.LANDMARKS["old_oak"]["pos"], 9.0, 16]]
	for s in spots:
		var p: Vector2 = s[0]
		var ff := _fireflies(float(s[1]), int(s[2]))
		ff.position = Vector3(p.x, terrain.height_at(p.x, p.y) + 0.9, p.y)
		add_child(ff)
		fireflies.append(ff)
	var oak: Vector2 = Layout.LANDMARKS["old_oak"]["pos"]
	var leaf_spots: Array = [[oak, 7.0, 9.5, 14], [Vector2(-24, 22), 10.0, 6.0, 8], [Vector2(26, -24), 10.0, 6.0, 8], [Vector2(-20, -40), 10.0, 6.5, 8]]
	for l in leaf_spots:
		var p: Vector2 = l[0]
		var lf := _leaves(float(l[1]), int(l[3]))
		lf.position = Vector3(p.x, terrain.height_at(p.x, p.y) + float(l[2]), p.y)
		add_child(lf)
		leaves.append(lf)
	swirl = _swirl()
	var ws := SL.WARD_STONE
	swirl.position = Vector3(ws.x, terrain.height_at(ws.x, ws.y) + 0.4, ws.y)
	add_child(swirl)
	var bspots: Array = [[Layout.LANDMARKS["meadow"]["pos"], 5], [Vector2(0, 17), 3], [Vector2(-14, 4), 2], [Layout.LANDMARKS["glade"]["pos"], 3], [Vector2(40, 44), 2]]
	var cols := [Palette.FLOWER_YELLOW, Palette.BLOSSOM, Palette.FLOWER_BLUE, Palette.FLOWER_WHITE, Palette.CLOTH_RED, Palette.FLOWER_PURPLE]
	var i := 0
	for b in bspots:
		for k in int(b[1]):
			var p: Vector2 = b[0] + Vector2(cos(float(i) * 2.4), sin(float(i) * 2.4)) * (2.0 + float(k) * 1.6)
			_add_butterfly(Vector3(p.x, terrain.height_at(p.x, p.y), p.y), cols[i % cols.size()], float(i) * 1.37)
			i += 1


func _fireflies(radius: float, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.randomness = 0.5
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius, 1.0, radius)
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3.ZERO
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 3.5
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.2, Color(1, 1, 1, 1))
	ramp.add_point(0.5, Color(1, 1, 1, 0.35))
	ramp.add_point(0.8, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.045
	m.height = 0.09
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color("fff49a")
	mat.emission_enabled = true
	mat.emission = Color("e8ff8a")
	mat.emission_energy_multiplier = 3.0
	m.surface_set_material(0, mat)
	p.draw_pass_1 = m
	p.visibility_aabb = AABB(Vector3(-radius - 3, -3, -radius - 3), Vector3(radius * 2 + 6, 7, radius * 2 + 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


func _leaves(radius: float, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 10.0
	p.preprocess = 10.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius, 1.0, radius)
	pm.gravity = Vector3(0.15, -0.55, 0.05)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.2
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 2.5
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.25
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	var g := Gradient.new()
	g.set_color(0, Palette.FOLIAGE)
	g.set_color(1, Palette.FOLIAGE_AUTUMN)
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.add_point(0.5, Palette.FOLIAGE_LIGHT)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.1)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	q.surface_set_material(0, mat)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-radius - 2, -12, -radius - 2), Vector3(radius * 2 + 4, 14, radius * 2 + 4))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _swirl() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 5.0
	p.preprocess = 2.0
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 3.6
	pm.emission_ring_inner_radius = 2.2
	pm.emission_ring_height = 0.5
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 0.12, 0)
	pm.orbit_velocity_min = 0.12
	pm.orbit_velocity_max = 0.22
	pm.radial_velocity_min = -0.15
	pm.radial_velocity_max = 0.05
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.15, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var m := SphereMesh.new()
	m.radius = 0.05
	m.height = 0.1
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color("ffe6a0")
	mat.emission_enabled = true
	mat.emission = Color("ffd98a")
	mat.emission_energy_multiplier = 3.5
	m.surface_set_material(0, mat)
	p.draw_pass_1 = m
	p.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 9, 12))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


func _add_butterfly(home: Vector3, color: Color, phase: float) -> void:
	var root := Node3D.new()
	root.name = "Butterfly"
	add_child(root)
	root.position = home + Vector3(0, 1.0, 0)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.018
	cm.height = 0.13
	cm.radial_segments = 6
	cm.rings = 2
	body.mesh = cm
	body.material_override = Mat.toon(Color("3b2f35"))
	body.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(body)
	var wing_mesh := _wing_mesh()
	var wmat := Mat.toon(color, {"rim": 0.6})
	var wings: Array = []
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		root.add_child(pivot)
		var w := MeshInstance3D.new()
		w.mesh = wing_mesh
		w.material_override = wmat
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.scale = Vector3(float(sx), 1, 1)
		pivot.add_child(w)
		wings.append(pivot)
	root.visible = false
	butterflies.append([root, home, phase, wings, 2.5 + fmod(phase, 1.5)])


static func _wing_mesh() -> ArrayMesh:
	var verts := PackedVector3Array([Vector3(0, 0, -0.03), Vector3(0.13, 0, -0.1), Vector3(0.15, 0, 0.0),
		Vector3(0, 0, 0.0), Vector3(0.15, 0, 0.0), Vector3(0.1, 0, 0.09), Vector3(0, 0, 0.04)])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3, 3, 4, 5, 3, 5, 6])
	var back := PackedInt32Array()
	for i in range(0, idx.size(), 3):
		back.append_array(PackedInt32Array([idx[i], idx[i + 2], idx[i + 1]]))
	idx.append_array(back)
	var norms := PackedVector3Array()
	for v in verts:
		norms.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## 0 = night .. 1 = full day.
func set_daylight(daylight: float) -> void:
	_daylight = daylight
	var night := clampf(1.0 - daylight * 2.2, 0.0, 1.0)
	for ff in fireflies:
		var p := ff as GPUParticles3D
		p.emitting = night > 0.05
		p.amount_ratio = night
	var day_bugs := daylight > 0.45
	for b in butterflies:
		(b[0] as Node3D).visible = day_bugs
	if swirl != null:
		var want := swirl_on and (night > 0.1 or _swirl_forced)
		swirl.emitting = want
		swirl.amount_ratio = 1.0 if _swirl_forced else clampf(night, 0.3, 0.8)



## Restoration: a bright swirl for the ceremony (forced), then it keeps glowing at night.
func start_swirl(forced: bool) -> void:
	swirl_on = true
	_swirl_forced = forced
	set_daylight(_daylight)


func _process(delta: float) -> void:
	_t += delta
	if _daylight <= 0.45 or butterflies.is_empty():
		return
	_cam_check -= delta
	if _cam_check <= 0.0:
		_cam_check = 0.5
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			_cam_pos = cam.global_position
	for b in butterflies:
		var root: Node3D = b[0]
		var home: Vector3 = b[1]
		if home.distance_squared_to(_cam_pos) > 3600.0:
			continue
		var ph: float = b[2]
		var r: float = b[4]
		var t := _t * 0.35 + ph
		var p := home + Vector3(sin(t) * r + sin(t * 2.3) * 0.6, 0.9 + sin(t * 1.7) * 0.45 + sin(t * 5.1) * 0.08, cos(t * 0.8) * r + cos(t * 2.9) * 0.5)
		var vel := p - root.position
		root.position = p
		if vel.length() > 0.0001:
			var flat := Vector3(vel.x, 0, vel.z)
			if flat.length() > 0.0001:
				root.rotation.y = atan2(-flat.x, -flat.z)
		var flap := sin(_t * 18.0 + ph * 3.0) * 0.9 + 0.2
		var wings: Array = b[3]
		(wings[0] as Node3D).rotation.z = -flap
		(wings[1] as Node3D).rotation.z = flap
