extends "res://tests/test_case.gd"
## Lanternwake Expeditions runner (module D2) on a flat stand-in for the Reach: the stop's group appears only
## when Krystal is near its lantern, never in a safe zone and never where the camera can see it (frustum +
## line of sight), defeats advance the saved run, a despawn (far away / respawn) brings back only the ones
## still standing, a reload resumes at the saved stop, the cache appears after the last stop and pays once,
## setting a run aside clears the world - and nothing here sets a flag.

const Ex := preload("res://src/expeditions/expeditions.gd")
const Data := preload("res://data/expeditions.gd")
const Runner := preload("res://src/expeditions/expedition_runner.gd")
const Base := preload("res://src/enemies/enemy_base.gd")

const UNLOCKS := ["ch2_orchard_restored", "ch2_quarry_restored", "ch2_manor_restored"]


class FakeReach extends Node3D:
	var safe_center := Vector3(1.0e6, 0.0, 0.0)
	var safe_radius := 0.0

	func height_at(_x: float, _z: float) -> float:
		return 0.0

	func is_safe_zone(p: Vector3) -> bool:
		return Vector2(p.x - safe_center.x, p.z - safe_center.z).length() <= safe_radius


var _area: FakeReach
var _player: Node3D
var _runner: Node3D
var _was_listening := false
var _flags_seen: Array = []


func before_each() -> void:
	fresh_state()
	Base.reset_attack_tokens()
	_was_listening = Ex.is_listening()
	for f in UNLOCKS:
		GameState.flags[f] = true
	_area = FakeReach.new()
	add_child(_area)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	cs.shape = box
	floor_body.add_child(cs)
	_area.add_child(floor_body)
	floor_body.position = Vector3(0, -0.5, 0)
	_player = Node3D.new()
	_area.add_child(_player)
	_flags_seen = []
	Events.flag_set.connect(_on_flag)


func after_each() -> void:
	Events.flag_set.disconnect(_on_flag)
	if not _was_listening:
		Ex.shutdown()
	if is_instance_valid(_area):
		_area.queue_free()
	for w in get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(w):
			w.queue_free()
	await wait_frames(2)


func _on_flag(f: String, _v: Variant) -> void:
	_flags_seen.append(f)


func _attach() -> Node3D:
	_runner = Runner.attach(_area)
	_runner.set_process(false)
	_runner.player_override = _player
	_runner.use_camera = false
	await wait_physics(2)
	_runner.update_runner()
	return _runner


func _stop_pos(i: int) -> Vector3:
	var p: Vector2 = Ex.current_plan()["stops"][i]["pos"]
	return Vector3(p.x, 0.0, p.y)


func _freeze() -> void:
	for e in _runner.alive:
		if is_instance_valid(e):
			(e as Node).set_physics_process(false)


func _kill(e: Node) -> void:
	e.get("health").apply_damage(99999.0)


func _kill_all() -> void:
	for e in _runner.alive.duplicate():
		if is_instance_valid(e):
			_kill(e)


func _alive_ids() -> Array:
	var out: Array = []
	for e in _runner.alive:
		out.append(String((e as Node).get_meta("exp_enemy")))
	out.sort()
	return out


# --- Tests ---------------------------------------------------------------------------------------------------------

func test_attach_is_idempotent_and_the_lantern_marks_the_stop() -> void:
	assert_true(Ex.start("orchard_patrol", 12))
	await _attach()
	assert_eq(Runner.attach(_area), _runner, "one runner per area")
	assert_eq(String(_runner.name), Runner.NODE_NAME)
	assert_not_null(_runner.beacon)
	var b: Vector3 = _runner.beacon.global_position
	var want := _stop_pos(0)
	assert_almost(Vector2(b.x, b.z).distance_to(Vector2(want.x, want.z)), 0.0, 0.01, "the lantern stands at the first stop")
	assert_false(_runner.beacon.is_in_group("enemy") or _runner.beacon.is_in_group("interactable"))
	assert_null(_runner.cache, "no cache before the route is walked")


