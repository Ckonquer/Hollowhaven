extends "res://tests/test_case.gd"
## Ashbell Quarry geometry with real physics (src/world/reach/east/quarry_sandbox.gd: the district's own
## shape_terrain + build on a small heightfield, the same calls the Reach makes). A 0.5 m walk graph is sampled
## with rays (standable = floor normal <= 46 deg + 1.6 m headroom; up-steps <= 0.45 m; falling down is always
## allowed; knee/chest rays block walls and rails):
##  * from the region's quarry-arch spawn, every lower-quarry harvest node, the winch drum, the quarry log, the
##    arena and every pillar are reachable; the upper shelf (lamp, Moon Crystal seams) is NOT without the winch
##  * with the gangway lowered the shelf is reachable, and nothing can trap Krystal (every standable patch in
##    the quarry can walk back to the arch)
##  * no holes (every sample in the circle has a floor at or above the terrain), the spawn has capsule
##    clearance, the gangway / bell gate / haul road openings are >= 1.6 m wide x 2.4 m tall
##  * build time, determinism of node ids and positions

const Q := preload("res://data/reach_east.gd")
const Reach := preload("res://data/hallowmere_layout.gd")
const Shape := preload("res://src/world/reach/east/quarry_shape.gd")
const SandboxScript := preload("res://src/world/reach/east/quarry_sandbox.gd")
const District := preload("res://src/world/reach/districts/quarry.gd")

const STEP := 0.5
const GR := 32.0
const CLIMB := 0.45
const MIN_NY := 0.69
const MASK := 1 | 32

var _box: Node3D = null
var _tried := false
var _gr := GR                   # walk graph radius around the quarry centre (a wider graph: _set_graph_radius)
var _gn := 0
var _walls: Dictionary = {}


## The area hosting the quarry: the stand-alone sandbox here; test_reach_east_region.gd overrides it with the
## real Hallowmere Reach (null = unavailable -> the geometry tests are skipped there).
func _make_host() -> Node3D:
	return SandboxScript.new()


func before_each() -> void:
	fresh_state()
	if _box == null and not _tried:
		_tried = true
		_box = _make_host()
		if _box != null:
			add_child(_box)
			await wait_physics(3)
	_set_graph_radius(GR)


func _set_graph_radius(r: float) -> void:
	_gr = r
	_gn = int(2.0 * _gr / STEP) + 1
	_walls.clear()


func _host_ok() -> bool:
	if _box == null or not is_instance_valid(_box):
		print("  (quarry host unavailable - skipped)")
		return false
	return true


func _quarry() -> Node3D:
	return District.district_root(_box)


func _set_gangway(on: bool) -> void:
	_quarry().winch.set_lowered(on, false)
	_walls.clear()
	await wait_physics(2)


# --- the walk graph ------------------------------------------------------------------------------------

func _pos(k: int) -> Vector2:
	var i := k % _gn
	var j := k / _gn
	return Vector2(Q.CENTER.x - _gr + float(i) * STEP, Q.CENTER.y - _gr + float(j) * STEP)


func _sample() -> PackedFloat32Array:
	var space := _box.get_world_3d().direct_space_state
	var ys := PackedFloat32Array()
	ys.resize(_gn * _gn)
	ys.fill(NAN)
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	for k in _gn * _gn:
		var p := _pos(k)
		if p.distance_to(Q.CENTER) > _gr:
			continue
		q.from = Vector3(p.x, 60.0, p.y)
		q.to = Vector3(p.x, -40.0, p.y)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var n: Vector3 = hit["normal"]
		if n.y < MIN_NY:
			continue
		var hp: Vector3 = hit["position"]
		q.from = hp + Vector3(0, 0.15, 0)
		q.to = hp + Vector3(0, 1.75, 0)
		if not space.intersect_ray(q).is_empty():
			continue
		ys[k] = hp.y
	return ys


