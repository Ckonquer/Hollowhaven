extends Node3D
## What the Matron holds on to at the Weaver's Crossing's authored ceiling anchors (MP 13.2), owned by the boss
## (top_level child: freed with her, world coordinates):
##   silk mode:          a bundle of fresh silk on each LINE anchor (the one she holds is fuller, with a strand
##                       down to her) - "her threads";
##   arachnophobia mode: round carved STONE SEALS under every anchor ring - the Hollow Mother floats between
##                       them - with a pale rune (no silk, no legs anywhere); the held seal's rune brightens
##                       and a pale root tendril hangs from it to her.
## An EXPOSED anchor (its line-brazier flared under her) glows ember-warm for a while (both looks).
## Swaps live with set_alt(); nothing is allocated per frame.
##   var m = AnchorMarks.new(); m.setup({"anchors": [Vector3...], "lines": 3, "alt": false}); boss.add_child(m)
##   m.set_held(line, body_pos); m.set_exposed(line)

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")
const HitFx := preload("res://src/combat/hit_fx.gd")

const EXPOSED_GLOW_TIME := 8.0
const SILK := Color("e8e4f0")
const ROOT := Color("cdbfa3")
const RUNE := Color("d9f2c4")
const EMBER := Color("ff8a3d")

var anchors: Array = []
var lines: int = 3
var alt := false
var held: int = -1

var _root: Node3D = null
var _held_marks: Array = []      # per anchor: the "held" highlight node
var _embers: Array = []          # per anchor: the exposed glow node
var _ember_left: Array = []
var _tether: MeshInstance3D = null
var _tether_mat: Material = null
var _body_pos := Vector3.ZERO


func setup(p: Dictionary) -> void:
	anchors.clear()
	var a: Variant = p.get("anchors", [])
	if a is Array or a is PackedVector3Array:
		for v in a:
			if v is Vector3:
				anchors.append(v)
	lines = int(p.get("lines", lines))
	alt = bool(p.get("alt", alt))


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_build()


func set_alt(on: bool) -> void:
	if on == alt and _root != null:
		return
	alt = on
	_build()


## Highlights the anchor she holds (-1: none) and hangs the tether down to `body` (her position).
func set_held(line: int, body: Vector3) -> void:
	held = line
	_body_pos = body
	for i in _held_marks.size():
		(_held_marks[i] as Node3D).visible = i == held
	_place_tether()


func update_body(body: Vector3) -> void:
	_body_pos = body
	_place_tether()


func set_exposed(line: int) -> void:
	if line < 0 or line >= _embers.size():
		return
	_ember_left[line] = EXPOSED_GLOW_TIME
	(_embers[line] as Node3D).visible = true


func exposed_glowing(line: int) -> bool:
	return line >= 0 and line < _embers.size() and (_embers[line] as Node3D).visible


func seal_count() -> int:
	if _root == null:
		return 0
	return _root.find_children("Seal*", "", false, false).size()


func silk_count() -> int:
	if _root == null:
		return 0
	return _root.find_children("Silk*", "", false, false).size()


func _process(delta: float) -> void:
	for i in _ember_left.size():
		if float(_ember_left[i]) > 0.0:
			_ember_left[i] = maxf(float(_ember_left[i]) - delta, 0.0)
			if float(_ember_left[i]) <= 0.0:
				(_embers[i] as Node3D).visible = false


func _place_tether() -> void:
	if _tether == null:
		return
	if held < 0 or held >= anchors.size():
		_tether.visible = false
		return
	var a: Vector3 = anchors[held]
	var b := _body_pos
	var d := b - a
	var l := d.length()
	if l < 0.3:
		_tether.visible = false
		return
	_tether.visible = true
	var y := d / l
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	var w := 0.04 if alt else 0.018
	_tether.global_transform = Transform3D(Basis(x * w, y * l, z * w), (a + b) * 0.5)


func _build() -> void:
	if _root != null and is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()
	_held_marks.clear()
	var keep_left: Array = _ember_left.duplicate()
	_embers.clear()
	_ember_left.clear()
	_root = Node3D.new()
	_root.name = "Marks"
	add_child(_root)
	var ember_mat := Mat.glow(EMBER, 1.6)
	var stone := Mat.outlined(Mat.toon(Palette.RUIN_STONE, {"rim": 0.35, "noise": 0.14}), 0.014)
	var rune := Mat.glow(RUNE, 0.9)
	var rune_hot := Mat.glow(RUNE, 2.2)
	var silk := Mat.toon(SILK, {"rim": 0.7, "emission": SILK, "emission_energy": 0.25, "noise": 0.0})
	for i in anchors.size():
		var a: Vector3 = anchors[i]
		var holder := Node3D.new()
		holder.name = ("Seal%d" % i) if alt else ("Silk%d" % i)
		_root.add_child(holder)
		holder.position = a
		var hm := Node3D.new()
		hm.name = "Held"
		holder.add_child(hm)
		if alt:
			# a round carved stone seal just under the anchor ring, rune facing down
			var disc := Kit.cylinder(0.62, 0.66, 0.16, stone, 20)
			Kit.add(holder, disc, Vector3(0, -0.18, 0))
			var ring := Kit.torus(0.34, 0.4, rune)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Kit.add(holder, ring, Vector3(0, -0.27, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
			var hot := Kit.torus(0.2, 0.28, rune_hot)
			hot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Kit.add(hm, hot, Vector3(0, -0.28, 0), Vector3.ZERO, Vector3(1, 0.25, 1))
		elif i < lines:
			# a bundle of fresh silk on the line anchors she uses
			var tuft := Kit.blob(0.26, silk, 11 + i, 0.3, 0.8, 2)
			tuft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Kit.add(holder, tuft, Vector3(0, -0.2, 0))
			var more := Kit.blob(0.2, silk, 23 + i, 0.35, 0.7, 2)
			more.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Kit.add(hm, more, Vector3(0.12, -0.36, 0.05))
		hm.visible = i == held
		_held_marks.append(hm)
		var glow := Kit.blob(0.34, ember_mat, 9, 0.35, 0.5, 2)
		glow.name = "Ember"
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.set_meta("no_flash", true)
		Kit.add(holder, glow, Vector3(0, -0.34, 0))
		var left := float(keep_left[i]) if i < keep_left.size() else 0.0
		glow.visible = left > 0.0
		_embers.append(glow)
		_ember_left.append(left)
	_tether_mat = Mat.outlined(Mat.toon(ROOT, {"rim": 0.4}), 0.008) if alt else Mat.glow(SILK, 0.6)
	_tether = MeshInstance3D.new()
	_tether.name = "Tether"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	_tether.mesh = cyl
	_tether.material_override = _tether_mat
	_tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tether.top_level = true
	_root.add_child(_tether)
	_tether.visible = false
	_place_tether()
