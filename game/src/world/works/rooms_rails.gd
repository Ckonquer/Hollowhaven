extends RefCounted
## Rooms 3 and 6 of the Hushed Works.
##   Humming Rails (3): a tall, long iron-girdered rail hall in cold steel blue, twin tracks running east to the
##   rail junction, where Hask's lamp burns beside the rail (the only warm light). Two short side corridors near
##   the east end are dark and sealed behind grates - the false signals' corridors (no light at all).
##   Hall of Closed Eyes (6): a long, narrow, pale-violet stone hall of carved faces with their eyes shut, each
##   over an empty-looking iron hook; one great face is a hidden door whose lantern lies misplaced on the floor.
##   On the east wall a barred cell nobody can enter (the wrong door). Quiet on purpose.
## Interactive pieces (signal lamp, glints, doors, the misplaced lantern) are placed by the area script.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const WP := preload("res://src/world/works/works_props.gd")
const Geo := preload("res://src/world/works/works_geo.gd")
const Layout := preload("res://data/works_layout.gd")

const RAIL_FLOOR := Color("454a52")
const RAIL_WALL := Color("4f5866")
const RAIL_CEIL := Color("2a2f38")
const EYES_FLOOR := Color("8e8a92")
const EYES_WALL := Color("9a95a0")
const EYES_CEIL := Color("5c5866")
const EYES_LAMP := Color("c8c0e8")


static func build(b: Builder, area: Node3D) -> void:
	_rails(b, area)
	_false_corridor(b, "rails_false_n", -1.0)
	_false_corridor(b, "rails_false_s", 1.0)
	_junction(b, area)
	_junction_stair(b, area)
	_eyes_way(b, area)
	_eyes(b, area)
	_eyes_route(b, area)
	_bells_way(b, area)


static func _rails(b: Builder, area: Node3D) -> void:
	var n := b.begin("rails")
	var y := -11.0
	b.shell("rails", RAIL_FLOOR, RAIL_WALL, RAIL_CEIL)
	WP.flag_floor(b, -29.8, -2.2, -5.8, 5.8, y, Color("4a4f57"), 1.9)
	# Twin tracks from the west door to the junction turntable.
	Props.rails(b, Vector3(-29.6, y, -2.2), Vector3(0.2, y, -2.2))
	Props.rails(b, Vector3(-29.6, y, 2.2), Vector3(0.2, y, 2.2))
	# Iron girder arches (tall hall silhouette), riveted wall plates between them.
	for x in [-26.5, -21.0, -10.5, -3.2]:
		WP.girder_arch(b, x, -6.0, 6.0, y, 7.4, "x")
	for x in [-28.5, -23.8, -18.5, -8.6]:
		WP.wall_rib(b, Vector3(x, y, -6.0), Vector3(0, 0, 1), 7.4, WP.IRON_DARK)
		if x != -18.5 and x != -8.6:
			WP.wall_rib(b, Vector3(x, y, 6.0), Vector3(0, 0, -1), 7.4, WP.IRON_DARK)
	# Cable bundles humming along both walls (the hum Hask heard) and a ceiling trough.
	for zz in [-5.55, 5.55]:
		WP.pipe(b, Vector3(-29.6, y + 5.1, zz), Vector3(-2.4, y + 5.1, zz), 0.12, WP.IRON_DARK)
		WP.pipe(b, Vector3(-29.6, y + 5.45, zz), Vector3(-2.4, y + 5.45, zz), 0.07, WP.COPPER_PIPE, false)
	b.vbox(Vector3(-16.0, y + 7.2, 0.0), Vector3(27.0, 0.3, 1.2), WP.IRON_DARK, Basis.IDENTITY, WP.OUT)
	# A hand trolley parked on the north track, a signal lever frame, rubble at the wall feet.
	var tc := Vector3(-19.5, y, -2.2)
	b.solid(tc + Vector3(0, 0.55, 0), Vector3(1.8, 0.5, 1.3), b.vary(WP.RUST, 0.05), "stone", Basis.IDENTITY, {"outline": true, "outline_w": 0.016, "no_occluder": true})
	for dx in [-0.6, 0.6]:
		for dz in [-0.45, 0.45]:
			b.vcyl(tc + Vector3(dx, 0.2, dz), 0.2, 0.08, WP.IRON_DARK, Basis(Vector3(1, 0, 0), PI * 0.5))
	b.vbox(tc + Vector3(0, 1.2, 0), Vector3(0.12, 0.9, 0.12), WP.IRON, Basis.IDENTITY, WP.OUT)
	b.vbox(tc + Vector3(0, 1.62, 0), Vector3(1.4, 0.08, 0.1), WP.IRON, Basis(Vector3(0, 0, 1), 0.25), WP.OUT)
	b.vbox(Vector3(-25.0, y + 0.6, 5.3), Vector3(1.6, 1.2, 0.5), WP.IRON_DARK, Basis.IDENTITY, WP.OUT)
	for i in 4:
		b.vbox(Vector3(-25.6 + float(i) * 0.4, y + 1.5, 5.3), Vector3(0.06, 0.8, 0.06), WP.STEEL, Basis(Vector3(1, 0, 0), -0.3 + float(i % 2) * 0.5))
	b.col_box(Vector3(-25.0, y + 0.6, 5.3), Vector3(1.6, 1.2, 0.5))
	b.pebbles(-29.5, -2.5, -5.6, -4.6, y, [WP.STONE, WP.STONE_DARK], 30)
	b.pebbles(-29.5, -2.5, 4.6, 5.6, y, [WP.STONE, WP.STONE_DARK], 30)
	# Cold, dim hanging lamps (the director may make them stutter).
	for x in [-24.0, -13.0]:
		WP.chain(b, Vector3(x, y + 7.2, 0.0), 2.4)
		WP.cage_shade(b, Vector3(x, y + 4.7, 0.0))
		Props.lamp(n, Vector3(x, y + 4.7, 0.0), {"style": "glow", "energy": 1.0, "range": 9.0, "color": WP.COLD_LAMP, "flame": WP.COLD_LAMP, "idle": 0.03})
	Props.glow_light(n, Vector3(-16.0, y + 6.5, 0.0), Color("5c6f90"), 0.35, 16.0)
	# Sign over the eyes passage and over the junction (symbols, not colour)
	WP.symbol_sign(b, Vector3(-14.5, y + 4.0, 5.95), Vector3(0, 0, -1), "bell", Color.WHITE, 0.6)
	WP.symbol_sign(b, Vector3(-2.05, y + 5.2, 0.0), Vector3(-1, 0, 0), "refuge", Color.WHITE, 0.8)


