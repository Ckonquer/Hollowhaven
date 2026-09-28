extends "res://tests/test_case.gd"
## Game flow rules for Chapter Two (autoload/game.gd, docs/CHAPTER_TWO_SPEC.md §1, §5, §8, MP §9):
## manual save / quiet autosave per area (SAFE_SAVE_AREAS anywhere; other Chapter Two areas in a safe
## zone; the Below and trials never; never with a boss active or something chasing within 20 m),
## per-area respawn memory, the Lantern Road list and gate, companion_present(), the new-game look,
## complete_chapter_two() granting exactly once (twice in a row, and after a save/reload) with one gifts toast,
## and Continue on an upper storey (the saved spot is validated again once the structures exist).

const Reach := preload("res://data/hallowmere_layout.gd")

var _saved := {}
var _tmp: Array = []


func before_each() -> void:
	fresh_state()
	_saved = {"mode": Game.mode, "area_id": Game.area_id, "area": Game.area, "player": Game.player,
		"safe": Game.in_safe_zone, "companions": Game.companion_nodes}
	Game.mode = "playing"
	Game.area = null
	Game.player = null
	Game.companion_nodes = {}
	Game._autosave_t = 0.0
	Game._bosses.clear()
	SaveSystem.delete_test_saves()


func after_each() -> void:
	Game.mode = String(_saved["mode"])
	Game.area_id = String(_saved["area_id"])
	Game.area = _saved["area"]
	Game.player = _saved["player"]
	Game.in_safe_zone = bool(_saved["safe"])
	Game.companion_nodes = _saved["companions"]
	Game._bosses.clear()
	Game._autosave_t = 0.0
	GameState.active = false
	for n in _tmp:
		if is_instance_valid(n):
			n.queue_free()
	_tmp.clear()
	await wait_frames(2)


func _node(pos: Vector3, groups: Array = [], source: String = "") -> Node3D:
	var n := Node3D.new()
	if source != "":
		var s := GDScript.new()
		s.source_code = source
		s.reload()
		n.set_script(s)
	add_child(n)
	n.global_position = pos
	for g in groups:
		n.add_to_group(String(g))
	_tmp.append(n)
	return n


func _ok(area: String, safe: bool) -> bool:
	Game.area_id = area
	Game.in_safe_zone = safe
	return bool(Game.can_manual_save()["ok"])


# --- Saving ------------------------------------------------------------------------------------------

func test_manual_save_rules_per_area() -> void:
	assert_true(_ok("surface", false), "surface: anywhere")
	assert_true(_ok("hallowmere_reach", false), "Reach: anywhere (like the surface)")
	assert_false(_ok("below", true), "Below: lanterns only, even in a safe zone")
	Game.area_id = "below"
	assert_eq(String(Game.can_manual_save()["reason"]), "Underground, rest at a lit lantern to save.", "legacy wording kept")
	assert_false(_ok("echo_trial", true), "trials never save")
	for a in ["tobin_annex", "moonveil_manor", "hushed_works"]:
		assert_false(_ok(a, false), "%s: not outside a safe zone" % a)
		assert_true(_ok(a, true), "%s: in a safe zone" % a)
	assert_false(_ok("arena", true), "unregistered (debug) areas keep the old refusal")
	Game.mode = "cutscene"
	assert_false(_ok("surface", true), "not during a cutscene")
	Game.mode = "playing"


func test_no_save_during_a_boss_encounter() -> void:
	Events.boss_encounter_changed.emit("count_velour", true)
	assert_true(Game.boss_active(), "encounter tracked")
	assert_false(_ok("hallowmere_reach", true), "no save while a boss encounter is active")
	assert_false(_ok("moonveil_manor", true), "not even in a safe zone")
	assert_false(bool(Game.can_fast_travel()["ok"]), "no Lantern Road during a boss encounter")
	Events.boss_encounter_changed.emit("count_velour", false)
	assert_true(_ok("hallowmere_reach", false), "saving allowed again after the encounter")
	# The legacy Matron only reports through the boss bar (hp < 0 hides it).
	Events.boss_health_changed.emit("weaver_matron", 120.0, 240.0)
	assert_false(_ok("surface", true), "legacy boss bar visible = boss active")
	Events.boss_health_changed.emit("weaver_matron", -1.0, 240.0)
	assert_true(_ok("surface", true), "bar hidden = over")
	Events.boss_encounter_changed.emit("quarry_warden", true)
	Events.area_exiting.emit("hallowmere_reach")
	assert_false(Game.boss_active(), "leaving the area ends every encounter")


