extends RefCounted
## Small, restrained one-shot particle bursts for gathering feedback (shared surface/Below).
##   const Fx := preload("res://src/world/common/fx.gd")
##   Fx.burst(get_parent(), global_position + Vector3.UP, "chips")
## Kinds: leaves, blossom, chips, dust, berries, grass, copper, sparkle, silk, crystal, splash.
## Each burst is a CPUParticles3D that frees itself; meshes/materials are shared.

const Palette := preload("res://src/art/palette.gd")

const KINDS := {
	"leaves": {"colors": [Color("6fae4f"), Color("9ccf62"), Color("467d3f"), Color("e9a15b")], "mesh": "leaf", "amount": 12, "vel": [1.5, 3.2], "grav": -2.2, "life": 1.8, "size": [0.7, 1.2], "damp": 1.2, "spread": 80.0},
	"blossom": {"colors": [Color("f2a7c0"), Color("ffd9e6"), Color("e27f9f")], "mesh": "leaf", "amount": 12, "vel": [1.5, 3.0], "grav": -1.8, "life": 2.0, "size": [0.6, 1.0], "damp": 1.3, "spread": 80.0},
	"chips": {"colors": [Color("b8b2a7"), Color("8f897f"), Color("d4cfc4")], "mesh": "chip", "amount": 9, "vel": [2.5, 4.5], "grav": -14.0, "life": 0.8, "size": [0.6, 1.2], "damp": 0.5, "spread": 55.0},
	"dust": {"colors": [Color(0.86, 0.8, 0.7, 0.8), Color(0.76, 0.7, 0.62, 0.7)], "mesh": "puff", "amount": 8, "vel": [0.8, 1.8], "grav": 0.4, "life": 1.1, "size": [0.8, 1.6], "damp": 2.0, "spread": 90.0},
	"berries": {"colors": [Color("d9446a"), Color("e4665c"), Color("ff8fa8")], "mesh": "ball", "amount": 7, "vel": [1.5, 3.0], "grav": -12.0, "life": 0.7, "size": [0.7, 1.0], "damp": 0.5, "spread": 60.0},
	"grass": {"colors": [Color("8cc063"), Color("b5d977"), Color("d9d47a")], "mesh": "leaf", "amount": 9, "vel": [1.2, 2.6], "grav": -3.0, "life": 1.0, "size": [0.5, 0.9], "damp": 1.5, "spread": 70.0},
	"copper": {"colors": [Color("d98b4e"), Color("ffcf8a"), Color("8f897f")], "mesh": "chip", "amount": 10, "vel": [2.5, 4.5], "grav": -14.0, "life": 0.8, "size": [0.5, 1.0], "damp": 0.5, "spread": 55.0},
	"sparkle": {"colors": [Color("fff4c8"), Color("ffe2a0"), Color("ffffff")], "mesh": "glow", "amount": 10, "vel": [0.6, 1.6], "grav": 0.8, "life": 0.9, "size": [0.6, 1.2], "damp": 1.5, "spread": 180.0},
	"silk": {"colors": [Color("f4f1fa"), Color("e8e4f0")], "mesh": "puff", "amount": 8, "vel": [0.6, 1.4], "grav": -0.6, "life": 1.4, "size": [0.5, 0.9], "damp": 1.8, "spread": 120.0},
	"crystal": {"colors": [Color("b9a3f0"), Color("e6dcff")], "mesh": "glow", "amount": 10, "vel": [2.0, 3.5], "grav": -8.0, "life": 0.8, "size": [0.5, 0.9], "damp": 0.8, "spread": 70.0},
	"splash": {"colors": [Color(0.85, 0.95, 1.0, 0.9), Color(0.6, 0.85, 0.95, 0.8)], "mesh": "ball", "amount": 10, "vel": [1.5, 3.0], "grav": -9.0, "life": 0.6, "size": [0.4, 0.8], "damp": 0.3, "spread": 45.0},
}

static var _meshes: Dictionary = {}


static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var mesh: Mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	match kind:
		"leaf":
			var q := QuadMesh.new()
			q.size = Vector2(0.12, 0.08)
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh = q
		"chip":
			var b := BoxMesh.new()
			b.size = Vector3(0.09, 0.07, 0.08)
			mesh = b
		"ball":
			var s := SphereMesh.new()
			s.radius = 0.05
			s.height = 0.1
			s.rings = 4
			s.radial_segments = 6
			mesh = s
		"puff":
			var s2 := SphereMesh.new()
			s2.radius = 0.14
			s2.height = 0.28
			s2.rings = 4
			s2.radial_segments = 8
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh = s2
		_:
			var s3 := SphereMesh.new()
			s3.radius = 0.035
			s3.height = 0.07
			s3.rings = 3
			s3.radial_segments = 6
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.9, 0.7)
			mat.emission_energy_multiplier = 2.0
			mesh = s3
	mesh.surface_set_material(0, mat)
	_meshes[kind] = mesh
	return mesh


static func _gradient(colors: Array) -> Gradient:
	var key := "grad|%s" % str(colors)
	if _meshes.has(key):
		return _meshes[key]
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / maxf(float(colors.size() - 1), 1.0))
		cols.append(colors[i])
	g.offsets = offsets
	g.colors = cols
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	_meshes[key] = g
	return g


static func _fade_curve() -> Curve:
	if _meshes.has("fade_curve"):
		return _meshes["fade_curve"]
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(0.7, 0.9))
	fade.add_point(Vector2(1.0, 0.0))
	_meshes["fade_curve"] = fade
	return fade


## Spawns a one-shot burst at a world position. amount_scale scales the particle count (0.5 = half).
static func burst(parent: Node, pos: Vector3, kind: String, amount_scale: float = 1.0, dir: Vector3 = Vector3.UP) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	var d: Dictionary = KINDS.get(kind, KINDS["dust"])
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = maxi(2, int(round(float(d["amount"]) * amount_scale)))
	p.lifetime = float(d["life"])
	p.mesh = _mesh(String(d["mesh"]))
	p.direction = dir if dir.length() > 0.01 else Vector3.UP
	p.spread = float(d["spread"])
	var vel: Array = d["vel"]
	p.initial_velocity_min = float(vel[0])
	p.initial_velocity_max = float(vel[1])
	p.gravity = Vector3(0, float(d["grav"]), 0)
	p.damping_min = float(d["damp"])
	p.damping_max = float(d["damp"]) * 1.5
	var sz: Array = d["size"]
	p.scale_amount_min = float(sz[0])
	p.scale_amount_max = float(sz[1])
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.angular_velocity_min = -220.0
	p.angular_velocity_max = 220.0
	p.color_initial_ramp = _gradient(d["colors"])
	p.scale_amount_curve = _fade_curve()
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	# Free the burst when it is done. Connect to the node's own method (not a lambda capturing it):
	# if the area is freed first (area change), the connection dies with the node instead of the timer
	# later calling a lambda whose capture is gone ("Lambda capture at index 0 was freed").
	p.finished.connect(p.queue_free)
	var tree := parent.get_tree()
	if tree != null:
		tree.create_timer(p.lifetime + 1.0, false).timeout.connect(p.queue_free)
