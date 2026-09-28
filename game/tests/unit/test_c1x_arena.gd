extends "res://tests/test_case.gd"
## Module B7: the Knotted Elder's open arena at Bramblewatch. Its fallback roots (used when the Elder script does
## not bring its own) are telegraphed first, never enclose Krystal (at most max_raised slots, at least min_open stay
## open, never raised on her / a companion / the Elder, natural gaps between slots), can always be cut, sink on
## their own, and vanish when the fight ends. An Elder with its own roots switches the arena's roots off.

const L := preload("res://data/c1x_layout.gd")
const Bramble := preload("res://src/world/surface/c1x/bramblewatch.gd")
const AreaBase := preload("res://src/world/area_base.gd")

var _area: Node3D = null
var _arena: Node3D = null
var _player: Node3D = null
var _elder: Node3D = null


func before_each() -> void:
	fresh_state()
	_area = AreaBase.new()
	_area.area_id = "surface"
	add_child(_area)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(400, 1, 400)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, -0.5, 0)
	_area.add_child(body)
	_arena = Bramble.Arena.new()
	_area.add_child(_arena)
	var c: Vector2 = L.ELDER_ARENA["centre"]
	_arena.global_position = Vector3(c.x, 0, c.y)
	_arena.build_slots(_area)
	_player = Node3D.new()
	_area.add_child(_player)
	_player.global_position = _arena.global_position
	_arena.player_override = _player
	_elder = Node3D.new()
	_area.add_child(_elder)
	_elder.global_position = _arena.global_position + Vector3(2, 0, 0)
	_arena._on_elder_spawned(_elder)


func after_each() -> void:
	if _area != null and is_instance_valid(_area):
		_area.queue_free()
	_area = null
	# The real Elder's drops (resin / wood pickups) land under the current scene when no area is loaded: remove
	# them so they never leak into later suites.
	for w in get_tree().get_nodes_in_group("world_item"):
		if is_instance_valid(w):
			w.queue_free()
	await wait_frames(2)


func _walls() -> Array:
	return _arena.get("walls")


func _advance_all(dt: float) -> void:
	for w in _walls():
		w.advance(dt)


func _states() -> Array:
	return _walls().map(func(w: Node) -> String: return String(w.get("state")))


func test_roots_come_after_a_telegraph_and_leave_open_slots() -> void:
	assert_eq(_walls().size(), L.ROOT_SLOTS.size(), "one wall per slot")
	for i in 7:
		_arena.tick(1.0)
	assert_eq(int(_arena.raised_count()), 0, "no roots in the first seconds of the fight")
	_arena.tick(1.5)
	var n := int(_arena.raised_count())
	assert_true(n >= 1 and n <= int(L.ELDER_ARENA["max_raised"]), "a few slots rise (%d)" % n)
	assert_true(int(_arena.open_count()) >= int(L.ELDER_ARENA["min_open"]), "at least min_open slots stay open")
	# Telegraph: visible crack, nothing solid yet.
	for w in _walls():
		if String(w.get("state")) == "telegraph":
			assert_true((w.get("_crack") as Node3D).visible, "the crack shows during the telegraph")
			assert_eq((w.get("_solid") as StaticBody3D).collision_layer, 0, "nothing blocks during the telegraph")
	_advance_all(float(L.ELDER_ARENA["telegraph"]) + 0.01)
	var up := 0
	for w in _walls():
		if String(w.get("state")) == "up":
			up += 1
			assert_eq((w.get("_solid") as StaticBody3D).collision_layer, 1, "risen roots block")
			assert_eq((w.get("_interact") as StaticBody3D).collision_layer, 16, "risen roots can be focused")
			assert_true(w.is_in_group("harvestable"), "risen roots are a harvest target (cut)")
	assert_eq(up, n, "every telegraphed slot rose")
	# They sink on their own after the data duration.
	_advance_all(float(_arena._data_duration()) + 0.01)
	for w in _walls():
		assert_ne(String(w.get("state")), "up", "roots do not stay up")
		assert_eq((w.get("_solid") as StaticBody3D).collision_layer, 0, "sinking roots no longer block")
	_advance_all(1.0)
	assert_eq(_states().count("down"), _walls().size(), "all down again")


