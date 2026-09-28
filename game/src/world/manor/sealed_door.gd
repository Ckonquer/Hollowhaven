extends Node3D
## A way through the manor that opens on a condition: the Gallery doors (crescent lock, flag
## mm_ballroom_solved), the Balcony glass doors (the Count's enchantment, flag ch2_velour_defeated) and the
## Dressing-room tapestry (closed only while the Count's encounter is on). Closed = a solid blocker in the
## opening + a greyed prompt saying what opens it; open = leaves swung back / tapestry tied aside.
## The node stands in the middle of the wall gap; local +Z faces the side Krystal comes from.
##   setup({"id": "gallery", "style": "gallery"|"glass"|"tapestry", "width": 3.2, "height": 3.6,
##          "flag": "mm_ballroom_solved", "closed_text": "...", "open": false})
## API: is_open(), set_open(on, animate := true); signal opened.

signal opened

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const PLUM := Color("5b2a4e")
const GOLD := Color("d9b25a")
const IRON := Color("3a2c3e")
const GLASS := Color(0.78, 0.84, 1.0, 0.28)
const SHIMMER := Color("b98cff")

var door_id: String = ""
var style: String = "gallery"
var width: float = 3.2
var height: float = 3.6
var flag: String = ""
var closed_text: String = "It won't open."
var _open := false
var _start_open := false
var _shape: CollisionShape3D
var _leaves: Array = []          # hinge pivots
var _shimmer: MeshInstance3D
var _cloth: Node3D
var _tie: Node3D
var _tw: Tween = null


func setup(params: Dictionary) -> void:
	door_id = String(params.get("id", door_id))
	style = String(params.get("style", style))
	width = float(params.get("width", width))
	height = float(params.get("height", height))
	flag = String(params.get("flag", flag))
	closed_text = String(params.get("closed_text", closed_text))
	_start_open = bool(params.get("open", false))


func _ready() -> void:
	name = "SealedDoor_" + door_id
	add_to_group("interactable")
	add_to_group("mm_sealed_door")
	_build()
	var start := _start_open or (flag != "" and bool(GameState.get_flag(flag)))
	set_open(start, false)


func is_open() -> bool:
	return _open


func set_open(on: bool, animate: bool = true) -> void:
	var was := _open
	_open = on
	if _shape != null:
		if is_inside_tree():
			_shape.set_deferred("disabled", on)
		else:
			_shape.disabled = on
	if _tw != null and _tw.is_valid():
		_tw.kill()
	var do_anim := animate and is_inside_tree() and not _leaves.is_empty()
	if do_anim:
		_tw = create_tween().set_parallel(true)
	for i in _leaves.size():
		var pivot: Node3D = _leaves[i]
		var sgn := -1.0 if i == 0 else 1.0
		var goal := deg_to_rad(100.0) * sgn if on else 0.0
		if do_anim:
			_tw.tween_property(pivot, "rotation:y", goal, 1.2).set_trans(Tween.TRANS_SINE)
		else:
			pivot.rotation.y = goal
	if _shimmer != null:
		_shimmer.visible = not on
	if _cloth != null:
		_cloth.visible = not on
		_tie.visible = on
	if on and not was:
		opened.emit()


func get_interaction(_player: Node = null) -> Dictionary:
	if _open:
		return {}
	return {"text": _closed_title(), "enabled": false, "reason": closed_text}


func interact(_player: Node = null) -> void:
	if not _open:
		Events.notify.emit(closed_text, "info")


func _closed_title() -> String:
	match style:
		"glass":
			return "Glass doors"
		"tapestry":
			return "A heavy tapestry"
	return "The Gallery doors"


# --- Visuals ------------------------------------------------------------------------------------------------

func _build() -> void:
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "wood")
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.45)
	_shape.shape = box
	_shape.position = Vector3(0, height * 0.5, 0)
	body.add_child(_shape)
	add_child(body)
	match style:
		"tapestry":
			_build_tapestry()
		_:
			_build_leaves(style == "glass")
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	ics.shape = sph
	ics.position = Vector3(0, 1.2, 0.6)
	ib.add_child(ics)
	add_child(ib)


