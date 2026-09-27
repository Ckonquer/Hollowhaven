extends RefCounted
## Flower meshes + MultiMesh builder (surface_flower.gdshader). Petal colours per instance.
##   Flora.build_field(parent, placements, material) -> MultiMeshInstance3D
## placements: Array of [Vector3 pos, float yaw, float scale, Color petal, float bloom_dist, int kind]

const Palette := preload("res://src/art/palette.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const FLOWER_SHADER := preload("res://shaders/surface_flower.gdshader")

const PETAL_COLORS := [Color("fff4e0"), Color("f6d25a"), Color("e4665c"), Color("8fb6f0"), Color("b48ad8"), Color("f2a7c0")]

static var _meshes: Dictionary = {}


## kind 0: daisy-like five-petal flower; kind 1: little tulip cup; kind 2: tiny cluster of bells.
static func flower_mesh(kind: int) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var m := NodeVisuals.Merger.new()
	var stem := Color(0.37, 0.6, 0.27, 0.0)      # alpha 0 = not tinted
	var tint := Color(1, 1, 1, 1)                 # alpha 1 = petal, tinted per instance
	match kind:
		0:
			m.add(NodeVisuals._cyl(0.012, 0.016, 0.3, 4), Transform3D(Basis(), Vector3(0, 0.15, 0)), stem)
			for i in 5:
				var a := TAU * float(i) / 5.0
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
				m.add(Kit.blob_mesh(0.06, 7100 + i, 0.1, 0.3, 1), Transform3D(b.scaled(Vector3(0.75, 1.0, 1.3)), Vector3(0, 0.3, 0) + b * Vector3(0, 0, -0.065)), tint)
			m.add(Kit.blob_mesh(0.035, 7110, 0.1, 0.8, 1), Transform3D(Basis(), Vector3(0, 0.315, 0)), Color(0.98, 0.78, 0.25, 0.0))
			m.add(Kit.blob_mesh(0.05, 7111, 0.2, 0.3, 1), Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3(0.6, 1, 1.4)), Vector3(0.05, 0.1, 0)), stem)
		1:
			m.add(NodeVisuals._cyl(0.012, 0.016, 0.34, 4), Transform3D(Basis(), Vector3(0, 0.17, 0)), stem)
			for i in 4:
				var a := TAU * float(i) / 4.0
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, deg_to_rad(18.0))
				m.add(Kit.blob_mesh(0.05, 7120 + i, 0.1, 1.6, 1), Transform3D(b, Vector3(0, 0.39, 0) + b * Vector3(0, 0, -0.03)), tint)
			m.add(Kit.blob_mesh(0.06, 7130, 0.2, 0.3, 1), Transform3D(Basis(Vector3.UP, 1.9).scaled(Vector3(0.6, 1, 1.5)), Vector3(-0.04, 0.12, 0)), stem)
		_:
			m.add(NodeVisuals._cyl(0.01, 0.014, 0.26, 4), Transform3D(Basis(), Vector3(0, 0.13, 0)), stem)
			for i in 4:
				var y := 0.14 + float(i) * 0.04
				var a := float(i) * 2.2
				m.add(Kit.blob_mesh(0.03, 7140 + i, 0.1, 0.9, 1), Transform3D(Basis(), Vector3(cos(a) * 0.035, y, sin(a) * 0.035)), tint)
	var mesh := m.commit()
	_meshes[kind] = mesh
	return mesh


static func make_material(bloom: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FLOWER_SHADER
	if bloom:
		mat.set_shader_parameter("bloom_radius", 0.0)
	return mat


## Builds one MultiMeshInstance3D per flower kind present in `placements`.
static func build_fields(parent: Node3D, placements: Array, material: ShaderMaterial, node_name: String, vis_range: float = 140.0) -> Array:
	var by_kind: Dictionary = {}
	for p in placements:
		var kind := int(p[5])
		if not by_kind.has(kind):
			by_kind[kind] = []
		by_kind[kind].append(p)
	var out: Array = []
	for kind in by_kind:
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = flower_mesh(int(kind))
		mm.instance_count = list.size()
		for i in list.size():
			var p: Array = list[i]
			var s := float(p[2])
			var xf := Transform3D(Basis(Vector3.UP, float(p[1])).scaled(Vector3(s, s, s)), p[0])
			mm.set_instance_transform(i, xf)
			var c: Color = (p[3] as Color).srgb_to_linear()
			mm.set_instance_custom_data(i, Color(c.r, c.g, c.b, float(p[4])))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d" % [node_name, int(kind)]
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_end_margin = 15.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
		out.append(mmi)
	return out
