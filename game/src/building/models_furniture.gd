extends RefCounted
## Storybook furniture models: workbench, storage chest, cozy bed, round table, stool, braided rug.
## Local frame: footprint centred on the origin, ground at y = 0, the "front" faces +Z at rotation 0.
## Each builder adds children under `root` and returns named parts for animation.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Batch := preload("res://src/building/batch.gd")

static var BRASS: Color = U.keep(Palette.K_SCARF.lerp(Palette.COPPER, 0.35).darkened(0.04))   # never dyed
static var VICE: Color = Palette.TEAL.darkened(0.22)


# --- Workbench (2 x 1) ------------------------------------------------------------------------------

static func workbench(root: Node3D) -> Dictionary:
	var mesh := U.baked("workbench", func(b: Batch) -> void:
		# Top planks
		var tops := [Palette.WOOD_LIGHT, Palette.WOOD_LIGHT.darkened(0.07), Palette.WOOD_LIGHT.lightened(0.03)]
		for i in 3:
			b.rbox(Vector3(1.92, 0.09, 0.27), Vector3(0, 0.845, -0.29 + i * 0.29), tops[i], 0.03)
		# Legs, stretchers and shelf
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.rbox(Vector3(0.14, 0.8, 0.14), Vector3(0.82 * sx, 0.4, 0.31 * sz), Palette.WOOD, 0.035)
			b.rbox(Vector3(0.07, 0.07, 0.56), Vector3(0.82 * sx, 0.2, 0), Palette.WOOD_DARK, 0.02)
		b.rbox(Vector3(1.66, 0.05, 0.6), Vector3(0, 0.25, 0), Palette.WOOD, 0.02)
		# Logs and a stone on the shelf
		b.cyl(0.075, 0.075, 0.52, Vector3(-0.42, 0.35, -0.12), Palette.BARK, Vector3(0, 0, 90))
		b.cyl(0.075, 0.075, 0.52, Vector3(-0.42, 0.35, 0.05), Palette.BARK.lightened(0.06), Vector3(0, 0, 90))
		b.cyl(0.075, 0.075, 0.52, Vector3(-0.42, 0.48, -0.035), Palette.BARK.darkened(0.05), Vector3(0, 0, 90))
		for zz in [-0.12, 0.05]:
			b.cyl(0.06, 0.06, 0.005, Vector3(-0.162, 0.35, zz), Palette.WOOD_LIGHT, Vector3(0, 0, 90))
		b.blob(0.13, Vector3(0.45, 0.33, 0.02), Palette.STONE, 11, 0.25, 0.7)
		b.blob(0.09, Vector3(0.66, 0.31, -0.1), Palette.STONE_DARK, 4, 0.25, 0.7)
		# Back board with hanging tools
		b.rbox(Vector3(1.86, 0.52, 0.06), Vector3(0, 1.15, -0.43), Palette.WOOD, 0.025)
		b.rbox(Vector3(1.9, 0.07, 0.08), Vector3(0, 1.43, -0.43), Palette.WOOD_DARK, 0.02)
		for px in [-0.55, 0.2, 0.7]:
			b.cyl(0.018, 0.018, 0.08, Vector3(px, 1.3, -0.37), Palette.WOOD_DARK, Vector3(90, 0, 0))
		# Hammer
		b.cyl(0.022, 0.022, 0.34, Vector3(-0.55, 1.1, -0.36), Palette.WOOD_DARK)
		b.rbox(Vector3(0.18, 0.08, 0.08), Vector3(-0.55, 1.28, -0.36), Palette.STONE_DARK, 0.02)
		# Saw
		b.rbox(Vector3(0.36, 0.13, 0.015), Vector3(0.14, 1.19, -0.365), Palette.STONE.lightened(0.15), 0.006)
		b.rbox(Vector3(0.11, 0.13, 0.05), Vector3(0.36, 1.19, -0.365), Palette.CLOTH_RED, 0.02)
		# Coil of rope
		b.torus(0.06, 0.1, Vector3(0.7, 1.2, -0.37), Palette.THATCH, Vector3(90, 0, 0))
		# Vice (front right)
		b.rbox(Vector3(0.24, 0.1, 0.22), Vector3(0.72, 0.935, 0.28), VICE, 0.025)
		b.rbox(Vector3(0.24, 0.13, 0.06), Vector3(0.72, 1.05, 0.2), VICE, 0.02)
		b.rbox(Vector3(0.24, 0.13, 0.06), Vector3(0.72, 1.05, 0.4), VICE, 0.02)
		b.rbox(Vector3(0.22, 0.03, 0.02), Vector3(0.72, 1.105, 0.235), Palette.STONE_DARK, 0.005)
		b.rbox(Vector3(0.22, 0.03, 0.02), Vector3(0.72, 1.105, 0.365), Palette.STONE_DARK, 0.005)
		b.cyl(0.02, 0.02, 0.2, Vector3(0.72, 1.02, 0.52), Palette.STONE_DARK, Vector3(90, 0, 0))
		b.cyl(0.012, 0.012, 0.3, Vector3(0.72, 1.02, 0.61), Palette.STONE_DARK, Vector3(0, 0, 90))
		b.sphere(0.028, Vector3(0.57, 1.02, 0.61), BRASS)
		b.sphere(0.028, Vector3(0.87, 1.02, 0.61), BRASS)
		# A wood block being shaped, curly shavings and a pencil
		b.rbox(Vector3(0.32, 0.1, 0.15), Vector3(-0.12, 0.94, 0.1), Palette.WOOD_LIGHT.lightened(0.08), 0.02, Vector3(0, 12, 0))
		for i in 4:
			b.torus(0.012, 0.03, Vector3(0.1 + i * 0.05, 0.9, 0.18 - i * 0.03), Palette.WOOD_LIGHT.lightened(0.15), Vector3(90 * (i % 2), i * 40, 30))
		b.cyl(0.012, 0.012, 0.18, Vector3(0.3, 0.905, -0.05), Palette.FLOWER_YELLOW, Vector3(0, 30, 90))
		b.cyl(0.0, 0.012, 0.03, Vector3(0.378, 0.905, -0.095), Palette.WOOD_LIGHT, Vector3(0, 30, -90))
	)
	U.instance(root, mesh, U.vc_outlined(0.013))
	return {}


