extends RefCounted
## Shared, cached meshes and materials for the Weaver Matron's hazards (boss_hazards/*). Every hazard
## instance reuses these; per-instance fades use GeometryInstance3D.transparency, never a material copy.
## Two looks: the silk look (arachnophobia OFF) and the pale veil/root look (arachnophobia ON).

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")

const SILK := Color(0.93, 0.91, 0.98)
const SILK_SHEET := Color(0.9, 0.88, 0.97, 0.42)
const VEIL := Color(0.8, 0.9, 0.78)
const VEIL_SHEET := Color(0.78, 0.9, 0.8, 0.38)
const ROOT := Color("cdbfa3")
const ROOT_DARK := Color("8a7560")
const POST_STONE := Color("a39a8e")      # trip-line posts: a PALE stone peg (CR-03: dark blobs read as shadow critters)
const POST_ROOT := Color("b9a384")       # ... and a pale root stake with arachnophobia on
const SAC := Color("ddd6e6")
const SAC_VEIN := Color("9d8fb4")
const POD := Color("d9f2c4")
const POD_SEAM := Color("9fbf86")
const WARN := Color(0.95, 0.38, 0.32, 0.5)
const WARN_ALT := Color(0.95, 0.62, 0.3, 0.5)
const BOLD := Color("fff1c9")       # Settings "high_visibility_cues": the bold cream outline (both looks)

static var _cache: Dictionary = {}


## Flat circular sector on the XZ plane: apex at the origin, opening toward -Z, from r0 to r1.
static func sector_mesh(half_deg: float, r0: float, r1: float, segs: int = 14) -> ArrayMesh:
	var key := "sector|%.2f|%.2f|%.2f|%d" % [half_deg, r0, r1, segs]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := deg_to_rad(half_deg)
	for i in segs:
		var a0 := -h + 2.0 * h * float(i) / float(segs)
		var a1 := -h + 2.0 * h * float(i + 1) / float(segs)
		var i0 := Vector3(sin(a0) * r0, 0.0, -cos(a0) * r0)
		var o0 := Vector3(sin(a0) * r1, 0.0, -cos(a0) * r1)
		var i1 := Vector3(sin(a1) * r0, 0.0, -cos(a1) * r0)
		var o1 := Vector3(sin(a1) * r1, 0.0, -cos(a1) * r1)
		for v in [i0, o0, o1, i0, o1, i1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var m := st.commit()
	_cache[key] = m
	return m


## Unit cylinder (radius 1, height 1, along +Y) shared by every line / thread / strand.
static func unit_cylinder() -> CylinderMesh:
	if _cache.has("ucyl"):
		return _cache["ucyl"]
	var m := CylinderMesh.new()
	m.top_radius = 1.0
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 6
	m.rings = 1
	_cache["ucyl"] = m
	return m


static func sheet_mat(alt: bool) -> Material:
	return Mat.transparent(VEIL_SHEET if alt else SILK_SHEET, true)


static func warn_mat(alt: bool) -> Material:
	return Mat.transparent(WARN_ALT if alt else WARN, true)


static func strand_mat(alt: bool) -> Material:
	return Mat.glow(ROOT if alt else SILK, 0.55 if alt else 0.75)


## Settings "high_visibility_cues": every hazard adds bold outlines in this shared material (the cue then
## reads by shape and brightness, never by colour alone).
static func bold_mat() -> Material:
	return Mat.glow(BOLD, 1.3)


static func high_vis() -> bool:
	return bool(Settings.get_value("high_visibility_cues"))


static func post_mat(alt: bool) -> Material:
	var key := "post|%s" % alt
	if not _cache.has(key):
		# a faint self-light: the Matron's arenas are dark, and an unlit pale peg still reads as a black blob there
		var c := POST_ROOT if alt else POST_STONE
		_cache[key] = Mat.outlined(Mat.toon(c, {"rim": 0.45, "noise": 0.2, "emission": c, "emission_energy": 0.32}), 0.012)
	return _cache[key]


## A trip-line post that reads as an OBJECT (CR-03): a pale stone peg on a low plinth with a rounded cap (silk
## look) or a gnarled pale root stake with little root feet (arachnophobia), the glowing strand wound tight round
## its neck - no dark round blob with two pale "eye" crescents. Built under `holder` (origin = floor point).
## Shared meshes / materials; ~5 meshes per post, no shadows.
static func build_post(holder: Node3D, alt: bool) -> void:
	var m := post_mat(alt)
	var parts: Array = []
	if alt:
		parts.append(Kit.add(holder, Kit.cylinder(0.08, 0.13, 0.62, m, 8), Vector3(0, 0.31, 0), Vector3(0, 0, 4)))
		parts.append(Kit.add(holder, Kit.sphere(0.1, m, 8, 10), Vector3(0.01, 0.63, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)))
		for i in 3:
			var a := TAU * float(i) / 3.0 + 0.4
			parts.append(Kit.add(holder, Kit.cone(0.05, 0.28, m, 6), Vector3(cos(a) * 0.12, 0.06, sin(a) * 0.12), Vector3(cos(a) * -70.0, 0, sin(a) * 70.0)))
	else:
		parts.append(Kit.add(holder, Kit.cylinder(0.2, 0.25, 0.12, m, 12), Vector3(0, 0.06, 0)))
		parts.append(Kit.add(holder, Kit.cylinder(0.085, 0.11, 0.5, m, 10), Vector3(0, 0.36, 0)))
		parts.append(Kit.add(holder, Kit.sphere(0.12, m, 10, 12), Vector3(0, 0.62, 0), Vector3.ZERO, Vector3(1.0, 0.65, 1.0)))
	parts.append(Kit.add(holder, Kit.torus(0.075, 0.12, strand_mat(alt)), Vector3(0, 0.5, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)))
	for mi in parts:
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func sac_mat(alt: bool) -> Material:
	var key := "sac|%s" % alt
	if not _cache.has(key):
		var c := POD if alt else SAC
		_cache[key] = Mat.outlined(Mat.toon(c, {"rim": 0.55, "noise": 0.12, "emission": c, "emission_energy": 0.35}), 0.012)
	return _cache[key]


static func vein_mat(alt: bool) -> Material:
	return Mat.toon(POD_SEAM if alt else SAC_VEIN, {"rim": 0.3})


static func mote_mesh() -> SphereMesh:
	if _cache.has("mote"):
		return _cache["mote"]
	var m := SphereMesh.new()
	m.radius = 0.04
	m.height = 0.08
	m.radial_segments = 6
	m.rings = 3
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.vertex_color_use_as_albedo = true
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material = pm
	_cache["mote"] = m
	return m


## A thin line (MeshInstance3D) between two points using the shared unit cylinder.
static func line(parent: Node3D, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = unit_cylinder()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Places a line mesh made by line() from `a` to `b` (global) with `radius`. No allocations.
static func place_line(mi: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		mi.visible = false
		return
	mi.visible = true
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x * radius, y * l, z * radius), (a + b) * 0.5)


## Soft drifting motes (veil seeds / silk dust) for a patch; `extent` = box half size.
static func motes(parent: Node3D, color: Color, extent: Vector3, amount: int = 12) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mote_mesh()
	p.amount = amount
	p.lifetime = 2.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent
	p.direction = Vector3.UP
	p.spread = 25.0
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = Vector3(0, 0.15, 0)
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.emitting = true
	return p


static func pulse_alpha(t: float, lo: float, hi: float, speed: float) -> float:
	if bool(Settings.get_value("reduce_flashing")):
		return (lo + hi) * 0.5
	return lo + (hi - lo) * (0.5 + 0.5 * sin(t * speed))
