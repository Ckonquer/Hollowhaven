extends "res://tests/test_case.gd"
## The Below: a 0.35 m capsule (Krystal is 0.32 m x 1.6 m) sweeps along the authored critical path and
## the side paths without touching anything once the rubble and gate are open; while they are closed
## the path is blocked exactly there. Also checks for pits along the path (floor under every point).

const Layout := preload("res://src/world/below/below_layout.gd")
const WORLD := "res://src/world/below/below_world.gd"
const MASK := 1 | 32
const CLEARANCE := 0.25        # capsule floats this much above the floor (ramps, small lips)

var area: Node3D = null
var cap: CapsuleShape3D


func before_each() -> void:
	fresh_state()
	cap = CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6


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


func _center(p: Vector3) -> Vector3:
	return p + Vector3.UP * (CLEARANCE + cap.height * 0.5)


## Returns "" when the capsule can sweep from a to b, otherwise a description of what blocks it.
func _sweep(a: Vector3, b: Vector3) -> String:
	var space := area.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, _center(a))
	q.collision_mask = MASK
	var start_hits := space.intersect_shape(q, 4)
	if not start_hits.is_empty():
		return "start overlaps %s" % _names(start_hits)
	q.motion = b - a
	var r := space.cast_motion(q)
	if r[0] < 1.0:
		var at := a.lerp(b, r[1])
		q.transform = Transform3D(Basis.IDENTITY, _center(at))
		q.motion = Vector3.ZERO
		return "blocked at %s by %s" % [str(at.snapped(Vector3.ONE * 0.1)), _names(space.intersect_shape(q, 4))]
	return ""


func _names(hits: Array) -> String:
	var out := []
	for h in hits:
		var c: Object = h.get("collider")
		if c is Node:
			out.append(String((c as Node).get_path()).get_file())
	return ", ".join(out)


func _floor_below(p: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.8)
	q.collision_mask = MASK
	return not area.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _check_path(path: Array, label: String) -> void:
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		var res := _sweep(a, b)
		assert_eq(res, "", "%s segment %d %s -> %s" % [label, i, str(a), str(b)])
		# no pits: sample the floor along the segment
		var n := maxi(int(a.distance_to(b) / 0.75), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			if not _floor_below(p):
				fail("%s: no floor under %s" % [label, str(p.snapped(Vector3.ONE * 0.1))])
				break


func test_critical_path_is_clear_when_open() -> void:
	GameState.set_flag("gallery_cleared", true)
	GameState.set_flag("lower_gate_open", true)
	area = await _make_area()
	_check_path(Layout.CRITICAL_PATH, "critical")


func test_side_paths_are_clear() -> void:
	GameState.set_flag("gallery_cleared", true)
	GameState.set_flag("lower_gate_open", true)
	area = await _make_area()
	var i := 0
	for path in Layout.SIDE_PATHS:
		_check_path(path, "side%d" % i)
		i += 1


func test_path_is_blocked_while_locked() -> void:
	area = await _make_area()
	assert_ne(_sweep(Vector3(0, 0, -53.0), Vector3(0, 0, -57.2)), "", "closed gate blocks")
	assert_ne(_sweep(Vector3(7.0, 0, -43.75), Vector3(12.5, 0, -43.75)), "", "rubble blocks the office")
	# Everything before the gate is still reachable
	_check_path(Layout.CRITICAL_PATH.slice(0, 7), "pre-gate")


func test_no_escape_from_rooms() -> void:
	# Rays outward from room centres at knee and head height must hit a wall (no holes into the void),
	# except through the authored openings.
	GameState.set_flag("gallery_cleared", true)
	GameState.set_flag("lower_gate_open", true)
	area = await _make_area()
	var space := area.get_world_3d().direct_space_state
	for id in ["landing", "tunnel", "gallery", "office", "hall", "shrine", "webbed", "junction", "webbed2", "nursery", "antechamber"]:
		var r: Dictionary = Layout.ROOMS[id]
		var c := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, float(r["y"]), (float(r["z0"]) + float(r["z1"])) * 0.5)
		for k in 16:
			var a := TAU * float(k) / 16.0
			var dir := Vector3(cos(a), 0, sin(a))
			for h in [0.5, 1.5]:
				var from: Vector3 = c + Vector3.UP * float(h)
				var q := PhysicsRayQueryParameters3D.create(from, from + dir * 80.0)
				q.collision_mask = MASK
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					fail("%s: ray %d escapes into the void at height %.1f" % [id, k, h])
	# The round chamber: rays from the centre hit the ring wall (or leave through the entrance/lift).
	var cc := Layout.ARENA_CENTER + Vector3.UP * 1.0
	for k in 32:
		var a := TAU * float(k) / 32.0
		var q := PhysicsRayQueryParameters3D.create(cc, cc + Vector3(cos(a), 0, sin(a)) * 60.0)
		q.collision_mask = MASK
		if space.intersect_ray(q).is_empty():
			fail("arena: ray %d escapes" % k)
