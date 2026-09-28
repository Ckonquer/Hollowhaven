extends "res://src/world/areas_ch2/area_exit.gd"
## The Reach end of the Hushed Works refuge shortcut (spec §1: spawn refuge_exit; MP §10 "reliable return
## shortcut"): a round iron hatch in a mossy stone collar beside the Conservatory. Bolted from below until
## the refuge shortcut is opened (flag ch2_refuge_shortcut), then "Climb down to the refuge" ->
## Game.change_area("hushed_works", "refuge"). Same interaction logic as area_exit.gd; only the look differs.

const Kit := preload("res://src/art/mesh_kit.gd")
const NodeVisuals := preload("res://src/world/common/node_visuals.gd")
const Props := preload("res://src/world/reach/reach_props.gd")

var _lid: Node3D                # the hinge (rotates open)
var _glow: MeshInstance3D


func _ready() -> void:
	super._ready()
	if not Events.flag_set.is_connected(_on_flag):
		Events.flag_set.connect(_on_flag)
	_apply()


func _on_flag(flag: String, _value: Variant) -> void:
	if flag == requires_flag:
		_apply()


func _apply() -> void:
	var open := is_unlocked()
	if _lid != null:
		_lid.rotation = Vector3(deg_to_rad(-100.0) if open else 0.0, 0.0, 0.0)
	if _glow != null:
		_glow.visible = open


func _build() -> void:
	var m := NodeVisuals.Merger.new()
	for k in 10:
		var a := TAU * float(k) / 10.0
		m.add(Kit.blob_mesh(0.3, 7500 + k, 0.2, 0.55, 1), Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 1.0, 0.08, sin(a) * 1.0)), Color("a39a8e"))
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.5
		m.add(Kit.blob_mesh(0.22, 7520 + k, 0.4, 0.5, 1), Transform3D(Basis(), Vector3(cos(a) * 1.1, 0.2, sin(a) * 1.1)), Color("6f7a4a"))
	var ring := MeshInstance3D.new()
	ring.mesh = m.commit()
	ring.material_override = Props.stone_mat()
	add_child(ring)
	var dark := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.72
	cm.bottom_radius = 0.72
	cm.height = 0.04
	dark.mesh = cm
	dark.material_override = Mat.glow(Color("0b0a10"), 0.0)
	dark.position = Vector3(0, 0.1, 0)
	add_child(dark)
	# the hinged iron lid (hinge on the far edge)
	var hinge := Node3D.new()
	hinge.position = Vector3(0, 0.16, -0.72)
	add_child(hinge)
	var lm := NodeVisuals.Merger.new()
	lm.add(NodeVisuals._cyl(0.74, 0.74, 0.08, 16), Transform3D(Basis(), Vector3(0, 0, 0.72)), Color("4a4048"))
	lm.add(NodeVisuals._box(Vector3(1.3, 0.05, 0.12)), Transform3D(Basis(), Vector3(0, 0.05, 0.72)), Color("3a3238"))
	lm.add(NodeVisuals._box(Vector3(0.12, 0.05, 1.3)), Transform3D(Basis(), Vector3(0, 0.05, 0.72)), Color("3a3238"))
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.06
	ring_mesh.outer_radius = 0.1
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 6
	lm.add(ring_mesh, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.1, 1.2)), Color("c9b27a"))
	var lid_mi := MeshInstance3D.new()
	lid_mi.mesh = lm.commit()
	lid_mi.material_override = Mat.outlined(Mat.toon(Color.WHITE, {"vertex_color": true, "rim": 0.45}), 0.018)
	hinge.add_child(lid_mi)
	_lid = hinge
	_glow = MeshInstance3D.new()
	var gq := CylinderMesh.new()
	gq.top_radius = 0.6
	gq.bottom_radius = 0.6
	gq.height = 0.02
	_glow.mesh = gq
	_glow.material_override = Mat.glow(Color("ffd08a"), 1.2)
	_glow.position = Vector3(0, 0.05, 0)
	add_child(_glow)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	add_child(body)
	for k in 10:
		var a := TAU * float(k) / 10.0
		Props.cyl_col(body, Vector3(cos(a) * 1.0, 0.0, sin(a) * 1.0), 0.28, 0.3)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.4
	ics.shape = sph
	ics.position = Vector3(0, 0.6, 0)
	ib.add_child(ics)
	add_child(ib)