func test_no_save_or_travel_while_something_chases_her() -> void:
	Game.area_id = "hallowmere_reach"
	Game.player = _node(Vector3.ZERO)
	var chaser := _node(Vector3(10, 0, 0), ["enemy"], "extends Node3D\nvar hunting := true\nfunc is_threatening() -> bool:\n\treturn hunting\n")
	var r: Dictionary = Game.can_manual_save()
	assert_false(bool(r["ok"]), "chased within 20 m")
	assert_eq(String(r["reason"]), "You can't save while something is chasing you.")
	assert_false(bool(Game.can_fast_travel()["ok"]), "no fast travel during a chase")
	chaser.global_position = Vector3(25, 0, 0)
	assert_true(bool(Game.can_manual_save()["ok"]), "far enough away")
	assert_true(bool(Game.can_fast_travel()["ok"]), "travel allowed again")
	chaser.set("hunting", false)
	chaser.global_position = Vector3(3, 0, 0)
	assert_true(bool(Game.can_manual_save()["ok"]), "a calm enemy nearby doesn't block saving")


func test_quiet_autosave_per_area() -> void:
	GameState.active = true
	var saves: Array = []
	var cb := func(ok: bool) -> void: saves.append(ok)
	Events.game_saved.connect(cb)
	Game.area_id = "hallowmere_reach"
	Game.in_safe_zone = false
	assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS * 0.5), "not yet")
	assert_true(Game._tick_autosave(Game.AUTOSAVE_SECONDS), "the Reach autosaves like the surface")
	assert_true(SaveSystem.has_save(), "written")
	assert_eq(saves.size(), 0, "quietly")
	SaveSystem.delete_test_saves()
	Game._autosave_t = 0.0
	Game.area_id = "hushed_works"
	assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS * 2.0), "Works: waits outside a safe zone")
	Game.in_safe_zone = true
	assert_true(Game._tick_autosave(Game.AUTOSAVE_RETRY + 0.1), "saves once she rests somewhere safe")
	SaveSystem.delete_test_saves()
	Game._autosave_t = 0.0
	for a in ["below", "echo_trial"]:
		Game.area_id = a
		assert_false(Game._tick_autosave(Game.AUTOSAVE_SECONDS * 2.0), "%s never autosaves" % a)
	assert_false(SaveSystem.has_save(), "nothing written there")
	Events.game_saved.disconnect(cb)


# --- Respawn memory ------------------------------------------------------------------------------------

func test_per_area_respawn_memory() -> void:
	Game.set_respawn("hallowmere_reach", "orchard_arch")
	assert_eq(String(GameState.player["respawn_area"]), "hallowmere_reach")
	assert_eq(String(GameState.player["respawn_spawn"]), "orchard_arch")
	assert_eq(Game.area_respawn_of("hallowmere_reach"), "orchard_arch", "remembered per area")
	Game.set_respawn("hushed_works", "works_lockers")
	assert_eq(Game.area_respawn_of("hallowmere_reach"), "orchard_arch", "other areas keep theirs")
	assert_eq(Game.area_respawn_of("hushed_works"), "works_lockers")
	Game.set_respawn("below", "cp_office")
	assert_eq(String(GameState.player["below_respawn"]), "cp_office", "legacy key kept for the Below")
	assert_eq(Game.area_respawn_of("below"), "cp_office")
	assert_false((GameState.player["area_respawn"] as Dictionary).has("below"), "the Below stays on its legacy key")
	Game.set_respawn("surface", "bed")
	Game.set_respawn("echo_trial", "trial_start")
	assert_false((GameState.player["area_respawn"] as Dictionary).has("surface"), "the surface needs no memory")
	assert_false((GameState.player["area_respawn"] as Dictionary).has("echo_trial"), "trials are never remembered")
	assert_eq([String(GameState.player["respawn_area"]), String(GameState.player["respawn_spawn"])], ["surface", "bed"],
		"a trial never becomes the respawn point (a defeat there returns to the origin)")
	# Old saves: no area_respawn at all -> nothing remembered, the Below falls back to its legacy key.
	fresh_state()
	GameState.player["below_respawn"] = "cp_shrine"
	assert_eq(Game.area_respawn_of("hallowmere_reach"), "")
	assert_eq(Game.area_respawn_of("below"), "cp_shrine")