## Settings timing_assist removes the tight window: the telegraph lasts twice as long (at least 3 s).
func test_timing_assist_lengthens_the_telegraph() -> void:
	var old: Variant = Settings.get_value("timing_assist")
	Settings.set_value("timing_assist", true)
	var tele := float(L.ELDER_ARENA["telegraph"])
	var want := maxf(tele * 2.0, 3.0)
	assert_almost(float(Bramble.Arena.assisted_telegraph(tele)), want, 0.001, "assisted telegraph %.1f s" % want)
	assert_eq(float(Bramble.Arena.assisted_telegraph(0.0)), 0.0, "an instant rise stays instant")
	var n := int(_arena.raise_roots())
	assert_true(n > 0, "roots telegraph (%d)" % n)
	_advance_all(tele + 0.05)
	assert_eq(_states().count("up"), 0, "nothing rises at the normal telegraph time with the assist on")
	assert_eq(_states().count("telegraph"), n, "still telegraphing")
	_advance_all(want - tele)
	assert_eq(_states().count("up"), n, "they rise after the assisted telegraph")
	Settings.set_value("timing_assist", bool(old))
	_arena.clear_roots()
	assert_almost(float(Bramble.Arena.assisted_telegraph(tele)), tele, 0.001, "assist off: the data telegraph")


func test_roots_never_rise_on_krystal() -> void:
	for k in _walls().size():
		_arena.clear_roots()
		var mid := L.root_slot_mid(k)
		_player.global_position = Vector3(mid.x, 0, mid.y)
		for attempt in 4:
			_arena.clear_roots()
			_arena.set("_cooldown", 0.0)
			_arena.raise_roots()
			assert_ne(String(_walls()[k].get("state")), "telegraph", "slot %d under Krystal is never chosen" % k)
	# She walks onto a slot DURING its telegraph: that slot stays open.
	_arena.clear_roots()
	_player.global_position = _arena.global_position
	var w: Node = _walls()[2]
	w.begin(1.0, 6.0)
	var mid2 := L.root_slot_mid(2)
	_player.global_position = Vector3(mid2.x, 0, mid2.y)
	w.advance(1.1)
	assert_eq(String(w.get("state")), "down", "a root never closes on Krystal")
	assert_eq((w.get("_solid") as StaticBody3D).collision_layer, 0, "no collider under her")


func test_roots_never_rise_on_the_elder_or_a_companion() -> void:
	var mid := L.root_slot_mid(4)
	_elder.global_position = Vector3(mid.x, 0, mid.y)
	for attempt in 6:
		_arena.clear_roots()
		_arena.raise_roots()
		assert_ne(String(_walls()[4].get("state")), "telegraph", "never on the Elder")
	var comp := Node3D.new()
	_area.add_child(comp)
	var mid6 := L.root_slot_mid(6)
	comp.global_position = Vector3(mid6.x, 0, mid6.y)
	Game.companion_nodes["c1x_test_friend"] = comp
	for attempt in 6:
		_arena.clear_roots()
		_arena.raise_roots()
		assert_ne(String(_walls()[6].get("state")), "telegraph", "never on a companion")
	Game.companion_nodes.erase("c1x_test_friend")


func test_roots_can_be_cut() -> void:
	var w: Node = _walls()[0]
	w.begin(0.0, 6.0)
	assert_eq(String(w.get("state")), "up", "zero telegraph rises at once")
	var info: Dictionary = w.get_harvest_info()
	assert_eq(String(info["tool"]), "hand", "any hand can cut them")
	assert_false(bool(info["depleted"]), "a harvest target while up")
	assert_eq(String(w.get_interaction(null).get("text", "")), "Cut the thorny roots")
	var cut := [false]
	w.cut.connect(func() -> void: cut[0] = true)
	for i in int(L.ELDER_ARENA["root_hits"]) - 1:
		w.harvest_hit(null, "")
		assert_eq(String(w.get("state")), "up", "still standing after %d hit(s)" % (i + 1))
	w.interact(null)
	assert_true(cut[0], "cut signal")
	assert_eq(String(w.get("state")), "sinking", "cut roots sink at once")
	assert_eq((w.get("_solid") as StaticBody3D).collision_layer, 0, "and stop blocking immediately")
	assert_true(bool(w.get_harvest_info()["depleted"]), "no longer a target")
	assert_true(w.get_interaction(null).is_empty(), "no prompt")


