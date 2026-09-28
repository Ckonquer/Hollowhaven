extends "res://tests/test_case.gd"
## Surface world: terrain height vs collision, spawn points, zones, bounds, deterministic placement,
## restored-state toggling and the build-time budget. The world is built once and shared by the suite.

const SurfaceWorld := preload("res://src/world/surface/surface_world.gd")
const Vegetation := preload("res://src/world/surface/vegetation.gd")
const Terrain := preload("res://src/world/surface/terrain.gd")
const Layout := preload("res://data/world_layout.gd")
const WaygateScript := preload("res://src/world/surface/waygate.gd")

var _w: Node3D = null


func _world() -> Node3D:
	if _w == null or not is_instance_valid(_w):
		fresh_state()
		_w = SurfaceWorld.new()
		add_child(_w)
		await wait_physics(3)
	return _w


func after_each() -> void:
	pass


func _ray_down(w: Node3D, x: float, z: float) -> Dictionary:
	var space := w.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -60.0, z))
	q.collision_mask = 1
	return space.intersect_ray(q)


func test_height_at_matches_collision() -> void:
	var w: Node3D = await _world()
	var pts: Array = [Vector2(0, 0), Vector2(0.37, 7.2), Vector2(-7.6, 3.3), Vector2(20.4, -12.8), Vector2(46.5, 44.3),
		Vector2(-55.2, 12.7), Vector2(66.1, -12.3), Vector2(-12.4, -54.9), Vector2(48.3, -63.7), Vector2(-8.1, 60.2),
		Vector2(90.5, 90.5), Vector2(-99.3, 10.1), Vector2(33.3, -95.5), Vector2(12.5, 33.7), Vector2(-73.1, -73.3)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 25:
		pts.append(Vector2(rng.randf_range(-100.0, 100.0), rng.randf_range(-100.0, 100.0)))
	var checked := 0
	var worst := 0.0
	for p in pts:
		var hit := _ray_down(w, p.x, p.y)
		if hit.is_empty():
			fail("no ground under %s" % p)
			continue
		if not String(hit["collider"].name).begins_with("TerrainBody"):
			continue   # a tree/rock/prop is on top here; height_at describes the ground only
		var hy: float = hit["position"].y
		var h: float = w.height_at(p.x, p.y)
		worst = maxf(worst, absf(hy - h))
		assert_almost(hy, h, 0.12, "height_at vs collision at %s" % p)
		checked += 1
	assert_true(checked >= 25, "enough terrain samples checked (%d)" % checked)
	print("    height_at worst deviation %.3f m over %d samples" % [worst, checked])


func test_spawn_points_on_ground_and_clear() -> void:
	var w: Node3D = await _world()
	var space := w.get_world_3d().direct_space_state
	for id in Layout.SPAWN_HINTS:
		assert_true(w.spawns.has(id), "spawn %s registered" % id)
		var xf: Transform3D = w.get_spawn(id)
		var p := xf.origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0)
		q.collision_mask = 1 | 32
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "ground under spawn %s" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.35, "spawn %s sits on the ground" % id)
		# Nothing solid overlaps a player-sized capsule standing there.
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.6
		var sq := PhysicsShapeQueryParameters3D.new()
		sq.shape = cap
		sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 0.95, 0))
		sq.collision_mask = 1 | 32
		var overlaps := space.intersect_shape(sq, 4)
		assert_eq(overlaps.size(), 0, "spawn %s is not inside an object %s" % [id, str(overlaps.map(func(o): return o["collider"].name))])
		assert_true(w.is_inside_bounds(p, 3.0), "spawn %s inside the boundary" % id)
		assert_false(w.terrain.is_water(p.x, p.z), "spawn %s is dry" % id)
	# haven_start faces the Ward Stone (forward = -Z)
	var hs: Transform3D = w.get_spawn("haven_start")
	var fwd := -hs.basis.z
	var to_ws := Vector3(0, 0, -6) - hs.origin
	to_ws.y = 0.0
	assert_true(fwd.normalized().dot(to_ws.normalized()) > 0.95, "haven_start faces the Ward Stone")