## A short dark corridor sealed by a grate: no lamp at all (the false signals knock from here).
static func _false_corridor(b: Builder, id: String, sgn: float) -> void:
	b.begin(id)
	var y := -11.0
	b.shell(id, RAIL_FLOOR.darkened(0.2), RAIL_WALL.darkened(0.25), RAIL_CEIL.darkened(0.2))
	var gz: float = Layout.FALSE_GRATES_Z[0] if sgn < 0.0 else Layout.FALSE_GRATES_Z[1]
	WP.grate(b, gz, -7.0, -4.0, y, 3.2, "x", 0.2)
	# boards nailed across, rubble behind
	for i in 3:
		b.vbox(Vector3(-5.5, y + 0.7 + float(i) * 0.9, gz - sgn * 0.12), Vector3(3.2, 0.22, 0.06), b.vary(WP.TIMBER, 0.1), Basis(Vector3(0, 0, 1), (0.12 if i % 2 == 0 else -0.1)))
	Props.rubble_pile(b, Vector3(-5.5, y, gz + sgn * 0.7), 0.9, 1.1, [WP.STONE, WP.STONE_DARK], 7, false)
	Props.rails(b, Vector3(-5.5, y, 6.0 * sgn), Vector3(-5.5, y, gz - sgn * 0.3))
	b.pebbles(-6.8, -4.2, minf(gz, 6.0 * sgn), maxf(gz, 6.0 * sgn), y, [WP.STONE_DARK], 14)


static func _junction(b: Builder, area: Node3D) -> void:
	var n := b.begin("junction")
	var y := -11.0
	b.shell("junction", RAIL_FLOOR, RAIL_WALL, RAIL_CEIL)
	WP.flag_floor(b, -1.8, 4.8, -4.3, 4.3, y, Color("4a4f57"), 1.6)
	# the rail turntable: a big flat iron disc with a rail across it
	b.vcyl(Vector3(1.4, y + 0.025, 0.0), 2.3, 0.05, WP.IRON_DARK, Basis.IDENTITY, {"segments": 24, "shadows": false})
	b.vcyl(Vector3(1.4, y + 0.04, 0.0), 2.0, 0.03, WP.IRON, Basis.IDENTITY, {"segments": 24, "shadows": false})
	Props.rails(b, Vector3(-0.9, y + 0.02, 0.0), Vector3(3.7, y + 0.02, 0.0))
	# buffer stops at the dead ends of the tracks
	for zz in [-2.2, 2.2]:
		b.solid(Vector3(4.3, y + 0.45, zz), Vector3(0.4, 0.9, 1.2), b.vary(WP.RUST, 0.06), "stone", Basis.IDENTITY, {"outline": true, "outline_w": 0.016, "no_occluder": true})
	for x in [-1.4, 4.4]:
		WP.wall_rib(b, Vector3(x, y, -4.5), Vector3(0, 0, 1), 5.5, WP.IRON_DARK)
		WP.wall_rib(b, Vector3(x, y, 4.5), Vector3(0, 0, -1), 5.5, WP.IRON_DARK)
	WP.glow_pool(b, Vector3(2.6, y, -2.6), 2.2, WP.SIGNAL_LAMP)


