extends Node3D
## Tobin's side door (docs/CHAPTER_TWO_SPEC.md §1, §7.1; MP §7 "Tobin's Lost Shift").
## variant "surface": a small timbered adit on the mine cliff beside the legacy mine mouth (built by
##   src/world/surface/c1x/tobin_door.gd): leads to tobin_annex / annex_entry. It stays jammed until the
##   mine mouth's rubble is cleared (flag mine_opened); the first trip below shows the comfort screen when it
##   was never seen (legacy flag mine_comfort_seen, exactly like the mine entrance).
## variant "interior": the same door seen from the lamp room (ta_entry): back out to surface / annex_door.
## Origin on the floor at the threshold; +Z points to where Krystal stands, -Z goes through the door.
## Interaction contract: groups "interactable" + "area_exit" (target_area / target_spawn / use_respawn are read
## by the flow tests), a layer-16 StaticBody "Interact"; solid posts/walls on layer 1.
##   var d = AnnexDoor.new(); d.setup({"variant": "surface", "target_area": "tobin_annex", "target_spawn":
##       "annex_entry", "requires_flag": "mine_opened"}); parent.add_child(d)

signal travelled(area: String, spawn: String)   # just before Game.change_area (tests listen)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/surface/props.gd")
const AnnexProps := preload("res://src/world/annex/annex_props.gd")

const COMFORT_FLAG := "mine_comfort_seen"
const DOOR_W := 1.62
const DOOR_H := 2.45
const ADIT_DEPTH := 4.4
## Rock cladding around the surface adit (local pos, scale, variant): merges it into the cliff and the
## boulders at the cliff foot. Visual only.
const ROCKS := [
	[Vector3(-1.75, 0.15, -1.3), 1.2, 0], [Vector3(1.8, 0.1, -1.7), 1.25, 1], [Vector3(-1.45, 2.95, -2.6), 1.15, 2],
	[Vector3(1.35, 3.05, -2.8), 1.2, 0], [Vector3(0.0, 3.35, -3.7), 1.35, 1], [Vector3(-2.15, 1.55, -3.3), 1.05, 2],
	[Vector3(2.3, 1.65, -3.5), 1.05, 0],
]

var variant: String = "surface"
var text: String = "Go through Tobin's side door"
var target_area: String = "tobin_annex"
var target_spawn: String = "annex_entry"
var requires_flag: String = ""
var locked_text: String = "Jammed shut. The rockfall at the mine mouth pins the frame."
var use_respawn: bool = false
var ask_comfort: bool = false
var travel_enabled: bool = true          # tests turn real travel off and listen to `travelled`

var _busy: bool = false
var _leaf_pivot: Node3D
var _crack: MeshInstance3D
var _jam: Node3D


func setup(p: Dictionary) -> void:
	variant = String(p.get("variant", variant))
	if variant == "interior":
		text = "Back out to the mine mouth"
		target_area = "surface"
		target_spawn = "annex_door"
	text = String(p.get("text", text))
	target_area = String(p.get("target_area", target_area))
	target_spawn = String(p.get("target_spawn", target_spawn))
	requires_flag = String(p.get("requires_flag", requires_flag))
	locked_text = String(p.get("locked_text", locked_text))
	ask_comfort = bool(p.get("comfort", variant == "surface"))


func _ready() -> void:
	name = "TobinDoor" if variant == "surface" else "TobinDoorInside"
	add_to_group("interactable")
	add_to_group("area_exit")
	if variant == "surface":
		_build_surface()
	else:
		_build_interior()
	_apply_state()
	Events.flag_set.connect(_on_flag_set)


func is_unlocked() -> bool:
	return requires_flag == "" or bool(GameState.get_flag(requires_flag))


## {"area", "spawn"} this door leads to (area_exit contract).
func destination() -> Dictionary:
	return {"area": target_area, "spawn": target_spawn}


func get_interaction(_player: Node = null) -> Dictionary:
	if _busy:
		return {}
	if not is_unlocked():
		return {"text": "Tobin's side door", "enabled": false, "reason": locked_text}
	return {"text": text, "enabled": true}