func test_max_roots_always_leave_a_physical_way_out() -> void:
	_arena.set("_rng", RandomNumberGenerator.new())
	for round in 5:
		_arena.clear_roots()
		_arena.raise_roots(0.0, 6.0)
		await wait_physics(2)
		var up := _states().count("up")
		assert_true(up <= int(L.ELDER_ARENA["max_raised"]), "at most max_raised roots (%d)" % up)
		var space := _area.get_world_3d().direct_space_state
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.6
		var free_exits := 0
		for i in _walls().size():
			if String(_walls()[i].get("state")) == "up":
				continue
			var mid := L.root_slot_mid(i)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = cap
			q.transform = Transform3D(Basis.IDENTITY, Vector3(mid.x, 0.95, mid.y))
			q.collision_mask = 1
			var blocked := false
			for h in space.intersect_shape(q, 4):
				if (h.get("collider") as Node).name == "Solid":
					blocked = true
			if not blocked:
				free_exits += 1
		assert_true(free_exits >= int(L.ELDER_ARENA["min_open"]), "round %d: %d open exits" % [round, free_exits])
		# Between two neighbouring raised roots there is still a walkable gap (never a closed ring).
		for i in _walls().size():
			var a: Array = _walls()[i].world_ends()
			var b: Array = _walls()[(i + 1) % _walls().size()].world_ends()
			var gap := INF
			for pa in a:
				for pb in b:
					gap = minf(gap, Vector2((pa as Vector3).x - (pb as Vector3).x, (pa as Vector3).z - (pb as Vector3).z).length())
			assert_true(gap - float(L.ELDER_ARENA["root_depth"]) > 1.0, "gap between slots %d and %d fits Krystal" % [i, (i + 1) % _walls().size()])


func test_roots_clear_when_the_fight_ends() -> void:
	_arena.raise_roots(0.0, 6.0)
	assert_true(int(_arena.raised_count()) > 0, "roots up")
	Events.player_died.emit()
	assert_eq(_states().count("down"), _walls().size(), "Krystal down: every root sinks")
	_arena.raise_roots(0.0, 6.0)
	_player.global_position = _arena.global_position + Vector3(60, 0, 0)
	_arena.tick(0.3)
	assert_eq(_states().count("down"), _walls().size(), "Krystal ran off: roots sink")
	_player.global_position = _arena.global_position
	_arena.raise_roots(0.0, 6.0)
	_elder.queue_free()
	await wait_frames(1)
	_arena.tick(0.3)
	assert_eq(_states().count("down"), _walls().size(), "the Elder is gone: roots sink")
	assert_false(bool(_arena.is_engaged()), "no fight without the Elder")


func test_no_roots_outside_the_fight() -> void:
	_player.global_position = _arena.global_position + Vector3(40, 0, 0)
	for i in 30:
		_arena.tick(1.0)
	assert_eq(int(_arena.raised_count()), 0, "Krystal far away: nothing rises")


func test_an_elder_with_its_own_roots_switches_the_arena_roots_off() -> void:
	var gs := GDScript.new()
	gs.source_code = "extends Node3D\nfunc clear_roots() -> void:\n\tpass\nfunc live_roots() -> int:\n\treturn 0\n"
	gs.reload()
	var own: Node3D = gs.new()
	_area.add_child(own)
	own.global_position = _arena.global_position + Vector3(2, 0, 0)
	_arena.set("elder_driven", false)
	_arena._on_elder_spawned(own)
	assert_true(bool(Bramble.Arena.elder_owns_roots(own)), "detected")
	assert_true(bool(_arena.get("elder_driven")), "the Elder drives its own roots")
	for i in 30:
		_arena.tick(1.0)
	assert_eq(int(_arena.raised_count()), 0, "no double roots from the arena")
	_arena._on_elder_state("roots")
	assert_eq(int(_arena.raised_count()), 0, "its roots state does not trigger the arena's")


func test_a_roots_state_or_call_from_a_plain_elder_raises_them() -> void:
	_arena._on_elder_state("roots")
	assert_true(int(_arena.raised_count()) > 0, "a 'roots' state of an Elder without its own roots uses the arena's")
	assert_true(bool(_arena.get("elder_driven")), "and switches the arena's own schedule off")