## Comfort: the ribbon lantern's light column never pulses or flashes, its light casts no shadow, and with
## "reduce_flashing" even the little lantern stops bobbing.
func test_the_ribbon_lantern_is_calm_and_follows_reduce_flashing() -> void:
	var was: Variant = Settings.values.get("reduce_flashing", false)
	assert_true(Ex.start("orchard_patrol", 12))
	await _attach()
	var b: Node3D = _runner.beacon
	var col: MeshInstance3D = b.get("column")
	var light: OmniLight3D = b.get("light")
	var lantern: Node3D = b.get("lantern")
	assert_false(light.shadow_enabled, "no dynamic shadow")
	var mat: Material = col.material_override
	var energy := light.light_energy
	Settings.values["reduce_flashing"] = false
	for i in 12:
		b.call("_process", 0.13)
		assert_eq(col.material_override, mat, "the column never changes")
		assert_almost(light.light_energy, energy, 0.0001, "the light never pulses")
	Settings.values["reduce_flashing"] = true
	var y := lantern.position.y
	for i in 12:
		b.call("_process", 0.13)
	assert_almost(lantern.position.y, y, 0.0001, "reduce_flashing: the lantern holds still")
	Settings.values["reduce_flashing"] = was


func test_the_group_appears_only_near_its_lantern_and_out_of_safe_zones() -> void:
	assert_true(Ex.start("orchard_patrol", 12))
	await _attach()
	var c := _stop_pos(0)
	_player.global_position = c + Vector3(0, 0, 60)
	_runner.update_runner()
	assert_eq(_runner.alive.size(), 0, "nothing far from the stop")
	_area.safe_center = c + Vector3(0, 0, 20)
	_area.safe_radius = 5.0
	_player.global_position = c + Vector3(0, 0, 20)
	_runner.update_runner()
	assert_eq(_runner.alive.size(), 0, "nothing while she stands in a safe zone")
	_area.safe_center = Vector3(1.0e6, 0.0, 0.0)
	_runner.update_runner()
	var needed := int(Ex.current_plan()["stops"][0]["needed"])
	assert_eq(_runner.alive.size(), needed, "the whole group appears once she comes near")
	_freeze()
	for e in _runner.alive:
		assert_true((e as Node).is_in_group("enemy"))
		var pos: Vector3 = (e as Node3D).global_position
		assert_true(pos.distance_to(_player.global_position) >= Data.MIN_SPAWN_DISTANCE, "never on top of her")
		assert_true(Vector2(pos.x, pos.z).distance_to(Vector2(c.x, c.z)) <= Data.POINT_SPREAD + 0.1, "at an authored point")
	assert_eq(_alive_ids(), _sorted(Ex.current_plan()["stops"][0]["enemies"]), "exactly the seeded group")
	_runner.update_runner()
	assert_eq(_runner.alive.size(), needed, "never more than the group")


func _sorted(a: Array) -> Array:
	var out: Array = []
	for x in a:
		out.append(String(x))
	out.sort()
	return out


func test_never_spawns_in_view_of_the_camera() -> void:
	assert_true(Ex.start("orchard_patrol", 12))
	await _attach()
	var c := _stop_pos(0)
	_player.global_position = c + Vector3(0, 0, 22)
	var cam := Camera3D.new()
	_area.add_child(cam)
	cam.global_position = c + Vector3(0, 1.6, 22)
	cam.look_at(c + Vector3(0, 0.8, 0))
	_runner.camera_override = cam
	for p in _runner._points3:
		assert_true(_runner.is_point_in_view(p), "every point is in plain view from here")
	_runner.update_runner()
	assert_eq(_runner.alive.size(), 0, "nothing appears while she is looking at the stop")
	# A wall between her and the stop hides the points: now they may appear (behind it).
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(40, 8, 1)
	ws.shape = wb
	wall.add_child(ws)
	_area.add_child(wall)
	wall.global_position = c + Vector3(0, 4, 13)
	await wait_physics(2)
	assert_false(_runner.is_point_in_view(_runner._points3[0]), "hidden behind the wall")
	_runner.update_runner()
	var needed := int(Ex.current_plan()["stops"][0]["needed"])
	assert_eq(_runner.alive.size(), needed, "out of sight, the group appears")
	_freeze()
	# Looking away works the same.
	_kill_all()
	wall.queue_free()
	await wait_physics(2)
	cam.look_at(c + Vector3(0, 0.8, 60))
	for p in _runner._points3:
		assert_false(_runner.is_point_in_view(p), "behind her back")
	cam.queue_free()