func _blocked(space: PhysicsDirectSpaceState3D, a: int, b: int, ys: PackedFloat32Array) -> bool:
	var key := mini(a, b) * _gn * _gn + maxi(a, b)
	if _walls.has(key):
		return bool(_walls[key])
	var pa := _pos(a)
	var pb := _pos(b)
	var y := maxf(ys[a], ys[b])
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	var hit := false
	for dy in [0.45, 1.2]:
		q.from = Vector3(pa.x, y + float(dy), pa.y)
		q.to = Vector3(pb.x, y + float(dy), pb.y)
		if not space.intersect_ray(q).is_empty():
			hit = true
			break
		q.from = Vector3(pb.x, y + float(dy), pb.y)
		q.to = Vector3(pa.x, y + float(dy), pa.y)
		if not space.intersect_ray(q).is_empty():
			hit = true
			break
	_walls[key] = hit
	return hit


## Cells reachable from `start` (reverse = cells that can reach `start`).
func _bfs(ys: PackedFloat32Array, start: int, reverse: bool = false) -> PackedByteArray:
	var space := _box.get_world_3d().direct_space_state
	var seen := PackedByteArray()
	seen.resize(_gn * _gn)
	seen.fill(0)
	if start < 0:
		return seen
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var k := queue[head]
		head += 1
		var i := k % _gn
		for nk in [k - 1, k + 1, k - _gn, k + _gn]:
			if nk < 0 or nk >= _gn * _gn or seen[nk] == 1 or is_nan(ys[nk]):
				continue
			if (nk == k - 1 and i == 0) or (nk == k + 1 and i == _gn - 1):
				continue
			var up := (ys[nk] - ys[k]) if not reverse else (ys[k] - ys[nk])
			if up > CLIMB:
				continue
			if _blocked(space, k, nk, ys):
				continue
			seen[nk] = 1
			queue.append(nk)
	return seen


func _nearest_cell(ys: PackedFloat32Array, p: Vector2, y_hint: float = NAN, max_d: float = 3.0) -> int:
	var best := -1
	var bd := INF
	for k in _gn * _gn:
		if is_nan(ys[k]):
			continue
		var d := _pos(k).distance_to(p)
		if d > max_d or d >= bd:
			continue
		if not is_nan(y_hint) and absf(ys[k] - y_hint) > 1.2:
			continue
		bd = d
		best = k
	return best


## A reached cell within `r` (XZ) of p at about height y.
func _reached_near(ys: PackedFloat32Array, seen: PackedByteArray, p: Vector2, y: float, r: float = 2.2) -> bool:
	for k in _gn * _gn:
		if seen[k] == 1 and absf(ys[k] - y) < 1.2 and _pos(k).distance_to(p) <= r:
			return true
	return false


func _start(ys: PackedFloat32Array) -> int:
	var sp: Vector2 = Reach.SPAWNS["quarry_arch"]["pos"]
	return _nearest_cell(ys, sp, _box.height_at(sp.x, sp.y))


func _node_targets(include_shelf: bool) -> Array:
	var out: Array = []
	var qr := _quarry()
	for id in qr.nodes:
		var n: Node3D = qr.nodes[id]
		var shelf := Shape.is_shelf(n.position.x, n.position.z)
		if shelf == include_shelf:
			out.append([String(id), Vector2(n.position.x, n.position.z), n.position.y])
	return out


# --- tests ------------------------------------------------------------------------------------------------

func test_sandbox_built_and_shaped() -> void:
	if not _host_ok():
		return
	var qr := _quarry()
	assert_not_null(qr, "district root")
	assert_true(bool(qr.shaped), "terrain shaped (district levels found)")
	assert_true(bool(Shape.last_report.get("ok", false)), "shape report ok")
	assert_true(qr.nodes.size() >= 30, "harvest nodes built: %d" % qr.nodes.size())
	assert_not_null(qr.winch, "winch")
	assert_not_null(qr.lamp, "lamp")
	assert_not_null(qr.arena, "arena")
	assert_eq(qr.arena.pillars.size(), Q.PILLARS.size(), "pillars")
	assert_true(qr.spawners.has("hr_sp_quarry_warden") and qr.spawners.has("hr_sp_bellcaps"), "both spawners")
	print("  quarry district build %.1f ms (floor %.2f)" % [float(qr.build_ms), float(qr.floor_y)])
	for id in qr.nodes:
		var n: Node3D = qr.nodes[id]
		assert_almost(n.position.y, float(_box.height_at(n.position.x, n.position.z)), 0.02, "node on the ground: " + String(id))
		assert_eq(String(_box.get_zone_at(n.global_position)), Q.LANDMARK, "node in zone hr_quarry (music, bond xp): " + String(id))
	for piece in [qr.winch, qr.lamp, qr.note, qr.arena]:
		assert_eq(String(_box.get_zone_at((piece as Node3D).global_position)), Q.LANDMARK, "%s in zone hr_quarry" % piece.name)


