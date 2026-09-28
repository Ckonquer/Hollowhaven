extends Node3D
## Lanternwake Commons (MP §9): the safe festival ground where the Reach begins. Built around
## Reach.COMMONS: a central lantern pole with strings of warm bulbs, seven festival stalls with striped
## awnings and bunting, tables with candles and sweets, hay-bale seats, the pumpkin arch over the arrival
## road, copper leaves drifting down, the empty cottage lot (the optional outpost: nothing solid inside
## Reach.OUTPOST_BUILD_AREA), and three interactables:
##   * the festival map board: MP §17 line, flag ch2_read_festival_map (+ lore lore_ch2_festival_board);
##     the three branch roads are Reach.MAP_ROUTES for the map
##   * the festival mirror: "Change your look" -> Game.open_panel("wardrobe")
##   * the cottage-lot sign (flavour)
## The Commons arrival arch itself is a lantern_arch built by reach_world.gd (Reach.ARCHES["commons"]).
## The seed pouch is the quest layer's rw_ch2_commons reward: nothing is granted here.

const Reach := preload("res://data/hallowmere_layout.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const Flora := preload("res://src/world/reach/reach_flora.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Interactable := preload("res://src/world/reach/reach_interactable.gd")
const LoreData := preload("res://data/lore_ch2_reach.gd")

const MAP_FLAG := "ch2_read_festival_map"
const BOARD_LORE := "lore_ch2_festival_board"
const BOARD_SPEAKER := "Festival Board"

var terrain: RefCounted
var board: Node3D
var mirror: Node3D
var lot_sign: Node3D
var bulb_material: Material
var lights: Array = []           # OmniLight3D (warmer at night)
var _body: StaticBody3D
var _bulbs: Array = []           # Transform3D of every string-light bulb
var _wires := NodeVisuals.Merger.new()
var _pumpkins: Array = [[], [], [], []]


func _ready() -> void:
	name = "Commons"
	_body = StaticBody3D.new()
	_body.name = "CommonsCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "wood")
	add_child(_body)
	bulb_material = Props.bulb_mat()
	_build_pole()
	_build_stalls()
	_build_furniture()
	_build_pumpkin_arch()
	_build_arrival()
	_build_lot()
	_build_board()
	_build_mirror()
	_finish_batches()
	_build_leaves()


func _v3(p: Vector2, dy: float = 0.0) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.y) + dy, p.y)


func _mi(mesh: Mesh, mat: Material, xf: Transform3D, vis: float = 120.0, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = xf
	if vis > 0.0:
		mi.visibility_range_end = vis
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _string(a: Vector3, b: Vector3, sag: float, bulbs: int) -> void:
	var pts := Props.catenary(a, b, sag, 10)
	Props.wire(_wires, pts, 0.012, Color("3b2a22"))
	for i in bulbs:
		var t := (float(i) + 0.5) / float(bulbs)
		var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * sag + 0.07, 0)
		_bulbs.append(Transform3D(Basis(), p))


# --- The central lantern pole and its strings of light -----------------------------------------------

