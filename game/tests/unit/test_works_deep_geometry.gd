extends "res://tests/test_case.gd"
## Hushed Works rooms 9-14, built exactly as the Works area will build them (deep_preview_host.gd: stub hub
## + Builder + rooms_deep.gd + one finish()): build time, spawns on the floor with capsule clearance, the
## critical path and side paths walkable (floor under every step, headroom, capsule clear), openings
## passable, no fall-through, no escape (enclosed rooms), required interactables reachable, deterministic
## node ids, shadowed-light budget, zones & safe zones, checkpoints. Physics probes only (headless).

const Host := preload("res://src/world/works/deep/deep_preview_host.gd")
const Layout := preload("res://data/works_layout_deep.gd")
const MASK := 1 | 32
const STEP := 0.4

var host: Node3D = null


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if host != null and is_instance_valid(host):
		host.queue_free()
	host = null
	await wait_frames(2)


func _make() -> Node3D:
	var h: Node3D = Host.new()
	h.set("with_environment", false)
	add_child(h)
	await wait_physics(3)
	return h


func _space() -> PhysicsDirectSpaceState3D:
	return host.get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return _space().intersect_ray(q)


func _capsule_free(feet: Vector3, radius: float = 0.3, height: float = 1.4, lift: float = 0.3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (lift + height * 0.5))
	q.collision_mask = MASK
	return _space().intersect_shape(q, 4).is_empty()


## Opens every gated barrier so the whole route can be probed (tests of the gates themselves live in the
## mechanics / arena suites).
func _open_everything() -> void:
	var ctl: Node = host.get("deep")
	(ctl.call("thread", "hw_thread_winch_exit") as Node).call("burn")
	(ctl.call("thread", "hw_thread_nook") as Node).call("burn")
	(ctl.get("crossing") as Node).call("clear_encounter")
	(ctl.get("porch") as Node).call("reveal")
	(ctl.get("choir") as Node).call("clear_encounter")
	await wait_physics(3)


## Walks a polyline of floor points: every STEP there must be a floor within 0.45 m of the expected height,
## 2 m of headroom and a clear capsule. Returns the first problem ("" = walkable).
func _walk(points: Array) -> String:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var n := maxi(int(ceilf(a.distance_to(b) / STEP)), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			var hit := _ray(p + Vector3.UP * 1.0, p + Vector3.DOWN * 1.2)
			if hit.is_empty():
				return "no floor under %s" % str(p)
			var fy: float = (hit["position"] as Vector3).y
			if absf(fy - p.y) > 0.45:
				return "floor at %.2f, expected %.2f at %s" % [fy, p.y, str(p)]
			var f := Vector3(p.x, fy, p.z)
			if not _ray(f + Vector3.UP * 0.35, f + Vector3.UP * 2.0).is_empty():
				return "low ceiling at %s" % str(p)
			if not _capsule_free(f, 0.28, 1.3, 0.35):
				return "blocked at %s" % str(p)
	return ""


func test_build_time_is_well_under_budget() -> void:
	host = await _make()
	var ms: float = float(host.get("build_ms"))
	var deep_ms: float = float((host.get("deep") as Node).get("build_ms"))
	print("  works_deep build: host %.1f ms (rooms 9-14 build() %.1f ms)" % [ms, deep_ms])
	assert_true(ms < 1500.0, "host build %.0f ms < 1500" % ms)
	assert_true(deep_ms < 900.0, "rooms_deep.build %.0f ms < 900" % deep_ms)
	var batches := 0
	var instances := 0
	for n in host.find_children("*", "MultiMeshInstance3D", true, false):
		batches += 1
		instances += (n as MultiMeshInstance3D).multimesh.instance_count
	print("  works_deep batches %d, instances %d" % [batches, instances])
	assert_true(instances > 1500, "repeated props are batched (MultiMesh), %d instances" % instances)


func test_spawns_on_floor_with_capsule_clearance() -> void:
	host = await _make()
	for id in Layout.SPAWNS.keys() + ["refuge"]:
		assert_true(host.spawns.has(id), "spawn %s registered" % id)
		var p: Vector3 = host.get_spawn(id).origin
		var hit := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.5)
		assert_false(hit.is_empty(), "%s has ground below" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.2, "%s stands on the floor" % id)
		assert_true(_ray(p + Vector3.UP * 0.2, p + Vector3.UP * 2.4).is_empty(), "%s has 2.4 m headroom" % id)
		assert_true(_capsule_free(p, 0.35, 1.6, 0.25), "%s capsule is free" % id)
		assert_ne(host.validate_position(p), null, "%s passes validate_position" % id)


