extends RefCounted
## The Unsettling Ruins: the square-spiral Descent Stair, the Hall of Faces (+ the crossing passage of
## THE DISTANT CROSSING), the Drowned Shrine (THE IMITATION), its checkpoint alcove and the sloped
## descent into the Silk Hollows. Cold teal light, carved faces, pillars, shallow water.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")

const STONE := Color("5d7479")
const STONE_DARK := Color("3a4a52")
const TEAL := Color("7fd6d0")
const WARM_CAP := Color("ffcf8a")
const WATER_SHADER := preload("res://shaders/below_water.gdshader")


static func build(b: Builder, area: Node3D, decor: Node3D) -> void:
	_stair(b, area)
	_hall(b, area)
	_crossing(b, area, decor)
	_shrine(b, area)
	_shrine_cp(b, area)
	_descent(b, area, decor)


static func _stair(b: Builder, area: Node3D) -> void:
	var n := b.begin("stair")
	var x0: float = float(Layout.STAIR["x0"])
	var z1: float = float(Layout.STAIR["z1"])
	var s: float = float(Layout.STAIR["size"])
	var w: float = float(Layout.STAIR["w"])
	var x1 := x0 + s
	var z0 := z1 - s
	var ylo := -6.0
	var yhi := 4.0
	var cm := x0 + w          # core min x
	var cx := x1 - w          # core max x
	var cz := z0 + w          # core min z (north face)
	# Outer walls (collision + dark backing)
	b.solid(Vector3((2.0 + x1) * 0.5, (ylo + yhi) * 0.5, z1 + 0.5), Vector3(x1 - 2.0, yhi - ylo, 1.0), STONE_DARK)
	b.solid(Vector3((cm + 2.0) * 0.5, -3.0, z1 + 0.5), Vector3(2.0 - cm, 6.0, 1.0), STONE_DARK)
	b.solid(Vector3((x0 + cm) * 0.5, (ylo + 0.0) * 0.5, z1 + 0.5), Vector3(w, 6.0, 1.0), STONE_DARK)
	b.solid(Vector3((x0 + cm) * 0.5, (3.2 + yhi) * 0.5, z1 + 0.5), Vector3(w, yhi - 3.2, 1.0), STONE_DARK)
	b.solid(Vector3((x0 + x1) * 0.5, (ylo + yhi) * 0.5, z0 - 0.5), Vector3(s + 2.0, yhi - ylo, 1.0), STONE_DARK)
	b.solid(Vector3(x0 - 0.5, (ylo + yhi) * 0.5, (z0 + z1) * 0.5), Vector3(1.0, yhi - ylo, s), STONE_DARK)
	b.solid(Vector3(x1 + 0.5, (ylo + yhi) * 0.5, (z0 + (z1 - w)) * 0.5), Vector3(1.0, yhi - ylo, s - w), STONE_DARK)
	b.solid(Vector3(x1 + 0.5, (-3.0 + yhi) * 0.5, z1 - w * 0.5), Vector3(1.0, yhi + 3.0, w), STONE_DARK)
	# Central core
	b.solid(Vector3((cm + cx) * 0.5, (ylo + yhi) * 0.5, (cz + z1) * 0.5), Vector3(cx - cm, yhi - ylo, z1 - cz), STONE)
	b.ceiling_rect(x0, x1, z0, z1, yhi, STONE_DARK)
	# Landings and flights
	b.solid(Vector3((x0 + cm) * 0.5, -3.0, z1 - w * 0.5), Vector3(w, 6.0, w), STONE)                 # A (top, y 0)
	b.solid(Vector3((x0 + cm) * 0.5, -4.0, z0 + w * 0.5), Vector3(w, 4.0, w), STONE)                 # B (y -2)
	b.solid(Vector3((cx + x1) * 0.5, -5.0, z0 + w * 0.5), Vector3(w, 2.0, w), STONE)                 # C (y -4)
	b.floor_rect(cx, x1, z1 - w, z1, ylo, STONE)                                                      # D (y -6)
	var mid_a := (x0 + cm) * 0.5
	var mid_c := (cx + x1) * 0.5
	var mid_n := z0 + w * 0.5
	b.stairs(Vector3(mid_a, 0.0, z1 - w), Vector3(mid_a, -2.0, cz), w, 0.25, STONE, STONE_DARK)
	b.stairs(Vector3(cm, -2.0, mid_n), Vector3(cx, -4.0, mid_n), w, 0.25, STONE, STONE_DARK)
	b.stairs(Vector3(mid_c, -4.0, cz), Vector3(mid_c, -6.0, z1 - w), w, 0.25, STONE, STONE_DARK)
	# Carved block facing on every visible face
	Props.block_wall(b, Vector3(x0, -6.0, z1), Vector3(x0, -6.0, z0), Vector3(1, 0, 0), 10.0)
	Props.block_wall(b, Vector3(x0, -6.0, z0), Vector3(x1, -6.0, z0), Vector3(0, 0, 1), 10.0)
	Props.block_wall(b, Vector3(x1, -6.0, z0), Vector3(x1, -6.0, z1), Vector3(-1, 0, 0), 10.0, [[s - w, s, 3.0]])
	Props.block_wall(b, Vector3(cx, -6.0, z1), Vector3(x1, -6.0, z1), Vector3(0, 0, -1), 10.0)
	Props.block_wall(b, Vector3(cm, -6.0, z1), Vector3(cm, -6.0, cz), Vector3(-1, 0, 0), 10.0)
	Props.block_wall(b, Vector3(cm, -6.0, cz), Vector3(cx, -6.0, cz), Vector3(0, 0, -1), 10.0)
	Props.block_wall(b, Vector3(cx, -6.0, cz), Vector3(cx, -6.0, z1), Vector3(1, 0, 0), 10.0)
	# Faces watching the stair from the core (one has its eyes open)
	Props.carved_face(b, Vector3(cm - 0.05, 1.3, -63.0), Vector3(-1, 0, 0), 0.9, "closed")
	Props.carved_face(b, Vector3((cm + cx) * 0.5, -1.0, cz - 0.05), Vector3(0, 0, -1), 0.9, "open")
	Props.carved_face(b, Vector3(cx + 0.05, -3.2, -62.6), Vector3(1, 0, 0), 0.9, "closed")
	# Light: a miner's dropped lantern on landing B and a cold glow at the bottom
	Props.lamp(n, Vector3(x0 + 0.5, -2.0, z0 + 0.5), {"style": "floor", "energy": 0.8, "range": 5.0, "idle": 0.18, "color": Color("ffb35c")})
	Props.lamp(n, Vector3(cx + 0.55, -6.0, z1 - 0.55), {"style": "bowl", "energy": 1.1, "range": 7.0, "color": TEAL, "flame": TEAL, "idle": 0.05})
	# Hall passage (D -> Hall of Faces)
	b.begin("hall_way")
	b.shell("hall_way", STONE, STONE_DARK, STONE_DARK)
	Props.tile_floor(b, 8.7, 12.0, -60.6, -58.0, -6.0, 1.3)
	Props.block_wall(b, Vector3(8.7, -6.0, -60.6), Vector3(12.0, -6.0, -60.6), Vector3(0, 0, 1), 3.0)
	Props.block_wall(b, Vector3(8.7, -6.0, -58.0), Vector3(12.0, -6.0, -58.0), Vector3(0, 0, -1), 3.0)


