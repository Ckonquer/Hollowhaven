extends RefCounted
## Moonveil Manor architectural builder (walls, floors, ceilings, stairs, windows, curtains, chandeliers,
## candles). Used by the interior area (src/world/areas_ch2/moonveil_manor_world.gd) and the grounds
## district (src/world/reach/districts/manor_grounds.gd). Own code: it does not use the Below builder.
## * Collision: one StaticBody3D per (room, surface) on layer 1 with meta "surface" (footsteps).
## * Visuals: every repeated shape is collected per room and flushed by finish() into ONE
##   MultiMeshInstance3D per (room, mesh, material): instance colours tint a shared white toon material
##   (Mat cache), glows share Mat.glow materials, the mirror world uses one unshaded tinted material.
##   Call finish() exactly once, after everything is built.
## * Rooms come from data/manor_layout.gd (walls outside the room box, openings, thresholds, parapets).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://data/manor_layout.gd")

const WALL_T := Layout.WALL_T
const WAINSCOT_H := 0.85
const FLAME := Color("ffc56a")

var root: Node3D
var room: String = ""
var room_nodes: Dictionary = {}
var visibility_end: float = 75.0
var instances: int = 0                 # batched instances (tests / budget)
var bodies_made: int = 0

var _bodies: Dictionary = {}
var _batches: Dictionary = {}
var _lamps: int = 0
var _room_colors: Dictionary = {}       # room id -> the colours its room_shell() used (height-step fills)

static var _meshes: Dictionary = {}
static var _flat_mat: StandardMaterial3D = null


func _init(p_root: Node3D) -> void:
	root = p_root


# --- Shared unit meshes -------------------------------------------------------------------------------

static func unit_box() -> Mesh:
	if not _meshes.has("box"):
		var m := BoxMesh.new()
		m.size = Vector3.ONE
		_meshes["box"] = m
	return _meshes["box"]


static func unit_cyl(segments: int = 14) -> Mesh:
	var key := "cyl%d" % segments
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.5
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


## Truncated cone: top radius = ratio * 0.5 (bottom 0.5), height 1.
static func unit_taper(ratio: float, segments: int = 14) -> Mesh:
	var key := "tap%.2f|%d" % [ratio, segments]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.5 * ratio
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func unit_sphere(segments: int = 14) -> Mesh:
	var key := "sph%d" % segments
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.rings = maxi(segments / 2, 4)
		m.radial_segments = segments
		_meshes[key] = m
	return _meshes[key]


## Thin ring in the XZ plane, outer radius 1.
static func unit_ring() -> Mesh:
	if not _meshes.has("ring"):
		var m := TorusMesh.new()
		m.inner_radius = 0.86
		m.outer_radius = 1.0
		m.rings = 28
		m.ring_segments = 8
		_meshes["ring"] = m
	return _meshes["ring"]


## Triangular prism (roof wedge), unit size, apex up.
static func unit_prism() -> Mesh:
	if not _meshes.has("prism"):
		var m := PrismMesh.new()
		m.size = Vector3.ONE
		_meshes["prism"] = m
	return _meshes["prism"]


static var _default_tint: Material = null


static func tint_mat(opts: Dictionary = {}) -> Material:
	if opts.is_empty() or (opts.size() == 1 and opts.has("shadows")) or (opts.size() == 2 and opts.has("shadows") and opts.has("segments")):
		if _default_tint == null:
			_default_tint = Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.08, "rim": 0.2})
		return _default_tint
	var o := {"vertex_color": true, "noise": 0.08, "rim": 0.2}
	for k in ["noise", "rim", "emission", "emission_energy", "noise_scale", "specular", "wind", "wind_height"]:
		if opts.has(k):
			o[k] = opts[k]
	var m: Material = Mat.toon(Color.WHITE, o)
	if bool(opts.get("outline", false)):
		m = Mat.outlined(m, float(opts.get("outline_w", 0.02)))
	return m


## Unshaded, instance-tinted material (the Looking-Glass Hall's mirror world: only glows "light" it).
static func flat_mat() -> StandardMaterial3D:
	if _flat_mat == null:
		_flat_mat = StandardMaterial3D.new()
		_flat_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flat_mat.vertex_color_use_as_albedo = true
	return _flat_mat


# --- Rooms ----------------------------------------------------------------------------------------------

func begin(id: String) -> Node3D:
	room = id
	if not room_nodes.has(id):
		var n := Node3D.new()
		n.name = "Room_" + id
		root.add_child(n)
		room_nodes[id] = n
	return room_nodes[id]


func node() -> Node3D:
	if not room_nodes.has(room):
		begin(room if room != "" else "misc")
	return room_nodes[room]


# --- Collision ------------------------------------------------------------------------------------------

