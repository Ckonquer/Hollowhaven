extends RefCounted
## The Old Mine: Mine Landing, Timbered Tunnel (+ the dark side passage of THE THRESHOLD),
## Collapsed Gallery, Foreman's Office and the Lower Gate hall. Warm amber lanterns, timber, rails.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Layout := preload("res://src/world/below/below_layout.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")

const FLOOR := Color("5f4a3b")
const FLOOR_DARK := Color("4a392e")
const WALL := Color("5a4636")
const CEIL := Color("3b2a22")
const LAMP := Color("ffb35c")


static func rock_cols() -> Array:
	return [Palette.MINE_ROCK, Palette.MINE_ROCK.lerp(Palette.MINE_ROCK_DARK, 0.45), Palette.MINE_ROCK.lerp(Palette.DIRT_DARK, 0.3), Color("6a5140")]


static func build(b: Builder, area: Node3D) -> void:
	_landing(b, area)
	_tunnel(b, area)
	_side_passage(b, area)
	_gallery(b, area)
	_office(b, area)
	_gate(b, area)


static func _landing(b: Builder, area: Node3D) -> void:
	var n := b.begin("landing")
	var cols := rock_cols()
	b.shell("landing", FLOOR, WALL, CEIL)
	b.dress_room_rock("landing", cols, {"size": 1.1})
	b.ceiling_lumps(-6.5, 6.5, -5.5, 5.5, 5.0, [CEIL, Palette.MINE_ROCK_DARK], 10, 1.0)
	b.pebbles(-6.5, 6.5, -5.5, 5.5, 0.0, cols, 40)
	# Entry shaft to the surface (south): ladder in a tall shaft with warm daylight from above.
	b.floor_rect(-1.6, 1.6, 6.0, 8.6, 0.0, FLOOR)
	b.solid(Vector3(-2.1, 6.0, 7.3), Vector3(1.0, 12.0, 2.6), WALL)
	b.solid(Vector3(2.1, 6.0, 7.3), Vector3(1.0, 12.0, 2.6), WALL)
	b.solid(Vector3(0.0, 6.0, 9.1), Vector3(5.2, 12.0, 1.0), WALL)
	b.solid(Vector3(0.0, 8.5, 5.5), Vector3(5.2, 7.0, 1.0), WALL)     # lintel wall above the shaft mouth (y 5..12)
	b.rock_wall(Vector3(-1.6, 0, 6.0), Vector3(-1.6, 0, 8.6), Vector3(1, 0, 0), 11.0, cols, {"size": 0.8, "protrude": 0.2})
	b.rock_wall(Vector3(1.6, 0, 6.0), Vector3(1.6, 0, 8.6), Vector3(-1, 0, 0), 11.0, cols, {"size": 0.8, "protrude": 0.2})
	# ladder
	for s in [-0.35, 0.35]:
		b.vbox(Vector3(s, 5.5, 8.35), Vector3(0.1, 11.0, 0.1), Props.TIMBER, Basis.IDENTITY, Props.OUT)
	for i in 30:
		b.vbox(Vector3(0, 0.35 + float(i) * 0.36, 8.35), Vector3(0.7, 0.06, 0.07), Props.PLANK, Basis.IDENTITY, {"shadows": false})
	# daylight cap at the top of the shaft
	var sky := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3.2, 2.6)
	sky.mesh = pm
	sky.material_override = Mat.glow(Color("ffe2b0"), 1.6)
	sky.rotation_degrees.x = 180.0
	n.add_child(sky)
	sky.position = Vector3(0, 11.9, 7.3)
	var sun := SpotLight3D.new()
	sun.name = "ShaftLight"
	sun.light_color = Color("ffd9a0")
	sun.light_energy = 2.2
	sun.spot_range = 16.0
	sun.spot_angle = 24.0
	sun.spot_attenuation = 0.6
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 1.4
	n.add_child(sun)
	sun.position = Vector3(0, 11.6, 7.8)
	sun.rotation_degrees = Vector3(-80, 0, 0)
	sun.add_to_group("below_shaft_light")
	# Lift recess (east): the lift node itself is placed by the area.
	b.floor_rect(7.0, 9.9, -1.7, 1.7, 0.0, FLOOR_DARK)
	b.solid(Vector3(8.45, 2.5, -2.2), Vector3(2.9, 5.0, 1.0), WALL)
	b.solid(Vector3(8.45, 2.5, 2.2), Vector3(2.9, 5.0, 1.0), WALL)
	b.solid(Vector3(10.4, 2.5, 0.0), Vector3(1.0, 5.0, 5.4), WALL)
	b.solid(Vector3(8.45, 4.5, 0.0), Vector3(2.9, 1.0, 3.4), CEIL)    # shaft cover (dark hole above the cage)
	# Timber frames framing the tunnel mouth and the lift
	Props.timber_frame(b, -5.8, -2.2, 2.2, 0.0, 3.6, "x")
	Props.timber_frame(b, 6.8, -1.7, 1.7, 0.0, 3.2, "z")
	# Rails from the buffer stop into the tunnel
	Props.rails(b, Vector3(1.1, 0.0, -1.6), Vector3(1.1, 0.0, -6.0))
	b.solid(Vector3(1.1, 0.35, -1.4), Vector3(1.1, 0.7, 0.3), Props.TIMBER_DARK, "wood", Basis.IDENTITY, Props.OUT)
	# Clutter (along the walls, never in the way)
	Props.crate(b, Vector3(-6.2, 0, -5.1), 0.9, 8.0)
	Props.crate(b, Vector3(-5.2, 0, -5.2), 0.8, -12.0)
	Props.crate(b, Vector3(-5.9, 0.9, -5.1), 0.7, 25.0)
	Props.barrel(b, Vector3(-6.3, 0, -3.8))
	Props.barrel(b, Vector3(6.2, 0, -4.8))
	Props.barrel(b, Vector3(5.5, 0, -5.3), 0.32, 0.8)
	Props.sack(b, Vector3(6.3, 0, 3.6), 20.0)
	Props.sack(b, Vector3(5.8, 0, 4.5), -40.0)
	Props.crate(b, Vector3(-6.2, 0, 4.8), 0.9, 4.0)
	Props.rope_coil(b, Vector3(-4.6, 0, 5.2))
	Props.pickaxe_lean(b, Vector3(-6.75, 0, 2.4), 90.0)
	Props.pickaxe_lean(b, Vector3(-6.75, 0, 3.1), 80.0)
	Props.table(b, Vector3(-3.0, 0, -4.9), 0.0, 1.6, 0.8)
	Props.papers(b, Vector3(-3.3, 0.84, -4.9), 10.0)
	Props.sign_board(b, Vector3(3.6, 1.7, -5.85), 0.0, 1.3, 0.8)
	# Lights: warm and welcoming (this is the safe room)
	Props.lamp(n, Vector3(-2.5, 5.0, -1.5), {"style": "hanging", "hang": 1.2, "energy": 1.8, "range": 9.0, "shadow": true, "color": LAMP})
	Props.lamp(n, Vector3(2.8, 5.0, 2.5), {"style": "hanging", "hang": 1.4, "energy": 1.3, "range": 7.5, "color": LAMP})
	Props.lamp(n, Vector3(-2.6, 0.84, -4.9), {"style": "floor", "energy": 0.9, "range": 4.0, "color": LAMP})
	Props.glowcaps(b, n, Vector3(6.3, 0, -2.6), 6, 0.35, 0.5)
	Props.glowcaps(b, n, Vector3(-6.4, 0, 2.9), 4, 0.25)


