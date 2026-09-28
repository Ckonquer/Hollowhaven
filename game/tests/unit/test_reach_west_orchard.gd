extends "res://tests/unit/test_reach_west_fixture.gd"
## Pumpkintide Orchard (module C2): the irrigation puzzle state machine + reset, the lever visuals, the garden lamp
## (needs irrigation AND the cleared mimic pocket, sets its flag once, the quest layer pays the seal once), lamp
## discovery, the festival seed, the mimic pocket (inspect / wake / guarded fallback / real spawner / debug hook,
## never on player crops) and the guarded Patchwalker spawner.

const Pocket := preload("res://src/world/reach/west/mimic_pocket.gd")
const OrchardC := preload("res://src/world/reach/west/orchard_controller.gd")


func _orchard() -> Node3D:
	var h: Node3D = await flat_host()
	var o: Node3D = Orchard.build_district(h)
	await wait_physics(1)
	return o


func _player_at(p: Vector2) -> Node3D:
	var n := Node3D.new()
	n.name = "FakePlayer"
	add_child(n)
	_hosts.append(n)
	n.global_position = Vector3(p.x, 0.0, p.y)
	return n


func test_irrigation_state_machine_is_pure_reversible_and_resettable() -> void:
	fresh_state()
	var s := Irrigation.initial()
	var f := Irrigation.flow(s)
	assert_true(f["trunk"] and f["drain"] and f["drain_pond"], "the water starts in the drain pond")
	assert_false(f["garden_a"] or f["garden_b"] or f["garden"] or f["spill"], "nothing reaches the garden at first")
	# Gate first: nothing changes for the garden (the junction still sends the water away).
	var s1 := Irrigation.toggle_gate(s)
	assert_false(Irrigation.reaches_garden(s1))
	assert_true(Irrigation.flow(s1)["drain"])
	# Junction only: the water runs toward the garden and backs up against the closed gate (visible spill).
	var s2 := Irrigation.toggle_junction(s)
	var f2 := Irrigation.flow(s2)
	assert_true(f2["garden_a"] and f2["spill"], "junction to garden, gate shut: it spills before the gate")
	assert_false(f2["garden"] or f2["drain"])
	# Both: the garden is watered.
	var s3 := Irrigation.toggle_gate(s2)
	assert_true(Irrigation.reaches_garden(s3))
	assert_false(Irrigation.flow(s3)["spill"])
	# Reversible: toggling back returns the previous states exactly; inputs are never mutated.
	assert_eq(Irrigation.toggle_gate(Irrigation.toggle_gate(s3)), s3)
	assert_eq(Irrigation.toggle_junction(Irrigation.toggle_junction(s3)), s3)
	assert_eq(s, Irrigation.initial(), "pure: the start state was not modified")
	for st in [s, s1, s2, s3]:
		assert_true(Irrigation.describe(st).length() > 10, "a readable description for every state (never audio-only)")
	# Saved state + latch + reset.
	assert_false(Irrigation.store_state(s2), "no latch while the garden stays dry")
	assert_false(Irrigation.is_repaired())
	assert_eq(Irrigation.load_state(), s2, "levers saved in flags")
	assert_true(Irrigation.store_state(s3), "latched the first time the water reaches the garden")
	assert_false(Irrigation.store_state(s3), "latched only once")
	assert_true(Irrigation.is_repaired())
	assert_eq(Irrigation.reset(), Irrigation.initial(), "reset puts both levers back")
	assert_eq(Irrigation.load_state(), Irrigation.initial(), "reset is saved")
	assert_true(Irrigation.is_repaired(), "reset keeps 'irrigation repaired' (the lamp never un-qualifies)")