func _build_pole() -> void:
	var c: Vector2 = Reach.COMMONS["pole"]
	var base := _v3(c, -0.05)
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._cyl(0.14, 0.2, 5.8, 10), Transform3D(Basis(), Vector3(0, 2.9, 0)), Palette.WOOD_DARK)
	m.add(Kit.blob_mesh(0.55, 7651, 0.25, 0.45, 1), Transform3D(Basis(), Vector3(0, 0.1, 0)), Palette.STONE)
	m.add(NodeVisuals._cyl(0.62, 0.62, 0.1, 16), Transform3D(Basis(), Vector3(0, 5.5, 0)), Palette.WOOD)
	m.add(NodeVisuals._cyl(0.0, 0.3, 0.5, 10), Transform3D(Basis(), Vector3(0, 6.05, 0)), Props.CLOTH["plum"])
	for i in 6:
		var a := TAU * float(i) / 6.0
		m.add(NodeVisuals._box(Vector3(0.08, 0.9, 0.02)), Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 0.6, 5.0, sin(a) * 0.6)), [Props.CLOTH["pumpkin"], Props.CLOTH["cream"], Props.CLOTH["rose"]][i % 3])
	var root := Node3D.new()
	root.name = "LanternPole"
	add_child(root)
	root.position = base
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.wood_mat()
	root.add_child(mi)
	var lamp := MeshInstance3D.new()
	lamp.mesh = Props.lantern_glass_mesh()
	lamp.material_override = Mat.glow(Color("ffc66e"), 2.4)
	lamp.scale = Vector3(2.2, 2.0, 2.2)
	lamp.position = Vector3(0, 4.9, 0)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lamp)
	Props.cyl_col(_body, base, 0.26, 5.8)
	var light := OmniLight3D.new()
	light.light_color = Color("ffc07a")
	light.light_energy = 1.2
	light.omni_range = 15.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 15.0
	light.position = base + Vector3(0, 4.6, 0)
	add_child(light)
	lights.append(light)
	var top := base + Vector3(0, 5.45, 0)
	for pp in Reach.COMMONS["light_posts"]:
		var p: Vector2 = pp
		var pb := _v3(p, -0.03)
		var pm := NodeVisuals.Merger.new()
		pm.add(NodeVisuals._cyl(0.07, 0.09, 3.3, 8), Transform3D(Basis(), Vector3(0, 1.65, 0)), Palette.WOOD_DARK)
		pm.add(Kit.blob_mesh(0.2, 7652, 0.3, 0.4, 1), Transform3D(Basis(), Vector3(0, 0.05, 0)), Palette.STONE)
		pm.add(Kit.blob_mesh(0.09, 7653, 0.1, 0.7, 1), Transform3D(Basis(), Vector3(0, 3.35, 0)), Props.CLOTH["pumpkin"])
		_mi(pm.commit(), Props.wood_mat(), Transform3D(Basis(), pb))
		Props.cyl_col(_body, pb, 0.12, 3.3)
		_string(top, pb + Vector3(0, 3.2, 0), 0.55, 14)
	# the ring between the posts
	var ring: Array = Reach.COMMONS["light_posts"]
	for i in ring.size():
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		_string(_v3(a, 3.2), _v3(b, 3.2), 0.4, 10)


# --- Stalls ---------------------------------------------------------------------------------------------

func _build_stalls() -> void:
	var c: Vector2 = Reach.COMMONS["pole"]
	var goods_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.35, "specular": 0.25}), 0.012)
	for s in Reach.COMMONS["stalls"]:
		var p: Vector2 = s[0]
		var kind := String(s[1])
		var yaw := Props.face_yaw(p, c)
		var xf := Transform3D(Basis(Vector3.UP, yaw), _v3(p, -0.04))
		var stall := _mi(Props.stall_mesh(kind), Props.wood_mat(), xf, 150.0)
		stall.name = "Stall_" + kind
		_mi(Props.goods_mesh(kind), goods_mat, xf, 70.0, false)
		for spot in Props.pumpkin_spots(kind):
			_pumpkins[int(spot[0])].append(xf * (spot[1] as Transform3D))
		# counter + back shelf are solid; the front is open to walk up to
		Props.box_col(_body, xf * Transform3D(Basis(), Vector3(0, 0.55, 0.52)), Vector3(3.2, 1.1, 0.75))
		for sx in [-1.0, 1.0]:
			Props.box_col(_body, xf * Transform3D(Basis(), Vector3(float(sx) * 1.5, 1.45, -0.75)), Vector3(0.16, 2.9, 0.16))
		# bunting between the front posts and bulbs along the awning edge
		var a := xf * Vector3(-1.5, 2.5, 0.8)
		var b := xf * Vector3(1.5, 2.5, 0.8)
		_string(a, b, 0.12, 7)
		var name_pos := xf * Vector3(0, 3.28, -0.35)
		var l := Props.label(self, _stall_name(kind), name_pos, 30, Color("3b2a22"), yaw, 0.004)
		l.width = 380.0


static func _stall_name(kind: String) -> String:
	match kind:
		"costumes":
			return "Costumes"
		"pumpkins":
			return "Pumpkins"
		"lanterns":
			return "Lanterns"
		"sweets":
			return "Sweets"
		"candles":
			return "Candles"
		"ribbons":
			return "Ribbons"
		"roseberries":
			return "Roseberries"
	return kind.capitalize()