static func _tunnel(b: Builder, area: Node3D) -> void:
	var n := b.begin("tunnel")
	var cols := rock_cols()
	b.shell("tunnel", FLOOR, WALL, CEIL)
	b.dress_room_rock("tunnel", cols, {"size": 0.95, "spacing": 1.25})
	b.pebbles(-2.0, 2.0, -35.5, -6.5, 0.0, cols, 60)
	var z := -8.0
	var i := 0
	while z > -35.0:
		Props.timber_frame(b, z, -2.2, 2.2, 0.0, 3.6, "x", i == 3)
		# ceiling lagging planks between frames
		if i != 3:
			for k in 5:
				b.vbox(Vector3(-1.6 + float(k) * 0.8, 3.52, z - 1.75), Vector3(0.7, 0.08, 3.4), b.vary(Props.PLANK.darkened(0.25), 0.08), Basis.IDENTITY, {"shadows": false})
		z -= 3.5
		i += 1
	Props.rails(b, Vector3(1.1, 0.0, -6.0), Vector3(1.1, 0.0, -36.0))
	Props.cart(b, Vector3(1.1, 0.0, -28.8), 0.0, false)
	Props.crate(b, Vector3(-1.85, 0, -27.9), 0.7, 6.0)
	Props.papers(b, Vector3(-1.85, 0.71, -27.9), -20.0)
	Props.crate(b, Vector3(-1.82, 0, -12.4), 0.66, -6.0)
	Props.barrel(b, Vector3(1.75, 0, -15.5), 0.32, 0.8)
	Props.sack(b, Vector3(-1.8, 0, -31.5), 70.0)
	Props.pickaxe_lean(b, Vector3(2.0, 0, -10.2), -90.0)
	# Lanterns hang from frames; the Threshold mouth (z -18.5..-21.5) is left in shadow.
	Props.lamp(n, Vector3(0.0, 3.25, -8.0), {"style": "hanging", "hang": 0.4, "energy": 1.4, "range": 7.0, "shadow": true, "color": LAMP})
	Props.lamp(n, Vector3(0.0, 3.25, -25.5), {"style": "hanging", "hang": 0.4, "energy": 1.2, "range": 6.5, "color": LAMP})
	Props.lamp(n, Vector3(0.0, 3.25, -32.5), {"style": "hanging", "hang": 0.4, "energy": 1.0, "range": 6.0, "color": LAMP, "shadow": true})
	# Glowcaps along the wall foot light the path between lanterns
	for gz in [-11.5, -14.8, -23.0, -30.5, -34.5]:
		var gx: float = -1.85 if int(absf(gz)) % 2 == 0 else 1.85
		Props.glowcaps(b, n, Vector3(gx, 0, gz), 5, 0.3, 0.55, 2.6)


