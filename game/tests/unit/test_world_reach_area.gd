extends "res://tests/test_case.gd"
## Hallowmere Reach as a built area (headless): build time, spawns on clear dry ground, height == collision,
## zones and safe zones per the layout, the boundary, no fall-through, walkable connectivity along every road
## (physics probes) plus real capsule walks over the crossings, through the Conservatory doors and down the
## Bellhouse stair, reachable interactables, Continue position validation, exits and the waygate home.
## The region is built once and shared by the suite.

const ReachWorld := preload("res://src/world/areas_ch2/hallowmere_reach_world.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const WorldLayout := preload("res://data/world_layout.gd")
const Vegetation := preload("res://src/world/reach/reach_vegetation.gd")
const Conservatory := preload("res://src/world/reach/conservatory.gd")
const Logic := preload("res://src/player/player_logic.gd")

const SAFE_SPAWNS := ["waygate_arrival", "reach_respawn", "commons_arch", "orchard_arch", "quarry_arch", "manor_arch", "conservatory"]
const LEGAL_TARGETS := {"surface": ["waygate"], "moonveil_manor": ["manor_entry"], "hushed_works": ["service_landing", "refuge"]}

static var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = ReachWorld.new()
		add_child(_w)
		await wait_physics(3)
	return _w


func _space(w: Node3D) -> PhysicsDirectSpaceState3D:
	return w.get_world_3d().direct_space_state


func _ray(w: Node3D, from: Vector3, to: Vector3, mask: int = 1 | 32) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = mask
	return _space(w).intersect_ray(q)


func _capsule_hits(w: Node3D, feet: Vector3, radius: float = 0.3, height: float = 1.6) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0, height * 0.5 + 0.12, 0))
	sq.collision_mask = 1 | 32
	return _space(w).intersect_shape(sq, 4)


func test_build_time_budget() -> void:
	var w: Node3D = await _world()
	var total := float(w.build_times.get("total", 99999.0))
	var base := float(w.build_times.get("base_total", 99999.0))
	print("    reach build: %.0f ms (region %.0f ms, districts: load %.0f ms, build %.0f ms) %s" % [total, base,
		float(w.build_times.get("districts_load", 0.0)), float(w.build_times.get("districts_build", 0.0)), str(w.build_times)])
	assert_true(base < 1000.0, "the region itself builds well within the load fade (%.0f ms)" % base)
	assert_true(total < 4000.0, "the whole Reach incl. districts builds in reasonable time (%.0f ms)" % total)
	assert_eq(String(w.area_id), "hallowmere_reach")
	assert_false(bool(w.placeholder), "the real region, not the stand-in")


func test_spawns_on_ground_clear_dry_and_at_their_layout_points() -> void:
	var w: Node3D = await _world()
	for id in Reach.SPAWNS:
		assert_true((w.spawns as Dictionary).has(id), "spawn %s registered" % id)
		if not (w.spawns as Dictionary).has(id):
			continue
		var p: Vector3 = (w.spawns[id] as Transform3D).origin
		var want: Vector2 = Reach.SPAWNS[id]["pos"]
		assert_almost(Vector2(p.x, p.z).distance_to(want), 0.0, 0.01, "spawn %s at its layout point" % id)
		var hit := _ray(w, p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0)
		assert_false(hit.is_empty(), "ground under spawn %s" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.35, "spawn %s sits on the ground" % id)
		var hits := _capsule_hits(w, p, 0.35, 1.6)
		assert_eq(hits.size(), 0, "spawn %s is clear %s" % [id, str(hits.map(func(o: Dictionary) -> String: return String(o["collider"].name)))])
		assert_true(w.is_inside_bounds(p, 3.0), "spawn %s inside the walls" % id)
		assert_false(w.terrain.is_water(p.x, p.z), "spawn %s is dry" % id)
		assert_true(w.validate_position(p) is Vector3, "spawn %s is a valid saved position" % id)
	for id in SAFE_SPAWNS:
		assert_true(w.is_safe_zone((w.spawns[id] as Transform3D).origin), "spawn %s is safe" % id)
	var arrival: Transform3D = w.spawns["waygate_arrival"]
	assert_true((-arrival.basis.z).dot(Vector3.FORWARD) > 0.99, "the arrival faces north, into the festival")


