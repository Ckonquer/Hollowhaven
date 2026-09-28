extends "res://tests/test_case.gd"
## The Hushed Works, rooms 1-8 (works module C7): the room table contract (spec §10 x ranges, floors, the fixed
## hub east door), the merged table with and without the deep rooms, spawns on the floor with capsule
## clearance, openings / headroom, no-escape rays, walkable connectivity along every authored route (critical
## path 1 -> 7, loop A, the three line branches, the shortcut home, the ward door), no fall-through, gates that
## block until opened, determinism and the build-time budget; the Hall of Closed Eyes' single Borrowed Wisp
## (hw_sp_eyes_wisp: registered enemy, placed, on free floor out of every safe zone, clear of the hook, the
## carvings and the openings).

const Layout := preload("res://data/works_layout.gd")
const Factory := preload("res://src/enemies/enemy_factory.gd")
const Geo := preload("res://src/world/works/works_geo.gd")
const HorrorData := preload("res://data/horror_events.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"
const MASK := 1 | 32
const CLEARANCE := 0.25

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


func _make_area(opts: Dictionary = {}) -> Node3D:
	var a: Node3D = load(WORLD).new()
	a.use_deep = bool(opts.get("use_deep", false))
	if opts.has("deep_rooms"):
		a.deep_rooms_override = opts["deep_rooms"]
	if opts.has("deep_builder"):
		a.deep_builder_override = opts["deep_builder"]
	add_child(a)
	await wait_physics(3)
	return a


func _space() -> PhysicsDirectSpaceState3D:
	return area.get_world_3d().direct_space_state


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return _space().intersect_ray(q)


func _center(p: Vector3) -> Vector3:
	return p + Vector3.UP * (CLEARANCE + cap.height * 0.5)


func _sweep(a: Vector3, b: Vector3) -> String:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, _center(a))
	q.collision_mask = MASK
	var start_hits := _space().intersect_shape(q, 4)
	if not start_hits.is_empty():
		return "start overlaps %s" % _names(start_hits)
	q.motion = b - a
	var r := _space().cast_motion(q)
	if r[0] < 1.0:
		var at := a.lerp(b, r[1])
		q.transform = Transform3D(Basis.IDENTITY, _center(at))
		q.motion = Vector3.ZERO
		return "blocked at %s by %s" % [str(at.snapped(Vector3.ONE * 0.1)), _names(_space().intersect_shape(q, 4))]
	return ""


func _names(hits: Array) -> String:
	var out := []
	for h in hits:
		var c: Object = h.get("collider")
		if c is Node:
			out.append(String((c as Node).get_path()).get_file())
	return ", ".join(out)


func _floor_below(p: Vector3) -> bool:
	return not _ray(p + Vector3.UP * 0.6, p + Vector3.DOWN * 0.8).is_empty()


func _check_path(path: Array, label: String) -> void:
	for i in path.size() - 1:
		var a: Vector3 = path[i]
		var b: Vector3 = path[i + 1]
		assert_eq(_sweep(a, b), "", "%s segment %d %s -> %s" % [label, i, str(a), str(b)])
		var n := maxi(int(a.distance_to(b) / 0.75), 1)
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n))
			if not _floor_below(p):
				fail("%s: no floor under %s" % [label, str(p.snapped(Vector3.ONE * 0.1))])
				break


## A small fake "room 9" standing in for the deep module: one box east of the hub door.
func _fake_deep_rooms() -> Dictionary:
	return {"test_winch": {"space": 9, "zone": "hw_winch", "x0": 40.0, "x1": 52.0, "z0": -4.0, "z1": 4.0, "y": -18.0, "h": 4.0,
		"open": {"w": [[-1.5, 1.5, 3.4]]}}}


func _fake_deep_build(a: Node3D, b: Object) -> void:
	b.begin("test_winch")
	b.shell("test_winch", Color("404040"), Color("505050"), Color("303030"))
	a.place_spawn("crossing_gate", Vector3(49.0, -18.0, 0.0), 90.0)
	a.add_safe_area(Vector3(49.0, -18.0, 0.0), 3.0)


# --- Table contract -----------------------------------------------------------------------------------------------------