static func _side_passage(b: Builder, area: Node3D) -> void:
	var n := b.begin("side_passage")
	var cols := [Palette.MINE_ROCK_DARK, Palette.MINE_ROCK.lerp(Palette.MINE_ROCK_DARK, 0.6)]
	b.shell("side_passage", FLOOR_DARK, Palette.MINE_ROCK_DARK, CEIL)
	b.dress_room_rock("side_passage", cols, {"size": 0.9})
	# The passage "continues" into blackness, but a collapse closes it off.
	Props.rubble_pile(b, Vector3(-10.2, 0, -20.0), 1.6, 2.6, cols, 12, false)
	Props.timber_frame(b, -3.0, -21.5, -18.5, 0.0, 3.0, "z", true)
	Props.timber_frame(b, -7.0, -21.5, -18.5, 0.0, 3.0, "z", true)
	b.pebbles(-10.5, -2.5, -21.2, -18.8, 0.0, cols, 25)
	Props.rails(b, Vector3(-2.4, 0, -20.0), Vector3(-9.0, 0, -20.0), 0.8)
	var _unused := n


static func _gallery(b: Builder, area: Node3D) -> void:
	var n := b.begin("gallery")
	var cols := rock_cols()
	b.shell("gallery", FLOOR, WALL, CEIL)
	b.dress_room_rock("gallery", cols, {"size": 1.3, "spacing": 1.5})
	b.ceiling_lumps(-7.5, 7.5, -49.5, -36.5, 6.0, [CEIL, Palette.MINE_ROCK_DARK], 14, 1.3)
	b.pebbles(-7.5, 7.5, -49.5, -36.5, 0.0, cols, 70, 0.15)
	# The collapse: big rock piles in the corners, a fallen beam, broken frames
	Props.rubble_pile(b, Vector3(-6.4, 0, -48.2), 2.2, 3.4, cols, 14)
	Props.rubble_pile(b, Vector3(-6.6, 0, -37.8), 1.6, 2.2, cols, 9)
	Props.rubble_pile(b, Vector3(6.3, 0, -37.7), 1.5, 2.0, cols, 8)
	b.vbox(Vector3(-3.0, 1.3, -47.6), Vector3(0.32, 0.32, 5.5), Props.TIMBER_DARK, Basis(Vector3(0, 1, 0), 1.1) * Basis(Vector3(1, 0, 0), 0.45), Props.OUT)
	Props.cart(b, Vector3(5.4, 0, -47.9), 70.0, true)
	Props.rails(b, Vector3(1.1, 0.0, -36.0), Vector3(2.8, 0.0, -44.0))
	Props.crate(b, Vector3(7.1, 0, -40.0), 0.8, 30.0)
	Props.barrel(b, Vector3(7.2, 0, -41.3), 0.34, 0.85)
	# Support pillars of timber (dramatic, tall room)
	for p in [Vector3(-3.5, 0, -41.0), Vector3(3.6, 0, -45.0)]:
		b.vbox(p + Vector3(0, 3.0, 0), Vector3(0.4, 6.0, 0.4), Props.TIMBER, Basis.IDENTITY, Props.OUT)
		b.col_box(p + Vector3(0, 3.0, 0), Vector3(0.4, 6.0, 0.4), "wood")
		b.vbox(p + Vector3(0, 5.75, 0), Vector3(2.4, 0.3, 0.45), Props.TIMBER_DARK, Basis.IDENTITY, Props.OUT)
	# Dim, uneasy light: one flickering lantern post near the entry and a weak one by the gate.
	Props.lamp(n, Vector3(-2.9, 0, -37.2), {"style": "post", "energy": 1.25, "range": 7.5, "color": LAMP, "idle": 0.12, "shadow": true})
	Props.lamp(n, Vector3(2.6, 3.6, -49.9), {"style": "wall", "yaw": 0.0, "energy": 0.8, "range": 5.0, "color": LAMP})
	Props.glowcaps(b, n, Vector3(-7.3, 0, -43.0), 6, 0.4, 0.5)
	Props.glowcaps(b, n, Vector3(4.9, 0, -49.3), 4, 0.3, 0.4)
	Props.glowcaps(b, n, Vector3(7.4, 0, -46.3), 4, 0.25, 0.45)


