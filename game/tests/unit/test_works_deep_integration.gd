extends "res://tests/test_case.gd"
## Rooms 9-14 inside the REAL Works area (src/world/areas_ch2/hushed_works_world.gd, works module C7, which
## merges data/works_layout_deep.gd and calls rooms_deep.gd before its single finish()): the deep rooms are
## present, the contract spawns are ours (no hub fallbacks), checkpoints / safety / zones / moods / director
## anchors go through the area API, the hub's lower ward door connects to room 9 once the three lines are
## restored, the arenas drive area.set_fight, and the whole area still builds well inside the budget.
## Skips (with a note) if the area script does not load the deep module.

const Layout := preload("res://data/works_layout_deep.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"
const MASK := 1 | 32

var area: Node3D = null


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	await wait_frames(2)


func _make(lines_restored: bool = false) -> Node3D:
	if lines_restored:
		for f in ["ch2_line_water", "ch2_line_bell", "ch2_line_light"]:
			GameState.set_flag(f, true)
	var a: Node3D = load(WORLD).new()
	add_child(a)
	await wait_physics(3)
	return a


func _deep_ready() -> bool:
	if area.get_node_or_null("WorksDeep") == null:
		print("  SKIP: the Works area script does not build rooms 9-14 (rooms_deep.gd not called)")
		return false
	return true


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = MASK
	return area.get_world_3d().direct_space_state.intersect_ray(q)


func _capsule_free(feet: Vector3) -> bool:
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.4
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 1.05)
	q.collision_mask = MASK
	return area.get_world_3d().direct_space_state.intersect_shape(q, 4).is_empty()


## Budget: the build behind the load fade. The FIRST build in a process also pays the one-time GDScript
## compilation of every script involved (slow in the debug editor binary on this machine: ~0.1 ms per line,
## e.g. below_world.gd alone compiles in ~0.8 s cold), so it gets the project's generous cold bound
## (test_world_surface: 4 s); the build itself (scripts compiled, as on every later visit) gets the strict one.
func test_real_area_builds_the_deep_rooms_within_budget() -> void:
	area = await _make()
	if not _deep_ready():
		return
	var cold: Dictionary = (area.get("build_times") as Dictionary).duplicate()
	var cold_total := float(cold.get("total", 0))
	var cold_deep := float(cold.get("deep", 0)) - float(cold.get("nodes 1-8", 0))
	area.queue_free()
	await wait_frames(2)
	area = await _make()
	assert_true(bool(area.get("deep_present")), "deep module present")
	assert_eq(area.get("room_conflicts"), [], "no room id clashes with rooms 1-8")
	for id in ["hw_winch", "hw_crossing", "hw_wrong_landing", "hw_porch", "hw_throat", "hw_vault"]:
		assert_not_null(area.get_node_or_null("Room_" + id), "room %s built" % id)
	var bt: Dictionary = area.get("build_times")
	var total := float(bt.get("total", 0))
	var deep_ms := float(bt.get("deep", 0)) - float(bt.get("nodes 1-8", 0))
	var own_ms := float(((area.get_node("WorksDeep") as Node).get("build_ms")))
	print("  hushed_works build: first %.0f ms (deep rooms %.0f ms, incl. script compilation), again %.0f ms (deep rooms %.0f ms, rooms_deep.build %.0f ms)" % [cold_total, cold_deep, total, deep_ms, own_ms])
	assert_true(cold_total < 4000.0, "first Works build incl. compiling its scripts: %.0f ms (< 4000)" % cold_total)
	assert_true(total < 1500.0, "whole Works area builds in %.0f ms (< 1500)" % total)
	assert_true(deep_ms < 500.0, "rooms 9-14 add %.0f ms" % deep_ms)


