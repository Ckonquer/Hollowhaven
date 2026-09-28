extends Node3D
## A service lift cage of the deep Works. The node's local -Z faces out of the cage (toward the room).
## kind "true":  its signal lamp is a REAL light (OmniLight3D + group light_source) that pools warm light
##               on the brass landing plate in front of the cage, and its sign reads normally.
## kind "false": the same cage and the same warm-looking lamp, but the lamp lights nothing (no Light3D,
##               not a light_source), its landing plate stays dark and its sign reads backwards
##               (The Wrong Landing, MP §10 room 11: a readable lighting flaw, two cues, never colour alone).
## The ride itself is done by `handler` (deep_controller.gd): handler(lift_node). requires_flag gates it.
##   var l = Lift.new(); l.setup({"id": "hw_lift_real", "kind": "true", "text": "Ride the lift up",
##       "handler": Callable(ctl, "_on_lift"), "sign": "LIFT - REFUGE LEVEL"})
## Sign: a 2 m board with its label 5 cm in front (toward the cage mouth), the text fitted to SIGN_TEXT_WIDTH; optional
## "sign_pos" (local centre of the board, default SIGN_POS over the cage mouth) hangs it elsewhere, e.g. on the face of
## a recess lintel. The false lift's mirrored sign is double-sided (a mirrored single-sided Label3D is culled from the
## front); its board hides the back.

signal used(lift_id: String)

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Art := preload("res://src/world/works/deep/deep_art.gd")
const CameraBlock := preload("res://src/camera/camera_block.gd")

const PLATE_OFFSET := Vector3(0.0, 0.0, -1.55)   # the landing plate in front of the cage (local)
const LAMP_POS := Vector3(0.0, 2.95, -1.2)
## Camera-only box over the cage roof, pulley, signal lamp and sign (local): the follow camera stops in front of
## them instead of sitting inside the cage top (visual QA IN-04 / IN-05). Starts at the cage roof (2.52 m), so
## Krystal's camera pivot (1.38 m, ~2.4 m mid-jump) is never inside it, even when she stands in the cage.
const CAMERA_BLOCK_CENTER := Vector3(0.0, 3.21, 0.0)
const CAMERA_BLOCK_SIZE := Vector3(2.4, 1.38, 2.8)
const SIGN_POS := Vector3(0.0, 3.55, -1.05)       # default board centre (local), over the cage mouth
const SIGN_BOARD_W := 2.0
const SIGN_TEXT_WIDTH := 1.8                      # the label is fitted to this (VISUAL_BUGS IN-08)

var lift_id: String = ""
var kind: String = "true"
var text: String = "Ride the lift"
var locked_text: String = "The lift cage is stuck"
var requires_flag: String = ""
var sign_text: String = ""
var sign_pos: Vector3 = SIGN_POS
var handler: Callable
var light_radius: float = 3.2          # Combat.light_at (true lamp only)
var light_strength: float = 0.8

var _light: OmniLight3D
var _plate_glow: MeshInstance3D
var _gate: Node3D
var _hv: MeshInstance3D


func setup(p: Dictionary) -> void:
	lift_id = String(p.get("id", lift_id))
	kind = String(p.get("kind", kind))
	text = String(p.get("text", text))
	locked_text = String(p.get("locked_text", locked_text))
	requires_flag = String(p.get("requires_flag", requires_flag))
	sign_text = String(p.get("sign", sign_text))
	if p.get("sign_pos") is Vector3:
		sign_pos = p["sign_pos"]
	if p.has("handler"):
		handler = p["handler"]


func is_true_lift() -> bool:
	return kind == "true"


func usable() -> bool:
	return requires_flag == "" or bool(GameState.get_flag(requires_flag))


## True only for the real lift: its lamp is a Light3D that reaches the landing plate.
func lamp_lights_plate() -> bool:
	return _light != null and _light.visible and _light.omni_range > (LAMP_POS - PLATE_OFFSET).length()


func plate_position() -> Vector3:
	return to_global(PLATE_OFFSET) if is_inside_tree() else position + transform.basis * PLATE_OFFSET


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("hw_lift")
	_build()
	var a := Area3D.new()
	a.name = "InteractArea"
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.4, 2.4, 1.4)
	cs.shape = sh
	cs.position = Vector3(0, 1.2, -1.2)
	a.add_child(cs)
	add_child(a)
	Events.flag_set.connect(_on_flag)
	Events.settings_changed.connect(_on_settings_changed)
	_refresh()


func _on_flag(flag: String, _v: Variant) -> void:
	if requires_flag != "" and flag == requires_flag:
		_refresh()


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_refresh()