func test_room_table_follows_the_spec() -> void:
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		assert_true(float(r["x0"]) >= -80.0 and float(r["x1"]) <= 40.0, "%s inside x [-80, 40]" % id)
		assert_true(float(r["x1"]) - float(r["x0"]) >= 1.6 and float(r["z1"]) - float(r["z0"]) >= 1.6, "%s is wide enough" % id)
		assert_true(float(r["h"]) >= 2.4, "%s ceiling height" % id)
		var ys: Array = [float(r["y"])]
		if r.get("slope") is Dictionary:
			ys = [float(r["slope"]["y0"]), float(r["slope"]["y1"])]
			assert_true(bool(r.get("custom", false)), "%s: sloped rooms are custom" % id)
		for y in ys:
			assert_true(float(y) >= -34.0 and float(y) <= -6.0, "%s floor %.1f inside y [-34, -6]" % [id, float(y)])
		assert_true(Layout.ZONES.has(String(r["zone"])), "%s zone is a spec zone" % id)
		for o in Geo.openings(r):
			assert_true(float(o[2]) - float(o[1]) >= 1.6, "%s %s opening width" % [id, o[0]])
			assert_true(float(o[3]) >= 2.4, "%s %s opening height" % [id, o[0]])
	# Rooms 1-8 use zones 1-8 only; every one of them has at least one room.
	for z in ["hw_landing", "hw_lockers", "hw_rails", "hw_sluice", "hw_bells", "hw_eyes", "hw_refuge", "hw_lightwell"]:
		var found := false
		for id in Layout.ROOMS:
			found = found or String(Layout.ROOMS[id]["zone"]) == z
		assert_true(found, "zone %s has a room" % z)
	# The fixed connection (spec §10): hub east wall at x 40, floor -18, door centred on z 0, opening toward +x.
	var hub: Dictionary = Layout.ROOMS["refuge"]
	assert_eq(float(hub["x1"]), 40.0, "hub east wall at x 40")
	assert_eq(float(hub["y"]), -18.0, "hub floor at y -18")
	var east: Array = hub["open"]["e"]
	assert_eq(east.size(), 1, "one east door")
	assert_almost((float(east[0][0]) + float(east[0][1])) * 0.5, 0.0, 0.001, "east door centred on z 0")
	assert_eq(Layout.HUB_EAST_DOOR, Vector3(40.0, -18.0, 0.0))


## Openings match on both sides of every connection between two table rooms.
func test_connections_open_on_both_sides() -> void:
	var rooms: Dictionary = Layout.ROOMS
	for id in rooms:
		var r: Dictionary = rooms[id]
		for o in Geo.openings(r):
			var side := String(o[0])
			var mid := (float(o[1]) + float(o[2])) * 0.5
			var p: Vector3
			match side:
				"n": p = Vector3(mid, 0, float(r["z0"]) - 0.5)
				"s": p = Vector3(mid, 0, float(r["z1"]) + 0.5)
				"w": p = Vector3(float(r["x0"]) - 0.5, 0, mid)
				"e": p = Vector3(float(r["x1"]) + 0.5, 0, mid)
			if id == "refuge" and side == "e":
				continue      # toward the deep rooms
			if id == "eyes" and side == "e" and mid < 25.0:
				continue      # the wrong door: a sealed cell behind a grate, not a room
			var other := ""
			for oid in rooms:
				if oid == id:
					continue
				var orr: Dictionary = rooms[oid]
				if p.x >= float(orr["x0"]) - 0.01 and p.x <= float(orr["x1"]) + 0.01 and p.z >= float(orr["z0"]) - 0.01 and p.z <= float(orr["z1"]) + 0.01:
					other = String(oid)
			assert_ne(other, "", "%s %s opening at %s leads into a room" % [id, side, str(p)])


# --- Built area -----------------------------------------------------------------------------------------------------------

