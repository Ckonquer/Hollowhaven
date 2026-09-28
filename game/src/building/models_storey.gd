extends RefCounted
## Chapter Two storey pieces: wooden stairs, upper floor tile, railing, half wall, porch post, arched and
## crescent window walls, gable roof, roof corner (hip) and gothic porch trim. Same conventions as
## models_building.gd: footprint centred on the origin, ground (or the piece's rest height) at y = 0, walls
## run along X at rotation 0 centred on their grid line, one baked vertex-coloured mesh per piece (shared by
## every copy), glass as its own small mesh.

const Palette := preload("res://src/art/palette.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Batch := preload("res://src/building/batch.gd")
const Placement := preload("res://src/building/placement.gd")
const Parts := preload("res://src/building/models_building.gd")

const STAIR_STEPS := 12
const STAIR_RUN := 4.0                          # the stairs climb over their 4 m length (rot 0: +Z -> -Z)
const UPPER_SLAB := Vector3(2.0, 0.24, 2.0)     # collision slab of an upper floor tile (top at UPPER_TOP)
const ARCH_HALF := 0.4                          # arched window opening half-width
const ARCH_SILL := 0.9
const ARCH_SPRING := 2.15
const GABLE_RISE := 1.75
const GABLE_EAVE := 1.05                        # eave distance from the ridge line (tile half-depth + overhang)

static var TRIM: Color = Palette.K_PANTS.darkened(0.25)       # gothic trim: deep plum-brown paint


# --- Stairs (2 x 4) -------------------------------------------------------------------------------------

## Ramp collision under the treads: bottom edge at the entry (+Z), top edge flush with the landing floor.
static func stair_collision_points() -> PackedVector3Array:
	var h := Placement.STAIR_RISE
	var z := STAIR_RUN * 0.5
	var pts := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		pts.append(Vector3(sx, 0.0, z))
		pts.append(Vector3(sx, 0.0, -z))
		pts.append(Vector3(sx, h, -z))
	return pts


static func wood_stairs(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_stairs", func(b: Batch) -> void:
		var h := Placement.STAIR_RISE
		var rise := h / float(STAIR_STEPS)
		var run := STAIR_RUN / float(STAIR_STEPS)
		var half := STAIR_RUN * 0.5
		var cols := [Palette.WOOD_LIGHT, Palette.WOOD_LIGHT.darkened(0.06), Palette.WOOD]
		for i in STAIR_STEPS:
			var top := rise * float(i + 1)
			var zc := half - run * (float(i) + 0.5)
			b.rbox(Vector3(1.8, 0.07, run + 0.05), Vector3(0, top - 0.035, zc - 0.02), cols[i % cols.size()], 0.02)
			b.rbox(Vector3(1.76, rise - 0.06, 0.035), Vector3(0, top - 0.07 - (rise - 0.07) * 0.5, zc + run * 0.5 - 0.02), Palette.WOOD_DARK, 0.0)
		# Stringers along both sides, resting on the ground at the entry and on the landing at the top.
		var ang := rad_to_deg(atan2(h, STAIR_RUN))
		var length := sqrt(h * h + STAIR_RUN * STAIR_RUN) - 0.2
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.12, 0.3, length), Vector3(0.94 * sx, h * 0.5 - 0.1, 0.0), Palette.WOOD_DARK, 0.03, Vector3(ang, 0, 0))
			# Posts under the top end and newel posts with a handrail.
			b.rbox(Vector3(0.13, h - 0.12, 0.13), Vector3(0.9 * sx, (h - 0.12) * 0.5, -half + 0.1), Palette.WOOD_DARK, 0.03)
			b.rbox(Vector3(0.11, 0.95, 0.11), Vector3(0.94 * sx, rise + 0.47, half - 0.2), Palette.WOOD, 0.03)
			b.sphere(0.07, Vector3(0.94 * sx, rise + 0.98, half - 0.2), Palette.WOOD_LIGHT)
			b.rbox(Vector3(0.11, 0.9, 0.11), Vector3(0.94 * sx, h + 0.45, -half + 0.1), Palette.WOOD, 0.03)
			b.sphere(0.07, Vector3(0.94 * sx, h + 0.92, -half + 0.1), Palette.WOOD_LIGHT)
			var rail_len := sqrt(pow(STAIR_RUN - 0.3, 2.0) + pow(h - rise, 2.0))
			var rail_mid := Vector3(0.94 * sx, (rise + h) * 0.5 + 0.88, -0.05)
			b.rbox(Vector3(0.08, 0.07, rail_len), rail_mid, Palette.WOOD_LIGHT, 0.025, Vector3(ang, 0, 0))
			for k in 5:
				var t := (float(k) + 1.0) / 6.0
				var zb := lerpf(half - 0.2, -half + 0.1, t)
				var yb := lerpf(rise, h, t) + 0.02
				b.cyl(0.018, 0.018, 0.86, Vector3(0.94 * sx, yb + 0.43, zb), Palette.WOOD_DARK, Vector3.ZERO, 6)
		# A little heart carved on the bottom riser.
		b.heart(0.14, Vector3(0, rise * 0.5, half + 0.005), Palette.CLOTH_RED, 0.02)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Upper floor tile (2 x 2, one storey up) ---------------------------------------------------------------