## Walking straight at the lantern (the camera sees every point) and standing beside it never stalls a stop:
## the points behind and beside her (out of the third-person camera's view) fill in; the ones she looks at wait.
func test_standing_at_the_lantern_the_group_fills_in_out_of_sight() -> void:
	assert_true(Ex.start("manor_afterglow", 40))
	await _attach()
	var c := _stop_pos(0)
	var cam := Camera3D.new()
	_area.add_child(cam)
	_runner.camera_override = cam
	for step in [30.0, 20.0, 10.0]:
		_player.global_position = c + Vector3(0, 0, step)
		cam.global_position = _player.global_position + Vector3(0, 2.2, 4.5)
		cam.look_at(c + Vector3(0, 0.8, 0))
		_runner.update_runner()
		for e in _runner.alive:
			(e as Node).set_physics_process(false)
	_player.global_position = c
	cam.global_position = c + Vector3(0, 2.2, 4.5)
	cam.look_at(c + Vector3(0, 0.8, -6.0))
	_runner.update_runner()
	_freeze()
	assert_true(_runner.alive.size() > 0, "beside the lantern, the group appears around her")
	for e in _runner.alive:
		var pos: Vector3 = (e as Node3D).global_position
		assert_true(pos.distance_to(_player.global_position) >= Data.MIN_SPAWN_DISTANCE - 0.1, "not on top of her")
	for rec in _runner.spawn_log:
		var pt: Vector2 = rec["point"]
		assert_false(_runner.is_point_in_view(Vector3(pt.x, 0.0, pt.y)), "appeared out of sight (%s)" % str(pt))
	cam.queue_free()


func test_defeats_advance_the_stop_and_the_lantern_moves() -> void:
	assert_true(Ex.start("orchard_patrol", 12))
	await _attach()
	_player.global_position = _stop_pos(0) + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	var needed := int(Ex.current_plan()["stops"][0]["needed"])
	assert_eq(_runner.alive.size(), needed)
	_kill(_runner.alive[0])
	assert_eq(int(Ex.active()["defeated"]), 1, "a defeat is counted")
	_kill_all()
	assert_eq(Ex.current_stop_index(), 1, "the stop is done")
	_runner.update_runner()
	var b: Vector3 = _runner.beacon.global_position
	var want := _stop_pos(1)
	assert_almost(Vector2(b.x, b.z).distance_to(Vector2(want.x, want.z)), 0.0, 0.01, "the lantern moved on")
	assert_eq(_runner.alive.size(), 0, "the next group waits for her at its own stop")
	assert_eq(_flags_seen, [], "no flag was set")


func test_far_away_or_respawned_only_the_ones_still_standing_return() -> void:
	assert_true(Ex.start("quarry_circuit", 77))
	await _attach()
	var c := _stop_pos(0)
	_player.global_position = c + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	var all_ids := _alive_ids()
	var first: Node = _runner.alive[0]
	var gone := String(first.get_meta("exp_enemy"))
	_kill(first)
	var expected: Array = all_ids.duplicate()
	expected.erase(gone)
	_player.global_position = c + Vector3(0, 0, Data.DESPAWN_RADIUS + 10.0)
	_runner.update_runner()
	await wait_frames(1)
	assert_eq(_runner.alive.size(), 0, "they go home while she is far away")
	assert_eq(get_tree().get_nodes_in_group("enemy").filter(func(e: Node) -> bool: return _runner.is_ancestor_of(e) and not e.is_queued_for_deletion()).size(), 0)
	_player.global_position = c + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	assert_eq(_alive_ids(), expected, "only the ones still standing come back")
	Events.player_respawned.emit()
	assert_eq(_runner.alive.size(), 0, "a respawn sends them home")
	_runner.update_runner()
	_freeze()
	assert_eq(_alive_ids(), expected, "and they wait at the stop again")


