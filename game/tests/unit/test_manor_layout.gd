extends "res://tests/test_case.gd"
## Moonveil Manor interior geometry (area "moonveil_manor", data/manor_layout.gd): the real scene loads
## quickly, registers its spec spawns on collidable floor with a clear player capsule, every doorway is at
## least 1.6 m x 2.4 m (data AND physics), the probe routes through all five spaces and the side rooms are
## walkable (floor under every step, no step higher than the player can take, capsule clear), the gated hops
## are blocked until their flag is set, floors never let anyone fall through, rooms have no hole to the
## void, zones / safety follow spec §7.3, at most 3 shadowed lights, node ids are deterministic.

const Layout := preload("res://data/manor_layout.gd")
const SCENE := "res://scenes/moonveil_manor.tscn"
const CAP_R := 0.32
const CAP_H := 1.6
const STEP_MAX := 0.34          # player STEP_HEIGHT 0.3 + snap tolerance
const SAMPLE := 0.4

var _area: Node3D = null


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	await wait_frames(2)


func _load(flags: Array = []) -> Node3D:
	for f in flags:
		GameState.set_flag(String(f), true)
	var ps: PackedScene = load(SCENE)
	_area = ps.instantiate()
	add_child(_area)
	await wait_physics(3)
	return _area


func _space() -> PhysicsDirectSpaceState3D:
	return _area.get_world_3d().direct_space_state


## Floor height under (x, z) searching down from `from_y` (NAN if nothing).
func _floor(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, from_y - 6.0, z))
	q.collision_mask = 1 | 32
	var hit := _space().intersect_ray(q)
	if hit.is_empty():
		return NAN
	return float((hit["position"] as Vector3).y)


func _capsule_clear(p: Vector3, radius: float = CAP_R) -> Array:
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = CAP_H
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = cap
	sq.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, CAP_H * 0.5 + 0.12, 0))
	sq.collision_mask = 1 | 32
	return _space().intersect_shape(sq, 4).map(func(o: Dictionary) -> String: return str(o["collider"].get_path()) if o["collider"] is Node else "?")


## Walks a -> b in SAMPLE steps: floor under each sample, no step up/down beyond STEP_MAX, capsule clear.
## Returns "" if walkable, else the reason.
func _walk(a: Vector3, b: Vector3) -> String:
	var d := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(int(ceilf(d / SAMPLE)), 1)
	var prev_y := NAN
	for i in n + 1:
		var t := float(i) / float(n)
		var x := lerpf(a.x, b.x, t)
		var z := lerpf(a.z, b.z, t)
		var guess := lerpf(a.y, b.y, t)
		var y := _floor(x, z, guess + 1.2)
		if is_nan(y):
			return "no floor at (%.2f, %.2f)" % [x, z]
		if absf(y - guess) > 1.0:
			return "floor at (%.2f, %.2f) is %.2f, expected about %.2f" % [x, z, y, guess]
		if not is_nan(prev_y) and absf(y - prev_y) > STEP_MAX:
			return "step of %.2f m at (%.2f, %.2f)" % [absf(y - prev_y), x, z]
		prev_y = y
		var hits := _capsule_clear(Vector3(x, y, z), 0.3)
		if not hits.is_empty():
			return "blocked at (%.2f, %.2f): %s" % [x, z, str(hits)]
	return ""


# --- Loading, spawns, zones ------------------------------------------------------------------------------

