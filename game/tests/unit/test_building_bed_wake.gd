extends "res://tests/test_case.gd"
## Where the bed wakes Krystal (after sleeping, after a fall, Pause > "Return to the Haven"):
## never on the far side of the wall the bed stands against, on the open side of a bed that blocks a
## doorway, on top of the bed when every side is boxed in, and the "bed" spawn follows pieces built or
## taken apart later (a walled-in bed hands over to the Haven clearing until there's a way back).

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const AreaBase := preload("res://src/world/area_base.gd")
const Bed := preload("res://src/building/structures/bed.gd")
const PausePanel := preload("res://src/ui/panels/pause_panel.gd")

const OUTSIDE := Vector3(-4, 0, 6)
const HAVEN_RESPAWN := Vector3(-2, 0.08, 5)

var _area: Node3D
var _notes: Array = []


func before_each() -> void:
	fresh_state()
	_notes = []
	Events.notify.connect(_on_notify)


func after_each() -> void:
	if Events.notify.is_connected(_on_notify):
		Events.notify.disconnect(_on_notify)
	if _area != null and is_instance_valid(_area):
		_area.free()
	_area = null
	await wait_frames(2)


func _on_notify(text: String, _kind: String) -> void:
	_notes.append(text)


## Tiny "surface" area with flat world collision at y = 0 and the Haven's fallback wake-up point.
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
	_area.register_spawn("haven_respawn", Transform3D(Basis.IDENTITY, HAVEN_RESPAWN))
	return _area


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _ctx(player_pos: Vector3) -> Dictionary:
	return {"structures": GameState.structures, "area_id": "surface", "build_area": Ops.build_area_for("surface"),
		"height_fn": _flat, "player_pos": player_pos}


## Validates like the build mode, then records + spawns the piece (no item, no events).
func _place(sid: String, at: Vector3, rot: float, player_pos: Vector3) -> String:
	var pos: Vector3 = P.snap_position(P.def_of(sid), at, rot)
	var res := P.validate(sid, pos, rot, _ctx(player_pos))
	assert_true(bool(res["ok"]), "%s at %s rot %s is accepted (%s)" % [sid, pos, rot, res["reason"]])
	if not bool(res["ok"]):
		return ""
	var uid := GameState.add_structure(sid, Vector3(pos.x, float(res["y"]), pos.z), rot)
	Factory.spawn_structure(_area, uid)
	return uid


## Builds like the build mode does (validate, then BuildOps.place_structure: consumes the item, emits
## Events.structure_placed).
func _build(sid: String, at: Vector3, rot: float, player_pos: Vector3) -> String:
	var pos: Vector3 = P.snap_position(P.def_of(sid), at, rot)
	var res := P.validate(sid, pos, rot, _ctx(player_pos))
	assert_true(bool(res["ok"]), "%s at %s rot %s is accepted (%s)" % [sid, pos, rot, res["reason"]])
	if not bool(res["ok"]):
		return ""
	GameState.give_item(sid, 1)
	return Ops.place_structure(_area, sid, Vector3(pos.x, float(res["y"]), pos.z), rot)


## Room x in [-12, -8], z in [-2, 2]; doorway on the south wall at x in [-10, -8].
func _build_room() -> void:
	_place("wood_wall", Vector3(-11, 0, -2), 0.0, OUTSIDE)
	_place("wood_wall", Vector3(-9, 0, -2), 0.0, OUTSIDE)
	_place("wood_wall", Vector3(-11, 0, 2), 0.0, OUTSIDE)
	_place("wood_doorway", Vector3(-9, 0, 2), 0.0, OUTSIDE)
	_place("wood_wall", Vector3(-12, 0, -1), 90.0, OUTSIDE)
	_place("wood_wall", Vector3(-12, 0, 1), 90.0, OUTSIDE)
	_place("wood_wall", Vector3(-8, 0, -1), 90.0, OUTSIDE)
	_place("wood_wall", Vector3(-8, 0, 1), 90.0, OUTSIDE)


func _in_room(p: Vector3) -> bool:
	return p.x > -12.0 and p.x < -8.0 and p.z > -2.0 and p.z < 2.0


func _structure_hits(at: Vector3) -> int:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 0.9)
	q.collision_mask = 32
	return _area.get_world_3d().direct_space_state.intersect_shape(q, 4).size()


