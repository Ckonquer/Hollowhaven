extends RefCounted
## Rooms 1-2 of the Hushed Works: the Service Landing (low, warm, safe: stone flags, timber, one big real
## lantern whose light pools on the floor - the first "true light" lesson; the stair back up to the Bellhouse)
## and the Tool Lockers (a longer, colder, blue-grey room of painted iron lockers under caged lamps; the taught
## Hollow Drudge fight in the open middle, the service diagram on the east wall, an optional note in a locker).
## Geometry comes from data/works_layout.gd via the shared Below builder (the area passes it in).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Builder := preload("res://src/world/below/below_builder.gd")
const Props := preload("res://src/world/below/below_props.gd")
const WP := preload("res://src/world/works/works_props.gd")
const Geo := preload("res://src/world/works/works_geo.gd")

const LANDING_FLOOR := Color("5b5650")
const LANDING_WALL := Color("6b645c")
const LANDING_CEIL := Color("3d3833")
const LOCKER_FLOOR := Color("4c525c")
const LOCKER_WALL := Color("56606e")
const LOCKER_CEIL := Color("30353e")


static func build(b: Builder, area: Node3D) -> void:
	_landing(b, area)
	_landing_stair(b, area)
	_landing_way(b, area)
	_lockers(b, area)
	_lockers_way(b, area)


static func _landing(b: Builder, area: Node3D) -> void:
	var n := b.begin("landing")
	var y := -6.0
	b.shell("landing", LANDING_FLOOR, LANDING_WALL, LANDING_CEIL)
	WP.flag_floor(b, -75.8, -64.2, -5.8, 5.8, y, Color("67615a"), 1.45)
	# Heavy timber ceiling beams and iron wall ribs: a low, sheltered service room.
	for x in [-73.0, -69.5, -66.0]:
		b.vbox(Vector3(x, y + 4.35, 0.0), Vector3(0.4, 0.4, 12.0), b.vary(WP.TIMBER, 0.06), Basis.IDENTITY, WP.OUT)
	for x in [-74.5, -70.0, -65.5]:
		WP.wall_rib(b, Vector3(x, y, -6.0), Vector3(0, 0, 1), 4.6, WP.IRON)
		WP.wall_rib(b, Vector3(x, y, 6.0), Vector3(0, 0, -1), 4.6, WP.IRON)
	# Supplies along the north and south walls (never on the walk line z ~ 0).
	WP.supplies(b, Vector3(-75.0, y, -5.1), 4.0)
	WP.supplies(b, Vector3(-66.2, y, 5.1), 178.0)
	Props.barrel(b, Vector3(-65.2, y, -5.2))
	Props.barrel(b, Vector3(-66.1, y, -5.3), 0.32, 0.8)
	Props.rope_coil(b, Vector3(-74.6, y, 4.9))
	Props.pickaxe_lean(b, Vector3(-75.75, y, 3.6), 90.0)
	Props.table(b, Vector3(-71.2, y, 5.2), 0.0, 1.6, 0.7)
	Props.papers(b, Vector3(-71.4, y + 0.84, 5.2), -8.0)
	# A tool rack on the south wall and a service bell pull by the stair (story dressing)
	b.vbox(Vector3(-68.5, y + 1.6, 5.9), Vector3(2.2, 0.12, 0.1), WP.TIMBER, Basis.IDENTITY, WP.OUT)
	for i in 5:
		b.vbox(Vector3(-69.4 + float(i) * 0.45, y + 1.2, 5.8), Vector3(0.05, 0.9, 0.05), WP.STEEL, Basis(Vector3(1, 0, 0), 0.08))
	WP.symbol_sign(b, Vector3(-64.1, y + 3.7, -3.2), Vector3(-1, 0, 0), "refuge", Color.WHITE, 0.7)
	# Timber-lined lower walls, a shelf of tins, pinned notices over the table and the foreman's jacket on its
	# hook: a warm, lived-in service room like Chapter One's Below (VISUAL_BUGS IN-15). Visual only.
	WP.plank_wainscot(b, Vector3(-75.9, y, -6.0), Vector3(-64.1, y, -6.0), Vector3(0, 0, 1), y, 1.25, WP.TIMBER)
	WP.plank_wainscot(b, Vector3(-75.9, y, 6.0), Vector3(-64.1, y, 6.0), Vector3(0, 0, -1), y, 1.25, WP.TIMBER)
	WP.plank_wainscot(b, Vector3(-76.0, y, -5.9), Vector3(-76.0, y, 5.9), Vector3(1, 0, 0), y, 1.25, WP.TIMBER, [[-1.8, 1.8]])
	WP.plank_wainscot(b, Vector3(-64.0, y, -5.9), Vector3(-64.0, y, 5.9), Vector3(-1, 0, 0), y, 1.25, WP.TIMBER, [[-1.6, 1.6]])
	WP.wall_shelf(b, Vector3(-67.9, y + 1.75, -6.0), Vector3(0, 0, 1), 1.8)
	WP.notice(b, Vector3(-71.7, y + 1.95, 5.99), Vector3(0, 0, -1), 0.44, 0.58, 0.05)
	WP.notice(b, Vector3(-71.05, y + 2.05, 5.99), Vector3(0, 0, -1), 0.36, 0.46, -0.08)
	WP.work_jacket(b, Vector3(-75.97, y + 1.95, -3.2), Vector3(1, 0, 0), Color("6a5a44"))
	# THE REAL LANTERN: a big warm lantern hung low on a chain; its light pools on the flagstones below.
	WP.chain(b, Vector3(-68.6, y + 4.6, 1.4), 1.6)
	Props.lamp(n, Vector3(-68.6, y + 3.0, 1.4), {"style": "hanging", "hang": 0.1, "energy": 2.3, "range": 9.5,
		"shadow": true, "color": WP.WARM_LAMP, "idle": 0.04})
	WP.glow_pool(b, Vector3(-68.6, y, 1.4), 2.6)
	Props.lamp(n, Vector3(-64.5, y + 2.4, 3.8), {"style": "wall", "energy": 0.8, "range": 5.0, "color": WP.WARM_LAMP, "yaw": -90.0})