func test_scene_loads_fast_and_registers_spec_spawns_on_clear_floor() -> void:
	var t0 := Time.get_ticks_msec()
	await _load()
	var ms := Time.get_ticks_msec() - t0
	assert_eq(String(_area.get("area_id")), "moonveil_manor")
	assert_false(bool(_area.get("placeholder") == true), "the real manor, not the wave A stand-in")
	assert_true(ms < 1500, "loads within the fade (%d ms incl. 3 physics frames)" % ms)
	var build_ms: float = float(_area.get("build_ms"))
	assert_true(build_ms < 1000.0, "build itself well under a second (%.0f ms)" % build_ms)
	print("    manor build %.0f ms, total load %d ms, %d batched instances" % [build_ms, ms, int(_area.builder.instances)])
	for sp in ["manor_entry", "manor_ballroom", "manor_balcony"]:
		assert_true((_area.spawns as Dictionary).has(sp), "spawn %s" % sp)
		var p: Vector3 = (_area.spawns[sp] as Transform3D).origin
		var fy := _floor(p.x, p.z, p.y + 1.5)
		assert_false(is_nan(fy), "floor under %s" % sp)
		assert_almost(fy, p.y, 0.2, "%s stands on the floor" % sp)
		assert_eq(_capsule_clear(Vector3(p.x, fy, p.z), 0.35), [], "%s has capsule clearance" % sp)
		assert_true(_area.is_safe_zone(p), "%s is safe (spec §1)" % sp)
		assert_true(_area.validate_position(p) is Vector3, "%s validates as a saved position" % sp)
	# Facing: the entry looks into the house (north).
	var e: Transform3D = _area.spawns["manor_entry"]
	assert_true((-e.basis.z).dot(Vector3.FORWARD) > 0.95, "manor_entry faces north into the hall")


