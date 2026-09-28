extends "res://tests/test_case.gd"
## The Hushed Works, rooms 1-8: quest / optional flags and rewards (set by place and by interaction, once),
## the refuge shortcut home (flag + exit + open grate), checkpoints that set the hushed_works respawn, the MP
## §17 lore lines, the Light Well keepsake through the reward ledger, guarded enemy spawners with a debug
## clear hook, save / load of every piece of this module's state, and a real Game arrival (director with the
## Works events, saving only in safe places, resting and Continue).

const Layout := preload("res://data/works_layout.gd")
const LoreDB := preload("res://src/core/lore_db.gd")
const WORLD := "res://src/world/areas_ch2/hushed_works_world.gd"

var area: Node3D = null
var _probe: Node3D = null


func before_each() -> void:
	fresh_state()


func after_each() -> void:
	if area != null and is_instance_valid(area):
		area.queue_free()
	area = null
	if _probe != null and is_instance_valid(_probe):
		_probe.queue_free()
	_probe = null
	await wait_frames(2)


func _make_area() -> Node3D:
	var a: Node3D = load(WORLD).new()
	a.use_deep = false
	add_child(a)
	await wait_physics(2)
	return a


func _probe_at(p: Vector3) -> Node3D:
	if _probe == null:
		_probe = Node3D.new()
		add_child(_probe)
	_probe.global_position = p
	return _probe


# --- Lore ----------------------------------------------------------------------------------------------------------------

func test_lore_uses_the_mp17_lines_verbatim() -> void:
	LoreDB.reload()
	# Tobin's note is the annex's lore id (data/lore_ch2_annex.gd); the Works shows its context at the sluice.
	var want := {
		"lore_ch2_hask_note": "The knock came back a beat too late. I put my lamp beside the rail. A true light stays with what holds it.",
		"lore_ch2_tobin_note": "I dropped the lantern when the passage answered me. Hask found me at the sluice. Tell whoever comes after us: the garden below is real.",
		"lore_ch2_refuge_record": "Three of us made the garden. Tobin, Hask, and me. We left by the drainage stair at dawn. The voices stayed behind.",
		"lore_ch2_before_choir": "It has learned a welcome. It has not learned a home.",
	}
	for id in want:
		assert_true(LoreDB.has_lore(id), "%s known to LoreDB" % id)
		assert_eq(String(LoreDB.get_lore(id)["text"]), String(want[id]), id)
	assert_true(LoreDB.has_lore("lore_ch2_bell_throat_note"), "the deep module's Bell Throat note exists")
	for id in Layout.LORE_SPOTS:
		assert_true(LoreDB.has_lore(String(id)), "placed note %s has text" % id)
		assert_ne(String(LoreDB.get_lore(String(id))["title"]), "", "%s has a title" % id)


func test_reading_notes_discovers_lore_and_sets_their_flags() -> void:
	area = await _make_area()
	var note: Node = area.lore_notes["lore_ch2_hask_refuge_note"]
	note.interact(null)
	assert_true(GameState.lore.has("lore_ch2_hask_refuge_note"), "lore discovered")
	assert_true(bool(GameState.get_flag("ch2_hask_note_found")), "opt_miner_came_back objective flag")
	area.lore_notes["lore_ch2_hask_note"].interact(null)
	assert_true(GameState.lore.has("lore_ch2_hask_note"))
	var rec: Node = area.get_node("RefugeRecord")
	assert_eq(String(rec.get_interaction(null)["text"]), "Read the refuge record")
	rec.interact(null)
	assert_true(bool(GameState.get_flag("ch2_refuge_record")), "ch2_miners objective")
	assert_true(bool(GameState.get_flag("ch2_refuge_reached")))
	assert_true(GameState.lore.has("lore_ch2_refuge_record"))


# --- Progress flags by place -------------------------------------------------------------------------------------------------

func test_flags_by_place() -> void:
	area = await _make_area()
	var m: Node = area.moments
	var p := _probe_at(Vector3(-20.0, -11.0, 0.0))
	m.check(p, 0.1)
	assert_eq(String(m.room), "rails")
	assert_false(bool(GameState.get_flag("ch2_true_signal")), "not in the rail hall itself")
	p.global_position = Vector3(1.0, -11.0, 0.0)
	m.check(p, 0.1)
	assert_true(bool(GameState.get_flag("ch2_true_signal")), "the rail junction by Hask's lamp")
	p.global_position = Vector3(26.0, -18.0, 6.0)
	m.check(p, 0.1)
	assert_true(bool(GameState.get_flag("ch2_refuge_reached")), "the refuge")
	assert_false(bool(GameState.get_flag("ch2_refuge_shortcut")), "reaching it does not open the shortcut")