func test_builds_without_the_deep_rooms() -> void:
	var t0 := Time.get_ticks_msec()
	area = await _make_area({"use_deep": false})
	var ms := Time.get_ticks_msec() - t0
	assert_eq(area.area_id, "hushed_works")
	assert_false(bool(area.deep_present), "no deep rooms")
	assert_eq((area.rooms as Dictionary).size(), Layout.ROOMS.size(), "the table is rooms 1-8")
	for id in Layout.REQUIRED_SPAWNS:
		assert_true(area.spawns.has(id), "spawn %s registered" % id)
	assert_eq((area.deep_spawn_fallbacks as Array).size(), 3, "three deep spawns fall back to the hub")
	var zone_ids: Array = (area.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
	for z in Layout.ZONES:
		assert_true(zone_ids.has(z), "zone %s registered" % z)
	assert_true(ms < 1500, "builds under 1.5 s incl. 3 physics frames (%d ms; %s)" % [ms, str(area.build_times)])
	var mm := 0
	for n in area.find_children("*", "MultiMeshInstance3D", true, false):
		mm += (n as MultiMeshInstance3D).multimesh.instance_count
	assert_true(mm > 1000, "batched instances (%d)" % mm)
	print("  works build: %d ms, %d batched instances, times %s" % [ms, mm, str(area.build_times)])


func test_merges_the_deep_table_and_builder() -> void:
	area = await _make_area({"deep_rooms": _fake_deep_rooms(), "deep_builder": Callable(self, "_fake_deep_build")})
	assert_true(bool(area.deep_present), "deep rooms present")
	assert_true(bool(area.deep_built), "the deep builder ran (no stub)")
	assert_true((area.rooms as Dictionary).has("test_winch"), "merged table has the deep room")
	assert_true((area.rooms as Dictionary).has("refuge"), "and rooms 1-8")
	assert_eq(area.get_zone_at(Vector3(46.0, -18.0, 0.0)), "hw_winch", "deep zone from the merged table")
	assert_eq(area.room_at(Vector3(46.0, -17.0, 0.0)), "test_winch")
	assert_true(area.spawns.has("crossing_gate"), "deep module registered crossing_gate")
	assert_false((area.deep_spawn_fallbacks as Array).has("crossing_gate"), "no fallback for a registered deep spawn")
	assert_true((area.deep_spawn_fallbacks as Array).has("bell_throat"), "the others still fall back")
	assert_almost((area.spawns["crossing_gate"] as Transform3D).origin.x, 49.0, 0.01)
	# A deep id clashing with rooms 1-8 keeps the rooms 1-8 entry.
	var m := Geo.merge_rooms(Layout.ROOMS, {"refuge": {"x0": 0.0}})
	assert_eq(m["conflicts"], ["refuge"])
	assert_eq(float(m["rooms"]["refuge"]["x1"]), 40.0)
	# Through the open ward door into the deep room.
	for f in ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]:
		GameState.set_flag(f, true)
	await wait_physics(2)
	_check_path([Vector3(38.0, -18.0, 1.0), Vector3(39.4, -18.0, 0.0), Vector3(44.0, -18.0, 0.0)], "through the ward door")


## A deep room table without a working deep builder (rooms_deep.gd missing or failing to load) still closes the
## far side of the ward door with the collapsed stub, and every spawn still exists.
func test_deep_table_without_a_builder_gets_the_stub() -> void:
	area = await _make_area({"deep_rooms": _fake_deep_rooms()})
	assert_true(bool(area.deep_present), "deep rooms in the merged table")
	assert_false(bool(area.deep_built), "but no deep builder ran")
	for id in Layout.REQUIRED_SPAWNS:
		assert_true(area.spawns.has(id), "spawn %s registered" % id)
	for f in ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]:
		GameState.set_flag(f, true)
	await wait_physics(2)
	assert_true(bool(area.doors["ward_gate"].is_open), "the ward door opened")
	assert_false(_ray(Vector3(38.0, -17.0, 0.0), Vector3(120.0, -17.0, 0.0)).is_empty(), "it opens onto the stub, not the void")
	assert_false(_ray(Vector3(42.0, -17.5, 0.0), Vector3(42.0, -30.0, 0.0)).is_empty(), "the stub has a floor")


func test_every_spawn_is_on_the_floor_with_capsule_clearance() -> void:
	area = await _make_area()
	var q := PhysicsShapeQueryParameters3D.new()
	var c := CapsuleShape3D.new()
	c.radius = 0.35
	c.height = 1.6
	q.shape = c
	q.collision_mask = MASK
	for id in Layout.REQUIRED_SPAWNS:
		var p: Vector3 = (area.get_spawn(id) as Transform3D).origin
		var hit := _ray(p + Vector3.UP * 0.5, p + Vector3.DOWN * 1.5)
		assert_false(hit.is_empty(), "%s has ground below" % id)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.3, "%s ground height" % id)
		assert_true(_ray(p + Vector3.UP * 0.2, p + Vector3.UP * 2.4).is_empty(), "%s has 2.4 m headroom" % id)
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP * 1.05)
		assert_true(_space().intersect_shape(q, 4).is_empty(), "%s capsule is free" % id)
		assert_ne(area.room_at(p), "", "%s lies inside a room" % id)
		assert_true(area.validate_position(p) is Vector3, "%s is a valid position" % id)
		assert_true(area.is_safe_zone(p), "%s stands in a safe zone" % id)


