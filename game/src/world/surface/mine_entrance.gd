extends Node3D
## The Hollow Mine entrance in the north-east cliff: timber frame, a dark tunnel mouth, old rails,
## a tipped cart, lantern hooks and a RUBBLE pile sealing it (resource_node, pickaxe, 4 hits,
## node id "mine_rubble", never respawns, sets flag "mine_opened"). Once open, an interactable
## "Enter the Hollow Mine" (first time: Game.ui.show_comfort(false); closing it with Esc / X instead of
## Done stays on the surface) -> Game.change_area("below", "mine_entry").
## Place with its origin on the apron floor at the frame, -Z pointing INTO the mountain.

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const ResourceNode := preload("res://src/world/common/resource_node.gd")
const Fx := preload("res://src/world/common/fx.gd")
const Props := preload("res://src/world/surface/props.gd")

const RUBBLE_ID := "mine_rubble"
const OPEN_FLAG := "mine_opened"
const COMFORT_FLAG := "mine_comfort_seen"

var terrain: RefCounted          # optional, for placing rails on the ground
var rubble: Node3D
var enter_body: StaticBody3D
var opened := false
var _entering := false
var _lantern_lights: Array = []


func _ready() -> void:
	name = "MineEntrance"
	add_to_group("interactable")
	_sync_state()
	_build()


## Makes the flag and the depleted rubble agree (either one implies the mine is open).
func _sync_state() -> void:
	var flag := bool(GameState.get_flag(OPEN_FLAG))
	var dep := GameState.is_depleted(RUBBLE_ID)
	if flag and not dep:
		GameState.deplete(RUBBLE_ID, -1.0)
	elif dep and not flag:
		GameState.set_flag(OPEN_FLAG, true)
	opened = flag or dep


