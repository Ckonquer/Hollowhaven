extends Node3D
## The Foreman's desk: a lore note ("The Foreman's Order") and the Foreman's Key on a hook board.
## The key is guaranteed: it is available whenever the player doesn't hold it and the gate is still
## locked, and it is never duplicated. Taking it sets flag "foreman_key_taken".
## The node's local -Z faces the room (the desk stands against a wall behind it at +Z).

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Interactable := preload("res://src/world/below/below_interactable.gd")
const Lamp := preload("res://src/world/below/below_lamp.gd")
const Lore := preload("res://src/world/below/lore.gd")

const KEY := "foreman_key"
const NOTE_ID := "foreman_order"

var _key_node: Node3D
var _key_it: Node3D
var _note_it: Node3D


static func key_available() -> bool:
	return not GameState.has_item(KEY) and not bool(GameState.get_flag("lower_gate_open"))


func _ready() -> void:
	_build()
	_note_it = Interactable.new()
	_note_it.setup({"text": "Read the foreman's note", "size": Vector3(0.8, 0.6, 0.7), "offset": Vector3(0, 0.95, 0), "handler": Callable(self, "_read_note"), "accent": true, "accent_color": Color("ffe9b8")})
	_note_it.position = Vector3(-0.45, 0.0, 0.05)
	add_child(_note_it)
	_key_it = Interactable.new()
	_key_it.setup({"text": "Take the Foreman's Key", "size": Vector3(0.7, 0.8, 0.6), "offset": Vector3(0, 1.45, 0), "handler": Callable(self, "_take_key"), "text_func": Callable(self, "_key_text")})
	_key_it.position = Vector3(0.55, 0.0, 0.25)
	add_child(_key_it)
	_refresh()
	Events.inventory_changed.connect(_refresh)
	Events.key_item_added.connect(_on_key_item)


func _on_key_item(_id: String) -> void:
	_refresh()


