extends "res://src/world/area_base.gd"
## PLACEHOLDER surface (replaced by the Surface World agent): flat ground + spawns.

const Layout := preload("res://data/world_layout.gd")

func _ready() -> void:
	area_id = "surface"
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-50, 30, 0); add_child(sun)
	var env := WorldEnvironment.new(); var e := Environment.new(); e.background_mode = Environment.BG_SKY
	var sky := Sky.new(); sky.sky_material = ProceduralSkyMaterial.new(); e.sky = sky; env.environment = e; add_child(env)
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(240, 1, 240)
	cs.shape = sh; cs.position.y = -0.5; body.add_child(cs); add_child(body)
	var mi := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(240, 240); mi.mesh = pm; add_child(mi)
	for id in Layout.SPAWN_HINTS:
		var p: Vector2 = Layout.SPAWN_HINTS[id]
		register_spawn(id, Transform3D(Basis.IDENTITY, Vector3(p.x, 0.1, p.y)))
	for id in Layout.LANDMARKS:
		var l: Dictionary = Layout.LANDMARKS[id]
		add_zone(id, Vector3(l["pos"].x, 0, l["pos"].y), l["radius"], id == "haven")
