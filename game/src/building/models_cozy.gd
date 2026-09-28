extends RefCounted
## Chapter Two furniture and workshop stations: window flower box, curtains, bookshelf, wardrobe, vanity
## mirror, kitchen counter, furnace, loom & dye bench, companion bed and perch, cottage bench, music box,
## expedition board and the Lanternwake table. Local frame as in models_furniture.gd: footprint centred on the
## origin, ground at y = 0, the front faces +Z at rotation 0. `mount: wall` pieces hug the back (-Z) edge of
## their cell so they sit flush against the wall behind them. One baked mesh per piece (+ glass/glow parts).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Batch := preload("res://src/building/batch.gd")
const Placement := preload("res://src/building/placement.gd")

static var BRASS: Color = U.keep(Palette.K_SCARF.lerp(Palette.COPPER, 0.35).darkened(0.04))   # never dyed
## Book spines keep their colours when the shelf is recoloured (U.keep).
static var BOOK_COLS: Array = [U.keep(Palette.CLOTH_RED), U.keep(Palette.TEAL), U.keep(Palette.K_SCARF), U.keep(Palette.K_PANTS),
	U.keep(Palette.FOLIAGE_DARK), U.keep(Palette.BLOSSOM), U.keep(Palette.CLOTH_CREAM), U.keep(Palette.WOOD_DARK), U.keep(Palette.FLOWER_BLUE)]


# --- Window flower box (1 x 1, wall) ---------------------------------------------------------------------------

## A window box on two wall brackets at sill height (its top just under a round window's frame and under the
## arched window's sill). `dir` (model option "mount_dir", placement.gd mount_info): on a window panel the box
## shifts half a metre toward the window centre (-1 / +1 in local x) so it sits centred under the 2 m window;
## 0 = on its own cell (plain walls, previews).
static func flower_box(root: Node3D, dir: int = 0) -> Dictionary:
	var mesh := U.baked("flower_box", func(b: Batch) -> void:
		var back := Placement.MOUNT_BACK
		var z := back + 0.15
		var y := FLOWER_BOX_Y
		# Brackets: a plate on the wall and a curved brace under each end of the box.
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.07, 0.26, 0.04), Vector3(0.3 * sx, y - 0.2, back + 0.02), Palette.WOOD_DARK, 0.015)
			b.rbox(Vector3(0.06, 0.05, 0.3), Vector3(0.3 * sx, y - 0.19, back + 0.13), Palette.WOOD_DARK, 0.015, Vector3(-38, 0, 0))
			b.sphere(0.022, Vector3(0.3 * sx, y - 0.28, back + 0.045), Palette.BARK_DARK, Vector3(1, 1, 0.5))
		b.rbox(Vector3(0.9, 0.2, 0.26), Vector3(0, y, z), Palette.WOOD_LIGHT, 0.03)
		b.rbox(Vector3(0.94, 0.04, 0.3), Vector3(0, y - 0.1, z + 0.01), Palette.WOOD, 0.015)
		for x in [-0.3, 0.0, 0.3]:
			b.rbox(Vector3(0.012, 0.18, 0.01), Vector3(x + 0.15, y, z + 0.132), Palette.WOOD, 0.0)
		b.heart(0.09, Vector3(0, y, z + 0.135), Palette.CLOTH_RED, 0.015)
		b.rbox(Vector3(0.84, 0.03, 0.2), Vector3(0, y + 0.095, z), Palette.DIRT_DARK, 0.01)
		var fcols := [Palette.BLOSSOM, Palette.FLOWER_YELLOW, Palette.FLOWER_PURPLE, Palette.FLOWER_RED, Palette.BLOSSOM, Palette.FLOWER_BLUE]
		for i in 6:
			var fx := -0.36 + i * 0.144
			b.sphere(0.065, Vector3(fx, y + 0.13, z + 0.02 + (0.03 if i % 2 == 0 else -0.01)), Palette.FOLIAGE, Vector3(1.2, 0.8, 1.0))
			b.sphere(0.045, Vector3(fx + 0.02, y + 0.19, z + 0.06), fcols[i])
			b.sphere(0.018, Vector3(fx + 0.02, y + 0.21, z + 0.095), Palette.FLOWER_WHITE)
		# Ivy trailing over the front edge at both ends (the heart stays clear).
		for ix in [-0.37, 0.36]:
			for j in 4:
				b.sphere(0.032, Vector3(ix + 0.025 * float(j % 2), y + 0.1 - 0.06 * float(j), z + 0.14), Palette.FOLIAGE_DARK if j % 2 == 0 else Palette.FOLIAGE, Vector3(1.3, 0.75, 0.5), Vector3(0, 0, 25.0 * float(1 - 2 * (j % 2))))
	)
	var mi := U.instance(root, mesh, U.vc_outlined(0.01, {"wind": 0.012, "wind_height": 0.5, "wind_speed": 1.4}))
	mi.position.x = 0.5 * float(signi(dir))
	return {}


const FLOWER_BOX_Y := 0.72        # box centre height: top 0.82, flowers to ~0.95 (round windows start at 1.06)


# --- Curtains (1 x 1, wall) --------------------------------------------------------------------------------------