func test_zones_safety_and_validation() -> void:
	var w: Node3D = await _world()
	assert_eq(w.get_zone_at(Vector3(0, 0, 2)), "haven")
	assert_true(w.is_safe_zone(Vector3(3, 0, 3)), "Haven is safe")
	assert_eq(w.get_zone_at(Vector3(-12, 2, -66)), "ruin")
	assert_false(w.is_safe_zone(Vector3(-12, 2, -66)), "ruin is not safe")
	assert_eq(w.get_zone_at(Vector3(54, 0, -74)), "mine_mouth")
	for id in Layout.LANDMARKS:
		var p: Vector2 = Layout.LANDMARKS[id]["pos"]
		assert_eq(w.get_zone_at(Vector3(p.x, 0, p.y)), id, "zone at landmark %s" % id)
	assert_null(w.validate_position(Vector3(200, 5, 0)), "outside the world is rejected")
	var pc: Vector2 = w.terrain.pond_center
	assert_null(w.validate_position(Vector3(pc.x, w.height_at(pc.x, pc.y), pc.y)), "deep pond water is rejected")
	var ok: Variant = w.validate_position(Vector3(2, w.height_at(2, 9) + 0.5, 9))
	assert_true(ok is Vector3, "a Haven lawn position is valid")
	assert_eq(w.surface_at(Vector3(pc.x, 0, pc.y)), "water")
	assert_eq(w.surface_at(Vector3(3, 0, 10)), "grass")


func test_boundary_walls_block_leaving() -> void:
	var w: Node3D = await _world()
	var space := w.get_world_3d().direct_space_state
	for dir_v in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(1, 0, 1).normalized(), Vector3(-1, 0, 1).normalized()]:
		var dir: Vector3 = dir_v
		var from: Vector3 = dir * 80.0
		from.y = w.height_at(from.x, from.z) + 1.0
		var to: Vector3 = from + dir * 60.0
		to.y = from.y
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "something stops a walk out of the world toward %s" % dir)
		if not hit.is_empty():
			var hp: Vector3 = hit["position"]
			assert_true(Vector2(hp.x, hp.z).length() < 128.0, "stopped inside the terrain toward %s" % dir)


func test_placement_is_deterministic_and_complete() -> void:
	var t := Terrain.new()
	t.generate()
	var a: Dictionary = Vegetation.plan(t)
	var b: Dictionary = Vegetation.plan(t)
	for key in ["trees", "rocks", "ores", "bushes", "sticks", "stones", "tufts"]:
		var la: Array = a[key]
		var lb: Array = b[key]
		assert_eq(la.size(), lb.size(), "%s count stable" % key)
		for i in mini(la.size(), lb.size()):
			assert_eq(String(la[i]["id"]), String(lb[i]["id"]), "%s id stable" % key)
			assert_true((la[i]["pos"] as Vector3).is_equal_approx(lb[i]["pos"]), "%s position stable" % key)
	# ids unique across every harvestable
	var seen := {}
	for key in ["trees", "rocks", "ores", "bushes", "sticks", "stones", "tufts"]:
		for d in a[key]:
			var id := String(d["id"])
			assert_false(seen.has(id), "id %s unique" % id)
			seen[id] = true
	assert_true(a["trees"].size() >= 100, "plenty of trees (%d)" % a["trees"].size())
	assert_eq(a["ores"].size(), 7, "seven copper veins")
	assert_true(a["bushes"].size() >= 12, "berry bushes (%d)" % a["bushes"].size())
	# The first quest must never stall: sticks/stones/grass near the Haven.
	for key in ["sticks", "stones", "tufts"]:
		var near := 0
		for d in a[key]:
			var p: Vector3 = d["pos"]
			if Vector2(p.x, p.z).length() <= 35.0:
				near += 1
				assert_false(t.is_water(p.x, p.z), "%s %s not in water" % [key, d["id"]])
		var need := 14 if key != "tufts" else 10
		assert_true(near >= need, "%d %s within 35 m of the Haven (need %d)" % [near, key, need])
	# Trees keep off paths, the stream and the Haven centre.
	for d in a["trees"]:
		var p: Vector3 = d["pos"]
		assert_true(t.path_at(p.x, p.z) < 0.05, "tree %s off the path" % d["id"])
		assert_true(t.stream_distance(p.x, p.z) > 4.0, "tree %s away from the stream" % d["id"])
		assert_true(Vector2(p.x, p.z).length() > 19.0, "tree %s outside the Haven centre" % d["id"])