func test_height_matches_collision() -> void:
	var w: Node3D = await _world()
	var pts: Array = [Vector2(0, 60), Vector2(0, 98), Vector2(0, 6), Vector2(-60, 50), Vector2(62, 38), Vector2(10, -50),
		Vector2(72, -71), Vector2(-34, 30), Vector2(-100, 0), Vector2(110, -60), Vector2(40, 80), Vector2(-120, -95)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 40:
		pts.append(Vector2(rng.randf_range(-130.0, 130.0), rng.randf_range(-100.0, 100.0)))
	var checked := 0
	var worst := 0.0
	for p in pts:
		var hit := _ray(w, Vector3(p.x, 90.0, p.y), Vector3(p.x, -60.0, p.y), 1)
		if hit.is_empty():
			fail("no ground under %s" % p)
			continue
		if not String(hit["collider"].name).begins_with("TerrainBody"):
			continue
		var d := absf(float(hit["position"].y) - float(w.height_at(p.x, p.y)))
		worst = maxf(worst, d)
		assert_true(d < 0.12, "height_at vs collision at %s (%.3f)" % [p, d])
		checked += 1
	assert_true(checked >= 30, "enough terrain samples (%d)" % checked)
	print("    height_at worst deviation %.3f m over %d samples" % [worst, checked])


func test_zones_and_safe_zones_follow_the_layout() -> void:
	var w: Node3D = await _world()
	for id in Reach.LANDMARKS:
		var l: Dictionary = Reach.LANDMARKS[id]
		var p: Vector2 = l["pos"]
		assert_eq(String(w.get_zone_at(Vector3(p.x, 0, p.y))), String(id), "zone at landmark %s" % id)
		assert_eq(bool(w.is_safe_zone(Vector3(p.x, 0, p.y))), bool(l["safe"]), "landmark %s safety" % id)
	for id in Reach.ARCHES:
		var ap: Vector2 = Reach.ARCHES[id]["pos"]
		assert_true(w.is_safe_zone(Vector3(ap.x, 0, ap.y) + Vector3(Reach.ARCH_SAFE_RADIUS - 0.5, 0, 0)), "arch %s has a safe circle" % id)
	var arr: Vector2 = Reach.POINTS["waygate_arrival"]
	assert_true(w.is_safe_zone(Vector3(arr.x, 0, arr.y)), "the arrival is safe")
	for p in [Vector3(-82, 0, 36), Vector3(86, 0, 18), Vector3(18, 0, -74), Vector3(-86, 0, -60), Vector3(72, 0, -74), Vector3(-44, 0, -8), Vector3(40, 0, 80)]:
		assert_false(w.is_safe_zone(p), "%s is not safe" % str(p))
	for z in w.zones:
		assert_true(String(z["id"]).begins_with("hr_"), "zone ids are namespaced (%s)" % z["id"])


func test_boundary_holds_and_bounds_queries() -> void:
	var w: Node3D = await _world()
	for dir_v in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, -1).normalized(), Vector3(1, 0, -0.8).normalized()]:
		var dir: Vector3 = dir_v
		var from: Vector3 = dir * 60.0 + Vector3(0, 0, 10)
		from.y = w.height_at(from.x, from.z) + 1.0
		var to: Vector3 = from + dir * 140.0
		to.y = from.y
		var hit := _ray(w, from, to, 1)
		assert_false(hit.is_empty(), "something stops a walk out of the Reach toward %s" % dir)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			assert_true(absf(hp.x) < Reach.WALL_HALF_X + 1.0 and absf(hp.z) < Reach.WALL_HALF_Z + 1.0, "stopped at the walls toward %s (%s)" % [dir, hp])
	# Wading down Thimblebrook's carved channel to where it leaves through the south hills: the wall still holds.
	var info: Dictionary = w.terrain.nearest_stream_point(-32.5, 100.0)
	var bp: Vector3 = info["pos"]
	var bfrom := Vector3(bp.x, float(w.height_at(bp.x, bp.z)) + 0.9, bp.z)
	var bto := Vector3(-36.0, bfrom.y, 124.0)
	var bhit := _ray(w, bfrom, bto, 1)
	assert_false(bhit.is_empty(), "something stops a wade out along the brook")
	if not bhit.is_empty():
		assert_true(float(bhit["position"].z) < Reach.WALL_HALF_Z + 1.0, "stopped at the south wall (%s)" % bhit["position"])
	assert_true(w.is_inside_bounds(Vector3(0, 0, 0)), "centre inside")
	assert_true(w.is_inside_bounds(Vector3(130, 0, 0), 2.0), "near the east wall inside")
	assert_false(w.is_inside_bounds(Vector3(140, 0, 0)), "past the east wall outside")
	assert_false(w.is_inside_bounds(Vector3(134, 0, 104), 1.0), "the rounded corner is outside")
	assert_null(w.validate_position(Vector3(200, 1, 0)), "outside the Reach is rejected")


