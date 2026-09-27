extends "res://tests/test_case.gd"
## The Below: spawns on solid ground with headroom, zones & safe zones, rooms cover the critical path,
## director anchors, flicker lights, doorway dimensions.

const Layout := preload("res://src/world/below/below_layout.gd")
const WORLD := "res://src/world/below/below_world.gd"
const REQUIRED_SPAWNS := ["mine_entry", "cp_landing", "cp_office", "cp_shrine", "cp_arena", "lift_bottom", "lift_chamber"]
const MASK := 1 | 32

var area: Node3D = null


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(3)
	return a


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return area.get_world_3d().direct_space_state.intersect_ray(q)


func test_every_spawn_is_on_solid_ground_with_headroom() -> void:
	area = await _make_area()
	var space := area.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	for id in REQUIRED_SPAWNS:
		assert_true(area.spawns.has(id), "spawn %s registered" % id)
		if not area.spawns.has(id):
			continue
		var xf: Transform3D = area.get_spawn(id)
		var p := xf.origin
		var hit := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.5)
		assert_false(hit.is_empty(), "%s has ground below" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.3, "%s ground height" % id)
		assert_true(_ray(p + Vector3.UP * 0.2, p + Vector3.UP * 2.4).is_empty(), "%s has 2.4 m headroom" % id)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cap
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.05)
		q.collision_mask = MASK
		assert_true(space.intersect_shape(q, 4).is_empty(), "%s capsule is free" % id)
		assert_ne(Layout.room_at(p), "", "%s lies inside a room" % id)


func test_zones_and_safe_zones() -> void:
	area = await _make_area()
	assert_eq(area.get_zone_at(area.get_spawn("mine_entry").origin), "mine", "landing is mine")
	assert_eq(area.get_zone_at(Vector3(20, -6, -59.3)), "ruins", "hall is ruins")
	assert_eq(area.get_zone_at(Vector3(44.2, -6, -85)), "ruins", "shrine is ruins")
	assert_eq(area.get_zone_at(Vector3(90, -10, -85.75)), "silk", "webbed passage is silk")
	assert_eq(area.get_zone_at(Vector3(105, -10, -70)), "silk", "nursery is silk")
	assert_eq(area.get_zone_at(Layout.ARENA_CENTER + Vector3(3, 0, 3)), "boss", "chamber is boss")
	# The gallery sits right above nothing but the Hall lies below the office level: y must matter.
	assert_eq(area.get_zone_at(Vector3(16, 0, -43.75)), "mine", "office is mine")
	# Unknown points fall back to the nearest room rather than ""
	assert_ne(area.get_zone_at(Vector3(0, 0, 30)), "", "fallback zone")
	var zone_ids := []
	for z in area.zones:
		zone_ids.append(z["id"])
	for z in ["mine", "ruins", "silk", "boss"]:
		assert_true(zone_ids.has(z), "zone %s registered with add_zone" % z)
	assert_true(area.is_safe_zone(area.get_spawn("mine_entry").origin), "landing is safe")
	assert_true(area.is_safe_zone(area.get_spawn("lift_bottom").origin), "lift arrival is safe")
	assert_false(area.is_safe_zone(Vector3(0, 0, -43)), "gallery is not safe")
	assert_false(area.is_safe_zone(Vector3(0, -12, -43)), "safe zones respect height")
	var office: Vector3 = Layout.CHECKPOINTS["office"]["pos"]
	assert_false(area.is_safe_zone(office), "unlit checkpoint is not safe")
	var cp: Node = area.checkpoints["office"]
	cp.save_enabled = false
	cp.interact(null)
	assert_true(area.is_safe_zone(office), "lit checkpoint becomes a safe zone")
	assert_true(area.is_safe_zone(area.get_spawn("cp_office").origin), "checkpoint spawn is inside its safe zone")


func test_critical_path_points_are_inside_rooms() -> void:
	for p in Layout.CRITICAL_PATH:
		assert_ne(Layout.room_at(p), "", "path point %s inside a room" % str(p))
	for path in Layout.SIDE_PATHS:
		for p in path:
			assert_ne(Layout.room_at(p), "", "side point %s inside a room" % str(p))
	for s in Layout.SPACES:
		var found := false
		for id in Layout.ROOMS:
			if Layout.space_of(id) == s:
				found = true
		assert_true(found, "space %s has at least one room" % s)


func test_director_anchors_cover_every_space() -> void:
	area = await _make_area()
	var per_space := {}
	var kinds := ["sound", "doorway", "ceiling", "floor", "spawn"]
	var ceiling_silk := 0
	for a in area.get_tree().get_nodes_in_group("director_anchor"):
		if not area.is_ancestor_of(a):
			continue
		assert_true(a is Marker3D, "anchor is a Marker3D")
		var room := String(a.get_meta("room", ""))
		var zone := String(a.get_meta("zone", ""))
		var kind := String(a.get_meta("kind", ""))
		assert_true(["mine", "ruins", "silk"].has(zone), "anchor zone valid: " + zone)
		assert_true(kinds.has(kind), "anchor kind valid: " + kind)
		per_space[room] = int(per_space.get(room, 0)) + 1
		if zone == "silk" and kind == "ceiling":
			ceiling_silk += 1
	for s in Layout.SPACES:
		assert_true(int(per_space.get(s, 0)) >= 3, "space %s has >= 3 anchors (%d)" % [s, int(per_space.get(s, 0))])
	assert_true(ceiling_silk >= 3, "ceiling anchors in the Silk Hollows")


