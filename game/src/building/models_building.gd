extends RefCounted
## Cottage building pieces: wooden floor tile, wall panels (plain / round window / arched doorway),
## thatch roof tile and picket fence. Walls run along X at rotation 0, centred on the grid line.
## Corner posts sit exactly on the wall ends so neighbouring panels share them seamlessly.

const Palette := preload("res://src/art/palette.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Batch := preload("res://src/building/batch.gd")
const Placement := preload("res://src/building/placement.gd")

const WALL_H := 3.0
const PLANK_BOTTOM := 0.3
const PLANK_TOP := 2.8
const PLANK_DEPTH := 0.16
const INNER := 0.88            # half-width of the planked area between the corner posts
const WINDOW_Y := 1.62
const WINDOW_HOLE := 0.39
const DOOR_HALF := 0.55
const DOOR_SPRING := 1.95      # where the arch starts
const ARCH_OUTER := 0.78

static var PLANK_BACK: Color = Palette.WOOD_DARK.darkened(0.25)
static var PLANK_COLORS: Array = [Palette.WOOD, Palette.WOOD.darkened(0.07), Palette.WOOD_LIGHT.darkened(0.06),
	Palette.WOOD.lightened(0.04), Palette.WOOD.darkened(0.03), Palette.WOOD_LIGHT.darkened(0.12)]


# --- Floor tile (2 x 2) ---------------------------------------------------------------------------------

static func wood_floor(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_floor", func(b: Batch) -> void:
		b.rbox(Vector3(2.0, 0.07, 2.0), Vector3(0, 0.035, 0), Palette.WOOD_DARK, 0.02)
		var cols := [Palette.WOOD, Palette.WOOD_LIGHT.darkened(0.05), Palette.WOOD.lightened(0.05), Palette.WOOD_LIGHT.darkened(0.12), Palette.WOOD.darkened(0.04)]
		for i in 5:
			var z := -0.8 + i * 0.4
			b.rbox(Vector3(1.99, 0.07, 0.385), Vector3(0, 0.085, z), cols[i], 0.022)
			for x in [-0.9, 0.9]:
				for dz in [-0.1, 0.1]:
					b.sphere(0.014, Vector3(x, 0.12, z + dz), Palette.BARK_DARK, Vector3(1, 0.4, 1))
		# a knot in one plank
		b.sphere(0.04, Vector3(0.35, 0.12, 0.4), Palette.WOOD_DARK, Vector3(1.4, 0.2, 0.8))
	)
	U.instance(root, mesh, U.vc_mat())
	return {}


# --- Walls ----------------------------------------------------------------------------------------------

static func _frame(b: Batch, stone_left: float = -1.0, stone_right: float = 1.0) -> void:
	# Corner posts centred on the panel ends (shared with neighbours), top beam, cobbled footing.
	for sx in [-1.0, 1.0]:
		b.rbox(Vector3(0.24, WALL_H, 0.26), Vector3(1.0 * sx, WALL_H * 0.5, 0), Palette.WOOD_DARK, 0.04)
	b.rbox(Vector3(2.0, 0.22, 0.25), Vector3(0, WALL_H - 0.11, 0), Palette.WOOD_DARK, 0.04)
	if stone_right > stone_left:
		_cobbles(b, stone_left, stone_right)


## A row of chunky rounded footing stones between x0 and x1.
static func _cobbles(b: Batch, x0: float, x1: float) -> void:
	var cols := [Palette.STONE, Palette.STONE_DARK, Palette.STONE.lightened(0.08), Palette.STONE.darkened(0.06)]
	var n := maxi(1, int(roundf((x1 - x0) / 0.42)))
	var w := (x1 - x0) / float(n)
	for i in n:
		var h := 0.3 + 0.03 * float((i * 5) % 3)
		b.rbox(Vector3(w - 0.025, h, 0.28), Vector3(x0 + w * (float(i) + 0.5), h * 0.5, 0), cols[i % cols.size()], 0.07)


## Adds vertical planks across [x0, x1] between y0 and y1, colouring by the plank index so pieces of one
## plank that are split around an opening keep the same colour.
static func _planks(b: Batch, x0: float, x1: float, y0: float, y1: float) -> void:
	var w := (2.0 * INNER) / 6.0
	var i := 0
	while i < 6:
		var px0 := -INNER + w * i
		var px1 := px0 + w
		var a := maxf(px0, x0)
		var c := minf(px1, x1)
		if c - a > 0.005 and y1 - y0 > 0.005:
			var gap: float = 0.012 if (a == px0) else 0.0
			var gap2: float = 0.012 if (c == px1) else 0.0
			b.rbox(Vector3(c - a - gap - gap2, y1 - y0, PLANK_DEPTH), Vector3((a + c) * 0.5 + (gap - gap2) * 0.5, (y0 + y1) * 0.5, 0), PLANK_COLORS[i % PLANK_COLORS.size()], 0.02)
			# Dark backing board so plank gaps never show daylight.
			b.rbox(Vector3(c - a, y1 - y0, PLANK_DEPTH * 0.55), Vector3((a + c) * 0.5, (y0 + y1) * 0.5, 0), PLANK_BACK, 0.004)
		i += 1


static func wood_wall(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_wall", func(b: Batch) -> void:
		_frame(b)
		_planks(b, -INNER, INNER, PLANK_BOTTOM, PLANK_TOP)
		b.rbox(Vector3(1.8, 0.1, 0.2), Vector3(0, 1.05, 0), Palette.WOOD_DARK, 0.03)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


static func wood_window(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_window", func(b: Batch) -> void:
		_frame(b)
		var h := WINDOW_HOLE
		# Planks: full outside the hole, split above/below it inside.
		_planks(b, -INNER, -h, PLANK_BOTTOM, PLANK_TOP)
		_planks(b, h, INNER, PLANK_BOTTOM, PLANK_TOP)
		_planks(b, -h, h, PLANK_BOTTOM, WINDOW_Y - h)
		_planks(b, -h, h, WINDOW_Y + h, PLANK_TOP)
		# Round frame on both faces, mullions
		for z in [0.095, -0.095]:
			b.torus(0.4, 0.56, Vector3(0, WINDOW_Y, z), Palette.WOOD_DARK, Vector3(90, 0, 0))
		b.rbox(Vector3(0.05, 0.84, 0.06), Vector3(0, WINDOW_Y, 0), Palette.WOOD_DARK, 0.015)
		b.rbox(Vector3(0.84, 0.05, 0.06), Vector3(0, WINDOW_Y, 0), Palette.WOOD_DARK, 0.015)
		# Flower box under the window (outside, +Z)
		var by := WINDOW_Y - 0.62
		b.rbox(Vector3(0.84, 0.17, 0.2), Vector3(0, by, 0.2), Palette.WOOD_LIGHT, 0.03)
		b.rbox(Vector3(0.78, 0.03, 0.15), Vector3(0, by + 0.075, 0.2), Palette.DIRT_DARK, 0.01)
		var fcols := [Palette.BLOSSOM, Palette.FLOWER_YELLOW, Palette.FLOWER_RED, Palette.FLOWER_BLUE, Palette.BLOSSOM]
		for i in 5:
			var fx := -0.3 + i * 0.15
			b.sphere(0.06, Vector3(fx, by + 0.12, 0.2 + (0.03 if i % 2 == 0 else -0.02)), Palette.FOLIAGE, Vector3(1.2, 0.8, 1.0))
			b.sphere(0.045, Vector3(fx + 0.02, by + 0.19, 0.24), fcols[i])
			b.sphere(0.018, Vector3(fx + 0.02, by + 0.21, 0.275), Palette.FLOWER_WHITE)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var glass := MeshInstance3D.new()
	glass.mesh = Shapes.prim_cylinder(0.41, 0.41, 0.02, 24)
	glass.material_override = U.glass_mat()
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glass)
	glass.position = Vector3(0, WINDOW_Y, 0)
	glass.rotation_degrees = Vector3(90, 0, 0)
	return {}


static func wood_doorway(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_doorway", func(b: Batch) -> void:
		_frame(b, 1.0, 0.0)     # no continuous footing: the opening stays clear
		_cobbles(b, -1.0, -DOOR_HALF)
		_cobbles(b, DOOR_HALF, 1.0)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.2, DOOR_SPRING, 0.26), Vector3((DOOR_HALF + 0.1) * sx, DOOR_SPRING * 0.5, 0), Palette.WOOD_DARK, 0.035)
		_planks(b, -INNER, -(DOOR_HALF + 0.19), PLANK_BOTTOM, PLANK_TOP)
		_planks(b, DOOR_HALF + 0.19, INNER, PLANK_BOTTOM, PLANK_TOP)
		# Planks above the arch, stepped so they never cut into the opening.
		var step := 0.125
		var x := -(DOOR_HALF + 0.2)
		while x < DOOR_HALF + 0.2 - 0.001:
			var x1 := minf(x + step, DOOR_HALF + 0.2)
			var near: float = minf(absf(x), absf(x1)) if x * x1 > 0.0 else 0.0
			var y0 := DOOR_SPRING
			if near < DOOR_HALF:
				y0 = DOOR_SPRING + sqrt(DOOR_HALF * DOOR_HALF - near * near)
			_planks(b, x, x1, y0, PLANK_TOP)
			x = x1
		b.add(Shapes.arch_ring(DOOR_HALF, ARCH_OUTER, 0.27, 20), Batch.xf(Vector3(0, DOOR_SPRING, 0)), Palette.WOOD_DARK)
		var ky := DOOR_SPRING + (DOOR_HALF + ARCH_OUTER) * 0.5
		b.rbox(Vector3(0.22, 0.28, 0.31), Vector3(0, ky, 0), Palette.STONE, 0.05)
		# A little carved heart on the keystone (outside face)
		b.heart(0.13, Vector3(0, ky + 0.005, 0.16), Palette.CLOTH_RED, 0.025)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Thatch roof tile (2 x 2, sits on the wall tops) -----------------------------------------------------

const ROOF_RISE := 1.2
const ROOF_EAVE := 0.22        # overhang past the low edge

static func roof_profile() -> Dictionary:
	# Low eave at +Z, ridge at -Z (rotation 0). Pair two tiles back to back for a gable.
	var eave := Vector2(1.0 + ROOF_EAVE, -ROOF_RISE / 2.0 * ROOF_EAVE)   # (z, y)
	var ridge := Vector2(-1.0, ROOF_RISE)
	return {"eave": eave, "ridge": ridge, "angle": rad_to_deg(atan2(ROOF_RISE, 2.0))}


static func wood_roof(root: Node3D) -> Dictionary:
	var mesh := U.baked("wood_roof", func(b: Batch) -> void:
		var prof := roof_profile()
		var e: Vector2 = prof["eave"]
		var r: Vector2 = prof["ridge"]
		var ang: float = prof["angle"]
		var dir := (r - e).normalized()          # up the slope in (z, y)
		var n := Vector2(dir.y, -dir.x)          # surface normal (z, y) pointing up/out
		if n.y < 0.0:
			n = -n
		var length := e.distance_to(r)
		var mid := (e + r) * 0.5
		# Timber under-slab (seen from inside) and gable ends
		b.rbox(Vector3(2.12, 0.08, length), Vector3(0, mid.y, mid.x), Palette.WOOD_DARK, 0.02, Vector3(ang, 0, 0))
		for sx in [-1.0, 1.0]:
			b.prism(Vector3(2.0, ROOF_RISE, 0.08), Vector3(0.95 * sx, ROOF_RISE * 0.5, 0), Palette.WOOD, Vector3(0, -90, 0), 0.0)
		# Puffy thatch courses, each overlapping the one below like shingles
		var rows := 4
		var tcols := [Palette.THATCH, Palette.THATCH.lightened(0.07), Palette.THATCH.darkened(0.04), Palette.THATCH.lightened(0.03)]
		var tufts := 7
		for i in rows:
			var t := (float(i) + 0.5) / float(rows)
			var p := e.lerp(r, t) + n * 0.13
			# Each course is a row of overlapping straw bundles: rounded ends make a scalloped edge.
			for k in tufts:
				var x := -1.13 + (2.26 / float(tufts)) * (float(k) + 0.5) + (0.05 if i % 2 == 1 else 0.0)
				var col: Color = (tcols[(i + k) % tcols.size()] as Color)
				var sag := 0.015 * float((k * 3 + i) % 3)
				b.rbox(Vector3(2.26 / float(tufts) + 0.1, 0.25, length / float(rows) + 0.24), Vector3(x, p.y - sag, p.x), col, 0.12, Vector3(ang + 10.0, 0, 0), false)
		# Scalloped fringe along the eave
		for k in 11:
			var x := -1.08 + 2.16 * float(k) / 10.0
			var fp := e + n * 0.08 - dir * 0.02
			b.sphere(0.12, Vector3(x, fp.y, fp.x), Palette.THATCH.darkened(0.1), Vector3(1.0, 0.55, 0.85))
		# Ridge roll sits exactly on the tile edge, so back-to-back tiles share one seamless ridge
		var ry := ROOF_RISE + 0.1
		b.cyl(0.15, 0.15, 2.24, Vector3(0, ry, r.x), Palette.THATCH.darkened(0.2), Vector3(0, 0, 90), 16)
		for x in [-0.72, 0.0, 0.72]:
			b.torus(0.14, 0.19, Vector3(x, ry, r.x), Palette.WOOD_DARK, Vector3(0, 0, 90), Vector3(1, 0.5, 1))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


## Convex collision points of the roof slab (local space).
static func roof_collision_points() -> PackedVector3Array:
	var prof := roof_profile()
	var e: Vector2 = prof["eave"]
	var r: Vector2 = prof["ridge"]
	var pts := PackedVector3Array()
	for sx in [-1.07, 1.07]:
		pts.append(Vector3(sx, e.y - 0.05, e.x))
		pts.append(Vector3(sx, e.y + 0.25, e.x))
		pts.append(Vector3(sx, r.y - 0.05, r.x))
		pts.append(Vector3(sx, r.y + 0.3, r.x))
		pts.append(Vector3(sx, 0.0, -1.0))
	return pts


# --- Picket fence (1 x 1, along X) ------------------------------------------------------------------------

static func fence(root: Node3D) -> Dictionary:
	var mesh := U.baked("fence", func(b: Batch) -> void:
		for y in [0.3, 0.62]:
			b.rbox(Vector3(1.04, 0.075, 0.05), Vector3(0, y, -0.04), Palette.CLOTH_CREAM.darkened(0.08), 0.02)
		for i in 3:
			var x := -0.333 + i * 0.333
			var col: Color = Palette.CLOTH_CREAM if i != 1 else Palette.FLOWER_WHITE
			b.rbox(Vector3(0.14, 0.76, 0.055), Vector3(x, 0.38, 0.02), col, 0.025)
			b.prism(Vector3(0.14, 0.13, 0.055), Vector3(x, 0.825, 0.02), col)
		# A few grass tufts at the base
		b.sphere(0.07, Vector3(-0.2, 0.02, 0.08), Palette.GRASS_DARK, Vector3(1.4, 0.7, 1.0))
		b.sphere(0.06, Vector3(0.24, 0.02, 0.07), Palette.GRASS, Vector3(1.3, 0.8, 1.0))
	)
	U.instance(root, mesh, U.vc_outlined(0.011))
	return {}