static func upper_floor(root: Node3D) -> Dictionary:
	var mesh := U.baked("upper_floor", func(b: Batch) -> void:
		var top := Placement.UPPER_TOP
		# Sub-floor boards (seen from below) and three joists.
		b.rbox(Vector3(2.0, 0.1, 2.0), Vector3(0, top - 0.17, 0), Palette.WOOD_DARK, 0.0)
		for x in [-0.66, 0.0, 0.66]:
			b.rbox(Vector3(0.12, 0.12, 1.98), Vector3(x, top - 0.28, 0), Palette.BARK, 0.02)
		var cols := [Palette.WOOD_LIGHT, Palette.WOOD_LIGHT.darkened(0.08), Palette.WOOD.lightened(0.06), Palette.WOOD_LIGHT.darkened(0.03), Palette.WOOD]
		for i in 5:
			var z := -0.8 + i * 0.4
			b.rbox(Vector3(1.99, 0.07, 0.385), Vector3(0, top - 0.035, z), cols[i], 0.022)
			for x in [-0.9, 0.9]:
				b.sphere(0.014, Vector3(x, top, z), Palette.BARK_DARK, Vector3(1, 0.4, 1))
		b.sphere(0.035, Vector3(-0.4, top, -0.35), Palette.WOOD_DARK, Vector3(1.4, 0.2, 0.8))
	)
	U.instance(root, mesh, U.vc_mat())
	return {}


# --- Railing and half wall (edge pieces) ----------------------------------------------------------------------

static func wood_railing(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_railing", func(b: Batch) -> void:
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.12, 1.0, 0.12), Vector3(0.96 * sx, 0.5, 0), Palette.WOOD_DARK, 0.03)
			b.sphere(0.06, Vector3(0.96 * sx, 1.03, 0), Palette.WOOD_LIGHT)
		b.rbox(Vector3(2.0, 0.07, 0.12), Vector3(0, 0.94, 0), Palette.WOOD_LIGHT, 0.025)
		b.rbox(Vector3(1.9, 0.06, 0.08), Vector3(0, 0.14, 0), Palette.WOOD, 0.02)
		for i in 7:
			var x := -0.75 + 0.25 * float(i)
			b.rbox(Vector3(0.05, 0.76, 0.05), Vector3(x, 0.53, 0), Palette.WOOD if i % 2 == 0 else Palette.WOOD_LIGHT.darkened(0.05), 0.015)
		b.heart(0.13, Vector3(0, 0.62, 0.04), Palette.CLOTH_RED, 0.02)
	)
	U.instance(root, mesh, U.vc_outlined(0.011))
	return {}