func test_critical_path_and_side_paths_are_walkable() -> void:
	host = await _make()
	await _open_everything()
	var bad := _walk(Layout.CRITICAL_PATH)
	assert_eq(bad, "", "critical path hub door -> Choir Vault")
	for path in Layout.SIDE_PATHS:
		assert_eq(_walk(path), "", "side path from %s" % str(path[0]))
	# the hub side of the door (stub hub) connects too
	assert_eq(_walk([Vector3(36.0, -18.0, 0.0), Vector3(40.3, -18.0, 0.0), Vector3(43.0, -18.0, 0.0)]), "", "through the hub door")


func test_gates_block_until_opened() -> void:
	host = await _make()
	var ctl: Node = host.get("deep")
	# winch exit veil, crossing exit veil, porch illusion, vault exit gate, Matron route (always shut)
	var probes := [[Vector3(60.4, -17.0, 0.0), Vector3(62.8, -17.0, 0.0), "winch exit threads"],
		[Vector3(106.5, -17.0, 0.0), Vector3(108.6, -17.0, 0.0), "crossing exit threads"],
		[Vector3(137.5, -21.0, 33.5), Vector3(140.5, -21.0, 33.5), "porch illusion"],
		[Vector3(157.0, -31.0, 76.8), Vector3(157.0, -31.0, 79.5), "vault exit gate"],
		[Vector3(106.0, -17.0, -11.0), Vector3(106.0, -17.0, -14.5), "Matron route"]]
	for pr in probes:
		assert_false(_ray(pr[0], pr[1]).is_empty(), "%s blocks before" % String(pr[2]))
	await _open_everything()
	for i in 4:
		var pr: Array = probes[i]
		assert_true(_ray(pr[0], pr[1]).is_empty(), "%s open after" % String(pr[2]))
	assert_false(_ray(probes[4][0], probes[4][1]).is_empty(), "the Matron's deeper route stays shut (service gate)")
	assert_true(bool((ctl.get("crossing") as Node).call("route_gate_shut")), "service gate down")


func test_openings_are_passable() -> void:
	host = await _make()
	await _open_everything()
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var open: Dictionary = r["open"]
		for side in open:
			if open[side] is String:
				continue
			if id == "hw_crossing" and side == "n":
				continue   # the Matron's deeper route: deliberately shut by the service gate (gates test)
			for o in open[side]:
				var mid: float = (float(o[0]) + float(o[1])) * 0.5
				var p := Vector3.ZERO
				match String(side):
					"n": p = Vector3(mid, 0.0, float(r["z0"]) - 0.5)
					"s": p = Vector3(mid, 0.0, float(r["z1"]) + 0.5)
					"w": p = Vector3(float(r["x0"]) - 0.5, 0.0, mid)
					"e": p = Vector3(float(r["x1"]) + 0.5, 0.0, mid)
				var hit := _ray(Vector3(p.x, float(r["y"]) + 1.5, p.z), Vector3(p.x, float(r["y"]) - 1.5, p.z))
				assert_false(hit.is_empty(), "%s %s doorway has a floor" % [id, side])
				if hit.is_empty():
					continue
				var f: Vector3 = hit["position"]
				assert_true(_capsule_free(f, 0.3, 1.8, 0.3), "%s %s doorway clear for a 2.4 m tall walker" % [id, side])
				assert_true(_ray(f + Vector3.UP * 0.3, f + Vector3.UP * 2.35).is_empty(), "%s %s doorway >= 2.4 m tall" % [id, side])


func test_no_fall_through_floors() -> void:
	host = await _make()
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var nx := 5
		var nz := 5
		for i in nx:
			for j in nz:
				var x := lerpf(float(r["x0"]) + 0.6, float(r["x1"]) - 0.6, (float(i) + 0.5) / float(nx))
				var z := lerpf(float(r["z0"]) + 0.6, float(r["z1"]) - 0.6, (float(j) + 0.5) / float(nz))
				var p := Vector3(x, Layout.floor_y_at(id, Vector3(x, 0, z)), z)
				if id == "hw_crossing":
					continue   # its floor is the ledges + bridge; the pit below is checked as its own room
				if id == "hw_vault" and Vector2(x - 157.0, z - 65.0).length() > 12.2:
					continue
				var hit := _ray(p + Vector3.UP * 1.0, p + Vector3.DOWN * 3.0)
				assert_false(hit.is_empty(), "%s floor at %s" % [id, str(p)])
	# the bridge and both ledges
	for p in [Vector3(70.0, -18.0, 8.0), Vector3(80.0, -18.0, 3.0), Vector3(95.0, -18.0, -4.0), Vector3(106.0, -18.0, -9.0)]:
		assert_false(_ray(p + Vector3.UP, p + Vector3.DOWN * 2.0).is_empty(), "crossing floor at %s" % str(p))


