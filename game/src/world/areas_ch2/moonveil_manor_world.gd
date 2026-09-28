extends "res://src/world/areas_ch2/placeholder_area.gd"
## PLACEHOLDER Moonveil Manor (area "moonveil_manor", docs/CHAPTER_TWO_SPEC.md §1, §7.3): five spaces in a
## row - Entrance Cloakroom (safe, exit), Looking-Glass Hall, Ballroom (checkpoint manor_ballroom),
## Count's Gallery (the Velour arena), Conservatory Balcony (safe, checkpoint manor_balcony, stair back
## outside). Spawns: manor_entry, manor_ballroom, manor_balcony. Wave C replaces this with the real manor.


func _ready() -> void:
	area_id = "moonveil_manor"
	ambience = "amb_ruins"
	bounds = Rect2(-9, -68, 18, 68)
	build_environment({"bg": Color("1b1220"), "ambient": Color("b08a8a"), "ambient_energy": 0.55,
		"lamps": [[Vector3(0, 3.0, -6), Color("ffc978"), 1.1, 10.0], [Vector3(0, 3.0, -18), Color("ffc978"), 0.9, 10.0],
			[Vector3(0, 3.4, -31), Color("ffd39a"), 1.2, 12.0], [Vector3(0, 3.6, -47), Color("d9a0ff"), 1.0, 14.0],
			[Vector3(0, 3.0, -62), Color("ffc978"), 1.0, 10.0]]})
	add_ground(bounds, floor_y, Color("4a2e3e"), "wood")
	add_walls(bounds, floor_y, 6.0)
	add_room("mm_cloakroom", Rect2(-6, -12, 12, 12), floor_y, true, Color("6a3f52"))
	add_room("mm_hall", Rect2(-6, -24, 12, 12), floor_y, false, Color("5a3a5a"))
	add_room("mm_ballroom", Rect2(-6, -38, 12, 14), floor_y, false, Color("7a4a4a"))
	add_room("mm_gallery", Rect2(-9, -56, 18, 18), floor_y, false, Color("4a2e4a"))
	add_room("mm_balcony", Rect2(-6, -68, 12, 12), floor_y, true, Color("5e6a4a"))
	add_label("PLACEHOLDER - Moonveil Manor", Vector3(0, 3.6, -2), 64)
	place_spawn("manor_entry", Vector3(0, floor_y, -4.0), 0.0)
	place_spawn("manor_ballroom", Vector3(0, floor_y, -31.0), 0.0)
	place_spawn("manor_balcony", Vector3(0, floor_y, -62.0), 0.0)
	add_exit("front_door", {"text": "Step back outside", "target_area": "hallowmere_reach", "target_spawn": "manor_door"},
		Vector3(0, floor_y, -0.9), 0.0)
	add_rest_point("manor_ballroom", Vector3(3.0, floor_y, -31.0), 0.0)
	add_rest_point("manor_balcony", Vector3(3.0, floor_y, -62.0), 0.0)
	add_exit("balcony_stair", {"text": "Take the balcony stair down", "target_area": "hallowmere_reach", "target_spawn": "manor_door",
		"style": "stair"}, Vector3(0, floor_y, -67.0), 0.0)