func test_no_holes_and_spawn_clearance() -> void:
	if not _host_ok():
		return
	var space := _box.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	var holes := 0
	var under := 0
	var x := Q.CENTER.x - 29.5
	while x <= Q.CENTER.x + 29.5:
		var z := Q.CENTER.y - 29.5
		while z <= Q.CENTER.y + 29.5:
			if Vector2(x, z).distance_to(Q.CENTER) <= 29.5:
				q.from = Vector3(x, 60.0, z)
				q.to = Vector3(x, -40.0, z)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					holes += 1
				elif (hit["position"] as Vector3).y < _cell_min(x, z) - 0.05:
					under += 1
			z += 1.0
		x += 1.0
	assert_eq(holes, 0, "samples with no floor")
	assert_eq(under, 0, "samples whose first floor is below the terrain")
	var xf: Transform3D = _box.get_spawn("quarry_arch")
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.collision_mask = MASK
	sq.transform = Transform3D(Basis(), xf.origin + Vector3(0, 0.85, 0))
	assert_true(space.intersect_shape(sq, 4).is_empty(), "the quarry-arch spawn has capsule clearance")
	q.from = xf.origin + Vector3(0, 0.5, 0)
	q.to = xf.origin + Vector3(0, -0.6, 0)
	assert_false(space.intersect_ray(q).is_empty(), "the spawn stands on the floor")


func test_walk_without_the_winch() -> void:
	if not _host_ok():
		return
	await _set_gangway(false)
	var t0 := Time.get_ticks_msec()
	var ys := _sample()
	var s := _start(ys)
	assert_true(s >= 0, "start cell at the arch spawn")
	var seen := _bfs(ys, s)
	var standable := 0
	var reached := 0
	for k in ys.size():
		if not is_nan(ys[k]):
			standable += 1
		if seen[k] == 1:
			reached += 1
	assert_true(standable > 10000 and reached > 8000, "graph size: %d standable, %d reached" % [standable, reached])
	print("  walk graph: %d standable cells, %d reached from the arch" % [standable, reached])
	for t in _node_targets(false):
		assert_true(_reached_near(ys, seen, t[1], float(t[2])), "reachable without the winch: " + String(t[0]))
	for t in _node_targets(true):
		assert_false(_reached_near(ys, seen, t[1], float(t[2]), 3.0), "the shelf node %s is NOT reachable before the winch" % t[0])
	var qr := _quarry()
	var wp: Vector3 = qr.winch.position
	assert_true(_reached_near(ys, seen, Vector2(wp.x, wp.z), wp.y), "the winch drum")
	var np: Vector3 = qr.note.position
	assert_true(_reached_near(ys, seen, Vector2(np.x, np.z), np.y), "the quarry log")
	var lp: Vector3 = qr.lamp.position
	assert_false(_reached_near(ys, seen, Vector2(lp.x, lp.z), lp.y, 3.5), "the lamp is up on the gated shelf")
	var ap: Vector3 = qr.arena.position
	assert_true(_reached_near(ys, seen, Vector2(ap.x, ap.z), ap.y, 1.0), "the arena centre")
	for pl in qr.arena.pillars:
		var pp: Vector3 = (pl as Node3D).global_position
		assert_true(_reached_near(ys, seen, Vector2(pp.x, pp.z), pp.y, 1.9), "around pillar " + String(pl.pillar_id))
	var mouth := Shape.to_world(Vector2(22.0, -12.5))
	assert_true(_reached_near(ys, seen, mouth, _box.height_at(mouth.x, mouth.y), 1.0), "the north mouth (Bellhouse road) joins the bench")
	# nothing in the lower quarry traps her
	var back := _bfs(ys, s, true)
	var stuck := _stuck_patches(ys, back, false)
	assert_eq(stuck.size(), 0, "patches that can't walk back to the arch: %s" % str(stuck))
	print("  walk graph (no winch) %d ms" % (Time.get_ticks_msec() - t0))