func test_levers_change_the_visible_water() -> void:
	var o: Node3D = await _orchard()
	var w: Dictionary = o.water
	assert_true(w["drain"].visible and w["drain_pond"].visible and w["trunk"].visible, "starts flowing to the drain pond")
	assert_false(w["garden_a"].visible or w["garden_b"].visible or w["spill"].visible)
	var jp: Vector2 = Data.IRRIGATION["junction"]
	var arrow_drain: float = o._arrow.rotation.y
	assert_almost(arrow_drain, B.yaw_to(jp, Data.FLUME_SEGMENTS[1][2]), 0.001, "the arrow points at the drain pond")
	# Lever texts say what the lever will do.
	assert_true(String(o.interactables["lever_junction"].get_interaction(null)["text"]).contains("garden"))
	assert_eq(String(o.interactables["lever_gate"].get_interaction(null)["text"]), "Raise the garden sluice gate")
	o.interactables["lever_junction"].interact(null)
	assert_true(flag(Data.FLAG_JUNCTION_GARDEN))
	assert_true(w["garden_a"].visible and w["spill"].visible, "water runs to the gate and spills")
	assert_false(w["drain"].visible or w["drain_pond"].visible or w["garden_b"].visible)
	assert_almost(o._arrow.rotation.y, B.yaw_to(jp, Data.FLUME_SEGMENTS[2][2]), 0.001, "the arrow swings to the garden branch")
	assert_false(flag(Data.FLAG_IRRIGATED))
	var paddle_low: float = o._paddle.position.y
	o.interactables["lever_gate"].interact(null)
	assert_true(o._paddle.position.y > paddle_low + 0.5, "the gate paddle visibly rises")
	assert_true(w["garden_b"].visible and not w["spill"].visible, "water reaches the festival bed")
	assert_true(flag(Data.FLAG_IRRIGATED), "irrigation repaired")
	# Reversing the junction stops the water again, but the repair stays latched.
	o.interactables["lever_junction"].interact(null)
	assert_false(w["garden_b"].visible)
	assert_true(w["drain"].visible)
	assert_true(flag(Data.FLAG_IRRIGATED), "latched")
	# Reset-safe: a fresh build of the area shows exactly the saved lever positions.
	var saved := Irrigation.load_state()
	var h2: Node3D = HostScript.new()
	h2.area_id = Data.AREA_ID
	h2.add_ground(Rect2(-140, -110, 280, 220), 0.0, Color.BROWN, "grass")
	add_child(h2)
	_hosts.append(h2)
	var o2: Node3D = Orchard.build_district(h2)
	assert_eq(o2.irrigation, saved, "rebuilt with the saved levers")
	assert_eq(o2.water["drain"].visible, o.water["drain"].visible)
	assert_eq(o2.water["garden_b"].visible, o.water["garden_b"].visible)
	assert_eq(o.reset_irrigation(), Irrigation.initial())
	assert_true(o.water["drain_pond"].visible)


func test_lamp_needs_irrigation_and_the_cleared_pocket_and_lights_once() -> void:
	var o: Node3D = await _orchard()
	var lamp: Node3D = o.interactables["garden_lamp"]
	var p0: Dictionary = lamp.get_interaction(null)
	assert_false(bool(p0["enabled"]), "not yet")
	assert_true(String(p0["reason"]).contains("dry") and String(p0["reason"]).contains("crooked patch"), "the reason names both missing things")
	assert_false(o.light_lamp())
	# Only irrigation: still no.
	Irrigation.store_state({"junction": "garden", "gate": true})
	assert_false(o.can_light_lamp())
	assert_true(String(lamp.get_interaction(null)["reason"]).contains("twitching"), "only the pocket missing")
	assert_false(o.light_lamp())
	assert_false(flag(Data.FLAG_LAMP_LIT))
	# Only the pocket: still no.
	GameState.set_flag(Data.FLAG_IRRIGATED, false)
	o.mimic_pocket.mark_cleared(false)
	assert_false(o.can_light_lamp())
	assert_true(String(lamp.get_interaction(null)["reason"]).contains("dry"), "only the water missing")
	# Both: it lights, exactly once.
	GameState.set_flag(Data.FLAG_IRRIGATED, true)
	var sets := [0]
	var cb := func(f: String, _v: Variant) -> void:
		if f == Data.FLAG_LAMP_LIT:
			sets[0] += 1
	Events.flag_set.connect(cb)
	assert_true(bool(lamp.get_interaction(null)["enabled"]))
	lamp.interact(null)
	assert_true(flag(Data.FLAG_LAMP_LIT), "ch2_garden_lamp_lit")
	assert_true(flag(Data.FLAG_FOUND_LAMP), "lighting it also counts as finding it")
	assert_false(o.light_lamp(), "never twice")
	lamp.interact(null)
	Events.flag_set.disconnect(cb)
	assert_eq(sets[0], 1, "the lamp flag is set exactly once")
	assert_true(o._lamp_light.visible, "the lamp glows")
	assert_false(o._lamp_light.shadow_enabled)
	assert_eq(lamp.get_interaction(null), {}, "no prompt once lit")
	assert_false(GameState.has_reward("rw_ch2_orchard"), "the orchard never pays the seal itself")


