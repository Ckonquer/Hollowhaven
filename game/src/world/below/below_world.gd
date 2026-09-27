extends "res://src/world/area_base.gd"
## PLACEHOLDER dungeon (replaced by the Dungeon agent).

func _ready() -> void:
	area_id = "below"
	var body := StaticBody3D.new(); var cs := CollisionShape3D.new(); var sh := BoxShape3D.new(); sh.size = Vector3(60, 1, 60)
	cs.shape = sh; cs.position.y = -0.5; body.add_child(cs); add_child(body)
	var l := OmniLight3D.new(); l.position = Vector3(0, 3, 0); l.omni_range = 20; add_child(l)
	register_spawn("mine_entry", Transform3D(Basis.IDENTITY, Vector3(0, 0.1, 0)))