func test_no_fall_through_and_far_above_kill_y() -> void:
	var w: Node3D = await _world()
	var holes := 0
	var lowest := 1e9
	for i in 27:
		for j in 21:
			var x := -130.0 + float(i) * 10.0
			var z := -100.0 + float(j) * 10.0
			if not w.is_inside_bounds(Vector3(x, 0, z), 0.5):
				continue
			var hit := _ray(w, Vector3(x, 80.0, z), Vector3(x, WorldLayout.KILL_Y, z), 1)
			if hit.is_empty():
				holes += 1
			else:
				lowest = minf(lowest, float(hit["position"].y))
	assert_eq(holes, 0, "solid ground everywhere inside the walls")
	assert_true(lowest > WorldLayout.KILL_Y + 25.0, "the lowest floor (%.1f) is far above KILL_Y" % lowest)


## KILL_Y / outside / under-terrain recovery in the Reach (player_logic rules + this area's queries): a fall
## is detected, the region's own half extents are used, and the fallback recovery point (the saved spawn, or
## the first registered spawn for an unknown id) is valid ground.
func test_kill_y_and_recovery_rules_hold_in_the_reach() -> void:
	var w: Node3D = await _world()
	var bounds: Vector2 = Logic.world_half_extents("hallowmere_reach")
	assert_eq(bounds, Vector2(Reach.HALF_X, Reach.HALF_Z), "the player's bounds are the Reach's")
	var kill_y: float = Logic.kill_y_for("hallowmere_reach", WorldLayout.KILL_Y)
	var sp: Vector3 = (w.get_spawn("commons_arch") as Transform3D).origin
	assert_eq(String(Logic.recovery_reason_bounds(sp, bounds, kill_y, w.height_at(sp.x, sp.z), 0.0)), "", "standing at a spawn needs no recovery")
	assert_eq(String(Logic.recovery_reason_bounds(Vector3(sp.x, kill_y - 1.0, sp.z), bounds, kill_y, NAN, 0.0)), "fell", "below KILL_Y = a fall")
	assert_eq(String(Logic.recovery_reason_bounds(Vector3(sp.x, w.height_at(sp.x, sp.z) - 3.0, sp.z), bounds, kill_y, w.height_at(sp.x, sp.z), 0.5)), "below_floor", "under the terrain is recovered")
	# the walls stop her long before the "outside" margin: every wall point is inside the player's bounds
	for p in w.boundary_points():
		assert_true(absf(p.x) < bounds.x and absf(p.y) < bounds.y, "wall point %s inside the recovery bounds" % p)
	for id in ["commons_arch", "reach_respawn", "no_such_spawn"]:
		var xf: Transform3D = w.get_spawn(String(id))
		assert_true(w.validate_position(xf.origin) is Vector3, "recovery fallback via spawn %s is valid ground" % id)
		assert_true(xf.origin.y > kill_y + 20.0, "and far above KILL_Y")