# --- Storage chest (1 x 1) ------------------------------------------------------------------------------

static func storage_chest(root: Node3D) -> Dictionary:
	var body := U.baked("chest_body", func(b: Batch) -> void:
		b.rbox(Vector3(0.86, 0.46, 0.6), Vector3(0, 0.29, 0), Palette.WOOD, 0.045)
		for y in [0.2, 0.38]:
			b.rbox(Vector3(0.872, 0.018, 0.612), Vector3(0, y, 0), Palette.WOOD_DARK, 0.006)
		for x in [-0.3, 0.3]:
			b.rbox(Vector3(0.075, 0.48, 0.625), Vector3(x, 0.29, 0), BRASS, 0.02)
			b.sphere(0.018, Vector3(x, 0.44, 0.314), BRASS.lightened(0.2))
			b.sphere(0.018, Vector3(x, 0.14, 0.314), BRASS.lightened(0.2))
		b.rbox(Vector3(0.88, 0.06, 0.62), Vector3(0, 0.085, 0), Palette.WOOD_DARK, 0.02)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.sphere(0.07, Vector3(0.36 * sx, 0.05, 0.23 * sz), Palette.WOOD_DARK, Vector3(1, 0.7, 1))
		# Lock plate & keyhole
		b.rbox(Vector3(0.15, 0.15, 0.03), Vector3(0, 0.44, 0.31), BRASS, 0.02)
		b.rbox(Vector3(0.026, 0.055, 0.012), Vector3(0, 0.43, 0.327), Palette.BARK_DARK, 0.005)
		# Dark inside (visible when the lid opens) and a glint of treasure
		b.rbox(Vector3(0.74, 0.02, 0.48), Vector3(0, 0.515, 0), Palette.BARK_DARK, 0.005)
		b.cyl(0.05, 0.05, 0.02, Vector3(-0.12, 0.53, 0.05), BRASS.lightened(0.25), Vector3(8, 0, 0))
		b.cyl(0.05, 0.05, 0.02, Vector3(-0.04, 0.54, -0.02), BRASS.lightened(0.25), Vector3(-6, 0, 10))
		b.sphere(0.05, Vector3(0.14, 0.55, 0.02), Palette.WATER.lightened(0.2))
	)
	U.instance(root, body, U.vc_outlined(0.012))
	# Lid on a hinge pivot at the back top edge.
	var hinge := U.pivot(root, Vector3(0, 0.52, -0.3), "LidHinge")
	var lid := U.baked("chest_lid", func(b: Batch) -> void:
		b.add(Shapes.half_cylinder(14), Batch.xf(Vector3(0, 0.02, 0.3), Vector3.ZERO, Vector3(0.88, 0.2, 0.31)), Palette.WOOD)
		b.rbox(Vector3(0.9, 0.05, 0.63), Vector3(0, 0.0, 0.3), Palette.WOOD_DARK, 0.02)
		for x in [-0.3, 0.3]:
			b.add(Shapes.half_cylinder(14), Batch.xf(Vector3(x, 0.02, 0.3), Vector3.ZERO, Vector3(0.078, 0.215, 0.325)), BRASS)
		b.rbox(Vector3(0.1, 0.13, 0.03), Vector3(0, -0.03, 0.622), BRASS, 0.02)
	)
	U.instance(hinge, lid, U.vc_outlined(0.012))
	return {"lid": hinge}


