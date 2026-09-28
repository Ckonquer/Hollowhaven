extends "res://src/world/areas_ch2/placeholder_area.gd"
## PLACEHOLDER Tobin's Lost Shift (area "tobin_annex", docs/CHAPTER_TWO_SPEC.md §1): three compact spaces
## in a row off the mine mouth - ta_entry (safe, exit to the surface side door), ta_lockers (the annex
## lantern checkpoint) and ta_sump (the far end with the shortcut hatch, open after ta_hatch_open).
## Spawns: annex_entry, annex_lantern, annex_hatch_below. Wave C/B replaces this with the real annex.

const ROOM_W := 10.0
const ROOM_D := 10.0


func _ready() -> void:
	area_id = "tobin_annex"
	ambience = "amb_mine"
	bounds = Rect2(-ROOM_W * 0.5, -ROOM_D * 3.0, ROOM_W, ROOM_D * 3.0)
	build_environment({"bg": Color("120e10"), "ambient": Color("7a5a44"), "ambient_energy": 0.5,
		"lamps": [[Vector3(0, 2.6, -5), Color("ffb35c"), 1.2, 9.0], [Vector3(2.5, 2.4, -15), Color("ffb35c"), 1.0, 8.0],
			[Vector3(0, 2.6, -25), Color("c9a37a"), 0.8, 8.0]]})
	add_ground(bounds, floor_y, Color("5a4636"), "stone")
	add_walls(bounds, floor_y, 4.0)
	add_room("ta_entry", Rect2(-ROOM_W * 0.5, -ROOM_D, ROOM_W, ROOM_D), floor_y, true, Color("6b5442"))
	add_room("ta_lockers", Rect2(-ROOM_W * 0.5, -ROOM_D * 2.0, ROOM_W, ROOM_D), floor_y, false, Color("5e4a3a"))
	add_room("ta_sump", Rect2(-ROOM_W * 0.5, -ROOM_D * 3.0, ROOM_W, ROOM_D), floor_y, false, Color("4a4038"))
	add_label("PLACEHOLDER - Tobin's Lost Shift", Vector3(0, 3.4, -2), 64)
	place_spawn("annex_entry", Vector3(0, floor_y, -4.0), 0.0)
	place_spawn("annex_lantern", Vector3(0, floor_y, -15.0), 0.0)
	place_spawn("annex_hatch_below", Vector3(0, floor_y, -25.0), 0.0)
	add_exit("side_door", {"text": "Back out to the mine mouth", "target_area": "surface", "target_spawn": "annex_door"},
		Vector3(0, floor_y, -0.9), 0.0)
	add_rest_point("annex_lantern", Vector3(3.0, floor_y, -15.0), 0.0)
	add_exit("hatch", {"text": "Climb the shortcut hatch", "target_area": "surface", "target_spawn": "annex_hatch",
		"requires_flag": "ta_hatch_open", "style": "hatch", "locked_text": "The hatch is rusted shut from this side... for now."},
		Vector3(0, floor_y, -29.0), 0.0)