func test_terrain_generation_is_deterministic() -> void:
	var t1 := Terrain.new()
	t1.generate()
	var t2 := Terrain.new()
	t2.generate()
	for p in [Vector2(0, 0), Vector2(33.3, -44.4), Vector2(-80, 70), Vector2(54, -74)]:
		assert_almost(t1.height_at(p.x, p.y), t2.height_at(p.x, p.y), 0.0001, "same height at %s" % p)
	# The Haven is flat around the build area and the stream flows downhill into the pond.
	for p in [Vector2(0, 0), Vector2(10, 5), Vector2(-12, -8), Vector2(6, 12)]:
		assert_almost(t1.height_at(p.x, p.y), 0.0, 0.35, "Haven flat at %s" % p)
	var pts: PackedVector3Array = t1.stream_pts
	for k in range(1, pts.size()):
		assert_true(pts[k].y <= pts[k - 1].y + 0.0001, "stream never flows uphill (sample %d)" % k)
	assert_almost(pts[pts.size() - 1].y, t1.pond_level, 0.01, "stream meets the pond level")


func test_restored_state_toggles_visuals() -> void:
	var w: Node3D = await _world()
	w._apply_restored_state(true)
	assert_true(w.landmarks.restore_group.visible, "lanterns and garlands shown")
	assert_true(w.bloom_root.visible, "bloom flowers shown")
	assert_almost(float(w.landmarks.ward_stone.restored_amount), 1.0, 0.001, "ward stone bright")
	assert_almost(float(w.sky.warmth), 1.0, 0.001, "sky warmed")
	w._apply_restored_state(false)
	assert_false(w.landmarks.restore_group.visible, "restoration decor hidden again")
	assert_false(w.bloom_root.visible, "bloom hidden again")


func test_build_time_budget() -> void:
	var w: Node3D = await _world()
	var total := float(w.build_times.get("total", 99999.0))
	print("    surface build: %.0f ms %s" % [total, str(w.build_times)])
	# Generous: the target is < 1 s on a desktop; tests may run on a loaded machine.
	assert_true(total < 4000.0, "surface builds in reasonable time (%.0f ms)" % total)


func test_structure_mask_and_surface_queries() -> void:
	var w: Node3D = await _world()
	GameState.structures.clear()
	var uid := GameState.add_structure("workbench", Vector3(5, 0, 5), 0.0)
	w.rebuild_structure_mask()
	assert_almost(w.structure_mask.get_pixel(128 + 5, 128 + 5).r, 1.0, 0.01, "workbench footprint masked (grass/flowers hidden)")
	assert_almost(w.structure_mask.get_pixel(128 - 5, 128 - 5).r, 0.0, 0.01, "elsewhere clear")
	GameState.remove_structure(uid)
	w.rebuild_structure_mask()
	assert_almost(w.structure_mask.get_pixel(133, 133).r, 0.0, 0.01, "cleared after removal")
	var body: Node = w.find_child("TerrainBody", true, false)
	assert_not_null(body, "terrain body exists")
	var pc: Vector2 = w.terrain.pond_center
	assert_eq(String(body.get_surface_at(Vector3(pc.x, 0, pc.y))), "water", "pond is water")
	var sp: Vector3 = w.terrain.stream_pts[60]
	assert_eq(String(body.get_surface_at(sp)), "water", "stream centre is water")
	assert_eq(String(body.get_surface_at(Vector3(2, 0, 9))), "grass", "Haven lawn is grass")
	assert_eq(String(body.get_meta("surface", "")), "grass", "meta defaults to grass")