## Integration with the enemy module (skipped while its Knotted Elder is not available): the real Elder spawns
## from c1x_sp_knotted_elder (built exactly as Bramblewatch.build does), fights in THIS arena (centre + radius
## handed over through the spawner's enemy_params, R81), is recognised as bringing its own roots, and its
## defeat pays rw_c1x_elder once.
func test_real_elder_from_the_spawner_when_available() -> void:
	const Common := preload("res://src/world/surface/c1x/common.gd")
	if not Common.enemy_available("knotted_elder"):
		print("    (skipped: knotted_elder not available yet)")
		return
	var sp: Node3D = Bramble.make_elder_spawner(_area, _area)
	assert_not_null(sp, "the Elder's spawner")
	if sp != null:
		var ep: Dictionary = sp.get("enemy_params")
		assert_almost(float(ep.get("arena_radius", 0.0)), float(L.ELDER_ARENA["radius"]), 0.001, "the arena radius goes to the Elder")
		assert_false(bool(sp.get("out_of_view")), "the one-time Elder is placed in its arena, not hidden")
	if sp == null:
		return
	sp.set("player_override", _player)
	sp.set("ignore_safe_zones", true)
	_player.global_position = _arena.global_position + Vector3(9, 0, 0)
	_arena.attach_spawner(sp)
	sp.update_spawner()
	await wait_frames(2)
	var alive: Array = sp.get("alive")
	assert_eq(alive.size(), 1, "one Knotted Elder")
	if alive.is_empty():
		return
	var e: Node3D = alive[0]
	assert_eq(_arena.get("elder"), e, "the arena tracks the spawned Elder")
	assert_almost(float(e.get("arena_radius")), float(L.ELDER_ARENA["radius"]), 0.001, "Elder arena radius = ELDER_ARENA radius (data fallback 12)")
	var ac: Vector3 = e.get("arena_center")
	assert_true(Vector2(ac.x - _arena.global_position.x, ac.z - _arena.global_position.z).length() < 0.01, "Elder arena centre = the arena's centre")
	assert_true(bool(Bramble.Arena.elder_owns_roots(e)) == bool(_arena.get("elder_driven")), "own roots <-> arena roots off")
	assert_true(e.global_position.distance_to(_arena.global_position) < 2.0, "it spawns in the arena's middle")
	var resin0 := GameState.count_item("resin")
	var h: Node = e.get("health")
	h.apply_damage(99999.0, null)
	await wait_frames(2)
	assert_true(GameState.has_reward(L.REWARD_ELDER), "rw_c1x_elder paid on the Elder's defeat")
	assert_true(bool(GameState.get_flag(L.FLAG_ELDER_DEFEATED)), "c1x_elder_defeated")
	assert_true(bool(GameState.get_flag("spawner_cleared_" + String(L.ELDER_SPAWNER["id"]))), "its spawner cleared for good")
	var bundle: Dictionary = ItemDB.reward_bundle(L.REWARD_ELDER)
	assert_true(GameState.count_item("resin") - resin0 >= int(bundle["items"]["resin"]), "the bundle's resin (plus any drops)")
	assert_false(bool(sp.wave_available()), "the Elder never respawns")
	assert_eq(_states().count("down"), _walls().size(), "no arena roots left standing")


## R82: the renewable Brambleback group never pops in within view; the helper applies the layout's out_of_view.
func test_bramblebacks_spawner_is_out_of_view() -> void:
	const Common := preload("res://src/world/surface/c1x/common.gd")
	assert_true(bool(L.BRAMBLEBACK_SPAWNER.get("out_of_view", false)), "layout: Bramblebacks spawn out of view")
	if not Common.enemy_available("brambleback"):
		print("    (skipped: brambleback not available yet)")
		return
	var sp: Node3D = Bramble.make_bramblebacks(_area, _area)
	assert_not_null(sp, "the Brambleback spawner")
	if sp != null:
		assert_true(bool(sp.get("out_of_view")), "applied to the real spawner")
		assert_eq(String(sp.get("spawner_id")), String(L.BRAMBLEBACK_SPAWNER["id"]), "the id is unchanged")
		assert_eq(int(sp.get("count")), int(L.BRAMBLEBACK_SPAWNER["count"]), "the rest of the def is kept")