## A road is walkable when, sampled every 0.5 m, the floor never steps more than 0.45 m and a player
## capsule fits everywhere (physics probes: fast and strict).
func _probe_route(w: Node3D, route: Array, label: String) -> bool:
	var pts := PackedVector2Array()
	for i in route.size() - 1:
		var a: Vector2 = route[i]
		var b: Vector2 = route[i + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
		for k in n:
			pts.append(a.lerp(b, float(k) / float(n)))
	pts.append(route[route.size() - 1])
	var prev := NAN
	for p in pts:
		if _in_district(p):
			prev = NAN          # district interiors are the district modules' (they test their own ground)
			continue
		var top := float(w.height_at(p.x, p.y)) + 2.6
		var hit := _ray(w, Vector3(p.x, top, p.y), Vector3(p.x, top - 8.0, p.y))
		if hit.is_empty():
			fail("%s: no floor at %s" % [label, p])
			return false
		var y: float = hit["position"].y
		if not is_nan(prev) and absf(y - prev) > 0.45:
			fail("%s: a %.2f m step at %s" % [label, absf(y - prev), p])
			return false
		prev = y
		var hits := _capsule_hits(w, Vector3(p.x, y, p.y))
		if not hits.is_empty():
			fail("%s: blocked at %s by %s" % [label, p, str(hits.map(func(o: Dictionary) -> String: return String(o["collider"].get_parent().name) + "/" + String(o["collider"].name)))])
			return false
	return true


## Inside a district landmark circle (and not on one of the region's arch plazas).
func _in_district(p: Vector2) -> bool:
	for id in ["hr_orchard", "hr_pools", "hr_candleyard", "hr_quarry", "hr_manor_grounds"]:
		if p.distance_to(Reach.LANDMARKS[id]["pos"]) <= float(Reach.LANDMARKS[id]["radius"]) + 0.5:
			for a in Reach.ARCHES:
				if p.distance_to(Reach.ARCHES[a]["pos"]) < 4.5:
					return false
			return true
	return false


func _curve(w: Node3D, id: String) -> Array:
	var out: Array = []
	for p in w.terrain.path_curves.get(id, PackedVector2Array()):
		out.append(p)
	return out


func test_every_layout_point_is_reachable_along_the_roads() -> void:
	var w: Node3D = await _world()
	var routes := {
		"arrival -> Commons arch": _curve(w, "arrival_road"),
		"through the Commons": [Vector2(0, 70), Vector2(1.6, 66), Vector2(1.6, 54), Vector2(0, 50)],
		"Commons -> Conservatory": _curve(w, "main_road"),
		"into the Conservatory": [Vector2(0, 15.5), Vector2(0, 12.5), Vector2(0, 8.3)],
		"Conservatory north": [Vector2(0, 3.7), Vector2(0, -0.5), Vector2(0, -3.5)],
		"Conservatory west": [Vector2(-2.2, 6.4), Vector2(-6.5, 6.2), Vector2(-7.5, 6)],
		"Conservatory east": [Vector2(2.2, 6.2), Vector2(6.5, 6.2), Vector2(7.5, 6)],
		"west road (orchard)": _curve(w, "west_road"),
		"east road (quarry)": _curve(w, "east_road"),
		"north road (manor)": _curve(w, "north_road"),
		"refuge spur": _curve(w, "refuge_spur"),
		"pools road": _curve(w, "pools_road"),
		"brook steps": _curve(w, "brook_steps_road"),
		"orchard - pools": _curve(w, "orchard_pools"),
		"orchard - Candleyard": _curve(w, "orchard_candleyard"),
		"pools - Candleyard": _curve(w, "pools_candleyard"),
		"to the Bellhouse": _curve(w, "bellhouse_road"),
		"Bellhouse - quarry": _curve(w, "quarry_bellhouse"),
		"arrival <- waygate": [Vector2(0, 101.0), Vector2(0, 98)],
		"outpost lot": [Vector2(-2.5, 58), Vector2(-9, 56), Vector2(-16, 54)],
		"to the Bellhouse stair": [Vector2(70, -71), Vector2(72, -72), Vector2(72, -76.8)],
	}
	for label in routes:
		var r: Array = routes[label]
		assert_true(r.size() >= 2, "%s has a route" % label)
		if r.size() >= 2:
			assert_true(_probe_route(w, r, String(label)), "%s is walkable" % label)
	# Every named layout point lies on (or right beside) a road or plaza that is on that network.
	for id in ["waygate_arrival", "commons_arch", "orchard_arch", "quarry_arch", "manor_arch", "conservatory_arch", "outpost", "refuge_hatch", "bellhouse_stair"]:
		var p: Vector2 = Reach.POINTS[id]
		var best := 1e9
		for rid in routes:
			for q in routes[rid]:
				best = minf(best, p.distance_to(q))
		assert_true(best < 7.0, "layout point %s is on the road network (%.1f m)" % [id, best])


## Walks a player-sized capsule (no step-up assist: stricter than the real player) from `from` toward `to`.
func _walk(w: Node3D, from: Vector3, to: Vector3, seconds: float = 8.0) -> Vector3:
	var body := CharacterBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1 | 32
	body.floor_max_angle = deg_to_rad(46.0)
	body.floor_snap_length = 0.35
	body.floor_constant_speed = true
	body.floor_stop_on_slope = true
	body.floor_block_on_wall = true
	body.max_slides = 6
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	cs.shape = cap
	cs.position = Vector3(0, 0.8, 0)
	body.add_child(cs)
	w.add_child(body)
	body.global_position = from
	var vy := 0.0
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var flat := Vector3(to.x - body.global_position.x, 0.0, to.z - body.global_position.z)
		if flat.length() < 0.4:
			break
		var d := flat.normalized() * 4.5
		vy = 0.0 if body.is_on_floor() else vy - 20.0 * dt
		body.velocity = Vector3(d.x, vy, d.z)
		body.move_and_slide()
	var end := body.global_position
	body.queue_free()
	return end


func _g(w: Node3D, p: Vector2, dy: float = 0.2) -> Vector3:
	return Vector3(p.x, float(w.height_at(p.x, p.y)) + dy, p.y)


func test_real_walks_crossings_doors_and_arches() -> void:
	var w: Node3D = await _world()
	for c in w.water.crossings:
		var center: Vector3 = c["pos"]
		var axis: Vector3 = c["axis"]
		for sgn in [1.0, -1.0]:
			var a: Vector3 = center - axis * 6.5 * float(sgn)
			var b: Vector3 = center + axis * 6.5 * float(sgn)
			var end: Vector3 = await _walk(w, _g(w, Vector2(a.x, a.z)), _g(w, Vector2(b.x, b.z), 0.0))
			assert_true(Vector2(end.x - b.x, end.z - b.z).length() < 1.0, "%s %s walkable (%s side, ended %s)" % [c["id"], c["style"], "+" if sgn > 0.0 else "-", end])
	# Through the Conservatory: south door in, north door out.
	var e1: Vector3 = await _walk(w, _g(w, Vector2(0, 16.5)), _g(w, Vector2(0, 8.4), 0.0))
	assert_true(Vector2(e1.x, e1.z).distance_to(Vector2(0, 8.4)) < 1.0, "in through the south door (%s)" % e1)
	var e2: Vector3 = await _walk(w, _g(w, Vector2(0, 3.6)), _g(w, Vector2(0, -5.0), 0.0))
	assert_true(Vector2(e2.x, e2.z).distance_to(Vector2(0, -5.0)) < 1.0, "out through the north door (%s)" % e2)
	# Through each Lantern Road arch along its road.
	for id in ["orchard", "quarry", "manor"]:
		var ap: Vector2 = Reach.ARCHES[id]["pos"]
		var lm: Vector2 = Reach.LANDMARKS[String(Reach.ARCHES[id]["landmark"])]["pos"]
		var d := (lm - ap).normalized()
		var e: Vector3 = await _walk(w, _g(w, ap - d * 4.0), _g(w, ap + d * 3.0, 0.0))
		assert_true(Vector2(e.x, e.z).distance_to(ap + d * 3.0) < 1.0, "through the %s arch (%s)" % [id, e])


func test_openings_are_wide_and_tall_enough() -> void:
	var w: Node3D = await _world()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.4, 0.3)
	for dp in Conservatory.door_points():
		var p: Vector2 = dp
		var n := (p - Reach.CONSERVATORY["center"]).normalized()
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = box
		sq.transform = Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(p.x, float(w.height_at(p.x, p.y)) + 1.35, p.y))
		sq.collision_mask = 1 | 32
		assert_eq(_space(w).intersect_shape(sq, 4).size(), 0, "Conservatory doorway at %s is at least 1.6 x 2.4 m" % p)
	for id in ["orchard", "quarry", "manor", "commons", "conservatory"]:
		var ap: Vector2 = Reach.ARCHES[id]["pos"]
		var lm: Vector2 = Reach.LANDMARKS[String(Reach.ARCHES[id]["landmark"])]["pos"]
		var d := (lm - ap).normalized()
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = box
		sq.transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.y)), Vector3(ap.x, float(w.height_at(ap.x, ap.y)) + 1.35, ap.y))
		sq.collision_mask = 1 | 32
		assert_eq(_space(w).intersect_shape(sq, 4).size(), 0, "arch %s opening is at least 1.6 x 2.4 m" % id)
	var pa: Vector2 = Reach.COMMONS["pumpkin_arch"]
	var sq2 := PhysicsShapeQueryParameters3D.new()
	sq2.shape = box
	sq2.transform = Transform3D(Basis(), Vector3(pa.x, float(w.height_at(pa.x, pa.y)) + 1.35, pa.y))
	sq2.collision_mask = 1 | 32
	assert_eq(_space(w).intersect_shape(sq2, 4).size(), 0, "the pumpkin arch opening is wide and tall")


