extends "res://tests/test_case.gd"
## AUDIT (surface economy & world): fixed wake-up points vs the Haven build system.
## Game.respawn_player / Pause > "Return to the Haven" teleport Krystal to a registered spawn with no
## overlap check (player.teleport). The bed's wake spot is computed once (sleep / area load) and nothing
## stops a structure being built on it afterwards.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Factory := preload("res://src/building/structure_factory.gd")
const BuildingSystem := preload("res://src/building/building_system.gd")
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


## Sleep in a bed (west Haven, clear of the keep-clear circles), walk away, build a chest right on the
## wake spot, then do what Game.respawn_player / "Return to the Haven" do. Building there is allowed
## (by design); the bed re-validates its wake spot after every piece built, so the target moves.
func test_b_wall_on_the_bed_wake_spot() -> void:
	_make_area()
	var bed_uid := GameState.add_structure("bed", Vector3(-8.5, 0, 1.0), 0)
	var bed: Node3D = Factory.spawn_structure(_area, bed_uid)
	await wait_physics(2)
	GameState.total_minutes = 21.5 * 60.0
	await bed.sleep(null)
	var w: Vector3 = (_area.spawns["bed"] as Transform3D).origin
	print("    bed at %s wakes Krystal at %s" % [bed.global_position, w])
	# A chest (solid, 0.8 m) on the wake spot while Krystal stands elsewhere, built as the build mode does:
	var chest_pos: Vector3 = P.snap_position(P.def_of("storage_chest"), w, 0.0)
	var res := P.validate("storage_chest", chest_pos, 0.0, _ctx(Vector3(6, 0, 10)))
	print("    chest centred at %s over the wake spot: ok=%s %s" % [chest_pos, res["ok"], res["reason"]])
	if bool(res["ok"]):
		GameState.give_item("storage_chest", 1)
		Ops.place_structure(_area, "storage_chest", Vector3(chest_pos.x, float(res["y"]), chest_pos.z), 0.0)
	await wait_physics(2)
	var rs := PausePanel.unstuck_spawn("surface", GameState.player)
	var xf: Transform3D = _area.get_spawn(rs)
	var space := _area.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, xf.origin + Vector3.UP * 0.9)
	q.collision_mask = 32
	var hits := space.intersect_shape(q, 4)
	var pl: CharacterBody3D = load("res://src/player/player.gd").new()
	_area.add_child(pl)
	pl.read_from_state()
	pl.teleport(xf)
	await wait_physics(40)
	print("    death/unstuck target '%s' now %s (overlaps %d structure collider); Krystal ends at %s" % [rs, xf.origin, hits.size(), pl.global_position])
	pl.queue_free()
	await wait_frames(1)
	assert_eq(hits.size(), 0, "the respawn point is re-validated / kept clear of structures")


## The enclosure rule only protects where Krystal stands NOW. Bed in a 4 x 4 m room, sleep (wake spot
## registered inside), step outside, close the room with walls: accepted. Death / "Return to the Haven"
## used to put her in a sealed room (the unstuck option kept sending her back to the same bed spot);
## now the walled-in bed hands its spawn over to the Haven's own wake-up point.
func test_d_sealed_bedroom_respawn() -> void:
	_make_area()
	var bed_uid := GameState.add_structure("bed", Vector3(-9.5, 0, 0.0), 0)
	var bed: Node3D = Factory.spawn_structure(_area, bed_uid)
	await wait_physics(2)
	GameState.total_minutes = 21.5 * 60.0
	await bed.sleep(null)
	var outside := Vector3(-4, 0, 6)
	var walls := [
		[Vector3(-11, 0, -2), 0.0], [Vector3(-9, 0, -2), 0.0], [Vector3(-11, 0, 2), 0.0], [Vector3(-9, 0, 2), 0.0],
		[Vector3(-12, 0, -1), 90.0], [Vector3(-12, 0, 1), 90.0], [Vector3(-8, 0, -1), 90.0], [Vector3(-8, 0, 1), 90.0],
	]
	var all_ok := true
	for wv in walls:
		var pos: Vector3 = P.snap_position(P.def_of("wood_wall"), wv[0], float(wv[1]))
		var res := P.validate("wood_wall", pos, float(wv[1]), _ctx(outside))
		if not bool(res["ok"]):
			print("    refused wall at %s: %s" % [pos, res["reason"]])
			all_ok = false
			continue
		# Built as the build mode does it (consumes the piece, emits Events.structure_placed).
		GameState.give_item("wood_wall", 1)
		Ops.place_structure(_area, "wood_wall", Vector3(pos.x, float(res["y"]), pos.z), float(wv[1]))
	await wait_physics(2)
	var rs := PausePanel.unstuck_spawn("surface", GameState.player)
	var xf: Transform3D = _area.get_spawn(rs)
	var sealed := P.would_enclose(xf.origin, _ctx(xf.origin))
	var pl: CharacterBody3D = load("res://src/player/player.gd").new()
	_area.add_child(pl)
	pl.read_from_state()
	pl.teleport(xf)
	await wait_physics(20)
	var e := pl.global_position
	var inside := e.x > -12.0 and e.x < -8.0 and e.z > -2.0 and e.z < 2.0
	print("    all 8 walls accepted from outside: %s; respawn/unstuck spawn '%s' at %s sealed=%s; Krystal at %s inside=%s" % [
		all_ok, rs, xf.origin, sealed, e, inside])
	pl.queue_free()
	await wait_frames(1)
	assert_false(all_ok and sealed and inside, "closing a room around the registered wake-up point is refused (Krystal respawns sealed in)")


## Bed pushed against a house wall: wake_transform() only checks that a capsule fits 1.05 m to the side,
## not that it is reachable from the bed, so Krystal wakes on the far side of the wall (outside the house).
func test_e_bed_against_a_wall_wakes_outside() -> void:
	_make_area()
	var wuid := GameState.add_structure("wood_wall", Vector3(-8, 0, 1), 90.0)   # x = -8 line, z in [0, 2]
	Factory.spawn_structure(_area, wuid)
	var bed_uid := GameState.add_structure("bed", Vector3(-8.5, 0, 1.0), 0)     # cells x in [-9, -8]: flush with the wall
	var bed: Node3D = Factory.spawn_structure(_area, bed_uid)
	await wait_physics(3)
	var w: Vector3 = bed.wake_transform().origin
	print("    bed centre x %.2f, wall on x = -8, wake spot %s (%s the wall)" % [bed.global_position.x, w, "BEYOND" if w.x > -8.0 else "same side as"])
	assert_true(w.x < -8.0, "Krystal wakes on the bed's side of the wall")


## On load the bed registers its wake spot (deferred) with a physics query; neighbouring pieces spawned
## in the same attach() already count (control: this is NOT a bug).
func test_c_bed_wake_spot_after_reload_sees_neighbours() -> void:
	_make_area()
	var bed_uid := GameState.add_structure("bed", Vector3(-8.5, 0, 1.0), 0)
	GameState.structures[bed_uid]["data"] = {"respawn": true}
	GameState.add_structure("storage_chest", Vector3(-7.5, 0, 1.5), 0)   # on the first candidate side
	BuildingSystem.attach(_area)
	await wait_frames(1)
	var sp: Transform3D = _area.get_spawn("bed")
	await wait_physics(3)
	var bed: Node3D = Factory.find_node(_area, bed_uid)
	var fresh: Transform3D = bed.wake_transform()
	print("    wake spot registered on load %s, recomputed after physics %s" % [sp.origin, fresh.origin])
	assert_true(sp.origin.distance_to(fresh.origin) < 0.05, "load-time wake spot matches a settled physics query")
