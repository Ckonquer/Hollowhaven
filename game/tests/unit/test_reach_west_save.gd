extends "res://tests/unit/test_reach_west_fixture.gd"
## Reach west districts (module C2): everything the districts remember lives in GameState (flags, the reward
## ledger, depleted nodes) and survives a real save file round trip; rebuilt districts show exactly that state,
## and loading twice changes nothing.


func test_district_state_survives_a_save_file_round_trip() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var o: Node3D = d["orchard"]
	var p: Node3D = d["pools"]
	var c: Node3D = d["candleyard"]
	o.instant_growth = true
	o.mimic_pocket.instant = true
	c.instant = true
	B.availability_override = {"pumpkin_mimic": false}
	# Progress everything.
	o.pull_lever(null, "junction")
	o.pull_lever(null, "gate")
	o.plant_festival_seed()
	o.read_garden_note()
	o.mimic_pocket.inspect()
	assert_true(o.light_lamp())
	for i in Data.CHIMES.size():
		p.check_chimes(Vector3(Data.CHIMES[i].x, 0, Data.CHIMES[i].y))
	assert_true(p.take_pouch())
	c.read_note(null, Data.LORE_GROUNDSKEEPER_1, Data.FLAG_NOTE_1)
	c.read_note(null, Data.LORE_GROUNDSKEEPER_2, Data.FLAG_NOTE_2)
	assert_true(c.place_light())
	assert_true(c.rescue_hat())
	assert_true(c.take_pattern())
	(o.nodes["hr_pumpkin_0"] as Node).harvest_hit(null, "")
	(p.nodes["hr_sugarcap_0"] as Node).harvest_hit(null, "")
	var ledger_before: Dictionary = GameState.ledger.duplicate()
	var inv_counts := {}
	for id in ["moonpetal", "sugarcap", "candy", "pumpkin"]:
		inv_counts[id] = GameState.count_item(id)
	assert_true(SaveSystem.save_game(true), "saved")
	# Wipe and load the file.
	fresh_state()
	assert_false(flag(Data.FLAG_LAMP_LIT))
	assert_true(SaveSystem.load_game(), "loaded")
	for f in [Data.FLAG_LAMP_LIT, Data.FLAG_FOUND_LAMP, Data.FLAG_IRRIGATED, Data.FLAG_JUNCTION_GARDEN, Data.FLAG_GATE_OPEN,
			Data.FLAG_SEED_PLANTED, Data.FLAG_MIMICS_CLEARED, Data.FLAG_CHIMES_FOUND, Data.FLAG_CHIMES_DONE, Data.FLAG_NOTE_1,
			Data.FLAG_NOTE_2, Data.FLAG_LIGHT_PLACED, Data.FLAG_HAT, "ch2_candleyard_pattern", "spawner_cleared_hr_sp_orchard_mimics"]:
		assert_true(flag(f), "%s survives the save" % f)
	for rid in ledger_before:
		assert_true(GameState.has_reward(String(rid)), "ledger %s survives" % rid)
	assert_true(GameState.is_depleted("hr_pumpkin_0") and GameState.is_depleted("hr_sugarcap_0"), "picked nodes stay picked")
	assert_true(GameState.lore.has(Data.LORE_GARDEN), "the garden note is in the journal")
	# Rebuild on a fresh host (as after Continue): the world shows the saved state.
	var h2: Node3D = HostScript.new()
	h2.area_id = Data.AREA_ID
	h2.add_ground(Rect2(-140, -110, 280, 220), 0.0, Color.BROWN, "grass")
	add_child(h2)
	_hosts.append(h2)
	var o2: Node3D = Orchard.build_district(h2)
	var p2: Node3D = Pools.build_district(h2)
	var c2: Node3D = Candleyard.build_district(h2)
	assert_eq(o2.irrigation, {"junction": "garden", "gate": true}, "levers where she left them")
	assert_true(o2.water["garden_b"].visible, "the garden is watered")
	assert_true(o2._lamp_light.visible, "the lamp is lit")
	assert_eq(o2.interactables["garden_lamp"].get_interaction(null), {})
	assert_true(o2._festival.visible, "the festival pumpkin is there")
	assert_eq(o2.mimic_pocket.state, "cleared")
	assert_true(bool((o2.nodes["hr_pumpkin_0"] as Node).get("depleted")), "picked pumpkin still regrowing")
	assert_eq(p2.trail_state, "done")
	assert_true(c2._marker_candle.visible and c2._nook_light.visible)
	assert_false(c2._hat.visible)
	assert_false(c2._pattern_ribbon.visible)
	# Loading twice and repeating every action changes nothing (rewards once).
	assert_true(SaveSystem.load_game())
	assert_false(o2.light_lamp())
	assert_false(p2.take_pouch())
	assert_false(c2.place_light())
	assert_false(c2.rescue_hat())
	assert_false(c2.take_pattern())
	assert_eq(GameState.ledger.size(), ledger_before.size(), "no new ledger entries")
	for id2 in inv_counts:
		assert_eq(GameState.count_item(String(id2)), int(inv_counts[id2]), "%s unchanged" % id2)
