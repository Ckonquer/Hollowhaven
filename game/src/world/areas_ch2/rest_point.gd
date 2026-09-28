extends Node3D
## PLACEHOLDER checkpoint for the Chapter Two stand-in areas: resting here makes it the area's return
## point (Game.set_respawn -> GameState.player["area_respawn"][area]), makes Continue resume here and
## saves. Wave C replaces these with the real lanterns / candles. Interaction contract: group
## "interactable" + a layer-16 sphere.
##   setup({"area": "hushed_works", "spawn": "works_lockers"})

var area_name: String = ""
var spawn_id: String = ""
var save_enabled := true          # tests switch saving off
var _light: OmniLight3D


func setup(params: Dictionary) -> void:
	area_name = String(params.get("area", area_name))
	spawn_id = String(params.get("spawn", spawn_id))


func _ready() -> void:
	name = "RestPoint_" + spawn_id
	add_to_group("interactable")
	add_to_group("checkpoint")
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.5, 1.1, 0.55)
	var lamp := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.18
	cm.height = 0.4
	lamp.mesh = cm
	lamp.material_override = glow
	lamp.position = Vector3(0, 1.1, 0)
	add_child(lamp)
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 0.9
	post.mesh = pm
	post.position = Vector3(0, 0.45, 0)
	add_child(post)
	var ib := StaticBody3D.new()
	ib.name = "Interact"
	ib.collision_layer = 16
	ib.collision_mask = 0
	var ics := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 1.1
	ics.shape = sph
	ics.position = Vector3(0, 0.9, 0)
	ib.add_child(ics)
	add_child(ib)
	_light = OmniLight3D.new()
	_light.light_color = Color("ffc978")
	_light.light_energy = 0.8
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 1.4, 0)
	add_child(_light)


func get_interaction(_player: Node = null) -> Dictionary:
	return {"text": "Rest here (save)", "enabled": true}


func interact(_player: Node = null) -> void:
	if area_name == "" or spawn_id == "":
		return
	Game.set_respawn(area_name, spawn_id)
	GameState.player["spawn"] = spawn_id      # Continue resumes here
	var ok := true
	if save_enabled:
		ok = SaveSystem.save_game()
	Events.notify.emit("Rested - progress saved" if ok else "Rested (saving failed)", "success" if ok else "warn")
