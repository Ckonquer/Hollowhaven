extends Node3D
## The Ward-Keeper's Conservatory (MP §9, §11 steps 8-9, §17): an overgrown octagonal glasshouse with a
## glass lantern roof, amber/rose patterned panes (a patterned light pools on the floor), planters, a quiet
## safe corner, and four open doorways (2.2 m x 2.9 m) on the Commons, manor, pools and refuge sides.
## Inside: the lamp-linking pedestal (link_pedestal.gd), the preparations note (flag ch2_read_preparations,
## recommends an upgrade and never demands one), the workshop ledger (what each restored lamp taught:
## data/unlocks.gd flags ch2_orchard_restored / ch2_quarry_restored / ch2_manor_restored / ch2_winch_repaired,
## all set by the quest layer / quarry module - nothing is unlocked here), the Ward-Keeper's words (MP §17).
## Outside: the worn true-light plaque by the south door and the practice iron seam hr_practice_seam
## (a renewable ResourceNode like the quarry's lower veins) with its sign.

const Reach := preload("res://data/hallowmere_layout.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const Flora := preload("res://src/world/reach/reach_flora.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Interactable := preload("res://src/world/reach/reach_interactable.gd")
const Pedestal := preload("res://src/world/reach/link_pedestal.gd")
const ResourceNode := preload("res://src/world/common/resource_node.gd")
const LoreData := preload("res://data/lore_ch2_reach.gd")

const PREP_FLAG := "ch2_read_preparations"
const APOTHEM := 6.5
const WALL_H := 3.6
const DOOR_W := 2.2
const DOOR_H := 2.9
const DOOR_SIDES := [0, 2, 4, 6]            # side i faces angle i * 45 deg (0 = +X east, 2 = +Z south)
## Recipe groups the ledger reads: [unlock flag, lamp name, blank-page line].
const LEDGER := [
	["ch2_orchard_restored", "The garden lamp", "The garden page is still blank."],
	["ch2_quarry_restored", "The quarry lamp", "The quarry page is still blank."],
	["ch2_winch_repaired", "The mended winch", "A page about the upper shelf waits for the quarry winch."],
	["ch2_manor_restored", "The manor lamp", "The manor page is still blank."],
]

var terrain: RefCounted
var pedestal: Node3D
var lectern: Node3D
var ledger: Node3D
var plaque: Node3D
var true_light: Node3D
var seam_sign: Node3D
var bench: Node3D
var practice_seam: Node3D
var light: OmniLight3D
var floor_y := 0.0
var _body: StaticBody3D


func _ready() -> void:
	name = "Conservatory"
	var c: Vector2 = Reach.CONSERVATORY["center"]
	floor_y = terrain.height_at(c.x, c.y)
	position = Vector3(c.x, floor_y, c.y)
	_body = StaticBody3D.new()
	_body.name = "ConservatoryCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	add_child(_body)
	_build_shell()
	_build_floor()
	_build_interior()
	_build_outside()


func _local(p: Vector2) -> Vector3:
	var c: Vector2 = Reach.CONSERVATORY["center"]
	return Vector3(p.x - c.x, terrain.height_at(p.x, p.y) - floor_y, p.y - c.y)


static func side_dir(i: int) -> Vector2:
	var a := deg_to_rad(float(i) * 45.0)
	return Vector2(cos(a), sin(a))


## Door centres in world XZ (for tests and the walk probes).
static func door_points() -> Array:
	var out: Array = []
	var c: Vector2 = Reach.CONSERVATORY["center"]
	for i in DOOR_SIDES:
		out.append(c + side_dir(int(i)) * APOTHEM)
	return out


# --- The glasshouse ---------------------------------------------------------------------------------------

func _build_shell() -> void:
	var frame := NodeVisuals.Merger.new()
	var stone := NodeVisuals.Merger.new()
	var glass_a := NodeVisuals.Merger.new()     # amber panes
	var glass_b := NodeVisuals.Merger.new()     # rose / plum panes
	var ivy := NodeVisuals.Merger.new()
	var side_len := 2.0 * APOTHEM * tan(deg_to_rad(22.5))
	var vr := APOTHEM / cos(deg_to_rad(22.5))
	var frame_c := Color("5f6b4a")
	var cream := Color("efe2c2")
	var rng := RandomNumberGenerator.new()
	rng.seed = 6161
	for i in 8:
		var n := side_dir(i)
		var mid := Vector3(n.x, 0, n.y) * APOTHEM
		var along := Vector3(n.y, 0, -n.x)
		var wb := Basis(along, Vector3.UP, Vector3(n.x, 0, n.y))      # right-handed: along x up = outward normal
		var door := DOOR_SIDES.has(i)
		# corner pillar (at the vertex between side i and i+1)
		var va := deg_to_rad(float(i) * 45.0 + 22.5)
		var vp := Vector3(cos(va), 0, sin(va)) * vr
		frame.add(NodeVisuals._cyl(0.13, 0.16, WALL_H + 0.25, 8), Transform3D(Basis(), vp + Vector3(0, (WALL_H + 0.25) * 0.5, 0)), cream)
		frame.add(Kit.blob_mesh(0.2, 6170 + i, 0.2, 0.7, 1), Transform3D(Basis(), vp + Vector3(0, WALL_H + 0.3, 0)), cream.darkened(0.1))
		# segments of this side: [from, to] along the wall (0 = one end, side_len = the other)
		var segs: Array = [[0.0, side_len]]
		if door:
			segs = [[0.0, (side_len - DOOR_W) * 0.5], [(side_len + DOOR_W) * 0.5, side_len]]
		for s in segs:
			var u0: float = float(s[0]) - side_len * 0.5
			var u1: float = float(s[1]) - side_len * 0.5
			var ln := u1 - u0
			var um := (u0 + u1) * 0.5
			var at := mid + along * um
			# stone knee wall
			stone.add(NodeVisuals._box(Vector3(ln, 0.75, 0.34)), Transform3D(wb, at + Vector3(0, 0.375, 0)), Color("c2b39b"))
			stone.add(NodeVisuals._box(Vector3(ln + 0.06, 0.08, 0.42)), Transform3D(wb, at + Vector3(0, 0.79, 0)), Color("d8ccb4"))
			# glass above, split into panes by mullions
			var panes := maxi(1, int(round(ln / 0.9)))
			for pi in panes:
				var pu0 := u0 + ln * float(pi) / float(panes)
				var pu1 := u0 + ln * float(pi + 1) / float(panes)
				var pc := mid + along * ((pu0 + pu1) * 0.5)
				var broken := rng.randf() < 0.12
				if not broken:
					var target: Variant = glass_a if (pi + i) % 3 != 0 else glass_b
					target.add(NodeVisuals._box(Vector3(pu1 - pu0 - 0.04, WALL_H - 0.85, 0.03)), Transform3D(wb, pc + Vector3(0, 0.83 + (WALL_H - 0.83) * 0.5, 0)), Color.WHITE)
				frame.add(NodeVisuals._box(Vector3(0.06, WALL_H - 0.83, 0.07)), Transform3D(wb, mid + along * pu0 + Vector3(0, 0.83 + (WALL_H - 0.83) * 0.5, 0)), frame_c)
				# leaded pattern: a diamond in every pane
				var dh := (WALL_H - 0.83) * 0.5
				for k in 4:
					var ka := PI * 0.25 + float(k) * PI * 0.5
					var b2 := wb * Basis(Vector3.BACK, ka)
					frame.add(NodeVisuals._box(Vector3(0.025, minf(pu1 - pu0, dh) * 0.7, 0.05)), Transform3D(b2, pc + Vector3(0, 0.83 + dh, 0) + wb * Vector3(cos(ka + PI * 0.5) * 0.18, sin(ka + PI * 0.5) * 0.18, 0)), frame_c.darkened(0.2))
			frame.add(NodeVisuals._box(Vector3(ln, 0.08, 0.1)), Transform3D(wb, at + Vector3(0, WALL_H, 0)), frame_c)
			frame.add(NodeVisuals._box(Vector3(ln, 0.06, 0.08)), Transform3D(wb, at + Vector3(0, 2.2, 0)), frame_c)
			Props.box_col(_body, Transform3D(wb, at + Vector3(0, WALL_H * 0.5, 0)), Vector3(ln, WALL_H, 0.34))
		if door:
			# a painted festival arch over the doorway (worn symbols: suns and lanterns)
			var top := mid + Vector3(0, DOOR_H, 0)
			frame.add(NodeVisuals._box(Vector3(DOOR_W + 0.3, 0.16, 0.22)), Transform3D(wb, top + Vector3(0, 0.08, 0)), cream)
			frame.add(NodeVisuals._box(Vector3(DOOR_W, WALL_H - DOOR_H - 0.1, 0.03)), Transform3D(wb, top + Vector3(0, (WALL_H - DOOR_H) * 0.5 + 0.05, 0)), Color("d9a24a"))
			for sx in [-1.0, 1.0]:
				frame.add(NodeVisuals._box(Vector3(0.14, DOOR_H, 0.2)), Transform3D(wb, mid + along * (float(sx) * DOOR_W * 0.5) + Vector3(0, DOOR_H * 0.5, 0)), cream)
			frame.add(NodeVisuals._sph(0.16, 4, 8), Transform3D(Basis(), top + Vector3(0, 0.32, 0) + Vector3(n.x, 0, n.y) * 0.12), Color("e2b23e"))
		# autumn ivy creeping over the walls
		for k in 3:
			var u := rng.randf_range(-side_len * 0.5, side_len * 0.5)
			var hy := rng.randf_range(0.6, WALL_H + 0.2)
			if door and absf(u) < DOOR_W * 0.6 and hy < DOOR_H + 0.3:
				continue
			var ic := [Color("b8423a"), Color("d9822f"), Color("8a3a2a"), Color("c9a24a")][rng.randi() % 4] as Color
			ivy.add(Kit.blob_mesh(0.34, 6200 + i * 3 + k, 0.4, 0.6, 1), Transform3D(Basis(), mid + along * u + Vector3(n.x, 0, n.y) * 0.24 + Vector3(0, hy, 0)), ic)
	# the glass lantern roof: eight sloping panels up to a small cupola
	var eave_r := vr + 0.15
	var top_y := 7.0
	var cup_r := 1.3
	for i in 8:
		var a0 := deg_to_rad(float(i) * 45.0 + 22.5)
		var a1 := deg_to_rad(float(i + 1) * 45.0 + 22.5)
		var p0 := Vector3(cos(a0) * eave_r, WALL_H + 0.05, sin(a0) * eave_r)
		var p1 := Vector3(cos(a1) * eave_r, WALL_H + 0.05, sin(a1) * eave_r)
		var q0 := Vector3(cos(a0) * cup_r, top_y, sin(a0) * cup_r)
		var q1 := Vector3(cos(a1) * cup_r, top_y, sin(a1) * cup_r)
		var up := ((q0 + q1) * 0.5 - (p0 + p1) * 0.5)
		var nrm := (p1 - p0).cross(up).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var tgt: Variant = glass_a if i % 2 == 0 else glass_b
		if i != 3:
			tgt.tri(p0, q0, q1, nrm, Color.WHITE, Color.WHITE, Color.WHITE, true)
			tgt.tri(p0, q1, p1, nrm, Color.WHITE, Color.WHITE, Color.WHITE, true)
		Props.wire(frame, PackedVector3Array([p0, q0]), 0.06, frame_c)
		Props.wire(frame, PackedVector3Array([(p0 + p1) * 0.5, (q0 + q1) * 0.5]), 0.035, frame_c)
		Props.wire(frame, PackedVector3Array([p0, p1]), 0.07, frame_c)
		Props.wire(frame, PackedVector3Array([q0, q1]), 0.05, frame_c)
	frame.add(NodeVisuals._cyl(cup_r, cup_r, 0.9, 8), Transform3D(Basis(), Vector3(0, top_y + 0.45, 0)), frame_c)
	frame.add(NodeVisuals._cyl(0.1, cup_r + 0.2, 0.9, 8), Transform3D(Basis(), Vector3(0, top_y + 1.35, 0)), Color("7a4a3a"))
	frame.add(NodeVisuals._sph(0.18, 4, 8), Transform3D(Basis(), Vector3(0, top_y + 1.9, 0)), Color("e2b23e"))
	for k in 6:
		var a := rng.randf() * TAU
		ivy.add(Kit.blob_mesh(0.4, 6240 + k, 0.4, 0.5, 1), Transform3D(Basis(), Vector3(cos(a) * (eave_r - 0.3), WALL_H + 0.25, sin(a) * (eave_r - 0.3))), [Color("b8423a"), Color("d9822f")][k % 2])
	_add_mesh(frame.commit(), Props.wood_mat(), "Frame")
	_add_mesh(stone.commit(), Props.stone_mat(), "KneeWalls")
	_add_mesh(ivy.commit(), NodeVisuals.foliage_material(0.02, 3.0, 0.02, 0.2), "Ivy")
	var ga := Mat.transparent(Color(1.0, 0.78, 0.42, 0.28), false, true)
	var gb := Mat.transparent(Color(0.92, 0.55, 0.62, 0.3), false, true)
	var ma := _add_mesh(glass_a.commit(), ga, "GlassAmber")
	var mb := _add_mesh(glass_b.commit(), gb, "GlassRose")
	ma.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_mesh(mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.visibility_range_end = 220.0
	add_child(mi)
	return mi


## Flagstone floor and the patterned amber light pooled on it.
func _build_floor() -> void:
	var m := NodeVisuals.Merger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6262
	for ring in 4:
		var r := 1.3 + float(ring) * 1.45
		var n := 6 + ring * 6
		for k in n:
			var a := TAU * float(k) / float(n) + float(ring) * 0.3
			var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
			var c := Color("cdbfa6").lerp(Color("a8987f"), rng.randf() * 0.6)
			m.add(Kit.blob_mesh(0.5, 6300 + ring * 20 + k, 0.1, 0.15, 1), Transform3D(Basis(Vector3.UP, a).scaled(Vector3(1.3, 1.0, 0.9)), p + Vector3(0, 0.02, 0)), c)
	_add_mesh(m.commit(), Props.stone_mat(), "Flagstones").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# patterned light: a soft star-and-diamond glow on the floor (unshaded, additive, never flashing)
	var pat := NodeVisuals.Merger.new()
	for k in 8:
		var a := TAU * float(k) / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var s := Vector3(-d.z, 0, d.x)
		pat.tri(Vector3(0, 0.05, 0) + d * 1.2, Vector3(0, 0.05, 0) + d * 5.2 + s * 0.45, Vector3(0, 0.05, 0) + d * 5.2 - s * 0.45, Vector3.UP, Color.WHITE, Color.WHITE, Color.WHITE, true)
		var q := d * 3.4 + Vector3(0, 0.06, 0)
		pat.tri(q + s * 0.5, q + d * 0.5, q - s * 0.5, Vector3.UP, Color.WHITE, Color.WHITE, Color.WHITE, true)
		pat.tri(q - s * 0.5, q - d * 0.5, q + s * 0.5, Vector3.UP, Color.WHITE, Color.WHITE, Color.WHITE, true)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	pm.albedo_color = Color(1.0, 0.72, 0.36, 0.22)
	var pmi := _add_mesh(pat.commit(), pm, "PatternedLight")
	pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	light = OmniLight3D.new()
	light.name = "AmberLight"
	light.light_color = Color("ffbf70")
	light.light_energy = 1.1
	light.omni_range = 10.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 80.0
	light.distance_fade_length = 15.0
	light.position = Vector3(0, 4.2, 0)
	add_child(light)


# --- Inside --------------------------------------------------------------------------------------------------

func _build_interior() -> void:
	pedestal = Pedestal.new()
	add_child(pedestal)
	pedestal.position = _local(Reach.CONSERVATORY["pedestal"])
	# planters flanking every doorway
	var pl := NodeVisuals.Merger.new()
	var plants := NodeVisuals.Merger.new()
	var side_len := 2.0 * APOTHEM * tan(deg_to_rad(22.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6363
	for i in DOOR_SIDES:
		var n := side_dir(int(i))
		var along := Vector3(n.y, 0, -n.x)
		var wb := Basis(along, Vector3.UP, Vector3(n.x, 0, n.y))
		for sx in [-1.0, 1.0]:
			var u := float(sx) * (DOOR_W * 0.5 + (side_len - DOOR_W) * 0.25)
			var at := Vector3(n.x, 0, n.y) * (APOTHEM - 0.62) + along * u
			pl.add(NodeVisuals._box(Vector3(1.2, 0.55, 0.62)), Transform3D(wb, at + Vector3(0, 0.275, 0)), Palette.WOOD)
			pl.add(NodeVisuals._box(Vector3(1.1, 0.06, 0.52)), Transform3D(wb, at + Vector3(0, 0.56, 0)), Color("5a4030"))
			for k in 3:
				var c := [Color("d9822f"), Color("b8423a"), Color("e2b23e"), Color("7a4a7e"), Color("6f8a3a")][rng.randi() % 5] as Color
				plants.add(Kit.blob_mesh(0.22, 6400 + int(i) * 10 + k + int(sx + 1.0) * 3, 0.35, 0.8, 1), Transform3D(Basis(), at + along * ((float(k) - 1.0) * 0.36) + Vector3(0, 0.78, 0)), c)
			Props.box_col(_body, Transform3D(wb, at + Vector3(0, 0.3, 0)), Vector3(1.2, 0.6, 0.62))
	_add_mesh(pl.commit(), Props.wood_mat(), "Planters")
	_add_mesh(plants.commit(), NodeVisuals.foliage_material(0.03, 1.2, 0.02, 0.25), "PlanterPlants")
	# the safe corner: a bench under a little hanging lamp
	var bp := _local(Reach.CONSERVATORY["bench"])
	var bxf := Transform3D(Basis(Vector3.UP, Props.face_yaw(Reach.CONSERVATORY["bench"], Reach.CONSERVATORY["pedestal"])), bp)
	var bmi := MeshInstance3D.new()
	bmi.mesh = Props.bench_mesh()
	bmi.material_override = Props.wood_mat()
	bmi.transform = bxf
	add_child(bmi)
	Props.box_col(_body, bxf * Transform3D(Basis(), Vector3(0, 0.25, 0)), Vector3(1.8, 0.5, 0.45))
	var bl := MeshInstance3D.new()
	bl.mesh = Props.lantern_glass_mesh()
	bl.material_override = Mat.glow(Color("ffc66e"), 2.0)
	bl.position = bp + Vector3(0, 2.6, 0)
	add_child(bl)
	bench = Interactable.new()
	bench.setup({"text": "Sit a moment", "size": Vector3(1.8, 1.2, 1.2), "offset": Vector3(0, 0.6, 0.4),
		"handler": Callable(self, "_sit"), "marker_y": 1.8})
	bench.transform = bxf
	bench.name = "BenchInteract"
	add_child(bench)
	# the preparations lectern
	lectern = _note_stand(Reach.CONSERVATORY["lectern"], "Read the preparation notes", Callable(self, "_read_preparations"), true)
	# the workshop ledger board
	ledger = _note_stand(Reach.CONSERVATORY["ledger"], "Read the workshop ledger", Callable(self, "_read_ledger"), false)
	# the Ward-Keeper's words
	plaque = _note_stand(Reach.CONSERVATORY["plaque"], "Read the Ward-Keeper's words", Callable(self, "_read_plaque"), false)


## A lectern (book) or a wall board facing the pedestal, with its interactable.
func _note_stand(p: Vector2, text: String, handler: Callable, book: bool) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = _local(p)
	root.rotation.y = Props.face_yaw(p, Reach.CONSERVATORY["pedestal"])
	var m := NodeVisuals.Merger.new()
	if book:
		m.add(NodeVisuals._cyl(0.08, 0.12, 1.0, 8), Transform3D(Basis(), Vector3(0, 0.5, 0)), Palette.WOOD_DARK)
		m.add(NodeVisuals._box(Vector3(0.6, 0.06, 0.45)), Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0, 1.05, 0)), Palette.WOOD)
		m.add(NodeVisuals._box(Vector3(0.5, 0.05, 0.36)), Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0, 1.1, 0.01)), Color("f3e6c8"))
	else:
		for sx in [-0.55, 0.55]:
			m.add(NodeVisuals._box(Vector3(0.1, 1.9, 0.1)), Transform3D(Basis(), Vector3(float(sx), 0.95, 0)), Palette.WOOD_DARK)
		m.add(NodeVisuals._box(Vector3(1.2, 0.8, 0.06)), Transform3D(Basis(), Vector3(0, 1.4, 0.02)), Color("e9dcbc"))
		for k in 5:
			m.add(NodeVisuals._box(Vector3(0.8 - float(k % 2) * 0.2, 0.03, 0.01)), Transform3D(Basis(), Vector3(-0.05, 1.62 - float(k) * 0.1, 0.055)), Color("8a6a52"))
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.wood_mat()
	root.add_child(mi)
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, root.rotation.y), root.position + Vector3(0, 0.6, 0)), Vector3(0.7 if book else 1.2, 1.2, 0.4))
	var it := Interactable.new()
	it.setup({"text": text, "size": Vector3(1.3, 1.4, 1.2), "offset": Vector3(0, 1.0, 0.45), "handler": handler, "marker_y": 2.3})
	it.name = ("Lectern" if book else "Board") + "_" + String(text.get_slice(" ", 2)).capitalize().replace(" ", "")
	root.add_child(it)
	return it