func _build() -> void:
	var iron := Mat.outlined(Mat.toon(Color("4f6e5c") if kind != "bell" else Color("7a5a3a"), {"rim": 0.45}), 0.018)
	var dark := Mat.outlined(Mat.toon(Color("3a3034"), {"rim": 0.4}), 0.016)
	var plank := Mat.toon(Color("8e6340"))
	var brass := Mat.outlined(Mat.toon(Color("c89a4a"), {"rim": 0.5, "specular": 0.4}), 0.014)
	# Cage: floor, corner posts, bars on three sides, roof, pulley and cable into the shaft.
	Kit.add(self, Kit.box(Vector3(2.2, 0.12, 2.2), plank), Vector3(0, 0.06, 0.2))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Kit.add(self, Kit.box(Vector3(0.12, 2.6, 0.12), iron), Vector3(sx * 1.05, 1.3, 0.2 + sz * 1.05))
	for i in 7:
		Kit.add(self, Kit.cylinder(0.025, 0.025, 2.4, iron, 6), Vector3(-0.9 + float(i) * 0.3, 1.25, 1.25))
	for side in [-1.0, 1.0]:
		for i in 6:
			Kit.add(self, Kit.cylinder(0.025, 0.025, 2.4, iron, 6), Vector3(side * 1.05, 1.25, -0.55 + float(i) * 0.3))
	Kit.add(self, Kit.box(Vector3(2.3, 0.14, 2.3), dark), Vector3(0, 2.62, 0.2))
	Kit.add(self, Kit.torus(0.22, 0.34, dark), Vector3(0, 3.05, 0.2), Vector3(0, 0, 90))
	Kit.add(self, Kit.cylinder(0.03, 0.03, 1.4, dark, 6), Vector3(0, 3.8, 0.2))
	# Folding gate: drawn shut across the cage mouth while the lift can't be used.
	_gate = Node3D.new()
	_gate.name = "Gate"
	add_child(_gate)
	for i in 7:
		Kit.add(_gate, Kit.cylinder(0.02, 0.02, 2.2, iron, 6), Vector3(-0.9 + float(i) * 0.3, 1.2, -0.85))
	Kit.add(_gate, Kit.box(Vector3(2.0, 0.06, 0.06), iron), Vector3(0, 1.2, -0.85))
	# Landing plate in front (the lamp's light pools here - or doesn't)
	Kit.add(self, Kit.cylinder(0.75, 0.75, 0.04, brass, 20), PLATE_OFFSET + Vector3(0, 0.02, 0))
	_plate_glow = Kit.cylinder(0.72, 0.72, 0.02, Mat.glow(Palette.LANTERN_GLOW, 0.55), 20)
	Kit.add(self, _plate_glow, PLATE_OFFSET + Vector3(0, 0.05, 0))
	_plate_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Signal lamp on a bracket above the cage mouth: identical look for both kinds.
	Kit.add(self, Kit.box(Vector3(0.08, 0.08, 0.7), dark), Vector3(0, 3.2, -0.85))
	Kit.add(self, Kit.cylinder(0.14, 0.17, 0.08, dark, 10), LAMP_POS + Vector3(0, 0.22, 0))
	Kit.add(self, Kit.cylinder(0.12, 0.12, 0.3, Mat.transparent(Color(1.0, 0.86, 0.6, 0.25), true), 10), LAMP_POS)
	Kit.add(self, Kit.sphere(0.08, Mat.glow(Palette.LANTERN_GLOW, 3.0), 8, 10), LAMP_POS)
	if kind == "true" or kind == "bell":
		_light = OmniLight3D.new()
		_light.name = "SignalLight"
		_light.light_color = Palette.LANTERN_GLOW
		_light.light_energy = 1.6
		_light.omni_range = 4.6
		_light.omni_attenuation = 0.9
		_light.shadow_enabled = false
		_light.distance_fade_enabled = true
		_light.distance_fade_begin = 30.0
		_light.distance_fade_length = 8.0
		add_child(_light)
		_light.position = LAMP_POS + Vector3(0, -0.1, 0)
		add_to_group("light_source")
	else:
		# The flaw: a dark disc of "shadow" on the plate where light should fall.
		var shade := Kit.cylinder(0.7, 0.7, 0.02, Mat.toon(Color(0.05, 0.05, 0.06), {"rim": 0.0}), 20)
		Kit.add(self, shade, PLATE_OFFSET + Vector3(0, 0.055, 0))
	if sign_text != "":
		var board := Kit.box(Vector3(SIGN_BOARD_W, 0.42, 0.06), Mat.outlined(Mat.toon(Color("2e3a34")), 0.014))
		Kit.add(self, board, sign_pos)
		board.name = "SignBoard"
		var l := Art.label(self, sign_text, sign_pos + Vector3(0, 0, -0.05), 34, Color("f3e6c8"))
		l.name = "Sign"
		l.rotation_degrees = Vector3(0, 180, 0)
		Art.fit_label(l, SIGN_TEXT_WIDTH)
		if kind == "false":
			l.scale = Vector3(-1, 1, 1)      # reads backwards: the second, non-colour cue
			l.double_sided = true            # a mirrored single-sided label would be culled from the front
	# Solid cage walls (back and sides) so nobody walks through the bars.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	for spec in [[Vector3(0, 1.3, 1.3), Vector3(2.3, 2.6, 0.12)], [Vector3(-1.1, 1.3, 0.2), Vector3(0.12, 2.6, 2.3)], [Vector3(1.1, 1.3, 0.2), Vector3(0.12, 2.6, 2.3)]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = spec[1]
		cs.shape = sh
		cs.position = spec[0]
		body.add_child(cs)
	add_child(body)
	CameraBlock.add_box(self, CAMERA_BLOCK_CENTER, CAMERA_BLOCK_SIZE)
	_hv = Art.bold_ring(self, 0.95)
	_hv.position = PLATE_OFFSET + Vector3(0, 0.06, 0)


func _refresh() -> void:
	var ok := usable()
	var real := kind != "false"
	if _light != null:
		_light.visible = ok
	if _plate_glow != null:
		_plate_glow.visible = real and ok
	if _gate != null:
		_gate.visible = not ok
	if _hv != null:
		_hv.visible = real and ok and Art.high_visibility()
	if real and ok:
		add_to_group("light_source")
	elif is_in_group("light_source"):
		remove_from_group("light_source")


func is_light_active() -> bool:
	return kind != "false" and usable()


func get_interaction(_player: Node = null) -> Dictionary:
	if not usable():
		return {"text": locked_text, "enabled": false}
	return {"text": text, "enabled": true}


func interact(_player: Node = null) -> void:
	if not usable():
		return
	used.emit(lift_id)
	if handler.is_valid():
		handler.call(self)
