extends Node3D
## The Sunken Bellhouse (MP §9, §10, §11 steps 9-10): a half-sunken bell tower leaning in still water, one
## warm upper window that is always lit (reassuring), a cracked bell in the belfry, and an ominous stair on
## the forecourt that leads down to the old service gate of the Hushed Works.
##   * sealed (no ch2_lamps_linked): heavy stone slabs marked with three lanterns cover the stairwell
##     (walkable, collidable); a greyed "sealed stair" prompt explains what opens it
##   * revealed (ch2_lamps_linked, instantly on load; the slabs lie stacked beside the forecourt): the stair
##     leads down to the service gate (src/world/below/lower_gate.gd: flag ch2_service_gate_open, key
##     foreman_key, checked and never consumed); its locked text points to the Foreman's Key, with a gentle
##     variant when an inconsistent old save has lost the key (it is never granted here)
##   * past the open gate: bellhouse_descent.gd -> Game.change_area("hushed_works", "service_landing")
## Also: the equipment / comfort reminder sign and the bellhouse plaque (lore_ch2_bellhouse).

const Reach := preload("res://data/hallowmere_layout.gd")
const Props := preload("res://src/world/reach/reach_props.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Interactable := preload("res://src/world/reach/reach_interactable.gd")
const LowerGate := preload("res://src/world/below/lower_gate.gd")
const Descent := preload("res://src/world/reach/bellhouse_descent.gd")
const AudioUtil := preload("res://src/world/surface/audio_util.gd")
const LoreData := preload("res://data/lore_ch2_reach.gd")

const REVEAL_FLAG := "ch2_lamps_linked"
const GATE_FLAG := "ch2_service_gate_open"
const KEY := "foreman_key"
const LOCKED_TEXT := "The service gate is locked. It carries the old mine's stamp: the Foreman's Key would fit it."
## Shown only when an inconsistent old save lost the key (it can only ever live in the key pouch, and nothing
## uses it up). Honest and gentle: it never sends her searching the house or a chest.
const LOST_KEY_TEXT := "The Foreman's Key would fit this gate, but it isn't in your key pouch. Keys are never used up, so it has only gone astray; it was first found in the old mine's office."
const REMINDER := "Before the stair: wear your best armour, pack something to eat and keep your lantern lit. You can always come back up, and the Lantern Road will carry you home."
const STONE := Color("9d958a")
const STONE_DARK := Color("6f6862")
const SLATE := Color("5a5068")

var terrain: RefCounted
var hb := 0.0                       # forecourt height
var bottom := 0.0                   # stair bottom height
var gate: Node3D
var descent: Node3D
var seal: Node3D
var sign_it: Node3D
var plaque_it: Node3D
var window_light: OmniLight3D
var revealed := false
var _lid: Node3D
var _lid_body: StaticBody3D
var _pile: Node3D
var _stair_lamp: OmniLight3D
var _drip: AudioStreamPlayer3D
var _body: StaticBody3D


func _ready() -> void:
	name = "Bellhouse"
	hb = float(terrain.bellhouse_level)
	bottom = hb - float(Reach.BELLHOUSE["depth"])
	_body = StaticBody3D.new()
	_body.name = "BellhouseCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "stone")
	add_child(_body)
	_build_stairwell()
	_build_tower()
	_build_gate()
	_build_lid()
	_build_forecourt()
	apply_state()
	if not Events.flag_set.is_connected(_on_flag_set):
		Events.flag_set.connect(_on_flag_set)
	if not Events.key_item_added.is_connected(_on_key_added):
		Events.key_item_added.connect(_on_key_added)


func _on_flag_set(flag: String, _value: Variant) -> void:
	if flag == REVEAL_FLAG or flag == GATE_FLAG:
		apply_state()
	if flag == GATE_FLAG:
		# Deferred: when the gate itself unlocks, it sets the flag before it starts swinging open.
		_sync_gate_open.call_deferred()


## The service gate only reads its flag in _ready: if something else records ch2_service_gate_open while the
## region is loaded (a repair or debug hook), open the leaves too, so the flag never leaves a shut gate in front
## of an enabled way down.
func _sync_gate_open() -> void:
	if gate == null or not is_instance_valid(gate) or not bool(GameState.get_flag(GATE_FLAG)):
		return
	if not bool(gate.get("is_open")) and not bool(gate.get("animating")) and gate.has_method("unlock"):
		gate.unlock(false)


func _on_key_added(_item: String) -> void:
	_update_locked_text()


func is_revealed() -> bool:
	return bool(GameState.get_flag(REVEAL_FLAG))


## Chooses the gate's locked line: the normal one, or the gentle one when an old save lost the key.
func locked_text() -> String:
	if not GameState.has_item(KEY) and (bool(GameState.get_flag("foreman_key_taken")) or bool(GameState.get_flag("lower_gate_open"))):
		return LOST_KEY_TEXT
	return LOCKED_TEXT


func _update_locked_text() -> void:
	var t := locked_text()
	if gate != null:
		gate.set("locked_text", t)
	if descent != null:
		descent.set("locked_text", t)


func apply_state() -> void:
	revealed = is_revealed()
	if _lid != null:
		_lid.visible = not revealed
	if _lid_body != null:
		_lid_body.collision_layer = 0 if revealed else 1
	if _pile != null:
		_pile.visible = revealed
		(_pile.get_node("PileBody") as StaticBody3D).collision_layer = 1 if revealed else 0
	if seal != null:
		seal.set_active(not revealed)
	_set_gate_active(revealed)
	if _stair_lamp != null:
		_stair_lamp.visible = revealed
	if revealed and _drip == null and is_inside_tree():
		_drip = AudioUtil.make_loop("water_drip", "Ambience", -12.0, 12.0)
		if _drip != null:
			_drip.name = "StairDrip"
			add_child(_drip)
			_drip.global_position = Vector3(Reach.BELLHOUSE["stair_x"], bottom + 1.0, float(Reach.BELLHOUSE["gate_z"]) - 1.0)
	_update_locked_text()
	if descent != null and descent.has_method("refresh"):
		descent.refresh()


## The gate only answers the interaction probe once the stair is revealed (it sits under the slabs).
func _set_gate_active(on: bool) -> void:
	if gate == null or not is_instance_valid(gate):
		return
	gate.visible = on
	var open := bool(GameState.get_flag(GATE_FLAG))
	for c in gate.get_children():
		if c is Area3D:
			(c as Area3D).collision_layer = 16 if (on and not open) else 0
	if on and not open:
		if not gate.is_in_group("interactable"):
			gate.add_to_group("interactable")
	elif gate.is_in_group("interactable"):
		gate.remove_from_group("interactable")
	# the leaves stay solid either way (sealed: out of reach under the slabs)


# --- Stairwell ---------------------------------------------------------------------------------------------

func _build_stairwell() -> void:
	var B: Dictionary = Reach.BELLHOUSE
	var sx: float = B["stair_x"]
	var top_z: float = B["ramp_top_z"]
	var bot_z: float = B["ramp_bottom_z"]
	var end_z: float = B["bottom_end_z"]
	var walls := NodeVisuals.Merger.new()
	var z0 := -76.6
	var z1 := -85.5
	var y0 := bottom - 0.3
	var y1 := hb + 0.55
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	for sgn in [-1.0, 1.0]:
		var xc := sx + float(sgn) * (1.45 + 0.825)
		Props.box_col(_body, Transform3D(Basis(), Vector3(xc, (y0 + y1) * 0.5, (z0 + z1) * 0.5)), Vector3(1.65, y1 - y0, absf(z1 - z0)))
		# courses of big blocks, the inner face visible from the stair
		var rows := int(ceil((y1 - y0) / 0.55))
		for r in rows:
			var yy := y0 + (float(r) + 0.5) * (y1 - y0) / float(rows)
			var z := z0
			var k := 0
			while z > z1 + 0.01:
				var ln := minf(rng.randf_range(0.9, 1.5), z - z1)
				var c := STONE.lerp(STONE_DARK, rng.randf() * 0.5)
				walls.add(NodeVisuals._box(Vector3(1.66, (y1 - y0) / float(rows) - 0.04, ln - 0.04)), Transform3D(Basis(), Vector3(xc, yy, z - ln * 0.5)), c)
				z -= ln
				k += 1
		walls.add(NodeVisuals._box(Vector3(1.8, 0.14, absf(z1 - z0) + 0.1)), Transform3D(Basis(), Vector3(xc, y1 + 0.07, (z0 + z1) * 0.5)), Color("b3aa9c"))
	# visual steps over the smooth ramp (the ramp itself collides)
	var steps := 13
	for i in steps:
		var t0 := float(i) / float(steps)
		var t1 := float(i + 1) / float(steps)
		var za := lerpf(top_z, bot_z, t0)
		var zb := lerpf(top_z, bot_z, t1)
		var ya := lerpf(hb, bottom, t0)
		var yb := lerpf(hb, bottom, t1)
		walls.add(NodeVisuals._box(Vector3(2.9, (ya - yb) + 0.12, absf(zb - za) + 0.02)), Transform3D(Basis(), Vector3(sx, (ya + yb) * 0.5 - 0.02, (za + zb) * 0.5)), STONE.lightened(0.05) if i % 2 == 0 else STONE)
	walls.add(NodeVisuals._box(Vector3(2.9, 0.12, absf(end_z - bot_z) + 0.4)), Transform3D(Basis(), Vector3(sx, bottom - 0.05, (bot_z + end_z) * 0.5)), STONE_DARK)
	var mi := MeshInstance3D.new()
	mi.name = "Stairwell"
	mi.mesh = walls.commit()
	mi.material_override = Props.stone_mat()
	add_child(mi)
	# a clean walkable floor: the ramp and the landing (a hair above the carved ground)
	var ramp_len := Vector2(top_z - bot_z, hb - bottom).length()
	var ang := atan2(hb - bottom, top_z - bot_z)
	var bb := Basis(Vector3.RIGHT, -ang)
	# The ramp's walking face ends exactly on the top landing's edge (top_z, hb + 0.02) and only reaches past
	# its lower end (buried under the landing): no lip at either joint, so she walks up as easily as down.
	Props.box_col(_body, Transform3D(bb, Vector3(sx, (hb + bottom) * 0.5 + 0.02, (top_z + bot_z) * 0.5) - bb.y * 0.15 - bb.z * 0.1), Vector3(2.9, 0.3, ramp_len + 0.2))
	Props.box_col(_body, Transform3D(Basis(), Vector3(sx, bottom + 0.02 - 0.15, (bot_z + end_z) * 0.5)), Vector3(2.9, 0.3, absf(end_z - bot_z) + 0.4))
	Props.box_col(_body, Transform3D(Basis(), Vector3(sx, hb - 0.13, top_z + 0.55)), Vector3(2.9, 0.3, 1.1))
	# two small warm lanterns on the parapet ends, and a cold one by the gate below
	for sgn in [-1.0, 1.0]:
		var g := MeshInstance3D.new()
		g.mesh = Props.lantern_glass_mesh()
		g.material_override = Mat.glow(Color("ffc66e"), 1.8)
		g.position = Vector3(sx + float(sgn) * 2.2, y1 + 0.3, z0 - 0.3)
		add_child(g)
	_stair_lamp = OmniLight3D.new()
	_stair_lamp.light_color = Color("9fb4e8")
	_stair_lamp.light_energy = 0.6
	_stair_lamp.omni_range = 4.0
	_stair_lamp.shadow_enabled = false
	_stair_lamp.position = Vector3(sx + 1.1, bottom + 2.1, float(B["gate_z"]) + 0.6)
	add_child(_stair_lamp)
	var cold := MeshInstance3D.new()
	cold.mesh = Props.lantern_glass_mesh()
	cold.material_override = Mat.glow(Color("a9bde8"), 1.2)
	cold.position = _stair_lamp.position
	add_child(cold)


# --- The tower -------------------------------------------------------------------------------------------------

func _build_tower() -> void:
	var r: Rect2 = Reach.BELLHOUSE["tower"]
	var sx: float = Reach.BELLHOUSE["stair_x"]
	var c := Vector3(r.get_center().x, 0.0, r.get_center().y)
	var base_y := bottom - 0.3
	var body_top := hb + 7.4
	var half := r.size.x * 0.5
	var south := r.end.y             # z of the south face (-85.5)
	var pass_top := bottom + 2.9
	var inner := 1.45
	# collision (upright, around the passage)
	Props.box_col(_body, Transform3D(Basis(), Vector3((r.position.x + sx - inner) * 0.5, (base_y + body_top) * 0.5, c.z)), Vector3(sx - inner - r.position.x, body_top - base_y, r.size.y))
	Props.box_col(_body, Transform3D(Basis(), Vector3((r.end.x + sx + inner) * 0.5, (base_y + body_top) * 0.5, c.z)), Vector3(r.end.x - sx - inner, body_top - base_y, r.size.y))
	var back_z := float(Reach.BELLHOUSE["bottom_end_z"]) + 0.2
	Props.box_col(_body, Transform3D(Basis(), Vector3(sx, (base_y + body_top) * 0.5, (back_z + r.position.y) * 0.5)), Vector3(inner * 2.0, body_top - base_y, absf(back_z - r.position.y)))
	Props.box_col(_body, Transform3D(Basis(), Vector3(sx, (pass_top + body_top) * 0.5, (south + back_z) * 0.5)), Vector3(inner * 2.0, body_top - pass_top, absf(south - back_z)))
	# visuals: the whole tower leans a little (half-sunken), pivoting at its base
	var tower := Node3D.new()
	tower.name = "Tower"
	add_child(tower)
	tower.position = Vector3(c.x, base_y, c.z)
	tower.rotation = Vector3(deg_to_rad(-1.5), 0.0, deg_to_rad(2.2))
	var m := NodeVisuals.Merger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7272
	var h := body_top - base_y
	# body in four walls of big blocks (the south wall keeps the passage arch open)
	var rows := int(ceil(h / 0.7))
	for rr in rows:
		var y := (float(rr) + 0.5) * h / float(rows)
		var rh := h / float(rows) - 0.05
		var wy := base_y + y
		for side in 4:
			var ln := r.size.x
			var nx := 0.0
			var nz := 0.0
			match side:
				0:
					nz = half           # south (+z local)
				1:
					nz = -half
				2:
					nx = half
				3:
					nx = -half
			var along_x := side < 2
			var u := -ln * 0.5
			while u < ln * 0.5 - 0.01:
				var bl := minf(rng.randf_range(0.8, 1.4), ln * 0.5 - u)
				var um := u + bl * 0.5
				var cx := um if along_x else nx
				var cz := nz if along_x else um
				var cut := side == 0 and wy < pass_top + 0.1 and absf(um) < inner + 0.4
				if not cut:
					var col := STONE.lerp(STONE_DARK, rng.randf() * 0.55)
					if wy < hb - 0.9:
						col = col.lerp(Color("4a5a50"), 0.45)   # waterline algae
					var size := Vector3(bl - 0.04, rh, 0.5) if along_x else Vector3(0.5, rh, bl - 0.04)
					m.add(NodeVisuals._box(size), Transform3D(Basis(), Vector3(cx, y, cz)), col)
				u += bl
	# inner fill above the passage so the tower reads solid
	var f0 := pass_top - base_y + 0.1
	var f1 := h - 0.2
	m.add(NodeVisuals._box(Vector3(r.size.x - 0.8, f1 - f0, r.size.y - 0.8)), Transform3D(Basis(), Vector3(0, (f0 + f1) * 0.5, 0)), STONE_DARK)
	# the passage: side walls, ceiling and the back of the foundation (upright, like its collision)
	var pw := NodeVisuals.Merger.new()
	var back_z0 := float(Reach.BELLHOUSE["bottom_end_z"]) + 0.2
	var pz := (south + back_z0) * 0.5
	var plen := absf(south - back_z0)
	for sgn in [-1.0, 1.0]:
		pw.add(NodeVisuals._box(Vector3(0.5, pass_top - bottom + 0.3, plen)), Transform3D(Basis(), Vector3(sx + float(sgn) * (inner + 0.25), (bottom + pass_top) * 0.5, pz)), STONE_DARK)
	pw.add(NodeVisuals._box(Vector3(inner * 2.0 + 1.0, 0.5, plen)), Transform3D(Basis(), Vector3(sx, pass_top + 0.25, pz)), STONE_DARK.darkened(0.2))
	var pmi := MeshInstance3D.new()
	pmi.name = "Passage"
	pmi.mesh = pw.commit()
	pmi.material_override = Props.stone_mat()
	add_child(pmi)
	# corner quoins and two string courses
	for qx in [-1.0, 1.0]:
		for qz in [-1.0, 1.0]:
			m.add(NodeVisuals._box(Vector3(0.62, h, 0.62)), Transform3D(Basis(), Vector3(float(qx) * half, h * 0.5, float(qz) * half)), Color("b8ae9e"))
	for sy in [hb + 3.2 - base_y, body_top - base_y - 0.2]:
		m.add(NodeVisuals._box(Vector3(r.size.x + 0.3, 0.2, r.size.y + 0.3)), Transform3D(Basis(), Vector3(0, float(sy), 0)), Color("c2b8a8"))
	# the passage arch in the foundation (visible from the stair)
	var ay := pass_top - base_y
	for k in 7:
		var a := PI * float(k) / 6.0
		m.add(NodeVisuals._box(Vector3(0.55, 0.42, 0.6)), Transform3D(Basis(Vector3.BACK, a), Vector3(-cos(a) * (inner + 0.15), ay - 0.2 + sin(a) * 0.35, half + 0.05)), Color("b8ae9e"))
	# the reassuring upper window (warm, always lit) and a darker side window
	var wy2 := hb + 4.6 - base_y
	m.add(NodeVisuals._box(Vector3(1.3, 1.8, 0.2)), Transform3D(Basis(), Vector3(0, wy2, half + 0.18)), Color("c2b8a8"))
	m.add(NodeVisuals._box(Vector3(1.5, 0.14, 0.4)), Transform3D(Basis(), Vector3(0, wy2 - 0.95, half + 0.28)), Color("b8ae9e"))
	m.add(Kit.blob_mesh(0.22, 7280, 0.3, 0.6, 1), Transform3D(Basis(), Vector3(-0.35, wy2 - 0.75, half + 0.35)), Color("d9822f"))
	m.add(Kit.blob_mesh(0.2, 7281, 0.3, 0.6, 1), Transform3D(Basis(), Vector3(0.3, wy2 - 0.75, half + 0.35)), Color("b8423a"))
	m.add(NodeVisuals._box(Vector3(0.7, 1.1, 0.2)), Transform3D(Basis(), Vector3(half + 0.18, wy2 + 0.6, -0.5)), Color("3a3440"))
	# belfry: corner pillars, open arches, the cracked bell, a slate roof
	var bf := body_top - base_y
	for qx in [-1.0, 1.0]:
		for qz in [-1.0, 1.0]:
			m.add(NodeVisuals._box(Vector3(0.9, 2.7, 0.9)), Transform3D(Basis(), Vector3(float(qx) * (half - 0.45), bf + 1.35, float(qz) * (half - 0.45))), STONE)
	m.add(NodeVisuals._box(Vector3(r.size.x + 0.2, 0.35, r.size.y + 0.2)), Transform3D(Basis(), Vector3(0, bf + 2.85, 0)), Color("b8ae9e"))
	var roof_y := bf + 3.0
	var apex := Vector3(0, roof_y + 3.6, 0)
	var o := half + 0.5
	var corners := [Vector3(-o, roof_y, -o), Vector3(o, roof_y, -o), Vector3(o, roof_y, o), Vector3(-o, roof_y, o)]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n := (b - a).cross(apex - a).normalized()
		if n.y < 0.0:
			n = -n
		m.tri(a, apex, b, n, SLATE, SLATE.lightened(0.15), SLATE, true)
	m.add(NodeVisuals._cyl(0.05, 0.08, 0.9, 6), Transform3D(Basis(), apex + Vector3(0, 0.4, 0)), Color("3a3440"))
	m.add(NodeVisuals._cyl(0.08, 0.2, 0.3, 8), Transform3D(Basis(), apex + Vector3(0, 0.95, 0)), Color("c9a24a"))
	var bell := Vector3(0, bf + 1.55, 0)
	m.add(NodeVisuals._cyl(0.35, 0.8, 1.2, 12), Transform3D(Basis(), bell), Color("8a6a3a"))
	m.add(NodeVisuals._cyl(0.82, 0.82, 0.12, 12), Transform3D(Basis(), bell - Vector3(0, 0.6, 0)), Color("7a5a30"))
	m.add(NodeVisuals._box(Vector3(0.05, 0.9, 0.05)), Transform3D(Basis(Vector3.BACK, 0.35), bell + Vector3(0.45, -0.1, 0.62)), Color("201818"))
	m.add(NodeVisuals._box(Vector3(r.size.x - 1.0, 0.18, 0.18)), Transform3D(Basis(), bell + Vector3(0, 0.75, 0)), Palette.WOOD_DARK)
	# ivy and moss
	for k in 9:
		var a := rng.randf() * TAU
		var y := rng.randf_range(hb - base_y, bf)
		m.add(Kit.blob_mesh(0.42, 7290 + k, 0.4, 0.6, 1), Transform3D(Basis(), Vector3(cos(a) * (half + 0.2), y, sin(a) * (half + 0.2))), [Color("8a3a2a"), Color("b8662f"), Color("5f6b4a")][k % 3])
	var tmi := MeshInstance3D.new()
	tmi.mesh = m.commit()
	tmi.material_override = Props.stone_mat()
	tmi.visibility_range_end = 260.0
	tower.add_child(tmi)
	# window panes (warm) + the always-on window light
	var pane := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 1.4)
	pane.mesh = q
	pane.material_override = Mat.glow(Color("ffc978"), 1.6)
	pane.position = Vector3(0, wy2 + 0.05, half + 0.3)
	tower.add_child(pane)
	window_light = OmniLight3D.new()
	window_light.name = "WindowLight"
	window_light.light_color = Color("ffc07a")
	window_light.light_energy = 1.3
	window_light.omni_range = 7.5
	window_light.shadow_enabled = false
	window_light.position = Vector3(0, wy2, half + 1.0)
	tower.add_child(window_light)
	# the dark doorway at the back of the passage
	var door := MeshInstance3D.new()
	var dq := QuadMesh.new()
	dq.size = Vector2(inner * 2.0, 2.9)
	door.mesh = dq
	door.material_override = Mat.glow(Color("07060b"), 0.0)
	door.position = Vector3(sx, bottom + 1.45, back_z + 0.02)
	add_child(door)