# --- Lantern Road ---------------------------------------------------------------------------------------

func test_lantern_road_destinations() -> void:
	assert_eq(Game.lantern_road_destinations(), [], "nothing before any arch is lit")
	GameState.set_flag("ch2_arch_quarry", true)
	var d: Array = Game.lantern_road_destinations()
	assert_eq(d.map(func(x: Dictionary) -> String: return String(x["id"])), ["haven", "quarry"], "the Haven + the lit arch")
	assert_eq(d[0], {"id": "haven", "name": "The Haven (home)", "area": "surface", "spawn": "haven_respawn"}, "the ORIGINAL Haven")
	assert_eq(String(d[1]["area"]), "hallowmere_reach")
	assert_eq(String(d[1]["spawn"]), "quarry_arch")
	for id in Reach.ARCH_ORDER:
		GameState.set_flag(Reach.arch_flag(String(id)), true)
	d = Game.lantern_road_destinations()
	assert_eq(d.map(func(x: Dictionary) -> String: return String(x["id"])), ["haven", "commons", "orchard", "quarry", "manor", "conservatory"], "list order")
	assert_eq(String(d[5]["spawn"]), "conservatory")
	assert_false(await Game.lantern_road_travel("nowhere"), "unknown destination")
	Game.mode = "cutscene"
	assert_false(await Game.lantern_road_travel("haven"), "no travel during a cutscene")
	Game.mode = "playing"


func test_lantern_arch_lights_once_then_opens_the_road() -> void:
	var Arch: Script = load("res://src/world/common/lantern_arch.gd")
	var arch: Node3D = Arch.new()
	arch.setup({"id": "orchard", "area": "hallowmere_reach"})
	add_child(arch)
	_tmp.append(arch)
	var lit: Array = []
	var cb := func(id: String) -> void: lit.append(id)
	Events.arch_lit.connect(cb)
	assert_eq(String(arch.get_interaction(null)["text"]), "Light the lantern arch")
	Game.mode = "cutscene"
	assert_false(bool(arch.get_interaction(null)["enabled"]), "greyed while travel isn't allowed")
	arch.interact(null)
	assert_false(bool(GameState.get_flag("ch2_arch_orchard")), "not lit during a cutscene")
	Game.mode = "playing"
	arch.interact(null)
	assert_true(bool(GameState.get_flag("ch2_arch_orchard")), "flag ch2_arch_orchard")
	assert_eq(lit, ["orchard"], "Events.arch_lit")
	assert_eq(String(GameState.player["respawn_spawn"]), "orchard_arch", "the arch lit last is the return point")
	assert_eq(Game.area_respawn_of("hallowmere_reach"), "orchard_arch")
	assert_false(arch.light_arch(), "lit only once")
	assert_eq(lit.size(), 1, "no second arch_lit")
	assert_eq(String(arch.get_interaction(null)["text"]), "Travel the Lantern Road")
	Events.arch_lit.disconnect(cb)


# --- Companions ------------------------------------------------------------------------------------------

func test_companion_present() -> void:
	Game.player = _node(Vector3.ZERO)
	var lumi := _node(Vector3(10, 0, 0))
	Game.companion_nodes = {"lumi": lumi}
	GameState.befriend("lumi")
	GameState.set_companion_assignment("lumi", "follow")
	GameState.active_companion = "lumi"
	assert_true(Game.companion_present("lumi"), "follower within 25 m")
	lumi.global_position = Vector3(30, 0, 0)
	assert_false(Game.companion_present("lumi"), "too far")
	lumi.global_position = Vector3(0, 0, 24)
	assert_true(Game.companion_present("lumi"))
	GameState.active_companion = ""
	assert_false(Game.companion_present("lumi"), "not following")
	GameState.active_companion = "mochi"
	assert_false(Game.companion_present("mochi"), "follower not in this area")
	assert_false(Game.companion_present(""), "no id")


# --- New game look ----------------------------------------------------------------------------------------