func test_zones_safety_and_heights() -> void:
	area = await _make_area()
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var c := Geo.room_center(r)
		assert_eq(area.get_zone_at(c + Vector3.UP * 0.3), String(r["zone"]), "zone at the centre of %s" % id)
	assert_true(area.is_safe_zone(Vector3(-70.0, -6.0, 2.0)), "the landing is safe")
	assert_true(area.is_safe_zone(Vector3(33.0, -18.0, 8.0)), "the refuge is safe")
	for p in [Vector3(-47.0, -7.0, 2.0), Vector3(-16.0, -11.0, 0.0), Vector3(26.0, -20.0, -31.0), Vector3(12.0, -16.0, 33.0),
			Vector3(-14.5, -13.0, 25.0), Vector3(32.5, -20.0, 30.0)]:
		assert_false(area.is_safe_zone(p), "%s is not safe" % str(p))
	assert_false(area.is_safe_zone(Vector3(-70.0, 0.0, 2.0)), "safety respects height")
	assert_false(area.is_safe_zone(Vector3(-14.0, 0.0, -7.0)), "the placeholder's unsafe test point stays unsafe")
	assert_true(area.is_safe_zone(Layout.CHECKPOINTS["hw_lockers"]["pos"]), "the lockers checkpoint nook is safe")
	assert_eq(area.get_zone_at(Vector3(-47.0, 40.0, 0.0)), "hw_lockers", "points outside every room fall back to the nearest")
	assert_null(area.validate_position(Vector3(0.0, 30.0, 100.0)), "outside the Works is rejected")


func test_openings_headroom_and_no_escape() -> void:
	area = await _make_area()
	for id in Layout.ROOMS:
		var r: Dictionary = Layout.ROOMS[id]
		var c := Geo.room_center(r)
		# Floors collide across the whole room (sampled grid), ceilings stay above head height.
		var nx := maxi(int((float(r["x1"]) - float(r["x0"])) / 1.5), 1)
		var nz := maxi(int((float(r["z1"]) - float(r["z0"])) / 1.5), 1)
		var missing := 0
		for i in nx + 1:
			for k in nz + 1:
				var x := lerpf(float(r["x0"]) + 0.3, float(r["x1"]) - 0.3, float(i) / float(nx))
				var z := lerpf(float(r["z0"]) + 0.3, float(r["z1"]) - 0.3, float(k) / float(nz))
				var fy := Geo.floor_y_at(r, x, z)
				if _ray(Vector3(x, fy + 0.5, z), Vector3(x, fy - 1.0, z)).is_empty():
					missing += 1
		assert_eq(missing, 0, "%s: floor collides everywhere (no fall-through)" % id)
		if bool(r.get("custom", false)):
			continue
		for k in 16:
			var a := TAU * float(k) / 16.0
			var dir := Vector3(cos(a), 0, sin(a))
			for h in [0.5, 1.5]:
				var from: Vector3 = c + Vector3.UP * float(h)
				if _ray(from, from + dir * 90.0).is_empty():
					fail("%s: ray %d escapes into the void at height %.1f" % [id, k, h])
		var cp := c + (Vector3(5.0, 0.0, 5.0) if id == "refuge" else Vector3.ZERO)     # the refuge centre is under its daylight shaft
		assert_false(_ray(cp + Vector3.UP * 1.0, cp + Vector3.UP * (float(r["h"]) + 2.0)).is_empty(), "%s has a ceiling" % id)
	# The hub's east door leads into the collapsed stub when there are no deep rooms (never the void).
	for f in ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]:
		GameState.set_flag(f, true)
	await wait_physics(2)
	var from := Vector3(30.0, -17.0, 0.0)
	assert_false(_ray(from + Vector3(0, 0, 5.0), Vector3(120.0, -17.0, 5.0)).is_empty(), "the hub east wall")
	assert_false(_ray(Vector3(38.0, -17.0, 0.0), Vector3(120.0, -17.0, 0.0)).is_empty(), "the open ward door ends in the stub")


