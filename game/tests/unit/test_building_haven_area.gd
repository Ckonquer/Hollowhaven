extends "res://tests/test_case.gd"
## The bigger Haven (spec 7.1, MP §3): the extra build regions of data/world_layout.gd are checked against the
## REAL terrain and vegetation plan (away from the stream, the paths leaving the Haven, the Old Oak radius, the
## Ward Stone / campfire / start-path circles, the Haven sign and every tree, rock, ore, bush and log; gentle
## ground; one connected area), legacy placements keep exactly the legacy answers, the Haven safe zone covers
## the new boundary plus a 4 m buffer, and the Hallowmere Reach outpost is small and has no bed.

const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")
const Layout := preload("res://data/world_layout.gd")
const HL := preload("res://data/hallowmere_layout.gd")
const SL := preload("res://src/world/surface/surface_layout.gd")
const Terrain := preload("res://src/world/surface/terrain.gd")
const Vegetation := preload("res://src/world/surface/vegetation.gd")
const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")

const STREAM_CLEARANCE := 5.0      # from the stream centreline (the water is 2 m either side of it)
const OBSTACLE_CLEARANCE := 2.0    # from a tree / rock / bush / log planned by Vegetation.plan()
const SAFE_BUFFER := 4.0

static var _terrain: RefCounted = null
static var _plan: Dictionary = {}


func before_each() -> void:
	fresh_state()


func _world() -> void:
	if _terrain == null:
		_terrain = Terrain.new()
		_terrain.generate()
		_plan = Vegetation.plan(_terrain)


func _extra() -> Array:
	return Layout.BUILD_AREA["extra"]


## Sample points of a circle that lie outside the legacy build circle (what the region adds).
func _new_points(r: Dictionary) -> Array:
	var out: Array = []
	var c: Vector2 = r["center"]
	var rad := float(r["radius"])
	var n := int(ceilf(rad / 0.5))
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var p := c + Vector2(i, j) * 0.5
			if p.distance_to(c) <= rad and p.length() > float(Layout.BUILD_AREA["radius"]):
				out.append(p)
	return out


func _obstacles() -> Array:
	var out: Array = []
	for k in ["trees", "rocks", "ores", "bushes"]:
		for e in _plan[k]:
			out.append([String(e["id"]), Vector2(e["pos"].x, e["pos"].z), 2.4 if k == "trees" else (2.2 if k != "bushes" else 1.5)])
	for e in _plan["decor_bushes"]:
		var xf: Transform3D = e[1]
		out.append(["decor bush", Vector2(xf.origin.x, xf.origin.z), 1.3])
	for e in _plan["logs"]:
		var xf2: Transform3D = e[1]
		out.append(["log", Vector2(xf2.origin.x, xf2.origin.z), 2.4])
	return out


func test_extra_regions_avoid_the_stream_paths_and_landmarks() -> void:
	_world()
	assert_true(_extra().size() >= 6, "the Haven really grows")
	var oak: Dictionary = Layout.LANDMARKS["old_oak"]
	for r in _extra():
		var c: Vector2 = r["center"]
		var rad := float(r["radius"])
		var tag := "region %s r%.2f" % [str(c), rad]
		assert_true(c.distance_to(oak["pos"]) > rad + float(oak["radius"]), tag + " stays out of the Old Oak radius")
		for b in Layout.BUILD_AREA["blocked"]:
			assert_true(c.distance_to(b["center"]) > rad + float(b["radius"]), tag + " stays off the keep-clear circle at " + str(b["center"]))
		assert_true(c.distance_to(SL.SIGN) > rad + 1.5, tag + " leaves the Haven sign alone")
		for p in _new_points(r):
			assert_true(_terrain.stream_distance(p.x, p.y) >= STREAM_CLEARANCE, "%s: %s is too close to the stream" % [tag, str(p)])
			assert_true(_terrain.path_at(p.x, p.y) <= 0.25, "%s: %s is on a path leaving the Haven" % [tag, str(p)])
			var h0: float = _terrain.height_at(p.x, p.y)
			assert_true(absf(_terrain.height_at(p.x + 1.0, p.y) - h0) <= 0.21 and absf(_terrain.height_at(p.x, p.y + 1.0) - h0) <= 0.21, "%s: %s is too steep" % [tag, str(p)])
			assert_true(Vector2(p.x, p.y).length() < 34.0, tag + " stays next to the clearing")


