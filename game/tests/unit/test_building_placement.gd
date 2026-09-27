extends "res://tests/test_case.gd"
## Placement rules: snapping, footprints & rotation, build area, blocked circles, per-layer overlap,
## edge walls, roof support, uneven ground and the "never shut Krystal in" rule.

const P := preload("res://src/building/placement.gd")

const BA := {"center": Vector2(0, 0), "radius": 16.0, "blocked": [{"center": Vector2(0, -6), "radius": 3.5}]}


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _ctx(structs: Dictionary = {}, extra: Dictionary = {}) -> Dictionary:
	var c := {"structures": structs, "area_id": "surface", "build_area": BA, "height_fn": _flat}
	c.merge(extra, true)
	return c


func _rec(id: String, pos: Vector3, rot: float = 0.0) -> Dictionary:
	return {"id": id, "area": "surface", "pos": [pos.x, pos.y, pos.z], "rot": rot, "data": {}}


func _ok(id: String, pos: Vector3, rot: float, ctx: Dictionary) -> bool:
	return bool(P.validate(id, pos, rot, ctx)["ok"])


func test_snap_cell_structures() -> void:
	var chest := P.def_of("storage_chest")
	assert_eq(P.snap_position(chest, Vector3(3.3, 0, 4.9), 0), Vector3(3.5, 0, 4.5))
	assert_eq(P.snap_position(chest, Vector3(-0.2, 0, -0.9), 0), Vector3(-0.5, 0, -0.5))
	var wb := P.def_of("workbench")       # 2 x 1
	assert_eq(P.snap_position(wb, Vector3(0.3, 0, 0.2), 0), Vector3(0, 0, 0.5))
	assert_eq(P.snap_position(wb, Vector3(0.3, 0, 0.2), 90), Vector3(0.5, 0, 0), "rotated footprint snaps on the other axis")


func test_footprint_rotation_swaps_cells() -> void:
	var wb := P.def_of("workbench")
	assert_eq(P.footprint(wb, Vector3(0, 0, 0.5), 0)["cells"], [Vector2i(-1, 0), Vector2i(0, 0)])
	assert_eq(P.footprint(wb, Vector3(0.5, 0, 0), 90)["cells"], [Vector2i(0, -1), Vector2i(0, 0)])
	assert_eq(P.footprint(wb, Vector3(0, 0, 0.5), 180)["cells"], [Vector2i(-1, 0), Vector2i(0, 0)], "180 = same cells as 0")
	assert_eq(P.footprint(wb, Vector3(0.5, 0, 0), 270)["cells"], [Vector2i(0, -1), Vector2i(0, 0)])
	var bed := P.def_of("bed")            # 1 x 2
	assert_eq(P.footprint(bed, Vector3(0.5, 0, 1.0), 0)["cells"], [Vector2i(0, 0), Vector2i(0, 1)])
	assert_eq(P.footprint(bed, Vector3(1.0, 0, 0.5), 90)["cells"], [Vector2i(0, 0), Vector2i(1, 0)])
	assert_eq(P.norm_rot("cell", -90.0), 270)
	assert_eq(P.norm_rot("edge2", 270.0), 90, "walls only have two orientations")


func test_floor_and_wall_snapping() -> void:
	var floor_def := P.def_of("wood_floor")
	assert_eq(P.snap_position(floor_def, Vector3(3.1, 0, -0.4), 0), Vector3(3, 0, -1))
	assert_eq(P.footprint(floor_def, Vector3(3, 0, -1), 0)["cells"], [Vector2i(2, -2), Vector2i(2, -1), Vector2i(3, -2), Vector2i(3, -1)])
	var wall := P.def_of("wood_wall")
	assert_eq(P.snap_position(wall, Vector3(3.1, 0, -0.4), 0), Vector3(3, 0, 0), "along X on the z = 0 grid line")
	assert_eq(P.footprint(wall, Vector3(3, 0, 0), 0)["edges"], [Vector3i(1, 0, 0)])
	assert_eq(P.snap_position(wall, Vector3(3.1, 0, -0.4), 90), Vector3(4, 0, -1), "along Z on the x = 4 grid line")
	assert_eq(P.footprint(wall, Vector3(4, 0, -1), 90)["edges"], [Vector3i(2, -1, 1)])
	assert_eq(P.footprint(wall, Vector3(3, 0, 0), 180)["edges"], [Vector3i(1, 0, 0)], "180 is the same edge")


