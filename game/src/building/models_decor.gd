extends RefCounted
## Decorations: lantern post, flower pot, pebble cairn, echo chime, heartbloom lamp, haven banner.
## Animated / glowing parts are returned by name so the structure scripts can bring them to life.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const U := preload("res://src/building/model_util.gd")
const Shapes := preload("res://src/building/shapes.gd")
const Batch := preload("res://src/building/batch.gd")

const HEADING_FONT := "res://assets/fonts/Fredoka-Variable.ttf"

static var BRASS: Color = Palette.K_SCARF.lerp(Palette.COPPER, 0.35).darkened(0.04)
static var SHARD: Color = Color("b9a3f0")      # matches the echo_shard item colour
static var SHINY: Color = Color("9fd3e6")      # matches the shiny_pebble item colour


# --- Lantern post -----------------------------------------------------------------------------------------

static func lantern_post(root: Node3D) -> Dictionary:
	var mesh := U.baked("lantern_post", func(b: Batch) -> void:
		b.blob(0.24, Vector3(0, 0.07, 0), Palette.STONE, 3, 0.22, 0.5)
		b.blob(0.1, Vector3(0.2, 0.03, 0.12), Palette.STONE_DARK, 8, 0.25, 0.6)
		b.rbox(Vector3(0.13, 2.05, 0.13), Vector3(0, 1.08, 0), Palette.WOOD_DARK, 0.035)
		b.rbox(Vector3(0.56, 0.08, 0.08), Vector3(0.22, 2.02, 0), Palette.WOOD_DARK, 0.025)
		b.rbox(Vector3(0.32, 0.055, 0.055), Vector3(0.13, 1.86, 0), Palette.WOOD_DARK, 0.02, Vector3(0, 0, 45))
		b.sphere(0.06, Vector3(0, 2.13, 0), BRASS)
		# Hook and lantern cage
		b.torus(0.02, 0.04, Vector3(0.42, 1.95, 0), BRASS, Vector3(90, 0, 0))
		b.cyl(0.03, 0.15, 0.1, Vector3(0.42, 1.86, 0), BRASS)
		b.cyl(0.12, 0.12, 0.03, Vector3(0.42, 1.8, 0), Palette.WOOD_DARK)
		for c in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			b.rbox(Vector3(0.025, 0.24, 0.025), Vector3(0.42 + c.x * 0.085, 1.67, c.y * 0.085), Palette.WOOD_DARK, 0.008)
		b.cyl(0.12, 0.1, 0.04, Vector3(0.42, 1.54, 0), Palette.WOOD_DARK)
		b.sphere(0.025, Vector3(0.42, 1.505, 0), BRASS)
		# A little red ribbon bow on the post
		b.prism(Vector3(0.12, 0.09, 0.03), Vector3(-0.06, 1.42, 0.075), Palette.CLOTH_RED, Vector3(0, 0, 90))
		b.prism(Vector3(0.12, 0.09, 0.03), Vector3(0.06, 1.42, 0.075), Palette.CLOTH_RED, Vector3(0, 0, -90))
		b.sphere(0.03, Vector3(0, 1.42, 0.085), Palette.CLOTH_RED.darkened(0.1))
		b.rbox(Vector3(0.03, 0.12, 0.02), Vector3(-0.025, 1.34, 0.08), Palette.CLOTH_RED, 0.008, Vector3(0, 0, -12))
		b.rbox(Vector3(0.03, 0.12, 0.02), Vector3(0.025, 1.34, 0.08), Palette.CLOTH_RED, 0.008, Vector3(0, 0, 12))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var flame := MeshInstance3D.new()
	flame.mesh = Shapes.prim_sphere(0.075)
	flame.material_override = Mat.glow(Palette.LANTERN_GLOW, 3.0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)
	flame.position = Vector3(0.42, 1.66, 0)
	flame.scale = Vector3(1, 1.25, 1)
	return {"flame": flame, "light_pos": Vector3(0.42, 1.62, 0)}


# --- Flower pot ---------------------------------------------------------------------------------------------

static func flower_pot(root: Node3D) -> Dictionary:
	var pot := U.baked("flower_pot", func(b: Batch) -> void:
		b.cyl(0.25, 0.19, 0.34, Vector3(0, 0.17, 0), Palette.STONE, Vector3.ZERO, 18)
		b.torus(0.22, 0.3, Vector3(0, 0.34, 0), Palette.STONE.lightened(0.06), Vector3.ZERO, Vector3(1, 0.8, 1))
		b.cyl(0.235, 0.235, 0.02, Vector3(0, 0.345, 0), Palette.DIRT_DARK, Vector3.ZERO, 18)
		b.sphere(0.03, Vector3(0.12, 0.2, 0.2), Palette.MOSS, Vector3(1.6, 1, 0.6))
	)
	U.instance(root, pot, U.vc_outlined(0.012))
	var flowers := U.baked("flower_pot_flowers", func(b: Batch) -> void:
		var cols := [Palette.BLOSSOM, Palette.FLOWER_RED, Palette.FLOWER_BLUE, Palette.FLOWER_PURPLE, Palette.FLOWER_YELLOW]
		for i in 5:
			var a := TAU * float(i) / 5.0 + 0.3
			var lean: float = 0.09 if i != 4 else 0.0
			var hgt := 0.34 + 0.09 * float((i * 7) % 3)
			var top := Vector3(cos(a) * lean * 1.6, hgt, sin(a) * lean * 1.6)
			b.cyl(0.011, 0.014, hgt, top * 0.5, Palette.FOLIAGE_DARK, Vector3(rad_to_deg(top.z * 1.4), 0, -rad_to_deg(top.x * 1.4)), 6)
			for k in 5:
				var pa := TAU * float(k) / 5.0
				b.sphere(0.05, top + Vector3(cos(pa) * 0.06, 0.0, sin(pa) * 0.06), cols[i], Vector3(1, 0.42, 1))
			b.sphere(0.034, top + Vector3(0, 0.016, 0), Palette.FLOWER_YELLOW if i != 4 else Palette.FLOWER_WHITE)
		for k in 4:
			var la := TAU * float(k) / 4.0 + 0.8
			b.sphere(0.5, Vector3(cos(la) * 0.1, 0.05, sin(la) * 0.1), Palette.FOLIAGE, Vector3(0.1, 0.03, 0.18), Vector3(-25, -rad_to_deg(la) + 90, 0))
	)
	U.instance(root, flowers, U.vc_outlined(0.008, {"wind": 0.03, "wind_height": 0.4, "wind_speed": 1.6}), Vector3(0, 0.35, 0))
	return {}


# --- Pebble cairn ------------------------------------------------------------------------------------------

static func pebble_cairn(root: Node3D) -> Dictionary:
	var mesh := U.baked("pebble_cairn", func(b: Batch) -> void:
		b.blob(0.3, Vector3(0, 0.03, 0), Palette.MOSS, 21, 0.25, 0.18)
		b.blob(0.21, Vector3(0, 0.12, 0), Palette.STONE_DARK, 5, 0.18, 0.55)
		b.blob(0.165, Vector3(0.025, 0.3, -0.01), Palette.STONE, 9, 0.18, 0.6)
		b.blob(0.125, Vector3(-0.015, 0.45, 0.01), Palette.STONE.lightened(0.08), 13, 0.18, 0.62)
		for p in [Vector3(0.24, 0.04, 0.12), Vector3(-0.22, 0.04, 0.16), Vector3(0.1, 0.035, -0.25)]:
			b.blob(0.07, p, Palette.STONE, int(p.x * 100.0) + 40, 0.25, 0.6)
		b.sphere(0.035, Vector3(-0.2, 0.06, -0.12), Palette.FLOWER_WHITE)
		b.sphere(0.03, Vector3(-0.17, 0.05, -0.2), Palette.FLOWER_YELLOW)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var pebble := MeshInstance3D.new()
	pebble.mesh = Shapes.prim_sphere(0.085)
	pebble.material_override = Mat.outlined(Mat.toon(SHINY, {"specular": 0.7, "rim": 0.7, "emission": SHINY, "emission_energy": 0.25}), 0.012)
	root.add_child(pebble)
	pebble.position = Vector3(0, 0.57, 0)
	pebble.scale = Vector3(1.0, 0.85, 1.0)
	return {"pebble": pebble}


# --- Echo chime ------------------------------------------------------------------------------------------------

static func echo_chime(root: Node3D) -> Dictionary:
	var mesh := U.baked("echo_chime", func(b: Batch) -> void:
		b.blob(0.2, Vector3(0, 0.06, 0), Palette.STONE, 17, 0.2, 0.5)
		b.rbox(Vector3(0.1, 1.95, 0.1), Vector3(0, 1.0, 0), Palette.WOOD_DARK, 0.03)
		b.rbox(Vector3(0.58, 0.08, 0.08), Vector3(0.22, 1.94, 0), Palette.WOOD_DARK, 0.025)
		b.sphere(0.05, Vector3(0.52, 1.94, 0), Palette.WOOD_LIGHT)
		b.cyl(0.006, 0.006, 0.26, Vector3(0.42, 1.8, 0), Palette.CLOTH_CREAM, Vector3.ZERO, 5)
		b.torus(0.13, 0.17, Vector3(0.42, 1.66, 0), BRASS)
		b.cyl(0.004, 0.004, 0.16, Vector3(0.42, 1.58, 0), Palette.CLOTH_CREAM, Vector3.ZERO, 4)
		b.sphere(0.03, Vector3(0.42, 1.49, 0), BRASS)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var shard_mesh := U.baked("echo_shard", func(b: Batch) -> void:
		b.cyl(0.004, 0.004, 0.12, Vector3(0, -0.06, 0), Palette.CLOTH_CREAM, Vector3.ZERO, 4)
		b.cyl(0.02, 0.045, 0.06, Vector3(0, -0.15, 0), SHARD.lightened(0.15), Vector3.ZERO, 5)
		b.cyl(0.045, 0.0, 0.19, Vector3(0, -0.275, 0), SHARD, Vector3.ZERO, 5)
	)
	var mat := Mat.toon_unique(Color.WHITE, {"vertex_color": true, "rim": 0.8, "emission": SHARD, "emission_energy": 0.35})
	var shards: Array = []
	for i in 5:
		var a := TAU * float(i) / 5.0
		var pv := U.pivot(root, Vector3(0.42 + cos(a) * 0.15, 1.66, sin(a) * 0.15), "Shard%d" % i)
		U.instance(pv, shard_mesh, mat).scale = Vector3.ONE * (0.85 + 0.1 * float(i % 3))
		shards.append(pv)
	return {"shards": shards, "shard_mat": mat}


# --- Heartbloom lamp -----------------------------------------------------------------------------------------

static func heartbloom_lamp(root: Node3D) -> Dictionary:
	var head := Vector3(-0.02, 1.34, 0.08)
	var mesh := U.baked("heartbloom_lamp", func(b: Batch) -> void:
		b.blob(0.27, Vector3(0, 0.08, 0), Palette.STONE, 27, 0.2, 0.45)
		b.blob(0.22, Vector3(0, 0.16, 0), Palette.MOSS, 33, 0.3, 0.35)
		# Smooth, gently curving stem (quadratic curve, joints hidden by spheres)
		var p0 := Vector3(0, 0.18, 0)
		var p1 := Vector3(0.16, 0.8, -0.04)
		var p2 := head - Vector3(0, 0.04, 0)
		var prev := p0
		var segs := 8
		for i in range(1, segs + 1):
			var t := float(i) / float(segs)
			var q := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
			_segment(b, prev, q, 0.032 - 0.008 * t, Palette.FOLIAGE_DARK)
			prev = q
		# Leaves
		_leaf(b, Vector3(0.1, 0.5, 0.0), 0.3, 0.28, Palette.FOLIAGE, 55.0)
		_leaf(b, Vector3(0.12, 0.86, -0.02), 3.3, 0.24, Palette.FOLIAGE_LIGHT, 50.0)
		_leaf(b, Vector3(0.05, 1.1, 0.04), 1.2, 0.18, Palette.FOLIAGE, 60.0)
		# Cupped bloom: outer and inner petal rings around the glowing heart
		b.sphere(0.07, head, Palette.FOLIAGE_DARK, Vector3(1, 0.6, 1))
		for k in 5:
			var a := TAU * float(k) / 5.0
			_petal(b, head, a, deg_to_rad(62.0), 0.24, 0.12, Palette.BLOSSOM)
			_petal(b, head, a + TAU / 10.0, deg_to_rad(38.0), 0.2, 0.1, Palette.BLOSSOM.lightened(0.18))
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var bulb_pivot := U.pivot(root, head + Vector3(0, 0.16, 0), "Bulb")
	var bulb := U.baked("heartbloom_bulb", func(b: Batch) -> void:
		b.heart_round(0.24, Vector3.ZERO, Palette.HEART_GLOW)
	)
	var bmi := U.instance(bulb_pivot, bulb, Mat.glow(Palette.HEART_GLOW, 2.2))
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return {"bulb": bulb_pivot, "light_pos": head + Vector3(0, 0.2, 0.04)}


## Cylinder from a to b (for stems).
static func _segment(b: Batch, a: Vector3, c: Vector3, radius: float, color: Color) -> void:
	var d := c - a
	var up := d.normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := side.cross(up).normalized()
	b.add(Shapes.prim_cylinder(radius, radius * 1.1, d.length(), 8), Transform3D(Basis(side, up, fwd), (a + c) * 0.5), color)
	b.sphere(radius * 1.05, c, color)


## Petal leaning out from `centre` toward angle a (tilt from vertical), cupped around the bloom.
static func _petal(b: Batch, centre: Vector3, a: float, tilt: float, length: float, width: float, color: Color) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	var up := (dir * sin(tilt) + Vector3.UP * cos(tilt)).normalized()
	var side := Vector3(-sin(a), 0, cos(a))
	var face := side.cross(up).normalized()
	b.add(Shapes.prim_sphere(0.5, 6, 10), Transform3D(Basis(side * width, up * length, face * 0.035), centre + up * length * 0.42 + dir * 0.03), color)


## Leaf sprouting from the stem at `at`, pointing toward angle a.
static func _leaf(b: Batch, at: Vector3, a: float, length: float, color: Color, tilt_deg: float) -> void:
	var dir := Vector3(cos(a), 0, sin(a))
	var t := deg_to_rad(tilt_deg)
	var out := (dir * sin(t) + Vector3.UP * cos(t)).normalized()
	var side := Vector3(-sin(a), 0, cos(a))
	var face := side.cross(out).normalized()
	b.add(Shapes.prim_sphere(0.5, 6, 10), Transform3D(Basis(side * length * 0.42, out * length, face * 0.025), at + out * length * 0.45), color)


# --- Haven banner -----------------------------------------------------------------------------------------------

static func haven_banner(root: Node3D) -> Dictionary:
	var mesh := U.baked("haven_banner_pole", func(b: Batch) -> void:
		b.blob(0.26, Vector3(0, 0.07, 0), Palette.STONE, 41, 0.2, 0.45)
		b.cyl(0.045, 0.055, 2.55, Vector3(0, 1.3, 0), Palette.WOOD_DARK, Vector3.ZERO, 10)
		b.sphere(0.075, Vector3(0, 2.6, 0), BRASS)
		b.cyl(0.028, 0.028, 1.04, Vector3(0, 2.3, 0.07), Palette.WOOD_DARK, Vector3(0, 0, 90), 8)
		for sx in [-1.0, 1.0]:
			b.sphere(0.045, Vector3(0.52 * sx, 2.3, 0.07), BRASS)
		b.sphere(0.05, Vector3(0.08, 0.2, 0.14), Palette.FLOWER_WHITE)
		b.sphere(0.04, Vector3(-0.12, 0.17, 0.16), Palette.BLOSSOM)
	)
	U.instance(root, mesh, U.vc_outlined(0.012))
	var cloth_pivot := U.pivot(root, Vector3(0, 2.28, 0.08), "Cloth")
	var cloth := U.baked("haven_banner_cloth", func(b: Batch) -> void:
		b.rbox(Vector3(0.9, 1.3, 0.03), Vector3(0, -0.68, 0), Palette.TEAL, 0.012)
		for sx in [-1.0, 1.0]:
			b.prism(Vector3(0.45, 0.26, 0.03), Vector3(0.225 * sx, -1.46, 0), Palette.TEAL, Vector3(0, 0, 180))
			b.rbox(Vector3(0.045, 1.3, 0.036), Vector3(0.43 * sx, -0.68, 0), Palette.K_SCARF, 0.01)
		b.rbox(Vector3(0.9, 0.07, 0.036), Vector3(0, -0.06, 0), Palette.K_SCARF, 0.01)
		# Leaf-and-heart sigil (both faces)
		for side in [1.0, -1.0]:
			var z: float = 0.02 * side
			b.cyl(0.27, 0.27, 0.012, Vector3(0, -0.47, z), Palette.CLOTH_CREAM, Vector3(90, 0, 0), 28)
			b.torus(0.255, 0.29, Vector3(0, -0.47, z), Palette.K_SCARF, Vector3(90, 0, 0), Vector3(1, 0.3, 1))
			b.heart(0.25, Vector3(0, -0.45, z * 1.4), Palette.CLOTH_RED, 0.02)
			b.sphere(0.5, Vector3(-0.13, -0.58, z * 1.6), Palette.FOLIAGE, Vector3(0.075, 0.17, 0.02), Vector3(0, 0, 52))
			b.sphere(0.5, Vector3(0.13, -0.58, z * 1.6), Palette.FOLIAGE_LIGHT, Vector3(0.075, 0.17, 0.02), Vector3(0, 0, -52))
			b.sphere(0.03, Vector3(0, -0.66, z * 1.5), Palette.K_SCARF)
	)
	U.instance(cloth_pivot, cloth, U.vc_outlined(0.01))
	for side in [1.0, -1.0]:
		var lbl := Label3D.new()
		lbl.text = "Krystal's\nHaven"
		if ResourceLoader.exists(HEADING_FONT):
			lbl.font = load(HEADING_FONT)
		lbl.font_size = 64
		lbl.pixel_size = 0.0021
		lbl.modulate = Palette.CLOTH_CREAM
		lbl.outline_modulate = Palette.TEAL.darkened(0.55)
		lbl.outline_size = 10
		lbl.line_spacing = -8.0
		lbl.double_sided = false
		lbl.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		lbl.name = "Label%s" % ("Front" if side > 0.0 else "Back")
		cloth_pivot.add_child(lbl)
		lbl.position = Vector3(0, -1.0, 0.03 * side)
		lbl.rotation_degrees = Vector3(0, 0 if side > 0.0 else 180, 0)
	return {"cloth": cloth_pivot}
