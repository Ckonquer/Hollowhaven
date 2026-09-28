extends "res://src/world/areas_ch2/placeholder_area.gd"
## PLACEHOLDER Echo Trial (area "echo_trial", docs/CHAPTER_TWO_SPEC.md §1): one arena (zone "trial"), the
## entry pad (safe) at spawn trial_start and a way out that always returns to the trial's origin
## (Game.change_area never overwrites the respawn point when entering a trial, so "back to the respawn
## point" is the origin checkpoint). Trials are never saved (Game.can_manual_save refuses here and the
## arrival autosave is skipped). Wave D replaces this with the real replay arenas.


func _ready() -> void:
	area_id = "echo_trial"
	ambience = "amb_silk"
	bounds = Rect2(-15, -30, 30, 30)
	build_environment({"bg": Color("151520"), "ambient": Color("8a7fb0"), "ambient_energy": 0.55,
		"lamps": [[Vector3(0, 4.0, -15), Color("c9b0ff"), 1.2, 18.0], [Vector3(0, 2.4, -3), Color("ffe2a0"), 0.8, 6.0]]})
	add_ground(bounds, floor_y, Color("2e2a40"), "stone")
	add_walls(bounds, floor_y, 6.0)
	add_room("trial", bounds, floor_y, false, Color("3a3452"))
	add_label("PLACEHOLDER - Echo Trial", Vector3(0, 3.6, -2), 64)
	place_spawn("trial_start", Vector3(0, floor_y, -4.0), 0.0)
	add_safe_spot(Vector3(0, floor_y, -3.0), 3.0)
	add_exit("leave", {"text": "Leave the trial", "use_respawn": true}, Vector3(0, floor_y, -0.9), 0.0)