func test_play_restoration_completes() -> void:
	var w: Node3D = await _world()
	w._apply_restored_state(false)
	GameState.set_flag("ward_restored", true)
	var t0 := Time.get_ticks_msec()
	await w.play_restoration()
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	assert_true(secs >= 8.0 and secs <= 14.0, "restoration lasts about 10 s (%.1f s)" % secs)
	assert_false(bool(w.restoring), "no longer restoring")
	assert_true(w.landmarks.restore_group.visible, "lanterns and garlands stay")
	assert_almost(float(w.landmarks.ward_stone.restored_amount), 1.0, 0.01, "stone bright")
	await wait_frames(2)
	assert_null(w.find_child("LightColumn", true, false), "temporary effects cleaned up")
	assert_null(w.find_child("RestorationCamera", true, false), "cinematic camera removed")


## Walks a player-sized capsule (same floor settings as the player, but WITHOUT its step-up assist,
## so this is stricter than the real player) from `from` toward `to`. Returns where it ended up.
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
		var d := flat.normalized() * 4.0
		vy = 0.0 if body.is_on_floor() else vy - 20.0 * dt
		body.velocity = Vector3(d.x, vy, d.z)
		body.move_and_slide()
	var end := body.global_position
	body.queue_free()
	return end


func test_stream_crossings_are_walkable() -> void:
	var w: Node3D = await _world()
	var crossings: Array = w.water.crossings
	assert_eq(crossings.size(), Layout.STREAM_CROSSINGS.size(), "every crossing is built")
	for c in crossings:
		var center: Vector3 = c["pos"]
		var axis: Vector3 = c["axis"]
		for sgn in [1.0, -1.0]:
			var a: Vector3 = center - axis * 6.5 * float(sgn)
			var b: Vector3 = center + axis * 6.5 * float(sgn)
			a.y = w.height_at(a.x, a.z) + 0.2
			b.y = w.height_at(b.x, b.z)
			var end: Vector3 = await _walk(w, a, b)
			var miss := Vector2(end.x - b.x, end.z - b.z).length()
			assert_true(miss < 1.0, "%s at %s walkable (%s side; stopped %.1f m short at %s)" % [c["style"], center, "+" if sgn > 0.0 else "-", miss, end])
			if String(c["style"]) == "bridge":
				assert_true(end.y > w.height_at(end.x, end.z) - 0.3, "did not fall through the bridge")


## A save / recovery point on a bridge deck or stepping stone is dry footing even though the stream
## below it is deeper than 0.6 m; the open stream right beside the crossing is still refused.
func test_positions_on_stream_crossings_are_valid() -> void:
	var w: Node3D = await _world()
	var space := w.get_world_3d().direct_space_state
	for c in w.water.crossings:
		var center: Vector3 = c["pos"]
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center + Vector3.UP * 6.0, center + Vector3.DOWN * 6.0, 1))
		assert_false(hit.is_empty(), "walkway under the %s at %s" % [c["style"], center])
		if hit.is_empty():
			continue
		var top: Vector3 = (hit["position"] as Vector3) + Vector3.UP * 0.02
		var ok: Variant = w.validate_position(top)
		assert_true(ok is Vector3 and (ok as Vector3).distance_to(top) < 0.5, "standing on the %s at %s is a valid position (got %s)" % [c["style"], str(top), str(ok)])
		var bed := float(w.height_at(top.x, top.z))
		assert_true(float(w.water_level_at(top.x, top.z)) - bed > 0.6, "the %s spans deep water (the case that used to be refused)" % c["style"])
	# Deep open stream (bed samples far from every crossing) stays invalid.
	var pts: PackedVector3Array = w.terrain.stream_pts
	var refused := 0
	for i in range(0, pts.size(), 3):
		var sp: Vector3 = pts[i]
		var near := false
		for c in w.water.crossings:
			var cp: Vector3 = c["pos"]
			if Vector2(sp.x, sp.z).distance_to(Vector2(cp.x, cp.z)) < 6.0:
				near = true
		var h := float(w.height_at(sp.x, sp.z))
		if near or not w.is_inside_bounds(sp, 4.0) or not w.terrain.is_water(sp.x, sp.z) or float(w.water_level_at(sp.x, sp.z)) - h <= 0.6:
			continue
		assert_null(w.validate_position(Vector3(sp.x, h + 0.02, sp.z)), "deep open stream at (%.1f, %.1f) is refused" % [sp.x, sp.z])
		refused += 1
	assert_true(refused > 10, "checked deep open-stream samples (%d)" % refused)