func _unstuck_target() -> Transform3D:
	return _area.get_spawn(PausePanel.unstuck_spawn("surface", GameState.player))


func _sleep_in(bed: Node) -> void:
	GameState.total_minutes = 21.5 * 60.0
	await bed.sleep(null)


# --- Wake spot ---------------------------------------------------------------------------------------------

## The bed's first-choice side (+x, local) is flush with a wall in every rotation: the spot 1.05 m out
## has room on the far side of the 0.22 m wall, but Krystal must wake on the bed's own side.
func test_bed_against_a_wall_wakes_her_on_its_own_side() -> void:
	_make_area()
	# [bed probe point, rot, wall centre, wall rot, bed side of the wall: sign of (x or z) - line]
	var cases := [
		[Vector3(-8.5, 0, 1.0), 0.0, Vector3(-8, 0, 1), 90.0, "x", -8.0, -1.0],
		[Vector3(-7.5, 0, 1.0), 180.0, Vector3(-8, 0, 1), 90.0, "x", -8.0, 1.0],
		[Vector3(-9.0, 0, -1.5), 90.0, Vector3(-9, 0, -2), 0.0, "z", -2.0, 1.0],
		[Vector3(-9.0, 0, -2.5), 270.0, Vector3(-9, 0, -2), 0.0, "z", -2.0, -1.0],
	]
	for c in cases:
		var wall := _place("wood_wall", c[2], float(c[3]), OUTSIDE)
		var buid := _place("bed", c[0], float(c[1]), OUTSIDE)
		await wait_physics(2)
		var bed: Node3D = Factory.find_node(_area, buid)
		var w: Vector3 = bed.wake_transform().origin
		var coord: float = w.x if c[4] == "x" else w.z
		var side: float = (coord - float(c[5])) * float(c[6])
		assert_true(side > 0.3, "bed rot %d at %s wakes Krystal on its side of the wall (got %s)" % [int(c[1]), bed.global_position, w])
		assert_true(w.distance_to(bed.global_position) > 0.9, "beside the bed, not in it")
		for u in [buid, wall]:
			GameState.remove_structure(u)
			Factory.find_node(_area, u).free()
		await wait_physics(2)


## A bed in a 2 m wide nook: one long side flush with a wall, the other 0.5 m from the next wall (a
## little too tight for her capsule). The tight side in sight wins over the roomy spot behind the wall.
func test_tight_side_in_sight_beats_a_roomy_spot_behind_the_wall() -> void:
	_make_area()
	_place("wood_wall", Vector3(-8, 0, 1), 90.0, OUTSIDE)
	_place("wood_wall", Vector3(-10, 0, 1), 90.0, OUTSIDE)
	_place("wood_wall", Vector3(-9, 0, 0), 0.0, OUTSIDE)
	_place("wood_wall", Vector3(-9, 0, 2), 0.0, OUTSIDE)
	var bed: Node3D = Factory.spawn_structure(_area, GameState.add_structure("bed", Vector3(-8.5, 0, 1.0), 0.0))
	await wait_physics(2)
	var w: Vector3 = bed.wake_transform().origin
	assert_true(w.x > -10.0 and w.x < -8.0 and w.z > 0.0 and w.z < 2.0, "wakes inside the nook (got %s)" % w)