static func _office(b: Builder, area: Node3D) -> void:
	# Passage (holds the rubble; the rubble node itself is added by the area)
	var nw := b.begin("office_way")
	var cols := rock_cols()
	b.shell("office_way", FLOOR, WALL, CEIL)
	b.dress_room_rock("office_way", cols, {"size": 0.8})
	Props.timber_frame(b, 8.6, -45.5, -42.0, 0.0, 3.0, "z")
	Props.timber_frame(b, 11.6, -45.5, -42.0, 0.0, 3.0, "z")
	var _unused := nw
	# The office: plank floor, plank walls, beams. Warm and lived-in, long abandoned.
	var n := b.begin("office")
	var r: Dictionary = Layout.ROOMS["office"]
	b.shell("office", Props.PLANK, Color("6e4a31"), Color("5a3b27"), {"surface": "wood"})
	# floor planks
	for i in 18:
		var z := -47.75 + float(i) * 0.5
		b.vbox(Vector3(16.0, 0.01, z), Vector3(7.96, 0.03, 0.46), b.vary(Props.PLANK, 0.08), Basis.IDENTITY, {"shadows": false})
	# vertical wall planks (north, south, east; west has the doorway)
	for i in 16:
		var x := 12.25 + float(i) * 0.5
		b.vbox(Vector3(x, 1.7, -47.96), Vector3(0.46, 3.4, 0.06), b.vary(Color("7d5538"), 0.1), Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(x, 1.7, -39.04), Vector3(0.46, 3.4, 0.06), b.vary(Color("7d5538"), 0.1), Basis.IDENTITY, {"shadows": false})
	for i in 18:
		var z := -47.75 + float(i) * 0.5
		b.vbox(Vector3(19.96, 1.7, z), Vector3(0.06, 3.4, 0.46), b.vary(Color("7d5538"), 0.1), Basis.IDENTITY, {"shadows": false})
	for sz in [-47.8, -39.2]:
		b.vbox(Vector3(16.0, 3.25, sz), Vector3(8.0, 0.3, 0.3), Props.TIMBER_DARK, Basis.IDENTITY, Props.OUT)
	for bx in [14.0, 18.0]:
		b.vbox(Vector3(bx, 3.25, -43.5), Vector3(0.3, 0.3, 9.0), Props.TIMBER_DARK, Basis.IDENTITY, Props.OUT)
	# Shelves with jars and boxes (north wall)
	for sy in [1.0, 1.7]:
		b.vbox(Vector3(16.5, sy, -47.6), Vector3(3.0, 0.07, 0.55), Props.PLANK, Basis.IDENTITY, Props.OUT)
		for k in 5:
			var jx := 15.3 + float(k) * 0.6
			if b.rng.randf() < 0.5:
				b.vcyl(Vector3(jx, sy + 0.16, -47.55), 0.1, 0.26, b.pick([Color("7d9a8a"), Color("b07a4f"), Color("c9b27a")]), Basis.IDENTITY, Props.OUT)
			else:
				b.vbox(Vector3(jx, sy + 0.12, -47.55), Vector3(0.3, 0.22, 0.3), b.vary(Props.PLANK.darkened(0.1)), Basis.IDENTITY, Props.OUT)
	b.col_box(Vector3(16.5, 1.0, -47.6), Vector3(3.0, 2.0, 0.6), "wood")
	# Bunk against the south wall
	b.vbox(Vector3(17.6, 0.45, -39.6), Vector3(2.0, 0.2, 0.9), Props.TIMBER, Basis.IDENTITY, Props.OUT)
	b.vbox(Vector3(17.6, 0.6, -39.6), Vector3(1.9, 0.14, 0.8), Color("8a6a5a"), Basis.IDENTITY, {})
	b.vbox(Vector3(16.9, 0.72, -39.6), Vector3(0.45, 0.12, 0.6), Color("d8c8a8"), Basis.IDENTITY, {})
	b.col_box(Vector3(17.6, 0.35, -39.6), Vector3(2.0, 0.7, 0.9), "wood")
	# Map pinned to the wall and a stove
	b.vbox(Vector3(15.5, 1.8, -39.08), Vector3(1.2, 0.8, 0.02), Color("e8dcc0"), Basis.IDENTITY, {"shadows": false})
	b.vbox(Vector3(15.3, 1.85, -39.07), Vector3(0.5, 0.06, 0.02), Color("8a3b3b"), Basis.IDENTITY, {"shadows": false})
	b.vcyl(Vector3(13.0, 0.5, -47.2), 0.35, 1.0, Color("3b3238"), Basis.IDENTITY, Props.OUT)
	b.vcyl(Vector3(13.0, 2.2, -47.2), 0.08, 2.4, Color("3b3238"), Basis.IDENTITY, {})
	b.col_cyl(Vector3(13.0, 0.5, -47.2), 0.36, 1.0, "stone")
	Props.crate(b, Vector3(19.3, 0, -47.3), 0.7, 5.0)
	Props.crate(b, Vector3(19.35, 0.7, -47.25), 0.55, -18.0)
	Props.lamp(n, Vector3(16.0, 3.4, -43.6), {"style": "hanging", "hang": 0.6, "energy": 0.6, "range": 6.0, "color": LAMP})
	var _r := r


static func _gate(b: Builder, area: Node3D) -> void:
	var n := b.begin("gate")
	var cols := rock_cols()
	b.shell("gate", FLOOR, WALL, CEIL)
	b.dress_room_rock("gate", cols, {"size": 0.85})
	b.pebbles(-1.8, 1.8, -57.8, -50.2, 0.0, cols, 20)
	Props.timber_frame(b, -51.0, -2.0, 2.0, 0.0, 4.0, "x")
	# Carved old stone creeping in beyond the gate: the ruins begin here.
	b.vbox(Vector3(0.0, 0.03, -56.8), Vector3(3.8, 0.06, 2.2), Palette.RUIN_STONE_DARK, Basis.IDENTITY, {"shadows": false})
	Props.lamp(n, Vector3(-1.95, 2.5, -52.8), {"style": "wall", "yaw": 90.0, "energy": 1.1, "range": 6.0, "color": LAMP, "shadow": true})
	Props.glowcaps(b, n, Vector3(1.7, 0, -53.6), 4, 0.25, 0.35)