func test_zones_and_safety_follow_the_spec() -> void:
	await _load()
	var ids: Array = (_area.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
	for z in Layout.ZONE_ORDER:
		assert_true(ids.has(z), "zone %s registered" % z)
	var expect := {Vector3(0, 0, -5): "mm_cloakroom", Vector3(0, 0, -20): "mm_hall", Vector3(6.5, 0, -20): "mm_hall",
		Vector3(0, 0, -41): "mm_ballroom", Vector3(-14, 0.6, -48): "mm_ballroom", Vector3(0, 0, -64.5): "mm_gallery",
		Vector3(16.5, 0, -64.5): "mm_gallery", Vector3(0, 1.8, -90): "mm_balcony", Vector3(11.5, 1.8, -89): "mm_balcony",
		Vector3(0, 1.0, -80.5): "mm_balcony"}
	for p in expect:
		assert_eq(_area.get_zone_at(p), String(expect[p]), "zone at %s" % str(p))
	assert_true(_area.is_safe_zone(Vector3(0, 0, -5)), "Cloakroom safe")
	assert_true(_area.is_safe_zone(Vector3(0, 1.8, -90)), "Balcony safe")
	for p in [Vector3(0, 0, -18), Vector3(0, 0, -47), Vector3(0, 0, -41), Vector3(0, 0, -64.5), Vector3(-14, 0.6, -48), Vector3(16.5, 0, -64.5)]:
		assert_false(_area.is_safe_zone(p), "%s is not safe" % str(p))
	assert_true(_area.is_safe_zone(Vector3(6.5, 0, -33.5)), "the ballroom rest candles are a safe circle")
	assert_null(_area.validate_position(Vector3(40, 0, -40)), "outside the manor is rejected")


# --- Openings -------------------------------------------------------------------------------------------------

func test_every_doorway_is_wide_and_tall_enough() -> void:
	await _load(["mm_ballroom_solved", "ch2_velour_defeated", "mm_balcony_shortcut"])
	var checked := 0
	for o in Layout.openings():
		if bool(o["mirror"]):
			continue
		assert_true(float(o["width"]) >= Layout.MIN_OPENING_W, "%s %s opening width %.2f" % [o["room"], o["side"], o["width"]])
		assert_true(float(o["height"]) >= Layout.MIN_OPENING_H, "%s %s opening height %.2f" % [o["room"], o["side"], o["height"]])
		if bool(o["blocked"]):
			continue
		# Physics: measure the free gap through the wall at its centre.
		var c: Vector3 = o["center"]
		var along_x := String(o["side"]) == "n" or String(o["side"]) == "s"
		var axis := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var mid := c + Vector3.UP * 1.2
		var width := _free(mid, axis, 3.0) + _free(mid, -axis, 3.0)
		var height := _free(c + Vector3.UP * 0.05, Vector3.UP, 6.0)
		assert_true(width >= Layout.MIN_OPENING_W - 0.02, "%s %s free width %.2f m" % [o["room"], o["side"], width])
		assert_true(height >= Layout.MIN_OPENING_H - 0.02, "%s %s free height %.2f m" % [o["room"], o["side"], height])
		checked += 1
	assert_true(checked >= 8, "measured %d doorways" % checked)


## Free distance from `from` along `dir` until world geometry (capped).
func _free(from: Vector3, dir: Vector3, cap: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * cap)
	q.collision_mask = 1 | 32
	var hit := _space().intersect_ray(q)
	if hit.is_empty():
		return cap
	return from.distance_to(hit["position"])


# --- Walkable connectivity -------------------------------------------------------------------------------------

func test_all_spaces_and_side_rooms_are_connected_on_foot() -> void:
	await _load(["mm_ballroom_solved", "ch2_velour_defeated", "mm_balcony_shortcut"])
	for r in Layout.ROUTES:
		var pts: Array = r["points"]
		for i in pts.size() - 1:
			var why := _walk(pts[i], pts[i + 1])
			assert_eq(why, "", "route %s hop %d %s -> %s" % [r["gate"], i, str(pts[i]), str(pts[i + 1])])
	# Every scrap and every key interactable has a walkable, clear approach point within reach.
	for s in Layout.SCRAPS:
		var ap: Vector3 = s["approach"]
		var fy := _floor(ap.x, ap.z, ap.y + 1.2)
		assert_false(is_nan(fy), "floor at the approach to %s" % s["id"])
		assert_eq(_capsule_clear(Vector3(ap.x, fy, ap.z), 0.3), [], "%s approach is clear" % s["id"])
		assert_true(Vector2(ap.x, ap.z).distance_to(Vector2((s["pos"] as Vector3).x, (s["pos"] as Vector3).z)) < 2.0, "%s within reach" % s["id"])


func test_gated_hops_are_blocked_until_their_flag() -> void:
	await _load()
	var shut := {"mm_ballroom_solved": [Vector3(0, 0, -49.8), Vector3(0, 0, -52.6)],
		"ch2_velour_defeated": [Vector3(0, 0, -76.8), Vector3(0, 0, -78.6)],
		"mm_balcony_shortcut": [Vector3(8.4, 1.8, -89.0), Vector3(10.2, 1.8, -89.0)]}
	for f in shut:
		var hop: Array = shut[f]
		assert_ne(_walk(hop[0], hop[1]), "", "closed before %s" % f)
	# The ungated routes work in a fresh save.
	for r in Layout.ROUTES:
		if String(r["gate"]) != "":
			continue
		var pts: Array = r["points"]
		for i in pts.size() - 1:
			assert_eq(_walk(pts[i], pts[i + 1]), "", "open route hop %d" % i)


# --- No fall-through, no escape ---------------------------------------------------------------------------------

func test_floors_collide_everywhere_and_rooms_are_closed() -> void:
	await _load(["mm_ballroom_solved", "ch2_velour_defeated", "mm_balcony_shortcut"])
	for id in Layout.ROOM_ORDER:
		var r: Dictionary = Layout.ROOMS[id]
		var x0 := float(r["x0"]) + 0.3
		var x1 := float(r["x1"]) - 0.3
		var z0 := float(r["z0"]) + 0.3
		var z1 := float(r["z1"]) - 0.3
		var misses := 0
		for ix in 5:
			for iz in 5:
				var x := lerpf(x0, x1, float(ix) / 4.0)
				var z := lerpf(z0, z1, float(iz) / 4.0)
				var want := Layout.floor_y(String(id), x, z)
				var y := _floor(x, z, want + 0.6)
				if is_nan(y) or absf(y - want) > 1.4:
					misses += 1
		assert_eq(misses, 0, "%s: floor under all 25 sample points" % id)
		# Rays out of the room at knee and head height always hit something (no hole into the void).
		var c := Vector3((float(r["x0"]) + float(r["x1"])) * 0.5, float(r["y"]) + 0.9, (float(r["z0"]) + float(r["z1"])) * 0.5)
		for k in 12:
			var a := TAU * float(k) / 12.0
			for hgt in [0.5, 1.4]:
				var from := Vector3(c.x, float(r["y"]) + float(hgt), c.z)
				if String(id) == "stair":
					from.y = Layout.floor_y("stair", c.x, c.z) + float(hgt)
				var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0, sin(a)) * 150.0)
				q.collision_mask = 1 | 32
				assert_false(_space().intersect_ray(q).is_empty(), "%s: ray %d at %.1f m leaves the house" % [id, k, hgt])