static func _junction_stair(b: Builder, area: Node3D) -> void:
	var n := b.begin("junction_stair")
	Geo.sloped_passage(b, "junction_stair", RAIL_FLOOR, RAIL_WALL, RAIL_CEIL, Color("7d8898"), 0.22)
	var r: Dictionary = b.rooms["junction_stair"]
	for zz in [-1.35, 1.35]:
		WP.pipe(b, Vector3(6.0, Geo.floor_y_at(r, 6.0, 0.0) + 0.95, zz), Vector3(17.0, Geo.floor_y_at(r, 17.0, 0.0) + 0.95, zz), 0.035, WP.BRASS, false)
	# warm garden light spilling up the stair from the refuge
	Props.glow_light(n, Vector3(16.0, -18.0 + 2.6, 0.0), Color("ffd89a"), 0.9, 7.0)
	Props.glow_light(n, Vector3(9.0, -12.5 + 2.4, 0.0), Color("8090b0"), 0.25, 5.0)


static func _eyes_way(b: Builder, area: Node3D) -> void:
	var n := b.begin("eyes_way")
	Geo.sloped_passage(b, "eyes_way", EYES_FLOOR, EYES_WALL, EYES_CEIL, Color("b0aab4"))
	Props.lamp(n, Vector3(-14.5, -12.0 + 2.6, 9.0), {"style": "glow", "energy": 0.55, "range": 4.5, "color": EYES_LAMP, "flame": EYES_LAMP, "idle": 0.02})


static func _eyes(b: Builder, area: Node3D) -> void:
	var n := b.begin("eyes")
	var y := -13.0
	b.shell("eyes", EYES_FLOOR, EYES_WALL, EYES_CEIL)
	WP.flag_floor(b, -19.8, -9.2, 12.2, 37.8, y, Color("9b97a0"), 1.3)
	# a long runner of darker stone down the middle
	b.vbox(Vector3(-14.5, y + 0.035, 25.0), Vector3(2.4, 0.03, 25.2), Color("6e6878"), Basis.IDENTITY, {"shadows": false})
	# pilasters between the faces (colliding, against the walls)
	for zz in [12.9, 17.8, 30.2, 36.3]:
		b.solid(Vector3(-19.7, y + 3.0, zz), Vector3(0.6, 6.0, 0.7), b.vary(EYES_WALL.darkened(0.08), 0.04), "stone", Basis.IDENTITY, {"no_occluder": true})
	for zz in [13.8, 17.8, 25.0, 29.4, 36.3]:
		b.solid(Vector3(-9.3, y + 3.0, zz), Vector3(0.6, 6.0, 0.7), b.vary(EYES_WALL.darkened(0.08), 0.04), "stone", Basis.IDENTITY, {"no_occluder": true})
	# carved faces, eyes shut, each over an iron hook with a dark lantern (the west great face is the door)
	for zz in [15.8, 21.8, 33.2]:
		WP.face_relief(b, Vector3(-19.72, y + 3.4, zz), Vector3(1, 0, 0), 1.05, true)
	for zz in [15.8, 27.2, 36.9]:
		WP.face_relief(b, Vector3(-9.28, y + 3.4, zz), Vector3(-1, 0, 0), 1.05, true)
	# the wrong door: the sealed cell behind the east grate (nobody, and no companion, can get in)
	var cx0 := -9.0
	var cx1 := -5.5
	var cz0 := 19.6
	var cz1 := 23.4
	b.floor_rect(cx0, cx1, cz0, cz1, y, Color("35323a"))
	b.solid(Vector3((cx0 + cx1) * 0.5, y + 3.3, (cz0 + cz1) * 0.5), Vector3(cx1 - cx0 + 1.0, 0.6, cz1 - cz0 + 2.0), Color("2a2830"))
	b.solid(Vector3(cx1 + 0.5, y + 1.6, (cz0 + cz1) * 0.5), Vector3(1.0, 3.8, cz1 - cz0 + 2.0), Color("2e2b33"))
	b.solid(Vector3((cx0 + cx1) * 0.5, y + 1.6, cz0 - 0.5), Vector3(cx1 - cx0, 3.8, 1.0), Color("2e2b33"))
	b.solid(Vector3((cx0 + cx1) * 0.5, y + 1.6, cz1 + 0.5), Vector3(cx1 - cx0, 3.8, 1.0), Color("2e2b33"))
	WP.grate(b, -9.05, 20.0, 23.0, y, 3.0, "z", 0.19)
	b.vbox(Vector3(-9.05, y + 3.1, 21.5), Vector3(0.3, 0.3, 3.6), WP.IRON_DARK, Basis.IDENTITY, WP.OUT)
	# the real lamp beside the grate lights the hall floor in front of it (the cell floor stays dark)
	Props.lamp(n, Vector3(-9.4, y + 2.3, 18.3), {"style": "wall", "energy": 1.0, "range": 5.5, "color": WP.WARM_LAMP, "yaw": -90.0})
	WP.glow_pool(b, Vector3(-10.4, y, 18.6), 1.6)
	# the misplaced lantern's empty hook on the great face (door) is part of the door node; a plaque by the entrance
	b.vbox(Vector3(-19.93, y + 1.3, 14.4), Vector3(0.08, 0.8, 1.2), Color("c8c0b0"), Basis.IDENTITY, WP.OUT)
	# candle stubs in wall niches (tiny glows, no lights: the hall is dim)
	for zz in [19.9, 31.7]:
		for dz in [-0.25, 0.0, 0.3]:
			b.vcyl(Vector3(-19.55, y + 1.05, zz + dz), 0.05, 0.18 + absf(dz) * 0.3, Color("efe6cf"), Basis.IDENTITY, {"segments": 6, "shadows": false})
			b.vglow(Builder.unit_sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3(0.05, 0.08, 0.05)), Vector3(-19.55, y + 1.2 + absf(dz) * 0.3, zz + dz)), Color("ffd08a"), 2.2)
	# soft cold-violet wall lamps
	Props.lamp(n, Vector3(-19.5, y + 4.2, 24.0), {"style": "wall", "energy": 0.8, "range": 7.5, "color": EYES_LAMP, "flame": EYES_LAMP, "idle": 0.02, "yaw": 90.0})
	Props.lamp(n, Vector3(-9.5, y + 4.2, 32.8), {"style": "wall", "energy": 0.8, "range": 7.0, "color": EYES_LAMP, "flame": EYES_LAMP, "idle": 0.02, "yaw": -90.0})
	Props.glow_light(n, Vector3(-14.5, y + 5.4, 25.0), Color("6a6488"), 0.3, 14.0)