func test_interactables_are_reachable() -> void:
	var w: Node3D = await _world()
	var nodes: Array = [w.commons.board, w.commons.mirror, w.commons.lot_sign, w.conservatory.pedestal, w.conservatory.lectern,
		w.conservatory.ledger, w.conservatory.plaque, w.conservatory.true_light, w.conservatory.seam_sign, w.conservatory.bench,
		w.conservatory.practice_seam, w.bellhouse.sign_it, w.bellhouse.plaque_it, w.waygate, w.refuge_hatch]
	for id in w.arches:
		nodes.append(w.arches[id])
	for n in nodes:
		assert_not_null(n, "interactable exists")
		if n == null:
			continue
		var col: CollisionObject3D = null
		for c in (n as Node).find_children("*", "CollisionObject3D", true, false):
			if (c as CollisionObject3D).collision_layer & 16:
				col = c
				break
		assert_not_null(col, "%s has an interaction collider on layer 16" % n.name)
		if col == null:
			continue
		var target: Vector3 = (col.get_child(0) as Node3D).global_position if col.get_child_count() > 0 else col.global_position
		var ok := false
		for k in 16:
			var a := TAU * float(k) / 16.0
			for r in [1.3, 1.9]:
				var s := Vector2(target.x, target.z) + Vector2(cos(a), sin(a)) * float(r)
				var top := float(w.height_at(s.x, s.y)) + 2.5
				var hit := _ray(w, Vector3(s.x, top, s.y), Vector3(s.x, top - 6.0, s.y))
				if hit.is_empty():
					continue
				var feet: Vector3 = hit["position"]
				if absf(feet.y - (target.y - 1.0)) > 1.6 or not _capsule_hits(w, feet).is_empty():
					continue
				var eye := feet + Vector3(0, 1.3, 0)
				var los := _ray(w, eye, target, 1 | 32)
				if los.is_empty() or (n as Node).is_ancestor_of(los["collider"]) or (los["position"] as Vector3).distance_to(target) < 0.6:
					ok = true
					break
			if ok:
				break
		assert_true(ok, "%s can be walked up to and seen" % n.name)