## Chapter Two: the music director (src/audio/music_director.gd, tests/unit/test_audio_music_*.gd) owns the
## surface playlists now. The old play/rest cycle below is its fallback when the director is unavailable,
## so it is checked with the director switched off; the test after it checks the surface defers to it.
func test_music_rests_between_plays() -> void:
	var w: Node3D = await _world()
	if not Audio.has_sound(SurfaceWorld.MUSIC_DAY) or not Audio.has_sound(SurfaceWorld.MUSIC_NIGHT):
		return   # audio module not generated yet: nothing to cycle
	var had_director := Audio.music_director_active()
	Audio.set_music_director_enabled(false)
	var track: String = SurfaceWorld.MUSIC_NIGHT if bool(w.sky.is_night) else SurfaceWorld.MUSIC_DAY
	w.on_player_spawned(null)
	assert_eq(Audio.current_music(), track, "the surface theme starts when Krystal arrives")
	w._update_audio(SurfaceWorld.MUSIC_PLAY_SECONDS * 0.5)
	assert_eq(Audio.current_music(), track, "still playing half way through")
	w._update_audio(SurfaceWorld.MUSIC_PLAY_SECONDS * 0.5 + 1.0)
	assert_eq(Audio.current_music(), "", "then it fades out and the woods get a quiet spell")
	w._update_audio(SurfaceWorld.MUSIC_REST_SECONDS + 1.0)
	assert_eq(Audio.current_music(), track, "and the music comes back after the rest")
	# Someone else's track (e.g. the ending theme) is never cut off by the cycle.
	Audio.play_music("music_ending", 0.0)
	w._update_audio(SurfaceWorld.MUSIC_PLAY_SECONDS + 1.0)
	assert_eq(Audio.current_music(), "music_ending", "foreign music is left alone")
	w._audio_started = false
	Audio.stop_music(0.0)
	Audio.stop_ambience(0.0)
	await wait_frames(6)       # let the Audio decks and the audio server release the streams
	Audio.set_music_director_enabled(had_director)


func test_surface_music_is_left_to_the_director() -> void:
	var w: Node3D = await _world()
	if not Audio.music_director_active():
		return   # no director (script missing): the legacy cycle above applies
	Audio.stop_music(0.0)
	await wait_frames(2)
	w.on_player_spawned(null)
	assert_eq(Audio.current_music(), "", "arrival no longer starts a track itself: the director picks the playlist")
	Audio.play_music("music_night", 0.0)          # whatever the director chose
	w._update_audio(SurfaceWorld.MUSIC_PLAY_SECONDS + SurfaceWorld.MUSIC_REST_SECONDS + 1.0)
	assert_eq(Audio.current_music(), "music_night", "the old play/rest cycle never touches the director's music")
	w._audio_started = false
	Audio.stop_music(0.0)
	Audio.stop_ambience(0.0)
	await wait_frames(6)


func test_ruin_quest_cannot_stall_without_enemy_module() -> void:
	var w: Node3D = await _world()
	GameState.flags.erase("ruin_cleared")
	w.landmarks._build_spawners("res://does/not/exist.gd")
	assert_true(bool(GameState.get_flag("ruin_cleared")), "no spawner script -> the ruin counts as cleared (no softlock)")
	GameState.flags.erase("ruin_cleared")