func _build_gate() -> void:
	var B: Dictionary = Reach.BELLHOUSE
	var sx: float = B["stair_x"]
	gate = LowerGate.new()
	gate.setup({"flag": GATE_FLAG, "key": KEY, "locked_text": locked_text(), "width": 2.6, "height": 2.5})
	gate.name = "ServiceGate"
	add_child(gate)
	gate.position = Vector3(sx, bottom, float(B["gate_z"]))
	descent = Descent.new()
	descent.setup({"gate": gate, "locked_text": locked_text()})
	add_child(descent)
	descent.position = Vector3(sx, bottom, float(B["descent_z"]))
	descent.rotation.y = PI


## The heavy slabs over the stairwell (sealed state) and the stack they end up in (revealed state).
func _build_lid() -> void:
	var sx: float = Reach.BELLHOUSE["stair_x"]
	_lid = Node3D.new()
	_lid.name = "Lid"
	add_child(_lid)
	_lid_body = StaticBody3D.new()
	_lid_body.name = "LidBody"
	_lid_body.collision_layer = 1
	_lid_body.collision_mask = 0
	_lid_body.set_meta("surface", "stone")
	_lid.add_child(_lid_body)
	var m := NodeVisuals.Merger.new()
	var runes := NodeVisuals.Merger.new()
	var segs := [[-76.6, -79.6], [-79.6, -82.6], [-82.6, -85.5]]
	for i in segs.size():
		var za: float = segs[i][0]
		var zb: float = segs[i][1]
		var zc := (za + zb) * 0.5
		var ln := absf(zb - za)
		m.add(NodeVisuals._box(Vector3(2.96, 0.36, ln - 0.06)), Transform3D(Basis(), Vector3(sx, hb - 0.13, zc)), Color("a39a8e").darkened(0.05 * float(i)))
		Props.box_col(_lid_body, Transform3D(Basis(), Vector3(sx, hb - 0.13, zc)), Vector3(2.96, 0.36, ln))
		# a lantern shape carved on each slab (three lanterns: link them to open the stair)
		var cz := zc
		runes.add(NodeVisuals._box(Vector3(0.36, 0.02, 0.55)), Transform3D(Basis(), Vector3(sx, hb + 0.06, cz)), Color.WHITE)
		runes.add(NodeVisuals._box(Vector3(0.5, 0.02, 0.08)), Transform3D(Basis(), Vector3(sx, hb + 0.06, cz - 0.34)), Color.WHITE)
		runes.add(NodeVisuals._box(Vector3(0.5, 0.02, 0.08)), Transform3D(Basis(), Vector3(sx, hb + 0.06, cz + 0.34)), Color.WHITE)
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.stone_mat()
	_lid.add_child(mi)
	var rmi := MeshInstance3D.new()
	rmi.mesh = runes.commit()
	rmi.material_override = Mat.toon(Color("6a5a4e"), {"rim": 0.4, "emission": Color("c9a24a"), "emission_energy": 0.15})
	_lid.add_child(rmi)
	seal = Interactable.new()
	seal.setup({"text_func": Callable(self, "_seal_prompt"), "size": Vector3(3.0, 1.6, 8.5),
		"offset": Vector3(sx, hb + 0.8, -81.0), "marker_y": hb + 2.2})
	seal.name = "SealedStair"
	_lid.add_child(seal)
	# the stack beside the forecourt (revealed state)
	var pp: Vector2 = Reach.BELLHOUSE["slab_pile"]
	_pile = Node3D.new()
	_pile.name = "SlabPile"
	add_child(_pile)
	_pile.position = Vector3(pp.x, terrain.height_at(pp.x, pp.y), pp.y)
	var pm := NodeVisuals.Merger.new()
	for i in 3:
		pm.add(NodeVisuals._box(Vector3(2.6, 0.34, 2.7)), Transform3D(Basis(Vector3.UP, 0.12 * float(i - 1)), Vector3(0, 0.17 + float(i) * 0.35, 0)), Color("a39a8e").darkened(0.05 * float(i)))
	var pmi := MeshInstance3D.new()
	pmi.mesh = pm.commit()
	pmi.material_override = Props.stone_mat()
	_pile.add_child(pmi)
	var pb := StaticBody3D.new()
	pb.name = "PileBody"
	pb.collision_mask = 0
	pb.set_meta("surface", "stone")
	_pile.add_child(pb)
	Props.box_col(pb, Transform3D(Basis(), Vector3(0, 0.55, 0)), Vector3(2.6, 1.1, 2.7))