func test_refuge_shortcut_opens_the_way_home() -> void:
	area = await _make_area()
	var ex: Node = area.exits["refuge_shortcut"]
	assert_false(bool(ex.is_unlocked()), "barred at first")
	assert_false(bool(ex.get_interaction(null)["enabled"]))
	assert_eq(ex.destination(), {"area": "hallowmere_reach", "spawn": "refuge_exit"})
	assert_true(ex.is_in_group("area_exit"))
	var wheel: Node = area.get_node("ShortcutWheel")
	assert_false((wheel.get_interaction(null) as Dictionary).is_empty(), "the wheel offers itself")
	wheel.interact(null)
	assert_true(bool(GameState.get_flag("ch2_refuge_shortcut")), "ch2_refuge_shortcut (step ch2_refuge, opt_long_way_home)")
	assert_true(bool(GameState.get_flag("ch2_refuge_reached")))
	assert_true(bool(ex.is_unlocked()), "the drainage stair leads home now")
	assert_true(bool(area.doors["refuge_grate"].is_open), "the bars are gone")
	assert_true((wheel.get_interaction(null) as Dictionary).is_empty(), "the wheel has done its job")
	# The landing's way back up always works.
	var up: Node = area.exits["bellhouse_stair"]
	assert_true(bool(up.is_unlocked()))
	assert_eq(up.destination(), {"area": "hallowmere_reach", "spawn": "bellhouse_stair"})


func test_checkpoints_set_the_works_respawn() -> void:
	area = await _make_area()
	for id in Layout.CHECKPOINTS:
		var d: Dictionary = Layout.CHECKPOINTS[id]
		var cp: Node = area.checkpoints[id]
		assert_true(String(id).begins_with("hw_"), "checkpoint ids are hw_*")
		assert_eq(String(cp.name), "RestPoint_" + String(d["spawn"]))
		cp.save_enabled = false
		cp.interact(null)
		assert_true(bool(GameState.get_flag("cp_lit_" + String(id))), "cp_lit_%s" % id)
		assert_eq(String(GameState.player.get("respawn_area", "")), "hushed_works", "respawn area")
		assert_eq(String(GameState.player.get("respawn_spawn", "")), String(d["spawn"]), "respawn spawn")
		assert_eq(Game.area_respawn_of("hushed_works"), String(d["spawn"]), "remembered per area")
		assert_true(area.is_safe_zone(d["pos"]), "the lantern stands in a safe nook")


func test_misplaced_lantern_reveals_the_carvers_rest() -> void:
	area = await _make_area()
	var lan: Node3D = area.eyes_lantern
	var it: Node = lan.get_node("Hang")
	assert_eq(String(it.get_interaction(null)["text"]), "Hang the fallen lantern back on its hook")
	assert_false(bool(area.doors["eyes_route"].is_open))
	assert_false((lan.get_node("Body/Light") as Light3D).visible, "unlit on the floor")
	it.interact(null)
	assert_true(bool(GameState.get_flag(Layout.FLAG_EYES_ROUTE)))
	assert_true(bool(area.doors["eyes_route"].is_open), "the great face opens")
	assert_true((lan.get_node("Body/Light") as Light3D).visible, "the lantern burns on its hook")
	await wait_seconds(1.2)
	assert_almost(lan.global_position.distance_to(Layout.EYES_LANTERN_HOOK), 0.0, 0.05, "hung on the hook")


func test_keepsake_trunk_uses_the_ledger_once() -> void:
	area = await _make_area()
	var bundle: Dictionary = ItemDB.reward_bundle(Layout.ALCOVE_REWARD_ID)
	var first: bool = area._open_trunk(null)
	var second: bool = area._open_trunk(null)
	assert_true(bool(GameState.get_flag(Layout.ALCOVE_FOUND_FLAG)), "found flag")
	assert_false(second, "never paid twice")
	if bundle.is_empty():
		assert_false(first, "no data/sources.gd bundle yet: nothing granted")
		assert_false(GameState.has_reward(Layout.ALCOVE_REWARD_ID), "and the ledger stays open for when it exists")
	else:
		assert_true(first, "the bundle is granted once")
		assert_true(GameState.has_reward(Layout.ALCOVE_REWARD_ID))
		assert_eq(String(area.get_node("KeepsakeTrunk").get_interaction(null)["text"]), "The keepsake trunk")