static func half_wall(root: Node3D) -> Dictionary:
	var mesh := U.baked("half_wall", func(b: Batch) -> void:
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.24, 1.2, 0.26), Vector3(1.0 * sx, 0.6, 0), Palette.WOOD_DARK, 0.04)
		Parts._cobbles(b, -1.0, 1.0)
		Parts._planks(b, -Parts.INNER, Parts.INNER, Parts.PLANK_BOTTOM, 1.08)
		b.rbox(Vector3(2.16, 0.09, 0.32), Vector3(0, 1.155, 0), Palette.WOOD_LIGHT, 0.03)
		b.sphere(0.05, Vector3(-0.4, 1.23, 0.02), Palette.BLOSSOM)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Porch post (1 x 1, holds up an upper floor) ----------------------------------------------------------------

static func porch_post(root: Node3D) -> Dictionary:
	var mesh := U.baked("porch_post", func(b: Batch) -> void:
		b.rbox(Vector3(0.42, 0.26, 0.42), Vector3(0, 0.13, 0), Palette.STONE, 0.05)
		b.rbox(Vector3(0.2, 2.62, 0.2), Vector3(0, 1.55, 0), Palette.WOOD, 0.04)
		for y in [0.4, 2.7]:
			b.rbox(Vector3(0.27, 0.08, 0.27), Vector3(0, y, 0), Palette.WOOD_DARK, 0.02)
		b.rbox(Vector3(0.34, 0.16, 0.34), Vector3(0, 2.92, 0), Palette.WOOD_DARK, 0.03)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.44, 0.08, 0.1), Vector3(0.2 * sx, 2.62, 0), Palette.WOOD_DARK, 0.02, Vector3(0, 0, 40.0 * sx))
		# A climbing vine with a few blossoms.
		for i in 9:
			var a := float(i) * 1.1
			var y := 0.45 + float(i) * 0.24
			b.sphere(0.055, Vector3(cos(a) * 0.12, y, sin(a) * 0.12), Palette.FOLIAGE if i % 2 == 0 else Palette.FOLIAGE_LIGHT, Vector3(1.3, 0.6, 1.0))
			if i % 3 == 1:
				b.sphere(0.035, Vector3(cos(a) * 0.14, y + 0.04, sin(a) * 0.14), Palette.BLOSSOM)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Arched window wall ---------------------------------------------------------------------------------------

static func arched_window(root: Node3D) -> Dictionary:
	var mesh := U.baked("arched_window", func(b: Batch) -> void:
		Parts._frame(b)
		var w := ARCH_HALF + 0.06
		var top := ARCH_SPRING + ARCH_HALF
		Parts._planks(b, -Parts.INNER, -w, Parts.PLANK_BOTTOM, Parts.PLANK_TOP)
		Parts._planks(b, w, Parts.INNER, Parts.PLANK_BOTTOM, Parts.PLANK_TOP)
		Parts._planks(b, -w, w, Parts.PLANK_BOTTOM, ARCH_SILL)
		# Above the arch, stepped so the planks never cut into the opening.
		var step := 0.1
		var x := -w
		while x < w - 0.001:
			var x1 := minf(x + step, w)
			var near: float = minf(absf(x), absf(x1)) if x * x1 > 0.0 else 0.0
			var y0 := ARCH_SPRING
			if near < ARCH_HALF:
				y0 = ARCH_SPRING + sqrt(ARCH_HALF * ARCH_HALF - near * near) + 0.04
			if y0 < Parts.PLANK_TOP:
				Parts._planks(b, x, x1, y0, Parts.PLANK_TOP)
			x = x1
		b.add(Shapes.arch_ring(ARCH_HALF, ARCH_HALF + 0.1, 0.22, 18), Batch.xf(Vector3(0, ARCH_SPRING, 0)), Palette.WOOD_DARK)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.1, ARCH_SPRING - ARCH_SILL, 0.22), Vector3((ARCH_HALF + 0.05) * sx, (ARCH_SPRING + ARCH_SILL) * 0.5, 0), Palette.WOOD_DARK, 0.02)
		b.rbox(Vector3(1.0, 0.08, 0.34), Vector3(0, ARCH_SILL - 0.02, 0.02), Palette.WOOD_LIGHT, 0.025)
		b.rbox(Vector3(0.05, top - ARCH_SILL, 0.06), Vector3(0, (top + ARCH_SILL) * 0.5, 0), Palette.WOOD_DARK, 0.015)
		b.rbox(Vector3(ARCH_HALF * 2.0, 0.05, 0.06), Vector3(0, 1.62, 0), Palette.WOOD_DARK, 0.015)
		b.rbox(Vector3(0.2, 0.22, 0.26), Vector3(0, top + 0.08, 0), Palette.STONE, 0.04)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var glass := MeshInstance3D.new()
	glass.mesh = arch_pane(ARCH_HALF, ARCH_SPRING - ARCH_SILL, 0.02)
	glass.material_override = U.glass_mat()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	glass.position = Vector3(0, ARCH_SILL, 0)
	return {}