func _build_furniture() -> void:
	var c: Vector2 = Reach.COMMONS["pole"]
	for t in Reach.COMMONS["tables"]:
		var p: Vector2 = t[0]
		var yaw := Props.face_yaw(p, c) + float(t[1])
		var xf := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), _v3(p, -0.02))
		_mi(Props.table_mesh(), Props.wood_mat(), xf, 90.0)
		Props.box_col(_body, xf * Transform3D(Basis(), Vector3(0, 0.45, 0)), Vector3(2.4, 0.9, 0.9))
		for sgn in [-1.0, 1.0]:
			var bx := xf * Transform3D(Basis(Vector3.UP, 0.0 if sgn < 0.0 else PI), Vector3(0, 0, float(sgn) * 0.95))
			_mi(Props.bench_mesh(), Props.wood_mat(), bx, 80.0)
			Props.box_col(_body, bx * Transform3D(Basis(), Vector3(0, 0.25, 0)), Vector3(1.8, 0.5, 0.45))
	for bp in Reach.COMMONS["bales"]:
		var p: Vector2 = bp
		var xf := Transform3D(Basis(Vector3.UP, Props.face_yaw(p, c) + PI * 0.5), _v3(p, -0.05))
		_mi(Props.hay_mesh(), Props.wood_mat(), xf, 90.0)
		Props.box_col(_body, xf * Transform3D(Basis(), Vector3(0, 0.35, 0)), Vector3(1.2, 0.7, 0.8))
		_pumpkins[int(absf(p.x)) % 4].append(Transform3D(Basis(Vector3.UP, p.y).scaled(Vector3.ONE * 0.55), xf * Vector3(0.25, 0.78, 0.0)))
	# pumpkin piles around the green's edge (never on the paths)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777
	for i in 26:
		var a := rng.randf() * TAU
		var r := rng.randf_range(16.5, 22.0)
		var p := c + Vector2(cos(a), sin(a)) * r
		var v := rng.randi() % 4
		var s := rng.randf_range(0.7, 1.4)
		if terrain.path_at(p.x, p.y) > 0.05 or p.distance_to(Reach.OUTPOST_BUILD_AREA["center"]) < 9.5:
			continue
		var blocked := false
		for st in Reach.COMMONS["stalls"]:
			if p.distance_to(st[0]) < 2.8:
				blocked = true
		if blocked:
			continue
		_pumpkins[v].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), _v3(p, -0.04)))


# --- The pumpkin arch over the arrival road ------------------------------------------------------------

func _build_pumpkin_arch() -> void:
	var p: Vector2 = Reach.COMMONS["pumpkin_arch"]
	var base := _v3(p, -0.05)
	var m := NodeVisuals.Merger.new()
	var half := 2.7
	for sx in [-1.0, 1.0]:
		m.add(NodeVisuals._box(Vector3(0.36, 4.3, 0.36)), Transform3D(Basis(), Vector3(float(sx) * half, 2.15, 0)), Palette.WOOD_DARK)
		m.add(Kit.blob_mesh(0.45, 7661 + int(sx), 0.3, 0.45, 1), Transform3D(Basis(), Vector3(float(sx) * half, 0.1, 0)), Palette.STONE)
	var seg := 12
	var arc := func(t: float) -> Vector3:
		var a := PI * t
		return Vector3(-cos(a) * half, 4.3 + sin(a) * 1.2, 0)
	for i in seg:
		var p0: Vector3 = arc.call(float(i) / float(seg))
		var p1: Vector3 = arc.call(float(i + 1) / float(seg))
		var d := p1 - p0
		m.add(NodeVisuals._box(Vector3(d.length() + 0.08, 0.34, 0.4)), Transform3D(Basis(Vector3.BACK, atan2(d.y, d.x)), (p0 + p1) * 0.5), Palette.WOOD)
	# a banner under the arc
	m.add(NodeVisuals._box(Vector3(3.6, 0.62, 0.05)), Transform3D(Basis(), Vector3(0, 4.28, 0.22)), Props.CLOTH["plum"])
	m.add(NodeVisuals._box(Vector3(3.7, 0.08, 0.07)), Transform3D(Basis(), Vector3(0, 4.62, 0.22)), Palette.WOOD_DARK)
	var root := Node3D.new()
	root.name = "PumpkinArch"
	add_child(root)
	root.position = base
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.wood_mat()
	root.add_child(mi)
	for side in [0, 1]:
		var z := 0.25 if side == 0 else 0.19
		var l := Props.label(root, "Lanternwake", Vector3(0, 4.28, z), 72, Color("f7e2b0"), 0.0 if side == 0 else PI, 0.0055)
		l.outline_modulate = Color("3b2a22")
	# pumpkins stacked up both posts and along the arc
	for sx in [-1.0, 1.0]:
		for k in 4:
			var s := 0.9 - float(k) * 0.12
			_pumpkins[k % 4].append(Transform3D(Basis(Vector3.UP, float(k)).scaled(Vector3(s, s, s)), base + Vector3(float(sx) * (half + 0.62), float(k) * 0.02, 0.35 - float(k) * 0.3)))
	for i in 9:
		var t := (float(i) + 0.5) / 9.0
		var q: Vector3 = arc.call(t)
		_pumpkins[i % 4].append(Transform3D(Basis(Vector3.UP, float(i)).scaled(Vector3.ONE * 0.5), base + q + Vector3(0, 0.12, 0)))
	_string(base + Vector3(-half, 3.9, 0.3), base + Vector3(half, 3.9, 0.3), 0.3, 9)
	for sx in [-1.0, 1.0]:
		Props.box_col(_body, Transform3D(Basis(), base + Vector3(float(sx) * half, 2.15, 0)), Vector3(0.4, 4.3, 0.4))