## Curtains on a rail held off the wall by brackets (in front of any window frame or sill). `dir` (model option
## "mount_dir"): on a window panel the piece is one half of a pair that frames the window: a single drape tied
## back on the side away from the window centre, the rail and valance running across to it (-1 / +1 = the
## window centre's side in local x). 0 = both drapes on the cell (plain walls, previews).
static func curtain(root: Node3D, dir: int = 0) -> Dictionary:
	var sd := signi(dir)
	var mesh := U.baked("curtain|%d" % sd, func(b: Batch) -> void:
		var back := Placement.MOUNT_BACK
		var z := back + CURTAIN_OUT
		var ry := CURTAIN_RAIL_Y
		b.cyl(0.025, 0.025, 1.0, Vector3(0, ry, z), Palette.WOOD_DARK, Vector3(0, 0, 90), 8)
		var ends: Array = [-1.0, 1.0] if sd == 0 else [-float(sd)]
		for sx in ends:
			b.sphere(0.05, Vector3(0.5 * sx, ry, z), BRASS)
		# Brackets from the wall to the rail (away from the panel's corner posts).
		for bx in [-0.34, 0.34]:
			b.rbox(Vector3(0.04, 0.04, CURTAIN_OUT + 0.02), Vector3(bx, ry, back + CURTAIN_OUT * 0.5), BRASS.darkened(0.15), 0.012)
			b.rbox(Vector3(0.06, 0.1, 0.02), Vector3(bx, ry, back + 0.01), BRASS.darkened(0.15), 0.01)
		# Valance: a scalloped band along the top.
		b.rbox(Vector3(0.98, 0.16, 0.06), Vector3(0, ry - 0.1, z + 0.05), Palette.CLOTH_RED.darkened(0.05), 0.03)
		for k in 6:
			b.sphere(0.085, Vector3(-0.41 + 0.164 * float(k), ry - 0.18, z + 0.05), Palette.CLOTH_RED.darkened(0.05), Vector3(1, 0.7, 0.45))
		# Drapes of soft folds, gathered by a ribbon tie-back.
		var sides: Array = [-1.0, 1.0] if sd == 0 else [-float(sd)]
		for sx in sides:
			for f in 3:
				var x: float = (0.2 + 0.1 * float(f)) * sx
				var col: Color = Palette.CLOTH_RED if f != 1 else Palette.CLOTH_RED.lightened(0.08)
				var top_h := ry - 1.25
				b.cyl(0.05, 0.035, ry - 0.2 - top_h, Vector3(x * 0.9 + 0.03 * sx, (ry - 0.2 + top_h) * 0.5, z + 0.03 + 0.02 * float(f % 2)), col, Vector3.ZERO, 10)
				b.cyl(0.035, 0.065, top_h - 0.06, Vector3(x + 0.02 * sx * float(f), (top_h + 0.06) * 0.5, z + 0.04 + 0.02 * float(f % 2)), col, Vector3(0, 0, -4.0 * sx), 10)
			b.torus(0.07, 0.1, Vector3(0.3 * sx, ry - 1.25, z + 0.06), Palette.K_SCARF, Vector3(90, 0, 0), Vector3(1.6, 1, 0.6))
			b.heart(0.08, Vector3(0.3 * sx, ry - 1.25, z + 0.12), Palette.K_SCARF, 0.02)
	)
	U.instance(root, mesh, U.vc_outlined(0.01))
	return {}


const CURTAIN_RAIL_Y := 2.45
const CURTAIN_OUT := 0.2          # rail in front of the wall face: clear of window frames (0.1) and sills (0.11)


# --- Bookshelf (2 x 1) ----------------------------------------------------------------------------------------------

static func bookshelf(root: Node3D) -> Dictionary:
	var mesh := U.baked("bookshelf", func(b: Batch) -> void:
		b.rbox(Vector3(1.86, 1.9, 0.05), Vector3(0, 0.98, -0.4), Palette.WOOD_DARK, 0.0)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.08, 1.96, 0.46), Vector3(0.93 * sx, 0.98, -0.2), Palette.WOOD, 0.025)
		for y in [0.06, 0.52, 0.98, 1.44]:
			b.rbox(Vector3(1.82, 0.05, 0.44), Vector3(0, y, -0.2), Palette.WOOD_LIGHT, 0.01)
		b.rbox(Vector3(2.0, 0.08, 0.52), Vector3(0, 1.96, -0.19), Palette.WOOD_DARK, 0.025)
		b.rbox(Vector3(1.9, 0.06, 0.06), Vector3(0, 0.03, 0.02), Palette.WOOD_DARK, 0.0)
		# Books: rows of spines with varied heights, a leaning book and a small stack.
		var rng := RandomNumberGenerator.new()
		rng.seed = 5150
		for row in 3:
			var y0 := 0.085 + 0.46 * float(row)
			var x := -0.84
			var n := 0
			while x < 0.78 and n < 16:
				var w := rng.randf_range(0.055, 0.1)
				var h := rng.randf_range(0.26, 0.37)
				var col: Color = BOOK_COLS[rng.randi() % BOOK_COLS.size()]
				if row == 1 and n == 5:
					b.rbox(Vector3(w, h, 0.3), Vector3(x + 0.08, y0 + h * 0.46, -0.2), col, 0.0, Vector3(0, 0, -18))
					x += 0.16
				else:
					b.rbox(Vector3(w, h, 0.3), Vector3(x + w * 0.5, y0 + h * 0.5, -0.2), col, 0.0)
					b.rbox(Vector3(w + 0.004, 0.02, 0.304), Vector3(x + w * 0.5, y0 + h * 0.75, -0.2), BRASS, 0.0)
					x += w + 0.008
				n += 1
				if row == 2 and x > 0.1:
					break
		for i in 3:
			b.rbox(Vector3(0.34, 0.06, 0.26), Vector3(0.52, 1.035 + 0.062 * float(i), -0.2), BOOK_COLS[(i * 3 + 1) % BOOK_COLS.size()], 0.0, Vector3(0, 8.0 * float(i), 0))
		# Top shelf: a potted plant, a candle and a jar of dried flowers.
		b.cyl(0.09, 0.07, 0.14, Vector3(-0.55, 1.535, -0.2), Palette.CLOTH_RED)
		for k in 5:
			var a := TAU * float(k) / 5.0
			b.sphere(0.08, Vector3(-0.55 + cos(a) * 0.06, 1.66, -0.2 + sin(a) * 0.05), Palette.FOLIAGE if k % 2 == 0 else Palette.FOLIAGE_LIGHT, Vector3(1.2, 0.8, 1.0))
		b.cyl(0.035, 0.035, 0.16, Vector3(0.0, 1.545, -0.2), Palette.CLOTH_CREAM, Vector3.ZERO, 8)
		b.sphere(0.022, Vector3(0.0, 1.64, -0.2), Palette.LANTERN_GLOW, Vector3(0.8, 1.3, 0.8))
		b.cyl(0.07, 0.07, 0.16, Vector3(0.45, 1.545, -0.2), Palette.WATER.lightened(0.3), Vector3.ZERO, 10)
		for k in 4:
			b.sphere(0.035, Vector3(0.43 + 0.02 * float(k), 1.67 + 0.02 * float(k % 2), -0.2), [Palette.FLOWER_PURPLE, Palette.FLOWER_YELLOW][k % 2])
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Wardrobe (2 x 1) ---------------------------------------------------------------------------------------------