func test_rooms_are_enclosed() -> void:
	host = await _make()
	await _open_everything()
	var origins: Array = []
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var c := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, Layout.floor_y_at(id, Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, 0, (float(r["z0"]) + float(r["z1"])) * 0.5)) + 1.2, (float(r["z0"]) + float(r["z1"])) * 0.5)
		if id == "hw_crossing":
			c = Vector3(88.0, -16.8, 0.0)
		origins.append([id, c])
	for oc in origins:
		var id: String = oc[0]
		var c: Vector3 = oc[1]
		for k in 24:
			var ang := TAU * float(k) / 24.0
			var dir := Vector3(cos(ang), 0.0, sin(ang))
			assert_false(_ray(c, c + dir * 120.0).is_empty(), "%s: a ray toward %.0f deg escapes" % [id, rad_to_deg(ang)])
			var up_dir := (dir * 0.6 + Vector3.UP).normalized()
			assert_false(_ray(c, c + up_dir * 60.0).is_empty(), "%s: an upward ray toward %.0f deg escapes" % [id, rad_to_deg(ang)])
		var down := _ray(c, c + Vector3.DOWN * 40.0)
		assert_false(down.is_empty(), "%s has a floor below its centre" % id)


func test_interactables_are_reachable() -> void:
	host = await _make()
	var count := 0
	for n in get_tree().get_nodes_in_group("interactable"):
		if not host.is_ancestor_of(n):
			continue
		var th: Variant = n.get("thick")
		if th is bool and th:
			continue
		var center := _interact_center(n as Node3D)
		count += 1
		assert_true(_standing_spot_near(center), "%s at %s is reachable" % [String(n.name), str(center)])
	assert_true(count >= 20, "the deep rooms offer their interactables (%d)" % count)


func _interact_center(n: Node3D) -> Vector3:
	for c in n.get_children():
		if c is Area3D and ((c as Area3D).collision_layer & 16) != 0:
			for s in c.get_children():
				if s is CollisionShape3D:
					return (s as CollisionShape3D).global_position
	return n.global_position + Vector3.UP


## A floor point within the probe range (2.6 m) of `center`, with a clear capsule and a line of sight.
func _standing_spot_near(center: Vector3) -> bool:
	for rr in [0.9, 1.4, 1.9, 2.3]:
		for k in 16:
			var ang := TAU * float(k) / 16.0
			var p := center + Vector3(cos(ang) * float(rr), 0.0, sin(ang) * float(rr))
			var hit := _ray(Vector3(p.x, center.y + 1.2, p.z), Vector3(p.x, center.y - 3.0, p.z))
			if hit.is_empty():
				continue
			var f: Vector3 = hit["position"]
			if absf(f.y - center.y) > 2.2 or not _capsule_free(f, 0.3, 1.2, 0.3):
				continue
			var eye := f + Vector3.UP * 1.3
			if eye.distance_to(center) > 2.6:
				continue
			var los := _ray(eye, center)
			if los.is_empty() or (los["position"] as Vector3).distance_to(center) < 0.6:
				return true
	return false


func test_node_ids_are_deterministic() -> void:
	host = await _make()
	var a := _signature(host)
	host.queue_free()
	await wait_frames(2)
	host = await _make()
	var b := _signature(host)
	assert_eq(a["ids"], b["ids"], "persistent ids")
	assert_eq(a["names"], b["names"], "named nodes")
	assert_eq(a["instances"], b["instances"], "batched geometry per room")
	assert_true((a["ids"] as Array).size() >= 6, "threads, checkpoints and lifts have ids")