func test_extra_regions_keep_off_trees_rocks_and_bushes() -> void:
	_world()
	var obs := _obstacles()
	for r in _extra():
		for p in _new_points(r):
			for o in obs:
				if (p as Vector2).distance_to(o[1]) < float(o[2]) - 0.3:
					fail("region %s: %s is on %s" % [str(r["center"]), str(p), String(o[0])])
					return


func test_extra_regions_form_one_connected_home() -> void:
	var regions: Array = [{"center": Layout.BUILD_AREA["center"], "radius": float(Layout.BUILD_AREA["radius"])}]
	regions.append_array(_extra())
	var linked := {0: true}
	var changed := true
	while changed:
		changed = false
		for i in regions.size():
			if linked.has(i):
				continue
			for j in linked.keys():
				var a: Dictionary = regions[i]
				var b: Dictionary = regions[j]
				if (a["center"] as Vector2).distance_to(b["center"]) < float(a["radius"]) + float(b["radius"]) - 0.5:
					linked[i] = true
					changed = true
					break
	assert_eq(linked.size(), regions.size(), "every region overlaps the clearing or another region")


func test_expansion_adds_real_building_room() -> void:
	var ba := Ops.build_area_for("surface")
	var legacy := {"center": ba["center"], "radius": ba["radius"], "blocked": ba["blocked"]}
	var added := 0
	for x in range(-40, 40, 2):
		for z in range(-40, 40, 2):
			var rect := Rect2(x, z, 2, 2)
			if P.rect_in_build_area(rect, ba) and not P.rect_in_build_area(rect, legacy):
				added += 1
	assert_true(added >= 40, "at least 40 new 2 x 2 m floor tiles (got %d)" % added)


func test_legacy_placements_keep_the_legacy_answers() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var ba := Ops.build_area_for("surface")
	var legacy := {"center": ba["center"], "radius": ba["radius"], "blocked": ba["blocked"]}
	var ctx_new := {"structures": {}, "area_id": "surface", "build_area": ba, "height_fn": flat}
	var ctx_old := {"structures": {}, "area_id": "surface", "build_area": legacy, "height_fn": flat}
	var checked := 0
	for sid in ["storage_chest", "wood_floor", "wood_wall", "workbench", "rug"]:
		for x in range(-17, 17):
			for z in range(-17, 17):
				var pos := Vector3(float(x) + 0.5, 0, float(z) + 0.5)
				var a := P.validate(sid, pos, 0, ctx_old)
				if not bool(a["ok"]) and String(a["reason"]) == P.MSG_OUTSIDE:
					continue
				var b := P.validate(sid, pos, 0, ctx_new)
				checked += 1
				if a != b:
					fail("%s at %s: legacy %s, now %s" % [sid, str(pos), str(a), str(b)])
					return
	assert_true(checked > 500, "compared %d legacy placements" % checked)


func test_new_regions_accept_building_and_the_stream_side_does_not() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var ctx := {"structures": {}, "area_id": "surface", "build_area": Ops.build_area_for("surface"), "height_fn": flat}
	var sw := P.validate("wood_floor", Vector3(-9, 0, 21), 0, ctx)
	assert_true(bool(sw["ok"]), "south-west lawn: " + String(sw["reason"]))
	assert_true(bool(P.validate("storage_chest", Vector3(-17.5, 0, -4.5), 0, ctx)["ok"]), "west lawn")
	assert_eq(String(P.validate("storage_chest", Vector3(18.5, 0, -2.5), 0, ctx)["reason"]), P.MSG_OUTSIDE, "not on the stream bank")
	assert_eq(String(P.validate("storage_chest", Vector3(-30.5, 0, -18.5), 0, ctx)["reason"]), P.MSG_OUTSIDE, "not at the Old Oak")
	assert_true(P.in_build_area(Vector3(-9, 0, 21), Ops.build_area_for("surface")), "build mode knows she's at the Haven")
	var raw: Array = Layout.BUILD_AREA["extra"]
	assert_false((raw[0] as Dictionary).has("name"), "the shared layout data is never modified")