func _build() -> void:
	var wood := Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "noise": 0.14, "noise_scale": 2.0, "rim": 0.2}), 0.022)
	var frame := NodeVisuals.Merger.new()
	var timber := Palette.MINE_TIMBER
	var w := 3.4
	var h := 3.3
	for sx in [-1.0, 1.0]:
		frame.add(NodeVisuals._box(Vector3(0.36, h + 0.2, 0.36)), Transform3D(Basis(Vector3.BACK, deg_to_rad(float(sx) * -3.0)), Vector3(float(sx) * w * 0.5, h * 0.5, 0)), timber)
		# braces
		var bb := Basis(Vector3.BACK, deg_to_rad(float(sx) * 45.0))
		frame.add(NodeVisuals._box(Vector3(0.18, 0.9, 0.2)), Transform3D(bb, Vector3(float(sx) * (w * 0.5 - 0.42), h - 0.42, 0.05)), timber.darkened(0.1))
	frame.add(NodeVisuals._box(Vector3(w + 0.9, 0.42, 0.42)), Transform3D(Basis(Vector3.BACK, deg_to_rad(1.5)), Vector3(0, h + 0.1, 0)), timber.lightened(0.05))
	frame.add(NodeVisuals._box(Vector3(w + 0.4, 0.2, 0.3)), Transform3D(Basis(), Vector3(0, h - 0.25, -0.05)), timber.darkened(0.15))
	# name board above the lintel
	frame.add(NodeVisuals._box(Vector3(1.9, 0.5, 0.08)), Transform3D(Basis(Vector3.BACK, deg_to_rad(-2.0)), Vector3(0, h + 0.62, 0.2)), Palette.WOOD)
	for sx in [-0.8, 0.8]:
		frame.add(NodeVisuals._cyl(0.012, 0.012, 0.35, 4), Transform3D(Basis(), Vector3(float(sx), h + 0.5, 0.2)), Palette.STONE_DARK)
	var fm := MeshInstance3D.new()
	fm.name = "Frame"
	fm.mesh = frame.commit()
	fm.material_override = wood
	add_child(fm)
	var board := Label3D.new()
	board.text = "Hollow Mine"
	board.font = load("res://assets/fonts/Fredoka-Variable.ttf") if ResourceLoader.exists("res://assets/fonts/Fredoka-Variable.ttf") else null
	board.font_size = 64
	board.pixel_size = 0.004
	board.modulate = Color("3b2a22")
	board.outline_size = 0
	board.position = Vector3(0, h + 0.63, 0.25)
	board.rotation_degrees = Vector3(0, 0, -2.0)
	board.double_sided = false
	add_child(board)
	# The dark mouth: a deep-shadow panel just inside the frame with a soft vignette.
	var void_mat := StandardMaterial3D.new()
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_mat.albedo_color = Color(0.035, 0.028, 0.04)
	var mouth := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w - 0.1, h + 0.1)
	mouth.mesh = qm
	mouth.material_override = void_mat
	mouth.position = Vector3(0, h * 0.5 - 0.05, -0.35)
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mouth)
	var inner := MeshInstance3D.new()
	inner.mesh = NodeVisuals._box(Vector3(w - 0.1, h + 0.1, 0.1))
	inner.material_override = void_mat
	inner.position = Vector3(0, h * 0.5 - 0.05, -0.45)
	add_child(inner)
	# Rock shoulders framing the timber so it reads as cut into the cliff.
	var rock_mat := NodeVisuals.rock_material(0.03)
	var shoulders: Array = [[Vector3(-2.7, 1.2, -0.6), 1.5, 0], [Vector3(2.8, 1.0, -0.5), 1.4, 1], [Vector3(-1.6, 4.1, -0.8), 1.3, 2],
		[Vector3(1.9, 4.2, -0.9), 1.4, 0], [Vector3(0.1, 4.6, -1.0), 1.2, 1], [Vector3(-3.4, 2.9, -1.2), 1.2, 2], [Vector3(3.5, 2.8, -1.1), 1.2, 1]]
	for sd in shoulders:
		var r := Props.instance(NodeVisuals.boulder_mesh(int(sd[2]), Palette.STONE_DARK, 0.5), rock_mat)
		r.position = sd[0]
		r.scale = Vector3.ONE * float(sd[1])
		r.rotation.y = float(sd[2]) * 1.3
		add_child(r)
	# Rails + sleepers running out onto the apron
	var rails := NodeVisuals.Merger.new()
	var rail_len := 9.0
	for i in 11:
		var z := 0.3 + float(i) * 0.85
		var y := _ground_y(Vector3(0, 0, z)) + 0.04
		rails.add(NodeVisuals._box(Vector3(1.5, 0.08, 0.24)), Transform3D(Basis(), Vector3(0, y, z)), Palette.WOOD_DARK)
	for sx in [-0.5, 0.5]:
		for seg in 6:
			var z0 := float(seg) * rail_len / 6.0
			var z1 := float(seg + 1) * rail_len / 6.0
			var p0 := Vector3(float(sx), _ground_y(Vector3(float(sx), 0, z0)) + 0.12, z0)
			var p1 := Vector3(float(sx), _ground_y(Vector3(float(sx), 0, z1)) + 0.12, z1)
			var dir := p1 - p0
			var rb := Basis(Vector3.RIGHT, -atan2(dir.y, dir.z))
			rails.add(NodeVisuals._box(Vector3(0.07, 0.07, dir.length() + 0.02)), Transform3D(rb, (p0 + p1) * 0.5), Palette.STONE_DARK.darkened(0.2))
	var rm := MeshInstance3D.new()
	rm.name = "Rails"
	rm.mesh = rails.commit()
	rm.material_override = Mat.toon(Color.WHITE, {"vertex_color": true, "specular": 0.3})
	add_child(rm)
	# A tipped old cart beside the rails
	var cart := NodeVisuals.Merger.new()
	cart.add(NodeVisuals._box(Vector3(1.1, 0.65, 0.8)), Transform3D(Basis(), Vector3(0, 0.55, 0)), Palette.MINE_TIMBER)
	cart.add(NodeVisuals._box(Vector3(1.14, 0.08, 0.84)), Transform3D(Basis(), Vector3(0, 0.88, 0)), Palette.STONE_DARK)
	for wx in [-0.35, 0.35]:
		for wz in [-0.42, 0.42]:
			cart.add(NodeVisuals._cyl(0.16, 0.16, 0.08, 10), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3(float(wx), 0.18, float(wz))), Palette.STONE_DARK.darkened(0.3))
	for i in 3:
		cart.add(Kit.blob_mesh(0.18, 9400 + i, 0.3, 0.8, 1), Transform3D(Basis(), Vector3(-0.2 + float(i) * 0.2, 0.9, 0.05 * float(i))), Palette.COPPER.darkened(0.2))
	var cm := MeshInstance3D.new()
	cm.name = "Cart"
	cm.mesh = cart.commit()
	cm.material_override = wood
	add_child(cm)
	var cart_pos := Vector3(2.6, 0, 3.4)
	cm.position = Vector3(cart_pos.x, _ground_y(cart_pos), cart_pos.z)
	cm.rotation_degrees = Vector3(0, 25, -8)
	# Lantern hooks either side (dim warm glow)
	for sx in [-1.0, 1.0]:
		var post := Props.instance(Props.lantern_post(), wood)
		post.position = Vector3(float(sx) * (w * 0.5 + 0.9), _ground_y(Vector3(float(sx) * (w * 0.5 + 0.9), 0, 0.6)), 0.6)
		post.rotation.y = 0.0 if sx < 0.0 else PI
		add_child(post)
		var glass := MeshInstance3D.new()
		glass.mesh = Props.lantern_glass()
		glass.material_override = Mat.glow(Palette.MINE_LIGHT, 1.6)
		glass.position = post.position + post.basis * Vector3(0.38, Props.LANTERN_Y, 0)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glass)
		var l := OmniLight3D.new()
		l.light_color = Palette.MINE_LIGHT
		l.light_energy = 0.7
		l.omni_range = 4.5
		l.shadow_enabled = false
		l.position = glass.position
		add_child(l)
		_lantern_lights.append(l)
	# Collision: frame posts and the cart; the mouth itself is blocked by the rubble (or the cliff).
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	add_child(body)
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.4, h + 0.3, 0.45)
		cs.shape = bx
		cs.position = Vector3(float(sx) * w * 0.5, h * 0.5, 0)
		body.add_child(cs)
	var back := CollisionShape3D.new()
	var bk := BoxShape3D.new()
	bk.size = Vector3(w, h + 1.0, 0.5)
	back.shape = bk
	back.position = Vector3(0, h * 0.5, -0.7)
	body.add_child(back)
	var ccs := CollisionShape3D.new()
	var cbx := BoxShape3D.new()
	cbx.size = Vector3(1.1, 0.9, 0.8)
	ccs.shape = cbx
	ccs.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), cm.position + Vector3(0, 0.45, 0))
	body.add_child(ccs)
	# Rubble seal
	rubble = ResourceNode.new()
	rubble.setup({"node_id": RUBBLE_ID, "kind": "rubble", "tool": "pickaxe", "hits": 4, "respawn_minutes": -1.0,
		"flag": OPEN_FLAG, "name": "Rubble", "tint": Palette.STONE_DARK, "scale": 1.55, "seed": 0,
		"drops": [{"item": "stone", "min": 2, "max": 3, "chance": 1.0}]})
	rubble.position = Vector3(0, 0, 0.35)
	add_child(rubble)
	rubble.harvested_out.connect(_on_rubble_cleared)
	# Doorway interaction (active once open)
	enter_body = StaticBody3D.new()
	enter_body.name = "Interact"
	enter_body.collision_mask = 0
	var ecs := CollisionShape3D.new()
	var ebx := BoxShape3D.new()
	ebx.size = Vector3(w - 0.4, h - 0.3, 1.2)
	ecs.shape = ebx
	ecs.position = Vector3(0, h * 0.5, 0.2)
	enter_body.add_child(ecs)
	add_child(enter_body)
	_set_open_state(opened)