func _say_lore(id: String, secs: float = 8.0) -> void:
	var l: Dictionary = LoreData.get_lore(id)
	GameState.discover_lore(id)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l["title"]), String(l["text"]), secs)


func _read_preparations(_player: Node) -> void:
	read_preparations()


## MP §11 step 8: read the notes (flag ch2_read_preparations). A recommendation, never a demand.
func read_preparations() -> void:
	_say_lore("lore_ch2_preparations", 11.0)
	if not bool(GameState.get_flag(PREP_FLAG)):
		GameState.set_flag(PREP_FLAG, true)
		Events.hint.emit("ch2_prepare_seam", "A practice seam of iron waits just outside. A stone pickaxe will do; a better one is quicker.")


func _read_plaque(_player: Node) -> void:
	_say_lore("lore_ch2_conservatory", 7.0)


func _read_true_light(_player: Node) -> void:
	_say_lore("lore_ch2_true_light", 8.0)


func _sit(_player: Node) -> void:
	Events.say.emit("", "A quiet corner. The glass hums faintly, and the light through it is the colour of honey.", 5.0)


func _read_ledger(_player: Node) -> void:
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit("Workshop Ledger", ledger_text(), 11.0)


## What the restored lamps have taught (recipe names from data/recipes.gd through ItemDB), one line per lamp.
static func ledger_text() -> String:
	var lines: Array = []
	for g in LEDGER:
		var flag := String(g[0])
		if not bool(GameState.get_flag(flag)):
			lines.append(String(g[2]))
			continue
		var names: Array = []
		for rid in ItemDB.every_recipe_id():
			var r: Dictionary = ItemDB.recipe(String(rid))
			if String(r.get("unlock", "")) != flag:
				continue
			var nm := ""
			if String(r.get("pattern", "")) != "":
				nm = String(ItemDB.pattern(String(r["pattern"])).get("name", String(r["pattern"]).capitalize()))
			else:
				nm = ItemDB.display_name(String(r.get("result", rid)))
			if nm != "" and not names.has(nm):
				names.append(nm)
		if names.size() > 6:
			names = names.slice(0, 6)
			names.append("and more")
		lines.append("%s taught: %s." % [String(g[1]), ", ".join(names)])
	return " ".join(lines)