func test_contract_spawns_checkpoints_safety_zones() -> void:
	area = await _make()
	if not _deep_ready():
		return
	assert_eq(area.get("deep_spawn_fallbacks"), [], "crossing_gate / bell_throat / vault_exit come from the deep module")
	for id in ["crossing_gate", "bell_throat", "vault_exit"]:
		var want: Vector3 = Layout.SPAWNS[id]["pos"]
		var got: Vector3 = area.get_spawn(id).origin
		assert_true(Vector2(got.x - want.x, got.z - want.z).length() < 0.05 and absf(got.y - want.y) < 0.2, "%s at the deep position" % id)
		var hit := _ray(got + Vector3.UP * 0.5, got + Vector3.DOWN * 1.5)
		assert_false(hit.is_empty(), "%s on a floor" % id)
		assert_true(_capsule_free(got), "%s has capsule clearance" % id)
	var cps: Dictionary = area.get("checkpoints")
	for id in Layout.CHECKPOINTS:
		assert_true(cps.has(id), "area.checkpoints lists %s" % id)
		assert_eq(String((cps[id] as Node).get("area_id")), "hushed_works")
	assert_true(area.is_safe_zone(Vector3(157.0, -28.0, 25.0)), "Bell Throat safe (add_safe_room)")
	assert_false(area.is_safe_zone(Vector3(88.0, -18.0, 0.0)), "the crossing is not safe")
	assert_false(area.is_safe_zone(Vector3(157.0, -32.0, 65.0)), "the vault is not safe")
	assert_eq(area.get_zone_at(Vector3(52.0, -18.0, 2.0)), "hw_winch")
	assert_eq(area.get_zone_at(Vector3(129.0, -22.0, 0.0)), "hw_wrong_landing")
	assert_eq(area.get_zone_at(Vector3(124.0, -22.0, 30.0)), "hw_porch")
	assert_eq(area.get_zone_at(Vector3(157.0, -32.0, 65.0)), "hw_vault")
	assert_ne(area.validate_position(Vector3(88.0, -17.9, 0.0)), null, "saved positions on the bridge validate")


func test_moods_and_director_anchors_through_the_area_api() -> void:
	area = await _make()
	if not _deep_ready():
		return
	var moods: Dictionary = area.get("_moods")
	for zone in Layout.MOODS:
		assert_eq((moods[zone] as Dictionary)["ambient"], Layout.MOODS[zone]["ambient"], "%s uses the deep light temperature" % zone)
	var ceiling := 0
	var spawn := 0
	for m in area.get("anchors"):
		var z := String((m as Node).get_meta("zone", ""))
		var k := String((m as Node).get_meta("kind", ""))
		if z == "hw_winch" and k == "ceiling":
			ceiling += 1
			assert_false(_ray((m as Node3D).global_position, (m as Node3D).global_position + Vector3.UP * 1.0).is_empty(), "ceiling anchor under a ceiling")
		if z == "hw_wrong_landing" and k == "spawn":
			spawn += 1
			assert_true(_capsule_free((m as Node3D).global_position), "spawn anchor clear")
	assert_true(ceiling >= 2, "winch ceiling anchors for hw_winch_dust")
	assert_true(spawn >= 2, "wrong-landing spawn anchors for hw_wisp_drift")


func test_hub_ward_door_connects_to_room_nine() -> void:
	area = await _make(true)
	if not _deep_ready():
		return
	var gate: Variant = (area.get("doors") as Dictionary).get("ward_gate")
	if gate is Node:
		assert_true(bool((gate as Node).get("is_open")), "all three lines open the lower ward door")
	await wait_physics(2)
	var pts := [Vector3(35.5, -18.0, 0.0), Vector3(38.5, -18.0, 0.0), Vector3(40.5, -18.0, 0.0), Vector3(42.5, -18.0, 0.0), Vector3(46.0, -18.0, 0.0)]
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		for k in 6:
			var p := a.lerp(b, float(k) / 5.0)
			var hit := _ray(p + Vector3.UP, p + Vector3.DOWN)
			assert_false(hit.is_empty(), "floor through the hub door at %s" % str(p))
			if not hit.is_empty():
				assert_true(_capsule_free(hit["position"]), "clear through the hub door at %s" % str(p))
	# the door frame closes around room 9's corridor: sideways rays at the door hit walls
	for z in [-1.0, 1.0]:
		assert_false(_ray(Vector3(41.5, -16.5, 0.0), Vector3(41.5, -16.5, z * 6.0)).is_empty(), "room 9's corridor is walled at the door")


func test_choir_victory_in_the_live_area_moves_the_respawn_to_the_exit() -> void:
	area = await _make()
	if not _deep_ready():
		return
	var prev: Node = Game.area
	Game.area = area
	var choir: Node = (area.get_node("WorksDeep") as Node).get("choir")
	choir.set("save_on_clear", false)
	choir.call("start_encounter")
	Events.boss_defeated.emit("borrowed_choir")
	Game.area = prev
	assert_true(bool(GameState.get_flag("ch2_choir_defeated")))
	assert_eq(String(GameState.player.get("respawn_area", "")), "hushed_works")
	assert_eq(String(GameState.player.get("respawn_spawn", "")), "vault_exit", "she wakes beside the exit lift")
	assert_true(area.is_safe_zone(Vector3(157.0, -32.0, 65.0)), "the won vault is a safe zone of the real area")
	assert_false(bool(area.get("fight_active")), "no fight left")
	var lift: Node = choir.get("exit_lift")
	assert_true(bool(lift.call("usable")), "the exit bell-lift works")


