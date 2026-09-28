extends "res://tests/unit/test_reach_east_walk.gd"
## The same Ashbell Quarry geometry checks as test_reach_east_walk.gd, run on the REAL Hallowmere Reach (the
## region module's area script with every district, when it builds): the quarry's shaping and content on the
## region terrain, walk graph from the region's quarry-arch spawn, openings, no holes, zones, plus: district
## build time inside the region, ids unique across the whole region, positions = the deterministic plan.
## When the region script is missing or doesn't compile the suite reports "skipped" (the sandbox suite still
## covers the quarry).

const REGION := "res://src/world/areas_ch2/hallowmere_reach_world.gd"
const Builder := preload("res://src/world/reach/east/quarry_builder.gd")


func _make_host() -> Node3D:
	if not ResourceLoader.exists(REGION):
		return null
	var s: Variant = load(REGION)
	if not (s is Script) or not (s as Script).can_instantiate():
		return null
	var w: Variant = (s as Script).new()
	if not (w is Node3D):
		return null
	if District.district_root(w as Node) == null and not (w as Node).has_method("height_at"):
		return null
	return w


## The region's Bellhouse road (path quarry_bellhouse) walks into the quarry's north mouth and down onto the arena
## bench: physics floor under every 0.5 m step, gentle slope, nothing blocking at knee / chest height.
func test_bellhouse_road_walks_into_the_quarry() -> void:
	if not _host_ok():
		return
	var space := _box.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	var road: Array = Reach.PATHS["quarry_bellhouse"]
	var pts: Array = [road[road.size() - 2], road[road.size() - 1], Shape.to_world(Vector2(24.0, -14.0)),
		Shape.to_world(Vector2(22.0, -12.5)), Shape.to_world(Vector2(16.0, -9.0)), Q.ARENA]
	var prev := Vector3(NAN, NAN, NAN)
	var worst := 0.0
	var holes := 0
	var blocked := 0
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var n := int(ceil(a.distance_to(b) / 0.5))
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			q.from = Vector3(p.x, 60.0, p.y)
			q.to = Vector3(p.x, -40.0, p.y)
			var hit := q.from
			var r := space.intersect_ray(q)
			if r.is_empty():
				holes += 1
				continue
			hit = r["position"]
			if not is_nan(prev.x):
				var dd := Vector2(hit.x - prev.x, hit.z - prev.z).length()
				if dd > 0.01:
					worst = maxf(worst, rad_to_deg(atan(absf(hit.y - prev.y) / dd)))
				for dy in [0.45, 1.2]:
					q.from = prev + Vector3(0, float(dy), 0)
					q.to = hit + Vector3(0, float(dy), 0)
					if not space.intersect_ray(q).is_empty():
						blocked += 1
			prev = hit
	assert_eq(holes, 0, "floor under the whole route")
	assert_eq(blocked, 0, "nothing blocks the route")
	assert_true(worst <= 30.0, "gentle slope all the way (steepest %.1f deg)" % worst)


## The shelf is sealed from the Reach's own ground around the quarry too (not only from the benches): a wider walk
## graph (46 m, well past the crown wall and the landmark circle) from the quarry-arch spawn walks the natural
## ground outside the circle and still never reaches the shelf or the lamp while the gangway is raised.
func test_shelf_sealed_from_the_surrounding_region() -> void:
	if not _host_ok():
		return
	await _set_gangway(false)
	_set_graph_radius(46.0)
	var ys := _sample()
	var s := _start(ys)
	assert_true(s >= 0, "start cell at the arch spawn")
	var seen := _bfs(ys, s)
	var outside := 0
	var shelf: Array = []
	for k in ys.size():
		if seen[k] != 1:
			continue
		var p := _pos(k)
		if p.distance_to(Q.CENTER) > Q.RADIUS + 0.5:
			outside += 1
		if Shape.is_shelf(p.x, p.y) and shelf.size() < 8:
			shelf.append("%s y=%.1f" % [p, ys[k]])
	print("  wide walk graph (46 m): %d reached cells outside the landmark circle" % outside)
	assert_true(outside > 500, "the wider graph really walks the ground outside the quarry (%d cells)" % outside)
	assert_eq(shelf, [], "shelf cells reached from the region without the winch")
	var lp: Vector3 = _quarry().lamp.position
	assert_false(_reached_near(ys, seen, Vector2(lp.x, lp.z), lp.y, 3.5), "the lamp stays out of reach")
	_set_graph_radius(GR)


func test_build_time_and_determinism() -> void:
	if not _host_ok():
		return
	var qr := _quarry()
	assert_not_null(qr, "the region built the quarry district")
	if qr == null:
		return
	print("  in the Reach: quarry district build %.1f ms" % float(qr.build_ms))
	assert_true(float(qr.build_ms) < 450.0, "district build %.1f ms" % float(qr.build_ms))
	var plan := Builder.node_plan()
	assert_eq(qr.nodes.size(), plan.size(), "every planned node exists")
	for e in plan:
		var n: Node3D = qr.nodes.get(String(e["id"]))
		assert_not_null(n, "node " + String(e["id"]))
		if n == null:
			continue
		var w: Vector2 = e["pos"]
		assert_true(Vector2(n.position.x, n.position.z).distance_to(w) < 0.001, "planned position: " + String(e["id"]))
	if _box.has_method("resource_ids"):
		var ids: Array = _box.resource_ids()
		var seen := {}
		var dup: Array = []
		for id in ids:
			if seen.has(id):
				dup.append(id)
			seen[id] = true
		assert_eq(dup, [], "harvest ids unique across the whole Reach")
		for e in plan:
			assert_true(seen.has(String(e["id"])), "the region lists %s" % e["id"])
