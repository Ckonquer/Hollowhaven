extends "res://tests/test_case.gd"
## AUDIT VERIFY (surface), now a regression test: surface_world.validate_position used to measure the
## stream depth down to the terrain bed, so it refused Krystal standing on a bridge / stepping stone (a
## pause-menu "Save & Quit" there resumed at the last arrival spawn). Fixed in surface_world.gd. The stream is ~0.60 m deep almost everywhere and the terrain
## collider differs from height_at() by a few cm, so a fix must NOT measure depth against the ray hit on
## plain terrain (that flips borderline open-water samples to "valid"). The rule mirrored in _proposed()
## only skips the depth check when the ground found is clearly above the stream bed (a deck / stone).
##  * test_a: the mirrored rule accepts every crossing and refuses every deep open-water sample.
##  * test_b: the REAL validate_position behaves the same (failed before the surface_world.gd fix).

const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")

var _w: Node3D = null


func after_each() -> void:
	if _w != null and is_instance_valid(_w):
		_w.queue_free()
	_w = null
	await wait_frames(2)


func _world() -> Node3D:
	fresh_state()
	_w = SurfaceWorld.new()
	add_child(_w)
	await wait_physics(3)
	return _w


## Mirror of area_base.validate_position (world + structures ray, headroom check).
func _base_ground(w: Node3D, pos: Vector3) -> Variant:
	var space := w.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 3.0, pos + Vector3.DOWN * 8.0)
	q.collision_mask = 1 | 32
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	var p: Vector3 = hit["position"] + Vector3.UP * 0.1
	var q2 := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.2, p + Vector3.UP * 1.8)
	q2.collision_mask = 1 | 32
	if not space.intersect_ray(q2).is_empty():
		return null
	return p


## Proposed surface rule: base ground first; the water-depth rule (unchanged, measured to the bed at the
## saved x/z) applies only when that ground is the stream bed, not a deck / stone standing above it.
func _proposed(w: Node3D, pos: Vector3) -> Variant:
	if not w.is_inside_bounds(pos, 2.0):
		return null
	var g: Variant = _base_ground(w, pos)
	if not (g is Vector3):
		return null
	var gp: Vector3 = g
	var t: RefCounted = w.terrain
	var standing_on_something: bool = gp.y - 0.1 > float(t.height_at(gp.x, gp.z)) + 0.25
	if not standing_on_something and t.is_water(pos.x, pos.z) and float(t.water_level_at(pos.x, pos.z)) - float(t.height_at(pos.x, pos.z)) > 0.6:
		return null
	return gp


## Top of each crossing's walkway at its centre.
func _crossing_tops(w: Node3D) -> Array:
	var out: Array = []
	var space := w.get_world_3d().direct_space_state
	for c in w.water.crossings:
		var center: Vector3 = c["pos"]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.UP * 6.0, center + Vector3.DOWN * 6.0, 1))
		if hit.is_empty():
			fail("no walkway at %s" % str(center))
			continue
		out.append({"style": String(c["style"]), "top": (hit["position"] as Vector3) + Vector3.UP * 0.02})
	return out


## Deep (> 0.6 m by height_at) stream centre-line samples at least 6 m from every crossing.
func _deep_open_water(w: Node3D) -> Array:
	var out: Array = []
	var t: RefCounted = w.terrain
	var pts: PackedVector3Array = t.stream_pts
	for i in range(0, pts.size(), 3):
		var sp: Vector3 = pts[i]
		var far := true
		for c in w.water.crossings:
			var cp: Vector3 = c["pos"]
			if Vector2(sp.x, sp.z).distance_to(Vector2(cp.x, cp.z)) < 6.0:
				far = false
		if not far or not w.is_inside_bounds(sp, 4.0):
			continue
		var h: float = float(t.height_at(sp.x, sp.z))
		if not t.is_water(sp.x, sp.z) or float(t.water_level_at(sp.x, sp.z)) - h <= 0.6:
			continue
		out.append(Vector3(sp.x, h + 0.02, sp.z))
	return out


func test_a_proposed_rule_accepts_crossings_and_still_refuses_open_water() -> void:
	var w: Node3D = await _world()
	var tops := _crossing_tops(w)
	assert_eq(tops.size(), 3, "three crossings")
	for c in tops:
		var top: Vector3 = c["top"]
		var prop: Variant = _proposed(w, top)
		assert_true(prop is Vector3 and (prop as Vector3).distance_to(top) < 0.5, "proposed rule accepts the %s at %s (got %s)" % [c["style"], str(top), str(prop)])
	var deep := _deep_open_water(w)
	assert_true(deep.size() > 10, "found deep open-water samples (%d)" % deep.size())
	for p in deep:
		assert_null(_proposed(w, p), "proposed rule refuses deep open water at %s" % str(p))
		assert_null(w.validate_position(p), "validate_position refuses deep open water at %s" % str(p))


func test_b_real_validate_position_accepts_crossings_and_refuses_open_water() -> void:
	var w: Node3D = await _world()
	for c in _crossing_tops(w):
		var top: Vector3 = c["top"]
		var ok: Variant = w.validate_position(top)
		assert_true(ok is Vector3 and (ok as Vector3).distance_to(top) < 0.5, "a save on the %s at %s is accepted (got %s)" % [c["style"], str(top.snapped(Vector3.ONE * 0.01)), str(ok)])
	for p in _deep_open_water(w):
		assert_null(w.validate_position(p), "deep open water at %s is still refused" % str(p))
