extends RefCounted
## The three line rooms of the Hushed Works (static dressing; the puzzle nodes are placed by the area):
##   Sluice Gallery (4): a wide, teal-green gallery of great pipes, gantry rails and shallow channels.
##   Bellmaker's Floor (5): a very tall square hall, bronze and timber, four great bells on two beams over a
##   cold casting pit; warm forge light.
##   Light Well (8): a narrow, 16 m high pale-limestone well with a skylight, ledges spiralling up, vines;
##   a small alcove behind a brass shutter (outfit / decor keepsakes).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const WP := preload("res://src/world/works/works_props.gd")
const Geo := preload("res://src/world/works/works_geo.gd")
const Layout := preload("res://data/works_layout.gd")

const SLUICE_FLOOR := Color("46524f")
const SLUICE_WALL := Color("4f615e")
const SLUICE_CEIL := Color("27302f")
const SLUICE_LAMP := Color("a8e0d8")
const BELL_FLOOR := Color("6a5a48")
const BELL_WALL := Color("7a6650")
const BELL_CEIL := Color("3a3028")
const WELL_FLOOR := Color("a39c8c")
const WELL_WALL := Color("bdb5a4")
const WELL_CEIL := Color("7d7668")
const BRONZE_INGOT := Color("b88450")


static func build(b: Builder, area: Node3D) -> void:
	_sluice_way(b, area)
	_sluice(b, area)
	_bells(b, area)
	_bells_hub_way(b, area)
	_lightwell_way(b, area)
	_lightwell(b, area)
	_alcove(b, area)


static func _sluice_way(b: Builder, area: Node3D) -> void:
	var n := b.begin("sluice_way")
	Geo.sloped_passage(b, "sluice_way", SLUICE_FLOOR, SLUICE_WALL, SLUICE_CEIL, Color("7d8898"))
	WP.pipe(b, Vector3(27.35, -18.2 + 2.6, -14.0), Vector3(27.35, -20.0 + 2.6, -20.0), 0.12, WP.COPPER_PIPE)
	Props.lamp(n, Vector3(28.75, -19.0 + 2.6, -17.0), {"style": "glow", "energy": 0.55, "range": 4.5, "color": SLUICE_LAMP, "flame": SLUICE_LAMP, "idle": 0.03})


