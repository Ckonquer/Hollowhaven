extends "res://tests/unit/test_reach_west_fixture.gd"
## The Candleyard (module C2): "A Candle for the Groundskeeper" and "A Hat Too Large" complete once (the optional
## log pays), the hidden pattern bundle through the ledger, the bench, the violet night lighting, guarded enemy
## loops, and arachnophobia (not applicable: nothing spider-like).


func _candleyard() -> Node3D:
	var h: Node3D = await flat_host()
	var c: Node3D = Candleyard.build_district(h)
	await wait_physics(1)
	return c


func _activate_chapter_two() -> void:
	GameState.set_flag("chapter_one_complete", true)
	GameState.set_flag("ch2_accepted", true)


func test_candle_for_the_groundskeeper_completes_once() -> void:
	var c: Node3D = await _candleyard()
	c.instant = true
	_activate_chapter_two()
	var marker: Node3D = c.interactables["groundskeeper_marker"]
	assert_eq(String(marker.get_interaction(null)["text"]), "Look at the empty candle dish", "first just a curious dish")
	marker.interact(null)
	assert_false(flag(Data.FLAG_LIGHT_PLACED), "nothing happens before the notes")
	assert_false(c.place_light())
	c.interactables["groundskeeper_note_1"].interact(null)
	assert_true(flag(Data.FLAG_NOTE_1))
	assert_true(GameState.lore.has(Data.LORE_GROUNDSKEEPER_1), "note 1 in the journal")
	assert_eq(String(marker.get_interaction(null)["text"]), "Look at the empty candle dish", "one note is not enough")
	c.interactables["groundskeeper_note_2"].interact(null)
	assert_true(flag(Data.FLAG_NOTE_2))
	assert_true(GameState.lore.has(Data.LORE_GROUNDSKEEPER_2))
	assert_true(String(c.interactables["groundskeeper_note_2"].get_interaction(null)["text"]).ends_with("again"), "re-reading is allowed")
	assert_eq(String(marker.get_interaction(null)["text"]), "Light a candle for the groundskeeper")
	assert_false(c._marker_candle.visible)
	var petals: Node3D = c._nook_flowers.get_node("NookPetals")
	assert_false(petals.visible, "the nook is still closed")
	marker.interact(null)
	assert_true(flag(Data.FLAG_LIGHT_PLACED), "ch2_groundskeeper_light_placed")
	assert_true(c._marker_candle.visible, "the candle burns on the dish")
	assert_true(petals.visible and c._nook_light.visible, "the calm moonflower nook blooms")
	assert_false(c._nook_light.shadow_enabled)
	assert_eq(marker.get_interaction(null), {}, "done")
	assert_false(c.place_light(), "once")
	# The optional log pays the Ghost Lantern exactly once (never this module).
	GameState.optional_goals.evaluate()
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_groundskeeper"), "goal complete")
	assert_true(GameState.has_reward("rw_opt_groundskeeper"))
	assert_eq(GameState.count_item("ghost_lantern"), 1, "one Ghost Lantern")
	assert_true(flag("ch2_groundskeeper_candle"), "the recipe flag from the optional log")


func test_hat_too_large_completes_once_without_jumping() -> void:
	var c: Node3D = await _candleyard()
	c.instant = true
	_activate_chapter_two()
	var it: Node3D = c.interactables["witch_hat"]
	assert_eq(String(it.get_interaction(null)["text"]), "Rescue the stranded witch hat")
	assert_true(float(Data.HAT["height"]) <= 1.8, "the hat hangs at arm's height (no precision jump)")
	var hat_pos: Vector3 = c._hat.global_position
	assert_almost(hat_pos.y, float(Data.HAT["height"]), 0.01)
	assert_true(Vector2(hat_pos.x, hat_pos.z).distance_to(Data.HAT["stand"]) < 2.2, "within reach of the stand spot")
	it.interact(null)
	assert_true(flag(Data.FLAG_HAT), "ch2_witch_hat_found")
	assert_false(c._hat.visible)
	assert_eq(it.get_interaction(null), {})
	assert_false(c.rescue_hat(), "once")
	GameState.optional_goals.evaluate()
	assert_true(GameState.optional_goals.is_done("opt_hat_too_large"))
	assert_true((GameState.wardrobe["owned"] as Array).has("pat_witch_hat"), "the optional log unlocked the hat pattern")
	assert_eq((GameState.wardrobe["owned"] as Array).count("pat_witch_hat"), 1)
	# The ribbons flutter (toon wind) along the route.
	var mm: MultiMeshInstance3D = c.get_node("HatRibbonsPlum")
	assert_true(mm.multimesh.instance_count >= 3)
	assert_true(float((mm.material_override as ShaderMaterial).get_shader_parameter("wind_strength")) > 0.0, "fluttering")


