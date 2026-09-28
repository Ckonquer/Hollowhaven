extends RefCounted
## Room 7 of the Hushed Works: the Pocket Conservatory, the miners' underground garden and the hub. A big,
## warm room (10 m) around a shaft of real daylight falling onto a round planter; raised beds, ferns,
## glowcaps, a little pond, benches and lamps. Doors: west (the junction stair), north (the drainage stair
## home and the sluice gallery), south (the bellmaker's floor and the light well), east (the lower ward
## door, fixed at (40, -18, 0)). Three conduits along the walls carry the lines to the ward door.
## Interactive pieces (checkpoint, record, shortcut grate + lever, exit, ward door, workbench, notes,
## resources) are placed by the area script.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const WP := preload("res://src/world/works/works_props.gd")
const Geo := preload("res://src/world/works/works_geo.gd")

const FLOOR := Color("6a6152")
const WALL := Color("7a7164")
const CEIL := Color("4a443c")
const MOSS := Color("6f9a55")
const LEAF := Color("5f9a4a")
const LEAF_LIGHT := Color("8cc063")
const SOIL := Color("5a4030")
const SHAFT := Vector3(29.0, -18.0, 0.0)
const SHAFT_HALF := 3.0
const TOP_Y := 4.0


static func build(b: Builder, area: Node3D) -> void:
	_refuge(b, area)
	_refuge_stair(b, area)