func test_continue_position_validation() -> void:
	var w: Node3D = await _world()
	for p in [Vector2(3, 62), Vector2(0, 98), Vector2(-16, 54), Vector2(2, 6.5), Vector2(72, -71), Vector2(-60, 47), Vector2(40, 44)]:
		var v: Variant = w.validate_position(Vector3(p.x, float(w.height_at(p.x, p.y)) + 0.4, p.y))
		assert_true(v is Vector3, "a saved position at %s is valid" % p)
		if v is Vector3:
			assert_almost(float((v as Vector3).y), float(w.height_at(p.x, p.y)) + 0.1, 0.4, "it snaps to the ground at %s" % p)
	var pond: Vector2 = Reach.BELLHOUSE["pond"] + Vector2(-8, 0)
	assert_null(w.validate_position(Vector3(pond.x, float(w.height_at(pond.x, pond.y)) + 0.1, pond.y)), "the Bellhouse pond is refused")
	var refused := 0
	var pts: PackedVector3Array = w.terrain.stream_pts
	for i in range(0, pts.size(), 3):
		var sp: Vector3 = pts[i]
		var near := false
		for c in w.water.crossings:
			if Vector2(sp.x, sp.z).distance_to(Vector2((c["pos"] as Vector3).x, (c["pos"] as Vector3).z)) < 6.0:
				near = true
		var h := float(w.height_at(sp.x, sp.z))
		if near or not w.is_inside_bounds(sp, 4.0) or not w.terrain.is_water(sp.x, sp.z) or float(w.water_level_at(sp.x, sp.z)) - h <= 0.6:
			continue
		assert_null(w.validate_position(Vector3(sp.x, h + 0.02, sp.z)), "deep brook at (%.1f, %.1f) is refused" % [sp.x, sp.z])
		refused += 1
	assert_true(refused >= 3, "deep brook samples checked (%d)" % refused)
	for c in w.water.crossings:
		var center: Vector3 = c["pos"]
		var hit := _ray(w, center + Vector3.UP * 6.0, center + Vector3.DOWN * 6.0, 1)
		assert_false(hit.is_empty(), "walkway over the %s" % c["style"])
		if not hit.is_empty():
			assert_true(w.validate_position((hit["position"] as Vector3) + Vector3.UP * 0.05) is Vector3, "standing on the %s is a valid saved position" % c["style"])
	assert_null(w.validate_position(Vector3(137.5, 5.0, 0.0)), "beyond the walls is refused")