func interact(_player: Node = null) -> void:
	if _busy:
		return
	if not is_unlocked():
		Events.notify.emit(locked_text, "info")
		return
	if Game.mode != "playing" and travel_enabled:
		return
	_busy = true
	if ask_comfort and not bool(GameState.get_flag(COMFORT_FLAG)):
		var accepted: bool = await _ask_comfort()
		if not accepted or not is_inside_tree():
			_busy = false
			return
		GameState.set_flag(COMFORT_FLAG, true)
	Audio.play_3d("door_creak", global_position + Vector3.UP * 1.2, -4.0)
	travelled.emit(target_area, target_spawn)
	if not travel_enabled:
		_busy = false
		return
	# Fire and forget: the area change frees this node. If the change is refused (another transition is
	# running) the node survives, so re-arm after a moment; the tween dies with the node.
	create_tween().tween_callback(func() -> void: _busy = false).set_delay(4.0)
	Game.change_area(target_area, target_spawn)


## The comfort screen before the first trip underground (same rule as the legacy mine entrance). Fails
## open (true) without a UI or comfort panel so the door can never become unusable.
func _ask_comfort() -> bool:
	var ui: Node = Game.ui
	if ui == null or not is_instance_valid(ui) or not ui.has_method("show_comfort"):
		return true
	ui.call("show_comfort", false)
	var panels: Variant = ui.get("panels")
	var p: Variant = (panels as Dictionary).get("comfort") if panels is Dictionary else null
	if not is_instance_valid(p) or not (p as Object).has_signal("confirmed"):
		return true
	var panel: Object = p
	await Signal(panel, "confirmed")
	if not is_instance_valid(panel):
		return true
	var acc: Variant = panel.get("accepted")
	return bool(acc) if acc is bool else true


func _on_flag_set(flag_name: String, _value: Variant) -> void:
	if flag_name == requires_flag:
		_apply_state()


## Locked: the leaf is shut and two fallen stones lean on it. Open: the leaf stands ajar with warm light
## in the crack (surface) / a thin line of daylight (inside).
func _apply_state() -> void:
	var open := is_unlocked()
	if _leaf_pivot != null:
		_leaf_pivot.rotation.y = deg_to_rad(-14.0) if open and variant == "surface" else 0.0
	if _crack != null:
		_crack.visible = open
	if _jam != null:
		_jam.visible = not open


# --- Visuals -------------------------------------------------------------------------------------------

func _timber_mat() -> Material:
	return Mat.outlined(Mat.toon(Palette.MINE_TIMBER, {"noise": 0.14, "noise_scale": 2.0, "rim": 0.2}), 0.02)


func _plank_mat() -> Material:
	return Mat.outlined(Mat.toon(Palette.WOOD_DARK, {"noise": 0.16, "noise_scale": 2.4, "rim": 0.18}), 0.016)


func _iron_mat() -> Material:
	return Mat.outlined(Mat.toon(Color("3b3238"), {"rim": 0.4}), 0.012)


func _build_leaf(z: float) -> void:
	_leaf_pivot = Node3D.new()
	_leaf_pivot.name = "Leaf"
	add_child(_leaf_pivot)
	_leaf_pivot.position = Vector3(-DOOR_W * 0.5, 0.0, z)
	var planks := _plank_mat()
	var iron := _iron_mat()
	for i in 5:
		var w := DOOR_W / 5.0
		Kit.add(_leaf_pivot, Kit.box(Vector3(w - 0.015, DOOR_H - 0.04 * float(i % 2), 0.07), planks), Vector3(w * (float(i) + 0.5), DOOR_H * 0.5, 0))
	for y: float in [0.45, 1.25, 2.05]:
		Kit.add(_leaf_pivot, Kit.box(Vector3(DOOR_W - 0.08, 0.09, 0.03), iron), Vector3(DOOR_W * 0.5, y, 0.05))
	Kit.add(_leaf_pivot, Kit.torus(0.03, 0.08, iron), Vector3(DOOR_W * 0.82, 1.15, 0.08))