func test_inside_and_outside_the_build_area() -> void:
	var ctx := _ctx()
	assert_true(_ok("storage_chest", Vector3(5.5, 0, 5.5), 0, ctx))
	var r := P.validate("storage_chest", Vector3(15.5, 0, 0.5), 0, ctx)
	assert_false(bool(r["ok"]), "corner pokes out of the 16 m circle")
	assert_eq(String(r["reason"]), P.MSG_OUTSIDE)
	assert_false(_ok("storage_chest", Vector3(40.5, 0, 40.5), 0, ctx))
	var nowhere := _ctx({}, {"build_area": {}})
	assert_eq(String(P.validate("storage_chest", Vector3(0.5, 0, 0.5), 0, nowhere)["reason"]), P.MSG_OUTSIDE, "no build area = not here")


func test_blocked_circles() -> void:
	var ctx := _ctx()
	var r := P.validate("storage_chest", Vector3(0.5, 0, -5.5), 0, ctx)
	assert_false(bool(r["ok"]), "inside the Ward Stone circle")
	assert_eq(String(r["reason"]), P.MSG_CLEAR)
	assert_true(_ok("storage_chest", Vector3(0.5, 0, -1.5), 0, ctx), "4 m from the stone is fine")
	var named := _ctx({}, {"build_area": {"center": Vector2.ZERO, "radius": 16.0, "blocked": [{"center": Vector2(4, 3), "radius": 2.2, "name": "campfire"}]}})
	assert_eq(String(P.validate("storage_chest", Vector3(4.5, 0, 3.5), 0, named)["reason"]), "Too close to the campfire")


func test_overlap_same_layer_blocks_other_layers_do_not() -> void:
	var structs := {"s1": _rec("storage_chest", Vector3(2.5, 0, 2.5))}
	var r := P.validate("table", Vector3(2.5, 0, 2.5), 0, _ctx(structs))
	assert_false(bool(r["ok"]))
	assert_eq(String(r["blocker"]), "s1")
	assert_true(String(r["reason"]).contains("Storage Chest"), String(r["reason"]))
	assert_true(_ok("wood_floor", Vector3(3, 0, 3), 0, _ctx(structs)), "floors are another layer")
	structs["f1"] = _rec("wood_floor", Vector3(3, 0, 3))
	assert_false(_ok("wood_floor", Vector3(3, 0, 3), 0, _ctx(structs)), "two floors on one tile")
	assert_true(_ok("wood_floor", Vector3(5, 0, 3), 0, _ctx(structs)), "the next tile is free")
	assert_true(_ok("table", Vector3(3.5, 0, 3.5), 0, _ctx(structs)), "furniture on a floor")
	assert_almost(P.placement_y("table", Vector3(3.5, 0, 3.5), 0, _ctx(structs)), P.FLOOR_TOP, 0.001, "stands on the floor top")
	assert_almost(P.placement_y("table", Vector3(7.5, 0, 3.5), 0, _ctx(structs)), 0.0, 0.001, "on the ground elsewhere")


func test_rotated_footprints_overlap_correctly() -> void:
	var structs := {"b": _rec("bed", Vector3(0.5, 0, 1.0), 0)}
	assert_false(_ok("storage_chest", Vector3(0.5, 0, 1.5), 0, _ctx(structs)), "bed foot cell")
	assert_true(_ok("storage_chest", Vector3(1.5, 0, 0.5), 0, _ctx(structs)), "beside the bed")
	var turned := {"b": _rec("bed", Vector3(1.0, 0, 0.5), 90)}
	assert_false(_ok("storage_chest", Vector3(1.5, 0, 0.5), 0, _ctx(turned)), "turned bed covers x+1")
	assert_true(_ok("storage_chest", Vector3(0.5, 0, 1.5), 0, _ctx(turned)), "and no longer z+1")


