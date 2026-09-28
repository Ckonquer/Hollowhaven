extends "res://tests/test_case.gd"
## AUDIT VERIFY (building): where does the bed wake Krystal when the bed stands against a house wall?
## A real 4 x 4 m room (8 walls on the 2 m grid, one of them a doorway), every piece placed through
## Placement.validate (so only layouts the build mode accepts are used). The bed is put flush against
## each wall in each orientation that validate accepts; the wake spot must be inside the room.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const PausePanel := preload("res://src/ui/panels/pause_panel.gd")

var _area: Node3D


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null
	await wait_frames(2)


func _make_area() -> Node3D:
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(80, 1, 80)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)
	_area.register_spawn("haven_respawn", Transform3D(Basis.IDENTITY, Vector3(-2, 0.08, 5)))
	return _area


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _ctx(player_pos: Vector3) -> Dictionary:
	return {"structures": GameState.structures, "area_id": "surface", "build_area": Ops.build_area_for("surface"),
		"height_fn": _flat, "player_pos": player_pos}


func _place(sid: String, at: Vector3, rot: float, player_pos: Vector3) -> String:
	var pos: Vector3 = P.snap_position(P.def_of(sid), at, rot)
	var res := P.validate(sid, pos, rot, _ctx(player_pos))
	if not bool(res["ok"]):
		print("    refused %s at %s rot %s: %s" % [sid, pos, rot, res["reason"]])
		return ""
	var uid := GameState.add_structure(sid, Vector3(pos.x, float(res["y"]), pos.z), rot)
	Factory.spawn_structure(_area, uid)
	return uid


## Room x in [-12, -8], z in [-2, 2]; doorway on the south wall at x in [-10, -8].
func _build_room(player_pos: Vector3) -> void:
	_place("wood_wall", Vector3(-11, 0, -2), 0.0, player_pos)
	_place("wood_wall", Vector3(-9, 0, -2), 0.0, player_pos)
	_place("wood_wall", Vector3(-11, 0, 2), 0.0, player_pos)
	_place("wood_doorway", Vector3(-9, 0, 2), 0.0, player_pos)
	_place("wood_wall", Vector3(-12, 0, -1), 90.0, player_pos)
	_place("wood_wall", Vector3(-12, 0, 1), 90.0, player_pos)
	_place("wood_wall", Vector3(-8, 0, -1), 90.0, player_pos)
	_place("wood_wall", Vector3(-8, 0, 1), 90.0, player_pos)


func _inside(p: Vector3) -> bool:
	return p.x > -12.0 and p.x < -8.0 and p.z > -2.0 and p.z < 2.0


## Beds flush against a wall in every rotation; count wake spots that end up outside the room.
func test_bed_flush_against_walls_every_rotation() -> void:
	_make_area()
	var inside_player := Vector3(-10.5, 0, 0.5)
	_build_room(Vector3(-4, 0, 6))
	await wait_physics(2)
	# [probe point, rot]: long side against the east / west wall, and head/foot against north / south wall.
	var cases := [
		[Vector3(-8.5, 0, -0.5), 0.0, "long side on EAST wall"], [Vector3(-8.5, 0, -0.5), 180.0, "long side on EAST wall"],
		[Vector3(-11.5, 0, -0.5), 0.0, "long side on WEST wall"], [Vector3(-11.5, 0, -0.5), 180.0, "long side on WEST wall"],
		[Vector3(-10.5, 0, -1.5), 90.0, "long side on NORTH wall"], [Vector3(-10.5, 0, -1.5), 270.0, "long side on NORTH wall"],
		[Vector3(-10.5, 0, -1.0), 0.0, "end on NORTH wall"], [Vector3(-10.5, 0, -1.0), 180.0, "end on NORTH wall"],
	]
	var outside_count := 0
	for c in cases:
		var buid := _place("bed", c[0], float(c[1]), inside_player)
		if buid == "":
			continue
		await wait_physics(2)
		var bed: Node3D = Factory.find_node(_area, buid)
		var w: Vector3 = bed.wake_transform().origin
		var ins := _inside(w)
		if not ins:
			outside_count += 1
		print("    bed %-24s rot %3d centre %s -> wake %s %s" % [c[2], int(c[1]), bed.global_position, w, "inside" if ins else "OUTSIDE THE ROOM"])
		GameState.remove_structure(buid)
		bed.free()
		await wait_physics(2)
	print("    %d of %d accepted bed layouts wake Krystal outside the room" % [outside_count, cases.size()])
	assert_eq(outside_count, 0, "every bed layout wakes Krystal inside her room")


