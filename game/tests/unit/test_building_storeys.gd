extends "res://tests/test_case.gd"
## Two storeys (Chapter Two): upper floors need support (walls, porch posts, a supported neighbour), nothing
## new floats, stairs keep their stairwell, foot and top clear, pieces upstairs need an upper floor, roofs
## connect at the new height, dismantling a support is refused with a clear reason (no collapse, nothing
## destroyed), the enclosure rule works upstairs, level-0 occupancy keys stay byte-identical, and the
## non-destructive audit only reports.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Storey := preload("res://src/building/models_storey.gd")

const BA := {"center": Vector2(0, 0), "radius": 30.0, "blocked": []}

var _game_saved: Dictionary = {}


func before_each() -> void:
	fresh_state()


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _ctx(structs: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var c := {"structures": structs, "area_id": "surface", "build_area": BA, "height_fn": _flat}
	c.merge(extra, true)
	return c


func _rec(id: String, pos: Vector3, rot: float = 0.0, level: int = 0) -> Dictionary:
	var data := {}
	if level > 0:
		data["level"] = level
	return {"id": id, "area": "surface", "pos": [pos.x, pos.y, pos.z], "rot": rot, "data": data}


func _v(id: String, pos: Vector3, rot: float, ctx: Dictionary) -> Dictionary:
	return P.validate(id, pos, rot, ctx)


## A 4 x 4 m room x 0..4, z 0..4 (eight wall panels).
func _room(structs: Dictionary, prefix: String = "w", level: int = 0, y: float = 0.0) -> void:
	var walls := [[Vector3(1, y, 0), 0], [Vector3(3, y, 0), 0], [Vector3(1, y, 4), 0], [Vector3(3, y, 4), 0],
		[Vector3(0, y, 1), 90], [Vector3(0, y, 3), 90], [Vector3(4, y, 1), 90], [Vector3(4, y, 3), 90]]
	for i in walls.size():
		structs["%s%d" % [prefix, i]] = _rec("wood_wall", walls[i][0], float(walls[i][1]), level)


# --- Support ------------------------------------------------------------------------------------------------

func test_upper_floor_needs_support_and_sits_one_storey_up() -> void:
	var s := {}
	_room(s)
	var r := _v("upper_floor", Vector3(1, 0, 1), 0, _ctx(s))
	assert_true(bool(r["ok"]), String(r["reason"]))
	assert_eq(int(r["level"]), 1, "upper floors are always upstairs")
	assert_almost(float(r["y"]), P.LEVEL_HEIGHT, 0.001, "rests on the wall tops")
	var floating := _v("upper_floor", Vector3(11, 0, 11), 0, _ctx(s))
	assert_false(bool(floating["ok"]), "no floating new floor")
	assert_eq(String(floating["reason"]), P.MSG_UPPER)
	# A railing or half wall is too short to hold a floor up; a window/doorway wall is full height.
	var short := {"r": _rec("wood_railing", Vector3(11, 0, 10), 0), "h": _rec("half_wall", Vector3(12, 0, 11), 90)}
	assert_false(bool(_v("upper_floor", Vector3(11, 0, 11), 0, _ctx(short))["ok"]), "railings don't hold floors")
	var win := {"a": _rec("arched_window", Vector3(11, 0, 10), 0)}
	assert_true(bool(_v("upper_floor", Vector3(11, 0, 11), 0, _ctx(win))["ok"]), "arched window walls support")
	var door := {"d": _rec("wood_doorway", Vector3(11, 0, 10), 0)}
	assert_true(bool(_v("upper_floor", Vector3(11, 0, 11), 0, _ctx(door))["ok"]), "legacy doorways support by rule")


func test_porch_posts_and_supported_neighbours_hold_tiles_but_not_chains() -> void:
	var s := {"p": _rec("porch_post", Vector3(10.5, 0, 10.5))}
	var r := _v("upper_floor", Vector3(11, 0, 11), 0, _ctx(s))
	assert_true(bool(r["ok"]), "a post under one of its cells: " + String(r["reason"]))
	assert_almost(float(r["y"]), 3.0, 0.001)
	# Cantilever: one tile past a directly supported tile is fine, two are not.
	var c := {"w": _rec("wood_wall", Vector3(4, 0, 1), 90), "u1": _rec("upper_floor", Vector3(5, 3, 1), 0, 1)}
	assert_true(bool(_v("upper_floor", Vector3(7, 0, 1), 0, _ctx(c))["ok"]), "a supported neighbour holds it")
	assert_almost(float(_v("upper_floor", Vector3(7, 0, 1), 0, _ctx(c))["y"]), 3.0, 0.001, "lines up with the neighbour")
	c["u2"] = _rec("upper_floor", Vector3(7, 3, 1), 0, 1)
	var far := _v("upper_floor", Vector3(9, 0, 1), 0, _ctx(c))
	assert_false(bool(far["ok"]), "no chains of floating tiles")
	assert_eq(String(far["reason"]), P.MSG_UPPER)


func test_pieces_upstairs_need_an_upper_floor_and_level_ok() -> void:
	var s := {}
	_room(s)
	s["u"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	var up := _ctx(s, {"level": 1})
	var t := _v("table", Vector3(0.5, 0, 0.5), 0, up)
	assert_true(bool(t["ok"]), "legacy furniture may go upstairs: " + String(t["reason"]))
	assert_almost(float(t["y"]), 3.0 + P.UPPER_TOP, 0.001, "stands on the upper floor")
	var off := _v("table", Vector3(2.5, 0, 2.5), 0, up)
	assert_false(bool(off["ok"]))
	assert_eq(String(off["reason"]), P.MSG_NEEDS_UPPER, "no upper floor under it")
	assert_eq(String(_v("crop_plot", Vector3(1, 0, 1), 0, up)["reason"]), P.MSG_GROUND_ONLY, "crop plots stay downstairs")
	var bs := _v("bookshelf", Vector3(1, 0, 0.5), 0, up)
	assert_true(bool(bs["ok"]), "level_ok new furniture: " + String(bs["reason"]))
	# Walls upstairs stand on the upper floor's edge, legacy walls included.
	var w := _v("wood_wall", Vector3(1, 0, 0), 0, up)
	assert_true(bool(w["ok"]), String(w["reason"]))
	assert_almost(float(w["y"]), 3.0, 0.001, "upstairs wall base = upper floor origin")
	assert_eq(String(_v("wood_railing", Vector3(5, 0, 0), 0, up)["reason"]), P.MSG_NEEDS_UPPER, "railing needs a floor beside it")
	# The same wall on the ground floor is still just a ground wall (overlap with the room's wall).
	assert_false(bool(_v("wood_wall", Vector3(1, 0, 0), 0, _ctx(s))["ok"]), "ground edge is taken")


func test_roofs_connect_on_the_upstairs_walls() -> void:
	var s := {}
	_room(s)
	s["u"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	s["uw"] = _rec("wood_wall", Vector3(1, 3, 0), 0, 1)
	var r := _v("gable_roof", Vector3(1, 0, 1), 0, _ctx(s))
	assert_true(bool(r["ok"]), String(r["reason"]))
	assert_eq(int(r["level"]), 1, "a roof on upstairs walls is an upstairs roof")
	assert_almost(float(r["y"]), 6.0, 0.001, "on top of the upstairs wall")
	s["ur"] = _rec("gable_roof", Vector3(1, 6, 1), 0, 1)
	var n := _v("roof_corner", Vector3(3, 0, 1), 0, _ctx(s))
	assert_eq(int(n["level"]), 1, "neighbour of an upstairs roof")
	assert_true(bool(n["ok"]), String(n["reason"]))
	assert_almost(float(n["y"]), 6.0, 0.001, "lines up with the neighbour roof")
	# A ground-floor roof may not cover an upper floor; an upper floor may not be built into a roof.
	var s2 := {}
	_room(s2)
	s2["u"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	var low := _v("wood_roof", Vector3(1, 0, 1), 0, _ctx(s2))
	assert_false(bool(low["ok"]))
	assert_eq(String(low["reason"]), P.MSG_ROOF_OVER_UPPER)
	assert_eq(String(low["blocker"]), "u")
	s2["r"] = _rec("wood_roof", Vector3(3, 3, 3), 0)
	var into := _v("upper_floor", Vector3(3, 0, 3), 0, _ctx(s2))
	assert_eq(String(into["reason"]), P.MSG_UPPER_UNDER_ROOF)


# --- Stairs ------------------------------------------------------------------------------------------------

## A 4 x 6 m room x 0..4, z 0..6 with a doorway at x 0..2 on the south side (z = 6).
func _stair_room() -> Dictionary:
	var s := {}
	var walls := [[Vector3(1, 0, 0), 0, "wood_wall"], [Vector3(3, 0, 0), 0, "wood_wall"], [Vector3(1, 0, 6), 0, "wood_doorway"],
		[Vector3(3, 0, 6), 0, "wood_wall"], [Vector3(0, 0, 1), 90, "wood_wall"], [Vector3(0, 0, 3), 90, "wood_wall"],
		[Vector3(0, 0, 5), 90, "wood_wall"], [Vector3(4, 0, 1), 90, "wood_wall"], [Vector3(4, 0, 3), 90, "wood_wall"],
		[Vector3(4, 0, 5), 90, "wood_wall"]]
	for i in walls.size():
		s["w%d" % i] = _rec(String(walls[i][2]), walls[i][0], float(walls[i][1]))
	return s


## Stairs rot 0 at x 0..2, z 2..6 (top at z = 2, landing tile x 0..2, z 0..2, foot at the doorway).
func _stair_house() -> Dictionary:
	var s := _stair_room()
	s["st"] = _rec("wood_stairs", Vector3(1, 0, 4), 0)
	return s


func test_stairs_snap_to_the_even_grid_and_know_their_ends() -> void:
	var def := P.def_of("wood_stairs")
	assert_eq(P.snap_position(def, Vector3(1.3, 0, 4.2), 0), Vector3(1, 0, 4))
	assert_eq(P.snap_position(def, Vector3(1.3, 0, 4.2), 90), Vector3(2, 0, 5), "rotated: 4 m along X")
	var fp := P.footprint(def, Vector3(1, 0, 4), 0)
	assert_eq(fp["layer"], "stair")
	assert_eq((fp["cells"] as Array).size(), 8)
	assert_eq(fp["rect"], Rect2(0, 2, 2, 4))
	var ends := P.stair_ends(fp)
	assert_eq(ends["landing"], Vector2i(0, 0), "landing tile beyond the top (-Z)")
	assert_eq(ends["top_edge"], Vector3i(0, 1, 0))
	assert_eq(ends["bottom_edge"], Vector3i(0, 3, 0))
	assert_eq(ends["mid_edge"], Vector3i(0, 2, 0))
	assert_eq(ends["entry"], [Vector2i(0, 6), Vector2i(1, 6)])
	var e90 := P.stair_ends(P.footprint(def, Vector3(2, 0, 5), 90))
	assert_eq(e90["landing"], Vector2i(-2, 4), "rot 90 rises toward -X")
	assert_eq(e90["up"], Vector2i(-1, 0))
	assert_true(Storey.stair_collision_points().size() == 6, "one wedge")
	var s := {}
	var r := _v("wood_stairs", Vector3(1, 0, 4), 0, _ctx(s))
	assert_true(bool(r["ok"]), String(r["reason"]))
	assert_eq(int(r["level"]), 0)
	assert_false(P.blocks_movement(def), "stairs are walkable, never a blocker")


func test_stairwell_foot_and_top_stay_clear() -> void:
	var s := _stair_house()
	var c := _ctx(s)
	assert_eq(String(_v("storage_chest", Vector3(0.5, 0, 4.5), 0, c)["reason"]), P.MSG_STAIRWELL, "nothing in the stairwell")
	assert_eq(String(_v("rug", Vector3(1, 0, 4), 0, c)["blocker"]), "st")
	assert_eq(String(_v("fence", Vector3(0.5, 0, 6.5), 0, c)["reason"]), P.MSG_STAIR_FOOT, "solid piece at the foot")
	assert_true(bool(_v("flower_pot", Vector3(0.5, 0, 6.5), 0, c)["ok"]), "a non-solid pot at the foot is fine")
	assert_eq(String(_v("wood_wall", Vector3(1, 0, 4), 0, c)["reason"]), P.MSG_STAIR_CUT, "wall across the middle")
	# The room's south wall line z = 4 runs across the stairs' middle only at x 0..2 (already a room wall
	# there), so use a fresh set for the foot/bottom edge.
	var s2 := {"st": _rec("wood_stairs", Vector3(11, 0, 14), 0)}
	var c2 := _ctx(s2)
	assert_eq(String(_v("wood_wall", Vector3(11, 0, 16), 0, c2)["reason"]), P.MSG_STAIR_FOOT, "wall across the foot")
	assert_true(bool(_v("wood_doorway", Vector3(11, 0, 16), 0, c2)["ok"]), "a doorway at the foot is fine")
	assert_true(bool(_v("wood_wall", Vector3(10, 0, 13), 90, c2)["ok"]), "walls along the sides are fine")
	var up_on_stairs := _v("upper_floor", Vector3(11, 0, 13), 0, _ctx({"st": s2["st"], "w": _rec("wood_wall", Vector3(10, 0, 13), 90)}))
	assert_eq(String(up_on_stairs["reason"]), P.MSG_STAIRWELL, "no upper floor over the stairwell (head room)")
	# Stairs are refused into an existing upper floor or under a roof.
	var s3 := {"w": _rec("wood_wall", Vector3(20, 0, 1), 90), "u": _rec("upper_floor", Vector3(21, 3, 1), 0, 1)}
	assert_eq(String(_v("wood_stairs", Vector3(21, 0, 2), 0, _ctx(s3))["reason"]), P.MSG_STAIRWELL)
	var s4 := {"w": _rec("wood_wall", Vector3(20, 0, 1), 90), "r": _rec("wood_roof", Vector3(21, 3, 1), 0)}
	assert_eq(String(_v("wood_stairs", Vector3(21, 0, 2), 0, _ctx(s4))["reason"]), P.MSG_STAIR_ROOF)


func test_top_of_the_stairs_and_a_reachable_upstairs() -> void:
	var s := _stair_house()
	assert_false(P.has_reachable_upstairs(_ctx(s)), "no landing yet")
	var land := _v("upper_floor", Vector3(1, 0, 1), 0, _ctx(s))
	assert_true(bool(land["ok"]), "the landing tile: " + String(land["reason"]))
	s["land"] = _rec("upper_floor", Vector3(1, float(land["y"]), 1), 0, 1)
	assert_true(P.has_reachable_upstairs(_ctx(s)), "stairs lead onto an upper floor")
	var up := _ctx(s, {"level": 1})
	var blocked := _v("wood_wall", Vector3(1, 0, 2), 0, up)
	assert_eq(String(blocked["reason"]), P.MSG_STAIR_TOP, "no wall across the top of the stairs")
	assert_eq(String(_v("wood_railing", Vector3(1, 0, 2), 0, up)["reason"]), P.MSG_STAIR_TOP)
	assert_true(bool(_v("wood_doorway", Vector3(1, 0, 2), 0, up)["ok"]), "a doorway at the top is fine")
	assert_eq(String(_v("storage_chest", Vector3(0.5, 0, 1.5), 0, up)["reason"]), P.MSG_STAIR_TOP, "keep the landing row free")
	assert_true(bool(_v("storage_chest", Vector3(0.5, 0, 0.5), 0, up)["ok"]), "the back of the landing is fine")
	# The stair ramp ends flush with the landing's walkable top.
	assert_almost(float(land["y"]) + P.UPPER_TOP, P.STAIR_RISE, 0.001)


func test_stairs_refused_when_the_top_is_walled_off() -> void:
	var s := _stair_room()
	assert_true(bool(_v("wood_stairs", Vector3(1, 0, 4), 0, _ctx(s))["ok"]), "the stairs fit the room")
	s["land"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	s["uw"] = _rec("wood_wall", Vector3(1, 3, 2), 0, 1)
	var r := _v("wood_stairs", Vector3(1, 0, 4), 0, _ctx(s))
	assert_false(bool(r["ok"]))
	assert_eq(String(r["reason"]), P.MSG_STAIR_TOP)
	assert_eq(String(r["blocker"]), "uw")


# --- Dismantling (validation only: no collapse, nothing destroyed) ---------------------------------------------

func test_dismantling_a_support_is_refused_with_a_reason() -> void:
	var wall := GameState.add_structure("wood_wall", Vector3(1, 0, 0), 0)
	var tile := GameState.add_structure("upper_floor", Vector3(1, 3, 1), 0)
	GameState.structures[tile]["data"]["level"] = 1
	var before := GameState.structures.size()
	var res := Ops.dismantle(null, wall)
	assert_false(bool(res["ok"]))
	assert_eq(String(res["reason"]), Ops.MSG_UPPER_ON_SUPPORT)
	assert_eq(GameState.structures.size(), before, "nothing removed or destroyed")
	assert_eq(GameState.count_item("wood_wall"), 0, "no refund for a refused dismantle")
	# A second wall under the tile keeps it up: now the first one may go.
	GameState.add_structure("wood_wall", Vector3(0, 0, 1), 90)
	assert_true(bool(Ops.dismantle(null, wall)["ok"]), "the other wall still holds the floor")


func test_dismantling_an_upper_floor_that_carries_pieces_is_refused() -> void:
	GameState.add_structure("wood_wall", Vector3(4, 0, 1), 90)
	var a := GameState.add_structure("upper_floor", Vector3(5, 3, 1), 0)
	GameState.structures[a]["data"]["level"] = 1
	var b := GameState.add_structure("upper_floor", Vector3(7, 3, 1), 0)     # held only by tile a
	GameState.structures[b]["data"]["level"] = 1
	var res := Ops.can_dismantle(a)
	assert_false(bool(res["ok"]))
	assert_eq(String(res["reason"]), Ops.MSG_UPPER_ON_UPPER)
	var t := GameState.add_structure("table", Vector3(7.5, 3.12, 1.5), 0)
	GameState.structures[t]["data"]["level"] = 1
	assert_eq(String(Ops.can_dismantle(b)["reason"]), Ops.MSG_UPPER_CARRIES, "the table stands on it")
	assert_true(bool(Ops.dismantle(null, t)["ok"]), "furniture upstairs comes off freely")
	assert_true(bool(Ops.dismantle(null, b)["ok"]), "then the outer tile")
	assert_true(bool(Ops.dismantle(null, a)["ok"]), "then the inner one")
	assert_eq(GameState.count_item("upper_floor"), 2, "full refunds")


func test_upstairs_wall_holding_an_upstairs_roof_waits_for_the_roof() -> void:
	GameState.add_structure("wood_wall", Vector3(1, 0, 0), 0)
	var tile := GameState.add_structure("upper_floor", Vector3(1, 3, 1), 0)
	GameState.structures[tile]["data"]["level"] = 1
	var uw := GameState.add_structure("wood_wall", Vector3(1, 3, 0), 0)
	GameState.structures[uw]["data"]["level"] = 1
	var roof := GameState.add_structure("wood_roof", Vector3(1, 6, 1), 0)
	GameState.structures[roof]["data"]["level"] = 1
	assert_eq(String(Ops.can_dismantle(uw)["reason"]), Ops.MSG_ROOF_ON_WALL)
	assert_eq(String(Ops.can_dismantle(tile)["reason"]), Ops.MSG_UPPER_CARRIES, "the upstairs wall stands on the tile")
	assert_true(bool(Ops.dismantle(null, roof)["ok"]))
	assert_true(bool(Ops.dismantle(null, uw)["ok"]))
	assert_true(bool(Ops.dismantle(null, tile)["ok"]))


func test_stairs_always_come_apart_and_grandfathered_floaters_never_lock() -> void:
	var st := GameState.add_structure("wood_stairs", Vector3(1, 0, 4), 0)
	var tile := GameState.add_structure("upper_floor", Vector3(9, 3, 9), 0)     # floating (e.g. an edited save)
	GameState.structures[tile]["data"]["level"] = 1
	var wall := GameState.add_structure("wood_wall", Vector3(3, 0, 0), 0)
	assert_true(bool(Ops.can_dismantle(wall)["ok"]), "an already floating tile never blocks other pieces")
	assert_true(bool(Ops.dismantle(null, st)["ok"]), "stairs can always be taken apart")
	var issues := Ops.audit("surface")
	var found := false
	for i in issues:
		if String(i["uid"]) == tile and String(i["issue"]) == "unsupported_upper":
			found = true
	assert_true(found, "the audit reports the floating tile: " + str(issues))
	assert_true(GameState.structures.has(tile), "the audit never removes anything")


# --- Enclosure upstairs --------------------------------------------------------------------------------------

func test_enclosure_rule_upstairs() -> void:
	var s := {}
	_room(s)
	s["u"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	s["u2"] = _rec("upper_floor", Vector3(3, 3, 1), 0, 1)
	s["a"] = _rec("wood_wall", Vector3(1, 3, 0), 0, 1)
	s["b"] = _rec("wood_wall", Vector3(0, 3, 1), 90, 1)
	s["c"] = _rec("wood_wall", Vector3(1, 3, 2), 0, 1)
	var her := Vector3(1.0, 3.12, 1.0)
	var up := _ctx(s, {"level": 1, "player_pos": her})
	assert_eq(P.player_level(her, up), 1, "standing on the upper floor")
	assert_false(P.would_enclose(her, up), "the open side leads to the next tile and its open edge")
	var last := _v("wood_wall", Vector3(2, 0, 1), 90, up)
	assert_false(bool(last["ok"]), "the fourth upstairs wall would shut her in")
	assert_eq(String(last["reason"]), P.MSG_ENCLOSE)
	assert_true(bool(_v("wood_doorway", Vector3(2, 0, 1), 90, up)["ok"]), "a doorway keeps a way out")
	# Downstairs, upstairs walls are not in her way.
	var below := Vector3(1.0, 0.0, 1.0)
	var down := _ctx(s, {"player_pos": below})
	assert_eq(P.player_level(below, down), 0)
	assert_true(P.would_enclose(below, down) == P.would_enclose(below, _ctx(_ground_only(s), {"player_pos": below})), "only her own storey counts")


func _ground_only(s: Dictionary) -> Dictionary:
	var out := {}
	for k in s:
		if P.level_of(s[k]) == 0:
			out[k] = s[k]
	return out


# --- Legacy keys and records --------------------------------------------------------------------------------

func test_ground_storey_keys_are_the_legacy_keys() -> void:
	var s := {"f": _rec("wood_floor", Vector3(1, 0, 1)), "w": _rec("wood_wall", Vector3(1, 0, 2), 0),
		"r": _rec("wood_roof", Vector3(1, 3, 1), 0), "t": _rec("table", Vector3(0.5, 0.12, 0.5)), "g": _rec("rug", Vector3(1, 0.12, 1))}
	var occ := P.build_occupancy(s, "surface")
	var layers: Array = occ.keys()
	layers.sort()
	assert_eq(layers, ["decor", "edge", "floor", "object", "roof"], "no storey suffix on the ground")
	assert_eq(occ["edge"], {Vector3i(0, 1, 0): "w"})
	assert_eq(P.footprint(P.def_of("wood_wall"), Vector3(1, 0, 2), 0)["layer"], "edge")
	assert_eq(P.level_of(s["w"]), 0, "no data.level = ground")
	var js: Variant = JSON.parse_string(JSON.stringify({"id": "upper_floor", "data": {"level": 1.0}}))
	assert_eq(P.level_of(js), 1, "JSON floats are read as storeys")
	assert_eq(P.level_of({"id": "upper_floor", "data": {}}), 1, "an upper floor is upstairs even without data")
	s["u"] = _rec("upper_floor", Vector3(1, 3, 1), 0, 1)
	assert_true(P.build_occupancy(s, "surface").has("floor@1"))


func test_place_structure_records_the_storey_only_upstairs() -> void:
	GameState.give_item("upper_floor", 1)
	GameState.give_item("table", 2)
	var u := Ops.place_structure(null, "upper_floor", Vector3(1, 3, 1), 0)
	assert_eq(int(GameState.structures[u]["data"]["level"]), 1)
	var t := Ops.place_structure(null, "table", Vector3(0.5, 3.12, 0.5), 0, 1)
	assert_eq(int(GameState.structures[t]["data"]["level"]), 1)
	var g := Ops.place_structure(null, "table", Vector3(5.5, 0, 5.5), 0)
	assert_false((GameState.structures[g]["data"] as Dictionary).has("level"), "ground pieces keep the legacy record shape")
	var back: Dictionary = JSON.parse_string(JSON.stringify(GameState.to_dict()))
	GameState.reset()
	GameState.from_dict(back)
	assert_eq(P.level_of(GameState.structures[t]), 1, "the storey survives a save")
	assert_eq(P.level_of(GameState.structures[g]), 0)


func test_roofs_never_rest_on_railings_or_half_walls() -> void:
	var s := {"r": _rec("wood_railing", Vector3(11, 0, 10), 0), "h": _rec("half_wall", Vector3(12, 0, 11), 90)}
	var r := _v("wood_roof", Vector3(11, 0, 11), 0, _ctx(s))
	assert_false(bool(r["ok"]), "a roof on a railing would float")
	assert_eq(String(r["reason"]), P.MSG_ROOF)
	s["w"] = _rec("wood_wall", Vector3(10, 0, 11), 90)
	assert_true(bool(_v("wood_roof", Vector3(11, 0, 11), 0, _ctx(s))["ok"]), "a full wall holds it")


## The preview cottage (preview_all.gd "upstairs", used for the pending visual check) is a build the rules
## accept, piece by piece in its listed order, at exactly the listed heights.
func test_preview_cottage_is_a_legal_build() -> void:
	var s := {}
	var i := 0
	for e in preload("res://src/building/preview_all.gd").upstairs_layout():
		var sid := String(e[0])
		var pos: Vector3 = e[1]
		var level := 1 if pos.y > 1.5 else 0
		var res := _v(sid, pos, float(e[2]), _ctx(s, {"level": level}))
		assert_true(bool(res["ok"]), "%s at %s: %s" % [sid, str(pos), String(res["reason"])])
		assert_almost(float(res["y"]), pos.y, 0.001, "%s at %s height" % [sid, str(pos)])
		s["p%d" % i] = _rec(sid, Vector3(pos.x, float(res["y"]), pos.z), float(e[2]), int(res["level"]))
		i += 1
	assert_true(P.has_reachable_upstairs(_ctx(s)), "the cottage's stairs reach its upper floor")


## "A House With an Upstairs" (data/optional_goals.gd opt_upstairs, set by building): its objectives read the
## placed stairs and upper floor; built the real way (support, reachable landing) the goal latches once Krystal has
## walked up onto it (COV-005: placing the landing alone is not "Walk up your stairs onto the upper floor").
func test_a_house_with_an_upstairs_goal_completes_from_a_real_build() -> void:
	var area_ctx := func() -> Dictionary:
		return {"structures": GameState.structures, "area_id": "surface", "build_area": Ops.build_area_for("surface"), "height_fn": _flat}
	var place := func(sid: String, pos: Vector3, rot: float) -> String:
		var res := P.validate(sid, pos, rot, area_ctx.call())
		assert_true(bool(res["ok"]), "%s: %s" % [sid, String(res["reason"])])
		GameState.give_item(sid, 1)
		return Ops.place_structure(null, sid, Vector3(pos.x, float(res["y"]), pos.z), rot, int(res["level"]))
	place.call("workbench", Vector3(-9, 0, 9.5), 0)
	GameState.optional_goals.evaluate()
	assert_false(GameState.optional_goals.is_done("opt_upstairs"))
	place.call("wood_wall", Vector3(-5, 0, 0), 0)
	place.call("wood_wall", Vector3(-6, 0, 1), 90)
	place.call("wood_stairs", Vector3(-5, 0, 4), 0)
	GameState.optional_goals.evaluate()
	assert_false(GameState.optional_goals.is_done("opt_upstairs"), "stairs alone are not an upstairs")
	place.call("upper_floor", Vector3(-5, 0, 1), 0)
	assert_true(P.has_reachable_upstairs(area_ctx.call()), "the landing is reachable")
	GameState.optional_goals.evaluate()
	assert_false(GameState.optional_goals.is_done("opt_upstairs"), "built, but she has not walked up yet")
	assert_true(Ops.check_upstairs_walk("surface", Vector3(-5, P.LEVEL_HEIGHT + P.UPPER_TOP, 1)), "she walks up onto the landing")
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_upstairs"), "the goal latches")
	var railings := GameState.count_item("wood_railing")
	GameState.optional_goals.evaluate()
	assert_eq(GameState.count_item("wood_railing"), railings, "its reward is paid once, by the optional log")


# --- Stairs must meet their landing ---------------------------------------------------------------------------------

## On uneven ground walls and stairs can rest on different heights. A landing more than one small step above the
## end of the ramp is refused whichever is built first, and never counts as a reachable upstairs; a small step up
## (0.2 m) or a step down is fine.
func test_stairs_and_landing_must_meet_in_height() -> void:
	var s := {"st": _rec("wood_stairs", Vector3(1, 0, 4), 0), "w": _rec("wood_wall", Vector3(1, 0.5, 0), 0)}
	var high := _v("upper_floor", Vector3(1, 0, 1), 0, _ctx(s))
	assert_almost(float(high["y"]), 3.5, 0.001, "the landing would rest on the higher wall")
	assert_false(bool(high["ok"]), "a landing 0.5 m above the end of the ramp is out of reach")
	assert_eq(String(high["reason"]), P.MSG_STAIR_HEIGHT)
	assert_eq(String(high["blocker"]), "st")
	# The other way round: the landing is there first, the stairs come after.
	var s2 := {"w": _rec("wood_wall", Vector3(1, 0.5, 0), 0), "land": _rec("upper_floor", Vector3(1, 3.5, 1), 0, 1)}
	var st := _v("wood_stairs", Vector3(1, 0, 4), 0, _ctx(s2))
	assert_false(bool(st["ok"]))
	assert_eq(String(st["reason"]), P.MSG_STAIR_HEIGHT)
	assert_eq(String(st["blocker"]), "land")
	s2["st"] = _rec("wood_stairs", Vector3(1, 0, 4), 0)
	assert_false(P.has_reachable_upstairs(_ctx(s2)), "a (grandfathered) mismatch is not a reachable upstairs")
	for ly in [3.2, 2.7]:
		var s3 := {"w": _rec("wood_wall", Vector3(1, ly - 3.0, 0), 0), "land": _rec("upper_floor", Vector3(1, ly, 1), 0, 1)}
		var ok := _v("wood_stairs", Vector3(1, 0, 4), 0, _ctx(s3))
		assert_true(bool(ok["ok"]), "landing at %.1f: %s" % [ly, String(ok["reason"])])
		s3["st"] = _rec("wood_stairs", Vector3(1, 0, 4), 0)
		assert_true(P.has_reachable_upstairs(_ctx(s3)), "landing at %.1f is reachable" % ly)
	# Flat ground: always flush (the ramp ends exactly at the landing's walkable top).
	assert_true(P.stair_meets_landing(0.0, P.LEVEL_HEIGHT))
	assert_almost(P.LEVEL_HEIGHT + P.UPPER_TOP, P.STAIR_RISE, 0.0001)


# --- "A House With an Upstairs": the reachability flag ----------------------------------------------------------------

func _place_real(sid: String, pos: Vector3, rot: float, level: int = 0) -> String:
	var ctx := {"structures": GameState.structures, "area_id": Ops.area_id_of(null), "build_area": Ops.build_area_for("surface"),
		"height_fn": _flat, "level": level}
	var res := P.validate(sid, pos, rot, ctx)
	assert_true(bool(res["ok"]), "%s: %s" % [sid, String(res["reason"])])
	GameState.give_item(sid, 1)
	return Ops.place_structure(null, sid, Vector3(pos.x, float(res["y"]), pos.z), rot, int(res["level"]))


## COV-005: set only when Krystal stands on an upper floor tile while stairs lead onto a reachable upper floor: not
## by stairs alone, not by the placement that completes the house, not by a landing walled off at the top of the
## stairs (the way up opens when that wall comes down and she walks up), never cleared.
func test_upstairs_flag_needs_krystal_on_a_reachable_upper_floor() -> void:
	var up := Vector3(-5, P.LEVEL_HEIGHT + P.UPPER_TOP, 1)      # her feet on the landing tile's walkable top
	assert_false(bool(GameState.get_flag(Ops.FLAG_UPSTAIRS)))
	_place_real("wood_wall", Vector3(-5, 0, 0), 0)
	_place_real("wood_wall", Vector3(-6, 0, 1), 90)
	_place_real("wood_stairs", Vector3(-5, 0, 4), 0)
	assert_false(Ops.check_upstairs_walk(Ops.area_id_of(null), Vector3(-5, 0, 6.5)), "stairs alone are not an upstairs")
	var land := _place_real("upper_floor", Vector3(-5, 0, 1), 0)
	assert_ne(land, "")
	assert_false(bool(GameState.get_flag(Ops.FLAG_UPSTAIRS)), "placing the landing is not walking up")
	assert_eq(Ops.upper_floor_under(Ops.area_id_of(null), up), land, "her feet on the landing")
	assert_eq(Ops.upper_floor_under(Ops.area_id_of(null), Vector3(-5, 0, 1)), "", "the ground floor under it is not upstairs")
	assert_eq(Ops.upper_floor_under(Ops.area_id_of(null), Vector3(-5, 2.6, 2.5)), "", "nor is the top of the ramp")
	assert_eq(Ops.upper_floor_under("hallowmere_reach", up), "", "nor a tile of another area")
	assert_true(Ops.check_upstairs_walk(Ops.area_id_of(null), up), "she walks up onto the landing")
	assert_true(bool(GameState.get_flag(Ops.FLAG_UPSTAIRS)))
	# A top wall taken down opens the way up (records made directly: validation would refuse that wall).
	fresh_state()
	var aid := Ops.area_id_of(null)
	GameState.add_structure("wood_wall", Vector3(-5, 0, 0), 0, aid)
	var tile := GameState.add_structure("upper_floor", Vector3(-5, 3, 1), 0, aid)
	GameState.structures[tile]["data"]["level"] = 1
	GameState.add_structure("wood_stairs", Vector3(-5, 0, 4), 0, aid)
	var top := GameState.add_structure("wood_wall", Vector3(-5, 3, 2), 0, aid)
	GameState.structures[top]["data"]["level"] = 1
	assert_false(Ops.check_upstairs_walk(aid, up), "a wall across the top of the stairs: no way up to that floor")
	assert_true(bool(Ops.dismantle(null, top)["ok"]))
	assert_false(bool(GameState.get_flag(Ops.FLAG_UPSTAIRS)), "the way up is open, but she has not walked up yet")
	assert_true(Ops.check_upstairs_walk(aid, up), "the way up is open and she walks up")
	assert_true(bool(Ops.dismantle(null, tile)["ok"]), "the landing still comes apart")
	assert_true(bool(GameState.get_flag(Ops.FLAG_UPSTAIRS)), "the flag stays (the goal latches)")


## A Haven area with the building system attached, Krystal (a stand-in node, feet at its origin) in it as the current
## area's player. Returns [area, krystal]; _end_haven() puts Game back.
func _haven() -> Array:
	var area: Node3D = preload("res://src/world/area_base.gd").new()
	area.area_id = "surface"
	add_child(area)
	preload("res://src/building/building_system.gd").attach(area)
	var k := Node3D.new()
	add_child(k)
	_game_saved = {"area": Game.area, "player": Game.player, "area_id": Game.area_id}
	Game.area = area
	Game.player = k
	Game.area_id = "surface"
	return [area, k]


func _end_haven(h: Array) -> void:
	Game.area = _game_saved.get("area")
	Game.player = _game_saved.get("player")
	Game.area_id = String(_game_saved.get("area_id", ""))
	for n in h:
		if is_instance_valid(n):
			(n as Node).free()


## The Haven's upstairs watcher (BuildingSystem.attach) polled with Krystal's feet at `feet`.
func _poll_watch(area: Node, k: Node3D, feet: Vector3) -> void:
	k.position = feet
	var w: Node = area.get_node_or_null("UpstairsWatch")
	if w != null and not w.is_queued_for_deletion():
		w._process(0.6)


## COV-005 (QA bot, lamp_orders_ch1_optional COV2-002): "Walk up your stairs onto the upper floor" completed on the
## frame the landing tile was placed, 12 s before Krystal walked up. Now only standing up there completes it: the
## Haven's watcher polls her position; the foot of the stairs, the ramp and the ground under the landing never count.
func test_the_upstairs_goal_waits_until_krystal_walks_up() -> void:
	var h := _haven()
	var area: Node3D = h[0]
	var k: Node3D = h[1]
	GameState.add_structure("workbench", Vector3(-9, 0, 9.5), 0)   # the goal is shown
	_place_real("wood_wall", Vector3(-5, 0, 0), 0)
	_place_real("wood_wall", Vector3(-6, 0, 1), 90)
	_place_real("wood_stairs", Vector3(-5, 0, 4), 0)
	_place_real("upper_floor", Vector3(-5, 0, 1), 0)
	GameState.optional_goals.evaluate()
	assert_false(bool(GameState.get_flag("c1x_upstairs_reachable")), "placing the landing is not walking up")
	assert_false(GameState.optional_goals.is_done("opt_upstairs"), "the goal waits for her")
	assert_not_null(area.get_node_or_null("UpstairsWatch"), "the Haven watches for her walking up")
	for feet in [Vector3(-5, 0, 6.5), Vector3(-5, 1.5, 4.5), Vector3(-5, 2.6, 2.5), Vector3(-5, 0, 1)]:
		_poll_watch(area, k, feet)
		assert_false(bool(GameState.get_flag("c1x_upstairs_reachable")), "not upstairs yet at %s" % str(feet))
	_poll_watch(area, k, Vector3(-5, 3.12, 1))
	assert_true(bool(GameState.get_flag("c1x_upstairs_reachable")), "she stands on the upper floor")
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_upstairs"), "the goal completes now")
	var w: Node = area.get_node_or_null("UpstairsWatch")
	assert_true(w == null or w.is_queued_for_deletion(), "a latched goal needs no watcher")
	_end_haven(h)


## A saved house from an older save (stairs onto a reachable landing, no flag): loading the Haven no longer
## completes the goal by itself - the first walk up does. A save whose goal is done gets no watcher at all.
func test_a_saved_house_completes_the_goal_when_she_walks_up() -> void:
	GameState.add_structure("workbench", Vector3(-9, 0, 9.5), 0)
	GameState.add_structure("wood_wall", Vector3(-5, 0, 0), 0)
	var tile := GameState.add_structure("upper_floor", Vector3(-5, 3, 1), 0)
	GameState.structures[tile]["data"]["level"] = 1
	GameState.add_structure("wood_stairs", Vector3(-5, 0, 4), 0)
	assert_false(bool(GameState.get_flag("c1x_upstairs_reachable")))
	var h := _haven()
	var area: Node3D = h[0]
	var k: Node3D = h[1]
	GameState.optional_goals.evaluate()
	assert_false(bool(GameState.get_flag("c1x_upstairs_reachable")), "loading the Haven is not walking up")
	assert_false(GameState.optional_goals.is_done("opt_upstairs"))
	_poll_watch(area, k, Vector3(-5, 0.05, 7))
	assert_false(bool(GameState.get_flag("c1x_upstairs_reachable")), "at the foot of the stairs")
	_poll_watch(area, k, Vector3(-5.5, 3.12, 0.5))
	assert_true(bool(GameState.get_flag("c1x_upstairs_reachable")), "up on the landing")
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_upstairs"))
	_end_haven(h)
	var h2 := _haven()
	assert_null(h2[0].get_node_or_null("UpstairsWatch"), "the goal is done: no watcher")
	_end_haven(h2)