func _seal_prompt() -> Dictionary:
	if is_revealed():
		return {}
	return {"text": "A sealed stair", "enabled": false, "reason": Descent.SEALED_TEXT}


# --- Forecourt ------------------------------------------------------------------------------------------------

func _build_forecourt() -> void:
	var fc: Vector2 = Reach.BELLHOUSE["forecourt"]
	var sx: float = Reach.BELLHOUSE["stair_x"]
	var m := NodeVisuals.Merger.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7373
	for k in 44:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 5.6
		var p := fc + Vector2(cos(a), sin(a)) * r
		if absf(p.x - sx) < 1.7 and p.y < -76.0:
			continue
		m.add(Kit.blob_mesh(0.5, 7400 + k, 0.1, 0.12, 1), Transform3D(Basis(Vector3.UP, a).scaled(Vector3(1.2, 1.0, 0.95)), Vector3(p.x, terrain.height_at(p.x, p.y) + 0.02, p.y)), Color("b3aa9c").lerp(Color("8f877c"), rng.randf() * 0.6))
	var fmi := MeshInstance3D.new()
	fmi.name = "Forecourt"
	fmi.mesh = m.commit()
	fmi.material_override = Props.stone_mat()
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fmi.visibility_range_end = 120.0
	add_child(fmi)
	sign_it = _post_sign(Reach.BELLHOUSE["sign"], "Read the sign", "Mind\nthe stair", Callable(self, "_read_sign"))
	plaque_it = _bell_stone(Reach.BELLHOUSE["plaque"])