## The geometry suite walks the route on the stand-alone host; this walks it inside the REAL area (rooms 1-8
## and the hub built by the same builder), from the hub side of the ward door to the middle of the Choir
## Vault, plus every side path: floor under each 0.4 m step, 2 m headroom, a clear capsule.
func test_critical_path_is_walkable_in_the_real_area() -> void:
	area = await _make(true)
	if not _deep_ready():
		return
	var ctl: Node = area.get_node("WorksDeep")
	for id in Layout.THREADS:
		(ctl.call("thread", id) as Node).call("burn")
	(ctl.get("crossing") as Node).call("clear_encounter")
	(ctl.get("porch") as Node).call("reveal")
	(ctl.get("choir") as Node).call("clear_encounter")
	await wait_physics(3)
	var route: Array = [Vector3(37.0, -18.0, 0.0)]
	route.append_array(Layout.CRITICAL_PATH)
	assert_eq(_walk(route), "", "hub -> ward door -> rooms 9-14 -> Choir Vault in the real Works")
	for path in Layout.SIDE_PATHS:
		assert_eq(_walk(path), "", "side path from %s in the real Works" % str(path[0]))


func _walk(points: Array) -> String:
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var n := maxi(int(ceilf(a.distance_to(b) / 0.4)), 1)
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
			var cap := CapsuleShape3D.new()
			cap.radius = 0.28
			cap.height = 1.3
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, f + Vector3.UP * 1.0)
			q.collision_mask = MASK
			if not area.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
				return "blocked at %s" % str(p)
	return ""


## A respawn (or a lift ride) that takes Krystal out of the Borrowed Porch without walking out of it still
## releases the porch's director hold and its Intense silence - the rest of the Works never stays muted.
func test_respawn_out_of_the_porch_releases_its_hold_and_silence() -> void:
	var prev_int: Variant = Settings.get_value("horror_intensity")
	Settings.set_value("horror_intensity", 2)
	area = await _make()
	if not _deep_ready():
		Settings.set_value("horror_intensity", prev_int)
		return
	var ctl: Node = area.get_node("WorksDeep")
	var d := Node3D.new()
	add_child(d)
	d.global_position = Vector3(129.0, -22.0, 20.0)
	ctl.set("player_override", d)
	ctl.call("check", 0.1)
	assert_true((area.call("held_ids") as Array).has("hw_porch"), "the porch holds the director while she is there")
	d.global_position = Vector3(123.0, -22.0, 26.0)
	ctl.call("check", 0.1)
	assert_true(bool((ctl.get("porch") as Node).get("fragment_played")), "Intense: the fragment played")
	var got: Array = []
	var cb := func(ctx: String) -> void: got.append(ctx)
	Events.music_context_changed.connect(cb)
	d.global_position = (Layout.SPAWNS["crossing_gate"]["pos"] as Vector3)    # teleported by the respawn
	Events.player_respawned.emit()
	Events.music_context_changed.disconnect(cb)
	assert_false((area.call("held_ids") as Array).has("hw_porch"), "the porch hold is released")
	assert_true(got.has(""), "the porch silence is lifted")
	assert_eq(String(ctl.get("room")), "", "the room is re-detected on the next tick")
	ctl.call("check", 0.1)
	assert_eq(String(ctl.get("room")), "hw_crossing_gate")
	ctl.set("player_override", null)
	d.queue_free()
	Settings.set_value("horror_intensity", prev_int)


func test_arena_fight_flag_through_the_area() -> void:
	area = await _make()
	if not _deep_ready():
		return
	var ctl: Node = area.get_node("WorksDeep")
	var crossing: Node = ctl.get("crossing")
	crossing.call("start_encounter")
	assert_true(bool(area.get("fight_active")), "set_fight: Game.boss_active() sees the crossing")
	crossing.call("stop_encounter", "left")
	assert_false(bool(area.get("fight_active")), "released when she retreats")
	var choir: Node = ctl.get("choir")
	choir.call("start_encounter")
	assert_true(bool(area.get("fight_active")))
	choir.call("clear_encounter")
	assert_false(bool(area.get("fight_active")), "released on victory")
	assert_true(bool(GameState.get_flag("ch2_choir_defeated")))
