extends Node3D
## The miners' workbench in the Pocket Conservatory (room 7): a fixed crafting station (group
## "crafting_station", station_id "workbench") so Krystal can prepare between excursions without going home.
## Not a player structure (nothing saved, nothing to dismantle). Local +Z faces the room.

const Mat := preload("res://src/art/mat.gd")
const Kit := preload("res://src/art/mesh_kit.gd")

var station_id: String = "workbench"


func _ready() -> void:
	add_to_group("crafting_station")
	add_to_group("interactable")
	var wood := Mat.outlined(Mat.toon(Color("8e5f3a")), 0.016)
	var dark := Mat.outlined(Mat.toon(Color("5e3b28")), 0.016)
	var iron := Mat.outlined(Mat.toon(Color("4b5563"), {"rim": 0.35}), 0.012)
	Kit.add(self, Kit.box(Vector3(1.9, 0.12, 0.9), wood), Vector3(0, 0.86, 0))
	for sx in [-0.82, 0.82]:
		for sz in [-0.36, 0.36]:
			Kit.add(self, Kit.box(Vector3(0.12, 0.84, 0.12), dark), Vector3(sx, 0.42, sz))
	Kit.add(self, Kit.box(Vector3(1.7, 0.08, 0.7), dark), Vector3(0, 0.25, 0))
	Kit.add(self, Kit.box(Vector3(1.9, 0.8, 0.08), wood), Vector3(0, 1.3, -0.42))
	# a few tools on the back board and the top
	Kit.add(self, Kit.box(Vector3(0.06, 0.5, 0.04), iron), Vector3(-0.5, 1.35, -0.36), Vector3(0, 0, 15))
	Kit.add(self, Kit.box(Vector3(0.3, 0.08, 0.06), iron), Vector3(-0.44, 1.58, -0.36))
	Kit.add(self, Kit.box(Vector3(0.05, 0.42, 0.04), dark), Vector3(0.3, 1.3, -0.36), Vector3(0, 0, -10))
	Kit.add(self, Kit.box(Vector3(0.4, 0.08, 0.25), Mat.toon(Color("efe0bd"))), Vector3(0.45, 0.96, 0.1), Vector3(0, 12, 0))
	Kit.add(self, Kit.cylinder(0.08, 0.1, 0.12, iron, 8), Vector3(-0.2, 0.98, 0.15))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.9, 1.0, 0.9)
	cs.shape = sh
	cs.position = Vector3(0, 0.5, 0)
	body.add_child(cs)
	add_child(body)
	var a := Area3D.new()
	a.name = "InteractArea"
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	var acs := CollisionShape3D.new()
	var ash := BoxShape3D.new()
	ash.size = Vector3(2.2, 1.6, 1.4)
	acs.shape = ash
	acs.position = Vector3(0, 0.8, 0.3)
	a.add_child(acs)
	add_child(a)


func get_interaction(_player: Node = null) -> Dictionary:
	return {"text": "Use the miners' workbench", "enabled": true}


func interact(_player: Node = null) -> void:
	Game.open_panel("crafting", {"station": station_id})