static func wardrobe(root: Node3D) -> Dictionary:
	var mesh := U.baked("wardrobe", func(b: Batch) -> void:
		b.rbox(Vector3(1.8, 1.9, 0.8), Vector3(0, 1.1, 0), Palette.WOOD, 0.04)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.sphere(0.07, Vector3(0.8 * sx, 0.08, 0.32 * sz), Palette.WOOD_DARK, Vector3(1, 1.2, 1))
		b.rbox(Vector3(1.94, 0.12, 0.88), Vector3(0, 2.1, 0), Palette.WOOD_DARK, 0.03)
		b.rbox(Vector3(1.84, 0.1, 0.84), Vector3(0, 0.18, 0), Palette.WOOD_DARK, 0.03)
		b.prism(Vector3(0.9, 0.12, 0.1), Vector3(0, 2.22, 0.36), Palette.WOOD_DARK)
		b.heart(0.14, Vector3(0, 2.1, 0.45), Palette.CLOTH_RED, 0.02)
		# Two doors with inset panels and brass knobs; the right door has an oval mirror frame.
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.84, 1.7, 0.04), Vector3(0.44 * sx, 1.13, 0.405), Palette.WOOD_LIGHT, 0.02)
			b.rbox(Vector3(0.6, 0.5, 0.02), Vector3(0.44 * sx, 0.6, 0.43), Palette.WOOD, 0.015)
			b.sphere(0.035, Vector3(0.07 * sx, 1.1, 0.44), BRASS)
		b.rbox(Vector3(0.6, 0.72, 0.02), Vector3(-0.44, 1.45, 0.43), Palette.WOOD, 0.015)
		b.torus(0.25, 0.3, Vector3(0.44, 1.45, 0.43), BRASS, Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.45))
		b.sphere(0.03, Vector3(-0.44, 1.45, 0.445), Palette.BLOSSOM)
	)
	U.instance(root, mesh, U.vc_outlined(0.013))
	var mirror := MeshInstance3D.new()
	mirror.mesh = Shapes.prim_cylinder(0.26, 0.26, 0.012, 24)
	mirror.material_override = mirror_mat()
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mirror)
	mirror.position = Vector3(0.44, 1.45, 0.435)
	mirror.rotation_degrees = Vector3(90, 0, 0)
	mirror.scale = Vector3(1.0, 1.0, 1.45)
	return {}


## Soft silvery mirror glass (shared).
static func mirror_mat() -> Material:
	if U._cache.has("mirror"):
		return U._cache["mirror"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.86, 0.92)
	m.metallic = 0.85
	m.roughness = 0.12
	m.emission_enabled = true
	m.emission = Color(0.55, 0.62, 0.72)
	m.emission_energy_multiplier = 0.25
	U._cache["mirror"] = m
	return m


# --- Vanity mirror (1 x 1) ----------------------------------------------------------------------------------------

