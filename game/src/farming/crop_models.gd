extends RefCounted
## Crop plot visuals: a log-framed bed of tilled soil with three mounded rows, plus one merged mesh per
## growth stage (sprout, leaves, bushy, ripe with orange roots). Plants are drawn with one
## MultiMeshInstance3D per plot (9 plants = 1 draw call) and sway with the toon shader's wind.

const Palette := preload("res://src/art/palette.gd")
const U := preload("res://src/building/model_util.gd")
const Batch := preload("res://src/building/batch.gd")
const Shapes := preload("res://src/building/shapes.gd")

const ROWS := [-0.55, 0.0, 0.55]
const COLS := [-0.55, 0.0, 0.55]
const SOIL_TOP := 0.18

static var ROOT_ORANGE: Color = Color("f29a4a")     # matches the sweetroot item colour
static var SOIL: Color = Palette.DIRT_DARK.darkened(0.12)


static func plot(root: Node3D) -> Dictionary:
	var mesh := U.baked("crop_plot", func(b: Batch) -> void:
		for sz in [-1.0, 1.0]:
			b.rbox(Vector3(2.0, 0.17, 0.13), Vector3(0, 0.085, 0.935 * sz), Palette.WOOD, 0.05)
			b.rbox(Vector3(0.13, 0.17, 1.74), Vector3(0.935 * sz, 0.085, 0), Palette.WOOD.darkened(0.05), 0.05)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				b.cyl(0.07, 0.08, 0.26, Vector3(0.94 * sx, 0.13, 0.94 * sz), Palette.WOOD_DARK, Vector3.ZERO, 8)
				b.sphere(0.07, Vector3(0.94 * sx, 0.26, 0.94 * sz), Palette.WOOD_LIGHT, Vector3(1, 0.5, 1))
		b.rbox(Vector3(1.78, 0.12, 1.78), Vector3(0, 0.07, 0), Palette.DIRT_DARK, 0.03)
		for z in ROWS:
			b.rbox(Vector3(1.62, 0.1, 0.34), Vector3(0, 0.13, z), SOIL, 0.05)
		# tiny pebbles in the soil
		for p in [Vector3(-0.7, 0.14, -0.28), Vector3(0.62, 0.14, 0.27), Vector3(0.2, 0.14, -0.3)]:
			b.sphere(0.025, p, Palette.STONE, Vector3(1.2, 0.6, 1))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	return {}


## Plant positions (local to the plot).
static func plant_positions() -> Array:
	var out: Array = []
	for z in ROWS:
		for x in COLS:
			out.append(Vector3(float(x), SOIL_TOP, float(z)))
	return out


## Merged mesh of one plant at a growth stage (0 sprout .. 3 ripe).
static func stage_mesh(stage: int) -> ArrayMesh:
	return U.baked("crop_stage_%d" % stage, func(b: Batch) -> void:
		match stage:
			0:
				b.cyl(0.012, 0.016, 0.08, Vector3(0, 0.04, 0), Palette.FOLIAGE, Vector3.ZERO, 6)
				b.sphere(0.5, Vector3(-0.035, 0.085, 0), Palette.FOLIAGE_LIGHT, Vector3(0.07, 0.018, 0.04), Vector3(0, 0, 25))
				b.sphere(0.5, Vector3(0.035, 0.085, 0), Palette.FOLIAGE_LIGHT, Vector3(0.07, 0.018, 0.04), Vector3(0, 0, -25))
			1:
				_fronds(b, 4, 0.17, Palette.FOLIAGE_LIGHT, 0.0)
			2:
				b.sphere(0.045, Vector3(0, 0.0, 0), ROOT_ORANGE.darkened(0.1), Vector3(1, 0.6, 1))
				_fronds(b, 6, 0.24, Palette.FOLIAGE, 0.3)
				_fronds(b, 3, 0.17, Palette.FOLIAGE_LIGHT, 1.1)
			_:
				b.sphere(0.1, Vector3(0, 0.01, 0), ROOT_ORANGE, Vector3(1, 0.85, 1))
				b.sphere(0.035, Vector3(0.06, 0.02, 0.05), ROOT_ORANGE.lightened(0.1))
				for k in 3:
					var a := TAU * float(k) / 3.0
					b.cyl(0.003, 0.003, 0.03, Vector3(cos(a) * 0.08, 0.03, sin(a) * 0.08), ROOT_ORANGE.darkened(0.25), Vector3(0, 0, 90), 4)
				_fronds(b, 7, 0.3, Palette.FOLIAGE, 0.2)
				_fronds(b, 4, 0.22, Palette.FOLIAGE_LIGHT, 0.9)
	)


## Feathery upright leaves arranged in a rosette, each blade leaning outward and facing out.
static func _fronds(b: Batch, count: int, height: float, color: Color, phase: float) -> void:
	for i in count:
		var a := TAU * float(i) / float(count) + phase
		var tilt := deg_to_rad(22.0 + 10.0 * float(i % 2))
		var dir := Vector3(cos(a), 0, sin(a))
		var up := (dir * sin(tilt) + Vector3.UP * cos(tilt)).normalized()
		var side := Vector3(-sin(a), 0, cos(a))
		var face := side.cross(up).normalized()
		var blade := Basis(side * 0.07, up * height, face * 0.028)
		var centre := up * height * 0.5 + dir * 0.02
		var col: Color = color if i % 3 != 0 else color.darkened(0.08)
		b.add(Shapes.prim_sphere(0.5, 5, 8), Transform3D(blade, centre), col)
		var stem := Basis(side, up, face)
		b.add(Shapes.prim_cylinder(0.006, 0.009, height * 0.5, 4), Transform3D(stem, up * height * 0.25), color.darkened(0.2))


static func plant_material() -> Material:
	return U.vc_mat({"wind": 0.035, "wind_height": 0.3, "wind_speed": 1.7})