static func _hall(b: Builder, area: Node3D) -> void:
	var n := b.begin("hall")
	var y := -6.0
	b.shell("hall", STONE, STONE_DARK, STONE_DARK)
	Props.tile_floor(b, 12.0, 42.0, -66.3, -52.3, y)
	var skip_w := [[5.7, 8.3, 3.0]]
	var skip_e := [[5.2, 8.8, 3.4]]
	Props.block_wall(b, Vector3(12.0, y, -66.3), Vector3(42.0, y, -66.3), Vector3(0, 0, 1), 7.0)
	Props.block_wall(b, Vector3(12.0, y, -52.3), Vector3(42.0, y, -52.3), Vector3(0, 0, -1), 7.0)
	Props.block_wall(b, Vector3(12.0, y, -66.3), Vector3(12.0, y, -52.3), Vector3(1, 0, 0), 7.0, skip_w)
	Props.block_wall(b, Vector3(42.0, y, -66.3), Vector3(42.0, y, -52.3), Vector3(-1, 0, 0), 7.0, skip_e)
	# Two rows of pillars (one broken)
	for px in [16.0, 21.0, 26.0, 31.0, 36.0]:
		for pz in [-62.8, -55.8]:
			Props.pillar(b, Vector3(px, y, pz), 0.62, 7.0, px == 31.0 and pz == -55.8)
	# Carved faces between the pillars (eyes shut... except one)
	for fx in [18.5, 23.5, 28.5, 33.5, 38.5]:
		Props.carved_face(b, Vector3(fx, y + 2.7, -66.2), Vector3(0, 0, 1), 1.0, "open" if fx == 28.5 else "closed")
		Props.carved_face(b, Vector3(fx, y + 2.7, -52.4), Vector3(0, 0, -1), 1.0, "closed")
	# The far wall: a giant face whose open mouth is the doorway.
	var fx0 := 41.95
	var stone := Palette.RUIN_STONE.lightened(0.04)
	b.vbox(Vector3(fx0 - 0.3, y + 5.6, -59.3), Vector3(0.6, 0.5, 6.2), stone)                          # brow
	for sz in [-1.0, 1.0]:
		b.vblob(Vector3(fx0 - 0.1, y + 4.9, -59.3 + sz * 1.6), Vector3(0.35, 0.55, 0.8), STONE_DARK, 2)  # eye socket rims
		b.vsphere(Vector3(fx0 - 0.25, y + 4.85, -59.3 + sz * 1.6), Vector3(0.3, 0.55, 0.95), Color(0.03, 0.04, 0.05))
		b.vblob(Vector3(fx0 - 0.3, y + 3.6, -59.3 + sz * 2.7), Vector3(0.55, 1.4, 0.8), stone, 4)          # cheeks
		b.vbox(Vector3(fx0 - 0.12, y + 1.7, -59.3 + sz * 2.15), Vector3(0.3, 3.4, 0.6), stone.darkened(0.05))  # jaw sides
	b.batch(Props._prism_mesh(), Builder.tint_mat(), Transform3D(Basis(Vector3(0, 0, 1), PI * 0.5).scaled_local(Vector3(1.4, 0.7, 0.9)), Vector3(fx0 - 0.35, y + 4.1, -59.3)), stone)   # nose
	b.vbox(Vector3(fx0 - 0.2, y + 3.55, -59.3), Vector3(0.4, 0.3, 4.6), stone.darkened(0.08))           # upper lip
	b.vbox(Vector3(fx0 - 0.05, y + 0.03, -59.3), Vector3(0.9, 0.06, 4.0), STONE_DARK, Basis.IDENTITY, {"shadows": false})  # lower lip (flat)
	# The giant face is lit from below by two bowls flanking its mouth (the far doorway).
	Props.lamp(n, Vector3(41.0, y, -62.6), {"style": "bowl", "energy": 0.9, "range": 5.5, "color": TEAL, "flame": TEAL, "idle": 0.05})
	Props.lamp(n, Vector3(41.0, y, -56.0), {"style": "bowl", "energy": 0.9, "range": 5.5, "color": TEAL, "flame": TEAL, "idle": 0.05})
	# Light: cold fire-bowls, dim. The far doorway glows from behind (set in the crossing).
	Props.lamp(n, Vector3(18.5, y, -64.9), {"style": "bowl", "energy": 1.1, "range": 7.0, "color": TEAL, "flame": TEAL, "idle": 0.05, "shadow": true})
	Props.lamp(n, Vector3(28.5, y, -53.7), {"style": "bowl", "energy": 1.0, "range": 7.0, "color": TEAL, "flame": TEAL, "idle": 0.05})
	Props.lamp(n, Vector3(38.2, y, -64.9), {"style": "bowl", "energy": 0.9, "range": 6.5, "color": TEAL, "flame": TEAL, "idle": 0.05})
	Props.glow_light(n, Vector3(27.0, y + 6.0, -59.3), Color("5fa8b0"), 0.35, 16.0)
	# Roots through ceiling cracks, moss, rubble
	for i in 10:
		var p := Vector3(b.rng.randf_range(14.0, 40.0), y + 7.0, b.rng.randf_range(-65.5, -53.0))
		for k in 3:
			b.vcyl(p + Vector3(k * 0.12, -0.6 - k * 0.2, 0), 0.03, 1.2 + k * 0.4, Palette.ROOTS, Basis(Vector3(1, 0, 0), b.rng.randf_range(-0.2, 0.2)), {"shadows": false})
	Props.rubble_pile(b, Vector3(13.2, y, -53.3), 0.9, 1.0, [STONE, STONE_DARK], 6)
	Props.rubble_pile(b, Vector3(40.8, y, -65.3), 0.8, 0.9, [STONE, STONE_DARK], 5)