func test_new_game_look_is_stored_in_game_state() -> void:
	if not ("appearance" in GameState):
		Game._apply_new_game_look({"hair": "bob"})   # must not crash before schema v2
		return
	var before: Dictionary = (GameState.get("appearance") as Dictionary).duplicate(true)
	var changed: Array = []
	var cb := func() -> void: changed.append(true)
	Events.appearance_changed.connect(cb)
	Game._apply_new_game_look({})
	assert_eq(GameState.get("appearance"), before, "no look -> the default look stays")
	Game._apply_new_game_look({"hair": "bob", "hair_color": "honey", "palette": {"primary": "rose", "secondary": "cream", "accent": "plum"}})
	var look: Dictionary = GameState.get("appearance")
	assert_eq(String(look.get("hair", "")), "bob")
	assert_eq(String(look.get("hair_color", "")), "honey")
	assert_eq(String((look.get("palette", {}) as Dictionary).get("primary", "")), "rose")
	for k in before:
		if not ["hair", "hair_color", "palette"].has(k):
			assert_eq(look.get(k), before[k], "untouched part %s kept" % k)
	assert_eq(changed.size(), 1, "Events.appearance_changed")
	Events.appearance_changed.disconnect(cb)
	# It reaches the save: new_game() saves right after this.
	var data: Dictionary = SaveSystem.build_save_data()
	var st: Dictionary = data.get("state", {})
	if st.has("appearance"):
		assert_eq(String((st["appearance"] as Dictionary).get("hair", "")), "bob", "the chosen look is in the first save")


# --- Chapter Two ending ---------------------------------------------------------------------------------------

func test_complete_chapter_two_grants_once() -> void:
	Game.mode = "boot"          # headless: no cutscene/UI; the flow is the same
	GameState.active = true
	for f in ["ward_restored", "chapter_one_complete", "ch2_accepted", "ch2_choir_defeated", "ch2_homecoming"]:
		GameState.set_flag(f, true)
	var ended: Array = []
	var cb := func() -> void: ended.append(true)
	Events.chapter2_completed.connect(cb)
	var saves: Array = []
	var scb := func(ok: bool) -> void: saves.append(ok)
	Events.game_saved.connect(scb)
	assert_true(await Game.complete_chapter_two({"wood": 3}), "completes")
	assert_true(bool(GameState.get_flag("chapter_two_complete")), "chapter_two_complete")
	assert_eq(GameState.count_item("wood"), 3, "rewards granted")
	assert_true(SaveSystem.has_save(), "committed and saved before the presentation")
	assert_true(ended.size() >= 1, "Events.chapter2_completed")
	if "ledger" in GameState:
		assert_true((GameState.get("ledger") as Dictionary).has(Game.CH2_REWARD_ID), "recorded in the reward ledger")
	# Called again: nothing granted, nothing shown.
	var shown := ended.size()
	assert_false(await Game.complete_chapter_two({"wood": 3}), "second call does nothing")
	assert_eq(GameState.count_item("wood"), 3, "not granted twice")
	assert_eq(ended.size(), shown, "not shown twice")
	# Save, reload, call again.
	assert_true(SaveSystem.save_game(true))
	fresh_state()
	assert_true(SaveSystem.load_game(), "reloaded")
	assert_eq(GameState.count_item("wood"), 3, "reload keeps the rewards once")
	assert_false(await Game.complete_chapter_two({"wood": 3}), "after a reload: nothing again")
	assert_eq(GameState.count_item("wood"), 3, "still granted exactly once")
	assert_false(bool(GameState.get_flag("ward_restored")) == false, "Chapter One stays complete")
	Events.chapter2_completed.disconnect(cb)
	Events.game_saved.disconnect(scb)


## The chapter two ending never re-runs the Chapter One ending.
func test_complete_chapter_two_never_replays_chapter_one() -> void:
	Game.mode = "boot"
	GameState.set_flag("ward_restored", true)
	GameState.set_flag("chapter_one_complete", true)
	var ch1: Array = []
	var cb := func() -> void: ch1.append(true)
	Events.chapter_completed.connect(cb)
	GameState.give_item("heartseed", 1)
	await Game.complete_chapter_two({})
	assert_eq(ch1.size(), 0, "Events.chapter_completed (Chapter One) not emitted")
	assert_eq(GameState.count_item("heartseed"), 1, "complete_chapter() not called (it takes the seed)")
	Events.chapter_completed.disconnect(cb)
	if "ledger" in GameState:
		var oc: Dictionary = Game._feast_step_rewards()
		for f in oc.get("flags", []):
			assert_true(bool(GameState.get_flag(String(f))), "the final step's flag %s is set with the same ledger entry" % f)