static func _landing_stair(b: Builder, area: Node3D) -> void:
	var n := b.begin("landing_stair")
	var y := -6.0
	b.shell("landing_stair", LANDING_FLOOR, LANDING_WALL, LANDING_CEIL)
	# The Bellhouse stair rises west into the rock (the exit stands at its foot; the steps are solid): at the
	# top the service gate stands open (the Foreman's Key opened it from the Bellhouse side) and a little
	# daylight spills down.
	var steps := 11
	for i in steps:
		var x0 := -77.2 - float(i) * 0.26
		var top := y + float(i + 1) * 0.24
		b.vbox(Vector3(x0 - 0.13, (y - 0.2 + top) * 0.5, 0.0), Vector3(0.28, top - y + 0.2, 3.5), b.vary(Color("6f685f"), 0.05))
		b.vbox(Vector3(x0 - 0.02, top - 0.03, 0.0), Vector3(0.1, 0.08, 3.4), Color("8d857a"), Basis.IDENTITY, {"shadows": false})
	b.col_box(Vector3(-78.6, y + 1.4, 0.0), Vector3(2.8, 2.8, 3.6))
	var gy := y + float(steps) * 0.24
	b.vbox(Vector3(-79.9, gy + 1.5, -1.3), Vector3(0.12, 3.0, 0.12), WP.IRON, Basis.IDENTITY, WP.OUT)
	b.vbox(Vector3(-79.9, gy + 1.5, 1.3), Vector3(0.12, 3.0, 0.12), WP.IRON, Basis.IDENTITY, WP.OUT)
	WP.grate(b, -79.95, -1.6, -1.35, gy, 2.4, "z")
	var sky := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.6, 2.2)
	sky.mesh = pm
	sky.material_override = Mat.glow(Color("ffd9a8"), 1.2)
	sky.rotation_degrees = Vector3(0, 0, -90)
	n.add_child(sky)
	sky.position = Vector3(-79.98, gy + 1.3, 0.0)
	Props.glow_light(n, Vector3(-78.6, gy + 1.6, 0.0), Color("ffd9a8"), 0.9, 6.0)
	for zz in [-1.55, 1.55]:
		WP.pipe(b, Vector3(-77.0, y + 1.0, zz), Vector3(-79.9, gy + 1.0, zz), 0.035, WP.IRON_DARK, false)


