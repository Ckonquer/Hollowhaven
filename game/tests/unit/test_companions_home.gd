extends "res://tests/unit/test_companions_fixture.gd"
## Home life (MP §6.5): bounded, saved daily ledgers; Pebble's cairn never creates items and is capped; Mochi
## naps and wakes; Lumi visits a Haven lamp once a night; friends notice a new furnishing with a line; home
## spots from a nook (set, cleared when the nook is removed, repaired by the spawner).

const HomeLife := preload("res://src/companions/companion_home.gd")


func before_each() -> void:
	await super.before_each()
	Game.area_id = "surface"
	GameState.total_minutes = 60.0 * 10.0      # 10:00, daytime


func _inventory_total() -> int:
	var n := 0
	for s in GameState.inventory.slots:
		if s != null:
			n += int(s["count"])
	return n


func test_daily_ledger_caps_and_resets() -> void:
	var rec := {}
	for i in 3:
		assert_true(HomeLife.take(rec, 4, "cairn"), "stone %d" % (i + 1))
	assert_false(HomeLife.take(rec, 4, "cairn"), "three a day at most")
	assert_false(HomeLife.can_take(rec, 4, "cairn"))
	assert_true(HomeLife.can_take(rec, 5, "cairn"), "a new day")
	assert_true(HomeLife.take(rec, 5, "cairn"))
	assert_eq(int(rec["home_log"]["day"]), 5, "the ledger is stored in the record (saved)")


func test_pebble_builds_its_cairn_without_making_items() -> void:
	_befriend("pebble")
	var p := _make("pebble", "home", Vector3(0, 0.05, 10))
	await wait_physics(2)
	var items_before := _inventory_total()
	p.home_life.set("_t", 0.0)
	assert_true(await _wait_until(func() -> bool: return int(GameState.companion("pebble").get("cairn", 0)) >= 1, 12.0), "a stone on the cairn")
	assert_eq(_inventory_total(), items_before, "no items created")
	var cairn: Node = p.get_parent().get_node_or_null("PebbleCairn")
	assert_not_null(cairn, "a little stone stack beside its home")
	if cairn != null:
		await wait_frames(1)
		assert_eq(cairn.get_child_count(), 1, "one stone")
		var cp: Vector3 = p.home_life.cairn_pos()
		assert_true(Vector2((cairn as Node3D).global_position.x - cp.x, (cairn as Node3D).global_position.z - cp.z).length() < 0.05)
	assert_eq(int(GameState.companion("pebble")["home_log"].get("cairn", 0)), 1, "counted in the daily ledger")
	assert_eq(String(GameState.companion("pebble")["home_task"]), "", "task finished")
	# Capped: the cairn never grows past CAIRN_MAX.
	GameState.companion("pebble")["cairn"] = HomeLife.CAIRN_MAX
	p.home_life.set("carrying", true)
	p.home_life.on_work_action({"kind": "cairn_place"}, "stomp")
	assert_eq(int(GameState.companion("pebble")["cairn"]), HomeLife.CAIRN_MAX)


func test_mochi_naps_and_wakes() -> void:
	_befriend("mochi")
	var m := _make("mochi", "home", Vector3(0, 0.05, 10))
	await wait_physics(2)
	m.home_life.call("_start_nap")
	m.home_life.set("nap_left", 1.0)
	await wait_physics(2)
	assert_eq(String(m.visual.mood), "sleep", "curled up for a nap")
	assert_eq(String(GameState.companion("mochi")["home_task"]), "nap")
	await wait_seconds(1.3)
	assert_ne(String(m.visual.mood), "sleep", "and awake again")
	assert_eq(String(GameState.companion("mochi")["home_task"]), "")