# --- Cozy bed (1 x 2) -------------------------------------------------------------------------------------

static func bed(root: Node3D) -> Dictionary:
	var mesh := U.baked("bed", func(b: Batch) -> void:
		# Frame
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.08, 0.16, 1.86), Vector3(0.46 * sx, 0.25, 0), Palette.WOOD, 0.025)
			b.cyl(0.055, 0.06, 1.0, Vector3(0.46 * sx, 0.5, -0.94), Palette.WOOD_DARK)
			b.sphere(0.08, Vector3(0.46 * sx, 1.03, -0.94), Palette.WOOD_LIGHT)
			b.cyl(0.055, 0.06, 0.62, Vector3(0.46 * sx, 0.31, 0.94), Palette.WOOD_DARK)
			b.sphere(0.075, Vector3(0.46 * sx, 0.65, 0.94), Palette.WOOD_LIGHT)
		# Headboard with an arched top and a carved heart
		b.rbox(Vector3(0.86, 0.52, 0.07), Vector3(0, 0.6, -0.94), Palette.WOOD_LIGHT, 0.025)
		b.add(Shapes.half_cylinder(16), Batch.xf(Vector3(0, 0.86, -0.94), Vector3(0, 90, 0), Vector3(0.07, 0.17, 0.43)), Palette.WOOD_LIGHT)
		b.heart(0.2, Vector3(0, 0.74, -0.895), Palette.CLOTH_RED, 0.03)
		# Footboard
		b.rbox(Vector3(0.86, 0.3, 0.07), Vector3(0, 0.43, 0.94), Palette.WOOD_LIGHT, 0.025)
		# Mattress, pillow, sheet
		b.rbox(Vector3(0.84, 0.16, 1.8), Vector3(0, 0.38, 0), Palette.CLOTH_CREAM, 0.06)
		b.sphere(0.5, Vector3(0, 0.52, -0.66), Palette.FLOWER_WHITE, Vector3(0.64, 0.2, 0.34))
		b.rbox(Vector3(0.9, 0.09, 0.15), Vector3(0, 0.49, -0.33), Palette.FLOWER_WHITE, 0.04)
		# Quilt with patchwork squares, draping over the sides
		b.rbox(Vector3(0.9, 0.08, 1.2), Vector3(0, 0.48, 0.28), Palette.CLOTH_RED, 0.035)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.03, 0.22, 1.2), Vector3(0.455 * sx, 0.39, 0.28), Palette.CLOTH_RED, 0.012)
		var patch_cols := [U.keep(Palette.BLOSSOM), U.keep(Palette.CLOTH_CREAM), U.keep(Palette.K_SCARF.lightened(0.3)), U.keep(Palette.CLOTH_RED.lightened(0.15))]
		for i in 3:
			for j in 4:
				b.rbox(Vector3(0.25, 0.012, 0.25), Vector3(-0.28 + i * 0.28, 0.524, -0.15 + j * 0.29), patch_cols[(i + j * 2) % 4], 0.004)
	)
	U.instance(root, mesh, U.vc_outlined(0.013))
	return {}


# --- Round table (1 x 1) -------------------------------------------------------------------------------