func test_edge_walls_overlap_and_meet_at_corners() -> void:
	var structs := {"w": _rec("wood_wall", Vector3(3, 0, 0), 0)}
	assert_false(_ok("wood_window", Vector3(3, 0, 0), 0, _ctx(structs)), "same edge")
	assert_false(_ok("wood_wall", Vector3(3, 0, 0), 180, _ctx(structs)), "same edge, flipped")
	assert_true(_ok("wood_wall", Vector3(4, 0, -1), 90, _ctx(structs)), "perpendicular wall at the corner")
	assert_true(_ok("wood_wall", Vector3(5, 0, 0), 0, _ctx(structs)), "next wall along the line")
	assert_true(_ok("storage_chest", Vector3(2.5, 0, 0.5), 0, _ctx(structs)), "objects may stand against walls")


func test_roofs_need_support() -> void:
	var r := P.validate("wood_roof", Vector3(3, 3, 1), 0, _ctx())
	assert_false(bool(r["ok"]))
	assert_eq(String(r["reason"]), P.MSG_ROOF)
	var structs := {"w": _rec("wood_wall", Vector3(3, 0, 0), 0)}
	assert_true(_ok("wood_roof", Vector3(3, 3, 1), 0, _ctx(structs)), "a wall under one edge")
	assert_almost(P.placement_y("wood_roof", Vector3(3, 0, 1), 0, _ctx(structs)), 3.0, 0.001, "sits on top of the wall")
	structs["r1"] = _rec("wood_roof", Vector3(3, 3, 1), 0)
	assert_true(_ok("wood_roof", Vector3(5, 3, 1), 0, _ctx(structs)), "next to a supported roof")
	assert_false(_ok("wood_roof", Vector3(7, 3, 1), 0, _ctx(structs)), "two tiles away from any wall")
	assert_false(_ok("wood_roof", Vector3(3, 3, 1), 0, _ctx(structs)), "roof layer overlap")


func test_uneven_ground_is_rejected() -> void:
	var steep := func(x: float, _z: float) -> float: return x * 0.7
	var r := P.validate("storage_chest", Vector3(2.5, 0, 2.5), 0, _ctx({}, {"height_fn": steep}))
	assert_false(bool(r["ok"]))
	assert_eq(String(r["reason"]), P.MSG_UNEVEN)
	var gentle := func(x: float, _z: float) -> float: return x * 0.1
	assert_true(_ok("storage_chest", Vector3(2.5, 0, 2.5), 0, _ctx({}, {"height_fn": gentle})))
	assert_almost(P.placement_y("wood_floor", Vector3(3, 0, 3), 0, _ctx({}, {"height_fn": gentle})), 0.392, 0.01, "floors rest on the highest corner")


func test_wall_cannot_shut_the_player_into_a_tile() -> void:
	var player := Vector3(1.0, 0, 1.0)
	var structs := {
		"a": _rec("wood_wall", Vector3(1, 0, 0), 0),
		"b": _rec("wood_wall", Vector3(1, 0, 2), 0),
		"c": _rec("wood_wall", Vector3(0, 0, 1), 90),
	}
	var ctx := _ctx(structs, {"player_pos": player})
	assert_false(P.would_enclose(player, ctx), "three walls leave a gap")
	var r := P.validate("wood_wall", Vector3(2, 0, 1), 90, ctx)
	assert_false(bool(r["ok"]), "fourth wall would trap Krystal")
	assert_eq(String(r["reason"]), P.MSG_ENCLOSE)
	assert_false(_ok("wood_window", Vector3(2, 0, 1), 90, ctx), "windows block too")
	assert_true(_ok("wood_doorway", Vector3(2, 0, 1), 90, ctx), "a doorway keeps a way out")
	assert_true(_ok("wood_wall", Vector3(2, 0, 1), 90, _ctx(structs, {"player_pos": Vector3(5, 0, 5)})), "fine when she's outside")