## Frame the first view: lantern posts either side of the arrival, pumpkins, a welcome bench.
func _build_arrival() -> void:
	var p: Vector2 = Reach.POINTS["waygate_arrival"]
	for sx in [-1.0, 1.0]:
		var q := p + Vector2(float(sx) * 3.4, -1.6)
		var root := Node3D.new()
		add_child(root)
		root.position = _v3(q, -0.03)
		root.rotation.y = 0.0 if sx > 0.0 else PI
		var mi := MeshInstance3D.new()
		mi.mesh = Props.road_post_mesh()
		mi.material_override = Props.wood_mat()
		root.add_child(mi)
		var glass := MeshInstance3D.new()
		glass.mesh = Props.lantern_glass_mesh()
		glass.material_override = Mat.glow(Color("ffc66e"), 2.2)
		glass.position = Props.GLASS_POS
		root.add_child(glass)
		Props.cyl_col(_body, root.position, 0.12, 2.4)
		for k in 3:
			_pumpkins[(k + int(sx + 1.0)) % 4].append(Transform3D(Basis(Vector3.UP, float(k)).scaled(Vector3.ONE * (0.9 - float(k) * 0.15)), _v3(q + Vector2(float(sx) * (0.7 + float(k) * 0.55), 0.5 + float(k) * 0.3), -0.04)))
	# a welcome bench beside the arrival, turned toward the festival below
	var bq := p + Vector2(-4.6, 1.0)
	var bxf := Transform3D(Basis(Vector3.UP, Props.face_yaw(bq, Reach.COMMONS["pole"])), _v3(bq, -0.03))
	var bench := _mi(Props.bench_mesh(), Props.wood_mat(), bxf, 80.0)
	bench.name = "WelcomeBench"
	Props.box_col(_body, bxf * Transform3D(Basis(), Vector3(0, 0.25, 0)), Vector3(1.8, 0.5, 0.45))
	_pumpkins[2].append(Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 0.6), bxf * Vector3(1.25, 0.0, 0.1)))
	var light := OmniLight3D.new()
	light.light_color = Color("ffc07a")
	light.light_energy = 0.8
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.position = _v3(p, 2.4)
	add_child(light)
	lights.append(light)


# --- The empty cottage lot (optional outpost) ------------------------------------------------------------