func test_haven_safe_zone_covers_the_new_boundary_plus_a_buffer() -> void:
	var w: Node3D = SurfaceWorld.new()        # not added to the tree: no terrain build, zones added by hand
	var hv: Dictionary = Layout.LANDMARKS["haven"]
	w.add_zone("haven", Vector3(hv["pos"].x, 0, hv["pos"].y), float(hv["radius"]), true)
	var regions: Array = [{"center": Layout.BUILD_AREA["center"], "radius": float(Layout.BUILD_AREA["radius"])}]
	regions.append_array(_extra())
	for r in regions:
		var c: Vector2 = r["center"]
		for i in 24:
			var a := TAU * float(i) / 24.0
			for d in [0.0, float(r["radius"]) * 0.5, float(r["radius"]), float(r["radius"]) + SAFE_BUFFER - 0.05]:
				var p := c + Vector2(cos(a), sin(a)) * float(d)
				assert_true(w.is_safe_zone(Vector3(p.x, 0, p.y)), "safe at %s (region %s + buffer)" % [str(p), str(c)])
	# Outside the boundary + buffer it is ordinary woods again: player lights never make a safe field.
	for p in [Vector2(60, 60), Vector2(26, 0), Vector2(0, -40), Vector2(-34, -20)]:
		var covered := false
		for r in regions:
			if (p as Vector2).distance_to(r["center"]) <= float(r["radius"]) + SAFE_BUFFER:
				covered = true
		assert_false(covered, "test point %s is outside" % str(p))
		assert_false(w.is_safe_zone(Vector3(p.x, 0, p.y)), "not safe at %s" % str(p))
	w.free()


func test_reach_outpost_is_small_and_never_a_second_home() -> void:
	var ba := Ops.build_area_for(HL.AREA_ID)
	assert_false(ba.is_empty(), "the Reach has an outpost build area")
	assert_eq(ba["center"], HL.OUTPOST_BUILD_AREA["center"])
	assert_almost(float(ba["radius"]), float(HL.OUTPOST_BUILD_AREA["radius"]), 0.001)
	var flat := func(_x: float, _z: float) -> float: return 5.0
	var ctx := {"structures": {}, "area_id": HL.AREA_ID, "build_area": ba, "height_fn": flat}
	var c: Vector2 = HL.OUTPOST_BUILD_AREA["center"]
	var ok := P.validate("storage_chest", Vector3(c.x + 0.5, 0, c.y + 0.5), 0, ctx)
	assert_true(bool(ok["ok"]), String(ok["reason"]))
	assert_almost(float(ok["y"]), 5.0, 0.001, "sits on the Reach ground")
	var bed := P.validate("bed", Vector3(c.x + 0.5, 0, c.y + 1.0), 0, ctx)
	assert_false(bool(bed["ok"]))
	assert_eq(String(bed["reason"]), Ops.MSG_OUTPOST_BED)
	# A companion's home spot is a Haven position: nooks stay home too (a Reach nook would move the pet's
	# Haven home to the Reach's coordinates).
	for nook in ["companion_bed", "companion_perch"]:
		var r := P.validate(nook, Vector3(c.x + 0.5, 0, c.y + 0.5), 0, ctx)
		assert_false(bool(r["ok"]), nook + " stays at the Haven")
		assert_eq(String(r["reason"]), Ops.MSG_OUTPOST_NOOK)
	assert_true(bool(P.validate("companion_bed", Vector3(-9.5, 0, 9.5), 0, {"structures": {}, "area_id": "surface",
		"build_area": Ops.build_area_for("surface"), "height_fn": flat})["ok"]), "nooks are fine at the Haven")
	assert_eq(String(P.validate("storage_chest", Vector3(c.x + 12.5, 0, c.y + 0.5), 0, ctx)["reason"]), Ops.MSG_OUTPOST_OUTSIDE, "says where to build in the Reach")
	assert_true(Ops.build_area_for("below").is_empty(), "no building underground")
	assert_true(Ops.build_area_for("moonveil_manor").is_empty(), "or in the manor")