func test_quest_layer_pays_the_garden_seal_once_from_our_flag() -> void:
	var o: Node3D = await _orchard()
	for f in ["chapter_one_complete", "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons", "ch2_read_festival_map",
			"ch2_found_quarry_lamp", "ch2_found_manor_lamp"]:
		GameState.set_flag(f, true)
	Irrigation.store_state({"junction": "garden", "gate": true})
	o.mimic_pocket.mark_cleared(false)
	GameState.chapter2.evaluate()
	assert_eq(GameState.count_item("garden_seal"), 0, "no seal before the lamp")
	assert_true(o.light_lamp())
	for i in 3:
		GameState.chapter2.evaluate()
	assert_true(GameState.has_reward("rw_ch2_orchard"), "the quest layer paid rw_ch2_orchard")
	assert_eq(GameState.count_item("garden_seal"), 1, "exactly one Garden Seal")
	assert_true(flag("ch2_orchard_restored"), "carving / cooking unlock flag set by the quest layer")
	assert_false(o.light_lamp())
	GameState.chapter2.evaluate()
	assert_eq(GameState.count_item("garden_seal"), 1, "still one")


func test_lamp_is_found_on_approach_or_sight() -> void:
	var o: Node3D = await _orchard()
	var lp: Vector2 = Data.GARDEN["lamp"]
	var pl := _player_at(lp + Vector2(0, 40))
	o.player_override = pl
	o.screen_override = 1
	o.tick(0.2)
	assert_false(flag(Data.FLAG_FOUND_LAMP), "too far to notice")
	pl.global_position = Vector3(lp.x, 0, lp.y + 25.0)
	o.screen_override = 0
	o.tick(0.2)
	assert_false(flag(Data.FLAG_FOUND_LAMP), "25 m away and not looking")
	o.screen_override = 1
	o.tick(0.2)
	assert_true(flag(Data.FLAG_FOUND_LAMP), "seen from 25 m")
	GameState.set_flag(Data.FLAG_FOUND_LAMP, false)
	o.screen_override = 0
	pl.global_position = Vector3(lp.x + 10.0, 0, lp.y)
	o.tick(0.2)
	assert_true(flag(Data.FLAG_FOUND_LAMP), "found by walking up to it, even without looking")


func test_festival_seed_needs_water_and_grows_once() -> void:
	var o: Node3D = await _orchard()
	var seed_it: Node3D = o.interactables["festival_seed"]
	# First press opens the box: the garden note (MP §17, "A Note in the Seed Box") is read and journaled.
	assert_false(o.interactables.has("garden_note"), "the note lives in the seed box, not on a separate post")
	var p_open: Dictionary = seed_it.get_interaction(null)
	assert_eq(String(p_open["text"]), "Open the seed box")
	assert_true(bool(p_open["enabled"]))
	var said := []
	var cb := func(speaker: String, text: String, _secs: float) -> void:
		said.append([speaker, text])
	Events.say.connect(cb)
	seed_it.interact(null)
	Events.say.disconnect(cb)
	assert_true(flag(Data.FLAG_GARDEN_NOTE) and GameState.lore.has(Data.LORE_GARDEN), "note read and in the journal")
	assert_eq(said.size(), 1, "the note is shown")
	if said.size() == 1:
		assert_eq(String(said[0][1]), "Plant the round ones for supper. Carve the crooked ones for company. Do not feed the one that feeds itself.", "MP §17 garden note, verbatim")
	assert_false(flag(Data.FLAG_SEED_PLANTED), "opening the box plants nothing")
	var p0: Dictionary = seed_it.get_interaction(null)
	assert_eq(String(p0["text"]), "Plant the festival seed")
	assert_false(bool(p0["enabled"]), "the dry bed refuses the seed")
	assert_true(String(p0["reason"]).contains("Water"), "the reason points at the irrigation")
	seed_it.interact(null)
	assert_false(o.plant_festival_seed())
	assert_false(o._festival.visible)
	Irrigation.store_state({"junction": "garden", "gate": true})
	assert_true(bool(seed_it.get_interaction(null)["enabled"]))
	var inv_before: Array = GameState.inventory.to_array() if GameState.inventory.has_method("to_array") else []
	assert_true(o.plant_festival_seed(), "planted (no seed item needed: guaranteed)")
	assert_true(o.growing, "the growth beat plays")
	assert_eq(seed_it.get_interaction(null), {}, "no prompt while growing")
	assert_true(flag(Data.FLAG_SEED_PLANTED), "saved at once")
	await wait_seconds(OrchardC.GROW_SECONDS + 0.4)
	assert_false(o.growing, "the beat finished")
	assert_true(o._festival.visible and o._festival_pumpkin.visible, "a festival pumpkin grew")
	assert_almost(o._festival_pumpkin.scale.x, 1.0, 0.01)
	assert_false(o.plant_festival_seed(), "only once")
	assert_false(seed_it.active, "the seed box is done")
	if not inv_before.is_empty():
		assert_eq(GameState.inventory.to_array(), inv_before, "no inventory change")