static func _sluice(b: Builder, area: Node3D) -> void:
	var n := b.begin("sluice")
	var y := -20.0
	b.shell("sluice", SLUICE_FLOOR, SLUICE_WALL, SLUICE_CEIL)
	WP.flag_floor(b, 14.2, 37.8, -40.8, -21.2, y, Color("52605c"), 2.0)
	# Great pipes along the north and west walls; the inlet in the north wall is part of the puzzle node.
	WP.pipe(b, Vector3(14.6, y + 4.6, -40.4), Vector3(37.4, y + 4.6, -40.4), 0.34, WP.COPPER_PIPE)
	WP.pipe(b, Vector3(14.5, y + 3.6, -40.4), Vector3(14.5, y + 3.6, -21.6), 0.26, WP.STEEL)
	WP.pipe(b, Vector3(37.5, y + 5.4, -40.4), Vector3(37.5, y + 5.4, -21.6), 0.2, WP.COPPER_PIPE)
	for x in [18.0, 24.0, 32.0]:
		WP.pipe(b, Vector3(x, y + 4.6, -40.4), Vector3(x, y + 6.9, -40.4), 0.2, WP.COPPER_PIPE, false)
	# Gantry rails along the walls (decor, high up) and wall ribs.
	for x in [16.5, 21.5, 31.5, 35.5]:
		WP.wall_rib(b, Vector3(x, y, -41.0), Vector3(0, 0, 1), 7.0, WP.IRON_DARK)
	for zz in [-37.0, -33.0, -29.0, -25.0]:
		WP.wall_rib(b, Vector3(14.0, y, zz), Vector3(1, 0, 0), 7.0, WP.IRON_DARK)
		WP.wall_rib(b, Vector3(38.0, y, zz), Vector3(-1, 0, 0), 7.0, WP.IRON_DARK)
	b.vbox(Vector3(26.0, y + 4.0, -40.2), Vector3(23.6, 0.12, 1.0), WP.IRON, Basis.IDENTITY, WP.OUT)
	for i in 12:
		b.vbox(Vector3(14.6 + float(i) * 2.1, y + 4.5, -39.75), Vector3(0.05, 1.0, 0.05), WP.IRON_DARK, Basis.IDENTITY, {"shadows": false})
	# Channel curbs (flush plank bridges over the channels, visual only) and a drain grate at the west end.
	for bz in [[20.2, -35.5], [31.0, -30.1], [33.2, -24.5]]:
		b.vbox(Vector3(float(bz[0]), y + 0.05, float(bz[1])), Vector3(1.1, 0.06, 2.4), b.vary(WP.TIMBER, 0.06), Basis.IDENTITY, {"shadows": false})
	b.vbox(Vector3(14.9, y + 0.03, -35.5), Vector3(0.6, 0.04, 1.6), WP.IRON_DARK, Basis.IDENTITY, {"shadows": false})
	b.vbox(Vector3(37.3, y + 0.03, -35.2), Vector3(0.9, 0.04, 1.2), WP.IRON_DARK, Basis.IDENTITY, {"shadows": false})
	# Hask's resting spot by the west wall: a slate leaning on the wall with his chalk note (the lore node is
	# the area's, data/works_layout.gd LORE_SPOTS lore_ch2_sluice_chalk), a tin mug and a toppled stool.
	var sl := Vector3(14.16, y, -26.4)
	b.vbox(sl + Vector3(0, 0.62, 0), Vector3(0.06, 0.9, 0.7), Color("3a3f44"), Basis(Vector3(0, 0, 1), -0.12), WP.OUT)
	b.vbox(sl + Vector3(0.05, 0.62, 0), Vector3(0.02, 0.78, 0.6), Color("4a5056"), Basis(Vector3(0, 0, 1), -0.12), {"shadows": false})
	for i in 4:
		b.vbox(sl + Vector3(0.07, 0.42 + float(i) * 0.12, -0.2 + float(i % 2) * 0.08), Vector3(0.01, 0.025, 0.28 - float(i) * 0.04), Color("e8e2d4"), Basis(Vector3(0, 0, 1), -0.12), {"shadows": false})
	b.vcyl(Vector3(14.7, y + 0.07, -25.7), 0.06, 0.14, WP.STEEL, Basis.IDENTITY, {"segments": 8})
	b.vbox(Vector3(16.2, y + 0.2, -25.2), Vector3(0.4, 0.06, 0.4), WP.TIMBER, Basis(Vector3(1, 0, 0), 1.3))
	# The plaque by the entrance
	b.vbox(Vector3((Layout.SLUICE["plaque"] as Vector3).x, y + 1.4, -21.06), Vector3(1.2, 0.7, 0.08), WP.BRASS, Basis.IDENTITY, WP.OUT)
	# Lamps: cold teal over the water, one warm lamp by the plaque.
	for p in [Vector3(20.0, y + 5.8, -36.0), Vector3(30.0, y + 5.8, -30.0), Vector3(33.0, y + 5.8, -24.5)]:
		WP.chain(b, p + Vector3.UP * 1.2, 1.2)
		WP.cage_shade(b, p)
		Props.lamp(n, p, {"style": "glow", "energy": 1.05, "range": 9.0, "color": SLUICE_LAMP, "flame": SLUICE_LAMP, "idle": 0.03})
	Props.lamp(n, Vector3(24.5, y + 2.6, -21.5), {"style": "wall", "energy": 0.7, "range": 4.5, "color": WP.WARM_LAMP, "yaw": 180.0})
	Props.glow_light(n, Vector3(26.0, y + 6.2, -31.0), Color("4f7f80"), 0.35, 16.0)