static func _refuge(b: Builder, area: Node3D) -> void:
	var n := b.begin("refuge")
	var y := -18.0
	var r: Dictionary = b.rooms["refuge"]
	var cy := y + float(r["h"])
	b.shell("refuge", FLOOR, WALL, CEIL, {"no_ceiling": true})
	# Ceiling with the daylight shaft opening (6 x 6 m) and the shaft itself up to the surface.
	var sx0 := SHAFT.x - SHAFT_HALF
	var sx1 := SHAFT.x + SHAFT_HALF
	var sz0 := SHAFT.z - SHAFT_HALF
	var sz1 := SHAFT.z + SHAFT_HALF
	b.ceiling_rect(18.0, 40.0, -13.0, sz0, cy, CEIL)
	b.ceiling_rect(18.0, 40.0, sz1, 13.0, cy, CEIL)
	b.ceiling_rect(18.0, sx0, sz0, sz1, cy, CEIL)
	b.ceiling_rect(sx1, 40.0, sz0, sz1, cy, CEIL)
	var sh := TOP_Y - cy
	for w in [[Vector3(sx0 - 0.4, cy + sh * 0.5, SHAFT.z), Vector3(0.8, sh, SHAFT_HALF * 2.0 + 1.6)],
			[Vector3(sx1 + 0.4, cy + sh * 0.5, SHAFT.z), Vector3(0.8, sh, SHAFT_HALF * 2.0 + 1.6)],
			[Vector3(SHAFT.x, cy + sh * 0.5, sz0 - 0.4), Vector3(SHAFT_HALF * 2.0, sh, 0.8)],
			[Vector3(SHAFT.x, cy + sh * 0.5, sz1 + 0.4), Vector3(SHAFT_HALF * 2.0, sh, 0.8)]]:
		b.solid(w[0], w[1], WALL.darkened(0.1))
	b.solid(Vector3(SHAFT.x, TOP_Y + 0.3, SHAFT.z), Vector3(SHAFT_HALF * 2.0 + 1.6, 0.6, SHAFT_HALF * 2.0 + 1.6), CEIL)
	var sky := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SHAFT_HALF * 2.0 - 0.2, SHAFT_HALF * 2.0 - 0.2)
	sky.mesh = pm
	sky.material_override = Mat.glow(Color("fff0cf"), 1.7)
	sky.rotation_degrees.x = 180.0
	n.add_child(sky)
	sky.position = Vector3(SHAFT.x, TOP_Y - 0.02, SHAFT.z)
	var sun := SpotLight3D.new()
	sun.name = "ShaftLight"
	sun.light_color = Color("ffe8c0")
	sun.light_energy = 2.6
	sun.spot_range = 26.0
	sun.spot_angle = 17.0
	sun.spot_attenuation = 0.45
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 1.6
	area.add_child(sun)          # a direct child of the area: the Works' "sun" (flow tools look for one there)
	sun.position = Vector3(SHAFT.x, TOP_Y - 0.4, SHAFT.z)
	sun.rotation_degrees = Vector3(-90, 0, 0)
	# vines trailing down the shaft rim
	for i in 14:
		var a := TAU * float(i) / 14.0
		var p := Vector3(SHAFT.x + cos(a) * (SHAFT_HALF - 0.2), cy - 0.2, SHAFT.z + sin(a) * (SHAFT_HALF - 0.2))
		var ln := b.rng.randf_range(1.2, 3.4)
		b.vcyl(p - Vector3.UP * ln * 0.5, 0.035, ln, b.vary(LEAF, 0.1), Basis.IDENTITY, {"segments": 5, "shadows": false})
		for k in 3:
			b.vsphere(p - Vector3.UP * (ln * (0.3 + 0.3 * float(k))), Vector3(0.14, 0.09, 0.14), b.vary(LEAF_LIGHT, 0.12), Basis(Vector3.UP, b.rng.randf() * TAU), {"shadows": false})
	# Floor: warm flags, a mossy lawn under the shaft, a stone ring path.
	WP.flag_floor(b, 18.2, 39.8, -12.8, 12.8, y, Color("766c5c"), 1.7)
	b.vcyl(Vector3(SHAFT.x, y + 0.03, SHAFT.z), 4.6, 0.04, b.vary(MOSS, 0.05), Basis.IDENTITY, {"segments": 28, "shadows": false})
	b.vcyl(Vector3(SHAFT.x, y + 0.035, SHAFT.z), 3.3, 0.05, Color("8d8270"), Basis.IDENTITY, {"segments": 28, "shadows": false})
	# The round planter under the daylight: a small tree, ferns and flowers (collides as one cylinder).
	var pc := Vector3(SHAFT.x, y, SHAFT.z)
	b.vcyl(pc + Vector3.UP * 0.28, 2.6, 0.56, b.vary(WP.STONE_PALE, 0.04), Basis.IDENTITY, {"segments": 24})
	b.vcyl(pc + Vector3.UP * 0.57, 2.35, 0.04, SOIL, Basis.IDENTITY, {"segments": 24, "shadows": false})
	b.col_cyl(pc + Vector3.UP * 0.4, 2.6, 0.8)
	b.vcyl(pc + Vector3.UP * 1.6, 0.18, 2.2, Palette.BARK, Basis.IDENTITY, {"segments": 8})
	for k in 5:
		var off := Vector3(b.rng.randf_range(-0.7, 0.7), 3.0 + b.rng.randf_range(0.0, 0.8), b.rng.randf_range(-0.7, 0.7))
		b.vblob(pc + off, Vector3(1.0, 0.8, 1.0) * b.rng.randf_range(0.8, 1.2), b.vary(Color("7fb55a"), 0.1))
	_ferns_and_flowers(b, pc, 0.9, 2.2, y + 0.58, 22)
	# Raised beds along the walls (colliding) with ferns, flowers and glowing moonflowers.
	for bed in [[Vector3(24.0, y, 12.2), Vector3(3.2, 0.5, 1.3)], [Vector3(29.8, y, 12.2), Vector3(3.6, 0.5, 1.3)],
			[Vector3(37.8, y, -12.1), Vector3(3.4, 0.5, 1.4)],
			[Vector3(18.8, y, 4.8), Vector3(1.2, 0.5, 3.0)]]:
		var c: Vector3 = bed[0]
		var s: Vector3 = bed[1]
		b.solid(c + Vector3.UP * s.y * 0.5, s, b.vary(WP.TIMBER, 0.06), "wood", Basis.IDENTITY, {"outline": true, "outline_w": 0.014, "no_occluder": true})
		b.vbox(c + Vector3.UP * (s.y + 0.01), Vector3(s.x - 0.2, 0.03, s.z - 0.2), SOIL, Basis.IDENTITY, {"shadows": false})
		_ferns_and_flowers(b, c, 0.0, minf(s.x, s.z) * 0.45, y + s.y, int(s.x * s.z * 3.0))
	Props.glowcaps(b, n, Vector3(19.0, y, -9.0), 6, 0.4, 0.4)
	Props.glowcaps(b, n, Vector3(39.2, y, 10.8), 5, 0.3)
	# A little pond (visual) with stepping stones, benches, a tea table: rest and preparation.
	b.vcyl(Vector3(25.5, y + 0.02, 8.6), 1.7, 0.03, Color("3d6a70"), Basis.IDENTITY, {"segments": 20, "shadows": false})
	b.batch(Builder.unit_cyl(20), Mat.transparent(Color(0.45, 0.75, 0.8, 0.55), false), Transform3D(Basis.IDENTITY.scaled(Vector3(3.2, 0.02, 3.2)), Vector3(25.5, y + 0.06, 8.6)), Color.WHITE, false)
	for k in 7:
		var a := TAU * float(k) / 7.0
		b.vblob(Vector3(25.5 + cos(a) * 1.85, y + 0.08, 8.6 + sin(a) * 1.85), Vector3(0.3, 0.14, 0.26), b.vary(WP.STONE_PALE, 0.08), -1, Basis.IDENTITY, {"small": true})
	WP.bench(b, Vector3(28.6, y, 9.9), 2.6, "x")
	WP.bench(b, Vector3(34.0, y, -9.4), 2.6, "x")
	# Conduits: the three lines run along the walls to the ward door (visual; they glow as each line wakes -
	# the glowing overlay is a node owned by the area, see hushed_works_world.gd _build_conduits).
	WP.pipe(b, Vector3(30.8, y + 3.2, -12.7), Vector3(39.6, y + 3.2, -12.7), 0.12, WP.STEEL)
	WP.pipe(b, Vector3(39.6, y + 3.2, -12.7), Vector3(39.6, y + 3.2, -2.2), 0.12, WP.STEEL)
	WP.pipe(b, Vector3(22.6, y + 3.2, 12.7), Vector3(39.6, y + 3.2, 12.7), 0.12, WP.BRONZE)
	WP.pipe(b, Vector3(39.6, y + 3.2, 12.7), Vector3(39.6, y + 3.2, 2.2), 0.12, WP.BRONZE)
	WP.pipe(b, Vector3(36.6, y + 3.6, 12.6), Vector3(36.6, y + 3.6, 13.0), 0.1, WP.BRASS, false)
	# Signs above the doorways (symbols, readable without colour)
	WP.symbol_sign(b, Vector3(28.75, y + 4.0, -12.95), Vector3(0, 0, 1), "water", Color.WHITE, 0.7)
	WP.symbol_sign(b, Vector3(20.75, y + 4.0, 12.95), Vector3(0, 0, -1), "bell", Color.WHITE, 0.7)
	WP.symbol_sign(b, Vector3(34.75, y + 4.0, 12.95), Vector3(0, 0, -1), "light", Color.WHITE, 0.7)
	WP.symbol_sign(b, Vector3(21.25, y + 4.0, -12.95), Vector3(0, 0, 1), "up", Color.WHITE, 0.7)
	# Warm lamps (the safe room): hanging lanterns with pools of light on the flags.
	for p in [Vector3(22.2, y + 7.0, -6.2), Vector3(36.0, y + 7.0, -6.0), Vector3(22.2, y + 7.0, 6.4), Vector3(36.2, y + 7.0, 6.6)]:
		WP.chain(b, p + Vector3.UP * 3.0, 3.0)
		Props.lamp(n, p, {"style": "hanging", "hang": 0.1, "energy": 1.3, "range": 8.5, "color": WP.WARM_LAMP, "idle": 0.03})
		WP.glow_pool(b, Vector3(p.x, y, p.z), 2.2)
	Props.glow_light(n, Vector3(29.0, y + 2.5, 0.0), Color("fff0c8"), 0.8, 9.0)