func _ground_y(local: Vector3) -> float:
	if terrain == null or not is_inside_tree():
		return 0.0
	var g: Vector3 = global_transform * local
	return float(terrain.height_at(g.x, g.z)) - global_position.y


func _set_open_state(is_open: bool) -> void:
	opened = is_open
	if enter_body != null:
		enter_body.collision_layer = 16 if is_open else 0


func _on_rubble_cleared(_n: Node3D) -> void:
	_set_open_state(true)
	Fx.burst(get_parent(), global_position + global_transform.basis * Vector3(0, 1.2, 0.5), "dust", 2.0)
	Events.camera_shake.emit(0.3, 0.5)
	Events.notify.emit("The way into the Hollow Mine is clear.", "quest")
	Audio.play_3d("rock_break", global_position + Vector3.UP, 2.0)


# --- Interaction -------------------------------------------------------------------------------------

func get_interaction(_player: Node = null) -> Dictionary:
	if not opened or _entering:
		return {}
	return {"text": "Enter the Hollow Mine", "enabled": true}


func interact(_player: Node = null) -> void:
	if not opened or _entering:
		return
	_entering = true
	if not GameState.get_flag(COMFORT_FLAG):
		var accepted: bool = await _ask_comfort()
		if not accepted:
			# Closed with Esc / X: "not now" (as on the title screen). Stay up here; ask again next time.
			_entering = false
			return
		GameState.set_flag(COMFORT_FLAG, true)
	if not is_inside_tree():
		return
	GameState.set_flag("entered_below", true)
	Audio.play_sfx("door_creak", -4.0)
	# Fire and forget: this node is freed by the area change. If the change is refused (another
	# transition already running) the node survives, so re-arm the doorway after a moment instead of
	# leaving the mine unenterable until the next load. The tween dies with the node.
	create_tween().tween_callback(func() -> void: _entering = false).set_delay(4.0)
	Game.change_area("below", "mine_entry")


## Shows the comfort screen before the first descent (awaitable). True when it was closed with its
## Done button; false when it was closed with Esc / X. Fails open (true) without a UI or comfort panel,
## so the mine can never become unenterable. Reads the panel's `accepted` itself, so it works whether
## or not ui_root.show_comfort() reports how the screen was closed.
func _ask_comfort() -> bool:
	var ui: Node = Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("show_comfort"):
		return true
	ui.call("show_comfort", false)          # opens the panel (or finds the open one); its own await ends on close
	var panels: Variant = ui.get("panels")
	var p: Variant = (panels as Dictionary).get("comfort") if panels is Dictionary else null
	if not is_instance_valid(p) or not (p as Object).has_signal("confirmed"):
		return true
	var panel: Object = p
	await Signal(panel, "confirmed")         # emitted from on_close() on every close path
	if not is_instance_valid(panel):
		return true
	var acc: Variant = panel.get("accepted")
	if acc is bool:
		return bool(acc)
	return true