static func _eyes_route(b: Builder, area: Node3D) -> void:
	var n := b.begin("eyes_route")
	var y := -13.0
	b.shell("eyes_route", EYES_FLOOR.darkened(0.1), EYES_WALL.darkened(0.1), EYES_CEIL)
	WP.bench(b, Vector3(-25.5, y, 25.7), 2.4, "x", WP.TIMBER)
	for dz in [-0.3, 0.0, 0.35]:
		b.vcyl(Vector3(-26.6, y + 0.6, 28.4 + dz), 0.05, 0.22, Color("efe6cf"), Basis.IDENTITY, {"segments": 6, "shadows": false})
		b.vglow(Builder.unit_sphere(), Transform3D(Basis.IDENTITY.scaled(Vector3(0.05, 0.08, 0.05)), Vector3(-26.6, y + 0.78, 28.4 + dz)), Color("ffd08a"), 2.2)
	b.solid(Vector3(-26.6, y + 0.25, 28.4), Vector3(0.6, 0.5, 1.2), Color("6e6878"), "stone", Basis.IDENTITY, {"no_occluder": true})
	WP.face_relief(b, Vector3(-26.9, y + 2.2, 27.5), Vector3(1, 0, 0), 0.7, false)
	Props.glow_light(n, Vector3(-24.0, y + 2.4, 27.5), Color("ffd6a0"), 0.7, 5.5)


static func _bells_way(b: Builder, area: Node3D) -> void:
	var n := b.begin("bells_way")
	Geo.sloped_passage(b, "bells_way", EYES_FLOOR, EYES_WALL, EYES_CEIL, Color("b0aab4"))
	var r: Dictionary = b.rooms["bells_way"]
	WP.pipe(b, Vector3(-8.0, Geo.floor_y_at(r, -8.0, 0.0) + 2.8, 31.3), Vector3(1.0, Geo.floor_y_at(r, 1.0, 0.0) + 2.8, 31.3), 0.1, WP.BRONZE)
	Props.lamp(n, Vector3(-3.5, Geo.floor_y_at(r, -3.5, 0.0) + 2.7, 32.75), {"style": "glow", "energy": 0.6, "range": 5.0, "color": Color("ffc890"), "flame": Color("ffc890"), "idle": 0.03})