## Ferns (cones), flowers (small tinted spheres) and a few glowing moonflowers on a round / square patch.
static func _ferns_and_flowers(b: Builder, c: Vector3, r0: float, r1: float, top_y: float, count: int) -> void:
	var cols := [Color("f2a7c0"), Color("f6d25a"), Color("b48ad8"), Color("fff4e0"), Color("e9a15b")]
	for i in count:
		var a := b.rng.randf() * TAU
		var d := b.rng.randf_range(r0, r1)
		var p := Vector3(c.x + cos(a) * d, top_y, c.z + sin(a) * d)
		match i % 4:
			0, 1:
				var h := b.rng.randf_range(0.3, 0.6)
				b.vcone(p + Vector3.UP * h * 0.5, b.rng.randf_range(0.14, 0.24), h, b.vary(LEAF, 0.12), Basis(Vector3.UP, b.rng.randf() * TAU), {"shadows": false})
			2:
				b.vsphere(p + Vector3.UP * 0.18, Vector3(0.11, 0.09, 0.11), b.pick(cols), Basis.IDENTITY, {"shadows": false})
				b.vcyl(p + Vector3.UP * 0.08, 0.015, 0.16, LEAF, Basis.IDENTITY, {"segments": 4, "shadows": false})
			3:
				b.vglow(Builder.unit_sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3(0.09, 0.07, 0.09)), p + Vector3.UP * 0.2), Color("dff4ff"), 1.8)
				b.vcyl(p + Vector3.UP * 0.09, 0.015, 0.18, LEAF, Basis.IDENTITY, {"segments": 4, "shadows": false})


static func _refuge_stair(b: Builder, area: Node3D) -> void:
	var n := b.begin("refuge_stair")
	Geo.sloped_passage(b, "refuge_stair", FLOOR, WALL, CEIL, Color("9a8f7c"), 0.2)
	# The drainage stair: a round hatch in the ceiling at the top with a little daylight behind it.
	var top := Vector3(21.25, -15.0, -17.4)
	b.vcyl(top + Vector3.UP * 3.35, 0.9, 0.12, WP.IRON_DARK, Basis.IDENTITY, {"segments": 16})
	var sky := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.2, 1.2)
	sky.mesh = pm
	sky.material_override = Mat.glow(Color("ffe6c0"), 1.2)
	sky.rotation_degrees.x = 180.0
	n.add_child(sky)
	sky.position = top + Vector3.UP * 3.25
	for i in 6:
		b.vbox(Vector3(21.25, -15.0 + 0.5 + float(i) * 0.45, -17.85), Vector3(0.7, 0.06, 0.08), Props.PLANK, Basis.IDENTITY, {"shadows": false})
	for s in [-0.35, 0.35]:
		b.vbox(Vector3(21.25 + s, -15.0 + 1.6, -17.85), Vector3(0.08, 3.1, 0.08), Props.TIMBER, Basis.IDENTITY, WP.OUT)
	Props.glow_light(n, top + Vector3.UP * 2.6, Color("ffe6c0"), 0.8, 5.0)