static func vanity_mirror(root: Node3D) -> Dictionary:
	var mesh := U.baked("vanity_mirror", func(b: Batch) -> void:
		b.rbox(Vector3(0.9, 0.06, 0.5), Vector3(0, 0.72, 0.0), Palette.WOOD_LIGHT, 0.025)
		b.rbox(Vector3(0.84, 0.16, 0.44), Vector3(0, 0.61, 0.0), Palette.WOOD, 0.02)
		b.rbox(Vector3(0.3, 0.1, 0.02), Vector3(0, 0.61, 0.225), Palette.WOOD_LIGHT, 0.01)
		b.sphere(0.022, Vector3(0, 0.61, 0.24), BRASS)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.cyl(0.028, 0.02, 0.54, Vector3(0.38 * sx, 0.27, 0.18 * sz), Palette.WOOD_DARK, Vector3.ZERO, 8)
		# Mirror stand and oval frame.
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.05, 0.62, 0.05), Vector3(0.3 * sx, 1.06, -0.16), Palette.WOOD_DARK, 0.015)
		b.torus(0.24, 0.3, Vector3(0, 1.3, -0.16), BRASS, Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.35))
		b.heart(0.1, Vector3(0, 1.72, -0.16), Palette.BLOSSOM, 0.03)
		# Bottles, a brush and a ribbon.
		b.cyl(0.035, 0.04, 0.1, Vector3(-0.3, 0.8, 0.08), Palette.FLOWER_PURPLE.lightened(0.2), Vector3.ZERO, 10)
		b.sphere(0.022, Vector3(-0.3, 0.86, 0.08), BRASS)
		b.cyl(0.028, 0.03, 0.14, Vector3(-0.2, 0.82, 0.12), Palette.BLOSSOM.lightened(0.1), Vector3.ZERO, 10)
		b.rbox(Vector3(0.16, 0.03, 0.05), Vector3(0.24, 0.765, 0.1), Palette.WOOD_DARK, 0.01, Vector3(0, 25, 0))
		b.rbox(Vector3(0.07, 0.035, 0.06), Vector3(0.33, 0.77, 0.14), Palette.CLOTH_CREAM, 0.01, Vector3(0, 25, 0))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var mirror := MeshInstance3D.new()
	mirror.mesh = Shapes.prim_cylinder(0.25, 0.25, 0.012, 24)
	mirror.material_override = mirror_mat()
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mirror)
	mirror.position = Vector3(0, 1.3, -0.15)
	mirror.rotation_degrees = Vector3(90, 0, 0)
	mirror.scale = Vector3(1.0, 1.0, 1.35)
	return {}


# --- Kitchen counter (2 x 1) ---------------------------------------------------------------------------------------

