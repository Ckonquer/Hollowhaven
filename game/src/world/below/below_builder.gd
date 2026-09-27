extends RefCounted
## Geometry builder for The Below.
## * Collision: one StaticBody3D per (room, surface) on layer 1 with meta "surface" (stone/wood/water),
##   holding many box shapes. Stairs are visual steps over a RAMP collider.
## * Visuals: repeated shapes (rock blobs, blocks, planks, pebbles...) are collected per room and flushed
##   into MultiMeshInstance3D nodes by finish() (one draw per mesh/material per room). Instance colours
##   tint a shared white toon material, so the whole dungeon uses a handful of materials.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/below/below_layout.gd")

const WALL_T := 1.0            # collision wall thickness (outside the room box)
const BLOB_VARIANTS := 6

var root: Node3D
var room: String = ""
var room_nodes: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _bodies: Dictionary = {}
var _batches: Dictionary = {}
var _occluders: Array = []       # [room, center, size, basis] boxes for occlusion culling
var batch_visibility_end: float = 85.0

static var _meshes: Dictionary = {}


func _init(p_root: Node3D, seed_value: int = 7331) -> void:
	root = p_root
	rng.seed = seed_value


# --- Shared unit meshes -----------------------------------------------------------------

static func unit_box() -> Mesh:
	if not _meshes.has("box"):
		var m := BoxMesh.new()
		m.size = Vector3.ONE
		_meshes["box"] = m
	return _meshes["box"]


static func unit_cyl(segments: int = 12) -> Mesh:
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


static func unit_cone(segments: int = 10) -> Mesh:
	var key := "cone%d" % segments
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = 0.0
		m.bottom_radius = 0.5
		m.height = 1.0
		m.radial_segments = segments
		m.rings = 1
		_meshes[key] = m
	return _meshes[key]


static func unit_sphere() -> Mesh:
	if not _meshes.has("sph"):
		var m := SphereMesh.new()
		m.radius = 0.5
		m.height = 1.0
		m.rings = 8
		m.radial_segments = 12
		_meshes["sph"] = m
	return _meshes["sph"]


## Unit-radius lumpy rock (variant 0..5). Big rocks use 3 subdivisions, pebbles 1.
static func unit_blob(variant: int, small: bool = false) -> Mesh:
	var v := posmod(variant, BLOB_VARIANTS)
	if small:
		return Kit.blob_mesh(1.0, 101 + v, 0.28, 1.0, 1)
	return Kit.blob_mesh(1.0, 11 + v * 7, 0.24, 1.0, 3)


static func tint_mat(opts: Dictionary = {}) -> Material:
	var o := {"vertex_color": true, "noise": 0.10, "rim": 0.22}
	for k in ["noise", "rim", "emission", "emission_energy", "noise_scale", "specular"]:
		if opts.has(k):
			o[k] = opts[k]
	return Mat.toon(Color.WHITE, o)


# --- Rooms ----------------------------------------------------------------------------------

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


# --- Collision ----------------------------------------------------------------------------------

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


# --- Batched visuals -------------------------------------------------------------------------------

func batch(mesh: Mesh, mat: Material, xf: Transform3D, color: Color = Color.WHITE, shadows: bool = true) -> void:
	var key := "%s|%d|%d|%s" % [room, mesh.get_instance_id(), mat.get_instance_id(), shadows]
	if not _batches.has(key):
		_batches[key] = {"mesh": mesh, "mat": mat, "room": room, "xf": [], "col": [], "shadows": shadows}
	_batches[key]["xf"].append(xf)
	_batches[key]["col"].append(color)