## (Was a prototype of the fix.) The real wake_transform() now skips the side behind the east wall
## (no clear line of sight from the bed) and picks the in-room side.
func test_fix_prototype_ray_rejects_candidates_behind_walls() -> void:
	_make_area()
	_build_room(Vector3(-4, 0, 6))
	var buid := _place("bed", Vector3(-8.5, 0, -0.5), 0.0, Vector3(-10.5, 0, 0.5))
	await wait_physics(3)
	var bed: Node3D = Factory.find_node(_area, buid)
	var chosen: Vector3 = bed.wake_transform().origin
	print("    wake_transform picks %s (inside=%s)" % [chosen, _inside(chosen)])
	assert_true(_inside(chosen), "the line-of-sight check keeps the wake spot inside the room")


## The sealed-bedroom case, built only through Placement.validate and the real build path
## (BuildOps.dismantle / BuildOps.place_structure): bed slept in (spawn registered), Krystal outside,
## the doorway is dismantled and replaced by a wall. The wall is accepted (the enclosure rule protects
## where Krystal stands), but the resolved 'bed' target (death on the surface / Pause > Return to the
## Haven) must not be sealed: the bed hands over to the Haven's own wake-up point.
func test_doorway_replaced_by_wall_after_sleeping() -> void:
	_make_area()
	_build_room(Vector3(-4, 0, 6))
	var buid := _place("bed", Vector3(-11.5, 0, -0.5), 0.0, Vector3(-10.5, 0, 0.5))
	await wait_physics(2)
	var bed: Node3D = Factory.find_node(_area, buid)
	GameState.total_minutes = 21.5 * 60.0
	await bed.sleep(null)
	var spawn: Vector3 = (_area.get_spawn("bed") as Transform3D).origin
	# Take the doorway out and put a plain wall in its place, from outside, as the build mode does.
	var door_uid := ""
	for id in GameState.structures:
		if String(GameState.structures[id].get("id", "")) == "wood_doorway":
			door_uid = String(id)
	var dres: Dictionary = Ops.dismantle(_area, door_uid)
	var wall_pos: Vector3 = P.snap_position(P.def_of("wood_wall"), Vector3(-9, 0, 2), 0.0)
	var wres := P.validate("wood_wall", wall_pos, 0.0, _ctx(Vector3(-4, 0, 6)))
	var wall_uid := ""
	if bool(wres["ok"]):
		GameState.give_item("wood_wall", 1)
		wall_uid = Ops.place_structure(_area, "wood_wall", Vector3(wall_pos.x, float(wres["y"]), wall_pos.z), 0.0)
	await wait_physics(2)
	var target: Vector3 = (_area.get_spawn(PausePanel.unstuck_spawn("surface", GameState.player)) as Transform3D).origin
	var sealed := P.would_enclose(target, _ctx(target))
	print("    bed spawn %s; doorway dismantled ok=%s; wall accepted=%s; resolved target now %s sealed=%s; respawn=%s/%s" % [
		spawn, dres.get("ok"), wall_uid != "", target, sealed, GameState.player.get("respawn_area"), GameState.player.get("respawn_spawn")])
	assert_false(wall_uid != "" and sealed, "sealing the room around the registered wake spot is refused or the spawn falls back")