func test_a_new_furnishing_is_noticed_with_a_line() -> void:
	_befriend("mochi")
	var m := _make("mochi", "home", Vector3(0, 0.05, 10))
	await wait_physics(2)
	var uid := GameState.add_structure("haven_banner", Vector3(2.0, 0.0, 11.0), 0.0)
	Events.structure_placed.emit(uid, "haven_banner")
	var name := ItemDB.structure_display_name("haven_banner").to_lower()
	assert_true(await _wait_until(func() -> bool: return _said_contains(name), 8.0), "Mochi mentions the new %s: %s" % [name, str(said)])
	assert_eq(int(GameState.companion("mochi")["home_log"].get("notice", 0)), 1)


func test_lumi_visits_a_haven_lamp_once_a_night() -> void:
	_befriend("lumi")
	GameState.total_minutes = 60.0 * 22.0
	var lamp := Node3D.new()
	lamp.add_to_group("light_source")
	lamp.add_to_group("structure")
	add_child(lamp)
	nodes.append(lamp)
	lamp.global_position = Vector3(4.0, 0.05, 12.0)
	var l := _make("lumi", "home", Vector3(0, 0.05, 10))
	player.global_position = Vector3(1, 0.05, 11)
	assert_true(await _wait_until(func() -> bool: return _said_contains("lanterns"), 6.0), "Lumi pulses with the lamp: %s" % str(said))
	assert_eq(int(GameState.companion("lumi")["home_log"].get("lights", 0)), 1)
	await wait_seconds(1.5)
	assert_false(l.home_life.tick_night(0.1), "once a night")


func test_home_spot_follows_the_nook_and_falls_back() -> void:
	_befriend("mochi")
	var m := _make("mochi", "home", Vector3(0, 0.05, 10))
	m.set_home_spot(Vector3(6, 0.05, 12))
	assert_eq(m.home_pos, Vector3(6, 0.05, 12))
	GameState.companion("mochi")["home_spot"] = [6.0, 0.05, 12.0]
	GameState.companion("mochi")["home_nook"] = "s_gone"
	Events.structure_removed.emit("s_gone", "companion_bed")
	assert_null(GameState.companion("mochi")["home_spot"], "the nook was taken away")
	assert_eq(m.home_pos, Vector3(0, 0.05, 10), "back to its default spot")


func test_spawner_uses_and_repairs_home_spots() -> void:
	var area: Node3D = AreaBase.new()
	add_child(area)
	nodes.append(area)
	for id in ["mochi", "pebble", "lumi"]:
		area.register_spawn("companion_home_" + id, Transform3D(Basis.IDENTITY, Vector3(-3, 0.05, 10)))
		area.register_spawn("companion_wild_" + id, Transform3D(Basis.IDENTITY, Vector3(-9, 0.05, -9)))
	area.register_spawn("mine_threshold", Transform3D(Basis.IDENTITY, Vector3(30, 0.05, 30)))
	_befriend("mochi")
	_befriend("pebble")
	GameState.deplete("pebble_boulder", -1.0)
	var bed := GameState.add_structure("companion_bed", Vector3(5, 0, 12), 0.0)
	GameState.companion("mochi")["home_spot"] = [5.0, 0.0, 12.0]
	GameState.companion("mochi")["home_nook"] = bed
	GameState.companion("pebble")["home_spot"] = [8.0, 0.0, 8.0]
	GameState.companion("pebble")["home_nook"] = "s_missing"
	var out: Dictionary = Spawner.spawn_for_area(area, "surface", player)
	for id in out:
		nodes.append(out[id])
	var mh: Vector3 = out["mochi"].home_pos
	assert_true(Vector2(mh.x - 5.0, mh.z - 12.0).length() < 0.05, "Mochi's home is its bed (%s)" % str(mh))
	assert_null(GameState.companion("pebble")["home_spot"], "a home spot whose nook is gone is repaired")
	var ph: Vector3 = out["pebble"].home_pos
	assert_true(Vector2(ph.x + 3.0, ph.z - 10.0).length() < 0.05, "Pebble lives at its default spot")
