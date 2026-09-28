extends Node3D
## A door of the Hushed Works that opens for good once ALL its flags are set (GameState flags: the open state
## persists and is restored on load without animation). Blocks the doorway with a StaticBody3D (layer 1) while
## closed; opening slides the panel away and removes the collision at once.
## Local frame: width along X, height along Y, thickness along Z (rotate the node to fit the wall).
## Styles: "grate" (iron portcullis, slides up), "face" (a carved stone face slab, sinks into the floor),
## "shutter" (brass shutter, slides up), "ward" (the lower ward door: three line glyphs that light one by one,
## a readable prompt that names the missing lines; opens sideways into the walls).
##   var d = WorksDoor.new()
##   d.setup({"size": Vector3(3.5, 3.4, 0.5), "flags": ["ch2_refuge_shortcut"], "style": "grate"})

signal opened

const Palette := preload("res://src/art/palette.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const IRON := Color("333a46")
const BRASS := Color("c9a25a")
const STONE := Color("b9b2a3")
const STONE_DARK := Color("6f7480")
## Ward door glyphs: flag -> [symbol, lit colour, name].
const WARD_GLYPHS := {
	"ch2_line_water": ["water", Color("7fd0e8"), "water"],
	"ch2_line_bell": ["bell", Color("f0b060"), "bell"],
	"ch2_line_light": ["light", Color("ffe8a0"), "light"],
}

var size: Vector3 = Vector3(3.0, 3.2, 0.4)
var flags: Array = []
var style: String = "grate"
var door_name: String = "The door"
var closed_text: String = ""
var is_open: bool = false

var _body: StaticBody3D
var _panel: Node3D
var _panel_b: Node3D                  # ward: the second leaf
var _glyphs: Dictionary = {}          # flag -> {"on": Node3D, "off": Node3D, "light": OmniLight3D}
var _marker: Node3D
var _tween: Tween


func setup(p: Dictionary) -> void:
	size = p.get("size", size)
	flags = (p.get("flags", flags) as Array).duplicate()
	style = String(p.get("style", style))
	door_name = String(p.get("name", door_name))
	closed_text = String(p.get("closed_text", closed_text))


func _ready() -> void:
	_build()
	_body = StaticBody3D.new()
	_body.name = "Block"
	_body.collision_layer = 1
	_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(size.x, size.y, maxf(size.z, 0.3))
	cs.shape = sh
	cs.position = Vector3(0, size.y * 0.5, 0)
	_body.add_child(cs)
	add_child(_body)
	if style == "ward" or closed_text != "":
		add_to_group("interactable")
		var a := Area3D.new()
		a.name = "InteractArea"
		a.collision_layer = 16
		a.collision_mask = 0
		a.monitoring = false
		var acs := CollisionShape3D.new()
		var ash := BoxShape3D.new()
		ash.size = Vector3(size.x, 2.2, 1.2)
		acs.shape = ash
		acs.position = Vector3(0, 1.1, 0.4)
		a.add_child(acs)
		add_child(a)
	Events.flag_set.connect(_on_flag)
	Events.settings_changed.connect(_on_settings_changed)
	_refresh_glyphs()
	if all_set():
		open(false)
	_update_marker()


func all_set() -> bool:
	for f in flags:
		if not bool(GameState.get_flag(String(f))):
			return false
	return true


## Flags still missing (the ward door names them).
func missing() -> Array:
	var out: Array = []
	for f in flags:
		if not bool(GameState.get_flag(String(f))):
			out.append(String(f))
	return out


func open(animate: bool = true) -> void:
	if is_open:
		return
	is_open = true
	_body.collision_layer = 0
	for c in _body.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = true
	if is_in_group("interactable"):
		remove_from_group("interactable")
	var ia := get_node_or_null("InteractArea")
	if ia != null:
		ia.queue_free()
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var to_a := _open_offset(false)
	var to_b := _open_offset(true)
	if not animate or not is_inside_tree():
		if _panel != null:
			_panel.position = to_a
		if _panel_b != null:
			_panel_b.position = to_b
		_finish_open()
		return
	Audio.play_3d("gate_unlock" if style != "face" else "door_creak", global_position + Vector3.UP * 1.5, -3.0)
	_tween = create_tween().set_parallel(true)
	if _panel != null:
		_tween.tween_property(_panel, "position", to_a, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _panel_b != null:
		_tween.tween_property(_panel_b, "position", to_b, 2.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.chain().tween_callback(_finish_open)
	_update_marker()


func _finish_open() -> void:
	if style != "ward" and _panel != null:
		_panel.visible = style == "face"      # the face slab stays as a threshold stone; bars/shutters are gone
	opened.emit()
	_update_marker()


func _open_offset(second: bool) -> Vector3:
	match style:
		"face":
			return Vector3(0, -size.y + 0.06, 0)
		"ward":
			return Vector3((size.x * 0.52) * (1.0 if second else -1.0), 0, -0.1)
	return Vector3(0, size.y - 0.15, 0)


func get_interaction(_player: Node = null) -> Dictionary:
	if is_open:
		return {}
	if style == "ward":
		var names: Array = []
		for f in missing():
			names.append(String(WARD_GLYPHS.get(f, ["", Color.WHITE, f])[2]))
		var reason := "Asleep: the %s line%s." % [" and ".join(names), "s" if names.size() > 1 else ""]
		return {"text": door_name, "enabled": false, "reason": reason}
	return {"text": door_name, "enabled": false, "reason": closed_text}


func interact(_player: Node = null) -> void:
	var d := get_interaction()
	if d.is_empty():
		return
	Events.notify.emit(String(d.get("reason", "")), "info")


func _on_flag(flag: String, _v: Variant) -> void:
	if not flags.has(flag):
		return
	_refresh_glyphs(true)
	if all_set() and not is_open:
		open(true)


func _on_settings_changed(key: String) -> void:
	if key == "high_visibility_cues":
		_update_marker()


# --- Visuals ------------------------------------------------------------------------------------------------

func _build() -> void:
	match style:
		"grate":
			_panel = Node3D.new()
			add_child(_panel)
			var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.35}), 0.014)
			var n := int(size.x / 0.24)
			for i in n + 1:
				var x := -size.x * 0.5 + float(i) * size.x / float(maxi(n, 1))
				Kit.add(_panel, Kit.cylinder(0.035, 0.035, size.y, iron, 6), Vector3(x, size.y * 0.5, 0))
			for y in [0.12, size.y * 0.5, size.y - 0.1]:
				Kit.add(_panel, Kit.box(Vector3(size.x, 0.1, 0.12), iron), Vector3(0, y, 0))
		"shutter":
			_panel = Node3D.new()
			add_child(_panel)
			var brass := Mat.outlined(Mat.toon(BRASS, {"rim": 0.4, "specular": 0.4}), 0.014)
			var slats := int(size.y / 0.32)
			for i in slats:
				Kit.add(_panel, Kit.box(Vector3(size.x, 0.28, 0.1), brass), Vector3(0, 0.16 + float(i) * 0.32, 0))
			Kit.add(_panel, Kit.sphere(0.12, Mat.glow(Color("ffe8a0"), 1.6), 6, 8), Vector3(0, size.y * 0.5, 0.1))
		"face":
			_panel = Node3D.new()
			add_child(_panel)
			var stone := Mat.outlined(Mat.toon(STONE_DARK.lightened(0.15), {"rim": 0.2, "noise": 0.12}), 0.016)
			var dark := Mat.toon(STONE_DARK.darkened(0.35))
			Kit.add(_panel, Kit.box(Vector3(size.x, size.y, size.z), stone), Vector3(0, size.y * 0.5, 0))
			# a big serene face, eyes shut, mouth a closed line
			var f := Vector3(0, size.y * 0.55, size.z * 0.5 + 0.04)
			Kit.add(_panel, Kit.blob(0.9, stone, 21, 0.12, 1.3), f, Vector3.ZERO, Vector3(1.2, 1.1, 0.3))
			for sx in [-1.0, 1.0]:
				Kit.add(_panel, Kit.box(Vector3(0.42, 0.06, 0.08), dark), f + Vector3(sx * 0.36, 0.28, 0.24), Vector3(0, 0, -sx * 8.0))
			Kit.add(_panel, Kit.box(Vector3(0.5, 0.06, 0.08), dark), f + Vector3(0, -0.42, 0.24))
			Kit.add(_panel, Kit.prism(Vector3(0.3, 0.5, 0.3), stone), f + Vector3(0, -0.02, 0.26))
		"ward":
			var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.35}), 0.016)
			var brass := Mat.outlined(Mat.toon(BRASS, {"rim": 0.45, "specular": 0.4}), 0.014)
			_panel = Node3D.new()
			add_child(_panel)
			_panel_b = Node3D.new()
			add_child(_panel_b)
			for leaf in [[_panel, -1.0], [_panel_b, 1.0]]:
				var p: Node3D = leaf[0]
				var sx: float = leaf[1]
				Kit.add(p, Kit.box(Vector3(size.x * 0.5, size.y, 0.22), iron), Vector3(sx * size.x * 0.25, size.y * 0.5, 0))
				for y in [0.5, 1.6, 2.7]:
					Kit.add(p, Kit.box(Vector3(size.x * 0.5 - 0.1, 0.1, 0.06), brass), Vector3(sx * size.x * 0.25, y, 0.13))
			# three glyph plates above the leaves (fixed to the frame, not the leaves)
			var i := 0
			for f in ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]:
				if not flags.has(f):
					continue
				var g: Array = WARD_GLYPHS[f]
				var pos := Vector3(-1.1 + float(i) * 1.1, size.y + 0.55, 0.2)
				i += 1
				Kit.add(self, Kit.cylinder(0.42, 0.42, 0.1, brass, 16), pos, Vector3(90, 0, 0))
				var off := _glyph(String(g[0]), Mat.toon(Color("4b4f58")))
				var on := _glyph(String(g[0]), Mat.glow(g[1], 2.4))
				for gn in [off, on]:
					add_child(gn)
					gn.position = pos + Vector3(0, 0, 0.08)
				var l := OmniLight3D.new()
				l.light_color = g[1]
				l.light_energy = 0.7
				l.omni_range = 2.6
				l.shadow_enabled = false
				add_child(l)
				l.position = pos + Vector3(0, 0, 0.6)
				_glyphs[f] = {"on": on, "off": off, "light": l}
			# heavy stone arch
			var stone := Mat.outlined(Mat.toon(STONE_DARK, {"noise": 0.12}), 0.016)
			Kit.add(self, Kit.box(Vector3(size.x + 1.2, 1.3, 0.7), stone), Vector3(0, size.y + 0.6, -0.1))