func _build_lot() -> void:
	var c: Vector2 = Reach.OUTPOST_BUILD_AREA["center"]
	var h: float = terrain.height_at(c.x, c.y)
	# a flush stone footing outline (visual only: the whole build area stays free for building)
	var m := NodeVisuals.Merger.new()
	var hw := 3.0
	var hd := 2.4
	for i in 14:
		var t := float(i) / 14.0
		var per := 2.0 * (hw * 2.0 + hd * 2.0)
		var s := t * per
		var q := Vector3.ZERO
		if s < hw * 2.0:
			q = Vector3(-hw + s, 0, -hd)
		elif s < hw * 2.0 + hd * 2.0:
			q = Vector3(hw, 0, -hd + (s - hw * 2.0))
		elif s < hw * 4.0 + hd * 2.0:
			q = Vector3(hw - (s - hw * 2.0 - hd * 2.0), 0, hd)
		else:
			q = Vector3(-hw, 0, hd - (s - hw * 4.0 - hd * 2.0))
		m.add(Kit.blob_mesh(0.5, 7670 + i, 0.2, 0.3, 1), Transform3D(Basis(Vector3.UP, float(i)).scaled(Vector3(1.1, 0.35, 0.8)), q + Vector3(0, -0.05, 0)), Color("b8ab9a"))
	var mi := MeshInstance3D.new()
	mi.name = "CottageFooting"
	mi.mesh = m.commit()
	mi.material_override = Props.stone_mat()
	mi.position = Vector3(c.x, h, c.y)
	mi.rotation.y = 0.2
	mi.visibility_range_end = 110.0
	add_child(mi)
	# the lot sign stands just outside the build area
	var sp: Vector2 = Reach.COMMONS["lot_sign"]
	var root := Node3D.new()
	root.name = "LotSign"
	add_child(root)
	root.position = _v3(sp, -0.03)
	root.rotation.y = Props.face_yaw(sp, c)
	var sm := NodeVisuals.Merger.new()
	sm.add(NodeVisuals._box(Vector3(0.1, 1.3, 0.1)), Transform3D(Basis(), Vector3(0, 0.65, 0)), Palette.WOOD_DARK)
	sm.add(NodeVisuals._box(Vector3(0.9, 0.5, 0.06)), Transform3D(Basis(Vector3.BACK, 0.05), Vector3(0, 1.2, 0.05)), Palette.WOOD_LIGHT)
	var smi := MeshInstance3D.new()
	smi.mesh = sm.commit()
	smi.material_override = Props.wood_mat()
	root.add_child(smi)
	Props.label(root, "Lot for\na cottage", Vector3(0, 1.2, 0.09), 30, Color("3b2a22"), 0.0, 0.004)
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, root.rotation.y), root.position + Vector3(0, 0.65, 0)), Vector3(0.9, 1.3, 0.15))
	lot_sign = Interactable.new()
	lot_sign.setup({"text": "Read the sign", "size": Vector3(1.2, 1.6, 1.0), "offset": Vector3(0, 0.9, 0.3),
		"handler": Callable(self, "_read_lot_sign"), "marker_y": 2.1})
	lot_sign.name = "LotSignInteract"
	root.add_child(lot_sign)


func _read_lot_sign(_player: Node) -> void:
	Audio.play_ui("ui_open", -8.0)
	Events.say.emit("Lot Sign", "An empty cottage lot. The festival folk left the footing for anyone who needs a roof between adventures.", 6.0)


# --- The festival map board ---------------------------------------------------------------------------------