static func _bells(b: Builder, area: Node3D) -> void:
	var n := b.begin("bells")
	var y := -16.0
	b.shell("bells", BELL_FLOOR, BELL_WALL, BELL_CEIL)
	WP.flag_floor(b, 2.2, 23.8, 24.2, 41.8, y, Color("76644f"), 2.2)
	# Two massive beams across the hall carry the bells (their tops at y -8.2), on timber posts at the walls.
	for bz in [29.5, 37.5]:
		b.vbox(Vector3(13.0, -7.9, bz), Vector3(21.6, 0.6, 0.7), b.vary(WP.TIMBER, 0.05), Basis.IDENTITY, WP.OUT)
		for px in [2.5, 23.5]:
			b.solid(Vector3(px, y + 4.0, bz), Vector3(0.7, 8.0, 0.7), b.vary(WP.TIMBER, 0.05), "wood", Basis.IDENTITY, {"outline": true, "outline_w": 0.016, "no_occluder": true})
		for bx in [6.5, 17.5]:
			b.vbox(Vector3(bx, -7.45, bz), Vector3(0.5, 0.3, 0.9), WP.IRON_DARK, Basis.IDENTITY, WP.OUT)
	# Wall ribs and ringing-rope pegs; the cold casting pit (south): moulds, ingots, an anvil, a cold forge.
	for x in [5.0, 10.0, 15.0]:
		WP.wall_rib(b, Vector3(x, y, 42.0), Vector3(0, 0, -1), 11.0, WP.BRONZE.darkened(0.3))
	for zz in [26.5, 36.0, 40.0]:
		WP.wall_rib(b, Vector3(24.0, y, zz), Vector3(-1, 0, 0), 11.0, WP.BRONZE.darkened(0.3))
	for i in 5:
		var mp := Vector3(4.0 + float(i) * 1.6, y, 40.8)
		b.vcyl(mp + Vector3.UP * 0.35, 0.55, 0.7, b.vary(Color("5a4a3c"), 0.08), Basis.IDENTITY, {"segments": 14})
		b.vcyl(mp + Vector3.UP * 0.71, 0.4, 0.02, Color("2a2420"), Basis.IDENTITY, {"segments": 14, "shadows": false})
	b.col_box(Vector3(7.2, y + 0.35, 40.8), Vector3(8.2, 0.7, 1.2))
	for i in 6:
		b.vbox(Vector3(20.5 + float(i % 3) * 0.5, y + 0.12 + floorf(float(i) / 3.0) * 0.2, 40.9), Vector3(0.44, 0.18, 0.9), BRONZE_INGOT, Basis.IDENTITY, {"shadows": false})
	b.solid(Vector3(21.0, y + 0.45, 38.8), Vector3(0.9, 0.9, 0.5), WP.IRON_DARK, "stone", Basis.IDENTITY, {"outline": true, "outline_w": 0.016, "no_occluder": true})
	b.vbox(Vector3(21.0, y + 1.0, 38.8), Vector3(1.4, 0.25, 0.6), WP.IRON, Basis.IDENTITY, WP.OUT)
	# forge: a stone hood on the south wall with banked embers (warm light)
	b.solid(Vector3(12.0, y + 0.6, 41.3), Vector3(3.0, 1.2, 1.2), Color("5c524a"), "stone", Basis.IDENTITY, {"no_occluder": true})
	b.vbox(Vector3(12.0, y + 2.6, 41.4), Vector3(3.2, 2.8, 1.0), Color("4e463f"), Basis.IDENTITY, WP.OUT)
	for i in 9:
		b.vglow(Builder.unit_sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3(0.22, 0.12, 0.22)), Vector3(10.9 + float(i % 3) * 1.1, y + 1.25, 40.9 + floorf(float(i) / 3.0) * 0.25)), Color("ff8a40"), 1.6)
	Props.glow_light(n, Vector3(12.0, y + 1.8, 39.8), Color("ff9a50"), 1.1, 9.0)
	# Hanging lamps between the bells, warm bronze light, one high fill light (tall room).
	for p in [Vector3(12.0, y + 6.5, 29.5), Vector3(12.0, y + 6.5, 37.5)]:
		WP.chain(b, Vector3(p.x, -8.0, p.z), 1.5)
		Props.lamp(n, p, {"style": "hanging", "hang": 0.1, "energy": 1.3, "range": 10.0, "color": Color("ffc890"), "idle": 0.04})
	Props.glow_light(n, Vector3(13.0, y + 9.5, 33.0), Color("8a6a48"), 0.45, 18.0)
	WP.symbol_sign(b, Vector3(2.05, y + 4.0, 30.0), Vector3(1, 0, 0), "bell", Color.WHITE, 0.8)