func vbox(center: Vector3, size: Vector3, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	var mat: Material = tint_mat(opts)
	if opts.get("outline", false):
		mat = Mat.outlined(mat, float(opts.get("outline_w", 0.02)))
	batch(unit_box(), mat, Transform3D(basis.scaled_local(size), center), color, bool(opts.get("shadows", true)))


func vcyl(center: Vector3, radius: float, height: float, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	var mat: Material = tint_mat(opts)
	if opts.get("outline", false):
		mat = Mat.outlined(mat, float(opts.get("outline_w", 0.02)))
	batch(unit_cyl(int(opts.get("segments", 12))), mat, Transform3D(basis.scaled_local(Vector3(radius * 2.0, height, radius * 2.0)), center), color, bool(opts.get("shadows", true)))


func vcone(center: Vector3, radius: float, height: float, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_cone(), tint_mat(opts), Transform3D(basis.scaled_local(Vector3(radius * 2.0, height, radius * 2.0)), center), color, bool(opts.get("shadows", true)))


func vsphere(center: Vector3, scl: Vector3, color: Color, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	batch(unit_sphere(), tint_mat(opts), Transform3D(basis.scaled_local(scl), center), color, bool(opts.get("shadows", true)))


## Lumpy rock with per-axis radii (scl) and a random or given variant.
func vblob(center: Vector3, scl: Vector3, color: Color, variant: int = -1, basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	var v := variant if variant >= 0 else rng.randi_range(0, BLOB_VARIANTS - 1)
	var small := bool(opts.get("small", false))
	batch(unit_blob(v, small), tint_mat(opts), Transform3D(basis.scaled_local(scl), center), color, bool(opts.get("shadows", not small)))


## Glowing batched instance (unshaded emissive, e.g. glowcap caps, crystal tips).
func vglow(mesh: Mesh, xf: Transform3D, color: Color, energy: float = 2.0) -> void:
	batch(mesh, Mat.glow(color, energy), xf, Color.WHITE, false)


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
		mmi.visibility_range_end = batch_visibility_end
		mmi.visibility_range_end_margin = 12.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		var parent: Node3D = room_nodes.get(b["room"], root)
		parent.add_child(mmi)
	_batches.clear()
	for o in _occluders:
		var oi := OccluderInstance3D.new()
		var bo := BoxOccluder3D.new()
		bo.size = o[2]
		oi.occluder = bo
		oi.name = "Occluder"
		var par: Node3D = room_nodes.get(o[0], root)
		par.add_child(oi)
		oi.transform = Transform3D(o[3], o[1])
	_occluders.clear()


# --- Colour helpers ------------------------------------------------------------------------------------

func vary(c: Color, amount: float = 0.08) -> Color:
	var f := 1.0 + rng.randf_range(-amount, amount)
	return Color(c.r * f, c.g * f, c.b * f, 1.0)


func pick(colors: Array) -> Color:
	return colors[rng.randi_range(0, colors.size() - 1)]


# --- Composite pieces --------------------------------------------------------------------------------------

## Visible solid box with collision.
func solid(center: Vector3, size: Vector3, color: Color, surface: String = "stone", basis: Basis = Basis.IDENTITY, opts: Dictionary = {}) -> void:
	vbox(center, size, color, basis, opts)
	col_box(center, size, surface, basis)
	if not opts.get("no_occluder", false):
		occluder(center, size, basis)


## Floor slab whose top is at y. hole = [x0, x1, z0, z1] cut out (filled separately, e.g. water).
func floor_rect(x0: float, x1: float, z0: float, z1: float, y: float, color: Color, surface: String = "stone", visual: bool = true) -> void:
	var c := Vector3((x0 + x1) * 0.5, y - 0.25, (z0 + z1) * 0.5)
	var s := Vector3(x1 - x0, 0.5, z1 - z0)
	col_box(c, s, surface)
	occluder(c, s * Vector3(1.0, 0.6, 1.0))
	if visual:
		vbox(c, s, color)


func ceiling_rect(x0: float, x1: float, z0: float, z1: float, y: float, color: Color, collide: bool = true) -> void:
	var c := Vector3((x0 + x1) * 0.5, y + 0.3, (z0 + z1) * 0.5)
	var s := Vector3(x1 - x0 + 0.2, 0.6, z1 - z0 + 0.2)
	vbox(c, s, color)
	occluder(c, s * Vector3(0.98, 0.6, 0.98))
	if collide:
		col_box(c, s)


## Wall along one side of a room box, with openings. Returns the list of [a, b] solid spans.
func wall_side(r: Dictionary, side: String, color: Color, visual: bool = true) -> Array:
	var open_def = r.get("open", {}).get(side, [])
	if open_def is String and open_def == "all":
		return []
	var openings: Array = open_def if open_def is Array else []
	var y: float = float(r["y"])
	var h: float = float(r["h"])
	var along_x := side == "n" or side == "s"
	var a0: float = float(r["x0"]) if along_x else float(r["z0"])
	var a1: float = float(r["x1"]) if along_x else float(r["z1"])
	var spans: Array = []
	var cur := a0
	var sorted := openings.duplicate()
	sorted.sort_custom(func(p, q): return float(p[0]) < float(q[0]))
	for o in sorted:
		var oa: float = float(o[0])
		var ob: float = float(o[1])
		var oh: float = float(o[2])
		if oa > cur:
			spans.append([cur, oa])
		if oh < h - 0.01:
			_wall_piece(r, side, oa, ob, y + oh, y + h, color, visual)
		cur = ob
	if cur < a1:
		spans.append([cur, a1])
	for sp in spans:
		_wall_piece(r, side, float(sp[0]), float(sp[1]), y, y + h, color, visual)
	return spans


func _wall_piece(r: Dictionary, side: String, a: float, b: float, ylo: float, yhi: float, color: Color, visual: bool) -> void:
	if b - a < 0.01 or yhi - ylo < 0.01:
		return
	var c := Vector3.ZERO
	var s := Vector3.ZERO
	var cy := (ylo + yhi) * 0.5
	var sy := yhi - ylo
	match side:
		"n":
			c = Vector3((a + b) * 0.5, cy, float(r["z0"]) - WALL_T * 0.5)
			s = Vector3(b - a, sy, WALL_T)
		"s":
			c = Vector3((a + b) * 0.5, cy, float(r["z1"]) + WALL_T * 0.5)
			s = Vector3(b - a, sy, WALL_T)
		"w":
			c = Vector3(float(r["x0"]) - WALL_T * 0.5, cy, (a + b) * 0.5)
			s = Vector3(WALL_T, sy, b - a)
		"e":
			c = Vector3(float(r["x1"]) + WALL_T * 0.5, cy, (a + b) * 0.5)
			s = Vector3(WALL_T, sy, b - a)
	col_box(c, s)
	occluder(c, s)
	if visual:
		vbox(c, s, color)


## Box occluder (only for big solid pieces: walls, floors, ceilings).
func occluder(center: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var dims := [size.x, size.y, size.z]
	dims.sort()
	if float(dims[1]) < 1.2 or float(dims[2]) < 2.0:
		return
	_occluders.append([room, center, size, basis])


## Floor + ceiling + four walls from the layout table. Returns {side: spans}.
func shell(id: String, floor_color: Color, wall_color: Color, ceil_color: Color, opts: Dictionary = {}) -> Dictionary:
	var r: Dictionary = Layout.ROOMS[id]
	var y: float = float(r["y"])
	if not opts.get("no_floor", false):
		floor_rect(float(r["x0"]), float(r["x1"]), float(r["z0"]), float(r["z1"]), y, floor_color, String(opts.get("surface", "stone")))
	if not opts.get("no_ceiling", false):
		ceiling_rect(float(r["x0"]), float(r["x1"]), float(r["z0"]), float(r["z1"]), y + float(r["h"]), ceil_color)
	var out := {}
	for side in ["n", "s", "w", "e"]:
		out[side] = wall_side(r, side, wall_color, not opts.get("hide_walls", false))
	return out


## Ramp collider (+ optional visual slab) whose top surface runs from a to b (floor points).
func ramp(a: Vector3, b: Vector3, width: float, color: Color, surface: String = "stone", visual: bool = true, thickness: float = 0.4) -> void:
	var d := b - a
	var flat := Vector3(d.x, 0.0, d.z)
	if flat.length() < 0.01:
		return
	var length := d.length()
	var fwd := d.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var up := side.cross(fwd).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var basis := Basis(side, up, -fwd)
	var center := (a + b) * 0.5 - up * thickness * 0.5
	var size := Vector3(width, thickness, length)
	col_box(center, size, surface, basis)
	if visual:
		vbox(center, size, color, basis)


## Stairs from a (top or bottom floor point) to b: visual steps, ramp collision.
func stairs(a: Vector3, b: Vector3, width: float, step_rise: float, color: Color, edge_color: Color, surface: String = "stone") -> void:
	ramp(a, b, width, color, surface, false)
	var hi := a if a.y > b.y else b
	var lo := b if a.y > b.y else a
	var rise := hi.y - lo.y
	var n := maxi(int(roundf(rise / step_rise)), 1)
	var rs := rise / float(n)
	var run := Vector3(lo.x - hi.x, 0.0, lo.z - hi.z)
	var run_len := run.length()
	var dir := run / run_len
	var tread := run_len / float(n)
	var basis := Basis.looking_at(dir, Vector3.UP)
	for i in n:
		# Step i (from the top): top surface at hi.y - (i + 1) * rs + rs * 0.5 (half-rise offset keeps feet close).
		var top_y := hi.y - float(i + 1) * rs + rs * 0.5
		var mid := hi + dir * (tread * (float(i) + 0.5))
		var bottom_y := lo.y - 0.3
		var h := top_y - bottom_y
		var c := Vector3(mid.x, bottom_y + h * 0.5, mid.z)
		vbox(c, Vector3(width, h, tread + 0.02), vary(color, 0.05), basis)
		# nosing strip
		vbox(Vector3(mid.x, top_y - 0.04, mid.z) + dir * (tread * 0.5 - 0.06), Vector3(width * 0.98, 0.1, 0.14), edge_color, basis)


# --- Dressing ------------------------------------------------------------------------------------------------

## Lumpy rock dressing along a wall line p0 -> p1 (floor level). inward points into the room.
## skip: Array of [from, to, height] spans along the line (distance from p0) to keep clear (openings).
func rock_wall(p0: Vector3, p1: Vector3, inward: Vector3, h: float, colors: Array, opts: Dictionary = {}) -> void:
	var line := p1 - p0
	var length := line.length()
	if length < 0.2:
		return
	var dir := line / length
	var spacing: float = float(opts.get("spacing", 1.35))
	var size: float = float(opts.get("size", 1.0))
	var protrude: float = float(opts.get("protrude", 0.28))
	var skip: Array = opts.get("skip", [])
	var rows := maxi(int(ceilf(h / (1.25 * size))), 1)
	var n := maxi(int(ceilf(length / spacing)), 1)
	for i in n + 1:
		var t := (float(i) + rng.randf_range(-0.3, 0.3)) * length / float(n)
		t = clampf(t, 0.0, length)
		for row in rows:
			var yy := (float(row) + 0.45 + rng.randf_range(-0.2, 0.2)) * h / float(rows)
			if _skipped(t, yy, skip, 0.9 * size):
				continue
			var rr := size * rng.randf_range(0.8, 1.25)
			var depth := rr * 0.9
			var center := p0 + dir * t + Vector3.UP * yy - inward * (depth - protrude)
			var scl := Vector3(rr * rng.randf_range(0.9, 1.3), rr * rng.randf_range(0.75, 1.1), depth)
			var basis := Basis.looking_at(-inward, Vector3.UP).rotated(inward, rng.randf_range(-0.4, 0.4))
			vblob(center, scl, vary(pick(colors), 0.06), -1, basis)
	# Base rubble along the foot of the wall.
	if opts.get("base", true):
		var nb := int(length / 0.9)
		for i in nb:
			var t := rng.randf_range(0.0, length)
			if _skipped(t, 0.2, skip, 0.4):
				continue
			var rr := rng.randf_range(0.12, 0.34) * size
			var center := p0 + dir * t + inward * rng.randf_range(0.05, 0.35) + Vector3.UP * rr * 0.3
			vblob(center, Vector3(rr, rr * 0.7, rr), vary(pick(colors), 0.1), -1, Basis(Vector3.UP, rng.randf() * TAU), {"small": true})


func _skipped(t: float, y: float, skip: Array, margin: float) -> bool:
	for s in skip:
		if t > float(s[0]) - margin and t < float(s[1]) + margin and y < float(s[2]) + margin * 0.6:
			return true
	return false


## Dresses all walls of a layout room with rock blobs (openings kept clear).
func dress_room_rock(id: String, colors: Array, opts: Dictionary = {}) -> void:
	var r: Dictionary = Layout.ROOMS[id]
	var y: float = float(r["y"])
	var h: float = float(r["h"]) * float(opts.get("height_frac", 1.0))
	var x0: float = float(r["x0"])
	var x1: float = float(r["x1"])
	var z0: float = float(r["z0"])
	var z1: float = float(r["z1"])
	var sides := {
		"n": [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(0, 0, 1), x0],
		"s": [Vector3(x0, y, z1), Vector3(x1, y, z1), Vector3(0, 0, -1), x0],
		"w": [Vector3(x0, y, z0), Vector3(x0, y, z1), Vector3(1, 0, 0), z0],
		"e": [Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(-1, 0, 0), z0],
	}
	for side in sides:
		var od = r.get("open", {}).get(side, [])
		if od is String and od == "all":
			continue
		var skip: Array = []
		if od is Array:
			for o in od:
				skip.append([float(o[0]) - float(sides[side][3]), float(o[1]) - float(sides[side][3]), float(o[2])])
		var o2 := opts.duplicate()
		o2["skip"] = skip
		rock_wall(sides[side][0], sides[side][1], sides[side][2], h, colors, o2)


## Hanging lumps on a ceiling rect (cave feel).
func ceiling_lumps(x0: float, x1: float, z0: float, z1: float, y: float, colors: Array, count: int, size: float = 0.9) -> void:
	for i in count:
		var p := Vector3(rng.randf_range(x0 + 0.5, x1 - 0.5), y, rng.randf_range(z0 + 0.5, z1 - 0.5))
		var rr := size * rng.randf_range(0.6, 1.3)
		vblob(p + Vector3.UP * rr * 0.35, Vector3(rr * 1.2, rr * 0.7, rr * 1.1), vary(pick(colors), 0.06))


## Loose pebbles scattered on a floor rect.
func pebbles(x0: float, x1: float, z0: float, z1: float, y: float, colors: Array, count: int, size: float = 0.12) -> void:
	for i in count:
		var rr := size * rng.randf_range(0.5, 1.6)
		var p := Vector3(rng.randf_range(x0, x1), y + rr * 0.25, rng.randf_range(z0, z1))
		vblob(p, Vector3(rr, rr * 0.6, rr * 1.1), vary(pick(colors), 0.1), -1, Basis(Vector3.UP, rng.randf() * TAU), {"small": true})