## One reward toast at the end of Chapter Two (R06): the ending's grant (rw_ch2_feast) is silent and the
## ch2_feast step's own on_complete message is THE toast (the ending screen already says "Chapter Two complete").
## The rewards are unchanged, and a reload never announces the gifts a second time (the step is completed
## before the ending's commit save).
func test_chapter_two_ending_shows_one_gifts_toast() -> void:
	Game.mode = "boot"          # headless: no cutscene/UI; the commit path is the same
	GameState.active = true
	for f in ["ward_restored", "chapter_one_complete", "ch2_accepted", "ch2_waygate_repaired", "ch2_arch_commons",
			"ch2_read_festival_map", "ch2_found_orchard_lamp", "ch2_found_quarry_lamp", "ch2_found_manor_lamp",
			"ch2_garden_lamp_lit", "ch2_quarry_lamp_lit", "ch2_manor_lamp_lit", "ch2_read_preparations", "ch2_lamps_linked",
			"ch2_service_gate_open", "ch2_true_signal", "ch2_refuge_reached", "ch2_refuge_shortcut", "ch2_refuge_record",
			"ch2_line_water", "ch2_line_bell", "ch2_line_light", "ch2_crossing_cleared", "ch2_false_home_revealed",
			"ch2_choir_defeated", "ch2_returned_to_reach", "ch2_homecoming"]:
		GameState.set_flag(f, true)
	GameState.chapter2.evaluate()
	await wait_frames(2)        # the deferred quest evaluation of the flags above
	assert_eq(String(GameState.current_objective()["id"]), "ch2_feast", "only the Lanternwake is left")
	var feast: Dictionary = GameState.chapter2.step_by_id("ch2_feast")
	var step_msg := String((feast.get("on_complete", {}) as Dictionary).get("message", ""))
	assert_ne(step_msg, "", "the final step carries the gifts message")
	var notes: Array = []
	var cb := func(text: String, kind: String) -> void: notes.append([text, kind])
	Events.notify.connect(cb)
	var is_gift := func(n: Array) -> bool: return String(n[0]) == step_msg or String(n[0]).to_lower().contains("gifts")
	var rewards: Dictionary = Game.chapter_two_rewards()
	var before := {}
	for id in rewards:
		before[id] = GameState.count_item(String(id))
	assert_true(await Game.complete_chapter_two(rewards), "completes")
	await wait_frames(3)        # anything deferred after the ending (quest / optional evaluations)
	var gifts: Array = notes.filter(is_gift)
	assert_eq(gifts.size(), 1, "exactly one gifts toast: %s" % str(notes))
	if gifts.size() == 1:
		assert_eq(String(gifts[0][0]), step_msg, "it is the ch2_feast step's message")
	var texts: Array = notes.map(func(n: Array) -> String: return String(n[0]))
	for t in texts:
		assert_eq(texts.count(t), 1, "no toast is shown twice (%s)" % t)
	for id in rewards:
		assert_eq(GameState.count_item(String(id)) - int(before[id]), int(rewards[id]), "reward %s granted once, unchanged" % id)
	assert_true(GameState.has_reward(Game.CH2_REWARD_ID), "one ledger entry")
	assert_true(GameState.chapter2.is_finished(), "the final step completed with the ending")
	# The commit save already lists the final step: a reload (e.g. after a crash during the ending) is quiet.
	notes.clear()
	fresh_state()
	assert_true(SaveSystem.load_game(), "reloaded")
	GameState.active = true
	GameState.chapter2.evaluate()
	await wait_frames(2)
	assert_eq(notes.filter(is_gift).size(), 0, "a reload never announces the gifts again: %s" % str(notes))
	assert_true(GameState.chapter2.is_finished())
	Events.notify.disconnect(cb)