func _signature(h: Node3D) -> Dictionary:
	var ctl: Node = h.get("deep")
	var names: Array = []
	var inst := {}
	for room in h.get_children():
		if not String(room.name).begins_with("Room_") and room != ctl:
			continue
		for c in room.get_children():
			if c is MultiMeshInstance3D:
				inst[String(room.name)] = int(inst.get(String(room.name), 0)) + (c as MultiMeshInstance3D).multimesh.instance_count
			elif not String(c.name).begins_with("@") and not String(c.name).begins_with("Occluder") and not String(c.name).begins_with("Col_"):
				names.append(String(room.name) + "/" + String(c.name))
	names.sort()
	return {"ids": ctl.call("persistent_ids"), "names": names, "instances": inst}


func test_shadowed_light_budget() -> void:
	host = await _make()
	var shadowed: Array = []
	for l in host.find_children("*", "Light3D", true, false):
		if (l as Light3D).shadow_enabled:
			shadowed.append(l)
	for key in [Vector3(64.0, -17.0, 0.0), Vector3(88.0, -17.0, 0.0), Vector3(129.0, -21.0, 0.0), Vector3(124.0, -21.0, 30.0), Vector3(157.0, -27.0, 31.0), Vector3(157.0, -31.0, 65.0)]:
		var near := 0
		for l in shadowed:
			if (l as Node3D).global_position.distance_to(key) < 40.0:
				near += 1
		assert_true(near <= 8, "at most 8 shadowed lights around %s (%d)" % [str(key), near])


func test_zones_and_safe_zones() -> void:
	host = await _make()
	assert_eq(host.get_zone_at(Vector3(52.0, -18.0, 2.0)), "hw_winch")
	assert_eq(host.get_zone_at(Vector3(88.0, -18.0, 0.0)), "hw_crossing")
	assert_eq(host.get_zone_at(Vector3(129.0, -22.0, 0.0)), "hw_wrong_landing")
	assert_eq(host.get_zone_at(Vector3(124.0, -22.0, 30.0)), "hw_porch")
	assert_eq(host.get_zone_at(Vector3(157.0, -28.0, 30.0)), "hw_throat")
	assert_eq(host.get_zone_at(Vector3(157.0, -32.0, 65.0)), "hw_vault")
	var ids := {}
	for z in host.zones:
		ids[String(z["id"])] = true
	for z in Layout.zone_ids():
		assert_true(ids.has(z), "zone %s registered" % z)
	assert_true(host.is_safe_zone(Vector3(157.0, -28.0, 25.0)), "Bell Throat is safe")
	assert_true(host.is_safe_zone(host.get_spawn("bell_throat").origin), "bell_throat spawn is safe")
	assert_false(host.is_safe_zone(Vector3(88.0, -18.0, 0.0)), "the crossing is not safe")
	assert_false(host.is_safe_zone(Vector3(157.0, -32.0, 65.0)), "the vault is not safe")
	assert_false(host.is_safe_zone(Vector3(129.0, -22.0, 0.0)), "the wrong landing is not safe")
	var anchors := 0
	for a in get_tree().get_nodes_in_group("director_anchor"):
		if host.is_ancestor_of(a):
			anchors += 1
			assert_true(Layout.zone_ids().has(String(a.get_meta("zone", ""))), "anchor zone is a works zone")
	assert_true(anchors >= 9, "director anchors placed")


func test_checkpoints_set_respawn_and_safety() -> void:
	host = await _make()
	var ctl: Node = host.get("deep")
	for id in Layout.CHECKPOINTS:
		var cp: Node = ctl.call("checkpoint", id)
		assert_not_null(cp, "checkpoint %s" % id)
		assert_true((host.get("checkpoints") as Dictionary).has(id), "area.checkpoints lists %s" % id)
		assert_eq(String(cp.get("area_id")), "hushed_works", "checkpoint %s respawns in the Works" % id)
		var sp := String(Layout.CHECKPOINTS[id]["spawn"])
		assert_true(host.spawns.has(sp), "its spawn %s exists" % sp)
	var gate: Node = ctl.call("checkpoint", "hw_crossing_gate")
	var gp: Vector3 = Layout.CHECKPOINTS["hw_crossing_gate"]["pos"]
	assert_false(host.is_safe_zone(gp), "unlit checkpoint is not safe")
	gate.set("save_enabled", false)
	gate.call("interact", null)
	assert_true(bool(GameState.get_flag("cp_lit_hw_crossing_gate")), "lit flag")
	assert_true(host.is_safe_zone(gp), "lit checkpoint is a safe zone")
	assert_eq(String(GameState.player.get("respawn_area", "")), "hushed_works")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "crossing_gate", "respawn BEFORE the arena")