func test_spawners_are_guarded_and_can_be_cleared_in_tests() -> void:
	area = await _make_area()
	for id in Layout.SPAWNERS:
		var placed: bool = (area.spawners as Dictionary).has(id)
		var skipped: bool = (area.skipped_spawners as Array).has(id)
		assert_true(placed != skipped, "%s is either placed or skipped (placed %s)" % [id, str(placed)])
		if placed:
			assert_eq(String(area.spawners[id].get("enemy_id")), String(Layout.SPAWNERS[id]["enemy"]), "%s spawns its enemy by id" % id)
	# Placed exactly when the factory knows that enemy AND its script file exists.
	var factory: Script = load("res://src/enemies/enemy_factory.gd")
	for id in Layout.SPAWNERS:
		var enemy := String(Layout.SPAWNERS[id]["enemy"])
		var known := bool(factory.call("has_enemy", enemy)) and ResourceLoader.exists(String(factory.call("script_path", enemy)))
		assert_eq((area.spawners as Dictionary).has(id), known, "%s placed iff %s is registered and its script exists" % [id, enemy])
		assert_eq(bool(area.enemy_available(enemy)), known)
	assert_null(area.add_spawner({"spawner_id": "hw_sp_test_missing", "enemy": "no_such_enemy"}, Vector3(-47.0, -7.0, 0.0)), "an unknown enemy is skipped")
	assert_true((area.skipped_spawners as Array).has("hw_sp_test_missing"), "and recorded")
	assert_true(area.debug_clear_encounter("hw_sp_lockers"), "debug hook works in debug builds")
	assert_true(bool(GameState.get_flag("spawner_cleared_hw_sp_lockers")))
	assert_true(bool(GameState.get_flag(Layout.FLAG_LOCKERS_CLEARED)))
	# Nothing in rooms 1-8 waits on a fight: every line and the refuge work without the enemies.
	assert_eq(Layout.SPAWNERS["hw_sp_bells"]["quest_flag_on_clear"], "", "the bell line never depends on the sentries")


func test_save_and_load_restore_the_module_state() -> void:
	area = await _make_area()
	area.get_node("ShortcutWheel").interact(null)
	area.eyes_lantern.get_node("Hang").interact(null)
	area.sluice.turn(0)
	area.sluice.turn(1)
	var cp: Node = area.checkpoints["hw_refuge"]
	cp.save_enabled = false
	cp.interact(null)
	area.moments.check(_probe_at(Vector3(1.0, -11.0, 0.0)), 0.1)
	GameState.set_flag(Layout.MOMENT_KNOCK, true)
	assert_true(SaveSystem.save_game(true), "saved")
	fresh_state()
	assert_false(bool(GameState.get_flag("ch2_line_water")), "state cleared")
	assert_true(SaveSystem.load_game(), "loaded")
	for f in ["ch2_refuge_shortcut", "ch2_refuge_reached", Layout.FLAG_EYES_ROUTE, "ch2_line_water", "cp_lit_hw_refuge",
			"ch2_true_signal", Layout.MOMENT_KNOCK]:
		assert_true(bool(GameState.get_flag(f)), "%s survives save/load" % f)
	assert_eq(Game.area_respawn_of("hushed_works"), "refuge")
	area.queue_free()
	await wait_frames(2)
	area = await _make_area()
	assert_true(bool(area.doors["refuge_grate"].is_open), "grate open after load")
	assert_true(bool(area.doors["eyes_route"].is_open), "carvers' rest open after load")
	assert_true(bool(area.sluice.solved), "sluice solved after load")
	assert_true(bool(area.checkpoints["hw_refuge"].lit), "refuge lantern lit after load")
	assert_false(bool(area.checkpoints["hw_lockers"].lit), "the others stay unlit")
	assert_eq(String(area.moments.knock_state), "", "the knock is armed only by walking (and its flag keeps it done)")


# --- The flow module's area contract (test_flow_ch2_areas), on the real scene incl. the deep rooms ------------------------------