## The expanded Haven (extra build regions + 4 m) is the "haven" zone in the real world too (Haven music, not the
## woods), while every landmark centre and the waygate's own zone are unchanged.
func test_expanded_haven_is_the_haven_zone() -> void:
	var w: Node3D = await _world()
	for p in [Vector2(-9, 22), Vector2(4, -25), Vector2(-19, -9), Vector2(-24, 1)]:
		var pos := Vector3(p.x, 0, p.y)
		assert_true(Vector2(p.x, p.y).length() > 20.0, "%s lies outside the legacy 20 m haven circle" % str(p))
		assert_true(w.is_safe_zone(pos), "%s is safe" % str(p))
		assert_eq(String(w.get_zone_at(pos)), "haven", "%s is the Haven, not the woods" % str(p))
	for id in Layout.LANDMARKS:
		var lp: Vector2 = Layout.LANDMARKS[id]["pos"]
		assert_eq(String(w.get_zone_at(Vector3(lp.x, 0, lp.y))), String(id), "zone at landmark %s unchanged" % id)
	var wp: Vector2 = Layout.CH2_POINTS["waygate"]
	assert_eq(String(w.get_zone_at(Vector3(wp.x, 0, wp.y + 1.5))), "ch2_waygate", "the waygate zone is unchanged")
	assert_eq(String(w.get_zone_at(Vector3(30, 0, 0))), "", "the woods beyond the Haven stay the woods")


## The Haven's Lanternwake keepsake is built by the surface annex loader, so it is back after a reload of a
## finished save (and absent before the ending); legacy vegetation stays the golden plan.
func test_lanternwake_keepsake_returns_with_the_surface() -> void:
	const KEEPSAKE := "res://src/world/story_ch2/haven_dressing.gd"
	var Annexes: Script = load("res://src/world/surface/annexes.gd")
	assert_true((Annexes.call("all_scripts") as Array).has(KEEPSAKE), "the annex loader runs the Haven keepsake")
	var s: Script = load(KEEPSAKE)
	assert_true(s != null and s.can_instantiate() and s.has_method("build"), "the keepsake has a static build(area)")
	var node_name := String(s.get_script_constant_map().get("NODE_NAME", ""))
	# Before the ending: the shared world (built from a fresh state) has no keepsake.
	var w: Node3D = await _world()
	assert_null(w.get_node_or_null(node_name), "nothing before chapter_two_complete")
	var plan_before: Dictionary = w.vegetation.plan_data
	var veg_count := 0
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		veg_count += (plan_before[k] as Array).size()
	# "Reload" a finished save: a new surface world built with the flag set.
	_w.queue_free()
	_w = null
	await wait_frames(4)
	fresh_state()
	GameState.set_flag("chapter_two_complete", true)
	var w2: Node3D = SurfaceWorld.new()
	add_child(w2)
	await wait_physics(2)
	var keep := w2.get_node_or_null(node_name)
	assert_not_null(keep, "the keepsake is back after the reload")
	var count := 0
	for c in w2.get_children():
		if String(c.name) == node_name:
			count += 1
	assert_eq(count, 1, "exactly one keepsake")
	if keep is Node3D:
		var stone := Vector2.ZERO
		for b in Layout.BUILD_AREA["blocked"]:
			if String((b as Dictionary).get("name", "")) == "Ward Stone":
				stone = (b as Dictionary)["center"]
		var kp: Vector3 = (keep as Node3D).global_position
		assert_true(Vector2(kp.x, kp.z).distance_to(stone) < 1.0, "it floats at the Ward Stone (%s)" % str(kp))
	# Running the loader again (e.g. the story tracker's ensure) never doubles it.
	Annexes.call("_run_annex", w2, KEEPSAKE)
	var count2 := 0
	for c in w2.get_children():
		if String(c.name) == node_name:
			count2 += 1
	assert_eq(count2, 1, "idempotent")
	# Golden guard (same record as test_c1x_world / test_flow_ch2_areas): the legacy plan is untouched.
	var parts: PackedStringArray = []
	var veg2 := 0
	for k in ["trees", "rocks", "ores", "bushes", "tufts", "sticks", "stones"]:
		veg2 += (w2.vegetation.plan_data[k] as Array).size()
		for e in w2.vegetation.plan_data[k]:
			var p: Vector3 = e["pos"]
			parts.append("%s:%.1f,%.1f" % [e["id"], p.x, p.z])
	assert_eq(veg2, veg_count, "the legacy vegetation plan is the same with the keepsake built")
	assert_eq("|".join(parts).md5_text(), "bd86320366013834cd23feefa16c4703", "legacy vegetation golden hash with the keepsake built")
	GameState.flags.erase("chapter_two_complete")
	w2.queue_free()
	await wait_frames(8)


