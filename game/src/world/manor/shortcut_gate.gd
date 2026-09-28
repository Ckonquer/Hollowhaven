extends Node3D
## The bolted iron gate at the east end of the Conservatory Balcony (spec §7.3 "stair shortcut to the
## Cloakroom/outside"). Unbolted once, from the balcony side only: sets mm_balcony_shortcut (manor state:
## the servants' stair and the garden stair) and ch2_shortcut_manor (optional goal "The Long Way Home"),
## then stands open for good. Closed = a solid blocker across the gap. Local +Z faces the balcony.
##   setup({"width": 2.0})

signal unbolted

const Layout := preload("res://data/manor_layout.gd")
const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

const IRON := Color("35283a")
const GOLD := Color("d9b25a")

var width: float = 2.0
var opens: int = 0
var _shape: CollisionShape3D
var _leaf: Node3D


func setup(params: Dictionary) -> void:
	width = float(params.get("width", width))


func _ready() -> void:
	name = "ShortcutGate"
	add_to_group("interactable")
	add_to_group("mm_shortcut_gate")
	_build()
	_apply(false)


func is_open() -> bool:
	return bool(GameState.get_flag(Layout.FLAG_SHORTCUT))


func get_interaction(_player: Node = null) -> Dictionary:
	if is_open():
		return {}
	return {"text": "Slide back the bolt (a shortcut down)", "enabled": true}


func interact(_player: Node = null) -> void:
	open_gate()


## Opens the shortcut once. Returns true if this call opened it.
func open_gate() -> bool:
	if is_open():
		return false
	GameState.set_flag(Layout.FLAG_SHORTCUT, true)
	GameState.set_flag(Layout.FLAG_SHORTCUT_GOAL, true)
	opens += 1
	_apply(true)
	Audio.play_3d("gate_unlock", global_position + Vector3.UP, -3.0)
	Events.caption.emit("[an iron bolt slides back with a clank]")
	Events.notify.emit("Shortcut open: the servants' stair to the Cloakroom and the garden stair outside.", "success")
	GameState.request_quest_eval()
	unbolted.emit()
	return true


func _apply(animate: bool) -> void:
	var on := is_open()
	if _shape != null:
		if is_inside_tree():
			_shape.set_deferred("disabled", on)
		else:
			_shape.disabled = on
	var goal := deg_to_rad(-105.0) if on else 0.0
	if animate and is_inside_tree():
		create_tween().tween_property(_leaf, "rotation:y", goal, 0.9).set_trans(Tween.TRANS_SINE)
	else:
		_leaf.rotation.y = goal


func _build() -> void:
	var iron := Mat.outlined(Mat.toon(IRON, {"rim": 0.35}), 0.012)
	var gold := Mat.toon(GOLD, {"rim": 0.5})
	for sx in [-1.0, 1.0]:
		Kit.add(self, Kit.box(Vector3(0.24, 2.9, 0.24), iron), Vector3(float(sx) * (width * 0.5 + 0.1), 1.45, 0))
		Kit.add(self, Kit.sphere(0.14, gold, 8, 10), Vector3(float(sx) * (width * 0.5 + 0.1), 3.0, 0))
	_leaf = Node3D.new()
	_leaf.name = "Leaf"
	_leaf.position = Vector3(-width * 0.5, 0, 0)
	add_child(_leaf)
	for k in 7:
		var x := 0.14 + float(k) * (width - 0.28) / 6.0
		Kit.add(_leaf, Kit.cylinder(0.03, 0.03, 2.3, iron, 6), Vector3(x, 1.25, 0))
		Kit.add(_leaf, Kit.cone(0.06, 0.16, gold, 6), Vector3(x, 2.46, 0))
	for y in [0.35, 1.3, 2.2]:
		Kit.add(_leaf, Kit.box(Vector3(width - 0.1, 0.06, 0.06), iron), Vector3(width * 0.5, float(y), 0))
	# Scroll: a little iron crescent in the middle of the gate.
	Kit.add(_leaf, Kit.torus(0.2, 0.26, gold), Vector3(width * 0.5, 1.75, 0), Vector3(90, 0, 0))
	# The bolt (on the balcony side).
	Kit.add(_leaf, Kit.box(Vector3(0.36, 0.08, 0.08), gold), Vector3(width - 0.1, 1.05, 0.08))
	var body := StaticBody3D.new()
	body.name = "Blocker"
	body.collision_layer = 1
	body.collision_mask = 0
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, 3.0, 0.4)
	_shape.shape = box
	_shape.position = Vector3(0, 1.5, 0)
	body.add_child(_shape)
	add_child(body)
	var ib := StaticBody3D.new()
	ib.name = "InteractBody"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.0
	ics.shape = sph
	ics.position = Vector3(0, 1.1, 0.5)
	ib.add_child(ics)
	add_child(ib)