## Continue on an upper storey (R04): outdoor areas validate the saved spot BEFORE BuildingSystem.attach() has
## spawned the house, so the ground under an upper floor won and Krystal woke downstairs. load_area() now
## validates the spot again once the structures stand. Stand-in upper floor: one saved upper_floor tile (a real
## structure record; spawning a saved piece never re-checks its support) in the Haven of the REAL surface.
func test_continue_upstairs_keeps_krystal_on_her_upper_floor() -> void:
	var Terrain: Script = load("res://src/world/surface/terrain.gd")
	var Placement: Script = load("res://src/building/placement.gd")
	var t: RefCounted = Terrain.new()
	t.call("generate")
	var x := -4.0
	var z := 7.0
	var ground: float = float(t.call("height_at", x, z))
	var consts: Dictionary = Placement.get_script_constant_map()
	var floor_origin := Vector3(x, ground + float(consts["LEVEL_HEIGHT"]), z)
	var top: float = floor_origin.y + float(consts["UPPER_TOP"])
	var uid := GameState.add_structure("upper_floor", floor_origin, 0.0, "surface")
	GameState.structures[uid]["data"] = {"level": 1}
	GameState.active = true
	GameState.player["area"] = "surface"
	GameState.player["pos"] = [x, top + 0.02, z]      # what write_to_state() saved while she stood upstairs
	GameState.player["yaw"] = 0.5
	var runner := get_tree().current_scene
	var ph := Node.new()
	ph.name = "Ch2Placeholder"
	get_tree().root.add_child(ph)
	get_tree().current_scene = ph
	Game._transitioning = false
	Game.load_area("surface", "haven_respawn", true)
	var ok := false
	for i in 1500:
		if Game.mode == "playing" and not Game._transitioning and Game.area_id == "surface" \
				and Game.player != null and is_instance_valid(Game.player):
			ok = true
			break
		await get_tree().process_frame
	assert_true(ok, "Continue loaded the Woods")
	if ok:
		await wait_physics(3)
		var spawned: bool = Game.area.find_children("*", "", true, false).any(func(n: Node) -> bool: return n.get("uid") == uid)
		assert_true(spawned, "the saved upper floor was spawned")
		var p: Vector3 = Game.player.global_position
		assert_true(top - ground > 2.5, "the saved spot really is a storey up")
		assert_true(absf(p.y - top) < 0.4, "Krystal is upstairs on her floor (y %.2f; floor top %.2f; ground %.2f)" % [p.y, top, ground])
		assert_true(Vector2(p.x - x, p.z - z).length() < 0.5, "at the saved spot (%s)" % str(p))
		var sp: Variant = GameState.player.get("pos")
		assert_true(sp is Array and absf(float(sp[1]) - top) < 0.4, "GameState keeps the restored spot (%s)" % str(sp))
	# Clean up the loaded Woods, the UI root and the runner scene.
	if Game.ui != null and is_instance_valid(Game.ui):
		Game.ui.queue_free()
	Game.ui = null
	Game._ui_stack.clear()
	Game._transitioning = false
	Game.area = null
	Game.player = null
	Game.area_id = ""
	Game.zone_id = ""
	Game.companion_nodes = {}
	Game.director = null
	var cs := get_tree().current_scene
	if cs != null and cs != runner and is_instance_valid(cs):
		cs.queue_free()
	for n in get_tree().root.get_children():
		if n.name == "Ch2Placeholder" or n.name == "Surface":
			n.queue_free()
	get_tree().current_scene = runner
	GameState.active = false
	if Audio.has_method("stop_all"):
		Audio.stop_all()
	await wait_frames(4)


## Cold-load warm-up (R05): prefetch_area() starts threaded loads of an area's scene and its AREA_WARMUP scripts,
## is idempotent, ignores unknown ids and never waits; finished scripts are collected and kept compiled, the
## scene stays requested until load_area() takes it (every flow test that travels goes through that path).
func test_prefetch_area_is_idempotent_and_never_blocks() -> void:
	assert_eq(Game.prefetch_area("nowhere"), 0, "an unknown area requests nothing")
	var scene := String(Game.AREAS["moonveil_manor"])
	var warm: Array = Game.AREA_WARMUP["moonveil_manor"]
	var t0 := Time.get_ticks_msec()
	Game.prefetch_area("moonveil_manor")
	var ms := Time.get_ticks_msec() - t0
	assert_eq(Game.prefetch_area("moonveil_manor"), 0, "a second call starts nothing new")
	for p in [scene] + warm:
		assert_true(Game.is_prefetching(String(p)) or ResourceLoader.has_cached(String(p)), "%s is loading or loaded" % p)
	assert_true(ms < 1000, "it never waits for the loads (%d ms)" % ms)
	for i in 900:
		Game._collect_warmups()
		if not warm.any(func(p: Variant) -> bool: return Game.is_prefetching(String(p))):
			break
		await get_tree().process_frame
	for p in warm:
		assert_false(Game.is_prefetching(String(p)), "%s collected" % p)
		assert_true(ResourceLoader.has_cached(String(p)), "%s stays compiled" % p)
	# Hand the scene request back the way load_area() does, so nothing stays pending after this test.
	if Game.is_prefetching(scene):
		Game._prefetching.erase(scene)
		var ps: Variant = ResourceLoader.load_threaded_get(scene)
		assert_true(ps is PackedScene, "the prefetched scene is the area's PackedScene")