func _build_board() -> void:
	var p: Vector2 = Reach.COMMONS["board"]
	var root := Node3D.new()
	root.name = "FestivalBoard"
	add_child(root)
	root.position = _v3(p, -0.03)
	# faces the arriving traveller (toward the arch, a little toward the path)
	var look: Vector2 = Reach.SPAWNS["commons_arch"]["pos"]
	root.rotation.y = Props.face_yaw(p, look + Vector2(-1.5, 1.0))
	var m := NodeVisuals.Merger.new()
	for sx in [-0.95, 0.95]:
		m.add(NodeVisuals._box(Vector3(0.14, 2.5, 0.14)), Transform3D(Basis(), Vector3(float(sx), 1.25, 0)), Palette.WOOD_DARK)
	m.add(NodeVisuals._box(Vector3(2.0, 1.35, 0.08)), Transform3D(Basis(), Vector3(0, 1.55, 0.02)), Color("e9dcbc"))
	m.add(NodeVisuals._box(Vector3(2.16, 0.1, 0.14)), Transform3D(Basis(), Vector3(0, 2.27, 0.02)), Palette.WOOD_DARK)
	m.add(NodeVisuals._box(Vector3(2.16, 0.1, 0.14)), Transform3D(Basis(), Vector3(0, 0.84, 0.02)), Palette.WOOD_DARK)
	# the painted map: three roads from the Commons (bottom) to three lamps
	var ink := Color("6a4a3a")
	var mp := Vector3(0, 1.2, 0.07)
	Props.wire(m, PackedVector3Array([mp, mp + Vector3(0, 0.3, 0)]), 0.025, ink)
	Props.wire(m, PackedVector3Array([mp + Vector3(0, 0.3, 0), mp + Vector3(-0.7, 0.45, 0)]), 0.025, Color("d9822f"))
	Props.wire(m, PackedVector3Array([mp + Vector3(0, 0.3, 0), mp + Vector3(0.7, 0.4, 0)]), 0.025, Color("b8423a"))
	Props.wire(m, PackedVector3Array([mp + Vector3(0, 0.3, 0), mp + Vector3(0.15, 0.78, 0)]), 0.025, Color("7a4a7e"))
	m.add(NodeVisuals._sph(0.07, 4, 8), Transform3D(Basis(), mp + Vector3(-0.72, 0.46, 0)), Color("e9822f"))
	m.add(NodeVisuals._sph(0.07, 4, 8), Transform3D(Basis(), mp + Vector3(0.72, 0.41, 0)), Color("b8423a"))
	m.add(NodeVisuals._sph(0.07, 4, 8), Transform3D(Basis(), mp + Vector3(0.15, 0.8, 0)), Color("7a4a7e"))
	m.add(NodeVisuals._sph(0.06, 4, 8), Transform3D(Basis(), mp), Color("e2b23e"))
	# a little roof
	m.add(NodeVisuals._box(Vector3(2.3, 0.06, 0.6)), Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 2.52, 0.1)), Props.CLOTH["plum"])
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.wood_mat()
	root.add_child(mi)
	Props.label(root, "Lanternwake", Vector3(0, 2.03, 0.075), 40, Color("5a2e2a"), 0.0, 0.0042)
	Props.label(root, "Orchard", Vector3(-0.66, 1.52, 0.075), 20, Color("6a4a3a"), 0.0, 0.0042)
	Props.label(root, "Quarry", Vector3(0.64, 1.48, 0.075), 20, Color("6a4a3a"), 0.0, 0.0042)
	Props.label(root, "Manor", Vector3(0.36, 1.92, 0.075), 20, Color("6a4a3a"), 0.0, 0.0042)
	Props.label(root, "Commons", Vector3(0, 1.08, 0.075), 20, Color("6a4a3a"), 0.0, 0.0042)
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, root.rotation.y), root.position + Vector3(0, 1.3, 0)), Vector3(2.1, 2.6, 0.2))
	board = Interactable.new()
	board.setup({"text_func": Callable(self, "_board_prompt"), "handler": Callable(self, "_read_board"),
		"size": Vector3(2.2, 2.0, 1.3), "offset": Vector3(0, 1.3, 0.5), "marker_y": 3.0})
	board.name = "BoardInteract"
	root.add_child(board)


func _board_prompt() -> Dictionary:
	return {"text": "Read the festival map" if not bool(GameState.get_flag(MAP_FLAG)) else "Read the festival board", "enabled": true}


func _read_board(_player: Node) -> void:
	read_festival_map()


## Reads the board: the MP §17 line, the three roads, flag ch2_read_festival_map (quest step ch2_commons)
## and the lore entry. Safe to call again (the line is simply shown again).
func read_festival_map() -> void:
	var first := not bool(GameState.get_flag(MAP_FLAG))
	var lore: Dictionary = LoreData.get_lore(BOARD_LORE)
	GameState.discover_lore(BOARD_LORE)
	GameState.set_flag(MAP_FLAG, true)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(BOARD_SPEAKER, String(lore.get("text", "")), 6.0)
	if first:
		Events.notify.emit("The festival map marks three lamps: the orchard to the west, the quarry to the east, the manor to the north.", "quest")
		Events.caption.emit("[Three painted roads glow on the board: west, east and north]")


# --- The festival mirror ---------------------------------------------------------------------------------