func _solid_box(body: StaticBody3D, size: Vector3, pos: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = size
	cs.shape = bx
	cs.transform = Transform3D(basis, pos)
	body.add_child(cs)


func _interact_body(radius: float, pos: Vector3) -> void:
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	cs.position = pos
	ib.add_child(cs)
	add_child(ib)


func _build_surface() -> void:
	var timber := _timber_mat()
	var planks := _plank_mat()
	var iron := _iron_mat()
	var half := DOOR_W * 0.5 + 0.14
	# Frame: posts and a heavy lintel.
	for sx: float in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.28, DOOR_H + 0.35, 0.3), timber), Vector3(float(sx) * half, (DOOR_H + 0.35) * 0.5, 0.05))
	Kit.add(self, Kit.box(Vector3(DOOR_W + 0.95, 0.34, 0.38), timber), Vector3(0, DOOR_H + 0.3, 0.07), Vector3(0, 0, 1.5))
	# The adit: plank-clad side walls running back into the cliff and a lean-to plank roof.
	for sx: float in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.3, 2.9, ADIT_DEPTH), planks), Vector3(float(sx) * 1.2, 1.45, -ADIT_DEPTH * 0.5 + 0.2))
		for i in 3:
			Kit.add(self, Kit.box(Vector3(0.34, 2.95, 0.22), timber), Vector3(float(sx) * 1.2, 1.47, 0.1 - float(i) * 1.4))
	Kit.add(self, Kit.box(Vector3(2.95, 0.18, ADIT_DEPTH + 0.6), planks), Vector3(0, 3.18, -ADIT_DEPTH * 0.5 + 0.2), Vector3(4.0, 0, 0))
	# Dark interior behind the leaf (seen through the crack when it stands ajar).
	var void_mat := StandardMaterial3D.new()
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	void_mat.albedo_color = Color(0.05, 0.035, 0.03)
	var back := MeshInstance3D.new()
	back.mesh = NodeVisuals._box(Vector3(DOOR_W + 0.1, DOOR_H + 0.1, 0.05))
	back.material_override = void_mat
	back.position = Vector3(0, DOOR_H * 0.5, -0.9)
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)
	# Warm lamplight in the gap of the ajar door (visible only when it can be used).
	_crack = MeshInstance3D.new()
	_crack.name = "Crack"
	_crack.mesh = NodeVisuals._box(Vector3(DOOR_W - 0.2, DOOR_H - 0.2, 0.02))
	_crack.material_override = Mat.glow(Color("ffb35c"), 0.9)
	_crack.position = Vector3(0.1, DOOR_H * 0.5, -0.7)
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	_build_leaf(-0.14)
	# Name plate: stamped with a miner's name.
	Kit.add(self, Kit.box(Vector3(1.05, 0.26, 0.05), Mat.toon(Palette.WOOD, {"rim": 0.3})), Vector3(0, DOOR_H + 0.3, 0.28), Vector3(0, 0, -2.0))
	var plate := AnnexProps.label(self, "TOBIN", Vector3(0, DOOR_H + 0.3, 0.31), Basis(Vector3(0, 0, 1), deg_to_rad(-2.0)), 64, Color("3b2a22"), 0.004)
	plate.name = "NamePlate"
	# A miner's lamp on an iron arm, lit: it catches the eye from the mine path.
	var arm_y := DOOR_H + 0.05
	var arm_x := 1.2
	Kit.add(self, Kit.box(Vector3(0.06, 0.06, 0.55), iron), Vector3(arm_x, arm_y, 0.47))
	Kit.add(self, Kit.cylinder(0.012, 0.012, 0.22, iron, 6), Vector3(arm_x, arm_y - 0.12, 0.7))
	var glass := Props.instance(Props.lantern_glass(), Mat.glow(Palette.MINE_LIGHT, 1.6), 0.0, false)
	glass.position = Vector3(arm_x, arm_y - 0.36, 0.7)
	add_child(glass)
	var l := OmniLight3D.new()
	l.name = "DoorLamp"
	l.light_color = Palette.MINE_LIGHT
	l.light_energy = 0.8
	l.omni_range = 4.5
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = 50.0
	l.distance_fade_length = 10.0
	add_child(l)
	l.position = glass.position + Vector3(0, 0.05, 0.1)
	# Rock cladding that ties the adit into the cliff.
	var rock_mat := NodeVisuals.rock_material(0.03)
	for r in ROCKS:
		var ri := Props.instance(NodeVisuals.boulder_mesh(int(r[2]), Palette.STONE, 0.6), rock_mat)
		ri.position = r[0]
		ri.scale = Vector3.ONE * float(r[1])
		ri.rotation.y = float(r[2]) * 1.7 + 0.4
		add_child(ri)
	# Two stones jammed against the shut leaf (hidden once the mine mouth is cleared).
	_jam = Node3D.new()
	_jam.name = "Jam"
	add_child(_jam)
	var jr := Props.instance(NodeVisuals.boulder_mesh(1, Palette.STONE_DARK, 0.2), rock_mat)
	jr.position = Vector3(-0.35, 0.0, 0.2)
	jr.scale = Vector3.ONE * 0.45
	_jam.add_child(jr)
	var jr2 := Props.instance(NodeVisuals.boulder_mesh(2, Palette.STONE_DARK, 0.2), rock_mat)
	jr2.position = Vector3(0.3, 0.0, 0.25)
	jr2.scale = Vector3.ONE * 0.35
	_jam.add_child(jr2)
	# Collision: posts, adit walls and a plate behind the leaf (the door is used, never walked through).
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	add_child(body)
	for sx: float in [-1.0, 1.0]:
		_solid_box(body, Vector3(0.3, DOOR_H + 0.35, 0.32), Vector3(float(sx) * half, (DOOR_H + 0.35) * 0.5, 0.05))
		_solid_box(body, Vector3(0.3, 2.9, ADIT_DEPTH), Vector3(float(sx) * 1.2, 1.45, -ADIT_DEPTH * 0.5 + 0.2))
	_solid_box(body, Vector3(DOOR_W + 0.3, DOOR_H + 0.4, 0.3), Vector3(0, (DOOR_H + 0.4) * 0.5, -0.35))
	_interact_body(1.25, Vector3(0, 1.1, 0.45))