func test_walkable_routes() -> void:
	GameState.set_flag("ch2_refuge_shortcut", true)
	area = await _make_area()
	for id in Layout.PATHS:
		_check_path(Layout.PATHS[id], String(id))


func test_gates_block_until_opened() -> void:
	area = await _make_area()
	var sc: Array = Layout.PATHS["to_shortcut"]
	assert_ne(_sweep(sc[3], sc[4]), "", "the barred drainage stair blocks")
	assert_ne(_sweep(Vector3(38.0, -18.0, 0.0), Vector3(43.0, -18.0, 0.0)), "", "the ward door blocks")
	assert_ne(_sweep(Vector3(-17.0, -13.0, 27.5), Vector3(-23.0, -13.0, 27.5)), "", "the great face hides the carvers' rest")
	assert_ne(_sweep(Vector3(32.0, -20.0, 32.5), Vector3(32.0, -20.0, 36.0)), "", "the brass shutter closes the alcove")
	GameState.set_flag("ch2_refuge_shortcut", true)
	GameState.set_flag(Layout.FLAG_EYES_ROUTE, true)
	GameState.set_flag("ch2_line_light", true)
	await wait_physics(2)
	assert_eq(_sweep(sc[3], sc[4]), "", "the drainage stair opens")
	assert_eq(_sweep(Vector3(-17.0, -13.0, 27.5), Vector3(-23.0, -13.0, 27.5)), "", "the carvers' rest opens")
	assert_eq(_sweep(Vector3(32.0, -20.0, 32.2), Vector3(32.0, -20.0, 35.8)), "", "the alcove opens")
	assert_ne(_sweep(Vector3(38.0, -18.0, 0.0), Vector3(43.0, -18.0, 0.0)), "", "two lines keep the ward door shut")
	GameState.set_flag("ch2_line_water", true)
	GameState.set_flag("ch2_line_bell", true)
	await wait_physics(2)
	assert_eq(_sweep(Vector3(38.0, -18.0, 0.0), Vector3(42.0, -18.0, 0.0)), "", "all three lines open it")


## Every interactable of rooms 1-8 has free floor within reach (1.8 m) inside a room.
func test_interactables_are_reachable() -> void:
	area = await _make_area()
	var q := PhysicsShapeQueryParameters3D.new()
	var c := CapsuleShape3D.new()
	c.radius = 0.35
	c.height = 1.6
	q.shape = c
	q.collision_mask = MASK
	var count := 0
	for n in area.get_tree().get_nodes_in_group("interactable"):
		if not area.is_ancestor_of(n) or not (n is Node3D):
			continue
		if n.get_parent() is Node3D and (n.get_parent() as Node3D).is_in_group("interactable"):
			continue
		var p := (n as Node3D).global_position
		if n.has_method("get_interaction") and (n.get_interaction(null) as Dictionary).is_empty() and String(n.name) != "Hang":
			continue
		count += 1
		var ok := false
		for dist in [0.9, 1.3, 1.8]:
			for k in 16:
				var a := TAU * float(k) / 16.0
				var s := p + Vector3(cos(a), 0, sin(a)) * float(dist)
				var r: String = area.room_at(s + Vector3.UP * 0.3)
				if r == "":
					continue
				var fy := Geo.floor_y_at(area.rooms[r], s.x, s.z)
				var fp := Vector3(s.x, fy, s.z)
				q.transform = Transform3D(Basis.IDENTITY, fp + Vector3.UP * (CLEARANCE + 0.8))
				if _space().intersect_shape(q, 1).is_empty() and _floor_below(fp):
					ok = true
					break
			if ok:
				break
		assert_true(ok, "interactable %s at %s is reachable" % [n.name, str(p.snapped(Vector3.ONE * 0.1))])
	assert_true(count >= 25, "interactables checked (%d)" % count)


