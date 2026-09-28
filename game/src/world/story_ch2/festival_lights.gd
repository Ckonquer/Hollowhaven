extends RefCounted
## Shared Lanternwake festival-light visuals (module C9): floating paper lanterns as ONE MultiMesh pair
## (glowing bodies with per-instance colour + dark caps) so a whole road of lanterns is two draw calls.
## Meshes and materials are built once and cached (static), like Mat / Kit. No collision: the lanterns float
## above head height and never block a path, a spawn or a building. Nothing here casts shadows.
##   FestivalLights.lanterns(points, "KeepsakeLanterns", 70.0) -> Node3D   (points: [{"pos": Vector3, "color": Color, "scale": float}])
##   FestivalLights.lanterns_chunked(points, "RouteLanterns", 120.0, 48.0) -> Node3D   (region-wide sets: per-cell pairs)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")

## Warm festival colours: amber, rose, lavender, cream (Halloween as a warm autumn place).
const COLORS := [Color("ffb45a"), Color("ff9fb2"), Color("c9a8ff"), Color("ffe2a0")]
const AMBER := Color("ffb45a")

static var _body_mesh: Mesh = null
static var _cap_mesh: Mesh = null
static var _body_mat: StandardMaterial3D = null


## Rounded paper-lantern body (a squashed sphere, slightly taller than wide).
static func body_mesh() -> Mesh:
	if _body_mesh == null:
		var m := SphereMesh.new()
		m.radius = 0.24
		m.height = 0.58
		m.radial_segments = 12
		m.rings = 6
		_body_mesh = m
	return _body_mesh


## The little dark cap + tassel knot on top (one cylinder).
static func cap_mesh() -> Mesh:
	if _cap_mesh == null:
		var m := CylinderMesh.new()
		m.top_radius = 0.07
		m.bottom_radius = 0.13
		m.height = 0.1
		m.radial_segments = 8
		m.rings = 1
		_cap_mesh = m
	return _cap_mesh


## Self-lit paper: the instance colour is the albedo (HDR-ish so it blooms softly), unshaded.
static func body_material() -> StandardMaterial3D:
	if _body_mat == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = Color(1.35, 1.25, 1.15)
		_body_mat = m
	return _body_mat


static func color_for(i: int) -> Color:
	return COLORS[posmod(i, COLORS.size())]


## Builds the lantern group. Each point: {"pos": Vector3 (world or parent-local), "color": Color, "scale": float,
## "yaw": float}. Returns a Node3D with Bodies + Caps MultiMeshInstance3D children (empty points -> empty node).
static func lanterns(points: Array, node_name: String, vis_range: float = 0.0) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var n := points.size()
	if n == 0:
		return root
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.use_colors = true
	bodies.mesh = body_mesh()
	bodies.instance_count = n
	var caps := MultiMesh.new()
	caps.transform_format = MultiMesh.TRANSFORM_3D
	caps.mesh = cap_mesh()
	caps.instance_count = n
	for i in n:
		var p: Dictionary = points[i]
		var pos: Vector3 = p.get("pos", Vector3.ZERO)
		var s: float = float(p.get("scale", 1.0))
		var b := Basis(Vector3.UP, float(p.get("yaw", 0.0))).scaled(Vector3(s, s, s))
		bodies.set_instance_transform(i, Transform3D(b, pos))
		bodies.set_instance_color(i, p.get("color", AMBER))
		caps.set_instance_transform(i, Transform3D(b, pos + Vector3(0.0, 0.31 * s, 0.0)))
	root.add_child(_mmi(bodies, body_material(), "Bodies", vis_range))
	root.add_child(_mmi(caps, Mat.toon(Palette.BARK_DARK, {"rim": 0.2}), "Caps", vis_range))
	return root


## Like lanterns(), but split into square cells of `cell` metres (one Bodies + Caps pair per cell, children of
## the returned node named "Cell_<x>_<z>" in a stable order). A visibility range is measured to each
## MultiMesh's own bounds, so one region-wide MultiMesh would vanish all at once (the lanterns right next to
## Krystal included) whenever she stands far from the middle of the region; per-cell MultiMeshes fade by area.
static func lanterns_chunked(points: Array, node_name: String, vis_range: float, cell: float) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	var size := maxf(cell, 1.0)
	var cells := {}
	var keys: Array = []
	for p in points:
		var pos: Vector3 = (p as Dictionary).get("pos", Vector3.ZERO)
		var key := Vector2i(floori(pos.x / size), floori(pos.z / size))
		if not cells.has(key):
			cells[key] = []
			keys.append(key)
		(cells[key] as Array).append(p)
	for key: Vector2i in keys:
		root.add_child(lanterns(cells[key], "Cell_%d_%d" % [key.x, key.y], vis_range))
	return root


static func _mmi(mm: MultiMesh, mat: Material, node_name: String, vis_range: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_range > 0.0:
		mmi.visibility_range_end = vis_range
		mmi.visibility_range_end_margin = vis_range * 0.1
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	return mmi


## A soft warm omni light (never shadowed: the Haven's only shadowed omni is the campfire).
static func warm_light(energy: float, light_range: float, color: Color = Color("ffc98a")) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.shadow_enabled = false
	return l