func body(surface: String = "stone") -> StaticBody3D:
	var key := room + "|" + surface
	if _bodies.has(key):
		return _bodies[key]
	var b := StaticBody3D.new()
	b.name = "Col_%s_%s" % [room, surface]
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("surface", surface)
	node().add_child(b)
	_bodies[key] = b
	bodies_made += 1
	return b


func col_box(center: Vector3, size: Vector3, surface: String = "stone", basis: Basis = Basis.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body(surface).add_child(cs)
	cs.transform = Transform3D(basis, center)
	return cs


func col_cyl(center: Vector3, radius: float, height: float, surface: String = "stone") -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	body(surface).add_child(cs)
	cs.position = center
	return cs


# --- Batched visuals -----------------------------------------------------------------------------------

func batch(mesh: Mesh, mat: Material, xf: Transform3D, color: Color = Color.WHITE, shadows: bool = true) -> void:
	var key := "%s|%d|%d|%s" % [room, mesh.get_instance_id(), mat.get_instance_id(), shadows]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "mat": mat, "room": room, "xf": [], "col": [], "shadows": shadows}
	_batches[key]["xf"].append(xf)
	_batches[key]["col"].append(color)
	instances += 1


func vbox(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_box(), tint_mat(opts), Transform3D(basis.scaled_local(size), center), color, bool(opts.get("shadows", true)))


func vcyl(center: Vector3, radius: float, height: float, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_cyl(int(opts.get("segments", 14))), tint_mat(opts), Transform3D(basis.scaled_local(Vector3(radius * 2.0, height, radius * 2.0)), center), color, bool(opts.get("shadows", true)))