static func _crossing(b: Builder, area: Node3D, decor: Node3D) -> void:
	var n := b.begin("crossing")
	var y := -6.0
	b.shell("crossing", STONE, STONE_DARK, STONE_DARK)
	Props.tile_floor(b, 42.0, 46.5, -76.0, -50.0, y, 1.5)
	Props.block_wall(b, Vector3(42.0, y, -76.0), Vector3(42.0, y, -50.0), Vector3(1, 0, 0), 4.2, [[14.9, 18.5, 3.4]])
	Props.block_wall(b, Vector3(46.5, y, -76.0), Vector3(46.5, y, -50.0), Vector3(-1, 0, 0), 4.2)
	Props.block_wall(b, Vector3(42.0, y, -50.0), Vector3(46.5, y, -50.0), Vector3(0, 0, -1), 4.2)
	# Collapsed south end with a black crack the shape slipped out of
	Props.rubble_pile(b, Vector3(44.2, y, -51.3), 2.0, 2.6, [STONE, STONE_DARK], 12)
	b.vbox(Vector3(45.6, y + 1.6, -50.05), Vector3(0.5, 2.8, 0.1), Color(0.02, 0.02, 0.03), Basis(Vector3(0, 0, 1), 0.12), {"shadows": false})
	# Drag marks along the floor, from the crack toward the shrine
	var z := -52.5
	var i := 0
	while z > -66.0:
		for sx in [-0.22, 0.22]:
			var xx: float = 44.6 + sx + sin(z * 0.7) * 0.18
			b.vbox(Vector3(xx, y + 0.075, z), Vector3(0.09, 0.012, 0.75), Color(0.13, 0.12, 0.12), Basis(Vector3.UP, sin(z) * 0.12), {"shadows": false})
		z -= 0.85
		i += 1
	# Backlight so the far doorway reads from the hall; the dropped lantern is placed by the moments.
	Props.glow_light(n, Vector3(45.4, y + 3.0, -59.3), Color("9fd8d4"), 0.9, 7.0)
	Props.lamp(n, Vector3(45.9, y, -70.5), {"style": "bowl", "energy": 0.8, "range": 6.0, "color": TEAL, "flame": TEAL, "idle": 0.05})
	# The strand across the doorway (a clue)
	decor.add_strand(Vector3(42.3, y + 3.3, -60.9), Vector3(43.4, y + 0.05, -58.4))
	decor.add_strand(Vector3(44.6, y + 4.1, -61.5), Vector3(44.3, y + 0.05, -63.0))


