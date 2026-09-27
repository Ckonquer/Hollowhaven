extends Node3D
## DEBUG/QA-only target spawned by player_demo.gd (never used in normal play).
## setup({"mode": "harvest" | "chest" | "enemy"})
##   harvest: harvestable needing an axe (records every harvest_hit call)
##   chest:   interactable (counts interact calls)
##   enemy:   group "enemy" with a health child (30 hp) to verify one hit per swing

const HealthScript := preload("res://src/combat/health.gd")
const Kit := preload("res://src/art/mesh_kit.gd")
const Palette := preload("res://src/art/palette.gd")

var mode: String = "harvest"
var hits: Array = []
var interacts: int = 0
var health: Node = null


func setup(p: Dictionary) -> void:
	mode = String(p.get("mode", mode))


func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 1.6
	cs.shape = cyl
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	add_child(body)
	match mode:
		"harvest":
			body.collision_layer = 1 | 16
			add_to_group("harvestable")
			Kit.add(self, Kit.cylinder(0.25, 0.3, 1.6, Palette.BARK), Vector3(0, 0.8, 0))
			Kit.add(self, Kit.blob(0.9, Palette.FOLIAGE, 3, 0.2), Vector3(0, 2.1, 0))
		"chest":
			body.collision_layer = 32 | 16
			add_to_group("interactable")
			Kit.add(self, Kit.box(Vector3(0.9, 0.7, 0.6), Palette.WOOD), Vector3(0, 0.35, 0))
		"enemy":
			body.collision_layer = 8
			add_to_group("enemy")
			health = HealthScript.new()
			health.name = "Health"
			health.max_hp = 30.0
			add_child(health)
			Kit.add(self, Kit.blob(0.45, Palette.BERRY, 5, 0.25), Vector3(0, 0.5, 0))


func get_harvest_info() -> Dictionary:
	return {"tool": "axe", "name": "Test Tree"} if mode == "harvest" else {}


func harvest_hit(_player: Node, tool_item_id: String) -> void:
	hits.append(tool_item_id)


func get_interaction(_player: Node) -> Dictionary:
	return {"text": "Open Test Chest", "enabled": true} if mode == "chest" else {}


func interact(_player: Node) -> void:
	interacts += 1