# --- Lights, environment, determinism ----------------------------------------------------------------------------

func test_environment_and_light_budget() -> void:
	await _load()
	var env: WorldEnvironment = null
	var light_child := false
	for c in _area.get_children():
		if c is WorldEnvironment:
			env = c
		light_child = light_child or c is Light3D
	assert_not_null(env, "WorldEnvironment")
	assert_true(light_child, "a light directly under the area root")
	if env != null:
		assert_false(env.environment.volumetric_fog_enabled, "no volumetric fog")
		assert_eq(env.environment.background_mode, Environment.BG_COLOR)
	var shadowed := 0
	var lights := 0
	for n in _area.find_children("*", "Light3D", true, false):
		lights += 1
		if (n as Light3D).shadow_enabled:
			shadowed += 1
	assert_true(shadowed <= Layout.MAX_SHADOW_LIGHTS, "shadowed lights %d <= 3" % shadowed)
	assert_true(shadowed >= 2, "the chandelier and the fixture cast shadows (%d)" % shadowed)
	assert_true(lights < 60, "a sane number of lights (%d)" % lights)
	var mm := _area.find_children("*", "MultiMeshInstance3D", true, false).size()
	assert_true(mm > 20 and mm < 400, "geometry is batched (%d MultiMeshInstance3D)" % mm)


## Named world nodes (not batches / shapes / meshes). Enemies and anything inside them (the Count, spawned
## helpers: modules of a later wave, free to name their children) are left out.
func _ids(a: Node3D) -> Array:
	var out: Array = []
	var enemies: Array = a.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.is_in_group("enemy"))
	for n in a.find_children("*", "", true, false):
		if n is MultiMeshInstance3D or n is CollisionShape3D or n is MeshInstance3D:
			continue
		if enemies.any(func(e: Node) -> bool: return e == n or e.is_ancestor_of(n)):
			continue
		out.append(str(a.get_path_to(n)))
	out.sort()
	return out


func test_node_ids_are_deterministic() -> void:
	await _load()
	var first := _ids(_area)
	var inst1: int = int(_area.builder.instances)
	_area.queue_free()
	await wait_frames(2)
	await _load()
	assert_eq(_ids(_area), first, "same named nodes on every build")
	assert_eq(int(_area.builder.instances), inst1, "same batched instance count")
	for want in ["Exit_front_door", "Exit_balcony_stair", "Exit_servants_up", "Exit_servants_down", "RestPoint_manor_ballroom",
			"RestPoint_manor_balcony", "CandleRoutePuzzle", "EmptyWaltz", "LookingGlass", "ManorLantern", "ShortcutGate",
			"SealedDoor_gallery", "SealedDoor_balcony", "SealedDoor_tapestry", "WardCandle_north", "WardCandle_southwest",
			"WardCandle_southeast", "VelvetScrap_mm_scrap_1", "VelvetScrap_mm_scrap_2", "VelvetScrap_mm_scrap_3", "PipkinSpot"]:
		assert_true(first.has(want), "node %s exists" % want)


