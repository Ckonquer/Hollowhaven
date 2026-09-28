extends RefCounted
## Shared procedural art of the Borrowed Choir (static; materials / meshes come from Mat / Kit caches, so every
## bell, mask and ribbon shares them). Original shape language (MP §13.3): cracked hanging bells, carved wooden
## masks, harvest ribbons and DIM lights (emissive only - the Choir can never make true light).
##   const Art := preload("res://src/enemies/choir/choir_art.gd")
##   Art.bell(parent, pos, size)  Art.mask(parent, pos, yaw_deg, size)  Art.ribbon(parent, pos, len, colour)
##   Art.bold_ring(parent, r)     high_visibility_cues marker (cream + dark outline: a shape, never colour alone)
##   Art.sector_mesh(arc_deg)     unit flat wedge (+z = its middle), cached per arc

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const WOOD := Color("6e4a32")
const WOOD_DARK := Color("4a3022")
const BRONZE := Color("9a6a3c")
const MASK := Color("d6bf98")
const MASK_DARK := Color("a88a64")
const HOLLOW := Color(0.07, 0.05, 0.07)
const DIM_GLOW := Color("f2c98a")                  # a warm borrowed glow (lights nothing)
const RIBBONS := [Color("e4665c"), Color("f2c14e"), Color("b48ad8"), Color("6fae4f"), Color("f28bb0"), Color("e9a15b")]
const HV_COLOR := Color("fff1c8")
const HV_OUTLINE := Color(0.08, 0.05, 0.1)
const LIT_FLOOR := Color(1.0, 0.86, 0.58, 0.34)     # the kept flame's lit sector (a warm, soft floor wash)
const SAFE_LANE := Color(0.98, 0.95, 0.82, 0.3)     # a ring's opening (a pale lit lane, not a danger mark)

static var _sectors: Dictionary = {}


static func wood_mat() -> Material:
	return Mat.outlined(Mat.toon(WOOD, {"rim": 0.3, "noise": 0.12}), 0.016)


static func bronze_mat() -> Material:
	return Mat.outlined(Mat.toon(BRONZE, {"rim": 0.5, "specular": 0.35}), 0.018)


static func mask_mat() -> Material:
	return Mat.outlined(Mat.toon(MASK, {"rim": 0.3, "noise": 0.08}), 0.016)


static func dark_mat() -> Material:
	return Mat.toon(HOLLOW)


static func dim_glow(energy: float = 0.9) -> Material:
	return Mat.glow(DIM_GLOW, energy)