## A glyph (same silhouettes as the service signs: drop / bell / sun), ~0.5 m.
func _glyph(symbol: String, m: Material) -> Node3D:
	var n := Node3D.new()
	match symbol:
		"water":
			Kit.add(n, Kit.sphere(0.13, m, 8, 10), Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
			Kit.add(n, Kit.cone(0.1, 0.2, m, 8), Vector3(0, 0.12, 0))
		"bell":
			Kit.add(n, Kit.cone(0.16, 0.28, m, 10), Vector3(0, 0.02, 0))
			Kit.add(n, Kit.sphere(0.05, m, 6, 8), Vector3(0, -0.16, 0))
		_:
			Kit.add(n, Kit.sphere(0.11, m, 8, 10), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.4))
			for k in 8:
				var a := TAU * float(k) / 8.0
				Kit.add(n, Kit.box(Vector3(0.04, 0.1, 0.03), m), Vector3(sin(a) * 0.19, cos(a) * 0.19, 0), Vector3(0, 0, -rad_to_deg(a)))
	return n


func _refresh_glyphs(animate: bool = false) -> void:
	for f in _glyphs:
		var on := bool(GameState.get_flag(String(f)))
		var g: Dictionary = _glyphs[f]
		(g["on"] as Node3D).visible = on
		(g["off"] as Node3D).visible = not on
		var l: OmniLight3D = g["light"]
		l.visible = on
		if on and animate and is_inside_tree():
			l.light_energy = 0.0
			create_tween().tween_property(l, "light_energy", 0.7, 1.2)


## high_visibility_cues: a bold ring on the ground in front of a closed ward door (never colour alone).
func _update_marker() -> void:
	var want := style == "ward" and not is_open and bool(Settings.get_value("high_visibility_cues"))
	if want and _marker == null:
		_marker = Kit.add(self, Kit.torus(0.9, 1.05, Mat.glow(Color("fff1c4"), 1.8)), Vector3(0, 0.03, 1.4))
		_marker.scale = Vector3(1.0, 0.2, 1.0)
	if _marker != null:
		_marker.visible = want