static func kitchen_counter(root: Node3D) -> Dictionary:
	var mesh := U.baked("kitchen_counter", func(b: Batch) -> void:
		b.rbox(Vector3(1.9, 0.82, 0.86), Vector3(0, 0.45, 0), Palette.WOOD, 0.03)
		b.rbox(Vector3(1.86, 0.06, 0.8), Vector3(0, 0.05, 0.02), Palette.WOOD_DARK, 0.0)
		b.rbox(Vector3(2.0, 0.08, 0.94), Vector3(0, 0.9, 0), Palette.STONE.lightened(0.08), 0.02)
		# Left: a little iron oven with two burners and a kettle.
		b.rbox(Vector3(0.78, 0.6, 0.04), Vector3(-0.48, 0.46, 0.43), Palette.STONE_DARK.darkened(0.25), 0.02)
		b.rbox(Vector3(0.5, 0.3, 0.02), Vector3(-0.48, 0.46, 0.45), Palette.COPPER.darkened(0.3), 0.01)
		b.cyl(0.02, 0.02, 0.4, Vector3(-0.48, 0.68, 0.48), BRASS, Vector3(0, 0, 90), 8)
		for x in [-0.7, -0.3]:
			b.cyl(0.16, 0.16, 0.02, Vector3(x, 0.95, 0.05), Palette.STONE_DARK.darkened(0.35), Vector3.ZERO, 16)
		b.cyl(0.1, 0.12, 0.15, Vector3(-0.7, 1.03, 0.05), Palette.TEAL, Vector3.ZERO, 14)
		b.sphere(0.03, Vector3(-0.7, 1.13, 0.05), Palette.TEAL.darkened(0.2))
		b.cyl(0.02, 0.02, 0.12, Vector3(-0.6, 1.05, 0.05), Palette.TEAL, Vector3(0, 0, -60), 6)
		# Right: cupboard doors, a cutting board with a pumpkin, jars at the back.
		for x in [0.25, 0.7]:
			b.rbox(Vector3(0.4, 0.62, 0.03), Vector3(x, 0.46, 0.43), Palette.WOOD_LIGHT, 0.015)
			b.sphere(0.025, Vector3(x - 0.14 if x > 0.5 else x + 0.14, 0.52, 0.455), BRASS)
		b.rbox(Vector3(0.44, 0.03, 0.3), Vector3(0.45, 0.955, 0.12), Palette.WOOD_LIGHT.lightened(0.05), 0.01, Vector3(0, -10, 0))
		for k in 6:
			var a := TAU * float(k) / 6.0
			b.sphere(0.07, Vector3(0.45 + cos(a) * 0.035, 1.02, 0.12 + sin(a) * 0.035), Palette.FOLIAGE_AUTUMN.darkened(0.03 * float(k % 2)), Vector3(0.8, 0.85, 0.8))
		b.cyl(0.012, 0.016, 0.06, Vector3(0.45, 1.1, 0.12), Palette.FOLIAGE_DARK, Vector3.ZERO, 6)
		var jar_cols := [Palette.BERRY, Palette.K_SCARF, Palette.FOLIAGE_LIGHT]
		for k in 3:
			var jx := 0.2 + 0.2 * float(k)
			b.cyl(0.05, 0.05, 0.13, Vector3(jx, 1.005, -0.3), Palette.WATER.lightened(0.35), Vector3.ZERO, 10)
			b.cyl(0.045, 0.045, 0.08, Vector3(jx, 0.99, -0.3), jar_cols[k], Vector3.ZERO, 10)
			b.cyl(0.055, 0.055, 0.025, Vector3(jx, 1.08, -0.3), Palette.CLOTH_RED if k != 1 else Palette.CLOTH_CREAM, Vector3.ZERO, 10)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Furnace (2 x 1) -------------------------------------------------------------------------------------------------

## Stone furnace with a glowing coal bed in its arched mouth (parts: "flame" = the coals, "light_pos").
static func furnace(root: Node3D) -> Dictionary:
	var mesh := U.baked("furnace", func(b: Batch) -> void:
		var stones := [Palette.STONE, Palette.STONE_DARK, Palette.STONE.lightened(0.07), Palette.STONE.darkened(0.05)]
		b.rbox(Vector3(1.3, 0.2, 0.86), Vector3(0.15, 0.1, 0), Palette.STONE_DARK, 0.04)
		for row in 4:
			var y := 0.3 + 0.22 * float(row)
			var w := 1.2 - 0.12 * float(row)
			var n := 4 - row / 2
			for k in n:
				var x := 0.15 - w * 0.5 + w * (float(k) + 0.5) / float(n) + (0.05 if row % 2 == 1 else 0.0)
				b.rbox(Vector3(w / float(n) - 0.03, 0.2, 0.8 - 0.06 * float(row)), Vector3(x, y, -0.02), stones[(row + k) % stones.size()], 0.05)
		# Arched mouth (dark) with a brass frame.
		b.rbox(Vector3(0.52, 0.34, 0.1), Vector3(0.15, 0.5, 0.36), Palette.BARK_DARK.darkened(0.3), 0.03)
		b.add(Shapes.arch_ring(0.26, 0.34, 0.12, 14), Batch.xf(Vector3(0.15, 0.62, 0.38)), BRASS)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.08, 0.3, 0.12), Vector3(0.15 + 0.3 * sx, 0.47, 0.38), BRASS, 0.02)
		# Chimney.
		b.cyl(0.16, 0.2, 0.62, Vector3(0.15, 1.45, -0.12), Palette.STONE_DARK, Vector3.ZERO, 12)
		b.torus(0.15, 0.22, Vector3(0.15, 1.76, -0.12), Palette.STONE, Vector3.ZERO, Vector3(1, 0.6, 1))
		# Bellows and a little shelf of bars on the left.
		b.rbox(Vector3(0.3, 0.06, 0.5), Vector3(-0.72, 0.62, 0.05), Palette.WOOD_DARK, 0.015)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.05, 0.62, 0.05), Vector3(-0.72 + 0.12 * sx, 0.31, 0.25), Palette.WOOD_DARK, 0.01)
		b.sphere(0.13, Vector3(-0.72, 0.74, 0.05), Palette.K_BOOTS, Vector3(1.0, 0.45, 1.5))
		b.cyl(0.02, 0.03, 0.2, Vector3(-0.72, 0.76, 0.3), BRASS, Vector3(90, 0, 0), 6)
		for k in 3:
			b.rbox(Vector3(0.18, 0.06, 0.09), Vector3(-0.72, 0.68 + 0.065 * float(k), -0.12), Palette.COPPER if k != 1 else Palette.STONE.lightened(0.15), 0.01, Vector3(0, 12.0 * float(k), 0))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var coals := U.baked("furnace_coals", func(b: Batch) -> void:
		for k in 5:
			b.sphere(0.07, Vector3(-0.14 + 0.07 * float(k), 0.37 + 0.02 * float(k % 2), 0.0), Palette.MINE_LIGHT, Vector3(1.0, 0.6, 1.0))
		b.sphere(0.12, Vector3(0, 0.44, -0.02), Color("ffcf7a"), Vector3(1.2, 0.7, 0.5))
	)
	var glow := U.instance(root, coals, Mat.glow(Color("ff9a52"), 2.4), Vector3(0.15, 0.0, 0.33))
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"flame": glow, "light_pos": Vector3(0.15, 0.55, 0.5)}


# --- Loom & dye bench (2 x 1) ------------------------------------------------------------------------------------------

static func loom(root: Node3D) -> Dictionary:
	var mesh := U.baked("loom", func(b: Batch) -> void:
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.1, 1.5, 0.1), Vector3(0.75 * sx, 0.75, -0.2), Palette.WOOD_DARK, 0.025)
			b.rbox(Vector3(0.1, 0.9, 0.1), Vector3(0.75 * sx, 0.45, 0.3), Palette.WOOD_DARK, 0.025)
			b.rbox(Vector3(0.08, 0.08, 0.6), Vector3(0.75 * sx, 0.1, 0.05), Palette.WOOD, 0.02)
			b.sphere(0.06, Vector3(0.75 * sx, 1.53, -0.2), Palette.WOOD_LIGHT)
		b.cyl(0.05, 0.05, 1.56, Vector3(0, 1.42, -0.2), Palette.WOOD, Vector3(0, 0, 90), 10)
		b.cyl(0.05, 0.05, 1.56, Vector3(0, 0.86, 0.3), Palette.WOOD, Vector3(0, 0, 90), 10)
		# Woven cloth in progress (stripes) and the warp threads above it.
		var stripes := [Palette.CLOTH_CREAM, Palette.BLOSSOM, Palette.CLOTH_CREAM, Palette.TEAL, Palette.CLOTH_CREAM, Palette.K_SCARF]
		for i in stripes.size():
			b.rbox(Vector3(1.3, 0.07, 0.02), Vector3(0, 0.9 + 0.07 * float(i), 0.1 - 0.045 * float(i)), stripes[i], 0.0, Vector3(-33, 0, 0))
		for k in 11:
			var x := -0.6 + 0.12 * float(k)
			b.cyl(0.005, 0.005, 0.52, Vector3(x, 1.18, -0.08), Palette.CLOTH_CREAM, Vector3(-33, 0, 0), 4)
		b.rbox(Vector3(1.4, 0.05, 0.04), Vector3(0, 1.12, -0.04), Palette.WOOD_LIGHT, 0.01, Vector3(-33, 0, 0))
		b.rbox(Vector3(0.36, 0.05, 0.07), Vector3(0.1, 1.0, 0.08), Palette.WOOD_LIGHT, 0.02, Vector3(-33, 0, 0))
		# Treadles and a dye shelf with three pots on the right.
		for x in [-0.2, 0.2]:
			b.rbox(Vector3(0.1, 0.03, 0.4), Vector3(x, 0.08, 0.15), Palette.WOOD, 0.01, Vector3(12, 0, 0))
		b.rbox(Vector3(0.28, 0.04, 0.3), Vector3(0.88, 0.62, 0.05), Palette.WOOD, 0.01)
		var dyes := [Palette.BERRY, Palette.FLOWER_PURPLE, Palette.K_SCARF]
		for k in 3:
			b.cyl(0.05, 0.045, 0.09, Vector3(0.88, 0.685, -0.05 + 0.1 * float(k)), Palette.STONE, Vector3.ZERO, 10)
			b.cyl(0.042, 0.042, 0.01, Vector3(0.88, 0.73, -0.05 + 0.1 * float(k)), dyes[k], Vector3.ZERO, 10)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Companion bed and perch (1 x 1) ------------------------------------------------------------------------------------