func _build_mirror() -> void:
	var p: Vector2 = Reach.COMMONS["mirror"]
	var root := Node3D.new()
	root.name = "FestivalMirror"
	add_child(root)
	root.position = _v3(p, -0.03)
	root.rotation.y = Props.face_yaw(p, Reach.COMMONS["pole"])
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._box(Vector3(1.0, 0.12, 0.5)), Transform3D(Basis(), Vector3(0, 0.06, 0)), Palette.WOOD_DARK)
	for sx in [-0.52, 0.52]:
		m.add(NodeVisuals._box(Vector3(0.1, 2.2, 0.1)), Transform3D(Basis(), Vector3(float(sx), 1.1, 0)), Color("c9a24a"))
		m.add(NodeVisuals._sph(0.08, 4, 8), Transform3D(Basis(), Vector3(float(sx), 2.24, 0)), Color("e2b23e"))
	m.add(NodeVisuals._box(Vector3(1.14, 0.1, 0.1)), Transform3D(Basis(), Vector3(0, 2.18, 0)), Color("c9a24a"))
	m.add(NodeVisuals._box(Vector3(1.14, 0.1, 0.1)), Transform3D(Basis(), Vector3(0, 0.36, 0)), Color("c9a24a"))
	m.add(NodeVisuals._cyl(0.0, 0.16, 0.24, 8), Transform3D(Basis(), Vector3(0, 2.35, 0)), Props.CLOTH["plum"])
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.wood_mat()
	root.add_child(mi)
	var glass := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.94, 1.72)
	glass.mesh = q
	glass.material_override = Mat.toon(Color("b9c6d8"), {"rim": 0.9, "specular": 0.9, "emission": Color("dfe6f2"), "emission_energy": 0.25})
	glass.position = Vector3(0, 1.27, 0.03)
	root.add_child(glass)
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, root.rotation.y), root.position + Vector3(0, 1.1, 0)), Vector3(1.2, 2.2, 0.35))
	mirror = Interactable.new()
	mirror.setup({"text": "Change your look", "size": Vector3(1.4, 2.0, 1.2), "offset": Vector3(0, 1.1, 0.5),
		"handler": Callable(self, "_use_mirror"), "marker_y": 2.8})
	mirror.name = "MirrorInteract"
	root.add_child(mirror)


func _use_mirror(_player: Node) -> void:
	Game.open_panel("wardrobe")


# --- Batching, copper leaves, day/night -----------------------------------------------------------------

func _finish_batches() -> void:
	if not _bulbs.is_empty():
		add_child(_bulbs_node())
	if not _wires.is_empty():
		var w := MeshInstance3D.new()
		w.name = "Wires"
		w.mesh = _wires.commit()
		w.material_override = Mat.toon(Color.WHITE, {"vertex_color": true})
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.visibility_range_end = 90.0
		add_child(w)
	var pk_mat := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.35, "specular": 0.3}), 0.014)
	for v in 4:
		if not (_pumpkins[v] as Array).is_empty():
			add_child(preload("res://src/world/surface/props.gd").multimesh(Flora.pumpkin_mesh(v), pk_mat, _pumpkins[v], "CommonsPumpkins%d" % v, 110.0))


func _bulbs_node() -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Props.bulb_mesh()
	mm.instance_count = _bulbs.size()
	for i in _bulbs.size():
		mm.set_instance_transform(i, _bulbs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "StringLights"
	mmi.multimesh = mm
	mmi.material_override = bulb_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Copper leaves drifting down over the festival ground (gentle, never flashing).
func _build_leaves() -> void:
	var p := CPUParticles3D.new()
	p.name = "FallingLeaves"
	p.amount = 42
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(20.0, 0.5, 20.0)
	p.direction = Vector3(0.3, -1.0, 0.1)
	p.spread = 25.0
	p.gravity = Vector3(0.25, -0.35, 0.1)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.6
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.4
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.1)
	p.mesh = q
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	p.material_override = mat
	var g := Gradient.new()
	g.set_color(0, Color("e9923a"))
	g.set_color(1, Color("b8423a"))
	p.color_initial_ramp = g
	p.position = _v3(Reach.COMMONS["pole"], 9.0)
	p.visibility_aabb = AABB(Vector3(-24, -12, -24), Vector3(48, 16, 48))
	add_child(p)


func set_daylight(daylight: float) -> void:
	for l in lights:
		(l as OmniLight3D).light_energy = lerpf(1.5, 0.55, daylight)