static func _landing_way(b: Builder, area: Node3D) -> void:
	b.begin("landing_way")
	Geo.sloped_passage(b, "landing_way", LANDING_FLOOR, LANDING_WALL, LANDING_CEIL, Color("8d857a"))
	WP.pipe(b, Vector3(-63.0, -3.6, -1.3), Vector3(-57.0, -4.6, -1.3), 0.09)
	for x in [-62.0, -58.5]:
		Props.timber_frame(b, x, -1.6, 1.6, Geo.floor_y_at(b.rooms["landing_way"], x, 0.0), 3.1, "z")


static func _lockers(b: Builder, area: Node3D) -> void:
	var n := b.begin("lockers")
	var y := -7.0
	b.shell("lockers", LOCKER_FLOOR, LOCKER_WALL, LOCKER_CEIL)
	WP.flag_floor(b, -55.8, -38.2, -7.8, 7.8, y, Color("555c66"), 2.0)
	# Rows of painted iron lockers along the north and south walls (a few doors ajar).
	var k := 0
	for x in range(-50, -38):
		var xf := float(x) + 0.45
		WP.locker(b, Vector3(xf, y, -7.62), Vector3(0, 0, 1), k % 5 == 2, WP.PLATE if k % 3 != 1 else WP.PLATE_DARK)
		k += 1
	for x in range(-55, -38):
		var xf := float(x) + 0.45
		if absf(xf + 45.55) < 0.1:
			continue      # the open locker with Wren's note (built below)
		WP.locker(b, Vector3(xf, y, 7.62), Vector3(0, 0, -1), k % 4 == 1, WP.PLATE if k % 3 != 2 else WP.PLATE_DARK)
		k += 1
	WP.locker(b, Vector3(-45.55, y, 7.62), Vector3(0, 0, -1), true, Color("6a7a88"))
	# Benches (low, along the lockers: the middle stays open for the fight)
	WP.bench(b, Vector3(-46.0, y, -6.3), 5.0, "x")
	WP.bench(b, Vector3(-43.5, y, 6.3), 4.0, "x")
	# Pipes and cable trays under the ceiling; caged cold lamps.
	WP.pipe(b, Vector3(-55.5, y + 4.4, -6.8), Vector3(-38.5, y + 4.4, -6.8), 0.14, WP.STEEL)
	WP.pipe(b, Vector3(-55.5, y + 4.1, 6.9), Vector3(-38.5, y + 4.1, 6.9), 0.1, WP.COPPER_PIPE)
	for x in [-50.0, -44.0, -39.5]:
		b.vbox(Vector3(x, y + 4.85, 0.0), Vector3(0.3, 0.3, 16.0), b.vary(WP.IRON, 0.05), Basis.IDENTITY, WP.OUT)
	for p in [Vector3(-49.0, y + 4.2, 0.0), Vector3(-42.5, y + 4.2, -2.5)]:
		WP.cage_shade(b, p)
		Props.lamp(n, p, {"style": "glow", "energy": 1.25, "range": 8.5, "color": WP.COLD_LAMP, "flame": WP.COLD_LAMP, "idle": 0.02})
	# One broken caged lamp that sputters (a flicker light)
	WP.cage_shade(b, Vector3(-42.5, y + 4.2, 3.5))
	Props.lamp(n, Vector3(-42.5, y + 4.2, 3.5), {"style": "glow", "energy": 0.5, "range": 5.0, "color": WP.COLD_LAMP, "flame": WP.COLD_LAMP, "idle": 0.25})
	# THE SERVICE DIAGRAM: a big board on the east wall (north of the door): rooms as discs, lines as bars.
	var bx := -38.08
	var bc := Vector3(bx, y + 2.0, -4.9)
	b.vbox(bc, Vector3(0.1, 2.0, 3.4), WP.TIMBER, Basis.IDENTITY, WP.OUT)
	b.vbox(bc + Vector3(-0.06, 0, 0), Vector3(0.02, 1.8, 3.2), Color("e8dcc0"), Basis.IDENTITY, {"shadows": false})
	var ink := Color("3b2f35")
	var nodes := [Vector3(0, 0.6, 1.3), Vector3(0, 0.6, 0.5), Vector3(0, 0.6, -0.3), Vector3(0, -0.1, -0.9),
		Vector3(0, -0.7, -1.3), Vector3(0, -0.7, -0.5), Vector3(0, -0.7, 0.3)]
	for i in nodes.size():
		var p: Vector3 = bc + Vector3(-0.08, 0, 0) + nodes[i]
		b.vcyl(p, 0.13 if i != 3 else 0.2, 0.02, ink if i != 3 else Color("5f9a45"), Basis(Vector3(0, 0, 1), PI * 0.5), {"shadows": false})
	for pair in [[0, 1], [1, 2], [2, 3], [3, 4], [3, 5], [3, 6]]:
		var pa: Vector3 = bc + Vector3(-0.08, 0, 0) + nodes[pair[0]]
		var pb: Vector3 = bc + Vector3(-0.08, 0, 0) + nodes[pair[1]]
		var d := pb - pa
		b.vbox((pa + pb) * 0.5, Vector3(0.015, 0.035, d.length()), ink, Basis.looking_at(d.normalized(), Vector3.RIGHT), {"shadows": false})
	for i in 3:   # three line colours under the Refuge: water / bell / light
		b.vbox(bc + Vector3(-0.08, -0.4, -0.95 + float(i) * 0.25), Vector3(0.015, 0.12, 0.16), [Color("5fa8d0"), Color("c8843e"), Color("e8c860")][i], Basis.IDENTITY, {"shadows": false})
	Props.lamp(n, Vector3(-38.6, y + 3.4, -4.9), {"style": "wall", "energy": 0.7, "range": 4.0, "color": WP.WARM_LAMP, "yaw": -90.0})
	WP.symbol_sign(b, Vector3(-38.1, y + 3.7, 2.4), Vector3(-1, 0, 0), "up", Color.WHITE, 0.6)
	# Riveted plate seams on the painted iron walls, the miners' jackets and hard hats on hooks in the free
	# north-west corner, a shelf and shift notices by the west door (VISUAL_BUGS IN-15). Visual only, all
	# against the walls: the middle stays open for the Drudge fight.
	WP.plate_seams(b, Vector3(-55.9, y, -8.0), Vector3(-38.1, y, -8.0), Vector3(0, 0, 1), y, [2.3, 3.7], 5.0, 2.4)
	WP.plate_seams(b, Vector3(-55.9, y, 8.0), Vector3(-38.1, y, 8.0), Vector3(0, 0, -1), y, [2.3, 3.7], 5.0, 2.4)
	WP.plate_seams(b, Vector3(-56.0, y, -7.9), Vector3(-56.0, y, 7.9), Vector3(1, 0, 0), y, [2.3, 3.7], 5.0, 2.4, WP.PLATE_DARK, [[-1.6, 1.6]])
	WP.plate_seams(b, Vector3(-38.0, y, -7.9), Vector3(-38.0, y, 7.9), Vector3(-1, 0, 0), y, [3.7], 5.0, 2.4, WP.PLATE_DARK, [[-6.7, -3.1], [-1.6, 1.6]])
	for i in 3:
		WP.work_jacket(b, Vector3(-54.9 + float(i) * 1.15, y + 1.95, -7.98), Vector3(0, 0, 1), [Color("4a5a6a"), Color("6a5a44"), Color("5a6a58")][i], i != 1)
	WP.wall_shelf(b, Vector3(-55.98, y + 1.7, -5.2), Vector3(1, 0, 0), 1.6)
	WP.notice(b, Vector3(-55.98, y + 1.75, 3.4), Vector3(1, 0, 0), 0.48, 0.62, -0.04)
	WP.notice(b, Vector3(-55.98, y + 1.9, 4.2), Vector3(1, 0, 0), 0.36, 0.44, 0.07)


static func _lockers_way(b: Builder, area: Node3D) -> void:
	var n := b.begin("lockers_way")
	Geo.sloped_passage(b, "lockers_way", LOCKER_FLOOR, LOCKER_WALL, LOCKER_CEIL, Color("7d8898"))
	# iron handrails and a cold lamp at the bottom
	var r: Dictionary = b.rooms["lockers_way"]
	for zz in [-1.35, 1.35]:
		var a := Vector3(-37.0, Geo.floor_y_at(r, -37.0, 0.0) + 0.95, zz)
		var c := Vector3(-31.0, Geo.floor_y_at(r, -31.0, 0.0) + 0.95, zz)
		WP.pipe(b, a, c, 0.035, WP.IRON_DARK, false)
	Props.lamp(n, Vector3(-31.5, -11.0 + 2.9, 0.0), {"style": "glow", "energy": 0.6, "range": 4.5, "color": WP.COLD_LAMP, "flame": WP.COLD_LAMP, "idle": 0.03})