static func companion_bed(root: Node3D) -> Dictionary:
	var mesh := U.baked("companion_bed", func(b: Batch) -> void:
		b.cyl(0.42, 0.4, 0.08, Vector3(0, 0.04, 0), Palette.WOOD, Vector3.ZERO, 20)
		b.torus(0.24, 0.44, Vector3(0, 0.16, 0), Palette.CLOTH_RED, Vector3.ZERO, Vector3(1, 1.4, 1))
		b.sphere(0.3, Vector3(0, 0.13, 0), Palette.CLOTH_CREAM, Vector3(1, 0.28, 1))
		b.heart_round(0.16, Vector3(0.12, 0.25, -0.1), Palette.BLOSSOM, Vector3(-20, 0, 0))
		b.rbox(Vector3(0.28, 0.03, 0.22), Vector3(-0.1, 0.22, 0.1), Palette.K_SCARF.lightened(0.2), 0.01, Vector3(0, 20, 6))
		for k in 6:
			var a := TAU * float(k) / 6.0 + 0.3
			b.sphere(0.022, Vector3(cos(a) * 0.4, 0.25, sin(a) * 0.4), Palette.CLOTH_CREAM)
	)
	U.instance(root, mesh, U.vc_outlined(0.011))
	return {}


static func companion_perch(root: Node3D) -> Dictionary:
	var mesh := U.baked("companion_perch", func(b: Batch) -> void:
		b.blob(0.26, Vector3(0, 0.06, 0), Palette.STONE, 61, 0.2, 0.45)
		b.cyl(0.05, 0.07, 1.2, Vector3(0, 0.66, 0), Palette.BARK, Vector3.ZERO, 10)
		for side in [[0.28, 0.72, 35.0], [-0.26, 0.98, -35.0]]:
			var x: float = side[0]
			var y: float = side[1]
			b.cyl(0.03, 0.035, 0.42, Vector3(x * 0.5, y, 0), Palette.BARK, Vector3(0, 0, -float(side[2]) * 1.6), 8)
			b.cyl(0.028, 0.028, 0.28, Vector3(x, y + 0.08, 0), Palette.WOOD_DARK, Vector3(90, 0, 0), 8)
			b.sphere(0.07, Vector3(x * 1.2, y + 0.14, 0.05), Palette.FOLIAGE, Vector3(1.2, 0.7, 1.0))
		# Little platform with a cushion and a leafy crown on top.
		b.cyl(0.24, 0.22, 0.05, Vector3(0, 1.28, 0), Palette.WOOD, Vector3.ZERO, 16)
		b.sphere(0.2, Vector3(0, 1.32, 0), Palette.BLOSSOM, Vector3(1, 0.3, 1))
		for k in 5:
			var a := TAU * float(k) / 5.0
			b.sphere(0.07, Vector3(cos(a) * 0.23, 1.27, sin(a) * 0.23), Palette.FOLIAGE_LIGHT if k % 2 == 0 else Palette.FOLIAGE, Vector3(1.2, 0.6, 1.2))
		b.cyl(0.004, 0.004, 0.16, Vector3(0.3, 0.88, 0), Palette.CLOTH_CREAM, Vector3.ZERO, 4)
		b.sphere(0.035, Vector3(0.3, 0.79, 0), BRASS)
	)
	U.instance(root, mesh, U.vc_outlined(0.011))
	return {}


# --- Cottage bench (2 x 1) --------------------------------------------------------------------------------------------