func test_walk_with_the_winch() -> void:
	if not _host_ok():
		return
	await _set_gangway(true)
	var ys := _sample()
	var s := _start(ys)
	var seen := _bfs(ys, s)
	for t in _node_targets(true):
		assert_true(_reached_near(ys, seen, t[1], float(t[2])), "reachable with the gangway: " + String(t[0]))
	var lp: Vector3 = _quarry().lamp.position
	assert_true(_reached_near(ys, seen, Vector2(lp.x, lp.z), lp.y), "the lamp")
	var back := _bfs(ys, s, true)
	var stuck := _stuck_patches(ys, back, true)
	assert_eq(stuck.size(), 0, "patches that can't walk back to the arch: %s" % str(stuck))
	var lamp_cell := _nearest_cell(ys, Vector2(lp.x, lp.z), lp.y)
	assert_true(lamp_cell >= 0 and back[lamp_cell] == 1, "from the lamp she can walk all the way back")
	await _set_gangway(false)


## Connected groups (>= 6 cells, i.e. room for Krystal) of standable cells inside the quarry that are not in
## `back` (cannot reach the start). Shelf cells are ignored when the gangway is raised.
func _stuck_patches(ys: PackedFloat32Array, back: PackedByteArray, include_shelf: bool) -> Array:
	var done := PackedByteArray()
	done.resize(_gn * _gn)
	done.fill(0)
	var out: Array = []
	for k in _gn * _gn:
		if done[k] == 1 or is_nan(ys[k]) or back[k] == 1:
			continue
		var p := _pos(k)
		if p.distance_to(Q.CENTER) > 29.0:
			continue
		if not include_shelf and Shape.is_shelf(p.x, p.y):
			continue
		var comp := PackedInt32Array([k])
		done[k] = 1
		var head := 0
		while head < comp.size():
			var c := comp[head]
			head += 1
			for nk in [c - 1, c + 1, c - _gn, c + _gn]:
				if nk < 0 or nk >= _gn * _gn or done[nk] == 1 or is_nan(ys[nk]) or back[nk] == 1:
					continue
				if absf(ys[nk] - ys[c]) > CLIMB:
					continue
				done[nk] = 1
				comp.append(nk)
		if comp.size() >= 6:
			out.append("%d cells near %s y=%.1f" % [comp.size(), _pos(k), ys[k]])
	return out


## Lowest corner of the terrain cell under (x, z): the engine's heightmap collider splits cells along the other
## diagonal than height_at(), so on a step cell the collision surface lies anywhere down to this.
func _cell_min(x: float, z: float) -> float:
	var x0 := floorf(x)
	var z0 := floorf(z)
	return minf(minf(_box.height_at(x0, z0), _box.height_at(x0 + 0.999, z0)), minf(_box.height_at(x0, z0 + 0.999), _box.height_at(x0 + 0.999, z0 + 0.999)))


func _sweep(space: PhysicsDirectSpaceState3D, shape: Shape3D, a: Vector3, b: Vector3, basis: Basis = Basis()) -> float:
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = shape
	sq.collision_mask = MASK
	sq.transform = Transform3D(basis, a)
	sq.motion = b - a
	var r := space.cast_motion(sq)
	return float(r[0]) if r.size() > 0 else 0.0