func _post_sign(p: Vector2, prompt: String, painted: String, handler: Callable) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(p.x, terrain.height_at(p.x, p.y) - 0.03, p.y)
	root.rotation.y = Props.face_yaw(p, Reach.SPAWNS["bellhouse_stair"]["pos"])
	var sm := NodeVisuals.Merger.new()
	sm.add(NodeVisuals._box(Vector3(0.1, 1.5, 0.1)), Transform3D(Basis(), Vector3(0, 0.75, 0)), Palette.WOOD_DARK)
	sm.add(NodeVisuals._box(Vector3(0.95, 0.6, 0.06)), Transform3D(Basis(Vector3.BACK, -0.04), Vector3(0, 1.35, 0.05)), Palette.WOOD_LIGHT)
	var smi := MeshInstance3D.new()
	smi.mesh = sm.commit()
	smi.material_override = Props.wood_mat()
	root.add_child(smi)
	Props.sign_text(root, painted, Transform3D(Basis(Vector3.BACK, -0.04), Vector3(0, 1.35, 0.05)), Vector2(0.95, 0.6), 0.06,
		{"back": false, "font_size": 40, "px": 0.004, "outline": 6})
	Props.box_col(_body, Transform3D(Basis(Vector3.UP, root.rotation.y), root.position + Vector3(0, 0.75, 0)), Vector3(0.95, 1.5, 0.15))
	var it := Interactable.new()
	it.setup({"text": prompt, "size": Vector3(1.2, 1.6, 1.0), "offset": Vector3(0, 0.9, 0.35), "handler": handler, "marker_y": 2.2})
	it.name = "SignInteract"
	root.add_child(it)
	return it