static func cottage_bench(root: Node3D) -> Dictionary:
	var mesh := U.baked("cottage_bench", func(b: Batch) -> void:
		for x in [-0.4, 0.4]:
			b.rbox(Vector3(0.8, 0.07, 0.42), Vector3(x, 0.44, 0.06), Palette.WOOD_LIGHT, 0.025)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.08, 0.44, 0.08), Vector3(0.82 * sx, 0.22, 0.22), Palette.WOOD_DARK, 0.02)
			b.rbox(Vector3(0.08, 0.86, 0.08), Vector3(0.82 * sx, 0.43, -0.16), Palette.WOOD_DARK, 0.02)
			b.rbox(Vector3(0.08, 0.06, 0.46), Vector3(0.86 * sx, 0.64, 0.04), Palette.WOOD, 0.02)
			b.rbox(Vector3(0.06, 0.2, 0.06), Vector3(0.86 * sx, 0.54, 0.24), Palette.WOOD_DARK, 0.015)
		for y in [0.62, 0.8]:
			b.rbox(Vector3(1.66, 0.1, 0.04), Vector3(0, y, -0.17), Palette.WOOD, 0.015)
		b.heart(0.16, Vector3(0, 0.71, -0.14), Palette.CLOTH_RED, 0.03)
		b.rbox(Vector3(1.56, 0.06, 0.08), Vector3(0, 0.12, 0.06), Palette.WOOD_DARK, 0.015)
		b.rbox(Vector3(0.6, 0.06, 0.36), Vector3(-0.42, 0.5, 0.06), Palette.BLOSSOM, 0.03)
		b.sphere(0.13, Vector3(0.5, 0.58, -0.08), Palette.K_SCARF, Vector3(1, 0.85, 0.5), Vector3(-15, 0, 0))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Music box (1 x 1) ---------------------------------------------------------------------------------------------------

## A little music box on a round side table; "spinner" is the tiny star dancer that turns while it plays.
static func music_box(root: Node3D) -> Dictionary:
	var mesh := U.baked("music_box", func(b: Batch) -> void:
		b.cyl(0.26, 0.26, 0.04, Vector3(0, 0.36, 0), Palette.WOOD_LIGHT, Vector3.ZERO, 18)
		b.cyl(0.04, 0.06, 0.34, Vector3(0, 0.17, 0), Palette.WOOD, Vector3.ZERO, 10)
		b.cyl(0.14, 0.16, 0.03, Vector3(0, 0.015, 0), Palette.WOOD_DARK, Vector3.ZERO, 14)
		b.rbox(Vector3(0.3, 0.13, 0.22), Vector3(0, 0.445, 0.02), Palette.CLOTH_RED, 0.02)
		b.rbox(Vector3(0.31, 0.02, 0.23), Vector3(0, 0.5, 0.02), BRASS, 0.005)
		b.rbox(Vector3(0.3, 0.02, 0.2), Vector3(0, 0.6, -0.1), Palette.CLOTH_RED, 0.01, Vector3(-80, 0, 0))
		b.heart(0.07, Vector3(0, 0.45, 0.135), BRASS, 0.01)
		b.cyl(0.01, 0.01, 0.08, Vector3(0.19, 0.44, 0.02), BRASS, Vector3(0, 0, 90), 6)
		b.sphere(0.02, Vector3(0.23, 0.46, 0.02), BRASS)
		b.cyl(0.035, 0.035, 0.012, Vector3(0, 0.512, 0.02), Palette.CLOTH_CREAM, Vector3.ZERO, 12)
	)
	U.instance(root, mesh, U.vc_outlined(0.01))
	var spinner := U.pivot(root, Vector3(0, 0.52, 0.02), "Spinner")
	var dancer := U.baked("music_box_dancer", func(b: Batch) -> void:
		b.cyl(0.006, 0.006, 0.03, Vector3(0, 0.015, 0), BRASS, Vector3.ZERO, 5)
		b.add(Shapes.star(0.045), Batch.xf(Vector3(0, 0.07, 0)), Palette.FLOWER_YELLOW)
		b.add(Shapes.star(0.045), Batch.xf(Vector3(0, 0.07, 0), Vector3(0, 180, 0)), Palette.FLOWER_YELLOW)
	)
	U.instance(spinner, dancer, U.vc_mat({"emission": Palette.FLOWER_YELLOW, "emission_energy": 0.4}))
	return {"spinner": spinner}


# --- Expedition board (2 x 1) ---------------------------------------------------------------------------------------------