static func _shrine(b: Builder, area: Node3D) -> void:
	var n := b.begin("shrine")
	var y := -6.0
	var px0 := 37.0
	var px1 := 53.0
	var pz0 := -91.0
	var pz1 := -79.0
	b.shell("shrine", STONE, STONE_DARK, STONE_DARK, {"no_floor": true})
	b.floor_rect(34.0, 56.0, pz1, -76.0, y, STONE)
	b.floor_rect(34.0, 56.0, -94.0, pz0, y, STONE)
	b.floor_rect(34.0, px0, pz0, pz1, y, STONE)
	b.floor_rect(px1, 56.0, pz0, pz1, y, STONE)
	b.floor_rect(px0, px1, pz0, pz1, y, STONE_DARK.darkened(0.4), "water")
	Props.tile_floor(b, 34.0, 56.0, -94.0, -76.0, y, 2.0, [[px0, px1, pz0, pz1]])
	# Pool rim stones (flush) and the water surface
	for xx in range(int(px0), int(px1), 2):
		b.vbox(Vector3(float(xx) + 1.0, y + 0.05, pz1 + 0.15), Vector3(1.9, 0.1, 0.3), STONE.lightened(0.05), Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(float(xx) + 1.0, y + 0.05, pz0 - 0.15), Vector3(1.9, 0.1, 0.3), STONE.lightened(0.05), Basis.IDENTITY, {"shadows": false})
	for zz in range(int(pz0), int(pz1), 2):
		b.vbox(Vector3(px0 - 0.15, y + 0.05, float(zz) + 1.0), Vector3(0.3, 0.1, 1.9), STONE.lightened(0.05), Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(px1 + 0.15, y + 0.05, float(zz) + 1.0), Vector3(0.3, 0.1, 1.9), STONE.lightened(0.05), Basis.IDENTITY, {"shadows": false})
	var water := MeshInstance3D.new()
	water.name = "Water"
	var pm := PlaneMesh.new()
	pm.size = Vector2(px1 - px0, pz1 - pz0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(water)
	water.position = Vector3((px0 + px1) * 0.5, y + 0.16, (pz0 + pz1) * 0.5)
	# Walls: carved blocks, engaged pillars, faces above the water
	Props.block_wall(b, Vector3(34.0, y, -94.0), Vector3(56.0, y, -94.0), Vector3(0, 0, 1), 8.0, [[3.0, 6.5, 3.2]])
	Props.block_wall(b, Vector3(34.0, y, -76.0), Vector3(56.0, y, -76.0), Vector3(0, 0, -1), 8.0, [[8.0, 12.5, 4.2]])
	Props.block_wall(b, Vector3(34.0, y, -94.0), Vector3(34.0, y, -76.0), Vector3(1, 0, 0), 8.0)
	Props.block_wall(b, Vector3(56.0, y, -94.0), Vector3(56.0, y, -76.0), Vector3(-1, 0, 0), 8.0, [[6.5, 10.0, 3.2]])
	for p in [Vector3(34.6, y, -84.0), Vector3(55.4, y, -80.0), Vector3(55.4, y, -91.5), Vector3(47.0, y, -93.4)]:
		Props.pillar(b, p, 0.5, 8.0)
	Props.carved_face(b, Vector3(45.0, y + 5.2, -93.9), Vector3(0, 0, 1), 1.6, "closed")
	Props.carved_face(b, Vector3(34.1, y + 4.6, -88.0), Vector3(1, 0, 0), 1.2, "hollow")
	# The Ward-Keeper: a hooded statue on a plinth in the water, cupping an empty bowl
	var sp := Vector3(49.0, y, -88.4)
	var robe := STONE.lightened(0.06)
	b.vbox(sp + Vector3(0, 0.3, 0), Vector3(1.9, 0.6, 1.9), STONE_DARK)
	b.vbox(sp + Vector3(0, 0.66, 0), Vector3(1.6, 0.14, 1.6), STONE)
	b.col_box(sp + Vector3(0, 1.8, 0), Vector3(1.9, 3.6, 1.9))
	b.vcone(sp + Vector3(0, 1.75, 0), 0.72, 2.2, robe)                                    # robe
	b.vblob(sp + Vector3(0, 2.75, 0.0), Vector3(0.62, 0.34, 0.46), robe, 2)               # shoulders
	b.vblob(sp + Vector3(0, 3.22, -0.06), Vector3(0.36, 0.46, 0.4), robe, 3)              # hood
	b.vcone(sp + Vector3(0, 3.62, -0.2), 0.16, 0.36, robe, Basis(Vector3(1, 0, 0), -0.5))  # hood tip
	b.vsphere(sp + Vector3(0, 3.14, 0.22), Vector3(0.36, 0.42, 0.2), Color(0.03, 0.04, 0.05))  # the dark under the hood
	for sx in [-1.0, 1.0]:
		b.vcyl(sp + Vector3(sx * 0.32, 2.4, 0.3), 0.11, 0.62, robe, Basis(Vector3(1, 0, 0), 1.25) * Basis(Vector3(0, 0, 1), sx * 0.2))
	b.vcyl(sp + Vector3(0, 2.4, 0.66), 0.34, 0.16, STONE.lightened(0.12))                 # the empty bowl it offers
	b.vcyl(sp + Vector3(0, 2.46, 0.66), 0.27, 0.06, Color(0.08, 0.1, 0.11))
	b.vbox(sp + Vector3(0, 0.45, 0.96), Vector3(1.3, 0.3, 0.04), STONE.lightened(0.1), Basis.IDENTITY, {"shadows": false})
	# Cold light high above the water (reflections) and teal bowls by the entry.
	var cold := SpotLight3D.new()
	cold.light_color = Color("a8e0dc")
	cold.light_energy = 2.4
	cold.spot_range = 16.0
	cold.spot_angle = 38.0
	cold.shadow_enabled = true
	cold.light_volumetric_fog_energy = 0.9
	cold.distance_fade_enabled = true
	cold.distance_fade_begin = 36.0
	cold.distance_fade_length = 8.0
	n.add_child(cold)
	cold.position = Vector3(46.0, y + 7.6, -85.0)
	cold.rotation_degrees = Vector3(-90, 0, 0)
	b.vbox(Vector3(46.0, y + 8.3, -85.0), Vector3(2.2, 0.1, 0.5), Color("cfeeea"), Basis(Vector3.UP, 0.4), {"shadows": false})
	Props.lamp(n, Vector3(35.1, y, -77.0), {"style": "bowl", "energy": 1.0, "range": 7.0, "color": TEAL, "flame": TEAL, "idle": 0.05})
	Props.lamp(n, Vector3(54.9, y, -94.0 + 0.9), {"style": "bowl", "energy": 1.0, "range": 7.0, "color": TEAL, "flame": TEAL, "idle": 0.05})
	Props.lamp(n, Vector3(35.1, y, -83.0), {"style": "bowl", "energy": 0.9, "range": 6.5, "color": TEAL, "flame": TEAL, "idle": 0.05})
	Props.glow_light(n, Vector3(45.0, y + 6.0, -85.0), Color("6fb8bf"), 0.8, 18.0)
	# The right way: a warm glowcap trail from the entry along the east side to the east exit.
	var trail := [Vector3(46.8, y, -77.4), Vector3(49.3, y, -77.8), Vector3(51.8, y, -78.3), Vector3(54.3, y, -79.6), Vector3(55.2, y, -82.2), Vector3(55.3, y, -84.0)]
	for k in trail.size():
		var tp: Vector3 = trail[k]
		Props.glowcaps(b, n, tp, 5, 0.3, 0.75 if k % 2 == 0 else 0.0, 3.2, WARM_CAP)
	Props.lamp(n, Vector3(56.0, y + 2.3, -83.4), {"style": "wall", "yaw": -90.0, "energy": 1.1, "range": 6.0, "color": Color("ffb35c")})
	# Wrong way: short, dark, and it simply ends in a collapse.
	b.begin("wrong_way")
	b.shell("wrong_way", STONE, STONE_DARK, STONE_DARK)
	Props.tile_floor(b, 37.0, 40.5, -100.0, -94.0, y, 1.75)
	Props.block_wall(b, Vector3(37.0, y, -100.0), Vector3(37.0, y, -94.0), Vector3(1, 0, 0), 3.2)
	Props.block_wall(b, Vector3(40.5, y, -100.0), Vector3(40.5, y, -94.0), Vector3(-1, 0, 0), 3.2)
	Props.rubble_pile(b, Vector3(38.75, y, -99.2), 1.5, 2.6, [STONE, STONE_DARK], 10, false)


static func _shrine_cp(b: Builder, area: Node3D) -> void:
	var n := b.begin("shrine_cp")
	var y := -6.0
	b.shell("shrine_cp", STONE, STONE_DARK, STONE_DARK)
	Props.tile_floor(b, 56.0, 64.0, -89.5, -82.0, y, 1.6)
	Props.block_wall(b, Vector3(56.0, y, -89.5), Vector3(64.0, y, -89.5), Vector3(0, 0, 1), 3.6)
	Props.block_wall(b, Vector3(56.0, y, -82.0), Vector3(64.0, y, -82.0), Vector3(0, 0, -1), 3.6)
	# The miners made it this far: timber frame, a bench, supplies
	Props.timber_frame(b, 57.0, -89.5, -82.0, y, 3.6, "z")
	Props.timber_frame(b, 63.0, -89.5, -82.0, y, 3.6, "z")
	# A miner's lantern still burns on the frame: warm light spilling back into the shrine marks the
	# right way (the imitation's wrong exit has no warm light at all).
	Props.lamp(n, Vector3(57.0, y + 3.25, -85.75), {"style": "hanging", "hang": 0.5, "energy": 1.2, "range": 7.0, "color": Color("ffb35c"), "shadow": true})
	b.solid(Vector3(58.4, y + 0.23, -88.8), Vector3(1.8, 0.46, 0.5), Props.PLANK, "wood", Basis.IDENTITY, Props.OUT)
	Props.crate(b, Vector3(62.8, y, -88.8), 0.7, 12.0)
	Props.sack(b, Vector3(62.0, y, -89.0), 30.0)
	Props.glowcaps(b, n, Vector3(63.4, y, -82.7), 4, 0.25, 0.35)


static func _descent(b: Builder, area: Node3D, decor: Node3D) -> void:
	var n := b.begin("descent_top")
	var za := -88.0
	var zb := -83.5
	var zm := (za + zb) * 0.5
	var width := zb - za
	b.floor_rect(64.0, 66.0, za, zb, -6.0, STONE)
	Props.tile_floor(b, 64.0, 66.0, za, zb, -6.0, 1.5)
	b.stairs(Vector3(66.0, -6.0, zm), Vector3(72.0, -8.0, zm), width, 0.25, STONE, STONE_DARK)
	b.ramp(Vector3(72.0, -8.0, zm), Vector3(78.0, -10.0, zm), width, Palette.SILK_ROCK)
	b.floor_rect(78.0, 80.0, za, zb, -10.0, Palette.SILK_ROCK)
	# Ceiling follows the slope 4 m above the floor
	b.ceiling_rect(64.0, 66.0, za, zb, -2.0, STONE_DARK)
	b.ramp(Vector3(66.0, -1.6, zm), Vector3(78.0, -5.6, zm), width + 0.4, STONE_DARK, "stone", true, 0.6)
	b.ceiling_rect(78.0, 80.0, za, zb, -6.0, Palette.SILK_ROCK_DARK)
	# Walls (collision + backing), then rock dressing blending ruin stone into violet silk rock
	b.solid(Vector3(72.0, -6.0, za - 0.5), Vector3(16.0, 9.0, 1.0), STONE_DARK)
	b.solid(Vector3(72.0, -6.0, zb + 0.5), Vector3(16.0, 9.0, 1.0), STONE_DARK)
	b.begin("descent_low")
	for k in 8:
		var x := 64.5 + float(k) * 2.0
		var t := float(k) / 7.0
		var fy := -6.0 - clampf((x - 66.0) / 12.0, 0.0, 1.0) * 4.0
		var cols := [STONE.lerp(Palette.SILK_ROCK, t), STONE_DARK.lerp(Palette.SILK_ROCK_DARK, t)]
		for side in [-1.0, 1.0]:
			var wz := za if side < 0.0 else zb
			b.rock_wall(Vector3(x - 1.0, fy, wz), Vector3(x + 1.0, fy, wz), Vector3(0, 0, -side), 4.0, cols, {"size": 0.8, "protrude": 0.22})
	Props.lamp(n, Vector3(64.7, -6.0, za + 0.6), {"style": "bowl", "energy": 0.8, "range": 6.0, "color": TEAL, "flame": TEAL, "idle": 0.05})
	# First wisps of silk at the bottom
	decor.add_strand(Vector3(77.0, -6.0, zm - 1.2), Vector3(77.4, -9.9, zm - 1.9))
	decor.add_strand(Vector3(79.2, -6.0, zm + 1.4), Vector3(79.0, -9.9, zm + 2.0))
	decor.add_web(Vector3(79.6, -6.6, za + 0.35), Vector3(-0.5, -0.4, 0.8), 1.2, 0.35)
	Props.glowcaps(b, n, Vector3(78.6, -10.0, zb - 0.4), 4, 0.25, 0.4, 2.6, Palette.SILK_GLOW)