func test_scene_meets_the_flow_contract() -> void:
	var t0 := Time.get_ticks_msec()
	var a: Node3D = (load(String(Game.AREAS["hushed_works"])) as PackedScene).instantiate()
	add_child(a)
	await wait_physics(2)
	var ms := Time.get_ticks_msec() - t0
	area = a
	print("  hushed_works scene: %d ms (deep rooms: %s) %s" % [ms, str(a.get("deep_present")), str(a.get("build_times"))])
	assert_eq(String(a.get("area_id")), "hushed_works")
	assert_false(bool(a.get("placeholder") == true), "the real Works (no placeholder flag)")
	for sp in Layout.REQUIRED_SPAWNS:
		assert_true((a.spawns as Dictionary).has(sp), "spawn %s" % sp)
		var p: Vector3 = (a.spawns[sp] as Transform3D).origin
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.0, p + Vector3.DOWN * 6.0)
		q.collision_mask = 1 | 32
		var hit := a.get_world_3d().direct_space_state.intersect_ray(q)
		assert_false(hit.is_empty(), "ground under %s" % sp)
		if not hit.is_empty():
			assert_almost(float(hit["position"].y), p.y, 0.35, "%s on the ground" % sp)
		assert_true(a.validate_position(p) is Vector3, "%s valid position" % sp)
	for sp in ["service_landing", "works_lockers", "refuge", "crossing_gate", "bell_throat"]:
		assert_true(a.is_safe_zone((a.spawns[sp] as Transform3D).origin), "%s is safe" % sp)
	for p in [Vector3(-14, 0, -7), Vector3(14, 0, -21)]:
		assert_false(a.is_safe_zone(p), "%s is not safe" % str(p))
	var zone_ids: Array = (a.zones as Array).map(func(z: Dictionary) -> String: return String(z["id"]))
	for z in Layout.ZONES:
		assert_true(zone_ids.has(z), "zone %s" % z)
	var has_env := false
	var has_light := false
	for c in a.get_children():
		has_env = has_env or c is WorldEnvironment
		has_light = has_light or c is Light3D
	assert_true(has_env, "WorldEnvironment")
	assert_true(has_light, "a light directly under the area")
	var legal := {"hallowmere_reach": ["waygate_arrival", "reach_respawn", "commons_arch", "orchard_arch", "quarry_arch",
		"manor_arch", "conservatory", "manor_door", "bellhouse_stair", "refuge_exit"]}
	var outs := 0
	for n in a.find_children("*", "Node3D", true, false):
		if n.is_in_group("area_exit"):
			outs += 1
			if n.get("use_respawn") == true:
				continue
			var ta := String(n.get("target_area"))
			assert_true(legal.has(ta) and (legal[ta] as Array).has(String(n.get("target_spawn"))), "exit %s -> %s/%s" % [n.name, ta, String(n.get("target_spawn"))])
	assert_true(outs >= 2, "ways out (%d)" % outs)


# --- A real arrival through Game (the flow module's harness pattern) ------------------------------------------------------------

func test_game_arrival_director_saving_and_continue() -> void:
	var runner := get_tree().current_scene
	var saved_mode := Game.mode
	var ph := Node.new()
	ph.name = "WorksPlaceholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	GameState.active = true
	Game.load_area("hushed_works", "refuge", false)
	var ok: bool = await _until(func() -> bool: return Game.mode == "playing" and not Game._transitioning and Game.area_id == "hushed_works" and Game.player != null)
	assert_true(ok, "arrived in the Works")
	if ok:
		await wait_seconds(0.7)
		assert_true(bool(GameState.get_flag("ch2_service_gate_open")), "arrival repairs a missing service-gate flag")
		var d: Node = Game.director
		assert_not_null(d, "the Works has a horror director (Game.DIRECTOR_AREAS)")
		if d != null:
			assert_true((d.core.events as Dictionary).has("hw_rail_hum"), "with the Works events")
			assert_false((d.core.events as Dictionary).has("distant_pickaxe"), "and none of the Chapter One ones")
			assert_true(d.has_method("hold"), "stacking-safe holds")
		assert_true(Game.player_in_safe_zone(), "the refuge is safe")
		assert_true(bool(Game.can_manual_save()["ok"]), "saving allowed in the refuge")
		Game.player.teleport(Transform3D(Basis.IDENTITY, Vector3(-20.0, -10.95, 0.0)))
		await wait_physics(2)
		assert_false(Game.player_in_safe_zone(), "the rail hall is not safe")
		assert_false(bool(Game.can_manual_save()["ok"]), "no saving in the rail hall")
		var rest: Node = Game.area.get_node_or_null("RestPoint_works_lockers")
		assert_not_null(rest, "the lockers lantern")
		if rest != null:
			rest.interact(null)
			assert_eq([String(GameState.player.get("respawn_area")), String(GameState.player.get("respawn_spawn"))], ["hushed_works", "works_lockers"])
			fresh_state()
			Game.continue_game()
			var back: bool = await _until(func() -> bool: return Game.mode == "playing" and not Game._transitioning and Game.area_id == "hushed_works" and Game.player != null)
			assert_true(back, "Continue in the Works")
			if back:
				await wait_seconds(0.7)
				var xf: Transform3D = Game.area.get_spawn("works_lockers")
				assert_true(Vector2(Game.player.global_position.x - xf.origin.x, Game.player.global_position.z - xf.origin.z).length() < 1.2, "resumes at the lockers lantern")
	# Cleanup like test_flow_ch2_roundtrip.
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.companion_nodes = {}
	Game.director = null
	Game.zone_id = ""
	Game.in_safe_zone = true
	Game.mode = saved_mode
	Game._bosses.clear()
	var cs := get_tree().current_scene
	if cs != null and cs != runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "WorksPlaceholder" or n.name == "HushedWorks":
			n.queue_free()
	get_tree().current_scene = runner
	get_tree().paused = false
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


func _until(cond: Callable, max_frames: int = 1500) -> bool:
	for i in max_frames:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
	return bool(cond.call())