func _bell_stone(p: Vector2) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(p.x, terrain.height_at(p.x, p.y) - 0.05, p.y)
	root.rotation.y = Props.face_yaw(p, Reach.SPAWNS["bellhouse_stair"]["pos"])
	var m := NodeVisuals.Merger.new()
	m.add(NodeVisuals._cyl(0.3, 0.55, 1.1, 10), Transform3D(Basis(), Vector3(0, 0.55, 0)), Color("b3aa9c"))
	m.add(NodeVisuals._sph(0.3, 5, 10), Transform3D(Basis(), Vector3(0, 1.1, 0)), Color("b3aa9c"))
	m.add(NodeVisuals._box(Vector3(0.5, 0.36, 0.04)), Transform3D(Basis(), Vector3(0, 0.7, 0.44)), Color("c9a24a"))
	var mi := MeshInstance3D.new()
	mi.mesh = m.commit()
	mi.material_override = Props.stone_mat()
	root.add_child(mi)
	Props.cyl_col(_body, root.position, 0.55, 1.3)
	var it := Interactable.new()
	it.setup({"text": "Read the plaque", "size": Vector3(1.2, 1.4, 1.2), "offset": Vector3(0, 0.8, 0.4),
		"handler": Callable(self, "_read_plaque"), "marker_y": 2.0})
	it.name = "PlaqueInteract"
	root.add_child(it)
	return it


func _read_sign(_player: Node) -> void:
	Audio.play_ui("ui_open", -8.0)
	Events.say.emit("Bellhouse Sign", REMINDER, 8.0)


func _read_plaque(_player: Node) -> void:
	var l: Dictionary = LoreData.get_lore("lore_ch2_bellhouse")
	GameState.discover_lore("lore_ch2_bellhouse")
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l["title"]), String(l["text"]), 9.0)
