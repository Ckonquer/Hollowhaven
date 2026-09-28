extends "res://src/world/areas_ch2/placeholder_area.gd"
## PLACEHOLDER Hushed Works (area "hushed_works", docs/CHAPTER_TWO_SPEC.md §1, §7.4): the 14 rooms as a
## 7 x 2 grid of floor tiles (zones hw_*), so every spawn, zone and exit exists before wave C builds the
## real dungeon on the Below builder. Safe: Landing, Refuge, Bell Throat (+ small circles at the
## placeholder rest points). Spawns: service_landing, works_lockers, refuge, crossing_gate, bell_throat,
## vault_exit. Exits: the Bellhouse stair (landing), the refuge shortcut (after ch2_refuge_shortcut) and
## the vault exit (after ch2_choir_defeated). No horror director yet (Game.DIRECTOR_AREAS hook).

const ROOM := 14.0
const COLS := 7
## Room order of spec §7.4 (1..14); the grid fills row by row.
const ROOM_IDS := ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge",
	"hw_lightwell", "hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]
const SAFE_ROOMS := ["hw_landing", "hw_refuge", "hw_throat"]


static func room_rect(i: int) -> Rect2:
	var col := i % COLS
	var row := int(float(i) / float(COLS))
	return Rect2(-ROOM * float(COLS) * 0.5 + float(col) * ROOM, -float(row + 1) * ROOM, ROOM, ROOM)


static func room_center(room_id: String) -> Vector2:
	var i := ROOM_IDS.find(room_id)
	return room_rect(maxi(i, 0)).get_center()


func _ready() -> void:
	area_id = "hushed_works"
	ambience = "amb_mine"
	bounds = Rect2(-ROOM * float(COLS) * 0.5, -ROOM * 2.0, ROOM * float(COLS), ROOM * 2.0)
	var lamps: Array = []
	for rid in ["hw_landing", "hw_refuge", "hw_winch", "hw_throat", "hw_vault"]:
		var c := room_center(rid)
		lamps.append([Vector3(c.x, 3.2, c.y), Color("9fc0ff") if rid != "hw_refuge" else Color("ffe2a0"), 0.9, 12.0])
	build_environment({"bg": Color("0b0a10"), "ambient": Color("5a6078"), "ambient_energy": 0.45, "lamps": lamps})
	add_ground(bounds, floor_y, Color("3a3d48"), "stone")
	add_walls(bounds, floor_y, 5.0)
	for i in ROOM_IDS.size():
		var rid: String = ROOM_IDS[i]
		var tint := Color("45495a") if i % 2 == 0 else Color("3e4252")
		if SAFE_ROOMS.has(rid):
			tint = Color("56604a")
		add_room(rid, room_rect(i), floor_y, SAFE_ROOMS.has(rid), tint)
	add_label("PLACEHOLDER - The Hushed Works", Vector3(room_center("hw_landing").x, 3.8, -2.0), 64)
	_spawn_in("service_landing", "hw_landing")
	_spawn_in("works_lockers", "hw_lockers")
	_spawn_in("refuge", "hw_refuge")
	_spawn_in("crossing_gate", "hw_winch")
	_spawn_in("bell_throat", "hw_throat")
	_spawn_in("vault_exit", "hw_vault")
	for sp in [["works_lockers", "hw_lockers"], ["refuge", "hw_refuge"], ["crossing_gate", "hw_winch"], ["bell_throat", "hw_throat"]]:
		var c := room_center(String(sp[1]))
		add_rest_point(String(sp[0]), Vector3(c.x + 3.0, floor_y, c.y + 3.0), 0.0)
	var land := room_center("hw_landing")
	add_exit("bellhouse_stair", {"text": "Climb the Bellhouse stair", "target_area": "hallowmere_reach",
		"target_spawn": "bellhouse_stair", "style": "stair"}, Vector3(land.x, floor_y, land.y - 5.5), 0.0)
	var ref := room_center("hw_refuge")
	add_exit("refuge_shortcut", {"text": "Take the drainage stair up", "target_area": "hallowmere_reach",
		"target_spawn": "refuge_exit", "requires_flag": "ch2_refuge_shortcut", "style": "stair",
		"locked_text": "The drainage stair is blocked from this side."}, Vector3(ref.x, floor_y, ref.y - 5.5), 0.0)
	var vault := room_center("hw_vault")
	add_exit("vault_exit", {"text": "Leave the Works", "target_area": "hallowmere_reach", "target_spawn": "bellhouse_stair",
		"requires_flag": "ch2_choir_defeated", "style": "stair", "locked_text": "Not while the voices still sing."},
		Vector3(vault.x, floor_y, vault.y - 5.5), 0.0)


## Spawn in the south half of a room, facing north (into the room).
func _spawn_in(spawn_id: String, room_id: String) -> void:
	var c := room_center(room_id)
	place_spawn(spawn_id, Vector3(c.x, floor_y, c.y + 3.0), 0.0)