func _build() -> void:
	var wood := Mat.outlined(Mat.toon(Color("8e6340")), 0.02)
	var wood_dark := Mat.outlined(Mat.toon(Color("5a3b27")), 0.018)
	var iron := Mat.outlined(Mat.toon(Color("4a4048"), {"rim": 0.4}), 0.012)
	var paper := Mat.toon(Color("efe0bd"), {"emission": Color("efe0bd"), "emission_energy": 0.08})
	# Desk
	Kit.add(self, Kit.box(Vector3(1.9, 0.1, 0.9), wood), Vector3(0, 0.82, 0))
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.5, 0.78, 0.8), wood_dark), Vector3(sx * 0.68, 0.39, 0))
		Kit.add(self, Kit.box(Vector3(0.36, 0.05, 0.02), iron), Vector3(sx * 0.68, 0.6, -0.41))
	Kit.add(self, Kit.box(Vector3(0.86, 0.5, 0.05), wood_dark), Vector3(0, 0.5, 0.37))
	# Papers, ink pot, the note
	Kit.add(self, Kit.box(Vector3(0.34, 0.012, 0.44), paper), Vector3(-0.45, 0.88, 0.02), Vector3(0, 12, 0))
	Kit.add(self, Kit.box(Vector3(0.3, 0.012, 0.4), Mat.toon(Color("e2d1a8"))), Vector3(-0.2, 0.876, 0.12), Vector3(0, -8, 0))
	Kit.add(self, Kit.cylinder(0.05, 0.06, 0.09, Mat.toon(Color("2b2a3f")), 8), Vector3(0.05, 0.92, 0.25))
	Kit.add(self, Kit.box(Vector3(0.02, 0.2, 0.02), Mat.toon(Color("f3e6c8"))), Vector3(0.07, 1.0, 0.25), Vector3(0, 0, 20))
	# Ledger books
	for i in 3:
		Kit.add(self, Kit.box(Vector3(0.24, 0.07, 0.34), Mat.outlined(Mat.toon([Color("8a3b3b"), Color("3b5a6e"), Color("5a6e3b")][i]), 0.01)), Vector3(0.62, 0.91 + float(i) * 0.075, -0.05), Vector3(0, float(i) * 9.0 - 6.0, 0))
	# Chair
	Kit.add(self, Kit.box(Vector3(0.5, 0.07, 0.5), wood), Vector3(-0.2, 0.48, -0.75))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Kit.add(self, Kit.box(Vector3(0.06, 0.46, 0.06), wood_dark), Vector3(-0.2 + sx * 0.2, 0.23, -0.75 + sz * 0.2))
	Kit.add(self, Kit.box(Vector3(0.5, 0.55, 0.06), wood), Vector3(-0.2, 0.78, -0.98), Vector3(-8, 0, 0))
	# Hook board on the wall behind with the key
	Kit.add(self, Kit.box(Vector3(0.9, 0.55, 0.05), wood), Vector3(0.55, 1.5, 0.45))
	for i in 3:
		Kit.add(self, Kit.cylinder(0.012, 0.012, 0.08, iron, 6), Vector3(0.3 + float(i) * 0.25, 1.62, 0.41), Vector3(90, 0, 0))
	_key_node = Node3D.new()
	add_child(_key_node)
	_key_node.position = Vector3(0.55, 1.5, 0.39)
	var brass := Mat.outlined(Mat.toon(Color("c9b27a"), {"rim": 0.7, "emission": Color("c9a25a"), "emission_energy": 0.35}), 0.012)
	Kit.add(_key_node, Kit.torus(0.035, 0.07, brass), Vector3(0, 0.08, 0), Vector3(90, 0, 0))
	Kit.add(_key_node, Kit.box(Vector3(0.035, 0.22, 0.03), brass), Vector3(0, -0.07, 0))
	Kit.add(_key_node, Kit.box(Vector3(0.07, 0.035, 0.03), brass), Vector3(0.03, -0.15, 0))
	Kit.add(_key_node, Kit.box(Vector3(0.05, 0.03, 0.03), brass), Vector3(0.025, -0.09, 0))
	Kit.add(_key_node, Kit.sphere(0.03, Mat.glow(Color("ffe29a"), 1.5), 6, 8), Vector3(0, 0.08, 0.02))
	# Oil lamp on the desk (warm pool of light, flickers with the director)
	var lamp: Node3D = Lamp.new()
	lamp.setup({"style": "glow", "color": Color("ffb45c"), "energy": 1.4, "range": 5.0, "shadow": true, "flame": Color("ffc978")})
	lamp.position = Vector3(-0.72, 1.12, 0.1)
	add_child(lamp)
	Kit.add(self, Kit.cylinder(0.07, 0.09, 0.14, Mat.outlined(Mat.toon(Color("b07a4f")), 0.01), 10), Vector3(-0.72, 0.95, 0.1))
	Kit.add(self, Kit.cylinder(0.06, 0.06, 0.16, Mat.transparent(Color(1.0, 0.9, 0.7, 0.25), true), 10), Vector3(-0.72, 1.1, 0.1))
	# Desk collision
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 0.9, 0.9)
	cs.shape = sh
	cs.position = Vector3(0, 0.45, 0)
	body.add_child(cs)
	add_child(body)


func _refresh() -> void:
	if _key_node == null:
		return
	var avail := key_available()
	_key_node.visible = avail


func _key_text() -> Dictionary:
	if not key_available():
		return {}
	return {"text": "Take the Foreman's Key", "enabled": true}


func _take_key(_player: Node) -> void:
	if not key_available():
		return
	GameState.give_item(KEY, 1)
	GameState.set_flag("foreman_key_taken", true)
	Audio.play_3d("pickup", _key_node.global_position)
	Events.say.emit("", "A heavy iron key, stamped with a pickaxe. It's still warm from the lamp.", 3.5)
	_refresh()


func _read_note(_player: Node) -> void:
	var l: Dictionary = Lore.get_lore(NOTE_ID)
	GameState.discover_lore(NOTE_ID)
	Audio.play_ui("ui_open", -6.0)
	Events.say.emit(String(l.get("title", "")), String(l.get("text", "")), 9.0)