## Wall dressing stands on plain wall: the hall's rib posts never cover a looking-glass (the lesson is read in
## them), the Powder Room door, a sconce or a crescent window; the Cloakroom's east sconces clear the
## servants' door; the Pipkin marker sits on the north balustrade's cap.
func test_wall_dressing_stays_on_plain_wall() -> void:
	var half := float(Layout.HALL_RIB_POST_W) * 0.5
	var hall: Dictionary = Layout.ROOMS["hall"]
	var west: Array = hall["walls"]["w"]
	var east: Array = hall["walls"]["e"]
	for rz in Layout.HALL_RIBS:
		var z0 := float(rz) - half
		var z1 := float(rz) + half
		assert_true(z0 > float(hall["z0"]) and z1 < float(hall["z1"]), "rib %.1f inside the hall" % rz)
		for o in west:
			# glass span + its gilt frame (0.07 + half a 0.16 bar) on each side
			var a := float(o[0]) - 0.15
			var b := float(o[1]) + 0.15
			assert_true(z1 <= a or z0 >= b, "rib post %.1f clears the looking-glass %.1f..%.1f" % [rz, o[0], o[1]])
		for o in east:
			assert_true(z1 <= float(o[0]) or z0 >= float(o[1]), "rib post %.1f clears the Powder Room door" % rz)
		for c in Layout.HALL_TRUE_CANDLES:
			assert_true(absf((c as Vector3).z - float(rz)) >= half + 0.1, "rib post %.1f clears the sconce at %.1f" % [rz, (c as Vector3).z])
		for wz in Layout.HALL_WINDOWS:
			assert_true(absf(float(wz) - float(rz)) >= half + 0.62 * 1.12, "rib post %.1f clears the crescent window at %.1f" % [rz, wz])
	# The practice candle stands before a looking-glass, with no post between (its reflection is the lesson).
	var pc: Vector3 = Layout.PRACTICE_CANDLE
	assert_true(west.any(func(o: Array) -> bool: return pc.z > float(o[0]) and pc.z < float(o[1])), "practice candle faces a glass")
	# Cloakroom: the sconce plates (0.14 wide) never touch the servants' door (1.2 wide + jambs).
	await _load()
	var door: Node3D = _area.get("exits")["servants_up"]
	var dz := door.global_position.z
	assert_almost(dz, float(Layout.SERVANTS_DOOR_CLOAK["pos"].z), 0.01)
	for sz in Layout.CLOAK_EAST_SCONCES:
		assert_true(absf(float(sz) - dz) >= 0.72 + 0.1, "cloakroom sconce at z %.1f clears the servants' door at %.1f" % [sz, dz])
		var r: Dictionary = Layout.ROOMS["cloakroom"]
		assert_true(float(sz) > float(r["z0"]) + 0.3 and float(sz) < float(r["z1"]) - 0.3, "sconce inside the cloakroom")
	# Pipkin: on the north balustrade's cap, inside the balcony's width.
	var bal: Dictionary = Layout.ROOMS["balcony"]
	var pk: Vector3 = Layout.PIPKIN_SPOT
	assert_true(pk.x > float(bal["x0"]) + 0.5 and pk.x < float(bal["x1"]) - 0.5, "Pipkin marker along the north rail")
	assert_true(pk.z <= float(bal["z0"]) and pk.z >= float(bal["z0"]) - Layout.WALL_T, "Pipkin marker over the parapet")
	assert_almost(pk.y, float(bal["y"]) + Layout.PARAPET_H + 0.12, 0.03, "Pipkin marker on the cap")
	var m: Node3D = _area.get("pipkin_spot")
	assert_true(m.is_in_group("pipkin_spot") and m.global_position.is_equal_approx(pk), "marker node for the later wave")
	# Nothing stands on the rail where the bat will be (no plant or pumpkin within 0.6 m in XZ).
	for p in [Vector3(-8.5, 0, -96.5), Vector3(-6.0, 0, -96.3), Vector3(-5.3, 0, -96.5)]:
		assert_true(Vector2(p.x - pk.x, p.z - pk.z).length() > 0.6, "clear of the balcony decor at %s" % str(p))


func test_manor_never_touches_the_music() -> void:
	var files := ["res://src/world/areas_ch2/moonveil_manor_world.gd", "res://src/world/reach/districts/manor_grounds.gd"]
	var d := DirAccess.open("res://src/world/manor")
	if d != null:
		for f in d.get_files():
			if f.ends_with(".gd"):
				files.append("res://src/world/manor/" + f)
	for f in files:
		var src := FileAccess.get_file_as_string(String(f))
		assert_false(src.contains("play_music(") or src.contains("stop_music("), "%s never calls Audio.play_music / stop_music" % f)
	assert_true(files.size() >= 14, "scanned the manor module (%d files)" % files.size())