## Flat glass pane shaped like an arched window: a rectangle `rect_h` tall with a half circle on top,
## `depth` thick, bottom centre at the origin, facing +Z and -Z. Cached.
static func arch_pane(half_w: float, rect_h: float, depth: float, segments: int = 14) -> ArrayMesh:
	var key := "arch_pane|%.3f|%.3f|%.3f|%d" % [half_w, rect_h, depth, segments]
	if U._cache.has(key):
		return U._cache[key]
	var outline: Array = [Vector2(-half_w, 0.0), Vector2(half_w, 0.0)]
	for i in segments + 1:
		var a := PI * float(i) / float(segments)
		outline.append(Vector2(cos(a) * half_w, rect_h + sin(a) * half_w))
	var m := poly_slab(outline, Vector2(0.0, rect_h * 0.5), depth)
	U._cache[key] = m
	return m


## Convex polygon (XY outline) extruded along Z by `depth`: front, back and side faces.
static func poly_slab(outline: Array, inside: Vector2, depth: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var hz := depth * 0.5
	var n := outline.size()
	for side in [1.0, -1.0]:
		var base := verts.size()
		verts.append(Vector3(inside.x, inside.y, hz * side))
		norms.append(Vector3(0, 0, side))
		for p in outline:
			verts.append(Vector3((p as Vector2).x, (p as Vector2).y, hz * side))
			norms.append(Vector3(0, 0, side))
		for i in n:
			Shapes._tri_out(idx, verts, base, base + 1 + i, base + 1 + (i + 1) % n, Vector3(0, 0, side))
	for i in n:
		var a: Vector2 = outline[i]
		var c: Vector2 = outline[(i + 1) % n]
		var d := c - a
		var out := Vector3(d.y, -d.x, 0.0).normalized()
		if out.dot(Vector3(a.x - inside.x, a.y - inside.y, 0.0)) < 0.0:
			out = -out
		var base2 := verts.size()
		for p in [Vector3(a.x, a.y, hz), Vector3(c.x, c.y, hz), Vector3(c.x, c.y, -hz), Vector3(a.x, a.y, -hz)]:
			verts.append(p)
			norms.append(out)
		Shapes._tri_out(idx, verts, base2, base2 + 1, base2 + 2, out)
		Shapes._tri_out(idx, verts, base2, base2 + 2, base2 + 3, out)
	return Shapes._array_mesh(verts, norms, idx)


# --- Crescent window wall ---------------------------------------------------------------------------------------

static func crescent_window(root: Node3D) -> Dictionary:
	var wy := Parts.WINDOW_Y
	var mesh := U.baked("crescent_window", func(b: Batch) -> void:
		Parts._frame(b)
		var h := Parts.WINDOW_HOLE
		Parts._planks(b, -Parts.INNER, -h, Parts.PLANK_BOTTOM, Parts.PLANK_TOP)
		Parts._planks(b, h, Parts.INNER, Parts.PLANK_BOTTOM, Parts.PLANK_TOP)
		Parts._planks(b, -h, h, Parts.PLANK_BOTTOM, wy - h)
		Parts._planks(b, -h, h, wy + h, Parts.PLANK_TOP)
		for z in [0.095, -0.095]:
			b.torus(0.4, 0.54, Vector3(0, wy, z), TRIM, Vector3(90, 0, 0))
			# The dark "night" disc that turns the round pane into a crescent moon.
			b.cyl(0.33, 0.33, 0.03, Vector3(0.15, wy + 0.05, z * 0.7), Palette.K_PANTS.darkened(0.1), Vector3(90, 0, 0), 22)
		# Little painted stars around the frame (both faces).
		for sgn in [1.0, -1.0]:
			for p in [Vector2(-0.62, 2.25), Vector2(0.58, 2.35), Vector2(-0.55, 1.05), Vector2(0.64, 1.15)]:
				b.add(Shapes.star(0.07), Batch.xf(Vector3(p.x, p.y, 0.085 * sgn), Vector3(0, 90.0 - 90.0 * sgn, 0)), Palette.FLOWER_YELLOW)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var glass := MeshInstance3D.new()
	glass.mesh = Shapes.prim_cylinder(0.41, 0.41, 0.02, 24)
	glass.material_override = U.glass_mat()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	glass.position = Vector3(0, wy, 0)
	glass.rotation_degrees = Vector3(90, 0, 0)
	return {}


# --- Roofs -------------------------------------------------------------------------------------------------------

## Puffy thatch courses on one slope from `eave` to `ridge` ((z, y) pairs), `width` along X.
static func _thatch_slope(b: Batch, eave: Vector2, ridge: Vector2, width: float, rows: int, tufts: int, seed_shift: int) -> void:
	var dir := (ridge - eave).normalized()
	var n := Vector2(dir.y, -dir.x)
	if n.y < 0.0:
		n = -n
	var length := eave.distance_to(ridge)
	var ang := rad_to_deg(atan2(ridge.y - eave.y, eave.x - ridge.x))
	var tcols := [Palette.THATCH, Palette.THATCH.lightened(0.07), Palette.THATCH.darkened(0.04), Palette.THATCH.lightened(0.03)]
	var mid := (eave + ridge) * 0.5
	b.rbox(Vector3(width, 0.08, length), Vector3(0, mid.y, mid.x), Palette.WOOD_DARK, 0.02, Vector3(ang, 0, 0))
	for i in rows:
		var t := (float(i) + 0.5) / float(rows)
		var p := eave.lerp(ridge, t) + n * 0.12
		for k in tufts:
			var x := -width * 0.5 + (width / float(tufts)) * (float(k) + 0.5) + (0.05 if (i + seed_shift) % 2 == 1 else 0.0)
			var col: Color = tcols[(i + k + seed_shift) % tcols.size()]
			b.rbox(Vector3(width / float(tufts) + 0.1, 0.24, length / float(rows) + 0.22), Vector3(x, p.y - 0.012 * float((k * 3 + i) % 3), p.x), col, 0.1, Vector3(ang + 8.0, 0, 0), false)
	for k in 7:
		var x2 := -width * 0.5 + width * float(k) / 6.0
		var fp := eave + n * 0.07
		b.sphere(0.11, Vector3(x2, fp.y, fp.x), Palette.THATCH.darkened(0.1), Vector3(1.0, 0.55, 0.85))


static func gable_roof(root: Node3D) -> Dictionary:
	var mesh := U.baked("gable_roof", func(b: Batch) -> void:
		var ridge := GABLE_RISE
		var eave_y := -0.06
		_thatch_slope(b, Vector2(GABLE_EAVE, eave_y), Vector2(0.0, ridge), 2.2, 3, 5, 0)
		_thatch_slope(b, Vector2(-GABLE_EAVE, eave_y), Vector2(0.0, ridge), 2.2, 3, 5, 1)
		# Gable end boards with a round vent, and the ridge roll.
		for sx in [-1.0, 1.0]:
			b.prism(Vector3(1.96, ridge - 0.05, 0.08), Vector3(0.96 * sx, (ridge - 0.05) * 0.5, 0), Palette.WOOD, Vector3(0, 90, 0))
			b.torus(0.08, 0.13, Vector3(0.99 * sx, ridge * 0.42, 0), Palette.WOOD_DARK, Vector3(0, 0, 90))
		b.cyl(0.14, 0.14, 2.26, Vector3(0, ridge + 0.1, 0), Palette.THATCH.darkened(0.2), Vector3(0, 0, 90), 16)
		for x in [-0.75, 0.0, 0.75]:
			b.torus(0.13, 0.18, Vector3(x, ridge + 0.1, 0), Palette.WOOD_DARK, Vector3(0, 0, 90), Vector3(1, 0.5, 1))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


static func gable_collision_points() -> PackedVector3Array:
	var pts := PackedVector3Array()
	for sx in [-1.07, 1.07]:
		pts.append(Vector3(sx, -0.05, GABLE_EAVE))
		pts.append(Vector3(sx, -0.05, -GABLE_EAVE))
		pts.append(Vector3(sx, 0.2, GABLE_EAVE))
		pts.append(Vector3(sx, 0.2, -GABLE_EAVE))
		pts.append(Vector3(sx, GABLE_RISE + 0.25, 0.0))
	return pts


## Hip corner joining a roof row that slopes toward +Z (like wood_roof at rot 0) with one sloping toward +X
## (wood_roof at rot 90): high corner at (-1, rise, -1), both low edges at the eaves.
static func roof_corner(root: Node3D) -> Dictionary:
	var rise := Parts.ROOF_RISE
	var e := 1.0 + Parts.ROOF_EAVE
	var low := -rise * 0.5 * Parts.ROOF_EAVE
	var mesh := U.baked("roof_corner", func(b: Batch) -> void:
		var apex := Vector3(-1.0, rise, -1.0)
		var corner := Vector3(e, low, e)
		# Two thatch faces (thick triangles) meeting on the hip line.
		b.add(tri_slab(apex, Vector3(-1.0, low, e), corner, 0.12), Transform3D.IDENTITY, Palette.THATCH)
		b.add(tri_slab(apex, corner, Vector3(e, low, -1.0), 0.12), Transform3D.IDENTITY, Palette.THATCH.lightened(0.06))
		# Straw bundles in courses on each face.
		for i in 3:
			var t := (float(i) + 0.6) / 3.6
			for k in 3:
				var s := (float(k) + 0.5) / 3.0
				var pz := apex.lerp(Vector3(-1.0 + (e + 1.0) * s, low, e), t) + Vector3(0, 0.1, 0)
				var px := apex.lerp(Vector3(e, low, -1.0 + (e + 1.0) * s), t) + Vector3(0, 0.1, 0)
				if pz.x < pz.z - 0.15:
					b.sphere(0.2, pz, Palette.THATCH.darkened(0.03 * float(k)), Vector3(1.3, 0.45, 0.9), Vector3(-25, 0, 0))
				if px.z < px.x - 0.15:
					b.sphere(0.2, px, Palette.THATCH.lightened(0.03 * float(k)), Vector3(0.9, 0.45, 1.3), Vector3(0, 0, 25))
		# Hip roll along the diagonal and an eave fringe on both low edges.
		var d := corner - apex
		var mid := (apex + corner) * 0.5 + Vector3(0, 0.1, 0)
		var up := d.normalized()
		var side := up.cross(Vector3.UP).normalized()
		var fwd := side.cross(up).normalized()
		b.add(Shapes.prim_cylinder(0.12, 0.12, d.length(), 12), Transform3D(Basis(side, up, fwd), mid), Palette.THATCH.darkened(0.2))
		for k in 6:
			var f := float(k) / 5.0
			b.sphere(0.11, Vector3(-1.0 + (e + 1.0) * f, low + 0.05, e), Palette.THATCH.darkened(0.1), Vector3(1.0, 0.55, 0.85))
			b.sphere(0.11, Vector3(e, low + 0.05, -1.0 + (e + 1.0) * f), Palette.THATCH.darkened(0.1), Vector3(0.85, 0.55, 1.0))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


## Triangle a-b-c thickened downward by `thickness` (a closed prism).
static func tri_slab(a: Vector3, b2: Vector3, c: Vector3, thickness: float) -> ArrayMesh:
	var key := "tri_slab|%s|%s|%s|%.3f" % [a, b2, c, thickness]
	if U._cache.has(key):
		return U._cache[key]
	var down := Vector3(0, -thickness, 0)
	var top := [a, b2, c]
	var bot := [a + down, b2 + down, c + down]
	var centre := (a + b2 + c) / 3.0 + down * 0.5
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	var nt := (b2 - a).cross(c - a).normalized()
	if nt.y < 0.0:
		nt = -nt
	for face in [[top, nt], [bot, -nt]]:
		var base := verts.size()
		for p in face[0]:
			verts.append(p)
			norms.append(face[1])
		Shapes._tri_out(idx, verts, base, base + 1, base + 2, face[1])
	for i in 3:
		var p0: Vector3 = top[i]
		var p1: Vector3 = top[(i + 1) % 3]
		var q1: Vector3 = bot[(i + 1) % 3]
		var q0: Vector3 = bot[i]
		var out := (p1 - p0).cross(Vector3.DOWN).normalized()
		if out.dot((p0 + p1) * 0.5 - centre) < 0.0:
			out = -out
		var base2 := verts.size()
		for p in [p0, p1, q1, q0]:
			verts.append(p)
			norms.append(out)
		Shapes._tri_out(idx, verts, base2, base2 + 1, base2 + 2, out)
		Shapes._tri_out(idx, verts, base2, base2 + 2, base2 + 3, out)
	var m := Shapes._array_mesh(verts, norms, idx)
	U._cache[key] = m
	return m


static func corner_collision_points() -> PackedVector3Array:
	var rise := Parts.ROOF_RISE
	var e := 1.07
	return PackedVector3Array([Vector3(-e, 0.0, -e), Vector3(e, 0.0, -e), Vector3(e, 0.0, e), Vector3(-e, 0.0, e),
		Vector3(-e, rise + 0.25, -e), Vector3(e, 0.2, -e), Vector3(-e, 0.2, e), Vector3(e, 0.12, e)])


# --- Gothic porch trim (1 x 1, hugs the wall behind its cell) ------------------------------------------------------

static func gothic_trim(root: Node3D) -> Dictionary:
	var mesh := U.baked("gothic_trim", func(b: Batch) -> void:
		var z := -0.43
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.08, 2.9, 0.07), Vector3(0.44 * sx, 1.45, z), TRIM, 0.02)
			b.sphere(0.05, Vector3(0.44 * sx, 2.93, z), TRIM.lightened(0.15))
			# Pointed arch: short segments curving from the post tops to the peak.
			for k in 6:
				var t0 := float(k) / 6.0
				var t1 := float(k + 1) / 6.0
				var p0 := _gothic_arc(t0, sx)
				var p1 := _gothic_arc(t1, sx)
				var d := p1 - p0
				b.rbox(Vector3(d.length() + 0.03, 0.06, 0.06), Vector3((p0.x + p1.x) * 0.5, (p0.y + p1.y) * 0.5, z), TRIM, 0.015, Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))))
			# Trefoil rings in the spandrels.
			b.torus(0.05, 0.08, Vector3(0.3 * sx, 2.62, z + 0.01), TRIM, Vector3(90, 0, 0))
		b.rbox(Vector3(0.94, 0.07, 0.07), Vector3(0, 2.86, z), TRIM, 0.02)
		# Peak finial with a little crescent moon, and a lace fringe of drops.
		b.cyl(0.0, 0.05, 0.16, Vector3(0, 2.7, z), TRIM.lightened(0.1), Vector3.ZERO, 8)
		b.torus(0.05, 0.075, Vector3(0, 2.4, z + 0.02), Palette.FLOWER_YELLOW, Vector3(90, 0, 0))
		b.sphere(0.052, Vector3(0.028, 2.41, z + 0.035), TRIM, Vector3(1, 1, 0.5))
		for k in 7:
			var x := -0.36 + 0.12 * float(k)
			b.sphere(0.028, Vector3(x, 2.79 - 0.025 * float(k % 2), z + 0.01), TRIM.lightened(0.08), Vector3(1, 1.4, 1))
	)
	U.instance(root, mesh, U.vc_outlined(0.01))
	return {}


## Point on one side (sx) of the pointed arch, t = 0 at the post top (spring), 1 at the peak: each side is an
## arc centred on the opposite spring point (a classic two-centred arch), flattened a little in y.
static func _gothic_arc(t: float, sx: float) -> Vector2:
	var a := lerpf(0.0, PI / 3.0, t)
	return Vector2(-0.44 * sx + 0.88 * cos(a) * sx, 2.1 + 0.88 * sin(a) * 0.68)