## A cracked hanging bell (mouth down) with its clapper; returns the bell node (swing it about its top).
static func bell(parent: Node3D, pos: Vector3, size: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Bell"
	parent.add_child(n)
	n.position = pos
	Kit.add(n, Kit.cylinder(0.012 * size, 0.012 * size, 0.35 * size, dark_mat(), 5), Vector3(0, 0.17 * size, 0))
	Kit.add(n, Kit.cylinder(0.11 * size, 0.27 * size, 0.4 * size, bronze_mat(), 14), Vector3(0, -0.2 * size, 0))
	Kit.add(n, Kit.torus(0.24 * size, 0.29 * size, bronze_mat()), Vector3(0, -0.39 * size, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	Kit.add(n, Kit.sphere(0.06 * size, dark_mat(), 6, 8), Vector3(0, -0.42 * size, 0))
	# the crack: a dark jagged seam down one side
	Kit.add(n, Kit.box(Vector3(0.025, 0.2, 0.02) * size, dark_mat()), Vector3(0.14 * size, -0.14 * size, 0.2 * size), Vector3(0, 0, 14))
	Kit.add(n, Kit.box(Vector3(0.025, 0.16, 0.02) * size, dark_mat()), Vector3(0.18 * size, -0.3 * size, 0.2 * size), Vector3(0, 0, -18))
	return n


## A carved wooden mask facing local +z (rotate the returned node by yaw).
static func mask(parent: Node3D, pos: Vector3, yaw_deg: float, size: float = 1.0) -> Node3D:
	var n := Node3D.new()
	n.name = "Mask"
	parent.add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw_deg, 0)
	Kit.add(n, Kit.sphere(0.26 * size, mask_mat(), 10, 12), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.25, 0.42))
	for sx in [-1.0, 1.0]:
		Kit.add(n, Kit.sphere(0.055 * size, dark_mat(), 6, 8), Vector3(sx * 0.1 * size, 0.07 * size, 0.1 * size), Vector3.ZERO, Vector3(1.0, 1.3, 0.6))
	# a borrowed, painted-on smile (a little too wide)
	Kit.add(n, Kit.box(Vector3(0.2, 0.025, 0.02) * size, Mat.toon(MASK_DARK)), Vector3(0, -0.12 * size, 0.105 * size), Vector3(0, 0, 0))
	for sx in [-1.0, 1.0]:
		Kit.add(n, Kit.box(Vector3(0.06, 0.025, 0.02) * size, Mat.toon(MASK_DARK)), Vector3(sx * 0.12 * size, -0.09 * size, 0.1 * size), Vector3(0, 0, sx * 30.0))
	return n


## A harvest ribbon hanging down from `pos` (its pivot is the top: sway it by rotating the returned node).
static func ribbon(parent: Node3D, pos: Vector3, length: float, colour: Color, width: float = 0.07) -> Node3D:
	var n := Node3D.new()
	n.name = "Ribbon"
	parent.add_child(n)
	n.position = pos
	var r := Kit.box(Vector3(width, length, 0.015), Mat.toon(colour, {"rim": 0.2}))
	Kit.add(n, r, Vector3(0, -length * 0.5, 0))
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


## A small dim light mote (emissive only - never a Light3D, never a light source).
static func mote(parent: Node3D, pos: Vector3, radius: float = 0.07, energy: float = 0.9) -> MeshInstance3D:
	var m := Kit.sphere(radius, dim_glow(energy), 6, 8)
	Kit.add(parent, m, pos)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Bold, outlined floor ring for the high_visibility_cues option (shape + outline, never colour alone).
static func bold_ring(parent: Node3D, radius: float, y: float = 0.05) -> MeshInstance3D:
	var mat := Mat.outlined(Mat.toon(HV_COLOR, {"emission": HV_COLOR, "emission_energy": 0.8, "rim": 0.2}), 0.05, HV_OUTLINE)
	var ring := Kit.torus(radius - 0.09, radius + 0.09, mat)
	Kit.add(parent, ring, Vector3(0.0, y, 0.0), Vector3.ZERO, Vector3(1.0, 0.35, 1.0))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.name = "HvRing"
	return ring


## A bold outlined bar on the floor from local a to b (high visibility sector edges / lane edges).
static func bold_bar(parent: Node3D, a: Vector3, b: Vector3, y: float = 0.05) -> MeshInstance3D:
	var mat := Mat.outlined(Mat.toon(HV_COLOR, {"emission": HV_COLOR, "emission_energy": 0.8, "rim": 0.2}), 0.05, HV_OUTLINE)
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var bar := Kit.box(Vector3(0.16, 0.05, maxf(d.length(), 0.05)), mat)
	parent.add_child(bar)
	bar.position = (a + b) * 0.5 + Vector3(0, y, 0)
	if d.length_squared() > 0.0001:
		bar.rotation.y = atan2(d.x, d.z)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.name = "HvBar"
	return bar


## Flat unit wedge of `arc_deg` around +z (radius 1, from `inner` to 1), cached per arc/inner.
static func sector_mesh(arc_deg: float, inner: float = 0.0) -> ArrayMesh:
	var key := "%.1f|%.2f" % [arc_deg, inner]
	if _sectors.has(key):
		return _sectors[key]
	var segs := maxi(int(arc_deg / 6.0), 4)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var a0 := -deg_to_rad(arc_deg) * 0.5
	var step := deg_to_rad(arc_deg) / float(segs)
	for i in segs:
		var t0 := a0 + step * float(i)
		var t1 := t0 + step
		var o0 := Vector3(sin(t0), 0.0, cos(t0))
		var o1 := Vector3(sin(t1), 0.0, cos(t1))
		var i0 := o0 * inner
		var i1 := o1 * inner
		st.add_vertex(i0)
		st.add_vertex(o1)
		st.add_vertex(o0)
		if inner > 0.0:
			st.add_vertex(i0)
			st.add_vertex(i1)
			st.add_vertex(o1)
	var mesh := st.commit()
	_sectors[key] = mesh
	return mesh


static func caption(text: String) -> void:
	if text != "":
		Events.caption.emit(text)


static func sfx(sound: String, pos: Vector3, db: float = 0.0, max_distance: float = 40.0) -> void:
	if Audio.has_method("has_sound") and not Audio.has_sound(sound):
		return
	Audio.play_3d(sound, pos, db, 0.06, max_distance)


static func high_visibility() -> bool:
	return bool(Settings.get_value("high_visibility_cues"))


static func timing_assist() -> bool:
	return bool(Settings.get_value("timing_assist"))