func _build_interior() -> void:
	var timber := _timber_mat()
	var half := DOOR_W * 0.5 + 0.13
	for sx: float in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.26, DOOR_H + 0.2, 0.24), timber), Vector3(float(sx) * half, (DOOR_H + 0.2) * 0.5, 0.12))
	Kit.add(self, Kit.box(Vector3(DOOR_W + 0.7, 0.3, 0.3), timber), Vector3(0, DOOR_H + 0.12, 0.14))
	Kit.add(self, Kit.box(Vector3(DOOR_W + 0.4, 0.05, 0.4), timber), Vector3(0, 0.025, 0.2))
	_build_leaf(0.04)
	# A thin line of daylight around the leaf: the way out is always easy to find.
	_crack = MeshInstance3D.new()
	_crack.name = "Crack"
	var day := Mat.glow(Color("dfe9ff"), 1.4)
	_crack.mesh = NodeVisuals._box(Vector3(0.04, DOOR_H - 0.1, 0.02))
	_crack.material_override = day
	_crack.position = Vector3(DOOR_W * 0.5 - 0.03, DOOR_H * 0.5, 0.085)
	_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crack)
	var sill := MeshInstance3D.new()
	sill.mesh = NodeVisuals._box(Vector3(DOOR_W - 0.1, 0.03, 0.02))
	sill.material_override = day
	sill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crack.add_child(sill)
	sill.position = Vector3(-DOOR_W * 0.5 + 0.03, -DOOR_H * 0.5 + 0.06, 0.0)
	var body := StaticBody3D.new()
	body.name = "Solid"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	add_child(body)
	for sx: float in [-1.0, 1.0]:
		_solid_box(body, Vector3(0.26, DOOR_H + 0.2, 0.24), Vector3(float(sx) * half, (DOOR_H + 0.2) * 0.5, 0.12))
	_interact_body(1.2, Vector3(0, 1.1, 0.55))