func vtaper(center: Vector3, bottom_r: float, top_r: float, height: float, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	var ratio := clampf(top_r / maxf(bottom_r, 0.001), 0.0, 4.0)
	ratio = snappedf(ratio, 0.05)
	batch(unit_taper(ratio), tint_mat(opts), Transform3D(basis.scaled_local(Vector3(bottom_r * 2.0, height, bottom_r * 2.0)), center), color, bool(opts.get("shadows", true)))


func vcone(center: Vector3, radius: float, height: float, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_taper(0.0, int(opts.get("segments", 12))), tint_mat(opts), Transform3D(basis.scaled_local(Vector3(radius * 2.0, height, radius * 2.0)), center), color, bool(opts.get("shadows", true)))


func vsphere(center: Vector3, scl: Vector3, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_sphere(int(opts.get("segments", 14))), tint_mat(opts), Transform3D(basis.scaled_local(scl), center), color, bool(opts.get("shadows", true)))


func vring(center: Vector3, radius: float, thickness_y: float, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_ring(), tint_mat(opts), Transform3D(basis.scaled_local(Vector3(radius, thickness_y, radius)), center), color, bool(opts.get("shadows", false)))


func vprism(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_prism(), tint_mat(opts), Transform3D(basis.scaled_local(size), center), color, bool(opts.get("shadows", true)))


## Self-lit batched piece (flames, window glass, crystals). Never casts shadows.
func vglow(mesh: Mesh, xf: Transform3D, color: Color, energy: float = 2.0) -> void:
	batch(mesh, Mat.glow(color, energy), xf, Color.WHITE, false)


func glow_sphere(center: Vector3, scl: Vector3, color: Color, energy: float = 2.0) -> void:
	vglow(unit_sphere(10), Transform3D(Basis.IDENTITY.scaled_local(scl), center), color, energy)


func glow_box(center: Vector3, size: Vector3, color: Color, energy: float = 1.6, basis: Basis = Basis.IDENTITY) -> void:
	vglow(unit_box(), Transform3D(basis.scaled_local(size), center), color, energy)


func glow_disc(center: Vector3, radius: float, color: Color, energy: float, basis: Basis = Basis.IDENTITY, thickness: float = 0.02) -> void:
	vglow(unit_cyl(20), Transform3D(basis.scaled_local(Vector3(radius * 2.0, thickness, radius * 2.0)), center), color, energy)


## Unshaded tinted piece (mirror world).
func vflat(mesh: Mesh, xf: Transform3D, color: Color) -> void:
	batch(mesh, flat_mat(), xf, color, false)


# --- Composite pieces --------------------------------------------------------------------------------

func solid(center: Vector3, size: Vector3, color: Color, surface: String = "stone", basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	vbox(center, size, color, basis, opts)
	col_box(center, size, surface, basis)


## Floor slab whose top is at y.
func floor_rect(x0: float, x1: float, z0: float, z1: float, y: float, color: Color, surface: String = "stone", visual: bool = true, thick: float = 0.5) -> void:
	var c := Vector3((x0 + x1) * 0.5, y - thick * 0.5, (z0 + z1) * 0.5)
	var s := Vector3(x1 - x0, thick, z1 - z0)
	col_box(c, s, surface)
	if visual:
		vbox(c, s, color)


func ceiling_rect(x0: float, x1: float, z0: float, z1: float, y: float, color: Color) -> void:
	var c := Vector3((x0 + x1) * 0.5, y + 0.25, (z0 + z1) * 0.5)
	var s := Vector3(x1 - x0 + WALL_T * 2.0, 0.5, z1 - z0 + WALL_T * 2.0)
	vbox(c, s, color)
	col_box(c, s)


## Floor, ceiling (unless open_sky), walls/parapets with openings and thresholds for a layout room.
## colors: {"floor", "wall", "ceil", "trim", "wainscot"}.
func room_shell(id: String, colors: Dictionary, opts: Dictionary = {}) -> void:
	var r: Dictionary = Layout.ROOMS[id]
	begin(id)
	_room_colors[id] = colors
	var y: float = float(r["y"])
	var surf := String(r.get("surface", "stone"))
	var floor_c: Color = colors.get("floor", Palette.WOOD)
	if not r.has("ramp") and not bool(opts.get("no_floor", false)):
		floor_rect(float(r["x0"]), float(r["x1"]), float(r["z0"]), float(r["z1"]), y, floor_c, surf)
	if not bool(r.get("open_sky", false)) and not bool(opts.get("no_ceiling", false)):
		ceiling_rect(float(r["x0"]), float(r["x1"]), float(r["z0"]), float(r["z1"]), y + float(r["h"]), colors.get("ceil", Palette.WOOD_DARK))
	var walls: Dictionary = r.get("walls", {})
	var parapets: Array = r.get("parapet", [])
	for side in ["n", "s", "w", "e"]:
		if not walls.has(side):
			continue
		wall_side(id, side, walls[side], colors, parapets.has(side))


## One side of a room: solid spans between openings, lintels above, sills below, a threshold slab under
## every floor-level opening, a wainscot band and a crown trim on the inner face.
func wall_side(id: String, side: String, openings: Array, colors: Dictionary, parapet: bool = false) -> void:
	var r: Dictionary = Layout.ROOMS[id]
	var y: float = float(r["y"])
	var h: float = Layout.PARAPET_COLLIDE if parapet else float(r["h"])
	var vis_h: float = Layout.PARAPET_H if parapet else h
	var walls: Dictionary = r.get("walls", {})
	var along_x := side == "n" or side == "s"
	var a0: float = float(r["x0"]) if along_x else float(r["z0"])
	var a1: float = float(r["x1"]) if along_x else float(r["z1"])
	if along_x:
		if walls.has("w"):
			a0 -= WALL_T
		if walls.has("e"):
			a1 += WALL_T
	var wall_c: Color = colors.get("wall", Palette.CLOTH_CREAM)
	var sorted := openings.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var cur := a0
	var spans: Array = []
	for o in sorted:
		var oa: float = float(o[0])
		var ob: float = float(o[1])
		var top: float = float(o[2])
		var bottom: float = float(o[3]) if (o as Array).size() > 3 else 0.0
		if oa > cur:
			spans.append([cur, oa])
		# lintel above, sill below
		if top < h - 0.01:
			_wall_piece(r, side, oa, ob, y + top, y + h, wall_c, y + minf(vis_h, h), parapet)
		if bottom > 0.01:
			_wall_piece(r, side, oa, ob, y, y + bottom, colors.get("wainscot", wall_c), y + bottom, false)
		else:
			_threshold(r, side, oa, ob, y, colors.get("floor", Palette.WOOD), String(r.get("surface", "stone")))
		cur = ob
	if cur < a1:
		spans.append([cur, a1])
	for sp in spans:
		_wall_piece(r, side, float(sp[0]), float(sp[1]), y, y + h, wall_c, y + vis_h, parapet)
		if not parapet:
			_inner_band(r, side, float(sp[0]), float(sp[1]), y, WAINSCOT_H, colors.get("wainscot", wall_c.darkened(0.25)), 0.07)
			_inner_band(r, side, float(sp[0]), float(sp[1]), y + h - 0.28, 0.28, colors.get("trim", wall_c.lightened(0.2)), 0.1)
		else:
			_parapet_cap(r, side, float(sp[0]), float(sp[1]), y + vis_h, colors.get("trim", wall_c.lightened(0.15)))


## Solid piece of wall from ylo to yhi (collision), drawn up to `vis_top` (parapets: invisible above).
func _wall_piece(r: Dictionary, side: String, a: float, b: float, ylo: float, yhi: float, color: Color, vis_top: float, parapet: bool) -> void:
	if b - a < 0.01 or yhi - ylo < 0.01:
		return
	var box := _side_box(r, side, a, b, ylo, yhi)
	col_box(box[0], box[1])
	var vt := minf(vis_top, yhi) if parapet else yhi
	if vt - ylo > 0.01:
		var vb := _side_box(r, side, a, b, ylo, vt)
		vbox(vb[0], vb[1], color)


func _side_box(r: Dictionary, side: String, a: float, b: float, ylo: float, yhi: float) -> Array:
	var cy := (ylo + yhi) * 0.5
	var sy := yhi - ylo
	match side:
		"n":
			return [Vector3((a + b) * 0.5, cy, float(r["z0"]) - WALL_T * 0.5), Vector3(b - a, sy, WALL_T)]
		"s":
			return [Vector3((a + b) * 0.5, cy, float(r["z1"]) + WALL_T * 0.5), Vector3(b - a, sy, WALL_T)]
		"w":
			return [Vector3(float(r["x0"]) - WALL_T * 0.5, cy, (a + b) * 0.5), Vector3(WALL_T, sy, b - a)]
	return [Vector3(float(r["x1"]) + WALL_T * 0.5, cy, (a + b) * 0.5), Vector3(WALL_T, sy, b - a)]


## Walkable slab filling the wall gap under a floor-level opening.
func _threshold(r: Dictionary, side: String, a: float, b: float, y: float, color: Color, surface: String) -> void:
	var box := _side_box(r, side, a, b, y - 0.5, y)
	col_box(box[0], box[1], surface)
	vbox(box[0], box[1], color.darkened(0.1))


## A thin band on the inner face of a wall (wainscot / crown trim). depth = how far it stands out.
func _inner_band(r: Dictionary, side: String, a: float, b: float, ylo: float, height: float, color: Color, depth: float) -> void:
	if b - a < 0.05:
		return
	var cy := ylo + height * 0.5
	var c := Vector3.ZERO
	var s := Vector3.ZERO
	match side:
		"n":
			c = Vector3((a + b) * 0.5, cy, float(r["z0"]) + depth * 0.5)
			s = Vector3(b - a, height, depth)
		"s":
			c = Vector3((a + b) * 0.5, cy, float(r["z1"]) - depth * 0.5)
			s = Vector3(b - a, height, depth)
		"w":
			c = Vector3(float(r["x0"]) + depth * 0.5, cy, (a + b) * 0.5)
			s = Vector3(depth, height, b - a)
		"e":
			c = Vector3(float(r["x1"]) - depth * 0.5, cy, (a + b) * 0.5)
			s = Vector3(depth, height, b - a)
	vbox(c, s, color, Basis.IDENTITY, {"shadows": false})


## Where a taller room shares a wall with a lower neighbour that builds it (layout rule: only ONE of the two
## builds the shared wall, at its OWN height), the band between the neighbour's top and the taller room's
## ceiling would stay open to the void (VISUAL_BUGS IN-02: above the Cloakroom doorway in the Looking-Glass
## Hall). Pure data: [{room, side, a, b, ylo, yhi}] with a..b along the side (x for n/s, z for w/e, the taller
## room's wall thickness included at both ends) and ylo..yhi world heights. Open-sky rooms and parapets never
## need one.
static func height_steps() -> Array:
	var out: Array = []
	var opposite := {"n": "s", "s": "n", "w": "e", "e": "w"}
	for id in Layout.ROOM_ORDER:
		var r: Dictionary = Layout.ROOMS[id]
		if bool(r.get("open_sky", false)):
			continue
		var top: float = float(r["y"]) + float(r["h"])
		var walls: Dictionary = r.get("walls", {})
		for side in ["n", "s", "w", "e"]:
			if walls.has(side):
				continue
			for nid in Layout.ROOM_ORDER:
				if nid == id:
					continue
				var q: Dictionary = Layout.ROOMS[nid]
				var qwalls: Dictionary = q.get("walls", {})
				var opp: String = opposite[side]
				if not qwalls.has(opp) or (q.get("parapet", []) as Array).has(opp):
					continue
				var gap := 0.0
				match side:
					"n": gap = float(r["z0"]) - float(q["z1"])
					"s": gap = float(q["z0"]) - float(r["z1"])
					"w": gap = float(r["x0"]) - float(q["x1"])
					"e": gap = float(q["x0"]) - float(r["x1"])
				if absf(gap - WALL_T) > 0.01:
					continue
				var along_x: bool = side == "n" or side == "s"
				var a := maxf(float(r["x0"] if along_x else r["z0"]) - WALL_T, float(q["x0"] if along_x else q["z0"]) - WALL_T)
				var b := minf(float(r["x1"] if along_x else r["z1"]) + WALL_T, float(q["x1"] if along_x else q["z1"]) + WALL_T)
				var qtop: float = float(q["y"]) + float(q["h"])
				if b - a > 0.05 and qtop < top - 0.01:
					out.append({"room": String(id), "side": side, "a": a, "b": b, "ylo": qtop, "yhi": top})
	return out


## Builds every height_steps() band as a solid wall piece (collision like any wall) in the taller room's wall
## colour, standing 1 cm proud of the neighbour's ceiling slab edge (no z-fighting), with the room's crown trim
## and a thin moulding along the seam. Call after every room_shell(). Returns the number of bands built.
func close_height_steps() -> int:
	var steps := height_steps()
	var keep := room
	for s in steps:
		var id := String(s["room"])
		var r: Dictionary = Layout.ROOMS[id]
		var colors: Dictionary = _room_colors.get(id, {})
		var wall_c: Color = colors.get("wall", Palette.CLOTH_CREAM)
		var side := String(s["side"])
		var a := float(s["a"])
		var b := float(s["b"])
		var ylo := float(s["ylo"])
		var yhi := float(s["yhi"])
		begin(id)
		var box := _side_box(r, side, a, b, ylo, yhi)
		col_box(box[0], box[1])
		var inward := _inward(side)
		var vis_size: Vector3 = box[1] + Vector3(absf(inward.x), 0.0, absf(inward.z)) * 0.02
		vbox(box[0] + inward * 0.01, vis_size, wall_c)
		_inner_band(r, side, a + WALL_T, b - WALL_T, float(r["y"]) + float(r["h"]) - 0.28, 0.28, colors.get("trim", wall_c.lightened(0.2)), 0.1)
		_inner_band(r, side, a + WALL_T, b - WALL_T, ylo, 0.14, colors.get("trim", wall_c.lightened(0.2)), 0.06)
	if keep != "":
		begin(keep)
	return steps.size()


## Direction into the room from its `side` wall.
static func _inward(side: String) -> Vector3:
	match side:
		"n":
			return Vector3(0, 0, 1)
		"s":
			return Vector3(0, 0, -1)
		"w":
			return Vector3(1, 0, 0)
	return Vector3(-1, 0, 0)


func _parapet_cap(r: Dictionary, side: String, a: float, b: float, top: float, color: Color) -> void:
	var box := _side_box(r, side, a, b, top, top + 0.12)
	var s: Vector3 = box[1]
	if side == "n" or side == "s":
		s.z += 0.16
	else:
		s.x += 0.16
	vbox(box[0], s, color, Basis.IDENTITY, {"shadows": false})


## Ramp collider (+ optional visual slab) whose top surface runs from floor point a to floor point b.
func ramp(a: Vector3, b: Vector3, width: float, color: Color, surface: String = "stone", visual: bool = true, thickness: float = 0.4) -> void:
	var d := b - a
	if Vector3(d.x, 0.0, d.z).length() < 0.01:
		return
	var fwd := d.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var basis := Basis(side, up, -fwd)
	var center := (a + b) * 0.5 - up * thickness * 0.5
	var size := Vector3(width, thickness, d.length())
	col_box(center, size, surface, basis)
	if visual:
		vbox(center, size, color, basis)


## Stairs from floor point a to floor point b: visual steps with nosings over a ramp collider.
func stairs(a: Vector3, b: Vector3, width: float, step_rise: float, color: Color, edge_color: Color, surface: String = "stone") -> void:
	ramp(a, b, width, color, surface, false)
	var hi := a if a.y > b.y else b
	var lo := b if a.y > b.y else a
	var rise := hi.y - lo.y
	var n := maxi(int(roundf(rise / step_rise)), 1)
	var rs := rise / float(n)
	var run := Vector3(lo.x - hi.x, 0.0, lo.z - hi.z)
	var run_len := run.length()
	if run_len < 0.01:
		return
	var dir := run / run_len
	var tread := run_len / float(n)
	var basis := Basis.looking_at(dir, Vector3.UP)
	for i in n:
		# The ramp surface passes through the middle of each tread (feet never sink or float much).
		var top_y := hi.y - (float(i) + 0.5) * rs
		var mid := hi + dir * (tread * (float(i) + 0.5))
		var bottom_y := lo.y - 0.2
		var hh := top_y - bottom_y
		vbox(Vector3(mid.x, bottom_y + hh * 0.5, mid.z), Vector3(width, hh, tread + 0.02), color, basis)
		vbox(Vector3(mid.x, top_y - 0.03, mid.z) + dir * (tread * 0.5 - 0.05), Vector3(width * 0.98, 0.07, 0.12), edge_color, basis, {"shadows": false})


# --- Dressing ---------------------------------------------------------------------------------------------

## A pillar candle standing on `pos` (base). Returns the flame position.
func candle(pos: Vector3, height: float = 0.26, radius: float = 0.045, wax: Color = Color("f6ead2")) -> Vector3:
	vcyl(pos + Vector3.UP * height * 0.5, radius, height, wax, Basis.IDENTITY, {"shadows": false, "segments": 10})
	var f := pos + Vector3.UP * (height + radius * 1.1)
	glow_sphere(f, Vector3(radius * 1.3, radius * 2.6, radius * 1.3), FLAME, 3.0)
	return f


## Wall sconce: bracket + dish + candle. `normal` = direction into the room.
func sconce(pos: Vector3, normal: Vector3, metal: Color = Color("c9a54a")) -> Vector3:
	var n := Vector3(normal.x, 0.0, normal.z).normalized()
	var face := Basis.looking_at(-n, Vector3.UP)
	vbox(pos + n * 0.03 + Vector3.UP * -0.06, Vector3(0.14, 0.3, 0.05), metal, face, {"shadows": false})
	vbox(pos + n * 0.15, Vector3(0.04, 0.04, 0.26), metal, face, {"shadows": false})
	vcyl(pos + n * 0.27 + Vector3.UP * 0.02, 0.09, 0.03, metal, Basis.IDENTITY, {"shadows": false})
	return candle(pos + n * 0.27 + Vector3.UP * 0.035, 0.2, 0.038)


## A crescent window on a wall: frame + glowing pane with a darker disc biting the crescent out of it.
## `inward` = direction into the room (the window sits on the inner wall face at `center`).
func crescent_window(center: Vector3, inward: Vector3, radius: float, glass: Color, frame: Color, energy: float = 1.1) -> void:
	var n := Vector3(inward.x, 0.0, inward.z).normalized()
	var basis := Basis.looking_at(-n, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	vcyl(center + n * 0.02, radius * 1.12, 0.06, frame, basis, {"shadows": false, "segments": 20})
	glow_disc(center + n * 0.055, radius, glass, energy, basis)
	var bite := center + n * 0.07 + n.cross(Vector3.UP).normalized() * radius * 0.42 + Vector3.UP * radius * 0.12
	vcyl(bite, radius * 0.86, 0.02, frame.darkened(0.35), basis, {"shadows": false, "segments": 20})


## Tall arched window: frame, glowing pane, rounded top, mullion. `inward` = into the room.
func arched_window(base_center: Vector3, inward: Vector3, width: float, height: float, glass: Color, frame: Color, energy: float = 0.9) -> void:
	var n := Vector3(inward.x, 0.0, inward.z).normalized()
	var across := n.cross(Vector3.UP).normalized()
	var face := Basis.looking_at(-n, Vector3.UP)
	var rect_h := height - width * 0.5
	glow_box(base_center + Vector3.UP * rect_h * 0.5 + n * 0.04, Vector3(width, rect_h, 0.03), glass, energy, face)
	glow_disc(base_center + Vector3.UP * rect_h + n * 0.04, width * 0.5, glass, energy, face * Basis(Vector3.RIGHT, PI * 0.5))
	for sx in [-1.0, 1.0]:
		vbox(base_center + across * float(sx) * (width * 0.5 + 0.06) + Vector3.UP * rect_h * 0.5 + n * 0.05, Vector3(0.12, rect_h, 0.1), frame, face, {"shadows": false})
	vbox(base_center + Vector3.UP * rect_h * 0.5 + n * 0.07, Vector3(0.05, rect_h, 0.05), frame, face, {"shadows": false})
	vbox(base_center + Vector3.UP * (rect_h * 0.55) + n * 0.07, Vector3(width, 0.05, 0.05), frame, face, {"shadows": false})
	vbox(base_center + Vector3.UP * -0.04 + n * 0.1, Vector3(width + 0.3, 0.1, 0.22), frame, face, {"shadows": false})
	vring(base_center + Vector3.UP * rect_h + n * 0.06, width * 0.56, 0.6, frame, face * Basis(Vector3.RIGHT, PI * 0.5))


## Velvet curtain hanging from `top_center` (a rod), `width` wide, `height` tall. `inward` = into the room.
## open: 0 = drawn closed, 1 = gathered to the sides.
func curtain(top_center: Vector3, inward: Vector3, width: float, height: float, color: Color, trim: Color, open: float = 0.7) -> void:
	var n := Vector3(inward.x, 0.0, inward.z).normalized()
	var across := n.cross(Vector3.UP).normalized()
	var face := Basis.looking_at(-n, Vector3.UP)
	vcyl(top_center + n * 0.14, 0.035, width + 0.5, trim, face * Basis(Vector3.FORWARD, PI * 0.5), {"shadows": false})
	for end in [-1.0, 1.0]:
		vsphere(top_center + n * 0.14 + across * float(end) * (width * 0.5 + 0.28), Vector3(0.1, 0.1, 0.1), trim, Basis.IDENTITY, {"shadows": false})
	var half := width * 0.5
	var folds := maxi(int(width / 0.28), 3)
	for side in [-1.0, 1.0]:
		var span := half * lerpf(1.0, 0.36, clampf(open, 0.0, 1.0))
		var nf := maxi(int(float(folds) * span / width * 2.0), 2)
		for i in nf:
			var t := (float(i) + 0.5) / float(nf)
			var off := float(side) * (half - span * t)
			var c := top_center + n * 0.16 + across * off + Vector3.UP * (-height * 0.5)
			var shade := color.darkened(0.12 if i % 2 == 0 else 0.0)
			vcyl(c, 0.16, height, shade, face, {"shadows": false, "segments": 8})
		# tie-back sash
		if open > 0.2:
			var tc := top_center + n * 0.3 + across * float(side) * (half - span * 0.5) + Vector3.UP * (-height * 0.62)
			vring(tc, span * 0.55, 0.35, trim, face * Basis(Vector3.RIGHT, PI * 0.5))
	# valance
	vbox(top_center + n * 0.2 + Vector3.UP * -0.12, Vector3(width + 0.4, 0.34, 0.12), color.darkened(0.2), face, {"shadows": false})
	for i in int(width / 0.4) + 1:
		var px := -width * 0.5 + float(i) * 0.4
		vsphere(top_center + n * 0.24 + across * px + Vector3.UP * -0.32, Vector3(0.07, 0.1, 0.07), trim, Basis.IDENTITY, {"shadows": false, "segments": 8})


## Chandelier: chain, three tiers of gilt rings with candles and crystal drops. Returns the candle flames.
func chandelier(center: Vector3, radius: float, gold: Color, ceiling_y: float, tiers: int = 2) -> Array:
	var flames: Array = []
	vcyl(Vector3(center.x, (center.y + ceiling_y) * 0.5, center.z), 0.03, ceiling_y - center.y, gold.darkened(0.3), Basis.IDENTITY, {"shadows": false})
	vsphere(center + Vector3.UP * 0.1, Vector3(0.36, 0.5, 0.36), gold, Basis.IDENTITY, {"shadows": false})
	for t in tiers:
		var rr := radius * (1.0 - float(t) * 0.42)
		var ty := center.y - 0.1 + float(t) * 0.55
		vring(Vector3(center.x, ty, center.z), rr, 0.5, gold)
		var count := maxi(int(rr * 7.0), 5)
		for i in count:
			var a := TAU * float(i) / float(count) + float(t) * 0.3
			var p := Vector3(center.x + cos(a) * rr, ty, center.z + sin(a) * rr)
			vcyl(p + Vector3.UP * 0.02, 0.07, 0.04, gold, Basis.IDENTITY, {"shadows": false})
			flames.append(candle(p + Vector3.UP * 0.04, 0.18, 0.035))
			glow_sphere(p + Vector3.DOWN * 0.18, Vector3(0.05, 0.1, 0.05), Color("f4e8ff"), 0.9)
		for i in count:
			var a2 := TAU * (float(i) + 0.5) / float(count)
			var arm_end := Vector3(center.x + cos(a2) * rr, ty, center.z + sin(a2) * rr)
			var mid := (arm_end + center) * 0.5
			var d := arm_end - center
			if d.length() > 0.05:
				vbox(mid + Vector3.UP * 0.05, Vector3(0.04, 0.04, d.length()), gold, Basis.looking_at(d.normalized(), Vector3.UP), {"shadows": false})
	vsphere(center + Vector3.DOWN * 0.45, Vector3(0.18, 0.32, 0.18), Color("f4e8ff"), Basis.IDENTITY, {"shadows": false})
	return flames


## Floor rug with a border (visual only, sits just above the floor).
func rug(center: Vector3, size: Vector2, color: Color, border: Color, basis: Basis = Basis.IDENTITY) -> void:
	vbox(center + Vector3.UP * 0.012, Vector3(size.x, 0.024, size.y), border, basis, {"shadows": false})
	vbox(center + Vector3.UP * 0.02, Vector3(size.x - 0.3, 0.024, size.y - 0.3), color, basis, {"shadows": false})


func round_rug(center: Vector3, radius: float, color: Color, border: Color) -> void:
	vcyl(center + Vector3.UP * 0.012, radius, 0.024, border, Basis.IDENTITY, {"shadows": false, "segments": 32})
	vcyl(center + Vector3.UP * 0.02, radius - 0.25, 0.024, color, Basis.IDENTITY, {"shadows": false, "segments": 32})


## Pilaster on a wall (decor): base, shaft, capital. `inward` = into the room.
func pilaster(base: Vector3, inward: Vector3, height: float, color: Color, cap: Color) -> void:
	var n := Vector3(inward.x, 0.0, inward.z).normalized()
	var face := Basis.looking_at(-n, Vector3.UP)
	vbox(base + Vector3.UP * 0.15 + n * 0.08, Vector3(0.5, 0.3, 0.16), cap, face, {"shadows": false})
	vbox(base + Vector3.UP * height * 0.5 + n * 0.06, Vector3(0.34, height, 0.12), color, face, {"shadows": false})
	vbox(base + Vector3.UP * (height - 0.12) + n * 0.09, Vector3(0.5, 0.24, 0.18), cap, face, {"shadows": false})


## Free-standing column with collision. Returns nothing.
func column(base: Vector3, radius: float, height: float, color: Color, cap: Color, surface: String = "stone") -> void:
	vcyl(base + Vector3.UP * 0.15, radius * 1.35, 0.3, cap)
	vcyl(base + Vector3.UP * height * 0.5, radius, height, color)
	vcyl(base + Vector3.UP * (height - 0.15), radius * 1.35, 0.3, cap)
	col_cyl(base + Vector3.UP * height * 0.5, radius * 1.1, height, surface)


## A picture frame on a wall with a simple storybook "portrait" (bat-masked host or a landscape blob).
func portrait(center: Vector3, inward: Vector3, size: Vector2, frame: Color, canvas: Color, figure: Color, kind: String = "host") -> void:
	var n := Vector3(inward.x, 0.0, inward.z).normalized()
	var face := Basis.looking_at(-n, Vector3.UP)
	var across := n.cross(Vector3.UP).normalized()
	vbox(center + n * 0.04, Vector3(size.x + 0.22, size.y + 0.22, 0.08), frame, face, {"shadows": false})
	vbox(center + n * 0.08, Vector3(size.x, size.y, 0.02), canvas, face, {"shadows": false})
	if kind == "host":
		vsphere(center + n * 0.1 + Vector3.UP * size.y * 0.08, Vector3(size.x * 0.24, size.x * 0.24, 0.04), figure.lightened(0.4), face, {"shadows": false})
		for s in [-1.0, 1.0]:
			vsphere(center + n * 0.11 + Vector3.UP * size.y * 0.16 + across * float(s) * size.x * 0.13, Vector3(size.x * 0.12, size.x * 0.06, 0.03), figure, face, {"shadows": false})
		vprism(center + n * 0.1 + Vector3.UP * -size.y * 0.25, Vector3(size.x * 0.7, size.y * 0.45, 0.03), figure, face, {"shadows": false})
		vbox(center + n * 0.11 + Vector3.UP * size.y * 0.3, Vector3(size.x * 0.16, size.x * 0.08, 0.02), Color("e9c25a"), face, {"shadows": false})
	else:
		vsphere(center + n * 0.1 + Vector3.UP * -size.y * 0.18, Vector3(size.x * 0.8, size.y * 0.3, 0.03), figure, face, {"shadows": false})
		vsphere(center + n * 0.1 + Vector3.UP * size.y * 0.22 + across * size.x * 0.22, Vector3(size.x * 0.14, size.x * 0.14, 0.03), Color("f3e6c8"), face, {"shadows": false})


## Potted plant / little fern (decor, no collision).
func potted_plant(base: Vector3, pot: Color, leaf: Color, scale: float = 1.0) -> void:
	vtaper(base + Vector3.UP * 0.22 * scale, 0.2 * scale, 0.27 * scale, 0.44 * scale, pot, Basis.IDENTITY, {"shadows": false})
	for i in 5:
		var a := TAU * float(i) / 5.0
		vsphere(base + Vector3(cos(a) * 0.14 * scale, 0.62 * scale, sin(a) * 0.14 * scale), Vector3(0.22, 0.34, 0.22) * scale, leaf.darkened(0.08 * float(i % 2)), Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.4), {"shadows": false})


## A pumpkin (festival decor, no collision).
func pumpkin(base: Vector3, radius: float, color: Color = Color("e8862f")) -> void:
	for i in 5:
		var a := TAU * float(i) / 5.0
		vsphere(base + Vector3(cos(a) * radius * 0.35, radius * 0.72, sin(a) * radius * 0.35), Vector3(radius * 1.2, radius * 1.45, radius * 1.2), color.darkened(0.05 * float(i % 2)), Basis(Vector3.UP, a), {"shadows": false, "segments": 10})
	vcyl(base + Vector3.UP * radius * 1.55, radius * 0.12, radius * 0.5, Color("6b8a3a"), Basis(Vector3.FORWARD, 0.25), {"shadows": false, "segments": 6})


# --- Flush --------------------------------------------------------------------------------------------------

func finish() -> void:
	for key in _batches:
		var b: Dictionary = _batches[key]
		var xfs: Array = b["xf"]
		var cols: Array = b["col"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = b["mesh"]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
			mm.set_instance_color(i, cols[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = b["mat"]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b["shadows"] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "Batch"
		mmi.visibility_range_end = visibility_end
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		var parent: Node3D = room_nodes.get(b["room"], root)
		parent.add_child(mmi)
	_batches.clear()


# --- Small helpers --------------------------------------------------------------------------------------------

## Adds a light under the current room node. Shadowed lights are budgeted by the caller.
func lamp(pos: Vector3, color: Color, energy: float, light_range: float, shadow: bool = false) -> OmniLight3D:
	var o := OmniLight3D.new()
	o.position = pos
	o.light_color = color
	o.light_energy = energy
	o.omni_range = light_range
	o.omni_attenuation = 1.2
	o.shadow_enabled = shadow
	o.light_volumetric_fog_energy = 0.0
	o.distance_fade_enabled = true
	o.distance_fade_begin = 30.0
	o.distance_fade_length = 10.0
	if shadow:
		o.distance_fade_shadow = 22.0
		o.shadow_bias = 0.06
	o.name = "Light%d" % _lamps
	_lamps += 1
	node().add_child(o)
	return o