# --- Outside: the true-light plaque and the practice seam --------------------------------------------

func _build_outside() -> void:
	var tp: Vector2 = Reach.CONSERVATORY["true_light"]
	var root := Node3D.new()
	root.name = "TrueLightPlaque"
	add_child(root)
	root.position = _local(tp)
	root.rotation.y = Props.face_yaw(tp, tp + Vector2(0, 5))
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._box(Vector3(0.7, 1.0, 0.2)), Transform3D(Basis(), Vector3(0, 0.5, 0)), Color("b9ab94"))
	m.add(NodeVisuals._box(Vector3(0.56, 0.5, 0.04)), Transform3D(Basis(), Vector3(0, 0.72, 0.11)), Color("c9a24a"))
	m.add(NodeVisuals._sph(0.09, 4, 8), Transform3D(Basis(), Vector3(0, 0.8, 0.14)), Color("f2c14e"))
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.stone_mat()
	root.add_child(mi)
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, root.rotation.y), root.position + Vector3(0, 0.5, 0)), Vector3(0.7, 1.0, 0.25))
	true_light = Interactable.new()
	true_light.setup({"text": "Read the worn plaque", "size": Vector3(1.0, 1.2, 1.0), "offset": Vector3(0, 0.7, 0.4),
		"handler": Callable(self, "_read_true_light"), "marker_y": 1.7})
	true_light.name = "TrueLightInteract"
	root.add_child(true_light)
	# the practice seam: an iron outcrop with a few big stones around it
	var sp: Vector2 = Reach.CONSERVATORY["practice_seam"]
	# The data kind "iron_vein" (data/sources.gd, like the quarry's lower veins): tool, tier, hits, drops and
	# respawn come from the catalogue, and Events.harvested reports "iron_vein" (mastery, census), not copper "ore".
	practice_seam = ResourceNode.new()
	practice_seam.setup({"node_id": Reach.PRACTICE_SEAM_ID, "kind": "iron_vein", "visual": Flora.iron_seam_visual(1), "yaw": 30.0, "fx": "chips"})
	add_child(practice_seam)
	practice_seam.position = _local(sp) - Vector3(0, 0.08, 0)
	var rocks := NodeVisuals.Merger.new()
	for k in 3:
		var a := float(k) * 2.1 + 0.4
		rocks.add(NodeVisuals.boulder_mesh(k % 3, Color("a89a8a"), 0.3), Transform3D(Basis(Vector3.UP, a).scaled(Vector3.ONE * (0.55 + float(k) * 0.1)), _local(sp + Vector2(cos(a), sin(a)) * 1.9) - Vector3(0, 0.2, 0)), Color.WHITE)
	var rmi := MeshInstance3D.new()
	rmi.mesh = rocks.commit()
	rmi.material_override = NodeVisuals.rock_material()
	add_child(rmi)
	var ss: Vector2 = Reach.CONSERVATORY["seam_sign"]
	var sroot := Node3D.new()
	sroot.name = "SeamSign"
	add_child(sroot)
	sroot.position = _local(ss)
	sroot.rotation.y = Props.face_yaw(ss, Vector2(0, 17))
	var sm := NodeVisuals.Merger.new()
	sm.add(NodeVisuals._box(Vector3(0.1, 1.2, 0.1)), Transform3D(Basis(), Vector3(0, 0.6, 0)), Palette.WOOD_DARK)
	sm.add(NodeVisuals._box(Vector3(0.8, 0.45, 0.06)), Transform3D(Basis(), Vector3(0, 1.1, 0.05)), Palette.WOOD_LIGHT)
	var smi := MeshInstance3D.new()
	smi.mesh = sm.commit()
	smi.material_override = Props.wood_mat()
	sroot.add_child(smi)
	Props.label(sroot, "Practice\nseam", Vector3(0, 1.1, 0.09), 28, Color("3b2a22"), 0.0, 0.004)
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, sroot.rotation.y), sroot.position + Vector3(0, 0.6, 0)), Vector3(0.8, 1.2, 0.15))
	seam_sign = Interactable.new()
	seam_sign.setup({"text": "Read the sign", "size": Vector3(1.0, 1.4, 0.9), "offset": Vector3(0, 0.8, 0.3),
		"handler": Callable(self, "_read_seam_sign"), "marker_y": 1.9})
	seam_sign.name = "SeamSignInteract"
	sroot.add_child(seam_sign)


func _read_seam_sign(_player: Node) -> void:
	Events.say.emit("Practice Seam", "Iron runs close to the surface here. A stone pickaxe will do; better picks are quicker. It grows back by tomorrow.", 6.0)


func set_daylight(daylight: float) -> void:
	if light != null:
		light.light_energy = lerpf(1.6, 0.8, daylight)