func test_exits_arches_and_the_waygate_home() -> void:
	var w: Node3D = await _world()
	var exits: Dictionary = w.exits
	for name in ["manor_door", "bellhouse_stair", "refuge_hatch"]:
		assert_true(exits.has(name) and is_instance_valid(exits[name]), "exit %s exists" % name)
	for n in w.find_children("*", "Node3D", true, false):
		if not (n.is_in_group("area_exit") or n.is_in_group("waygate")):
			continue
		var ta := String(n.get("target_area"))
		var ts := String(n.get("target_spawn"))
		assert_true(LEGAL_TARGETS.has(ta) and (LEGAL_TARGETS[ta] as Array).has(ts), "%s leads to a spec spawn (%s/%s)" % [n.name, ta, ts])
	for id in Reach.ARCH_ORDER:
		var n: Node3D = w.arches.get(id)
		assert_not_null(n, "arch %s" % id)
		if n != null:
			assert_almost(Vector2(n.global_position.x, n.global_position.z).distance_to(Reach.ARCHES[id]["pos"]), 0.0, 0.01, "arch %s at its point" % id)
			assert_eq(String(n.get("spawn_id")), String(Reach.ARCHES[id]["spawn"]), "arch %s spawn" % id)
	var gate: Node3D = w.waygate
	assert_eq(String(gate.get("side")), "reach")
	assert_eq(String(gate.get_interaction(null).get("text", "")), "Return to Hollowhaven Woods", "the way home is always open")
	var arrival: Vector3 = (w.spawns["waygate_arrival"] as Transform3D).origin
	assert_true(gate.global_position.distance_to(arrival) < 6.0, "the waygate home stands right behind the arrival")


func test_vegetation_ids_are_unique_and_match_the_pure_plan() -> void:
	var w: Node3D = await _world()
	var ids: Array = w.resource_ids()
	var seen := {}
	for id in ids:
		assert_false(seen.has(id), "resource id %s unique" % id)
		seen[id] = true
		assert_true(String(id).begins_with("hr_"), "resource id %s is namespaced" % id)
	var plan: Dictionary = Vegetation.plan(w.terrain, w.district_footprints)
	assert_eq(Vegetation.ids(plan), Vegetation.ids(w.vegetation.plan_data), "the built plan is the pure plan")
	for id in Vegetation.ids(plan):
		assert_true(w.vegetation.resource_nodes.has(id), "node %s instantiated" % id)
	var practice: Node = w.conservatory.practice_seam
	assert_eq(String(practice.get("node_id")), Reach.PRACTICE_SEAM_ID)