static func _bells_hub_way(b: Builder, area: Node3D) -> void:
	var n := b.begin("bells_hub_way")
	Geo.sloped_passage(b, "bells_hub_way", BELL_FLOOR, BELL_WALL, BELL_CEIL, Color("a08870"))
	Props.lamp(n, Vector3(20.75, -17.0 + 2.6, 18.5), {"style": "glow", "energy": 0.55, "range": 4.5, "color": Color("ffc890"), "flame": Color("ffc890"), "idle": 0.03})


static func _lightwell_way(b: Builder, area: Node3D) -> void:
	var n := b.begin("lightwell_way")
	Geo.sloped_passage(b, "lightwell_way", WELL_FLOOR, WELL_WALL, WELL_CEIL, Color("d8d0bc"))
	Props.lamp(n, Vector3(34.75, -19.0 + 2.6, 16.5), {"style": "glow", "energy": 0.5, "range": 4.5, "color": Color("fff0c8"), "flame": Color("fff0c8"), "idle": 0.02})


static func _lightwell(b: Builder, area: Node3D) -> void:
	var n := b.begin("lightwell")
	var y := -20.0
	var r: Dictionary = b.rooms["lightwell"]
	var cy := y + float(r["h"])
	b.shell("lightwell", WELL_FLOOR, WELL_WALL, WELL_CEIL, {"no_ceiling": true})
	# Ceiling with the skylight straight above mirror A.
	var a: Vector3 = Layout.LIGHTWELL["mirror_a"]
	var hx0 := a.x - 1.5
	var hx1 := a.x + 1.5
	var hz0 := a.z - 1.5
	var hz1 := a.z + 1.5
	b.ceiling_rect(26.0, 39.0, 20.0, hz0, cy, WELL_CEIL)
	b.ceiling_rect(26.0, 39.0, hz1, 34.0, cy, WELL_CEIL)
	b.ceiling_rect(26.0, hx0, hz0, hz1, cy, WELL_CEIL)
	b.ceiling_rect(hx1, 39.0, hz0, hz1, cy, WELL_CEIL)
	b.solid(Vector3(a.x, cy + 1.2, a.z), Vector3(4.0, 0.4, 4.0), WELL_CEIL)       # cap above the skylight
	for w in [[Vector3(hx0 - 0.25, cy + 0.6, a.z), Vector3(0.5, 1.2, 3.5)], [Vector3(hx1 + 0.25, cy + 0.6, a.z), Vector3(0.5, 1.2, 3.5)],
			[Vector3(a.x, cy + 0.6, hz0 - 0.25), Vector3(3.0, 1.2, 0.5)], [Vector3(a.x, cy + 0.6, hz1 + 0.25), Vector3(3.0, 1.2, 0.5)]]:
		b.solid(w[0], w[1], WELL_WALL)
	WP.flag_floor(b, 26.2, 38.8, 20.2, 33.8, y, Color("b3ab98"), 1.3)
	# Ledges spiralling up the well walls (visual) and coursed limestone bands.
	for i in 14:
		var t := float(i) / 14.0
		var hh := y + 3.0 + t * 11.5
		var side := i % 4
		var p: Vector3
		var s: Vector3
		match side:
			0:
				p = Vector3(27.0 + t * 8.0, hh, 20.45)
				s = Vector3(2.4, 0.25, 0.9)
			1:
				p = Vector3(38.55, hh, 22.0 + t * 9.0)
				s = Vector3(0.9, 0.25, 2.4)
			2:
				p = Vector3(37.0 - t * 8.0, hh, 33.55)
				s = Vector3(2.4, 0.25, 0.9)
			_:
				p = Vector3(26.45, hh, 32.0 - t * 9.0)
				s = Vector3(0.9, 0.25, 2.4)
		b.vbox(p, s, b.vary(WELL_WALL.darkened(0.08), 0.05), Basis.IDENTITY, WP.OUT)
	for band in [3.2, 7.0, 11.0]:
		b.vbox(Vector3(32.5, y + band, 20.05), Vector3(13.0, 0.18, 0.12), WELL_WALL.darkened(0.15), Basis.IDENTITY, {"shadows": false})
		b.vbox(Vector3(32.5, y + band, 33.95), Vector3(13.0, 0.18, 0.12), WELL_WALL.darkened(0.15), Basis.IDENTITY, {"shadows": false})
	# Vines down the walls from the skylight's light, moss at the foot of the walls.
	for i in 16:
		var side := i % 4
		var t := b.rng.randf()
		var top := Vector3.ZERO
		match side:
			0: top = Vector3(26.5 + t * 12.0, cy - 0.2, 20.2)
			1: top = Vector3(38.8, cy - 0.2, 20.5 + t * 13.0)
			2: top = Vector3(26.5 + t * 12.0, cy - 0.2, 33.8)
			_: top = Vector3(26.2, cy - 0.2, 20.5 + t * 13.0)
		var ln := b.rng.randf_range(2.5, 7.0)
		b.vcyl(top - Vector3.UP * ln * 0.5, 0.03, ln, b.vary(Color("5f8a4a"), 0.1), Basis.IDENTITY, {"segments": 5, "shadows": false})
	b.pebbles(26.4, 38.6, 20.4, 21.2, y, [WELL_WALL, WELL_FLOOR], 16, 0.1)
	# The plaque, and pale fill light (the room brightens further once the line wakes: the puzzle node).
	b.vbox(Vector3(38.94, y + 1.4, (Layout.LIGHTWELL["plaque"] as Vector3).z), Vector3(0.08, 0.7, 1.0), WP.BRASS, Basis.IDENTITY, WP.OUT)
	Props.lamp(n, Vector3(38.5, y + 2.6, 22.5), {"style": "wall", "energy": 0.6, "range": 4.5, "color": WP.WARM_LAMP, "yaw": -90.0})
	Props.glow_light(n, Vector3(32.5, y + 8.0, 27.0), Color("d8d0b8"), 0.45, 16.0)