func test_bigger_room_enclosure_is_detected() -> void:
	# 4 x 4 m room: x 0..4, z 0..4, player in the middle.
	var structs := {}
	var walls := [[Vector3(1, 0, 0), 0], [Vector3(3, 0, 0), 0], [Vector3(1, 0, 4), 0], [Vector3(3, 0, 4), 0],
		[Vector3(0, 0, 1), 90], [Vector3(0, 0, 3), 90], [Vector3(4, 0, 1), 90]]
	for i in walls.size():
		structs["w%d" % i] = _rec("wood_wall", walls[i][0], float(walls[i][1]))
	var inside := _ctx(structs, {"player_pos": Vector3(2.2, 0, 2.3)})
	assert_false(_ok("wood_wall", Vector3(4, 0, 3), 90, inside), "last wall of the room")
	assert_true(_ok("wood_doorway", Vector3(4, 0, 3), 90, inside))
	assert_true(_ok("wood_wall", Vector3(4, 0, 3), 90, _ctx(structs, {"player_pos": Vector3(-3, 0, 2)})), "player outside the room")


func test_solid_objects_count_for_enclosure_but_rugs_do_not() -> void:
	var player := Vector3(5.5, 0, 5.5)
	var structs := {"f1": _rec("fence", Vector3(4.5, 0, 5.5)), "f2": _rec("fence", Vector3(6.5, 0, 5.5)), "f3": _rec("fence", Vector3(5.5, 0, 4.5))}
	var ctx := _ctx(structs, {"player_pos": player})
	assert_false(_ok("fence", Vector3(5.5, 0, 6.5), 0, ctx), "fences all around")
	assert_true(_ok("flower_pot", Vector3(5.5, 0, 6.5), 0, ctx), "non-solid decor never traps")
	assert_true(_ok("fence", Vector3(7.5, 0, 7.5), 0, ctx), "elsewhere is fine")


func test_structure_at_point_prefers_objects_then_walls_then_floors() -> void:
	var structs := {"f": _rec("wood_floor", Vector3(1, 0, 1)), "t": _rec("table", Vector3(0.5, 0.12, 0.5)), "w": _rec("wood_wall", Vector3(1, 0, 2), 0)}
	var ctx := _ctx(structs)
	assert_eq(P.structure_at_point(Vector3(0.4, 0, 0.6), ctx), "t")
	assert_eq(P.structure_at_point(Vector3(1.6, 0, 1.9), ctx), "w", "near the wall line")
	assert_eq(P.structure_at_point(Vector3(1.6, 0, 1.2), ctx), "f")
	assert_eq(P.structure_at_point(Vector3(9, 0, 9), ctx), "")


func test_other_areas_are_ignored() -> void:
	var rec := _rec("storage_chest", Vector3(2.5, 0, 2.5))
	rec["area"] = "below"
	assert_true(_ok("storage_chest", Vector3(2.5, 0, 2.5), 0, _ctx({"x": rec})), "structures of other areas don't occupy the Haven")


func test_already_enclosed_player_can_still_build() -> void:
	# Krystal hopped into a fenced pen: placing more solid pieces elsewhere must not be blocked forever.
	var player := Vector3(5.5, 0, 5.5)
	var structs := {"f1": _rec("fence", Vector3(4.5, 0, 5.5)), "f2": _rec("fence", Vector3(6.5, 0, 5.5)),
		"f3": _rec("fence", Vector3(5.5, 0, 4.5)), "f4": _rec("fence", Vector3(5.5, 0, 6.5))}
	var ctx := _ctx(structs, {"player_pos": player})
	assert_true(P.would_enclose(player, ctx), "she is in the pen")
	assert_true(_ok("storage_chest", Vector3(9.5, 0, 9.5), 0, _ctx(structs, {"player_pos": player})), "building elsewhere still works")