func test_mimic_pocket_falls_back_safely_without_the_enemy_script() -> void:
	var o: Node3D = await _orchard()
	var pocket: Node3D = o.mimic_pocket
	pocket.instant = true
	B.availability_override = {"pumpkin_mimic": false}
	assert_eq(pocket.state, "dormant")
	assert_eq(pocket.dormant.size(), (Data.MIMIC_POCKET["dormant"] as Array).size())
	for dm in pocket.dormant:
		assert_eq(String((dm["interact"] as Node3D).get_interaction(null)["text"]), "Inspect twitching pumpkin")
	(pocket.dormant[0]["interact"] as Node3D).interact(null)
	assert_eq(pocket.state, "cleared", "no enemy script: the pumpkins bounce away and the patch is quiet")
	assert_true(pocket.fallback_used)
	assert_null(pocket.spawner, "nothing spawned")
	assert_true(flag(Data.FLAG_MIMICS_CLEARED) and flag("spawner_cleared_hr_sp_orchard_mimics"), "cleared flags")
	for dm2 in pocket.dormant:
		assert_false((dm2["root"] as Node3D).visible)
		assert_eq((dm2["interact"] as Node3D).get_interaction(null), {}, "no more inspect prompt")
	assert_true(o.mimics_cleared())
	assert_false(pocket.wake(), "never wakes twice")


func test_mimic_pocket_wakes_through_the_real_spawner_and_clears() -> void:
	var o: Node3D = await _orchard()
	var pocket: Node3D = o.mimic_pocket
	pocket.instant = true
	pocket.enemy_override = "brambling"       # an existing enemy stands in for the later-wave pumpkin_mimic
	var pl := _player_at((Data.MIMIC_POCKET["center"] as Vector2) + Vector2(7, 0))
	var crops_before: Dictionary = GameState.crops.duplicate(true)
	var structures_before: int = GameState.structures.size()
	# Standing right beside a dormant mimic wakes it too (after half a second).
	var dm0: Vector3 = (pocket.dormant[0]["root"] as Node3D).global_position
	pocket.tick(Vector3(dm0.x + 1.0, 0, dm0.z), 0.3)
	assert_eq(pocket.state, "dormant", "not instantly")
	pocket.tick(Vector3(dm0.x + 1.0, 0, dm0.z), 0.3)
	assert_eq(pocket.state, "awake", "woke after standing beside it")
	var sp: Node3D = pocket.spawner
	assert_not_null(sp, "the spawner exists once awake")
	assert_eq(String(sp.get("spawner_id")), "hr_sp_orchard_mimics")
	assert_eq(int(sp.get("count")), int(Data.SPAWNERS["hr_sp_orchard_mimics"]["count"]))
	assert_true(float(sp.get("respawn_minutes")) < 0.0, "story group: never respawns")
	assert_eq(String(sp.get("quest_flag_on_clear")), Data.FLAG_MIMICS_CLEARED)
	sp.set_process(false)
	sp.player_override = pl
	sp.update_spawner()
	assert_eq((sp.alive as Array).size(), 2, "two mimics for the teaching encounter")
	for e in (sp.alive as Array).duplicate():
		(e as Node).set_physics_process(false)
		(e as Node).set_process(false)
		assert_false((e as Node).is_in_group("structure"), "an enemy, never a structure")
	for e2 in (sp.alive as Array).duplicate():
		e2.health.apply_damage(99999.0)
	assert_eq(pocket.state, "cleared", "cleared through the spawner")
	assert_true(flag(Data.FLAG_MIMICS_CLEARED))
	assert_true(flag("spawner_cleared_hr_sp_orchard_mimics"))
	assert_eq(GameState.crops, crops_before, "player crops untouched")
	var structures_after: int = GameState.structures.size()
	assert_eq(structures_after, structures_before, "no structure touched")
	await wait_frames(3)