static func _alcove(b: Builder, area: Node3D) -> void:
	var n := b.begin("lightwell_alcove")
	var y := -20.0
	b.shell("lightwell_alcove", WELL_FLOOR, WELL_WALL, WELL_CEIL)
	# a tailor's dummy wearing a festival shawl, bunting, a mirror frame; the trunk is the area's node.
	var d := Vector3(30.8, y, 37.2)
	b.vcyl(d + Vector3.UP * 0.05, 0.3, 0.1, WP.IRON_DARK)
	b.vcyl(d + Vector3.UP * 0.6, 0.03, 1.1, WP.TIMBER)
	b.vblob(d + Vector3.UP * 1.35, Vector3(0.3, 0.42, 0.22), Color("e8dcc0"), 2)
	b.vblob(d + Vector3.UP * 1.45, Vector3(0.42, 0.25, 0.3), Color("d9546a"), 4)
	for i in 7:
		var p := Vector3(30.2 + float(i) * 0.6, y + 2.8 - absf(float(i) - 3.0) * 0.08, 37.9)
		b.vcone(p, 0.14, 0.26, [Color("f2c14e"), Color("d9546a"), Color("b48ad8")][i % 3], Basis(Vector3(1, 0, 0), PI), {"shadows": false})
	b.vbox(Vector3(33.6, y + 1.3, 37.9), Vector3(0.7, 1.4, 0.06), WP.BRASS, Basis.IDENTITY, WP.OUT)
	b.vbox(Vector3(33.6, y + 1.3, 37.86), Vector3(0.55, 1.2, 0.02), Color("dfe6ee"), Basis.IDENTITY, {"shadows": false})
	Props.glow_light(n, Vector3(32.0, y + 2.4, 36.0), Color("ffd8a8"), 0.7, 5.0)