func test_floor_anchors_are_standable() -> void:
	area = await _make_area()
	var space := area.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.4
	for a in Layout.ANCHORS:
		var p: Vector3 = a[3]
		assert_ne(Layout.room_at(p + Vector3.UP * 0.1), "", "anchor %s %s inside a room" % [a[0], str(p)])
		if String(a[2]) == "spawn" or String(a[2]) == "floor":
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.0)
			q.collision_mask = MASK
			assert_true(space.intersect_shape(q, 4).is_empty(), "%s anchor %s is free" % [a[2], str(p)])
			assert_false(_ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.8).is_empty(), "%s anchor %s has floor" % [a[2], str(p)])


func test_flicker_lights_and_checkpoints() -> void:
	area = await _make_area()
	var flick := 0
	for n in area.get_tree().get_nodes_in_group("flicker_light"):
		if area.is_ancestor_of(n):
			flick += 1
			assert_true(n.has_method("flicker"), "flicker_light has flicker()")
	assert_true(flick >= 15, "plenty of flicker lights (%d)" % flick)
	var cps := 0
	for n in area.get_tree().get_nodes_in_group("checkpoint"):
		if area.is_ancestor_of(n):
			cps += 1
	assert_eq(cps, 4, "four checkpoint lanterns")
	# flicker then recover
	var lamp: Node = null
	for n in area.get_tree().get_nodes_in_group("flicker_light"):
		if area.is_ancestor_of(n):
			lamp = n
			break
	lamp.flicker(0.2)
	assert_true(lamp.is_flickering(), "flickering")
	await wait_seconds(0.35)
	assert_false(lamp.is_flickering(), "recovered")


func test_doorways_are_wide_and_tall_enough() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var od: Dictionary = r.get("open", {})
		for side in od:
			var v = od[side]
			if v is String:
				continue
			for o in v:
				var w: float = float(o[1]) - float(o[0])
				assert_true(w >= 1.6, "%s %s opening width %.2f" % [id, side, w])
				assert_true(float(o[2]) >= 2.4, "%s %s opening height %.2f" % [id, side, float(o[2])])
		assert_true(float(r["h"]) >= 2.4, "%s ceiling height" % id)
		assert_true(float(r["x1"]) - float(r["x0"]) >= 1.6 and float(r["z1"]) - float(r["z0"]) >= 1.6, "%s room is wide enough" % id)


func test_stalker_route_is_one_crawlable_chain() -> void:
	# The stalker only crawls between consecutive route points that are < 14 m apart with no world
	# geometry in between; a broken chain would leave parts of the Silk Hollows without passes.
	area = await _make_area()
	var route: Array = Layout.STALKER_ROUTE
	assert_true(route.size() >= 4, "a real route")
	for i in route.size():
		var p: Vector3 = route[i]
		assert_eq(Layout.zone_of_room(Layout.room_at(p)), "silk", "route point %d is in the Silk Hollows" % i)
		assert_false(_ray(p, p + Vector3.UP * 1.0).is_empty(), "route point %d hugs the ceiling" % i)
		assert_false(_ray(p, p + Vector3.DOWN * 9.0).is_empty(), "route point %d has a floor below" % i)
		if i + 1 < route.size():
			var q: Vector3 = route[i + 1]
			assert_true(p.distance_to(q) < 14.0, "hop %d is short enough (%.1f m)" % [i, p.distance_to(q)])
			assert_true(_ray(p, q).is_empty(), "no rock between route points %d and %d" % [i, i + 1])
	for a in Layout.STALKER_AMBUSH:
		var ap: Vector3 = a
		assert_eq(Layout.zone_of_room(Layout.room_at(ap + Vector3.UP * 0.5)), "silk", "ambush point in the Silk Hollows")
		assert_false(_ray(ap + Vector3.UP * 0.5, ap + Vector3.DOWN * 0.8).is_empty(), "ambush point on the floor")
	# The webbed passage itself (where the countermeasure is taught) is covered by the route.
	var covered := false
	for p in route:
		if Layout.room_at(p) == "webbed":
			covered = true
	assert_true(covered, "the Webbed Passage has route points")


func test_build_is_fast_enough() -> void:
	var t0 := Time.get_ticks_msec()
	area = await _make_area()
	var ms := Time.get_ticks_msec() - t0
	assert_true(ms < 2500, "area builds quickly (%d ms)" % ms)
	# Scatter is batched: far fewer nodes than rocks
	var mm := 0
	for n in area.find_children("*", "MultiMeshInstance3D", true, false):
		mm += (n as MultiMeshInstance3D).multimesh.instance_count
	assert_true(mm > 2000, "batched instances (%d)" % mm)