## Something tall right around every side: she wakes on the mattress, never beyond the walls.
func test_boxed_in_bed_wakes_her_on_top_of_it() -> void:
	_make_area()
	var bed: Node3D = Factory.spawn_structure(_area, GameState.add_structure("bed", Vector3(-8.5, 0, 1.0), 0.0))
	var box := StaticBody3D.new()
	box.collision_layer = 1
	for spec in [[Vector3(0.62, 1.5, 0.0), Vector3(0.1, 3, 3.0)], [Vector3(-0.62, 1.5, 0.0), Vector3(0.1, 3, 3.0)],
			[Vector3(0.0, 1.5, 1.12), Vector3(1.4, 3, 0.1)], [Vector3(0.0, 1.5, -1.12), Vector3(1.4, 3, 0.1)]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = spec[1]
		cs.shape = sh
		cs.position = spec[0]
		box.add_child(cs)
	_area.add_child(box)
	box.global_position = bed.global_position
	await wait_physics(2)
	var w: Vector3 = bed.wake_transform().origin
	var flat := Vector2(w.x - bed.global_position.x, w.z - bed.global_position.z)
	assert_true(flat.length() < 0.05, "stays over the bed (got %s)" % w)
	assert_true(w.y > bed.global_position.y + 0.6, "on top of the mattress (got %s)" % w)


## The bed stands outside, right across a room's doorway (so the room behind it is shut in). She wakes
## on the open side, not in the room the bed seals.
func test_bed_across_a_doorway_wakes_her_on_the_open_side() -> void:
	_make_area()
	_build_room()
	var buid := _place("bed", Vector3(-9.0, 0, 2.5), 90.0, OUTSIDE)
	await wait_physics(2)
	var bed: Node3D = Factory.find_node(_area, buid)
	var w: Vector3 = bed.wake_transform().origin
	assert_false(_in_room(w), "not inside the room the bed shuts (got %s)" % w)
	assert_false(P.would_enclose(w, _ctx(w)), "the wake spot has a way out")


# --- The "bed" spawn follows later building ---------------------------------------------------------------------

## Sleep, then build a chest right on the registered wake spot: the spawn moves to a free side.
func test_bed_spawn_moves_when_something_is_built_on_it() -> void:
	_make_area()
	var bed: Node3D = Factory.spawn_structure(_area, GameState.add_structure("bed", Vector3(-8.5, 0, 1.0), 0.0))
	await wait_physics(2)
	await _sleep_in(bed)
	var before: Vector3 = _unstuck_target().origin
	assert_eq(_structure_hits(before), 0)
	assert_ne(_build("storage_chest", before, 0.0, Vector3(6, 0, 10)), "", "chest built on the old wake spot")
	await wait_physics(2)
	var after: Vector3 = _unstuck_target().origin
	assert_true(after.distance_to(before) > 0.5, "the wake spot moved (%s -> %s)" % [before, after])
	assert_eq(_structure_hits(after), 0, "respawn / unstuck target is clear of structures")


## Sleep in a room, then (from outside) swap its doorway for a plain wall: the "bed" spawn hands over to
## the Haven clearing (death, Pause > "Return to the Haven") and Krystal is told. Put a doorway back and
## she wakes beside her bed again.
func test_walled_in_bed_hands_over_to_the_haven_clearing_until_reopened() -> void:
	_make_area()
	_build_room()
	var buid := _place("bed", Vector3(-11.5, 0, -0.5), 0.0, Vector3(-10.5, 0, 0.5))
	await wait_physics(2)
	var bed: Node3D = Factory.find_node(_area, buid)
	await _sleep_in(bed)
	assert_true(_in_room(_unstuck_target().origin), "wakes beside the bed in the room")
	var door_uid := ""
	for id in GameState.structures:
		if String(GameState.structures[id].get("id", "")) == "wood_doorway":
			door_uid = String(id)
	assert_true(bool(Ops.dismantle(_area, door_uid)["ok"]))
	var wall_uid := _build("wood_wall", Vector3(-9, 0, 2), 0.0, OUTSIDE)
	assert_ne(wall_uid, "", "the gap can be closed from outside")
	await wait_physics(2)
	var shut: Transform3D = _unstuck_target()
	assert_false(P.would_enclose(shut.origin, _ctx(shut.origin)), "respawn / unstuck target is never shut in")
	assert_true(shut.origin.distance_to(HAVEN_RESPAWN) < 0.01, "hands over to the Haven clearing (got %s)" % shut.origin)
	assert_true(_notes.has(Bed.MSG_SHUT_IN), "Krystal is told (notes: %s)" % [_notes])
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "bed", "her bed stays her bed")
	# Open it up again.
	assert_true(bool(Ops.dismantle(_area, wall_uid)["ok"]))
	assert_ne(_build("wood_doorway", Vector3(-9, 0, 2), 0.0, OUTSIDE), "")
	await wait_physics(2)
	var back: Vector3 = _unstuck_target().origin
	assert_true(_in_room(back), "wakes beside the bed again (got %s)" % back)
	assert_false(P.would_enclose(back, _ctx(back)))
	assert_true(_notes.has(Bed.MSG_OPEN_AGAIN), "Krystal is told it's open again (notes: %s)" % [_notes])