func _build_leaves(glass: bool) -> void:
	var frame := Mat.outlined(Mat.toon(IRON if glass else PLUM, {"rim": 0.35, "noise": 0.1}), 0.014)
	var gold := Mat.toon(GOLD, {"rim": 0.55, "specular": 0.3})
	var half := width * 0.5
	for i in 2:
		var sgn := -1.0 if i == 0 else 1.0
		var pivot := Node3D.new()
		pivot.name = "Leaf%d" % i
		pivot.position = Vector3(sgn * half, 0, 0)
		add_child(pivot)
		_leaves.append(pivot)
		var cx := -sgn * half * 0.5
		if glass:
			for k in 3:
				Kit.add(pivot, Kit.box(Vector3(half - 0.06, 0.08, 0.1), frame), Vector3(cx, 0.1 + float(k) * (height - 0.2) * 0.5, 0))
			for k in 2:
				Kit.add(pivot, Kit.box(Vector3(0.08, height - 0.1, 0.1), frame), Vector3(cx + (float(k) - 0.5) * (half - 0.1), height * 0.5, 0))
			var pane := Kit.box(Vector3(half - 0.14, height - 0.3, 0.03), Mat.transparent(GLASS, true))
			Kit.add(pivot, pane, Vector3(cx, height * 0.5, 0))
			pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			Kit.add(pivot, Kit.box(Vector3(half - 0.03, height - 0.05, 0.14), frame), Vector3(cx, (height - 0.05) * 0.5, 0))
			for k in 3:
				Kit.add(pivot, Kit.box(Vector3(half - 0.3, 0.06, 0.04), gold), Vector3(cx, 0.6 + float(k) * (height - 1.2) * 0.5, 0.08))
			Kit.add(pivot, Kit.torus(0.06, 0.1, gold), Vector3(-sgn * (half - 0.25), height * 0.45, 0.1), Vector3(90, 0, 0))
	if glass:
		# The Count's enchantment: a slow violet shimmer across the doors (gone once he is freed).
		_shimmer = Kit.box(Vector3(width, height, 0.02), Mat.transparent(Color(SHIMMER, 0.22), true))
		Kit.add(self, _shimmer, Vector3(0, height * 0.5, 0.22))
		_shimmer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_tapestry() -> void:
	var cloth := Mat.outlined(Mat.toon(Color("6a2447"), {"rim": 0.3, "noise": 0.14}), 0.012)
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	_cloth = Node3D.new()
	_cloth.name = "Cloth"
	add_child(_cloth)
	Kit.add(_cloth, Kit.box(Vector3(width + 0.3, height, 0.06), cloth), Vector3(0, height * 0.5, 0.3))
	Kit.add(_cloth, Kit.sphere(0.34, gold, 8, 10), Vector3(0, height * 0.58, 0.35), Vector3.ZERO, Vector3(1.0, 1.0, 0.2))
	for s in [-1.0, 1.0]:
		Kit.add(_cloth, Kit.sphere(0.3, gold, 8, 10), Vector3(float(s) * 0.5, height * 0.62, 0.35), Vector3(0, 0, float(s) * 20.0), Vector3(1.6, 0.6, 0.2))
	Kit.add(self, Kit.cylinder(0.04, 0.04, width + 0.8, gold, 8), Vector3(0, height + 0.1, 0.3), Vector3(0, 0, 90))
	# Tied back to one side when open.
	_tie = Node3D.new()
	_tie.name = "TiedBack"
	add_child(_tie)
	Kit.add(_tie, Kit.cylinder(0.26, 0.4, height, cloth, 10), Vector3(width * 0.5 + 0.2, height * 0.5, 0.35))
	Kit.add(_tie, Kit.torus(0.22, 0.3, gold), Vector3(width * 0.5 + 0.2, height * 0.45, 0.35))