func test_the_area_never_starts_music() -> void:
	var w: Node3D = await _world()
	Audio.stop_music(0.0)
	await wait_frames(2)
	var before: String = Audio.current_music()
	w.on_player_spawned(null)
	assert_eq(Audio.current_music(), before, "arrival leaves the music to the director")
	Audio.stop_ambience(0.0)
	await wait_frames(4)


## Real capsule walks at the Sunken Bellhouse: sealed, the slabs carry her over the stairwell at forecourt
## height (nothing to fall into); revealed, she walks down the stair to the service gate, the shut gate stops
## her, and once it is open she walks on into the tower passage and stands within reach of the way down.
func test_ys_bellhouse_stair_walks() -> void:
	var w: Node3D = await _world()
	var B: Dictionary = Reach.BELLHOUSE
	var sx: float = B["stair_x"]
	var hb := float(w.terrain.bellhouse_level)
	var bottom := hb - float(B["depth"])
	var bh: Node = w.bellhouse
	var saved := {}
	for f in ["ch2_lamps_linked", "ch2_service_gate_open"]:
		saved[f] = GameState.flags.get(f, null)
		GameState.flags.erase(f)
	bh.apply_state()
	await wait_physics(2)
	var top := Vector3(sx, hb + 0.2, float(B["ramp_top_z"]) + 2.0)
	var e0: Vector3 = await _walk(w, top, Vector3(sx, hb, float(B["gate_z"]) + 0.6))
	assert_true(e0.y > hb - 0.3, "sealed: the slabs hold her at forecourt height (y %.2f vs %.2f)" % [e0.y, hb])
	GameState.set_flag("ch2_lamps_linked", true)
	await wait_physics(2)
	var below_gate := Vector3(sx, bottom, float(B["gate_z"]) + 0.7)
	var e1: Vector3 = await _walk(w, top, below_gate, 10.0)
	assert_true(Vector2(e1.x - below_gate.x, e1.z - below_gate.z).length() < 1.0, "revealed: she walks down the stair to the gate (ended %s)" % e1)
	assert_almost(e1.y, bottom, 0.35, "and stands at the stair bottom")
	var inside := Vector3(sx, bottom, float(B["descent_z"]) + 0.4)
	var e2: Vector3 = await _walk(w, e1 + Vector3(0, 0.1, 0), inside, 4.0)
	assert_true(e2.z > float(B["gate_z"]) - 0.1, "the shut service gate stops her (ended %s)" % e2)
	bh.gate.unlock(false)
	await wait_physics(2)
	var e3: Vector3 = await _walk(w, e2 + Vector3(0, 0.1, 0), inside, 6.0)
	assert_true(Vector2(e3.x - inside.x, e3.z - inside.z).length() < 1.0, "through the open gate into the tower passage (ended %s)" % e3)
	var ib: StaticBody3D = bh.descent.get_node("Interact")
	assert_eq(int(ib.collision_layer), 16, "the way down answers once the gate is open")
	var sphere: Vector3 = (ib.get_child(0) as Node3D).global_position
	assert_true(sphere.distance_to(e3 + Vector3(0, 1.0, 0)) < 2.0, "and she stands within reach of it (%.2f m)" % sphere.distance_to(e3 + Vector3(0, 1.0, 0)))
	var up: Vector3 = await _walk(w, e3 + Vector3(0, 0.1, 0), top, 12.0)
	assert_true(Vector2(up.x - top.x, up.z - top.z).length() < 1.0 and up.y > hb - 0.3, "and walks back up to the forecourt (ended %s)" % up)
	for f in saved:
		if saved[f] == null:
			GameState.flags.erase(f)
		else:
			GameState.flags[f] = saved[f]
	bh.apply_state()
	w.road_lights.set_lit_instant(w.road_lights.should_be_lit())
	w.conservatory.pedestal.refresh()


func test_zz_cleanup() -> void:
	if _w != null and is_instance_valid(_w):
		_w.queue_free()
		_w = null
	await wait_frames(8)