func test_hidden_pattern_is_the_content_bundle_once() -> void:
	var c: Node3D = await _candleyard()
	var it: Node3D = c.interactables["hidden_pattern"]
	assert_true(c._pattern_ribbon.visible, "a pale ribbon peeks out (the clue)")
	it.interact(null)
	assert_true(GameState.has_reward(Data.REWARD_PATTERN), "rw_ch2_candleyard_pattern in the ledger")
	assert_true(flag("ch2_candleyard_pattern"), "the Loom pattern unlock flag")
	assert_false(c._pattern_ribbon.visible)
	assert_false(c.take_pattern(), "once")
	var ledger_size := GameState.ledger.size()
	it.interact(null)
	assert_eq(GameState.ledger.size(), ledger_size, "nothing more")
	# Rebuilt: stays taken.
	var h2: Node3D = HostScript.new()
	h2.area_id = Data.AREA_ID
	h2.add_ground(Rect2(-140, -110, 280, 220), 0.0, Color.BROWN, "grass")
	add_child(h2)
	_hosts.append(h2)
	var c2: Node3D = Candleyard.build_district(h2)
	assert_false(c2._pattern_ribbon.visible)
	assert_false((c2.interactables["hidden_pattern"] as Node3D).active)


func test_bench_is_a_calm_rest() -> void:
	var c: Node3D = await _candleyard()
	var it: Node3D = c.interactables["bench"]
	assert_eq(String(it.get_interaction(null)["text"]), "Sit a while")
	assert_true(c.rest_on_bench())
	assert_true(flag(Data.FLAG_BENCH_RESTED))
	assert_false(c.rest_on_bench(), "not a heal fountain (short cooldown)")
	assert_true(Data.BENCH["pos"].distance_to(Data.CANDLEYARD_CENTER) > Data.WALL_RADIUS, "at the edge")


func test_violet_lights_are_readable_and_brighter_at_night() -> void:
	var c: Node3D = await _candleyard()
	assert_eq(c.lights.size(), Data.VIOLET_LIGHTS.size())
	GameState.total_minutes = 60.0 * 23.0
	c.update_lights()
	assert_true(GameState.is_night())
	for l in c.lights:
		assert_almost((l[0] as OmniLight3D).light_energy, float(l[1]), 0.001, "full violet at night")
		assert_false((l[0] as OmniLight3D).shadow_enabled)
	GameState.total_minutes = 60.0 * 12.0
	c.update_lights()
	for l2 in c.lights:
		assert_true((l2[0] as OmniLight3D).light_energy > 0.2, "still readable by day")
		assert_true((l2[0] as OmniLight3D).light_energy < float(l2[1]), "softer by day")
	# Emissive candles and moonflowers (readable without any light).
	assert_true(c.get_node("CandleFlames").multimesh.instance_count >= 20, "plenty of candles")
	assert_true(c.get_node("MoonflowerPetals").multimesh.instance_count >= 30, "plenty of moonflowers")


func test_enemy_loops_are_guarded() -> void:
	var c: Node3D = await _candleyard()
	for sid in ["hr_sp_candleyard_drudges", "hr_sp_candleyard_patchwalkers"]:
		var enemy := String(Data.SPAWNERS[sid]["enemy"])
		if B.enemy_available(enemy):
			assert_not_null(c.spawners[sid])
		else:
			assert_null(c.spawners[sid], "%s: no spawner while %s is missing" % [sid, enemy])
	B.availability_override = {"hollow_drudge": true, "patchwalker": true}
	var c2: Node3D = await _candleyard()
	for sid2 in ["hr_sp_candleyard_drudges", "hr_sp_candleyard_patchwalkers"]:
		var sp: Node3D = c2.spawners[sid2]
		assert_not_null(sp, sid2)
		sp.set_process(false)
		assert_eq(String(sp.get("spawner_id")), sid2)
		assert_true(float(sp.get("respawn_minutes")) > 0.0, "optional loop")
		var pos: Vector2 = Data.SPAWNERS[sid2]["pos"]
		assert_true(pos.distance_to(Data.CANDLEYARD_CENTER) + float(Data.SPAWNERS[sid2]["radius"]) < Data.WALL_RADIUS, "spawns inside the wall")
		for act in [Data.MARKER, Data.NOTE_2, Data.SHED["note"], Data.HAT["stand"], Data.PATTERN_SPOT]:
			assert_true(pos.distance_to(act) > 10.0, "%s keeps its distance from the quiet activities" % sid2)


func test_arachnophobia_not_applicable() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var names_a: Array = []
	for key in ["orchard", "pools", "candleyard"]:
		for n in (d[key] as Node).find_children("*", "", true, false):
			var nm := String(n.name).to_lower()
			assert_false(nm.contains("spider") or nm.contains("web") or nm.contains("silk") or nm.contains("weaver"), "%s is not spider-like" % n.name)
			if not nm.begins_with("@"):
				names_a.append(nm)
	for sid in Data.SPAWNERS:
		var e: Dictionary = ItemDB.enemy(String(Data.SPAWNERS[sid]["enemy"]))
		assert_false(e.has("spider") and bool(e["spider"]), "%s enemy is not spider-like" % sid)
	# The setting changes nothing here (no alternative needed): same build either way.
	Settings.set_value("arachnophobia", true)
	var h2: Node3D = await flat_host()
	var d2 := await build_all(h2)
	var names_b: Array = []
	for key2 in ["orchard", "pools", "candleyard"]:
		for n2 in (d2[key2] as Node).find_children("*", "", true, false):
			var nm2 := String(n2.name).to_lower()
			if not nm2.begins_with("@"):
				names_b.append(nm2)
	Settings.set_value("arachnophobia", false)
	names_a.sort()
	names_b.sort()
	assert_eq(names_a, names_b, "identical content with arachnophobia on")