static func table(root: Node3D) -> Dictionary:
	var mesh := U.baked("table", func(b: Batch) -> void:
		b.cyl(0.46, 0.46, 0.07, Vector3(0, 0.76, 0), Palette.WOOD_LIGHT, Vector3.ZERO, 24)
		b.torus(0.43, 0.49, Vector3(0, 0.755, 0), Palette.WOOD, Vector3.ZERO, Vector3(1, 0.55, 1))
		b.cyl(0.07, 0.09, 0.7, Vector3(0, 0.37, 0), Palette.WOOD)
		for i in 3:
			var a := TAU * float(i) / 3.0
			b.rbox(Vector3(0.36, 0.07, 0.09), Vector3(cos(a) * 0.15, 0.04, sin(a) * 0.15), Palette.WOOD_DARK, 0.03, Vector3(0, -rad_to_deg(a), 0))
		# Doily, a mug of tea and a little book
		b.cyl(0.24, 0.24, 0.006, Vector3(0, 0.797, 0), Palette.FLOWER_WHITE, Vector3.ZERO, 20)
		b.cyl(0.05, 0.045, 0.1, Vector3(0.09, 0.85, 0.06), Palette.TEAL)
		b.cyl(0.043, 0.043, 0.004, Vector3(0.09, 0.897, 0.06), Palette.BARK)
		b.torus(0.018, 0.034, Vector3(0.145, 0.855, 0.06), Palette.TEAL, Vector3(90, 0, 0))
		b.rbox(Vector3(0.17, 0.04, 0.22), Vector3(-0.13, 0.822, -0.06), Palette.CLOTH_RED, 0.012, Vector3(0, 22, 0))
		b.rbox(Vector3(0.155, 0.03, 0.205), Vector3(-0.125, 0.823, -0.06), Palette.CLOTH_CREAM, 0.008, Vector3(0, 22, 0))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Stool (1 x 1) -----------------------------------------------------------------------------------------

static func stool(root: Node3D) -> Dictionary:
	var mesh := U.baked("stool", func(b: Batch) -> void:
		for i in 3:
			var a := TAU * float(i) / 3.0 + 0.5
			var p := Vector3(cos(a) * 0.14, 0.21, sin(a) * 0.14)
			var tilt := Vector3(sin(a) * -10.0, 0, cos(a) * 10.0)
			b.cyl(0.03, 0.036, 0.44, p, Palette.WOOD_DARK, tilt)
		b.cyl(0.25, 0.24, 0.07, Vector3(0, 0.44, 0), Palette.WOOD, Vector3.ZERO, 20)
		b.sphere(0.22, Vector3(0, 0.5, 0), Palette.BLOSSOM, Vector3(1.0, 0.32, 1.0))
		b.sphere(0.022, Vector3(0, 0.567, 0), Palette.CLOTH_RED)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


# --- Woven rug (2 x 2) ------------------------------------------------------------------------------------

## A berry-dyed woven rug: cream border band, a stitched heart with little leaves in the middle, mustard
## corner diamonds and tassel fringes on the short ends. (Concentric rings read as an archery target.)
static func rug(root: Node3D) -> Dictionary:
	var mesh := U.baked("rug", func(b: Batch) -> void:
		var L := 1.62       # length along X (without fringe)
		var W := 1.3        # width along Z
		# Base cloth and the inner field (slightly deeper berry), stacked a hair apart to avoid z-fighting.
		b.rbox(Vector3(L, 0.024, W), Vector3(0, 0.012, 0), Palette.CLOTH_RED, 0.012)
		b.rbox(Vector3(L - 0.36, 0.006, W - 0.36), Vector3(0, 0.026, 0), Palette.BERRY.lightened(0.04), 0.003)
		# Cream border band with a thin blossom stitch line inside it
		for sz in [-1.0, 1.0]:
			b.rbox(Vector3(L - 0.16, 0.006, 0.06), Vector3(0, 0.027, (W * 0.5 - 0.11) * sz), Palette.CLOTH_CREAM, 0.003)
			b.rbox(Vector3(L - 0.36, 0.005, 0.022), Vector3(0, 0.029, (W * 0.5 - 0.2) * sz), Palette.BLOSSOM, 0.002)
		for sx in [-1.0, 1.0]:
			b.rbox(Vector3(0.06, 0.006, W - 0.16), Vector3((L * 0.5 - 0.11) * sx, 0.027, 0), Palette.CLOTH_CREAM, 0.003)
			b.rbox(Vector3(0.022, 0.005, W - 0.36), Vector3((L * 0.5 - 0.2) * sx, 0.029, 0), Palette.BLOSSOM, 0.002)
		# Mustard diamonds in the field corners and small cream dots along the long sides
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.rbox(Vector3(0.09, 0.006, 0.09), Vector3(0.5 * sx, 0.03, 0.34 * sz), Palette.K_SCARF, 0.003, Vector3(0, 45, 0))
			for k in 3:
				b.sphere(0.018, Vector3((-0.2 + 0.2 * k), 0.03, 0.4 * sx), Palette.CLOTH_CREAM, Vector3(1, 0.3, 1))
		# Heart motif lying flat (top of the heart toward -Z) with two leaves
		b.heart(0.34, Vector3(0, 0.031, 0.02), Palette.CLOTH_CREAM, 0.008, Vector3(-90, 0, 0))
		b.heart(0.25, Vector3(0, 0.035, 0.015), Palette.BLOSSOM, 0.008, Vector3(-90, 0, 0))
		for sx in [-1.0, 1.0]:
			b.sphere(0.5, Vector3(0.25 * sx, 0.031, 0.1), Palette.FOLIAGE, Vector3(0.15, 0.012, 0.075), Vector3(0, -35.0 * sx, 0))
		# Tassel fringe on the short ends
		for sx in [-1.0, 1.0]:
			for k in 9:
				var z := -W * 0.5 + 0.1 + (W - 0.2) * float(k) / 8.0
				b.rbox(Vector3(0.11, 0.008, 0.028), Vector3((L * 0.5 + 0.045) * sx, 0.006, z), Palette.CLOTH_CREAM.darkened(0.04), 0.003)
	)
	U.instance(root, mesh, U.vc_mat())
	return {}