## Integration pass 2 (P13): one small fixed Borrowed Wisp encounter in the Hall of Closed Eyes teaches the lantern
## reveal before the Choir (on Gentle the director's hw_wisp_drift never runs).
func test_eyes_wisp_spawner_is_valid_and_out_of_safe_zones() -> void:
	var id := "hw_sp_eyes_wisp"
	assert_true(Layout.SPAWNERS.has(id), "the Hall of Closed Eyes has its wisp spawner")
	if not Layout.SPAWNERS.has(id):
		return
	var d: Dictionary = Layout.SPAWNERS[id]
	assert_eq(String(d["enemy"]), "borrowed_wisp")
	assert_eq(int(d["count"]), 1, "one wisp, never a group")
	assert_almost(float(d["radius"]), 1.0, 0.001)
	assert_almost(float(d["respawn_minutes"]), 1440.0, 0.001, "a renewable encounter")
	assert_eq(String(d["quest_flag_on_clear"]), "", "nothing depends on it")
	assert_almost(float(d["wander_radius"]), 3.0, 0.001)
	assert_eq(String(d["clear_message"]), "")
	# registered and spawnable, and data/enemies.gd places it in this zone
	assert_true(Factory.SCRIPTS.has("borrowed_wisp") and Factory.can_spawn("borrowed_wisp"), "borrowed_wisp is registered and compiles")
	assert_true((ItemDB.enemy("borrowed_wisp").get("zones", []) as Array).has("hw_eyes"), "data zones name hw_eyes")
	# clear of the lantern hook, the carvings and every opening of the hall (nearest point of each span)
	var pos: Vector3 = d["pos"]
	var flat := Vector2(pos.x, pos.z)
	var hook := Layout.EYES_LANTERN_HOOK
	assert_true(flat.distance_to(Vector2(hook.x, hook.z)) >= 6.0, "6 m from the eyes_route lantern hook")
	for lore in ["lore_ch2_closed_eyes", "lore_ch2_eyes_route"]:
		var lp: Vector3 = Layout.LORE_SPOTS[lore]["pos"]
		assert_true(flat.distance_to(Vector2(lp.x, lp.z)) >= 6.0, "6 m from %s" % lore)
	var eyes: Dictionary = Layout.ROOMS["eyes"]
	var openings := Geo.openings(eyes)
	assert_eq(openings.size(), 4, "the hall's four openings (north way, wrong door, bells way, carvers' rest)")
	for o in openings:
		var near := Vector2.ZERO
		match String(o[0]):
			"n":
				near = Vector2(clampf(pos.x, float(o[1]), float(o[2])), float(eyes["z0"]))
			"s":
				near = Vector2(clampf(pos.x, float(o[1]), float(o[2])), float(eyes["z1"]))
			"w":
				near = Vector2(float(eyes["x0"]), clampf(pos.z, float(o[1]), float(o[2])))
			"e":
				near = Vector2(float(eyes["x1"]), clampf(pos.z, float(o[1]), float(o[2])))
		assert_true(flat.distance_to(near) >= 6.0, "6 m from the %s opening %s (%.1f m)" % [String(o[0]), str(near), flat.distance_to(near)])
	assert_true(flat.distance_to(Vector2(Layout.FAKE_LUMI_POS.x, Layout.FAKE_LUMI_POS.z)) >= 6.0, "away from the Wrong Door cell")
	assert_true(pos.z - Layout.WRONG_DOOR_TRIGGER_Z > float(ItemDB.enemy("borrowed_wisp")["aggro_radius"]),
		"it does not notice her before the Wrong Door moment has begun")
	# the built area places it on free, walkable floor inside the hall, never in a safe zone
	area = await _make_area()
	assert_true((area.spawners as Dictionary).has(id), "the area placed it (data-driven)")
	assert_false((area.skipped_spawners as Array).has(id), "not skipped")
	var sp: Node3D = area.spawners.get(id)
	if sp != null:
		assert_true(sp.global_position.is_equal_approx(pos), "at its layout position")
		assert_eq(String(sp.get("enemy_id")), "borrowed_wisp")
	assert_eq(area.room_at(pos + Vector3.UP * 0.3), "eyes", "inside the Hall of Closed Eyes")
	assert_eq(area.get_zone_at(pos + Vector3.UP * 0.3), "hw_eyes")
	assert_true(area.validate_position(pos) is Vector3, "a valid position")
	var hit := _ray(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 1.5)
	assert_false(hit.is_empty(), "floor below")
	if not hit.is_empty():
		assert_almost(float(hit["position"].y), pos.y, 0.3, "floor height")
	assert_true(_ray(pos + Vector3.UP * 0.2, pos + Vector3.UP * 3.6).is_empty(), "headroom for its veiled float (2.9 m)")
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = MASK
	var reach: float = float(d["radius"]) + float(d["wander_radius"])
	for k in 9:
		var p := pos
		if k > 0:
			var a := TAU * float(k - 1) / 8.0
			p = pos + Vector3(cos(a), 0.0, sin(a)) * float(d["radius"])
		q.transform = Transform3D(Basis.IDENTITY, _center(p))
		assert_true(_space().intersect_shape(q, 4).is_empty(), "spawn point %s is free" % str(p))
		assert_true(_floor_below(p), "spawn point %s has floor" % str(p))
	for k in 16:
		var a := TAU * float(k) / 16.0
		for r in [0.0, float(d["radius"]), reach]:
			var p := pos + Vector3(cos(a), 0.0, sin(a)) * float(r)
			assert_false(area.is_safe_zone(p), "%s is not safe" % str(p))
	# and one real wisp appears there when Krystal walks down the hall
	if sp == null:
		return
	var probe := Node3D.new()
	area.add_child(probe)
	probe.global_position = pos + Vector3(0.0, 0.0, -9.0)
	sp.set("player_override", probe)
	var saved_mode := Game.mode
	Game.mode = "playing"
	sp.call("update_spawner")
	Game.mode = saved_mode
	var alive: Array = sp.get("alive")
	assert_eq(alive.size(), 1, "one Borrowed Wisp spawned")
	if alive.size() == 1:
		var w: Node3D = alive[0]
		assert_eq(String(w.get("enemy_id")), "borrowed_wisp")
		assert_eq(area.room_at(w.global_position + Vector3.UP * 0.3), "eyes", "inside the hall")
		assert_true(w.global_position.distance_to(pos) <= float(d["radius"]) + 0.3, "within its spawn radius")
	sp.call("despawn_all")
	await wait_frames(2)


