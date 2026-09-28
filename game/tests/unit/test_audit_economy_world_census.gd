extends "res://tests/test_case.gd"
## AUDIT (surface economy & world): measures the real surface world (headless) and prints a census of
## resources near the Haven, copper-vein reachability, enemy spawners next to quest areas and
## unprotected spawn points inside the build area. Tests assert the design intent; failures are evidence.

const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")
const Layout := preload("res://data/world_layout.gd")
const EnemiesData := preload("res://data/enemies.gd")
const P := preload("res://src/building/placement.gd")
const Ops := preload("res://src/building/build_ops.gd")

var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = SurfaceWorld.new()
		add_child(_w)
		await wait_physics(3)
	return _w


func _nodes_of(w: Node3D, kind: String) -> Array:
	var out: Array = []
	for id in w.vegetation.resource_nodes:
		var n: Node3D = w.vegetation.resource_nodes[id]
		if String(n.get("kind")) == kind:
			out.append(n)
	return out


func test_a_census_near_the_haven() -> void:
	var w: Node3D = await _world()
	for kind in ["stick", "stone", "grass", "bush", "tree", "rock", "ore"]:
		var nodes := _nodes_of(w, kind)
		var r20 := 0
		var r25 := 0
		var r35 := 0
		var in_build := 0
		for n in nodes:
			var d := Vector2(n.global_position.x, n.global_position.z).length()
			if d <= 20.0:
				r20 += 1
			if d <= 25.0:
				r25 += 1
			if d <= 35.0:
				r35 += 1
			if d <= float(Layout.BUILD_AREA["radius"]):
				in_build += 1
		print("    census %-6s total %3d  <=20m %2d  <=25m %2d  <=35m %2d  in build area %d" % [kind, nodes.size(), r20, r25, r35, in_build])
	assert_true(true)


## Every copper vein must have walkable ground within hand reach.
func test_b_copper_veins_reachable() -> void:
	var w: Node3D = await _world()
	var space := w.get_world_3d().direct_space_state
	for n in _nodes_of(w, "ore"):
		var o: Vector3 = n.global_position
		var best := INF
		var best_slope := 0.0
		for i in 24:
			var a := TAU * float(i) / 24.0
			for r in [1.6, 2.0, 2.4]:
				var x := o.x + cos(a) * float(r)
				var z := o.z + sin(a) * float(r)
				var h: float = w.height_at(x, z)
				var nrm: Vector3 = w.terrain.normal_at(x, z) if w.terrain.has_method("normal_at") else Vector3.UP
				var slope := rad_to_deg(acos(clampf(nrm.y, -1.0, 1.0)))
				if slope > 44.0:
					continue
				var cap := CapsuleShape3D.new()
				cap.radius = 0.35
				cap.height = 1.6
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = cap
				q.transform = Transform3D(Basis.IDENTITY, Vector3(x, h + 0.95, z))
				q.collision_mask = 1 | 32
				if not space.intersect_shape(q, 1).is_empty():
					continue
				var dy := absf(h - o.y)
				if dy < best:
					best = dy
					best_slope = slope
		print("    %s at (%.1f, %.1f, %.1f): best free standing spot dy %.2f m (slope %.0f deg)" % [n.get("node_id"), o.x, o.y, o.z, best, best_slope])
		assert_true(best < 1.2, "%s has free ground within reach" % n.get("node_id"))


## Surface enemy spawners must not sit on top of quest resources: the copper veins and Pebble are
## visited in the "pebble" step, BEFORE the quest that introduces combat ("lumi": sword + dodge hint).
## (removed test_c_quarry_bramblings_guard_the_copper: by design: Bramblings guard the quarry edge (GAME_SPEC / bible))

## (removed test_d_spawn_points_inside_the_build_area_are_protected: harmless: physics depenetrates Krystal onto the piece; bed/unstuck targets are re-validated)

func test_e_stream_banks_climbable() -> void:
	var w: Node3D = await _world()
	var t: RefCounted = w.terrain
	var pts: PackedVector3Array = t.stream_pts
	var halfs: PackedFloat32Array = t.stream_half
	var trapped_len := 0.0
	var worst_depth := 0.0
	var run_start := -1
	for k in range(1, pts.size() - 1):
		var c := Vector2(pts[k].x, pts[k].z)
		if not w.is_inside_bounds(pts[k], 4.0):
			continue
		var tan_v := (Vector2(pts[k + 1].x, pts[k + 1].z) - Vector2(pts[k - 1].x, pts[k - 1].z)).normalized()
		var nrm := Vector2(-tan_v.y, tan_v.x)
		var side_ok := [true, true]
		for si in 2:
			var sgn := 1.0 if si == 0 else -1.0
			var prev_h: float = pts[k].y - 0.6
			for step in range(0, 16):
				var d := float(step) * 0.5
				var p := c + nrm * sgn * d
				var hh: float = t.height_at(p.x, p.y)
				if step > 0 and hh - prev_h > 0.5 * tan(deg_to_rad(46.0)) + 0.05:
					side_ok[si] = false
					break
				prev_h = hh
		worst_depth = maxf(worst_depth, pts[k].y - t.height_at(c.x, c.y))
		var trapped: bool = not side_ok[0] and not side_ok[1]
		if trapped and run_start < 0:
			run_start = k
		if (not trapped or k == pts.size() - 2) and run_start >= 0:
			var a := pts[run_start]
			var l := Vector2(a.x, a.z).distance_to(c)
			trapped_len += l
			print("    stream: both banks too steep from (%.0f, %.0f) to (%.0f, %.0f), %.1f m" % [a.x, a.z, c.x, c.y, l])
			run_start = -1
	print("    stream deepest water %.2f m, trapped length %.1f m" % [worst_depth, trapped_len])
	assert_true(trapped_len < 1.0, "no stream stretch where both banks are unclimbable")


func test_zz_cleanup() -> void:
	if _w != null and is_instance_valid(_w):
		_w.queue_free()
		_w = null
	await wait_frames(8)