func test_mimic_interaction_only_on_the_pockets_own_props() -> void:
	var h: Node3D = await flat_host()
	var d := await build_all(h)
	var found := 0
	for key in ["orchard", "pools", "candleyard"]:
		for it in interactables_under(d[key]):
			var t := String((it as Node).get_interaction(null).get("text", ""))
			if t.contains("twitching"):
				found += 1
				assert_true((it as Node).has_meta("mimic_pocket"), "%s belongs to the mimic pocket" % it.name)
				assert_false((it as Node).is_in_group("structure"), "never a structure / crop plot")
				var gp: Vector3 = (it as Node3D).global_position
				assert_true(Vector2(gp.x, gp.z).distance_to(Data.MIMIC_POCKET["center"]) <= float(Data.MIMIC_POCKET["radius"]), "inside the marked ring")
				assert_true(Vector2(gp.x, gp.z).distance_to(Data.OUTPOST_CENTER) > 60.0, "far from any build area")
	assert_eq(found, (Data.MIMIC_POCKET["dormant"] as Array).size(), "only the dormant mimics say 'Inspect twitching pumpkin'")
	# A placed crop anywhere keeps its own interaction: nothing in this module scans structures or crops.
	for f in ["mimic_pocket.gd", "orchard_controller.gd", "west_build.gd", "pumpkin_moment.gd"]:
		var src: String = (load("res://src/world/reach/west/" + f) as Script).source_code
		assert_false(src.contains("GameState.structures") or src.contains("GameState.crops") or src.contains("\"crop_plot\""), "%s never looks at player structures / crops" % f)


func test_debug_hook_clears_the_pocket() -> void:
	var o: Node3D = await _orchard()
	assert_true(Debug.is_cheat_allowed(), "tests run in a debug build")
	assert_true(o.mimic_pocket.debug_clear())
	assert_true(o.mimics_cleared())
	# A rebuilt orchard shows the cleared patch (no dormant prompts).
	var h2: Node3D = await flat_host()
	GameState.set_flag(Data.FLAG_MIMICS_CLEARED, true)
	var o2: Node3D = Orchard.build_district(h2)
	assert_eq(o2.mimic_pocket.state, "cleared")
	for dm in o2.mimic_pocket.dormant:
		assert_false((dm["interact"] as Node3D).active)


func test_patchwalker_spawner_is_guarded() -> void:
	var o: Node3D = await _orchard()
	var pw_available := B.enemy_available("patchwalker")
	if pw_available:
		assert_not_null(o.spawners["hr_sp_orchard_patchwalkers"], "the Patchwalker field spawns once its script exists")
	else:
		assert_null(o.spawners["hr_sp_orchard_patchwalkers"], "no spawner (and no per-tick warnings) while the enemy script is missing")
	B.availability_override = {"patchwalker": true}
	var o2: Node3D = await _orchard()
	var sp: Node3D = o2.spawners["hr_sp_orchard_patchwalkers"]
	assert_not_null(sp)
	sp.set_process(false)
	assert_eq(String(sp.get("enemy_id")), "patchwalker")
	assert_eq(String(sp.get("spawner_id")), "hr_sp_orchard_patchwalkers")
	assert_true(float(sp.get("respawn_minutes")) > 0.0, "an optional, repeatable group")
	assert_eq(String(sp.get("quest_flag_on_clear")), "", "not a story gate")


func test_high_visibility_cues_and_timing_assist() -> void:
	var o: Node3D = await _orchard()
	var cued := ["lever_junction", "lever_gate", "festival_seed", "garden_lamp"]
	for id in cued:
		assert_false(o.interactables[id].is_cue_visible(), "%s: no bold ring by default" % id)
	Settings.set_value("high_visibility_cues", true)
	for id2 in cued:
		assert_true(o.interactables[id2].is_cue_visible(), "%s: bold ring with high_visibility_cues" % id2)
	for dm in o.mimic_pocket.dormant:
		assert_true((dm["interact"] as Node3D).is_cue_visible(), "dormant mimics are ringed too")
	Settings.set_value("high_visibility_cues", false)
	assert_false(o.interactables["garden_lamp"].is_cue_visible())
	# timing_assist: the twitching pumpkins take twice as long to wake (a calmer tell).
	B.availability_override = {"pumpkin_mimic": false}
	Settings.set_value("timing_assist", true)
	o.mimic_pocket.inspect()
	assert_eq(o.mimic_pocket.state, "waking")
	await wait_seconds(Pocket.WAKE_DELAY + 0.3)
	assert_eq(o.mimic_pocket.state, "waking", "still only twitching with timing_assist")
	await wait_seconds(Pocket.WAKE_DELAY_ASSIST - Pocket.WAKE_DELAY + 0.3)
	assert_eq(o.mimic_pocket.state, "cleared", "then it resolves (here: the missing-script fallback)")