func test_a_reload_resumes_at_the_saved_stop() -> void:
	assert_true(Ex.start("manor_afterglow", 5))
	await _attach()
	_player.global_position = _stop_pos(0) + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	_kill_all()
	assert_eq(Ex.current_stop_index(), 1)
	_runner.update_runner()
	_player.global_position = _stop_pos(1) + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	var first: Node = _runner.alive[0]
	var gone := String(first.get_meta("exp_enemy"))
	var expected := _alive_ids()
	expected.erase(gone)
	_kill(first)
	assert_true(SaveSystem.save_game(true))
	_runner.queue_free()
	GameState.reset()
	await wait_frames(2)
	assert_true(SaveSystem.load_game())
	await _attach()
	assert_eq(_runner._stop, 1, "resumed at the saved stop")
	_player.global_position = _stop_pos(1) + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	assert_eq(_alive_ids(), expected, "the rest of that group, not a fresh one")


func test_the_cache_appears_after_the_last_stop_and_pays_once() -> void:
	assert_true(Ex.start("orchard_patrol", 30))
	await _attach()
	var plan := Ex.current_plan()
	for i in (plan["stops"] as Array).size():
		_player.global_position = _stop_pos(i) + Vector3(0, 0, 20)
		_runner.update_runner()
		_freeze()
		assert_eq(_runner.alive.size(), int(plan["stops"][i]["needed"]), "stop %d group" % i)
		_kill_all()
		_runner.update_runner()
	assert_true(Ex.in_cache_phase())
	assert_not_null(_runner.cache, "the cache waits")
	var cp: Vector2 = plan["cache"]["pos"]
	var at: Vector3 = _runner.cache.global_position
	assert_almost(Vector2(at.x, at.z).distance_to(cp), 0.0, 0.01, "at its authored place")
	var it: Dictionary = _runner.cache.get_interaction(null)
	assert_true(String(it["text"]).contains(String(plan["cache"]["name"])))
	var rewards: Dictionary = plan["rewards"]
	var before := {}
	for id in rewards:
		before[id] = GameState.count_item(String(id))
	var cache: Node = _runner.cache
	cache.interact(null)
	for id in rewards:
		assert_eq(GameState.count_item(String(id)), int(before[id]) + int(rewards[id]), "paid %s" % id)
	assert_false(Ex.is_active())
	assert_null(_runner.cache, "the runner let go of the opened cache")
	assert_true(bool(cache.get("opened")))
	cache.interact(null)
	assert_eq(_runner.open_cache(), {}, "never twice")
	for id in rewards:
		assert_eq(GameState.count_item(String(id)), int(before[id]) + int(rewards[id]), "still once: %s" % id)
	_runner.update_runner()
	assert_null(_runner.beacon, "the lantern is packed away")
	assert_eq(_flags_seen, [], "no flag was set on the whole route")


func test_setting_the_run_aside_clears_its_world() -> void:
	assert_true(Ex.start("quarry_circuit", 2))
	await _attach()
	_player.global_position = _stop_pos(0) + Vector3(0, 0, 20)
	_runner.update_runner()
	_freeze()
	var e: Node = _runner.alive[0]
	assert_true(Ex.abandon())
	_runner.update_runner()
	assert_eq(_runner.alive.size(), 0)
	assert_null(_runner.beacon)
	await wait_frames(1)
	assert_false(is_instance_valid(e) and not e.is_queued_for_deletion(), "its group went home")
	# A stale enemy of the old run never counts for a new one.
	assert_true(Ex.start("quarry_circuit", 2))
	assert_false(Ex.record_defeat("quarry_circuit", 1, 0, "brambling"), "run 1 is over")
	assert_eq(int(Ex.active()["defeated"]), 0)