## Near a REPAIRED surface waygate (<= 25 m) the Reach is prefetched exactly once (timing only; the call is skipped
## when Game has no prefetch_area). Never before the repair, never from farther away, never from the Reach side.
func test_waygate_prefetches_the_reach_once_when_near_and_lit() -> void:
	fresh_state()
	var rec := GDScript.new()
	rec.source_code = "extends RefCounted\nvar calls: Array = []\nfunc prefetch_area(area_id: String) -> void:\n\tcalls.append(area_id)\n"
	rec.reload()
	var recorder: Object = rec.new()
	var holder := Node3D.new()
	add_child(holder)
	var g: Node3D = WaygateScript.new()
	g.setup({"side": "surface", "target_area": "hallowmere_reach", "target_spawn": "waygate_arrival"})
	holder.add_child(g)
	g.position = Vector3(10, 0, 10)
	g.set("prefetcher", recorder)
	assert_false(g.check_prefetch(Vector3(10, 0, 12)), "not while the gate is cold")
	GameState.set_flag("chapter_one_complete", true)
	GameState.set_flag("ch2_accepted", true)
	assert_eq(String(g.state()), "woken")
	assert_false(g.check_prefetch(Vector3(10, 0, 12)), "not before the repair")
	GameState.set_flag("ch2_waygate_repaired", true)
	assert_false(g.check_prefetch(Vector3(10, 0, 10 + WaygateScript.PREFETCH_RADIUS + 0.5)), "not from farther away")
	assert_eq(recorder.get("calls"), [], "nothing requested yet")
	assert_true(g.check_prefetch(Vector3(10 + 18.0, 3.0, 10 + 16.0)), "within 25 m of the lit gate")
	assert_false(g.check_prefetch(Vector3(10, 0, 11)), "only once")
	assert_eq(recorder.get("calls"), ["hallowmere_reach"], "Game.prefetch_area('hallowmere_reach') once")
	assert_true(bool(g.has_prefetched()))
	# Without a prefetch_area method (Game before R05) the check is a silent no-op.
	var g2: Node3D = WaygateScript.new()
	g2.setup({"side": "surface", "target_area": "hallowmere_reach", "target_spawn": "waygate_arrival"})
	holder.add_child(g2)
	g2.set("prefetcher", RefCounted.new())
	assert_true(g2.check_prefetch(Vector3(0, 0, 1)), "guarded call, no error")
	var mirror: Node3D = WaygateScript.new()
	mirror.setup({"side": "reach"})
	holder.add_child(mirror)
	mirror.set("prefetcher", recorder)
	assert_false(mirror.check_prefetch(Vector3(0, 0, 1)), "the Reach side never prefetches")
	assert_eq((recorder.get("calls") as Array).size(), 1)
	holder.queue_free()
	await wait_frames(2)


func test_zz_cleanup() -> void:
	if _w != null and is_instance_valid(_w):
		_w.queue_free()
		_w = null
	await wait_frames(8)       # the world's looping 3D sounds release their playbacks a few frames later