func test_director_anchors_are_valid() -> void:
	area = await _make_area()
	var kinds := {}
	for id in HorrorData.WORKS_EVENTS:
		kinds[String(HorrorData.WORKS_EVENTS[id]["anchor"])] = true
	var per_zone := {}
	for a in area.anchors:
		var zone := String(a.get_meta("zone"))
		var kind := String(a.get_meta("kind"))
		assert_true(HorrorData.WORKS_ZONES.has(zone), "anchor zone %s is a works zone" % zone)
		assert_true(kinds.has(kind) or kind == "floor", "anchor kind %s is used by the works events" % kind)
		per_zone[zone] = int(per_zone.get(zone, 0)) + 1
		var p: Vector3 = (a as Node3D).global_position
		assert_eq(area.get_zone_at(p + Vector3.UP * 0.1), zone, "anchor %s lies in its zone" % a.name)
		if kind == "floor":
			assert_true(_floor_below(p), "floor anchor %s on the floor" % a.name)
	for z in ["hw_rails", "hw_sluice", "hw_bells", "hw_lightwell"]:
		assert_true(int(per_zone.get(z, 0)) >= 3, "%s has >= 3 anchors" % z)


func test_build_is_deterministic() -> void:
	area = await _make_area()
	var a1 := _fingerprint(area)
	area.queue_free()
	await wait_frames(2)
	area = await _make_area()
	var a2 := _fingerprint(area)
	assert_eq(a1["ids"], a2["ids"], "same persistent node ids")
	assert_eq(a1["hash"], a2["hash"], "same batched geometry")
	assert_true((a1["ids"] as Array).size() >= 10, "ids collected")


func _fingerprint(a: Node3D) -> Dictionary:
	var ids: Array = []
	for id in a.resource_nodes:
		ids.append("res:" + String(id))
	for id in a.checkpoints:
		ids.append("cp:" + String(id) + ":" + String(a.checkpoints[id].get("spawn_id")))
	for id in a.spawners:
		ids.append("sp:" + String(id))
	for id in a.skipped_spawners:
		ids.append("skip:" + String(id))
	for id in a.doors:
		ids.append("door:" + String(id))
	for id in a.lore_notes:
		ids.append("lore:" + String(id))
	ids.sort()
	var h := 0
	for n in a.find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (n as MultiMeshInstance3D).multimesh
		for i in mm.instance_count:
			h = hash([h, mm.get_instance_transform(i).origin.snapped(Vector3.ONE * 0.001)])
	return {"ids": ids, "hash": h}