static func expedition_board(root: Node3D) -> Dictionary:
	var mesh := U.baked("expedition_board", func(b: Batch) -> void:
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.1, 2.0, 0.1), Vector3(0.84 * sx, 1.0, 0), Palette.WOOD_DARK, 0.025)
			b.blob(0.12, Vector3(0.84 * sx, 0.03, 0), Palette.STONE, 70 + int(sx), 0.2, 0.5)
		b.rbox(Vector3(1.6, 1.0, 0.06), Vector3(0, 1.36, 0.02), Palette.DIRT, 0.02)
		for y in [0.84, 1.88]:
			b.rbox(Vector3(1.7, 0.07, 0.1), Vector3(0, y, 0.02), Palette.WOOD, 0.02)
		b.prism(Vector3(1.9, 0.26, 0.34), Vector3(0, 2.05, 0.02), Palette.THATCH.darkened(0.08))
		# A pinned map with a route, notes and ribbons between pins.
		b.rbox(Vector3(0.62, 0.46, 0.012), Vector3(-0.35, 1.4, 0.058), Palette.CLOTH_CREAM, 0.004, Vector3(0, 0, 3))
		b.rbox(Vector3(0.5, 0.012, 0.014), Vector3(-0.37, 1.38, 0.066), Palette.FOLIAGE, 0.0, Vector3(0, 0, 18))
		b.rbox(Vector3(0.3, 0.012, 0.014), Vector3(-0.3, 1.5, 0.066), Palette.WATER_DEEP, 0.0, Vector3(0, 0, -25))
		var notes := [[Vector2(0.28, 1.6), 0.24, Palette.K_SCARF.lightened(0.35)], [Vector2(0.45, 1.2), 0.2, Palette.CLOTH_CREAM], [Vector2(0.12, 1.1), 0.18, Palette.BLOSSOM.lightened(0.2)]]
		for n in notes:
			var p: Vector2 = n[0]
			var s: float = n[1]
			b.rbox(Vector3(s, s * 0.8, 0.01), Vector3(p.x, p.y, 0.058), n[2], 0.003, Vector3(0, 0, float(int(p.x * 100.0) % 7 - 3)))
		var pins := [Vector2(-0.5, 1.55), Vector2(-0.2, 1.3), Vector2(0.28, 1.72), Vector2(0.45, 1.28), Vector2(0.12, 1.16)]
		for i in pins.size():
			var pp: Vector2 = pins[i]
			b.sphere(0.022, Vector3(pp.x, pp.y, 0.075), [Palette.CLOTH_RED, Palette.TEAL, Palette.K_SCARF][i % 3])
			if i > 0:
				var q: Vector2 = pins[i - 1]
				var d := pp - q
				b.rbox(Vector3(d.length(), 0.008, 0.006), Vector3((pp.x + q.x) * 0.5, (pp.y + q.y) * 0.5, 0.07), Palette.CLOTH_RED, 0.0, Vector3(0, 0, rad_to_deg(atan2(d.y, d.x))))
		b.add(Shapes.star(0.06), Batch.xf(Vector3(0.62, 1.7, 0.07)), Palette.FLOWER_YELLOW)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Lanternwake table (2 x 1) ----------------------------------------------------------------------------------------------

## The festival table: cloth runner, a small pumpkin, a platter and two candle lanterns (parts "flame", "light_pos").
static func lanternwake_table(root: Node3D) -> Dictionary:
	var mesh := U.baked("lanternwake_table", func(b: Batch) -> void:
		b.rbox(Vector3(1.9, 0.07, 0.86), Vector3(0, 0.74, 0), Palette.WOOD_LIGHT, 0.025)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.rbox(Vector3(0.08, 0.7, 0.08), Vector3(0.84 * sx, 0.35, 0.34 * sz), Palette.WOOD_DARK, 0.02)
		b.rbox(Vector3(1.94, 0.012, 0.4), Vector3(0, 0.781, 0), Palette.CLOTH_CREAM, 0.004)
		b.rbox(Vector3(1.95, 0.014, 0.06), Vector3(0, 0.783, 0), Palette.FOLIAGE_AUTUMN, 0.003)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.012, 0.2, 0.4), Vector3(0.975 * sx, 0.68, 0), Palette.CLOTH_CREAM, 0.003)
		# Centre: a little pumpkin and a platter of treats.
		for k in 6:
			var a := TAU * float(k) / 6.0
			b.sphere(0.08, Vector3(cos(a) * 0.045, 0.85, sin(a) * 0.045), Palette.FOLIAGE_AUTUMN, Vector3(0.8, 0.8, 0.8))
		b.cyl(0.014, 0.018, 0.07, Vector3(0, 0.93, 0), Palette.FOLIAGE_DARK, Vector3.ZERO, 6)
		b.cyl(0.18, 0.16, 0.03, Vector3(0.45, 0.8, 0.12), Palette.CLOTH_CREAM.darkened(0.05), Vector3.ZERO, 16)
		for k in 5:
			var a2 := TAU * float(k) / 5.0
			b.sphere(0.04, Vector3(0.45 + cos(a2) * 0.09, 0.835, 0.12 + sin(a2) * 0.09), [Palette.BERRY, Palette.K_SCARF, Palette.WOOD_LIGHT][k % 3], Vector3(1, 0.7, 1))
		b.cyl(0.05, 0.045, 0.1, Vector3(-0.45, 0.83, 0.18), Palette.TEAL, Vector3.ZERO, 10)
		b.cyl(0.05, 0.045, 0.1, Vector3(-0.3, 0.83, -0.2), Palette.CLOTH_RED, Vector3.ZERO, 10)
		# Two candle lanterns (brass frames; the flames glow separately).
		for x in [-0.72, 0.72]:
			b.cyl(0.06, 0.07, 0.02, Vector3(x, 0.8, -0.1), BRASS, Vector3.ZERO, 10)
			for c in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				b.rbox(Vector3(0.014, 0.16, 0.014), Vector3(x + c.x * 0.045, 0.89, -0.1 + c.y * 0.045), BRASS, 0.004)
			b.cyl(0.02, 0.07, 0.05, Vector3(x, 0.99, -0.1), BRASS, Vector3.ZERO, 10)
			b.cyl(0.018, 0.018, 0.06, Vector3(x, 0.84, -0.1), Palette.CLOTH_CREAM, Vector3.ZERO, 6)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var flames := U.baked("lanternwake_flames", func(b: Batch) -> void:
		for x in [-0.72, 0.72]:
			b.sphere(0.022, Vector3(x, 0.0, -0.1), Palette.LANTERN_GLOW, Vector3(0.8, 1.3, 0.8))
	)
	var fl := U.instance(root, flames, Mat.glow(Palette.LANTERN_GLOW, 2.6), Vector3(0, 0.9, 0))
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"flame": fl, "light_pos": Vector3(0, 1.05, 0)}