func test_openings_are_wide_and_tall_enough() -> void:
	if not _host_ok():
		return
	await _set_gangway(true)
	var space := _box.get_world_3d().direct_space_state
	var w = _quarry().winch
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 2.4, 0.2)
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.6
	# gangway: from just above its foot to its top, 1.6 x 2.4 box oriented across the gangway
	var hinge: Vector3 = w.hinge
	var dirv: Vector3 = w.dir
	var foot: Vector3 = hinge + dirv * (w.length * cos(deg_to_rad(w.slope_deg))) + Vector3(0, -w.length * sin(deg_to_rad(w.slope_deg)), 0)
	var across := Vector3.UP.cross(dirv).normalized()
	var bb := Basis(across, Vector3.UP, across.cross(Vector3.UP).normalized())
	var lift := Vector3(0, 1.2 + 0.12, 0)
	var a := foot + (hinge - foot) * 0.06 + lift
	var b := hinge + (foot - hinge) * 0.04 + lift
	assert_almost(_sweep(space, box, a, b, bb), 1.0, 0.001, "a 1.6 x 2.4 m opening all along the gangway")
	assert_almost(_sweep(space, cap, a + Vector3(0, -0.4, 0), b + Vector3(0, -0.4, 0)), 1.0, 0.001, "a capsule walks the gangway")
	# bell gate at the top of the haul road
	var g0 := Shape.to_world(Vector2(-1.9, 0.0))
	var g1 := Shape.to_world(Vector2(1.0, 0.0))
	var y: float = _box.height_at(g1.x, g1.y) + 1.25
	var gb := Basis(Vector3(Q.AXIS_V.x, 0, Q.AXIS_V.y), Vector3.UP, Vector3(Q.AXIS_V.x, 0, Q.AXIS_V.y).cross(Vector3.UP).normalized())
	assert_almost(_sweep(space, box, Vector3(g0.x, y, g0.y), Vector3(g1.x, y, g1.y), gb), 1.0, 0.001, "the bell gate is a wide opening")
	# the haul road, apron -> L2, in straight segments along its centre line
	var pts := [Vector2(-20.0, 0.0), Vector2(-17.5, 0.0), Vector2(-12.0, 0.0), Vector2(-7.5, 0.0), Vector2(-2.0, 0.0), Vector2(0.5, 0.0)]
	for i in pts.size() - 1:
		var p0 := Shape.to_world(pts[i])
		var p1 := Shape.to_world(pts[i + 1])
		var a3 := Vector3(p0.x, _box.height_at(p0.x, p0.y) + 1.3, p0.y)
		var b3 := Vector3(p1.x, _box.height_at(p1.x, p1.y) + 1.3, p1.y)
		assert_almost(_sweep(space, box, a3, b3, gb), 1.0, 0.001, "haul road segment %d is open" % i)
	# the open arena floor: flat L2 everywhere except the pillars
	var q := PhysicsRayQueryParameters3D.new()
	q.collision_mask = MASK
	var ap: Vector3 = _quarry().arena.position
	var bumps := 0
	for i in 21:
		for j in 21:
			var p := Vector2(ap.x - 10.0 + float(i), ap.z - 10.0 + float(j))
			if p.distance_to(Vector2(ap.x, ap.z)) > Q.ARENA_RADIUS - 0.6:
				continue
			var near_pillar := false
			for pl in _quarry().arena.pillars:
				var pp: Vector3 = (pl as Node3D).global_position
				if p.distance_to(Vector2(pp.x, pp.z)) < Q.PILLAR_RADIUS + 0.4:
					near_pillar = true
			if near_pillar:
				continue
			q.from = Vector3(p.x, ap.y + 2.0, p.y)
			q.to = Vector3(p.x, ap.y - 1.0, p.y)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or absf((hit["position"] as Vector3).y - ap.y) > 0.08:
				bumps += 1
	assert_eq(bumps, 0, "obstacles on the open arena floor")
	await _set_gangway(false)


func test_build_time_and_determinism() -> void:
	if not _host_ok():
		return
	print("  sandbox: shape_terrain %.1f ms, district build %.1f ms" % [_box.shape_ms, _box.build_ms])
	assert_true(_box.shape_ms < 80.0, "shape_terrain %.1f ms" % _box.shape_ms)
	assert_true(_box.build_ms < 450.0, "district build %.1f ms" % _box.build_ms)
	var other: Node3D = SandboxScript.new()
	add_child(other)
	var a: Dictionary = _quarry().nodes
	var b: Dictionary = other.quarry.nodes
	assert_eq(a.keys().size(), b.keys().size(), "same node count")
	var ka: Array = a.keys()
	ka.sort()
	var kb: Array = b.keys()
	kb.sort()
	assert_eq(ka, kb, "same node ids")
	for id in ka:
		assert_true((a[id] as Node3D).position.is_equal_approx((b[id] as Node3D).position), "same position: " + String(id))
	var ya: Array = []
	for c in _quarry().get_children():
		ya.append(String(c.name))
	var yb: Array = []
	for c in other.quarry.get_children():
		yb.append(String(c.name))
	assert_eq(ya, yb, "same build structure")
	other.queue_free()
	await wait_frames(2)
